import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import 'base_service.dart';

class UserService extends BaseService{
  static final UserService instance = UserService._internal();
  UserService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // Lấy thông tin profile từ bảng 'users' của Supabase
  Future<UserModel> getUserProfile() async {
    return await safeExecution(() async {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("Chưa đăng nhập");

      try {
        final data = await _supabase
            .from('users')
            .select()
            .eq('id', user.id)
            .single();

        return UserModel.fromJson(data);
      } catch (e) {
        debugPrint(" Lỗi lấy profile từ Supabase: $e");
        if (e.toString().contains("PGRST116") ||
            e.toString().contains("Row not found")) {
          throw Exception(
              "Không tìm thấy dữ liệu user. Hãy kiểm tra Policy RLS!");
        }
        rethrow;
      }
    });
  }

  // --- LẤY DANH SÁCH BẠN BÈ (FOLLOW CHÉO) ---
  Future<List<UserModel>> getFriendsList() async {
    return await safeExecution(() async {
      try {
        final userId = _supabase.auth.currentUser?.id;
        if (userId == null) return [];

        final response = await _supabase
            .from('friends_view')
            .select()
            .eq('user_id', userId);
        
        final List<dynamic> data = response as List;
        return data.map((json) => UserModel.fromFriendView(json)).toList();
      } catch (e) {
        debugPrint(" Lỗi lấy danh sách bạn bè: $e");
        return [];
      }
    });
  }
}