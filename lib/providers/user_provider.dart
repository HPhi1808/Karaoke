import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';

class UserProvider extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = false;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;

  // Key lưu cache
  static const String _storageKey = 'cached_user_profile';

  // 1. Khởi tạo: Load từ Cache trước -> Sau đó gọi API cập nhật ngầm
  Future<void> initUser() async {
    if (AuthService.instance.isGuest) return;

    // A. Load Cache ngay lập tức
    await _loadFromCache();

    // B. Fetch API ngầm để cập nhật mới nhất
    await fetchUserProfile();
  }

  // 2. Load từ SharedPreferences (Json)
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        _currentUser = UserModel.fromJson(jsonDecode(jsonStr));
        notifyListeners(); // Cập nhật UI ngay lập tức
      }
    } catch (e) {
      debugPrint("Lỗi đọc cache user: $e");
    }
  }

  // 3. Gọi API lấy thông tin mới nhất
  Future<void> fetchUserProfile() async {
    if (AuthService.instance.isGuest) return;

    try {
      final user = await UserService.instance.getUserProfile();
      if (user != null) {
        _currentUser = user;
        // Lưu ngược vào cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storageKey, jsonEncode(user.toJson()));

        notifyListeners();
      }
    } catch (e) {
      debugPrint("Lỗi fetch user profile: $e");
    }
  }

  // 4. Hàm update dùng sau khi Edit Profile thành công
  void updateUserLocally(UserModel newUser) {
    _currentUser = newUser;
    // Lưu cache
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_storageKey, jsonEncode(newUser.toJson()));
    });
    notifyListeners();
  }

  // 5. Clear khi đăng xuất
  Future<void> clearUser() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }
}