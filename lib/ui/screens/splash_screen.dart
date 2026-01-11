import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Import Supabase

import '../../utils/token_manager.dart';
import '../../utils/user_manager.dart';
import '../../services/user_service.dart';
import '../../services/auth_service.dart';
import '../../services/base_service.dart';
import 'auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _hasNavigated = false;
  Timer? _safetyValveTimer;
  final BaseService _baseService = BaseService();
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();

    // 1. Van an toàn: Sau 20s không vào được thì ép về login
    _safetyValveTimer = Timer(const Duration(seconds: 20), () {
      if (!_hasNavigated && mounted) {
        debugPrint("SPLASH: 🚨 Safety Valve kích hoạt -> Ép về Login");
        _navigateToLogin(message: "Phản hồi quá lâu, vui lòng đăng nhập lại.");
      }
    });

    UserManager.instance.setLoginProcess(true);

    // 2. Lắng nghe sự kiện Auth (cho Web Redirect)
    _setupAuthListener();

    // 3. Kiểm tra trạng thái App
    _checkAppState();
  }

  @override
  void dispose() {
    _safetyValveTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  void _setupAuthListener() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      // Nếu bắt được sự kiện đăng nhập thành công (từ Web Redirect)
      if (data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.tokenRefreshed) {
        if (data.session != null && !_hasNavigated) {
          debugPrint("SPLASH: 🎯 Auth Event Detected -> Vào luồng chính");
          _processLoggedInUser(data.session!);
        }
      }
    });
  }

  void _navigateToLogin({String? message}) {
    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;
    _safetyValveTimer?.cancel();
    _authSubscription?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LoginScreen(
          initialErrorMessage: message,
          onLoginSuccess: (bool isSuccess) {
            if (isSuccess) Navigator.pushReplacementNamed(context, '/home');
          },
        ),
      ),
    );
  }

  void _navigateToHome() {
    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;
    _safetyValveTimer?.cancel();
    _authSubscription?.cancel();

    debugPrint("SPLASH: ✅ Mọi thứ OK -> Vào Home");
    Navigator.pushReplacementNamed(context, '/home');
  }

  // --- LOGIC CHÍNH: Xử lý User đã đăng nhập ---
  Future<void> _processLoggedInUser(Session session) async {
    try {
      debugPrint("SPLASH: 2. Người dùng đã có Session -> Bắt đầu đồng bộ...");
      UserManager.instance.setLoginProcess(true);
      // BƯỚC 1: Lấy Session ID chuẩn từ Token (Sử dụng hàm của UserManager)
      final sessionId = await UserManager.instance.syncSessionFromToken(session.accessToken);

      if (sessionId.isNotEmpty) {
        debugPrint("SPLASH: 🛠️ Đang ghi đè Session ID ($sessionId) lên Server...");

        // BƯỚC 2: Cập nhật lên Server NGAY LẬP TỨC để tránh bị kick
        await Supabase.instance.client.from('users').update({
          'last_active_at': DateTime.now().toIso8601String(),
          'current_session_id': sessionId,
        }).eq('id', session.user.id);
      }

      // BƯỚC 3: Gọi các API kiểm tra
      await _baseService.safeExecution(() async {
        return await Future.wait([
          UserService.instance.getUserProfile(),
          UserManager.instance.init(),
        ]).timeout(const Duration(seconds: 15));
      });

      Future.delayed(const Duration(seconds: 3), () {
        UserManager.instance.setLoginProcess(false);
      });

      _navigateToHome();

    } catch (e) {
      UserManager.instance.setLoginProcess(false);
      _handleError(e);
    }
  }

  Future<void> _checkAppState() async {
    try {
      // Đợi 1 chút để Supabase Web kịp xử lý URL
      await Future.delayed(const Duration(milliseconds: 200));

      // Ưu tiên 1: Lấy session từ RAM (Supabase SDK)
      final session = Supabase.instance.client.auth.currentSession;

      if (session != null) {
        await _processLoggedInUser(session);
        return;
      }

      // Ưu tiên 2: Nếu RAM không có, check TokenManager (Disk)
      final localToken = await TokenManager.instance.getAccessToken();
      if (localToken != null && localToken.isNotEmpty) {
        // Trường hợp hãn hữu: Có token ở disk nhưng Supabase chưa load kịp
        // Ta thử recover session
        final recovered = await AuthService.instance.recoverSession();
        if (recovered && Supabase.instance.client.auth.currentSession != null) {
          await _processLoggedInUser(Supabase.instance.client.auth.currentSession!);
          return;
        }
      }

      // Nếu không tìm thấy session nào
      debugPrint("SPLASH: Chưa thấy token -> Đợi Deep Link thêm chút...");
      await Future.delayed(const Duration(seconds: 2));

      if (Supabase.instance.client.auth.currentSession == null && !_hasNavigated) {
        UserManager.instance.setLoginProcess(false);
        debugPrint("SPLASH: Timeout chờ Deep Link -> Login");
        _navigateToLogin();
      }

    } catch (e) {
      UserManager.instance.setLoginProcess(false);
      _handleError(e);
    }
  }

  Future<void> _handleError(dynamic e) async {
    if (_hasNavigated) return;

    String errorMsg = e.toString();
    debugPrint("SPLASH: ❌ Lỗi: $errorMsg");

    // Nếu lỗi liên quan đến Session/Khóa -> Logout ngay
    if (errorMsg.contains("đăng nhập trên thiết bị khác") ||
        errorMsg.contains("bị khóa") ||
        errorMsg.contains("JWT")) {

      await AuthService.instance.logout();
      _navigateToLogin(message: errorMsg);
      return;
    }

    // Các lỗi mạng khác -> Cho về Login để user thử lại
    _navigateToLogin(message: "Lỗi kết nối hoặc phiên hết hạn.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A0E7E),
              Color(0xE7500488),
              Color(0xFFB51196),
              Color(0xFF2D145C),
              Color(0xFF0A0527),
            ],
            stops: [0.0, 0.28, 0.46, 0.76, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/logo.png',
                width: 280,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 20),
              const Text(
                "KARAOKE PLUS",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 50),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF00CC)),
                strokeWidth: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}