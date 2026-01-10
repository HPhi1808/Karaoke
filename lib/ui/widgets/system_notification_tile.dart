import 'package:flutter/material.dart';
import '../../models/notification_model.dart';
import '../screens/mailbox/system_messages_screen.dart';

class SystemNotificationTile extends StatelessWidget {
  final NotificationModel? notification;
  final VoidCallback? onRefresh;

  const SystemNotificationTile({super.key, this.notification, this.onRefresh});

  // Helper: Lấy cấu hình giao diện dựa trên type
  _SystemStyle _getStyle() {
    final type = (notification?.type ?? '').trim().toLowerCase();

    switch (type) {
      case 'warning':
        return _SystemStyle(
          icon: Icons.warning_amber_rounded,
          color: Colors.red,
          bgColor: Colors.red.withValues(alpha: 0.1),
          title: "Cảnh báo vi phạm",
        );
      case 'success':
        return _SystemStyle(
          icon: Icons.card_giftcard,
          color: Colors.green,
          bgColor: Colors.green.withValues(alpha: 0.1),
          title: "Quà tặng & Khuyến mãi",
        );
      case 'info':
        return _SystemStyle(
          icon: Icons.info_outline,
          color: Colors.blue,
          bgColor: Colors.blue.withValues(alpha: 0.1),
          title: "Thông tin hệ thống",
        );
      default: // Mặc định là Broadcast (system)
        return _SystemStyle(
          icon: Icons.campaign_rounded,
          color: const Color(0xFFFF00CC),
          bgColor: const Color(0xFFFF00CC).withValues(alpha: 0.1),
          title: "Thông báo hệ thống",
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (notification == null) return const SizedBox.shrink();

    final style = _getStyle();
    final bool isUnread = !notification!.isRead;

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SystemMessagesScreen()),
        );
        if (onRefresh != null) {
          onRefresh!();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isUnread ? style.bgColor.withValues(alpha: 0.05) : Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
            left: isUnread ? BorderSide(color: style.color, width: 4) : BorderSide.none,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon Circle
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: style.bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(style.icon, color: style.color, size: 22),
            ),
            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        style.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: style.color,
                        ),
                      ),
                      Text(
                        _formatShortTime(notification!.createdAt),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${notification!.title}: ${notification!.message}",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isUnread ? Colors.black87 : Colors.grey[600],
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
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

  String _formatShortTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return "${diff.inMinutes}p";
    if (diff.inHours < 24) return "${diff.inHours}h";
    return "${time.day}/${time.month}";
  }
}

class _SystemStyle {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String title;

  _SystemStyle({required this.icon, required this.color, required this.bgColor, required this.title});
}