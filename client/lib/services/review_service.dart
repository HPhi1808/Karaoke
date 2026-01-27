import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/review_model.dart';

class ReviewService {
  static final ReviewService instance = ReviewService._internal();
  ReviewService._internal();

  final _supabase = Supabase.instance.client;

  // 1. Lấy review của chính user đang đăng nhập
  Future<ReviewModel?> fetchMyReview() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final response = await _supabase
          .from('app_reviews')
          .select('*, users(full_name, avatar_url, username)')
          .eq('user_id', user.id)
          .maybeSingle();

      if (response == null) return null;
      return ReviewModel.fromJson(response);
    } catch (e) {
      debugPrint("Error fetching my review: $e");
      return null;
    }
  }

  // 2. Gửi đánh giá mới (Insert)
  Future<void> addReview(int rating, String comment) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("Bạn cần đăng nhập");

    try {
      await _supabase.from('app_reviews').insert({
        'user_id': user.id,
        'rating': rating,
        'comment': comment,
      });
    } catch (e) {
      if (e.toString().contains('duplicate key') || e.toString().contains('unique')) {
        throw Exception("Bạn đã đánh giá rồi.");
      }
      throw Exception("Lỗi gửi đánh giá: $e");
    }
  }

  // 3. Cập nhật đánh giá (Update)
  Future<void> updateReview(int rating, String comment) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("Bạn cần đăng nhập");

    try {
      await _supabase
          .from('app_reviews')
          .update({
        'rating': rating,
        'comment': comment,
      })
          .eq('user_id', user.id);
    } catch (e) {
      throw Exception("Lỗi cập nhật: $e");
    }
  }

  // 4. Xóa đánh giá (Delete)
  Future<void> deleteReview() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("Bạn cần đăng nhập");

    try {
      await _supabase
          .from('app_reviews')
          .delete()
          .eq('user_id', user.id);
    } catch (e) {
      throw Exception("Lỗi xóa: $e");
    }
  }
}