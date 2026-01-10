import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_client.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final Dio _dio = ApiClient.instance.dio;

  //Gọi API Follow user và gửi thông báo
  Future<bool> followUser({required String targetUserId}) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      debugPrint("❌ Chưa đăng nhập");
      return false;
    }

    try {
      final response = await _dio.post(
        '/api/user/notifications/follow',
        data: {
          'follower_id': currentUser.id,
          'following_id': targetUserId,
        },
      );

      if (response.statusCode == 200) {
        debugPrint("✅ Follow thành công: ${response.data}");
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi Follow API: $e");
      return false;
    }
  }

  //Gọi API Unfollow và thu hồi thông báo
  Future<bool> unfollowUser({required String targetUserId}) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return false;

    try {
      final response = await _dio.post(
        '/api/user/notifications/unfollow',
        data: {
          'follower_id': currentUser.id,
          'following_id': targetUserId,
        },
      );

      if (response.statusCode == 200) {
        debugPrint("✅ Unfollow thành công: ${response.data}");
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi Unfollow API: $e");
      return false;
    }
  }

  //Gọi API gửi thông báo tin nhắn
  Future<void> sendChatNotification({
    required String receiverId,
    required String content,
  }) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    try {
      await _dio.post(
        '/api/user/notifications/chat',
        data: {
          'sender_id': currentUser.id,
          'receiver_id': receiverId,
          'message_content': content,
        },
      );

      if (kDebugMode) {
        debugPrint("🔔 Đã gửi lệnh Push Notification tin nhắn");
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi gửi thông báo tin nhắn (Server): $e");
    }
  }
}