import 'package:flutter/material.dart';
import '../../models/message_model.dart';

class ChatItem extends StatelessWidget {
  final ChatPreviewModel chat;
  final VoidCallback onTap;
  final Function(String partnerId) onDeleteChat;
  final Function(String partnerId) onBlockUser;

  const ChatItem({
    super.key,
    required this.chat,
    required this.onTap,
    required this.onDeleteChat,
    required this.onBlockUser,
  });

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    final now = DateTime.now();
    final diff = now.difference(localTime);
    if (diff.inDays > 0) {
      return "${localTime.day}/${localTime.month}";
    }

    if (diff.inHours > 0) {
      return "${diff.inHours} giờ trước";
    }
    if (diff.inMinutes > 0) {
      return "${diff.inMinutes} phút trước";
    }
    return "Vừa xong";
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text("Xoá cuộc trò chuyện", style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(ctx);
              onDeleteChat(chat.partnerId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.grey),
            title: const Text("Chặn người dùng"),
            onTap: () {
              Navigator.pop(ctx);
              onBlockUser(chat.partnerId);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool hasUnread = chat.unreadCount > 0;

    return ListTile(
      onTap: onTap,
      onLongPress: () => _showOptions(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey[200],
        backgroundImage: (chat.avatarUrl != null && chat.avatarUrl!.isNotEmpty)
            ? NetworkImage(chat.avatarUrl!)
            : null,
        child: (chat.avatarUrl == null || chat.avatarUrl!.isEmpty)
            ? Text(chat.fullName.isNotEmpty ? chat.fullName[0].toUpperCase() : "?")
            : null,
      ),
      title: Text(
        chat.fullName,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600, 
          fontSize: 16,
          color: hasUnread ? Colors.black : Colors.black87,
        ),
      ),
      subtitle: Text(
        chat.lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: hasUnread ? Colors.black : Colors.grey[600],
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatTime(chat.lastMessageTime),
            style: TextStyle(
              color: hasUnread ? Colors.red : Colors.grey[500],
              fontSize: 11,
              fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (hasUnread) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red, // Màu đỏ chuẩn như ảnh bạn gửi
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Text(
                chat.unreadCount > 9 ? "9+" : "${chat.unreadCount}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}