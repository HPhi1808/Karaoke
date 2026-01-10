import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/user_model.dart';
import '../../../models/message_model.dart';
import '../../../services/notification_service.dart';
import '../me/user_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final UserModel targetUser;

  const ChatScreen({super.key, required this.targetUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final _supabase = Supabase.instance.client;
  late final String _myId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _myId = _supabase.auth.currentUser!.id;
    _updateChatStatus(widget.targetUser.id);
    _markMessagesAsRead();
  }

  @override
  void dispose() {
    _updateChatStatus(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _markMessagesAsRead() async {
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('sender_id', widget.targetUser.id)
          .eq('receiver_id', _myId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint("Lỗi cập nhật đã đọc: $e");
    }
  }

  // Hàm lắng nghe khi người dùng bấm nút Home (ẩn app)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateChatStatus(widget.targetUser.id);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _updateChatStatus(null);
    }
  }

  Future<void> _updateChatStatus(String? partnerId) async {
    try {
      await _supabase.from('user_chat_status').upsert({
        'user_id': _myId,
        'current_partner_id': partnerId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint("Lỗi cập nhật trạng thái chat: $e");
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();

    try {
      final newMessage = MessageModel(
        senderId: _myId,
        receiverId: widget.targetUser.id,
        content: text,
      );
      await _supabase.from('messages').insert(newMessage.toJson());

      final statusData = await _supabase
          .from('user_chat_status')
          .select('current_partner_id')
          .eq('user_id', widget.targetUser.id)
          .maybeSingle();

      final String? chattingWithId = statusData?['current_partner_id'];
      if (chattingWithId != _myId) {
        NotificationService.instance.sendChatNotification(
          receiverId: widget.targetUser.id,
          content: text,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lỗi gửi tin nhắn: $e")),
        );
      }
    }
  }

  Stream<List<MessageModel>> _getChatStream() {
    return _supabase
        .from('messages')
        .stream(primaryKey: ['message_id'])
        .order('sent_at', ascending: false)
        .map((data) {
      final messages = data
          .map((json) => MessageModel.fromJson(json))
          .where((msg) =>
              (msg.senderId == _myId && msg.receiverId == widget.targetUser.id) ||
              (msg.senderId == widget.targetUser.id && msg.receiverId == _myId))
          .toList();
      
      if (messages.isNotEmpty && messages.first.receiverId == _myId && !messages.first.isRead) {
        _markMessagesAsRead();
      }
      
      return messages;
    });
  }

  // Xem hồ sơ
  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(user: widget.targetUser),
      ),
    );
  }

  // Xử lý Xoá cuộc trò chuyện
  Future<void> _confirmDeleteChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xoá cuộc trò chuyện?"),
        content: const Text("Cuộc trò chuyện này sẽ bị ẩn khỏi danh sách của bạn."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Huỷ"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Xoá", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('deleted_conversations').upsert(
          {
            'user_id': _myId,
            'partner_id': widget.targetUser.id,
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'user_id, partner_id',
        );

        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        debugPrint("Lỗi xoá chat: $e");
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi kết nối!")));
      }
    }
  }

  // Xử lý Chặn người dùng
  Future<void> _confirmBlockUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Chặn người dùng này?"),
        content: const Text("Họ sẽ không thể nhắn tin cho bạn nữa và cuộc trò chuyện sẽ bị ẩn."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Huỷ"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Chặn", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Thêm vào bảng blocked_users
        await _supabase.from('blocked_users').insert({
          'blocker_id': _myId,
          'blocked_id': widget.targetUser.id,
        });

        // Ẩn luôn cuộc trò chuyện (Soft delete)
        await _supabase.from('deleted_conversations').upsert({
          'user_id': _myId,
          'partner_id': widget.targetUser.id,
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id, partner_id');

        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Đã chặn người dùng")),
          );
        }
      } catch (e) {
        debugPrint("Lỗi chặn: $e");
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi chặn người dùng!")));
      }
    }
  }

  // Hàm định dạng trạng thái hoạt động
  String _getStatusText(String? lastActiveAtStr) {
    if (lastActiveAtStr == null) return "Offline";

    // 1. Chuyển đổi thời gian từ DB (UTC) sang DateTime
    final lastActive = DateTime.parse(lastActiveAtStr).toLocal();
    final now = DateTime.now();

    // 2. Tính khoảng cách thời gian
    final difference = now.difference(lastActive);
    final minutes = difference.inMinutes;

    // 3. Logic hiển thị
    if (minutes <= 6) {
      return "Đang hoạt động";
    } else if (minutes < 60) {
      return "Hoạt động $minutes phút trước";
    } else if (minutes < 1440) {
      final hours = difference.inHours;
      return "Hoạt động $hours giờ trước";
    } else {
      return "Hoạt động ${lastActive.day.toString().padLeft(2, '0')}/${lastActive.month.toString().padLeft(2, '0')}";
    }
  }

  // Hàm lấy màu sắc cho trạng thái
  Color _getStatusColor(String? lastActiveAtStr) {
    if (lastActiveAtStr == null) return Colors.grey;

    final lastActive = DateTime.parse(lastActiveAtStr).toLocal();
    final difference = DateTime.now().difference(lastActive);

    return difference.inMinutes <= 6 ? Colors.green : Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leadingWidth: 40,
        iconTheme: const IconThemeData(color: Colors.black),
        title: StreamBuilder<List<Map<String, dynamic>>>(
          // Lắng nghe thay đổi của user mục tiêu trong bảng 'users'
          stream: _supabase
              .from('users')
              .stream(primaryKey: ['id'])
              .eq('id', widget.targetUser.id),
          builder: (context, snapshot) {
            // 1. Lấy dữ liệu mới nhất (nếu có stream), nếu không thì dùng dữ liệu cũ từ widget.targetUser
            String? avatarUrl = widget.targetUser.avatarUrl;
            String fullName = widget.targetUser.fullName ?? "Người dùng";
            String? lastActiveAt;

            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              final userData = snapshot.data!.first;
              avatarUrl = userData['avatar_url']; // Cập nhật avatar nếu họ đổi
              fullName = userData['full_name'] ?? "Người dùng";
              lastActiveAt = userData['last_active_at']; // Cột thời gian quan trọng
            }

            // 2. Tính toán trạng thái hiển thị
            final statusText = _getStatusText(lastActiveAt);
            final statusColor = _getStatusColor(lastActiveAt);

            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: (avatarUrl == null || avatarUrl.isEmpty)
                      ? Text(
                    fullName.isNotEmpty ? fullName[0].toUpperCase() : "?",
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        statusText,
                        style: TextStyle(color: statusColor, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black54),
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  _navigateToProfile();
                  break;
                case 'delete':
                  _confirmDeleteChat();
                  break;
                case 'block':
                  _confirmBlockUser();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, color: Colors.blueGrey, size: 20),
                    SizedBox(width: 10),
                    Text('Xem hồ sơ'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red, size: 20),
                    SizedBox(width: 10),
                    Text('Xoá cuộc trò chuyện', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.grey, size: 20),
                    SizedBox(width: 10),
                    Text('Chặn người này'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _getChatStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final messages = snapshot.data!;
                
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == _myId;
                    
                    final bool isLatestFromMe = isMe && index == 0;
                    final bool showSeen = isLatestFromMe && msg.isRead;
                    final bool showSent = isLatestFromMe && !msg.isRead;

                    return _buildMessageBubble(msg, isMe, showSeen, showSent);
                  },
                );
              },
            ),
          ),
          
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: "Nhập tin nhắn...",
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFFFF00CC)),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel msg, bool isMe, bool showSeen, bool showSent) {
    final localTime = msg.sentAt?.toLocal();
    final String timeStr = localTime != null 
        ? "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}"
        : "";

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFFFF00CC) : Colors.grey[200],
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 0),
                    bottomRight: Radius.circular(isMe ? 0 : 16),
                  ),
                ),
                child: Text(
                  msg.content,
                  style: TextStyle(
                    color: isMe ? Colors.white : Colors.black87,
                    fontSize: 15,
                  ),
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 6),
                Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ],
          ),
          if (showSeen || showSent)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Text(
                showSeen ? "Đã xem" : "Đã gửi",
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
