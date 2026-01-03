import 'package:flutter/material.dart';
import '../../utils/token_manager.dart';
import '../../utils/user_manager.dart';
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

  void _navigateToLogin({String? message}) {
    if (!mounted) return;

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

  Future<void> _checkAppState() async {
    final accessToken = await TokenManager.instance.getAccessToken();
    await Future.delayed(const Duration(seconds: 1));

    if (accessToken == null || accessToken.isEmpty) {
      debugPrint("SPLASH: Không có token -> Login");
      _navigateToLogin();
      return;
    }

    try {
      await UserService.instance.getUserProfile();
      await UserManager.instance.checkSessionValidity();

      debugPrint("SPLASH: Mọi thứ OK -> Vào Home");
      if (mounted) Navigator.pushReplacementNamed(context, '/home');

    } catch (e) {
      // 1. Token hết hạn / Lỗi Server 500 / Tài khoản bị khóa...
      // 2. HOẶC User đã bấm nút "Hủy" trên hộp thoại lỗi mạng.
      String errorMsg = e.toString();
      debugPrint("SPLASH: Lỗi check app state: $errorMsg");

      // A. Nếu lỗi nghiệp vụ nghiêm trọng -> Logout ngay
      if (errorMsg.contains("đăng nhập trên thiết bị khác") || errorMsg.contains("bị khóa")) {
        await AuthService.instance.logout();
        _navigateToLogin(message: errorMsg);
        return;
      }

      // B. Thử cứu vãn bằng Refresh Token
      try {
        debugPrint("SPLASH: Token lỗi -> Thử Refresh...");

        final recovered = await AuthService.instance.recoverSession();

        if (recovered) {
          // Refresh thành công thì check lại session lần nữa
          await UserManager.instance.checkSessionValidity();
          if (mounted) Navigator.pushReplacementNamed(context, '/home');
          return;
        }
      } catch (refreshErr) {
        debugPrint("SPLASH: Refresh thất bại -> $refreshErr");
      }

      // C. Hết cách -> Logout và về Login
      debugPrint("SPLASH: Token chết hẳn/User hủy retry -> Logout");
      await AuthService.instance.logout();

      _navigateToLogin(message: "Phiên đăng nhập hết hạn hoặc lỗi kết nối.");
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