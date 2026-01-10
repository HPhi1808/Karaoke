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

  // Hàm hiện BottomSheet khi bấm giữ
  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text("Xoá cuộc trò chuyện", style: TextStyle(color: Colors.red)),
            subtitle: const Text("Cuộc trò chuyện sẽ bị ẩn cho đến khi có tin nhắn mới."),
            onTap: () {
              Navigator.pop(ctx);
              onDeleteChat(chat.partnerId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.grey),
            title: const Text("Chặn người dùng"),
            subtitle: const Text("Họ sẽ không thể nhắn tin cho bạn nữa."),
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
    return ListTile(
      onTap: onTap,
      onLongPress: () => _showOptions(context),
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
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      subtitle: Text(
        chat.lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.grey[600],
          fontWeight: (chat.isRead == false) ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: Text(
        _formatTime(chat.lastMessageTime),
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
      ),
    );
  }
}