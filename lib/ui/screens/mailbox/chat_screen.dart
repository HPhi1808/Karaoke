import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/user_model.dart';
import '../../../models/message_model.dart';

class ChatScreen extends StatefulWidget {
  final UserModel targetUser;

  const ChatScreen({super.key, required this.targetUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final _supabase = Supabase.instance.client;
  late final String _myId;

  @override
  void initState() {
    super.initState();
    _myId = _supabase.auth.currentUser!.id;
    _markMessagesAsRead();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leadingWidth: 40,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey[200],
              backgroundImage: (widget.targetUser.avatarUrl != null && widget.targetUser.avatarUrl!.isNotEmpty)
                  ? NetworkImage(widget.targetUser.avatarUrl!)
                  : null,
              child: (widget.targetUser.avatarUrl == null || widget.targetUser.avatarUrl!.isEmpty)
                  ? Text(
                      widget.targetUser.fullName?[0].toUpperCase() ?? "?",
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
                    widget.targetUser.fullName ?? "Người dùng",
                    style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    "Đang hoạt động",
                    style: TextStyle(color: Colors.green, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black54),
            onPressed: () {},
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
