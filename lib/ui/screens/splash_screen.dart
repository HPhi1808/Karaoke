import 'package:flutter/material.dart';
import '../../utils/token_manager.dart';
import '../../services/user_service.dart';
import 'login_screen.dart';

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

  Future<void> _checkAppState() async {
    final accessToken = await TokenManager.instance.getAccessToken();
    final hasToken = accessToken != null && accessToken.isNotEmpty;

    await Future.delayed(const Duration(seconds: 2));

    if (!hasToken) {
      debugPrint("SPLASH: Không tìm thấy token -> Vào chế độ Khách");
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
      return;
    }

    try {
      debugPrint("SPLASH: Tìm thấy token -> Đang kiểm tra với Server...");
      await UserService.instance.getUserProfile();
      debugPrint("SPLASH: Token hợp lệ -> Vào Home (User)");

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      debugPrint("SPLASH: Token lỗi hoặc hết hạn: $e");
      await TokenManager.instance.clearAuth();

      if (mounted) {
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
              Color(0xFF0A043C),
              Color(0xFF4B0082),
              Color(0xFFDF16BA),
              Color(0xFF2B125A),
              Color(0xFF000000),
            ],
            stops: [0.0, 0.28, 0.46, 0.76, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // [QUAN TRỌNG] Logo phải là ảnh PNG trong suốt (đã xóa nền)
              // Không cần ClipOval hay ClipRRect nữa vì nền đã trong suốt
              Image.asset(
                'assets/logo.png',
                width: 280, // Logo to rõ ràng
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 50),

              // Loading indicator màu hồng/tím trùng với tông màu logo
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