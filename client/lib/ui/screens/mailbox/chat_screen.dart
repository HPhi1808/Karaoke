import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../../models/user_model.dart';
import '../../../models/message_model.dart';
import '../../../services/chat_service.dart';
import '../../../services/user_service.dart';
import '../me/user_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final UserModel targetUser;

  const ChatScreen({super.key, required this.targetUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _statusChannel;
  final _supabase = Supabase.instance.client;
  late final String _myId;
  bool _blockedByMe = false;
  bool _blockedByThem = false;
  bool _isTargetLocked = false;
  bool _isLoadingStatus = true;

  List<MessageModel> _messages = [];
  StreamSubscription<List<MessageModel>>? _messagesSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _myId = _supabase.auth.currentUser!.id;

    _checkStatuses();
    ChatService.instance.updateChatStatus(_myId, widget.targetUser.id);
    _subscribeToMessages();
    _subscribeToReadStatus();
  }

  @override
  void dispose() {
    ChatService.instance.updateChatStatus(_myId, null);
    WidgetsBinding.instance.removeObserver(this);
    _messagesSubscription?.cancel();
    if (_statusChannel != null) _supabase.removeChannel(_statusChannel!);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottomInset = WidgetsBinding.instance.window.viewInsets.bottom;
    if (bottomInset > 0.0) {
      _scrollToBottom();
    }
  }

  Future<void> _checkStatuses() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    final results = await Future.wait([
      UserService.instance.checkBlockStatus(myId, widget.targetUser.id),
      ChatService.instance.checkUserLockStatus(widget.targetUser.id),
    ]);

    final blockStatus = results[0] as BlockStatus;
    final isLocked = results[1] as bool;

    if (mounted) {
      setState(() {
        _blockedByMe = blockStatus.blockedByMe;
        _blockedByThem = blockStatus.blockedByThem;
        _isTargetLocked = isLocked;
        _isLoadingStatus = false;
      });
    }
  }

  void _subscribeToReadStatus() {
    _statusChannel = _supabase.channel('chat_status_${widget.targetUser.id}')
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'sender_id',
        value: _myId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord['receiver_id'] == widget.targetUser.id) {
          final updatedId = newRecord['message_id'];
          final isRead = newRecord['is_read'];
          if (mounted) {
            setState(() {
              final index = _messages.indexWhere((m) => m.messageId == updatedId);
              if (index != -1) {
                _messages[index] = _messages[index].copyWith(isRead: true);
              }
            });
          }
        }
      },
    )
        .subscribe();
  }

  // --- LOGIC MESSAGES ---

  // Lắng nghe tin nhắn từ Server
  void _subscribeToMessages() {
    _messagesSubscription = _supabase
        .from('messages')
        .stream(primaryKey: ['message_id'])
        .order('sent_at', ascending: false)
        .limit(100)
        .map((data) {
      return data
          .map((json) => MessageModel.fromJson(json))
          .where((msg) =>
      (msg.senderId == _myId && msg.receiverId == widget.targetUser.id) ||
          (msg.senderId == widget.targetUser.id && msg.receiverId == _myId))
          .toList();
    })
        .listen((remoteMessages) {
      if (mounted) {
        setState(() {
          _messages = remoteMessages;

          if (_messages.isNotEmpty && _messages.first.receiverId == _myId && !_messages.first.isRead) {
            ChatService.instance.markAsRead(myId: _myId, partnerId: widget.targetUser.id);
          }
        });
      }
    });
  }

  // Gửi tin nhắn
  Future<void> _sendMessage() async {
    if (_blockedByMe || _blockedByThem || _isTargetLocked) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final tempId = DateTime.now().millisecondsSinceEpoch;
    final newMessage = MessageModel(
      messageId: tempId,
      senderId: _myId,
      receiverId: widget.targetUser.id,
      content: text,
      sentAt: DateTime.now(),
      isRead: false,
    );

    setState(() {
      _messages.insert(0, newMessage);
      _messageController.clear();
    });
    _scrollToBottom();

    try {
      await ChatService.instance.sendMessage(
          myId: _myId,
          targetId: widget.targetUser.id,
          content: text
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.messageId == tempId);
          _messageController.text = text;
        });
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _handleUnblock() async {
    try {
      await UserService.instance.unblockUser(_myId, widget.targetUser.id);
      setState(() {
        _blockedByMe = false;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã bỏ chặn người dùng')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi kết nối!")));
    }
  }

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

  void _navigateToProfile() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => UserProfileScreen(user: widget.targetUser)));
  }

  Future<void> _confirmDeleteChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xoá cuộc trò chuyện?"),
        content: const Text("Cuộc trò chuyện này sẽ bị ẩn khỏi danh sách của bạn."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Huỷ")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Xoá", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ChatService.instance.deleteConversation(_myId, widget.targetUser.id);
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi kết nối!")));
      }
    }
  }

  Future<void> _confirmBlockUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Chặn người dùng này?"),
        content: const Text("Họ sẽ không thể nhắn tin cho bạn nữa và cuộc trò chuyện sẽ bị ẩn."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Huỷ")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Chặn", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await UserService.instance.blockUser(_myId, widget.targetUser.id);
        setState(() => _blockedByMe = true);
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã chặn người dùng")));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi chặn người dùng!")));
      }
    }
  }

  String _getStatusText(String? lastActiveAtStr) {
    if (lastActiveAtStr == null) return "Offline";
    final lastActive = DateTime.parse(lastActiveAtStr).toLocal();
    final now = DateTime.now();
    final difference = now.difference(lastActive);
    final minutes = difference.inMinutes;

    if (minutes <= 6) return "Đang hoạt động";
    if (minutes < 60) return "Hoạt động $minutes phút trước";
    if (minutes < 1440) return "Hoạt động ${difference.inHours} giờ trước";
    return "Hoạt động ${lastActive.day.toString().padLeft(2, '0')}/${lastActive.month.toString().padLeft(2, '0')}";
  }

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
          stream: _supabase
              .from('users')
              .stream(primaryKey: ['id'])
              .eq('id', widget.targetUser.id),
          builder: (context, snapshot) {
            String? avatarUrl = widget.targetUser.avatarUrl;
            String fullName = widget.targetUser.fullName ?? "Người dùng";
            String? lastActiveAt;

            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              final userData = snapshot.data!.first;
              avatarUrl = userData['avatar_url'];
              fullName = userData['full_name'] ?? "Người dùng";
              lastActiveAt = userData['last_active_at'];
            }

            final bool isBlockedAny = _blockedByMe || _blockedByThem;
            final statusText = (isBlockedAny || _isTargetLocked) ? "" : _getStatusText(lastActiveAt);
            final statusColor = _getStatusColor(lastActiveAt);

            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: (!_isTargetLocked && avatarUrl != null && avatarUrl.isNotEmpty)
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: (_isTargetLocked || avatarUrl == null || avatarUrl.isEmpty)
                      ? Icon(Icons.person, size: 20, color: Colors.grey.shade400) // Avatar trắng nếu khóa
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
                      if (statusText.isNotEmpty)
                        Text(statusText, style: TextStyle(color: statusColor, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          if (!_blockedByMe && !_isTargetLocked)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black54),
              onSelected: (value) {
                switch (value) {
                  case 'profile': _navigateToProfile(); break;
                  case 'delete': _confirmDeleteChat(); break;
                  case 'block': _confirmBlockUser(); break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'profile', child: Row(children: [Icon(Icons.person, color: Colors.blueGrey, size: 20), SizedBox(width: 10), Text('Xem hồ sơ')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 20), SizedBox(width: 10), Text('Xoá cuộc trò chuyện', style: TextStyle(color: Colors.red))])),
                const PopupMenuItem(value: 'block', child: Row(children: [Icon(Icons.block, color: Colors.grey, size: 20), SizedBox(width: 10), Text('Chặn người này')])),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text("Chưa có tin nhắn nào", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
              controller: _scrollController,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg.senderId == _myId;
                final bool isLatestFromMe = isMe && index == 0;
                final bool showSeen = isLatestFromMe && msg.isRead;
                final bool showSent = isLatestFromMe && !msg.isRead;
                return _buildMessageBubble(msg, isMe, showSeen, showSent);
              },
            ),
          ),

          // --- LOGIC HIỂN THỊ PHẦN BOTTOM ---
          if (_isLoadingStatus)
            const SizedBox(height: 50, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
          else if (_blockedByMe)
            _buildUnblockArea()
          else if (_blockedByThem)
              _buildBlockedNotice()
            else if (_isTargetLocked)
                _buildLockedAccountNotice()
              else
                _buildMessageInputArea(),
        ],
      ),
    );
  }

  //  Widget thông báo tài khoản bị khóa
  Widget _buildLockedAccountNotice() {
    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border(top: BorderSide(color: Colors.red.shade100)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, color: Colors.red.shade400, size: 24),
          const SizedBox(height: 8),
          Text(
            "Tài khoản này đang bị tạm khoá",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red.shade400, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInputArea() {
    return Container(
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
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
    );
  }

  Widget _buildUnblockArea() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Bạn đã chặn người dùng này.", style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _handleUnblock,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10)),
            child: const Text("Bỏ chặn"),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedNotice() {
    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.grey[100], border: Border(top: BorderSide(color: Colors.grey[300]!))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block, color: Colors.grey, size: 24),
          const SizedBox(height: 8),
          Text("Bạn không thể nhắn tin cho người dùng này.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel msg, bool isMe, bool showSeen, bool showSent) {
    final localTime = msg.sentAt?.toLocal();
    final String timeStr = localTime != null ? "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}" : "";

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)), const SizedBox(width: 6)],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFFFF00CC) : Colors.grey[200],
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 0), bottomRight: Radius.circular(isMe ? 0 : 16),
                  ),
                ),
                child: Text(msg.content, style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 15)),
              ),
              if (isMe) ...[const SizedBox(width: 6), Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey))],
            ],
          ),
          if (showSeen || showSent)
            Padding(padding: const EdgeInsets.only(top: 4, right: 4), child: Text(showSeen ? "Đã xem" : "Đã gửi", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}