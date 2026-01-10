import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/notification_model.dart';
import '../../../services/base_service.dart';

class SystemMessagesScreen extends StatefulWidget {
  const SystemMessagesScreen({super.key});

  @override
  State<SystemMessagesScreen> createState() => _SystemMessagesScreenState();
}

class _SystemMessagesScreenState extends State<SystemMessagesScreen> {
  final _baseService = BaseService();

  bool _isLoading = true;
  List<NotificationModel> _messages = [];

  @override
  void initState() {
    super.initState();
    _fetchSystemMessages();
  }

  Future<void> _fetchSystemMessages() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // 2. Bao bọc bằng safeExecution
      final response = await _baseService.safeExecution(() async {
        return await Supabase.instance.client
            .from('all_notifications_view')
            .select()
            .order('created_at', ascending: false);
      });

      if (mounted) {
        setState(() {
          final allList = (response as List)
              .map((e) => NotificationModel.fromJson(e))
              .where((noti) {
            bool isSystem = noti.category == 'system';
            final type = (noti.type).trim().toLowerCase();
            bool isAdminMessage = ['warning', 'info', 'success'].contains(type);
            return isSystem || isAdminMessage;
          })
              .toList();

          _messages = allList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải tin hệ thống: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markItemAsRead(int index) async {
    final msg = _messages[index];
    if (msg.isRead) return;

    final updatedMsg = NotificationModel(
      id: msg.id,
      title: msg.title,
      message: msg.message,
      createdAt: msg.createdAt,
      isRead: true,
      type: msg.type,
      category: msg.category,
    );

    setState(() {
      _messages[index] = updatedMsg;
    });

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      if (msg.category == 'personal') {
        await supabase
            .from('notifications')
            .update({'is_read': true})
            .eq('id', msg.id)
            .eq('user_id', userId);
      } else {
        await supabase
            .from('system_read_status')
            .upsert({
          'user_id': userId,
          'notification_id': msg.id,
        });
      }
    } catch (e) {
      debugPrint("Lỗi server khi mark read: $e");
    }
  }

  _MessageStyle _getStyle(String? typeRaw) {
    final type = (typeRaw ?? '').trim().toLowerCase();
    switch (type) {
      case 'warning':
        return _MessageStyle(
          icon: Icons.warning_amber_rounded,
          color: Colors.red,
          bgColor: Colors.red.withValues(alpha: 0.1),
          label: "Cảnh báo",
        );
      case 'success':
        return _MessageStyle(
          icon: Icons.card_giftcard,
          color: Colors.green,
          bgColor: Colors.green.withValues(alpha: 0.1),
          label: "Quà tặng",
        );
      case 'info':
        return _MessageStyle(
          icon: Icons.info_outline,
          color: Colors.blue,
          bgColor: Colors.blue.withValues(alpha: 0.1),
          label: "Thông tin",
        );
      default:
        return _MessageStyle(
          icon: Icons.campaign_rounded,
          color: const Color(0xFFFF00CC),
          bgColor: const Color(0xFFFF00CC).withValues(alpha: 0.1),
          label: "Hệ thống",
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Tin nhắn hệ thống", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF00CC)))
          : _messages.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text("Hộp thư trống", style: TextStyle(color: Colors.grey[500], fontSize: 16)),
            const SizedBox(height: 10),
            // Nút thử lại thủ công
            TextButton.icon(
                onPressed: _fetchSystemMessages,
                icon: const Icon(Icons.refresh),
                label: const Text("Tải lại")
            )
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 20),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final msg = _messages[index];
          final style = _getStyle(msg.type);
          final bool isUnread = !msg.isRead;

          return Container(
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: isUnread ? style.bgColor.withValues(alpha: 0.08) : Colors.white,
              border: isUnread
                  ? Border(left: BorderSide(color: style.color, width: 4))
                  : null,
            ),
            child: InkWell(
              onTap: () => _markItemAsRead(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: style.bgColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(style.icon, color: style.color, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: style.color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  style.label.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: style.color,
                                  ),
                                ),
                              ),
                              Text(
                                _formatDate(msg.createdAt),
                                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            msg.title,
                            style: TextStyle(
                              fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                              fontSize: 15,
                              color: isUnread ? Colors.black87 : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            msg.message,
                            style: TextStyle(
                              color: isUnread ? Colors.black87 : Colors.grey[600],
                              height: 1.4,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month} • ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }
}

class _MessageStyle {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String label;

  _MessageStyle({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.label,
  });
}