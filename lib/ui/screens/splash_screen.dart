import 'package:flutter/material.dart';
import '../../utils/token_manager.dart';
import '../../services/user_service.dart';
// import '../../services/auth_service.dart';
import 'home_screen.dart';
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
    // 1. Lấy token
    final accessToken = await TokenManager.instance.getAccessToken();
    final hasToken = accessToken != null && accessToken.isNotEmpty;

    // Delay giả lập
    await Future.delayed(const Duration(seconds: 1));

    if (!hasToken) {
      // === TRƯỜNG HỢP 1: KHÁCH ===
      debugPrint("SPLASH: Không tìm thấy token -> Vào chế độ Khách");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen(onSongClick: (song){})),
        );
      }
      return;
    }

    // === TRƯỜNG HỢP 2: CÓ TOKEN ===
    try {
      debugPrint("SPLASH: Tìm thấy token -> Đang kiểm tra với Server...");
      await UserService.instance.getUserProfile();
      debugPrint("SPLASH: Token hợp lệ -> Vào Home (User)");

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen(onSongClick: (song){})),
        );
      }
    } catch (e) {
      // === TRƯỜNG HỢP 3: TOKEN HẾT HẠN ===
      debugPrint("SPLASH: Token lỗi hoặc hết hạn: $e");
      await TokenManager.instance.clearAuth();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            // Gọi LoginScreen mới
            builder: (context) => LoginScreen(
              onLoginSuccess: (bool isSuccess) {
                if (isSuccess) {
                  Navigator.pushReplacementNamed(context, '/home');
                }
              },
            ),
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.music_note, size: 80, color: Color(0xFFFF00CC)),
            SizedBox(height: 20),
            Text(
                "Karaoke Entertainment Plus",
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87
                )
            ),
            SizedBox(height: 40),
            CircularProgressIndicator(color: Color(0xFFFF00CC)),
          ],
        ),
      ),
    );
  }
}