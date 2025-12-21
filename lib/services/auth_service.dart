import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  // Nếu chạy máy ảo Android thì dùng 10.0.2.2, máy thật thì dùng IP LAN
  // final String _baseUrl = 'http://10.0.2.2:3000';

  final String _baseUrl = 'https://karaoke-server-paan.onrender.com';

  // ==========================================================
  // PHẦN 1: QUẢN LÝ GUEST
  // ==========================================================

  Future<void> loginAsGuest() async {
    if (isGuest) {
      print("⚠️ Đang là Guest rồi, không tạo session mới.");
      return;
    }
    if (isLoggedIn && !isGuest) {
      await logout();
    }
    try {
      await _client.auth.signInAnonymously();
    } catch (e) {
      throw Exception('Lỗi đăng nhập khách: ${e.toString()}');
    }
  }

  bool get isGuest {
    final user = _client.auth.currentUser;
    return user?.isAnonymous ?? false;
  }

  Future<String> getCurrentRole() async {
    final user = _client.auth.currentUser;
    if (user == null) return '';
    try {
      final data = await _client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      return data?['role']?.toString() ?? 'guest';
    } catch (e) {
      return 'guest';
    }
  }

  // ==========================================================
  // PHẦN 2: LUỒNG ĐĂNG NHẬP
  // ==========================================================

  Future<void> login({required String identifier, required String password}) async {
    try {
      // 1. Lưu lại ID Guest cũ để dọn dẹp sau khi login thành công
      String? oldGuestId;
      if (isGuest) {
        oldGuestId = _client.auth.currentUser?.id;
      }

      String input = identifier.trim();
      String emailToLogin = "";

      // 2. TRUY VẤN DB ĐỂ LẤY THÔNG TIN
      final response = await _client
          .from('users')
          .select('email, role, username, locked_until')
          .or('email.eq.$input,username.eq.$input')
          .maybeSingle();

      if (response == null) {
        throw Exception('Tài khoản không tồn tại!');
      }

      final String role = response['role']?.toString() ?? 'user';
      final String? dbUsername = response['username'];
      final String? lockedUntilStr = response['locked_until'];
      emailToLogin = response['email'] as String;

      // 3. CHẶN QUYỀN QUẢN TRỊ (ADMIN/OWN)
      if (role == 'admin' || role == 'own') {
        throw Exception('Ứng dụng chỉ dành cho Thành viên. Quản trị viên vui lòng dùng Web Admin.');
      }

      // 4. CHẶN TÀI KHOẢN CHƯA HOÀN TẤT
      if (dbUsername == null) {
        throw Exception('Tài khoản này chưa hoàn tất thủ tục đăng ký. Vui lòng đăng ký lại.');
      }

      // 5. [MỚI] CHẶN TÀI KHOẢN BỊ KHÓA
      if (lockedUntilStr != null) {
        DateTime lockedTime = DateTime.parse(lockedUntilStr);
        // Nếu thời gian mở khóa nằm ở tương lai (tức là hiện tại đang bị khóa)
        if (lockedTime.isAfter(DateTime.now())) {
          throw Exception('Tài khoản của bạn đang bị KHÓA do vi phạm quy định.\nVui lòng liên hệ bộ phận chăm sóc để được hỗ trợ.');
        }
      }

      // 6. TIẾN HÀNH ĐĂNG NHẬP (AUTH)
      await _client.auth.signInWithPassword(
        email: emailToLogin,
        password: password,
      );

      // 7. DỌN DẸP TÀI KHOẢN GUEST CŨ
      if (oldGuestId != null) {
        _cleanupGuestAccount(oldGuestId);
      }

    } catch (e) {
      String msg = e.toString();
      // Xử lý thông báo lỗi từ Supabase cho thân thiện
      if (msg.contains("Invalid login credentials")) {
        throw Exception("Sai mật khẩu hoặc tài khoản!");
      }
      rethrow;
    }
  }

  // Hàm dọn dẹp Guest (Gọi API Node.js)
  Future<void> _cleanupGuestAccount(String guestId) async {
    try {
      http.post(
        Uri.parse('$_baseUrl/api/auth/cleanup-guest'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'guest_id': guestId}),
      );
    } catch (e) {
      print("❌ Lỗi kết nối dọn guest: $e");
    }
  }

  // ==========================================================
  // PHẦN 3: LUỒNG ĐĂNG KÝ
  // ==========================================================

  Future<String> sendRegisterOtp(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/register/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return responseData['status'] ?? 'success';
      } else {
        throw Exception(responseData['message'] ?? 'Lỗi gửi OTP');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> verifyRegisterOtp(String email, String otp) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/auth/register/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'token': otp}),
    );

    if (response.statusCode != 200) {
      final responseData = jsonDecode(response.body);
      throw Exception(responseData['message'] ?? 'Mã OTP không đúng');
    }
  }

  Future<void> completeRegister({
    required String email,
    required String username,
    required String fullName,
    required String password,
    required String gender,
    required String region,
  }) async {
    final usernameRegex = RegExp(r'^[a-zA-Z0-9]{3,20}$');
    if (!usernameRegex.hasMatch(username)) {
      throw Exception('Tên đăng nhập 3-20 ký tự, không dấu, không ký tự đặc biệt.');
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/register/complete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'username': username,
          'full_name': fullName,
          'password': password,
          'gender': gender,
          'region': region,
        }),
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(responseData['message'] ?? 'Lỗi hoàn tất đăng ký');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Lỗi kết nối máy chủ.');
    }
  }

  // ==========================================================
  // PHẦN 4: LUỒNG QUÊN MẬT KHẨU
  // ==========================================================

  Future<String> sendRecoveryOtp(String email) async {
    // 1. KIỂM TRA TÀI KHOẢN TRƯỚC KHI GỬI API
    try {
      final userCheck = await _client
          .from('users')
          .select('id, username')
          .eq('email', email)
          .maybeSingle();

      if (userCheck == null) {
        throw Exception('Email này chưa được đăng ký tài khoản nào.');
      }

      // Nếu username là null -> Tài khoản rác/chưa hoàn tất -> Không cho reset pass
      if (userCheck['username'] == null) {
        throw Exception('Email chưa đăng ký tài khoản!');
      }
    } catch (e) {
      if (e.toString().contains('Email này') || e.toString().contains('Tài khoản này')) {
        rethrow;
      }
    }

    // 2. GỌI API NODE.JS ĐỂ GỬI OTP
    final response = await http.post(
      Uri.parse('$_baseUrl/api/auth/forgot-password/send-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) return data['status'];
    throw Exception(data['message'] ?? 'Lỗi gửi OTP');
  }

  Future<String> verifyRecoveryOtp(String email, String otp) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/auth/forgot-password/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'token': otp}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) return data['temp_token'];
    throw Exception(data['message'] ?? 'OTP không đúng');
  }

  Future<void> resetPasswordFinal(String email, String newPassword) async {
    if (newPassword.length < 6) throw Exception('Mật khẩu phải có ít nhất 6 ký tự.');

    final response = await http.post(
      Uri.parse('$_baseUrl/api/auth/forgot-password/reset'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'new_password': newPassword,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Lỗi đổi mật khẩu');
    }
  }

  // ==========================================================
  // PHẦN 5: TIỆN ÍCH CHUNG
  // ==========================================================

  Future<void> logout() async {
    await _client.auth.signOut();
  }

  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => _client.auth.currentSession != null;
}