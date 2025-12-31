import 'package:flutter/material.dart';
import '../../utils/token_manager.dart';
import '../../services/user_service.dart';
import '../../services/auth_service.dart';
import 'auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAppState();
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LoginScreen(
          onLoginSuccess: (bool isSuccess) {
            if (isSuccess) {
              Navigator.pushReplacementNamed(context, '/home');
            }
          },
        ),
      ),
    );
  }

  Future<void> _checkAppState() async {
    final accessToken = await TokenManager.instance.getAccessToken();
    final hasToken = accessToken != null && accessToken.isNotEmpty;

    await Future.delayed(const Duration(seconds: 1));

    // === TRƯỜNG HỢP 1 ===
    if (!hasToken) {
      debugPrint("SPLASH: Không có token -> Login");
      _navigateToLogin();
      return;
    }

    // === TRƯỜNG HỢP 2 ===
    try {
      debugPrint("SPLASH: Có token -> Đang kiểm tra profile...");

      // Thử lấy profile user
      await UserService.instance.getUserProfile();

      // Nếu không lỗi -> Vào Home
      debugPrint("SPLASH: Token OK -> Home");
      if (mounted) Navigator.pushReplacementNamed(context, '/home');

    } catch (e) {
      debugPrint("SPLASH: Lỗi lấy profile (có thể hết hạn): $e");

      try {
        debugPrint("SPLASH: Đang thử làm mới phiên đăng nhập (Refresh Token)...");

        // Gọi hàm phục hồi session
        final bool recovered = await AuthService.instance.recoverSession();

        if (recovered) {
          debugPrint("SPLASH: Refresh thành công -> Vào Home");
          if (mounted) Navigator.pushReplacementNamed(context, '/home');
          return;
        }
      } catch (refreshError) {
        debugPrint("SPLASH: Refresh thất bại: $refreshError");
      }

      // === TRƯỜNG HỢP 3 ===
      debugPrint("SPLASH: Token chết hẳn -> Logout và về Login");
      await AuthService.instance.logout();
      _navigateToLogin();
    }
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
                "KARAOKE ENTERTAINMENT PLUS",
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