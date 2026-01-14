import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Import các màn hình
import 'ui/screens/auth/login_screen.dart';
import 'ui/screens/auth/register_screen.dart';
import 'ui/screens/auth/reset_password_screen.dart';
import 'ui/screens/navbar_screen.dart';
import 'ui/screens/songs/song_detail_screen.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/me/me_recordings_screen.dart';
import 'ui/screens/me/favorites_screen.dart';

// Import services, providers & utils
import 'services/auth_service.dart';
import 'services/notification_service.dart'; // THÊM IMPORT
import 'providers/songs_provider.dart';
import 'utils/token_manager.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // KHỞI TẠO SUPABASE
  await Supabase.initialize(
    url: 'https://wvmulnuypsovlvlnmxxi.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind2bXVsbnV5cHNvdmx2bG5teHhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzMjAwNjAsImV4cCI6MjA4MDg5NjA2MH0.viLyy9wbJiQhfyJb-HNocsgZ1aMIsKGe4y4PJsg907U',
  );
  if (!kIsWeb) {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize("a69cad20-c2e6-4d0c-88ff-bd86361148d9");
    OneSignal.Notifications.requestPermission(true);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SongsProvider()),
      ],
      child: const MyApp(),
    ),
  );
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
        title: 'KARAOKE PLUS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: const Color(0xFFFF00CC),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF00CC)),
          useMaterial3: true,
        ),
        navigatorKey: navigatorKey,
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
          '/recordings': (context) => const MeRecordingsScreen(),
          '/favorites': (context) => const FavoritesScreen(),
        },
      ),
    );
  }

  // --- HÀM XỬ LÝ ĐĂNG XUẤT ---
  void _handleLogout(BuildContext context) async {
    try {
      // RESET DỮ LIỆU THÔNG BÁO VỀ 0 NGAY LẬP TỨC
      NotificationService.instance.clear(); 
      
      await AuthService.instance.logout();
      await TokenManager.instance.clearAuth();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      debugPrint("Lỗi đăng xuất: $e");
    }
  }
}