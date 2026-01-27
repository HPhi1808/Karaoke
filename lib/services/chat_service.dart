import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'base_service.dart';
import 'notification_service.dart';

class ChatService extends BaseService {
  static final ChatService instance = ChatService._internal();
  ChatService._internal();

  final _supabase = Supabase.instance.client;

  // --- GỬI TIN NHẮN (Bao gồm cả logic check thông báo) ---
  Future<void> sendMessage({
    required String myId,
    required String targetId,
    required String content,
  }) async {
    return await safeExecution(() async {
      // 1. Gửi tin nhắn vào DB
      await _supabase.from('messages').insert({
        'sender_id': myId,
        'receiver_id': targetId,
        'content': content,
      });

      // 2. Kiểm tra xem đối phương có đang chat với mình không để gửi Push Noti
      // (Logic này nên nằm ở Service để UI gọn)
      try {
        final statusData = await _supabase
            .from('user_chat_status')
            .select('current_partner_id')
            .eq('user_id', targetId)
            .maybeSingle();

        final String? chattingWithId = statusData?['current_partner_id'];

        // Nếu họ KHÔNG đang chat với mình -> Gửi thông báo
        if (chattingWithId != myId) {
          NotificationService.instance.sendChatNotification(
            receiverId: targetId,
            content: content,
          );
        }
      } catch (e) {
        // Lỗi gửi thông báo không nên làm fail việc gửi tin nhắn
        debugPrint("⚠️ Lỗi logic gửi thông báo: $e");
      }
    });
  }

  // --- ĐÁNH DẤU ĐÃ ĐỌC ---
  Future<void> markAsRead({required String myId, required String partnerId}) async {
    // Hàm này có thể không cần safeExecution quá khắt khe (silent retry là đủ)
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('sender_id', partnerId)
          .eq('receiver_id', myId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint("Lỗi markAsRead (ignored): $e");
    }
  }

  // --- CẬP NHẬT TRẠNG THÁI ĐANG CHAT ---
  Future<void> updateChatStatus(String myId, String? partnerId) async {
    try {
      await _supabase.from('user_chat_status').upsert({
        'user_id': myId,
        'current_partner_id': partnerId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint("Lỗi updateChatStatus (ignored): $e");
    }
  }

  // --- XOÁ CUỘC TRÒ CHUYỆN ---
  Future<void> deleteConversation(String myId, String partnerId) async {
    return await safeExecution(() async {
      await _supabase.from('deleted_conversations').upsert(
        {
          'user_id': myId,
          'partner_id': partnerId,
          'deleted_at': DateTime.now().toUtc().toIso8601String()
        },
        onConflict: 'user_id, partner_id',
      );
    });
  }

  // --- KIỂM TRA TÀI KHOẢN ĐỐI PHƯƠNG CÓ BỊ KHÓA KHÔNG ---
  Future<bool> checkUserLockStatus(String userId) async {
    return await safeExecution(() async {
      try {
        final userData = await _supabase
            .from('users')
            .select('locked_until')
            .eq('id', userId)
            .single();

        if (userData['locked_until'] != null) {
          final lockedUntil = DateTime.parse(userData['locked_until']);
          return lockedUntil.isAfter(DateTime.now());
        }
        return false;
      } catch (e) {
        return false;
      }
    });
  }
}