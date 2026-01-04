import 'package:flutter/material.dart';
import '../../models/notification_model.dart';
import '../screens/mailbox/system_messages_screen.dart';

class SystemNotificationTile extends StatelessWidget {
  final NotificationModel? notification;

  const SystemNotificationTile({Key? key, this.notification}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Nếu không có thông báo nào thì ẩn luôn
    if (notification == null) return const SizedBox.shrink();

    return InkWell(
      onTap: () {
        // CHỈ CHUYỂN TRANG, KHÔNG GỌI API Ở ĐÂY
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SystemMessagesScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // Logic màu nền cũ vẫn giữ để báo hiệu ở ngoài
        color: notification!.isRead ? Colors.white : const Color(0xFFFFF0F5),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF00CC).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.campaign, color: Color(0xFFFF00CC), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Thông báo hệ thống",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      // Chấm đỏ
                      if (!notification!.isRead)
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${notification!.title}: ${notification!.message}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: notification!.isRead ? Colors.black87 : Colors.grey[600],
                      fontSize: 13,
                      fontWeight: notification!.isRead ? FontWeight.normal : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
            ),
          ],
        ),
      ),
    );
  }
}