import 'package:flutter/material.dart';
import '../models/home_model.dart';
import '../services/api_service.dart';

class HomeProvider extends ChangeNotifier {
  // 1. Dữ liệu trang chủ
  HomeResponse? _homeData;
  HomeResponse? get homeData => _homeData;

  // 2. Trạng thái loading
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // 3. Thông báo lỗi
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Constructor (Tương đương khối init trong Kotlin)
  HomeProvider() {
    fetchHomeData();
  }

  // Hàm lấy dữ liệu (Tương đương fetchHomeData)
  Future<void> fetchHomeData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners(); // Báo cho UI hiện loading

    try {
      // Gọi API qua Singleton đã tạo ở bước trước
      _homeData = await ApiService.instance.getHomeData();
    } catch (e) {
      _errorMessage = "Lỗi kết nối: ${e.toString()}";
      print(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners(); // Báo cho UI cập nhật dữ liệu hoặc hiện lỗi
    }
  }

  // Hàm tăng view (Tương đương onSongSelected)
  // Kotlin dùng Long, Dart dùng int (int Dart đủ chứa Long)
  Future<void> onSongSelected(int songId) async {
    try {
      await ApiService.instance.incrementView(songId);
      // Không cần notifyListeners() vì tăng view chạy ngầm, không đổi giao diện ngay
    } catch (e) {
      print("Lỗi tăng view: $e");
    }
  }
}