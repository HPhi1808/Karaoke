import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Import các màn hình
import 'ui/screens/login_screen.dart';
import 'ui/screens/register_screen.dart';
import 'ui/screens/reset_password_screen.dart';
import 'ui/screens/navbar_screen.dart';
import 'ui/screens/song_detail_screen.dart';
import 'ui/screens/splash_screen.dart';

// Import services, providers & utils
import 'services/auth_service.dart';
import 'providers/songs_provider.dart';
import 'utils/token_manager.dart';

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
        ChangeNotifierProvider(create: (_) => SongsProvider()),
      ],
      child: MaterialApp(
        title: 'KARAOKE ENTERTAINMENT PLUS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: const Color(0xFFFF00CC),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF00CC)),
          useMaterial3: true,
        ),

        // Màn hình khởi động
        home: const SplashScreen(),

        // ĐỊNH NGHĨA ROUTES
        routes: {
          '/login': (context) => LoginScreen(
            onLoginSuccess: (isSuccess) {
              if (isSuccess) {
                Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
              }
            },
          ),

          '/register': (context) => RegisterScreen(
            onRegisterSuccess: () {
              Navigator.of(context).pop();
            },
            onBackClick: () => Navigator.of(context).pop(),
          ),

          '/reset_password': (context) => ResetPasswordScreen(
            onBackClick: () => Navigator.of(context).pop(),
          ),

          '/home': (context) => NavbarScreen(
            onLogout: () => _handleLogout(context),
            onSongClick: (song) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SongDetailScreen(
                    songId: song.id,
                    onBack: () {
                      Navigator.pop(context);
                    },
                  ),
                ),
              );
            },
          ),
        },
      ),
    );
  }

  // --- HÀM XỬ LÝ ĐĂNG XUẤT ---
  void _handleLogout(BuildContext context) async {
    try {
      // 1. Đăng xuất khỏi Supabase
      await AuthService.instance.logout();

      // 2. Xóa sạch Token trong bộ nhớ máy
      await TokenManager.instance.clearAuth();

      if (context.mounted) {
        // 3. Quay về màn hình Login và xóa hết lịch sử
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      debugPrint("Lỗi đăng xuất: $e");
    }
  }
}