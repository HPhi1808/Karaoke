import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  bool _isProcessing = false;
  Timer? _safetyValveTimer;
  final BaseService _baseService = BaseService();
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _safetyValveTimer = Timer(const Duration(seconds: 15), () {
      if (!_isProcessing && mounted) {
        debugPrint("SPLASH: 🚨 Safety Valve kích hoạt -> Ép về Login");
        _navigateToLogin(message: "Phản hồi quá lâu, vui lòng đăng nhập lại.");
      }
    });
    UserManager.instance.setLoginProcess(true);
    _checkAppState();
    _setupAuthListener();
  }

  @override
  void dispose() {
    _safetyValveTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  void _setupAuthListener() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!_isProcessing && (data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.tokenRefreshed)) {
        if (data.session != null) {
          debugPrint("SPLASH: 🎯 Auth Event Detected -> Vào luồng chính");
          _processLoggedInUser(data.session!);
        }
      }
    });
  }

  void _navigateToLogin({String? message}) {
    if (!mounted) return;
    _safetyValveTimer?.cancel();
    _authSubscription?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LoginScreen(
          initialErrorMessage: message,
        ),
      ),
    );
  }

  void _navigateToHome() {
    if (!mounted) return;
    _safetyValveTimer?.cancel();
    _authSubscription?.cancel();
    debugPrint("SPLASH: ✅ Mọi thứ OK -> Vào Home");
    Navigator.pushReplacementNamed(context, '/home');
  }

  Future<void> _processLoggedInUser(Session session) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      debugPrint("SPLASH: 2. Người dùng đã có Session -> Bắt đầu đồng bộ...");
      UserManager.instance.setLoginProcess(true);

      // Đồng bộ Session ID
      final sessionId = await UserManager.instance.syncSessionFromToken(session.accessToken);

      if (sessionId.isNotEmpty) {
        debugPrint("SPLASH: 🛠️ Đang ghi đè Session ID ($sessionId) lên Server...");
        await Supabase.instance.client.from('users').update({
          'last_active_at': DateTime.now().toUtc().toIso8601String(),
          'current_session_id': sessionId,
        }).eq('id', session.user.id);
      }

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
    if (_isProcessing) return;

    try {
      await Future.delayed(const Duration(milliseconds: 100));

      if (_isProcessing) return;

      final session = Supabase.instance.client.auth.currentSession;

      // Ưu tiên 1: Session RAM có sẵn
      if (session != null) {
        await _processLoggedInUser(session);
        return;
      }

      // Ưu tiên 2: Token trong Disk
      final localToken = await TokenManager.instance.getAccessToken();
      if (localToken != null && localToken.isNotEmpty) {
        try {
          final recovered = await AuthService.instance.recoverSession();
          if (recovered && Supabase.instance.client.auth.currentSession != null) {
            if (!_isProcessing) {
              await _processLoggedInUser(Supabase.instance.client.auth.currentSession!);
            }
            return;
          }
        } catch(e){
          debugPrint("SPLASH: Token lỗi -> Login");
          await AuthService.instance.logout();
          _navigateToLogin();
          return;
        }
      }

      // Ưu tiên 3: Deep Link
      debugPrint("SPLASH: Chưa thấy token -> Đợi Deep Link...");
      await Future.delayed(const Duration(seconds: 2));

      if (!_isProcessing && Supabase.instance.client.auth.currentSession == null) {
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
    if (!mounted) return;

    String errorMsg = e.toString();
    debugPrint("SPLASH: ❌ Lỗi: $errorMsg");

    if (errorMsg.contains("đăng nhập trên thiết bị khác") ||
        errorMsg.contains("bị khóa") ||
        errorMsg.contains("JWT")) {

      await AuthService.instance.logout();
      _navigateToLogin(message: errorMsg);
      return;
    }
    _navigateToLogin(message: "Phiên đăng nhập hết hạn.");
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