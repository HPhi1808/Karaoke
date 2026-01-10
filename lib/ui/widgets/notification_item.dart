import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/notification_model.dart';

class NotificationItem extends StatelessWidget {
  final NotificationModel notification;

  const NotificationItem({super.key, required this.notification});

  Future<void> _markAsRead() async {
    if (notification.isRead) return;
    try {
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
    final bool isUnread = !notification.isRead;

    return InkWell(
      onTap: () {
        _markAsRead();
        // TODO: Navigate logic
      },
      child: Container(
        color: isUnread ? const Color(0xFFF0F7FF) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildAvatarStack(),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.4,
                        fontFamily: 'Roboto',
                      ),
                      children: [
                        TextSpan(
                          text: notification.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text: " ${notification.message}",
                          style: TextStyle(
                            color: isUnread ? Colors.black87 : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(notification.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: isUnread ? const Color(0xFFFF00CC) : Colors.grey[500],
                      fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (isUnread)
              Container(
                margin: const EdgeInsets.only(left: 8),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF00CC),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarStack() {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade200),
                color: Colors.grey.shade100,
              ),
              child: ClipOval(
                // Placeholder Avatar đẹp hơn
                child: Icon(Icons.person, color: Colors.grey.shade400, size: 30),
                // Sau này thay bằng: Image.network(avatarUrl, fit: BoxFit.cover)
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: _getIconColor(),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)
                  ]
              ),
              child: Icon(_getIconData(), size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconData() {
    final type = (notification.type ?? '').toLowerCase();
    switch (type) {
      case 'like': return Icons.favorite_rounded;
      case 'comment': return Icons.chat_bubble_rounded;
      case 'follow': return Icons.person_add_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _getIconColor() {
    final type = (notification.type ?? '').toLowerCase();
    switch (type) {
      case 'like': return const Color(0xFFFF4D4F);
      case 'comment': return const Color(0xFF1890FF);
      case 'follow': return const Color(0xFFFF00CC);
      default: return Colors.grey;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) return "Vừa xong";
    if (diff.inMinutes < 60) return "${diff.inMinutes} phút trước";
    if (diff.inHours < 24) return "${diff.inHours} giờ trước";
    if (diff.inDays < 7) return "${diff.inDays} ngày trước";
    return "${time.day}/${time.month}/${time.year}";
  }
}