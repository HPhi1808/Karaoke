import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/notification_model.dart';

class SystemMessagesScreen extends StatefulWidget {
  const SystemMessagesScreen({Key? key}) : super(key: key);

  @override
  State<SystemMessagesScreen> createState() => _SystemMessagesScreenState();
}

class _SystemMessagesScreenState extends State<SystemMessagesScreen> {
  bool _isLoading = true;
  List<NotificationModel> _messages = [];

  @override
  void initState() {
    super.initState();
    _fetchSystemMessages();
  }

  Future<void> _fetchSystemMessages() async {
    try {
      final response = await Supabase.instance.client
          .from('all_notifications_view')
          .select()
          .eq('category', 'system')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _messages = (response as List)
              .map((e) => NotificationModel.fromJson(e))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải tin hệ thống: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LOGIC QUAN TRỌNG NHẤT Ở ĐÂY ---
  Future<void> _markItemAsRead(int index) async {
    final msg = _messages[index];

    // 1. ANTI-SPAM CHECK: Nếu đã đọc rồi thì dừng ngay lập tức (return).
    // Không gửi request, không làm gì cả.
    if (msg.isRead) return;

    // 2. OPTIMISTIC UPDATE: Cập nhật UI ngay lập tức để user thấy phản hồi
    // Tạo một bản sao mới của model với isRead = true
    final updatedMsg = NotificationModel(
      id: msg.id,
      title: msg.title,
      message: msg.message,
      createdAt: msg.createdAt,
      isRead: true, // Đánh dấu đã đọc local
      type: msg.type,
      category: msg.category,
    );

    setState(() {
      _messages[index] = updatedMsg; // Thay thế item trong list
    });

    // 3. Gửi request lên Supabase (Chạy ngầm)
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client.from('system_read_status').upsert({
          'user_id': userId,
          'notification_id': msg.id,
        });
        // Không cần setState ở đây nữa vì UI đã update ở bước 2 rồi
      }
    } catch (e) {
      debugPrint("Lỗi server: $e");
      // Nếu cần thiết, bạn có thể revert UI lại ở đây (nhưng với tính năng "đã đọc" thì không cần quá khắt khe)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Thông báo hệ thống", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final msg = _messages[index];

          // Logic hiển thị: Nếu chưa đọc thì nền hồng nhạt, đã đọc thì nền trắng
          final bgColor = msg.isRead ? Colors.white : const Color(0xFFFFF0F5);

          return Container(
            color: bgColor,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  // Nếu chưa đọc thì icon màu đậm, đã đọc màu nhạt hơn chút
                  color: msg.isRead
                      ? Colors.grey[200]
                      : Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    Icons.campaign,
                    // Icon màu cam nếu chưa đọc, màu xám nếu đọc rồi
                    color: msg.isRead ? Colors.grey : Colors.orange,
                    size: 24
                ),
              ),
              title: Text(
                msg.title,
                style: TextStyle(
                  // Chưa đọc thì in đậm
                  fontWeight: msg.isRead ? FontWeight.normal : FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    msg.message,
                    style: TextStyle(
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDate(msg.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
              onTap: () {
                // Gọi hàm xử lý khi bấm vào
                _markItemAsRead(index);
              },
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return "Ngày ${date.day}/${date.month}/${date.year} • ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }
}