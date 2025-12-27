import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

class UserService {
  static final UserService instance = UserService._internal();
  UserService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // Lấy thông tin profile từ bảng 'users' của Supabase
  Future<UserModel> getUserProfile() async {
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
      print("❌ Lỗi lấy profile từ Supabase: $e");
      if (e.toString().contains("PGRST116") || e.toString().contains("Row not found")) {
        throw Exception("Không tìm thấy dữ liệu user. Hãy kiểm tra Policy RLS!");
      }
      rethrow;
    }
  }
}