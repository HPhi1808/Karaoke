import 'package:flutter/material.dart';
import '../models/song_model.dart'; // [QUAN TRỌNG] Import file chứa SongResponse
import '../services/song_service.dart';

class SongsProvider extends ChangeNotifier {
  // 1. Dữ liệu bài hát (Đổi kiểu dữ liệu từ HomeResponse -> SongResponse)
  SongResponse? _data;
  SongResponse? get data => _data;

  // 2. Trạng thái loading
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // 3. Thông báo lỗi
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Constructor: Tự động lấy dữ liệu khi khởi tạo
  SongsProvider() {
    fetchSongsData();
  }

  // Hàm lấy dữ liệu (Đổi tên hàm từ fetchHomeData -> fetchSongsData cho hợp lý)
  Future<void> fetchSongsData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Gọi service (Lưu ý: Service phải trả về SongResponse)
      _data = await SongService.instance.getSongsOverview();
    } catch (e) {
      _errorMessage = "Lỗi kết nối: ${e.toString()}";
      debugPrint(_errorMessage); // Dùng debugPrint thay cho print
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Hàm tăng view khi chọn bài
  Future<void> onSongSelected(int songId) async {
    try {
      await SongService.instance.incrementView(songId);
    } catch (e) {
      debugPrint("Lỗi tăng view: $e");
    }
  }
}