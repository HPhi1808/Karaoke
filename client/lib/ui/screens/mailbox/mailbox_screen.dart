import 'package:flutter/material.dart';
import '../../../services/notification_service.dart';
import 'notifications_tab.dart'; // Import file vừa sửa
import 'messages_tap.dart';

class MailboxScreen extends StatefulWidget {
  const MailboxScreen({super.key});

  @override
  State<MailboxScreen> createState() => _MailboxScreenState();
}

class _MailboxScreenState extends State<MailboxScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // GlobalKey để điều khiển
  final GlobalKey<NotificationsTabState> _notificationKey = GlobalKey<NotificationsTabState>();
  final GlobalKey<MessagesTabState> _messagesKey = GlobalKey<MessagesTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Logic xử lý khi ấn vào Tab
  void _onTapTab(int index) {
    if (_tabController.index == index) {
      if (index == 0) {
        debugPrint("🔄 Reloading Notifications Tab...");
        _notificationKey.currentState?.refresh();
      } else if (index == 1) {
        debugPrint("🔄 Reloading Message Tab...");
        _messagesKey.currentState?.refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF00CC);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Hộp thư",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          onTap: _onTapTab,
          labelColor: primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: primaryColor,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 3,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Thông báo"),
                  _buildBadge(NotificationService.instance.getUnreadNotificationsCountStream()),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Nhắn tin"),
                  _buildBadge(NotificationService.instance.getUnreadMessagesCountStream()),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          NotificationsTab(key: _notificationKey),
          MessagesTab(key: _messagesKey),
        ],
      ),
    );
  }

  Widget _buildBadge(Stream<int> stream) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count == 0) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count > 9 ? "9+" : "$count",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}