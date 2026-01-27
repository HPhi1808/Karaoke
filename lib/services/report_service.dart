import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ReportTargetType { user, song, moment, comment }

class ReportService {
  static final ReportService instance = ReportService._internal();
  ReportService._internal();

  final _supabase = Supabase.instance.client;

  // --- DANH SÁCH LÝ DO BÁO CÁO ---

  // 1. Lý do báo cáo Người dùng
  static const List<String> userReasons = [
    "Avatar không phù hợp/Nhạy cảm",
    "Tên vi phạm tiêu chuẩn cộng đồng",
    "Giả mạo người khác",
    "Quấy rối hoặc bắt nạt",
    "Đăng tải nội dung rác (Spam)",
    "Khác"
  ];

  // 2. Lý do báo cáo Bài hát
  static const List<String> songReasons = [
    "Lời bài hát sai lệch/Lỗi font",
    "Lời bài hát chứa nội dung phản cảm",
    "Audio bị lỗi/Không nghe được",
    "Sai thông tin ca sĩ/nhạc sĩ",
    "Vi phạm bản quyền",
    "Khác"
  ];

  // 3. Lý do báo cáo Moment (Bài đăng)
  static const List<String> momentReasons = [
    "Ngôn từ gây thù ghét/Xúc phạm",
    "Thông tin sai lệch",
    "Quảng cáo trái phép",
    "Nội dung vi phạm tiêu chuẩn cộng đồng",
    "Khác"
  ];

  // 4. Lý do báo cáo Comment (Bình luận)
  static const List<String> commentReasons = [
    "Ngôn từ lăng mạ, xúc phạm",
    "Thông tin sai lệch",
    "Quảng cáo trái phép",
    "Khác"
  ];

  // Hàm gửi báo cáo lên Server
  Future<void> submitReport({
    required ReportTargetType targetType,
    required String targetId,
    required String reason,
    String? description,
  }) async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) throw Exception("Bạn cần đăng nhập để thực hiện báo cáo.");

    final typeString = targetType.name;

    try {
      final existingReport = await _supabase
          .from('reports')
          .select('id')
          .eq('reporter_id', myId)
          .eq('target_type', typeString)
          .eq('target_id', targetId)
          .eq('status', 'pending')
          .maybeSingle();

      if (existingReport != null) {
        throw Exception("Báo cáo của bạn cho nội dung này đang chờ xử lý. Vui lòng đợi kết quả trước khi báo cáo lại.");
      }

      await _supabase.from('reports').insert({
        'reporter_id': myId,
        'target_type': typeString,
        'target_id': targetId,
        'reason': reason,
        'description': description,
        'status': 'pending',
      });

    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception("Bạn đã báo cáo nội dung này rồi và đang chờ xử lý.");
      }
      debugPrint("Lỗi Database Report: ${e.message}");
      throw Exception("Lỗi kết nối khi gửi báo cáo. Vui lòng thử lại.");
    } catch (e) {
      debugPrint("Lỗi ReportService: $e");
      rethrow;
    }
  }
}