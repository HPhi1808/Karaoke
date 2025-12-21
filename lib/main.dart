import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Import các màn hình
import 'ui/screens/login_screen.dart';
import 'ui/screens/register_screen.dart';
import 'ui/screens/reset_password_screen.dart';
import 'ui/screens/navbar_screen.dart';
// import 'ui/screens/song_detail_screen.dart';

// Import services & providers
import 'services/auth_service.dart';
import 'providers/home_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // KHỞI TẠO SUPABASE
  await Supabase.initialize(
    url: 'https://wvmulnuypsovlvlnmxxi.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind2bXVsbnV5cHNvdmx2bG5teHhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMjAwNjAsImV4cCI6MjA4MDg5NjA2MH0.viLyy9wbJiQhfyJb-HNocsgZ1aMIsKGe4y4PJsg907U',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeProvider()),
      ],
      child: MaterialApp(
        title: 'Karaoke App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: const Color(0xFFFF00CC),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF00CC)),
          useMaterial3: true,
        ),

        // Màn hình khởi động: Kiểm tra Session đơn giản
        home: const AuthWrapper(),

        // ĐỊNH NGHĨA ROUTES
        routes: {
          '/login': (context) => LoginScreen(
            onLoginSuccess: (isSuccess) {
              Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
            },
            onNavigateToRegister: () => Navigator.of(context).pushNamed('/register'),
            onNavigateToResetPassword: () => Navigator.of(context).pushNamed('/reset_password'),
          ),

          '/register': (context) => RegisterScreen(
            onRegisterSuccess: () {
              // Vì đã tắt confirm email, đăng ký xong là coi như đăng nhập luôn
              // Ta có thể chuyển thẳng vào Home hoặc về Login tùy ý.
              // Ở đây cho về Login để người dùng nhập lại cho quen tay,
              // hoặc sửa thành pushNamedAndRemoveUntil('/home') nếu muốn vào luôn.
              Navigator.of(context).pop();
            },
            onBackClick: () => Navigator.of(context).pop(),
          ),

          '/reset_password': (context) => ResetPasswordScreen(
            onBackClick: () => Navigator.of(context).pop(),
          ),

          '/home': (context) => NavbarScreen(
            onLogout: () => _handleLogout(context),
            onSongClick: (songId) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Mở bài hát ID: $songId")));
            },
          ),
        },
      ),
    );
  }

  // --- HÀM XỬ LÝ ĐĂNG XUẤT ---
  void _handleLogout(BuildContext context) async {
    try {
      await AuthService.instance.logout();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      print("Lỗi đăng xuất: $e");
    }
  }
}

// --- WIDGET AUTH WRAPPER (ĐƠN GIẢN HÓA) ---
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    // Delay nhẹ để tạo hiệu ứng Splash
    await Future.delayed(const Duration(seconds: 1));

    // CHỈ KIỂM TRA: Có Session hay chưa? (Không quan tâm email confirm)
    final session = Supabase.instance.client.auth.currentSession;

    if (!mounted) return;

    if (session != null) {
      // Đã có token -> Vào Home luôn
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      // Chưa có token -> Về Login
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFFFF00CC)),
      ),
    );
  }
}