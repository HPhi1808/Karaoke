import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shimmer/shimmer.dart';
import '../../../models/notification_model.dart';
import '../../widgets/notification_item.dart';
import '../../widgets/system_notification_tile.dart';
import '../../../services/base_service.dart';
import '../../../services/auth_service.dart';

class NotificationsTab extends StatefulWidget {
  const NotificationsTab({super.key});

  @override
  State<NotificationsTab> createState() => NotificationsTabState();
}

class NotificationsTabState extends State<NotificationsTab> {
  final _supabase = Supabase.instance.client;
  final _baseService = BaseService();

  List<NotificationModel> _notifications = [];
  NotificationModel? _latestSystemNotification;
  bool _isLoading = true;
  bool _isGuest = false;

  @override
  void initState() {
    super.initState();
    _isGuest = AuthService.instance.isGuest;
    _fetchNotifications();
    _setupRealtimeSubscription();
  }

  // Hàm lấy dữ liệu từ VIEW
  Future<void> _fetchNotifications() async {
    try {
      final user = _supabase.auth.currentUser;
      final userId = user?.id;

      if (!_isGuest && userId == null) return;

      final List<dynamic> response = await _baseService.safeExecution(() async {
        if (_isGuest) {
          final String userCreatedAt = user!.createdAt;
          return await _supabase
              .from('system_notifications')
              .select()
              .gte('created_at', userCreatedAt)
              .order('created_at', ascending: false)
              .limit(1);
        } else {
          final String userCreatedAt = user!.createdAt;
          return await _supabase
              .from('all_notifications_view')
              .select()
              .gte('created_at', userCreatedAt)
              .order('updated_at', ascending: false);
        }
      });

      final allData = response.map((json) => NotificationModel.fromJson(json)).toList();

      if (mounted) {
        setState(() {
          if (_isGuest) {
            _latestSystemNotification = allData.isNotEmpty ? allData.first : null;
            _notifications = [];
          } else {
            bool isSystemOrAdminMsg(NotificationModel n) {
              if (n.category == 'system') return true;
              final type = (n.type).trim().toLowerCase();
              return ['warning', 'info', 'success'].contains(type);
            }

            final systemList = allData.where((e) => isSystemOrAdminMsg(e)).toList();
            _latestSystemNotification = systemList.isNotEmpty ? systemList.first : null;
            _notifications = allData.where((e) => !isSystemOrAdminMsg(e)).toList();
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải thông báo: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> refresh() async {
    // _scrollController.animateTo(0, ...);

    setState(() => _isLoading = true);
    await _fetchNotifications();
  }

  // Hàm lắng nghe Realtime
  void _setupRealtimeSubscription() {
    final userId = _supabase.auth.currentUser?.id;
    final channel = _supabase.channel('public:notifications_tab');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'system_notifications',
      callback: (payload) => _fetchNotifications(),
    );

    if (!_isGuest && userId != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) => _fetchNotifications(),
      ).onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'system_read_status',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) => _fetchNotifications(),
      );
    }
    channel.subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _isLoading = true);
          await _fetchNotifications();
        },
        color: const Color(0xFFFF00CC),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildSkeletonList();
    }

    if (_notifications.isEmpty && _latestSystemNotification == null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Container(
              height: constraints.maxHeight,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text("Chưa có thông báo nào", style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 10),
                  TextButton.icon(
                      onPressed: () {
                        setState(() => _isLoading = true);
                        _fetchNotifications();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text("Tải lại")
                  )
                ],
              ),
            ),
          );
        },
      );
    }

    // Trạng thái có dữ liệu -> Hiện List thật
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // --- PHẦN 1: THÔNG BÁO HỆ THỐNG ---
        if (_latestSystemNotification != null) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text("Quan trọng", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          SystemNotificationTile(
            notification: _latestSystemNotification,
            onRefresh: _fetchNotifications,
          ),
          if (_notifications.isNotEmpty) const Divider(height: 30, thickness: 1),
        ],

        // --- PHẦN 2: HOẠT ĐỘNG CÁ NHÂN ---
        if (_notifications.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text("Mới nhất", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ..._notifications.map((noti) => NotificationItem(notification: noti)),
        ]
      ],
    );
  }

  // ================= SKELETON WIDGET =================
  Widget _buildSkeletonList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: 10,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(radius: 26, backgroundColor: Colors.white),
                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Container(
                          width: double.infinity,
                          height: 14,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))
                      ),
                      const SizedBox(height: 6),
                      Container(
                          width: 200,
                          height: 14,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))
                      ),
                      const SizedBox(height: 8),
                      Container(
                          width: 60,
                          height: 10,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 10, height: 10,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}