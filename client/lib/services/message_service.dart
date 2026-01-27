import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import 'base_service.dart';

class MessageService extends BaseService {
  static final MessageService instance = MessageService._internal();
  MessageService._internal();

  final _supabase = Supabase.instance.client;

  // --- LẤY DANH SÁCH CHAT GẦN ĐÂY ---
  Future<List<ChatPreviewModel>> getRecentChats({
    required String userId,
    required int limit,
    required int offset,
  }) async {
    return await safeExecution(() async {
      final data = await _supabase.rpc(
        'get_recent_chats_v2',
        params: {
          'current_user_id': userId,
          'limit_count': limit,
          'offset_count': offset,
        },
      );

      if (data == null) return [];

      return (data as List)
          .map((e) => ChatPreviewModel.fromJson(e))
          .toList();
    });
  }

  // --- LẤY DANH SÁCH BẠN BÈ ---
  Future<List<UserModel>> getFriends(String userId) async {
    return await safeExecution(() async {
      final response = await _supabase
          .from('friends_view')
          .select()
          .eq('user_id', userId);

      return (response as List)
          .map((data) => UserModel.fromFriendView(data))
          .toList();
    });
  }

  // --- TÌM KIẾM NGƯỜI DÙNG GLOBAL ---
  Future<List<UserModel>> searchUsersGlobal(String query) async {
    return await safeExecution(() async {
      final response = await _supabase.rpc(
        'search_users',
        params: {
          'search_query': query,
          'max_limit': 20,
        },
      );

      if (response == null) return [];

      return (response as List)
          .map((data) => UserModel.fromSearch(data))
          .toList();
    });
  }
}