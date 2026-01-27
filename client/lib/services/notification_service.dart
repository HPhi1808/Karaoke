import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rxdart/rxdart.dart';
import 'api_client.dart';
import 'base_service.dart';

class NotificationService extends BaseService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final Dio _dio = ApiClient.instance.dio;
  final _supabase = Supabase.instance.client;

  // --- Quản lý State (Streams) ---
  final _totalController = BehaviorSubject<int>.seeded(0);
  final _notifsController = BehaviorSubject<int>.seeded(0);
  final _msgsController = BehaviorSubject<int>.seeded(0);

  // Subscriptions
  StreamSubscription? _authSub;
  RealtimeChannel? _realtimeChannel;

  // Getters cho UI lắng nghe
  Stream<int> getTotalUnreadCountStream() => _totalController.stream;
  Stream<int> getUnreadNotificationsCountStream() => _notifsController.stream;
  Stream<int> getUnreadMessagesCountStream() => _msgsController.stream;

  bool _isInitialized = false;

  // --- KHỞI TẠO ---
  void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      final userId = data.session?.user.id;
      if (userId == null) {
        _cleanup();
      } else {
        fetchCounts();
        _subscribeToRealtime(userId);
      }
    });

    // Gộp 2 stream
    CombineLatestStream.combine2<int, int, int>(
      _notifsController.stream,
      _msgsController.stream,
          (a, b) => a + b,
    ).listen((total) {
      if (!_totalController.isClosed) _totalController.add(total);
    });
  }

  // --- LẤY SỐ LIỆU TỪ DB ---
  Future<void> fetchCounts() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await safeExecution(() async {
      // 1. Đếm tin nhắn chưa đọc
      final msgCount = await _supabase
          .from('messages')
          .count(CountOption.exact)
          .eq('receiver_id', userId)
          .eq('is_read', false);

      // 2. Đếm thông báo chưa đọc
      final notifCount = await _supabase
          .from('notifications')
          .count(CountOption.exact)
          .eq('user_id', userId)
          .eq('is_read', false);

      // 3. Đẩy vào Stream
      if (!_msgsController.isClosed) _msgsController.add(msgCount);
      if (!_notifsController.isClosed) _notifsController.add(notifCount);

      debugPrint("🔔 Updated Counts: Msg=$msgCount, Notif=$notifCount");
    });
  }

  // --- LẮNG NGHE REALTIME ---
  void _subscribeToRealtime(String userId) {
    if (_realtimeChannel != null) _supabase.removeChannel(_realtimeChannel!);

    _realtimeChannel = _supabase.channel('global_counts_listener')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'receiver_id',
          value: userId
      ),
      callback: (payload) => fetchCounts(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId
      ),
      callback: (payload) => fetchCounts(),
    )
        .subscribe();
  }

  // --- DỌN DẸP ---
  void _cleanup() {
    if (_realtimeChannel != null) _supabase.removeChannel(_realtimeChannel!);
    _realtimeChannel = null;
    if (!_notifsController.isClosed) _notifsController.add(0);
    if (!_msgsController.isClosed) _msgsController.add(0);
    if (!_totalController.isClosed) _totalController.add(0);
  }

  void clear() {
    _cleanup();
  }

  void dispose() {
    _authSub?.cancel();
    _cleanup();
    _totalController.close();
    _notifsController.close();
    _msgsController.close();
  }

  // --- API CALLS ---

  Future<bool> followUser({required String targetUserId}) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return false;

    return await safeExecution(() async {
      final response = await _dio.post(
        '/api/user/notifications/follow',
        data: {
          'follower_id': currentUser.id,
          'following_id': targetUserId
        },
      );
      return response.statusCode == 200;
    });
  }

  Future<bool> unfollowUser({required String targetUserId}) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return false;

    return await safeExecution(() async {
      final response = await _dio.post(
        '/api/user/notifications/unfollow',
        data: {
          'follower_id': currentUser.id,
          'following_id': targetUserId
        },
      );
      return response.statusCode == 200;
    });
  }

  Future<void> sendChatNotification({required String receiverId, required String content}) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;

    // [MỚI] Bọc safeExecution để đảm bảo thông báo đẩy được gửi đi
    await safeExecution(() async {
      await _dio.post(
        '/api/user/notifications/chat',
        data: {
          'sender_id': currentUser.id,
          'receiver_id': receiverId,
          'message_content': content
        },
      );
    });
  }
}