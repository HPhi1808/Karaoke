import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../utils/token_manager.dart';
import '../utils/user_manager.dart';
import 'api_client.dart';
import 'base_service.dart';

class AuthService extends BaseService{
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  String get _baseUrl => ApiClient.baseUrl;

  // Hàm đồng bộ onesignal
  Future<void> _syncOneSignal(String userId, String role) async {
    try {
      OneSignal.login(userId);
      await Future.delayed(const Duration(seconds: 2));
      OneSignal.User.addTagWithKey("role", role);

      debugPrint("🔔 OneSignal Synced: $userId ($role)");
    } catch (e) {
      debugPrint("⚠️ Lỗi sync OneSignal: $e");
    }
  }

  // Hàm khôi phục session
  Future<bool> recoverSession() async {
    return await safeExecution(() async {
      try {
        // 1. Lấy Refresh Token từ bộ nhớ
        final refreshToken = await TokenManager.instance.getRefreshToken();
        if (refreshToken == null || refreshToken.isEmpty) return false;

        // 2. Yêu cầu Supabase cấp session mới
        final response = await _client.auth.setSession(refreshToken);

        if (response.session != null) {
          // 3. Lưu lại token mới nhất vào máy
          String role = await getCurrentRole();
          await TokenManager.instance.saveAuthInfo(
              response.session!.accessToken,
              response.session!.refreshToken ?? '',
              role
          );
          if (response.user != null) {
            _syncOneSignal(response.user!.id, role);
          }
          return true;
        }
        return false;
      } catch (e) {
        debugPrint("⚠️ Lỗi khôi phục session: $e");
        return false;
      }
    });
  }

  // ==========================================================
  // PHẦN 1: QUẢN LÝ GUEST (KHÁCH)
  // ==========================================================

  Future<void> loginAsGuest() async {
    await safeExecution(() async {
      // 1. ƯU TIÊN 1: Kiểm tra Session đang sống trong RAM
      final currentSession = _client.auth.currentSession;

      if (currentSession != null && !currentSession.isExpired) {
        // Nếu session này LÀ GUEST -> Dùng lại ngay
        if (currentSession.user.isAnonymous) {
          _syncOneSignal(currentSession.user.id, 'guest');
          debugPrint("♻️ Tái sử dụng Guest Session (RAM) - Không tạo mới.");
          return;
        } else {
          // Nếu đang là User thật (Real User) mà muốn vào Guest -> Phải đăng xuất User thật trước
          await logout();
        }
      }

      // 2. ƯU TIÊN 2: Thử khôi phục từ Disk (Trường hợp tắt app mở lại)
      // Lưu ý: recoverSession() của bạn tự động lưu vào TokenManager nếu thành công
      bool isRecovered = await recoverSession();

      if (isRecovered) {
        final recoveredSession = _client.auth.currentSession;
        if (recoveredSession != null && recoveredSession.user.isAnonymous) {
          debugPrint("♻️ Tái sử dụng Guest Session (Disk) - Không tạo mới.");
          return;
        } else {
          await logout();
        }
      }

      // 3. BƯỚC CUỐI: Không còn cách nào khác -> BẮT BUỘC TẠO MỚI
      try {
        debugPrint("🚀 Không tìm thấy Guest cũ -> Tạo Guest User mới...");
        final res = await _client.auth.signInAnonymously();

        if (res.session != null) {
          await TokenManager.instance.saveAuthInfo(
              res.session!.accessToken,
              res.session!.refreshToken ?? '',
              'guest'
          );
          _syncOneSignal(res.user!.id, 'guest');
        } else {
          throw Exception("Supabase không trả về Session.");
        }
      } catch (e) {
        throw Exception('Lỗi đăng nhập khách: $e');
      }
    });
  }

  // Getter kiểm tra nhanh
  bool get isGuest {
    final user = _client.auth.currentUser;
    return user?.isAnonymous ?? false;
  }

