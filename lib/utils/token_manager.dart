import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenManager {
  static final TokenManager instance = TokenManager._internal();

  TokenManager._internal();

  // Khởi tạo thư viện bảo mật
  // Trên Android nó sẽ tự dùng EncryptedSharedPreferences như code cũ của bạn
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // Key constants
  static const String _keyAccessToken = "access_token";
  static const String _keyRefreshToken = "refresh_token";
  static const String _keyUserRole = "user_role";

  // --- CÁC HÀM LƯU / LẤY / XÓA ---

  // 1. Lưu thông tin đăng nhập
  // Lưu ý: Phải dùng Future<void> vì ghi đĩa là bất đồng bộ
  Future<void> saveAuthInfo(String accessToken, String refreshToken, String role) async {
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: accessToken),
      _storage.write(key: _keyRefreshToken, value: refreshToken),
      _storage.write(key: _keyUserRole, value: role),
    ]);
  }

  // 2. Lấy Access Token
  Future<String?> getAccessToken() async {
    return await _storage.read(key: _keyAccessToken);
  }

  // 3. Lấy Refresh Token
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _keyRefreshToken);
  }

  // 4. Lấy Role (admin/user/own)
  Future<String?> getUserRole() async {
    return await _storage.read(key: _keyUserRole);
  }

  // 5. Xóa hết (Dùng khi Đăng xuất)
  Future<void> clearAuth() async {
    await _storage.deleteAll();
  }
}