// lib/ui/screens/mailbox/tabs/notifications_tab.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/notification_model.dart';
import '../../widgets/notification_item.dart';
import '../../widgets/system_notification_tile.dart';

class NotificationsTab extends StatefulWidget {
  const NotificationsTab({Key? key}) : super(key: key);

  @override
  State<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<NotificationsTab> {
  final _supabase = Supabase.instance.client;

  // State chứa dữ liệu
  List<NotificationModel> _notifications = [];
  NotificationModel? _latestSystemNotification;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    _setupRealtimeSubscription();
  }

  // Hàm lấy dữ liệu từ VIEW
  Future<void> _fetchNotifications() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Gọi vào View all_notifications_view
      final List<dynamic> response = await _supabase
          .from('all_notifications_view')
          .select()
          .order('created_at', ascending: false); // Mới nhất lên đầu

      final allData = response.map((json) => NotificationModel.fromJson(json)).toList();

      if (mounted) {
        setState(() {
          // Lọc ra thông báo hệ thống mới nhất
          // (Dùng firstWhereOrNull nếu có thư viện collection, đây dùng logic thủ công)
          try {
            _latestSystemNotification = allData.firstWhere(
                  (element) => element.category == 'system',
            );
          } catch (e) {
            _latestSystemNotification = null;
          }

          // Lọc ra thông báo cá nhân (loại bỏ system khỏi list dưới)
          _notifications = allData.where((element) => element.category == 'personal').toList();

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải thông báo: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Hàm lắng nghe Realtime
  void _setupRealtimeSubscription() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Kênh lắng nghe thay đổi
    _supabase.channel('public:notifications_tab')
    // 1. Lắng nghe bảng notifications (Của user hiện tại)
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        debugPrint("Có thông báo cá nhân mới!");
        _fetchNotifications(); // Tải lại toàn bộ view
      },
    )
    // 2. Lắng nghe bảng system_notifications (Toàn bộ)
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'system_notifications',
      callback: (payload) {
        debugPrint("Có thông báo hệ thống mới!");
        _fetchNotifications();
      },
    )
    // 3. Lắng nghe bảng system_read_status (Để cập nhật trạng thái đã đọc của system)
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'system_read_status',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        _fetchNotifications();
      },
    )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Nếu không có gì cả
    if (_notifications.isEmpty && _latestSystemNotification == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text("Chưa có thông báo nào", style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchNotifications,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // --- PHẦN 1: THÔNG BÁO HỆ THỐNG ---
          if (_latestSystemNotification != null) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text("Quan trọng", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            SystemNotificationTile(notification: _latestSystemNotification),
            const Divider(height: 30, thickness: 1),
          ],

          // --- PHẦN 2: HOẠT ĐỘNG CÁ NHÂN ---
          if (_notifications.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text("Mới nhất", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            // Map danh sách ra Widget
            ..._notifications.map((noti) => NotificationItem(notification: noti)).toList(),
          ]
        ],
      ),
    );
  }
}