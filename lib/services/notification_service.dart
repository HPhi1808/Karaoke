import 'dart:async';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rxdart/rxdart.dart';
import 'api_client.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final Dio _dio = ApiClient.instance.dio;
  final _supabase = Supabase.instance.client;

  // Quản lý các Controller để phát dữ liệu cho UI
  final _totalController = BehaviorSubject<int>.seeded(0);
  final _notifsController = BehaviorSubject<int>.seeded(0);
  final _msgsController = BehaviorSubject<int>.seeded(0);

  // Quản lý các Subscription để có thể hủy khi logout
  StreamSubscription? _notifSub;
  StreamSubscription? _msgSub;
  StreamSubscription? _authSub;
  StreamSubscription? _combineSub;

  Stream<int> getTotalUnreadCountStream() => _totalController.stream;
  Stream<int> getUnreadNotificationsCountStream() => _notifsController.stream;
  Stream<int> getUnreadMessagesCountStream() => _msgsController.stream;

  bool _isInitialized = false;
  void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    // Lắng nghe sự thay đổi tài khoản
    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      final userId = data.session?.user.id;
      if (userId == null) {
        _stopListening();
        clear();
      } else {
        _startListening(userId);
      }
    });

    // Tự động gộp 2 luồng dữ liệu thành tổng số
    _combineSub = CombineLatestStream.combine2<int, int, int>(
      _notifsController.stream,
      _msgsController.stream,
      (a, b) => a + b,
    ).listen((total) => _totalController.add(total));
  }

  void _startListening(String userId) {
    _stopListening(); // Hủy các kết nối cũ nếu có

    // 1. Thông báo chưa đọc
    _notifSub = _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', userId)
        .map((data) => data.where((item) => item['is_read'] == false).length)
        .listen((count) => _notifsController.add(count));

    // 2. Tin nhắn chưa đọc
    _msgSub = _supabase
        .from('messages')
        .stream(primaryKey: ['message_id'])
        .eq('receiver_id', userId)
        .map((data) {
          // QUAN TRỌNG: Chỉ đếm tin nhắn mà mình là người NHẬN và chưa đọc
          return data.where((item) => 
            item['receiver_id'] == userId && 
            item['is_read'] == false
          ).length;
        })
        .listen((count) => _msgsController.add(count));
  }

  void _stopListening() {
    _notifSub?.cancel();
    _msgSub?.cancel();
  }

  void clear() {
    _notifsController.add(0);
    _msgsController.add(0);
    _totalController.add(0);
  }

  void dispose() {
    _authSub?.cancel();
    _combineSub?.cancel();
    _stopListening();
    _totalController.close();
    _notifsController.close();
    _msgsController.close();
  }

  // --- API CALLS ---
  Future<bool> followUser({required String targetUserId}) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return false;
    try {
      final response = await _dio.post('/api/user/notifications/follow', data: {'follower_id': currentUser.id, 'following_id': targetUserId});
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<bool> unfollowUser({required String targetUserId}) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return false;
    try {
      final response = await _dio.post('/api/user/notifications/unfollow', data: {'follower_id': currentUser.id, 'following_id': targetUserId});
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<void> sendChatNotification({required String receiverId, required String content}) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;
    try {
      await _dio.post('/api/user/notifications/chat', data: {'sender_id': currentUser.id, 'receiver_id': receiverId, 'message_content': content});
    } catch (e) {}
  }
}