  // Lấy Role KHÔNG CẦN GỌI DATABASE
  Future<String> getCurrentRole() async {
      // Ưu tiên 1: Lấy từ Local Storage
    String? storedRole = await TokenManager.instance.getUserRole();
    if (storedRole != null && storedRole.isNotEmpty) {
      return storedRole;
    }

    final user = _client.auth.currentUser;
    if (user == null) return '';

    // Ưu tiên 2: Nếu là Anonymous User -> Guest
    if (user.isAnonymous) return 'guest';

    // Ưu tiên 3: Lấy từ Metadata
    final roleFromMeta = user.appMetadata['role'];
    if (roleFromMeta != null) {
      return roleFromMeta.toString();
    }

    return 'user';
  }

  // ==========================================================
  // PHẦN 2: LUỒNG ĐĂNG NHẬP (USER)
  // ==========================================================

  Future<void> login({required String identifier, required String password}) async {
    await safeExecution(() async {
      try {
        UserManager.instance.setLoginProcess(true);
        String? oldGuestId;
        if (isGuest) {
          oldGuestId = _client.auth.currentUser?.id;
        }

        String input = identifier.trim();
        String emailToLogin = "";
        String role = 'user';

        // 1. Kiểm tra User trong DB
        final response = await _client
            .from('users')
            .select('email, role, username, locked_until')
            .or('email.eq.$input,username.eq.$input')
            .maybeSingle();

        if (response == null) {
          throw Exception('Tài khoản không tồn tại!');
        }

        role = response['role']?.toString() ?? 'user';
        final String? dbUsername = response['username'];
        final String? lockedUntilStr = response['locked_until'];
        emailToLogin = response['email'] as String;

        if (role == 'admin' || role == 'own') {
          throw Exception(
              'App chỉ dành cho Thành viên. Admin vui lòng dùng Web.');
        }

        if (dbUsername == null) {
          throw Exception('Dữ liệu tài khoản lỗi (thiếu username).');
        }

        // Check khóa tài khoản
        if (lockedUntilStr != null) {
          DateTime lockedTime = DateTime.parse(lockedUntilStr).toLocal();
          if (lockedTime.isAfter(DateTime.now())) {
            throw Exception(
                'Tài khoản bị KHÓA đến ${lockedTime.toString().split(
                    '.')[0]}.');
          }
        }

        // 2. Thực hiện đăng nhập Auth
        final AuthResponse res = await _client.auth.signInWithPassword(
          email: emailToLogin,
          password: password,
        );

        final session = res.session;

        // 3. XỬ LÝ SESSION ID
        if (session != null && res.user != null) {
          // Lưu Token vào TokenManager
          await TokenManager.instance.saveAuthInfo(
              session.accessToken,
              session.refreshToken ?? '',
              role
          );

          _syncOneSignal(res.user!.id, role);
          OneSignal.User.addEmail(emailToLogin);

          // --- ĐỒNG BỘ SESSION ID TỪ TOKEN ---
          final String supabaseSessionId = await UserManager.instance
              .syncSessionFromToken(session.accessToken);

          final nowUtc = DateTime.now().toUtc().toIso8601String();

          // A. Cập nhật ID này lên Database
          await _client.from('users').update({
            'current_session_id': supabaseSessionId,
            'last_sign_in_at': nowUtc,
            'last_active_at': nowUtc,
          }).eq('id', res.user!.id);


          // C. Khởi động Manager (Guard)
          UserManager.instance.init();
        } else {
          throw Exception("Đăng nhập thất bại!");
        }

        // 4. Dọn dẹp Guest cũ
        if (oldGuestId != null) {
          _cleanupGuestAccount(oldGuestId);
        }
      } catch (e) {
        UserManager.instance.setLoginProcess(false);
        String msg = e.toString();
        if (msg.contains("Invalid login credentials")) {
          throw Exception("Sai mật khẩu hoặc tài khoản!");
        }
        rethrow;
      }
    });
  }

  Future<void> loginWithGoogle() async {
    await safeExecution(() async {
      String? oldGuestId;
      if (isGuest) {
        oldGuestId = _client.auth.currentUser?.id;
      }

      // 🌍 1. WEB
      if (kIsWeb) {
        await _client.auth.signInWithOAuth(
          OAuthProvider.google,
          // redirectTo: 'http://localhost:5000',
          redirectTo: 'https://app.karaokeplus.cloud',
          scopes: 'email profile openid',
        );
        return;
      }

      // 📱 2. MOBILE
      const webClientId = '575075728372-4450bgdh0h1h8qnk12d4v13q82ufo2qb.apps.googleusercontent.com';

      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
        scopes: ['email', 'profile', 'openid'],
      );

      try {
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) return;

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final accessToken = googleAuth.accessToken;
        final idToken = googleAuth.idToken;

        if (idToken == null) throw Exception('Không lấy được ID Token từ Google.');

        final AuthResponse res = await _client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );

        final session = res.session;
        final user = res.user;

        if (session != null && user != null) {
          await _handleAfterLogin(session, user, googleSignIn);
          debugPrint("✅ Đăng nhập Google Mobile thành công: ${user.email}");
        } else {
          throw Exception("Đăng nhập thất bại.");
        }

        if (oldGuestId != null) _cleanupGuestAccount(oldGuestId);

      } catch (e) {
        googleSignIn.signOut();
        debugPrint("❌ Lỗi Login Google Mobile: $e");
        rethrow;
      }
    });
  }

  Future<void> finalizeWebLogin(Session session) async {
    final user = session.user;
    await _handleAfterLogin(session, user, null);
    debugPrint("✅ Web Redirect: Đã hoàn tất đồng bộ dữ liệu sau đăng nhập.");
  }

  // 🛠️ HÀM PHỤ: Xử lý logic sau khi có User & Session
  Future<void> _handleAfterLogin(Session session, User user, GoogleSignIn? googleSignIn) async {
    UserManager.instance.setLoginProcess(true);
    final userData = await _client
        .from('users')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

    final String role = userData?['role'] ?? 'user';

    // 1. Check quyền Admin
    if (role == 'admin' || role == 'own') {
      UserManager.instance.setLoginProcess(false);
      await _client.auth.signOut();
      if (googleSignIn != null) await googleSignIn.signOut();
      await TokenManager.instance.clearAuth();
      throw Exception("Tài khoản Quản trị viên không thể đăng nhập vào App.");
    }

    // 2. Lưu Token
    await TokenManager.instance.saveAuthInfo(
        session.accessToken,
        session.refreshToken ?? '',
        role
    );

    // 3. Sync OneSignal
    _syncOneSignal(user.id, role);
    if (user.email != null) {
      OneSignal.User.addEmail(user.email!);
    }

    final String supabaseSessionId = await UserManager.instance
        .syncSessionFromToken(session.accessToken);
    final nowUtc = DateTime.now().toUtc().toIso8601String();

    Map<String, dynamic> updates = {
      'current_session_id': supabaseSessionId,
      'last_sign_in_at': nowUtc,
      'last_active_at': nowUtc,
    };

    // 4. Kiểm tra User mới để cập nhật Avatar/Tên từ Google
    final createdAt = DateTime.parse(user.createdAt);
    final isNewUser = DateTime.now().toUtc().difference(createdAt).inSeconds < 60;

    if (isNewUser) {
      debugPrint("🚀 User mới -> Đồng bộ thông tin Google");
      final googleAvatar = user.userMetadata?['avatar_url'];
      final googleName = user.userMetadata?['full_name'];

      updates['avatar_url'] = googleAvatar ??
          'https://media.karaokeplus.cloud/PictureApp/defautl.jpg';

      if (googleName != null) {
        updates['full_name'] = googleName;
      }
    }

    await _client.from('users').update(updates).eq('id', user.id);
    await UserManager.instance.init();
    Future.delayed(const Duration(seconds: 3), () {
      UserManager.instance.setLoginProcess(false);
      debugPrint("🛡️ User Manager: Đã tắt chế độ đăng nhập (Sẵn sàng bảo vệ)");
    });
  }

  // Hàm dọn dẹp guest
  Future<void> _cleanupGuestAccount(String guestId) async {
    await safeExecution(() async {
      try {
        await http.post(
          Uri.parse('$_baseUrl/api/auth/cleanup-guest'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'guest_id': guestId}),
        );
      } catch (e) {
        debugPrint("❌ Lỗi kết nối dọn guest: $e");
      }
    });
  }

  // ==========================================================
  // PHẦN 3: XỬ LÝ TOKEN & LOGOUT & TIỆN ÍCH
  // ==========================================================

  // Hàm logout
  Future<void> logout() async {
    try {
      OneSignal.logout();
      await _client.auth.signOut(scope: SignOutScope.global);
    } catch (e) {
      debugPrint("⚠️ Logout Server Error (Ignored): $e");
    }
    await TokenManager.instance.clearAuth();
  }

  // Hàm xử lý hết hạn token (Đá về login)
  Future<void> handleTokenExpired(BuildContext context) async {
    await safeExecution(() async {
      if (!context.mounted) return;
      await logout();
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Phiên đăng nhập hết hạn."))
      );
    });
  }

  User? get currentUser => _client.auth.currentUser;

  bool get isLoggedIn => _client.auth.currentSession != null;

  // ==========================================================
  // PHẦN 4: LUỒNG ĐĂNG KÝ
  // ==========================================================

  Future<String> sendRegisterOtp(String email) async {
    return await safeExecution(() async {
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
    });
  }

  Future<void> verifyRegisterOtp(String email, String otp) async {
    await safeExecution(() async {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/register/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'token': otp}),
      );

      if (response.statusCode != 200) {
        final responseData = jsonDecode(response.body);
        throw Exception(responseData['message'] ?? 'Mã OTP không đúng');
      }
    });
  }

  Future<void> completeRegister({
    required String email,
    required String username,
    required String fullName,
    required String password,
    required String gender,
    required String region,
  }) async {
    await safeExecution(() async {
      final usernameRegex = RegExp(r'^[a-zA-Z0-9]{3,20}$');
      if (!usernameRegex.hasMatch(username)) {
        throw Exception('Tên đăng nhập 3-20 ký tự, chỉ chứa chữ cái và số!');
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
    });
  }

  // ==========================================================
  // PHẦN 5: LUỒNG QUÊN MẬT KHẨU
  // ==========================================================

  Future<String> sendRecoveryOtp(String email) async {
    return await safeExecution(() async {
      try {
        final userCheck = await _client
            .from('users')
            .select('id, username')
            .eq('email', email)
            .maybeSingle();

        if (userCheck == null) throw Exception('Email này chưa được đăng ký.');
        if (userCheck['username'] == null) throw Exception('Email lỗi dữ liệu.');

      } catch (e) {
        if (e.toString().contains('Email này')) rethrow;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/forgot-password/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data['status'];
      throw Exception(data['message'] ?? 'Lỗi gửi OTP');
    });
  }

  Future<String> verifyRecoveryOtp(String email, String otp) async {
    return await safeExecution(() async {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/forgot-password/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'token': otp}),
      );
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return data['temp_token'] ?? '';
      }
      throw Exception(data['message'] ?? 'OTP không đúng');
    });
  }

  Future<void> resetPasswordFinal(String email, String newPassword, String tempToken) async {
    await safeExecution(() async {
      if (newPassword.length < 6) {
        throw Exception(
          'Mật khẩu quá ngắn (>6 ký tự).');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/forgot-password/reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'new_password': newPassword,
          'token': tempToken,
        }),
      );
      if (response.statusCode != 200) {
        throw Exception(
            jsonDecode(response.body)['message'] ?? 'Lỗi đổi mật khẩu');
      }
    });
  }

}