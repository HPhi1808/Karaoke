import 'package:flutter/material.dart';
import '../models/home_model.dart';
import '../services/song_service.dart';


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

  HomeProvider() {
    fetchHomeData();
  }

  // Hàm lấy dữ liệu
  Future<void> fetchHomeData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _homeData = await SongService.instance.getHomeData();
    } catch (e) {
      _errorMessage = "Lỗi kết nối: ${e.toString()}";
      print(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Hàm tăng view
  Future<void> onSongSelected(int songId) async {
    try {
      await SongService.instance.incrementView(songId);
    } catch (e) {
      print("Lỗi tăng view: $e");
    }
  }
}