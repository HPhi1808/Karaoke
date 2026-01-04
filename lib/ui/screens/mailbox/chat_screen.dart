import 'package:flutter/material.dart';
import '../../../models/user_model.dart';

class ChatScreen extends StatefulWidget {
  final UserModel targetUser;

  const ChatScreen({Key? key, required this.targetUser}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();

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
            // Avatar nhỏ trên AppBar
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey[200],
              backgroundImage: (widget.targetUser.avatarUrl != null && widget.targetUser.avatarUrl!.isNotEmpty)
                  ? NetworkImage(widget.targetUser.avatarUrl!)
                  : null,
              child: (widget.targetUser.avatarUrl == null || widget.targetUser.avatarUrl!.isEmpty)
                  ? Text(
                (widget.targetUser.fullName?.isNotEmpty == true)
                    ? widget.targetUser.fullName![0].toUpperCase()
                    : "?",
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              )
                  : null,
            ),
            const SizedBox(width: 10),
            // Tên và trạng thái
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.targetUser.fullName ?? "Người dùng",
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.bold
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    "Đang hoạt động",
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.call, color: Color(0xFFFF00CC))),
          IconButton(onPressed: () {}, icon: const Icon(Icons.videocam, color: Color(0xFFFF00CC))),
        ],
      ),
      body: Column(
        children: [
          // Phần hiển thị nội dung chat
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    "Bắt đầu cuộc trò chuyện với\n${widget.targetUser.fullName}",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),

          // Thanh nhập tin nhắn
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                )
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.add_circle, color: Colors.grey[400]),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: "Nhập tin nhắn...",
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.send, color: Color(0xFFFF00CC)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}