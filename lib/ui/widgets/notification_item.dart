import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/notification_model.dart';

class NotificationItem extends StatelessWidget {
  final NotificationModel notification;

  const NotificationItem({Key? key, required this.notification}) : super(key: key);

  Future<void> _markAsRead() async {
    if (notification.isRead) return;
    try {
      // Update bảng notifications (cho personal)
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notification.id);
    } catch (e) {
      debugPrint("Lỗi mark read personal: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        _markAsRead();
        // TODO: Điều hướng tùy theo type (ví dụ: vào bài hát, vào trang cá nhân user)
      },
      child: Container(
        color: notification.isRead ? Colors.white : const Color(0xFFFFF0F5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatarStack(),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(
                          text: notification.title, // Tên user (ví dụ: "Nam")
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                            text: " ${notification.message}", // Nội dung (ví dụ: "đã like bài hát")
                            style: TextStyle(
                                fontWeight: notification.isRead ? FontWeight.normal : FontWeight.w500
                            )
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(notification.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: notification.isRead ? Colors.grey[500] : const Color(0xFFFF00CC),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarStack() {
    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        children: [
          const Positioned.fill(
            child: CircleAvatar(
              backgroundColor: Colors.grey,
              // Tạm thời dùng icon mặc định, sau này bạn join bảng users để lấy avatar_url
              child: Icon(Icons.person, color: Colors.white),
            ),
          ),
          Positioned(
            right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _getIconColor(),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(_getIconData(), size: 10, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconData() {
    switch (notification.type) {
      case 'like': return Icons.favorite;
      case 'comment': return Icons.chat_bubble;
      case 'follow': return Icons.person_add;
      default: return Icons.notifications;
    }
  }

  Color _getIconColor() {
    switch (notification.type) {
      case 'like': return Colors.redAccent;
      case 'comment': return Colors.blueAccent;
      case 'follow': return const Color(0xFFFF00CC);
      default: return Colors.grey;
    }
  }

  String _formatTime(DateTime time) {
    // Hàm format thời gian đơn giản
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 60) return "${diff.inMinutes} phút trước";
    if (diff.inHours < 24) return "${diff.inHours} giờ trước";
    return "${time.day}/${time.month}";
  }
}