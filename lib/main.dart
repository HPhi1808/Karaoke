import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:timeago/timeago.dart' as timeago;

// Import các màn hình
import 'ui/screens/auth/login_screen.dart';
import 'ui/screens/auth/register_screen.dart';
import 'ui/screens/auth/reset_password_screen.dart';
import 'ui/screens/navbar_screen.dart';
import 'ui/screens/songs/song_detail_screen.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/me/me_recordings_screen.dart';
import 'ui/screens/me/favorites_screen.dart';
import 'ui/screens/me/black_list_screen.dart';
import 'ui/screens/me/review_app_screen.dart';
import 'ui/screens/me/policy_and_support_screen.dart';



// Import services, providers & utils
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'providers/songs_provider.dart';
import 'providers/user_provider.dart';
import 'utils/token_manager.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("⚠️ Lỗi load .env");
  }

  // KHỞI TẠO SUPABASE
  Map<String, String> supabaseConfig = await _fetchSupabaseConfig();
  debugPrint("🚀 Đang kết nối Supabase: ${supabaseConfig['isBackup'] == 'true' ? 'BACKUP' : 'MAIN'}");

  await Supabase.initialize(
    url: supabaseConfig['url'] ?? '',
    anonKey: supabaseConfig['key']?? '',
  );
  if (!kIsWeb) {
    await _initOneSignalSafe();
  }
  timeago.setLocaleMessages('vi', timeago.ViMessages());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SongsProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()..initUser()),
      ],
      child: const MyApp(),
    ),
  );
}

Future<Map<String, String>> _fetchSupabaseConfig() async {
  final String serverUrl = dotenv.env['BASE_URL'] ?? "http://localhost:3000";

  String currentUrl = dotenv.env['SUPABASE_URL'] ?? '';
  String currentKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  String isBackup = "false";

  try {
    final response = await http.get(Uri.parse('$serverUrl/api/app-config'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      currentUrl = data['supabaseUrl'];
      currentKey = data['supabaseAnonKey'];
      isBackup = data['isBackup'].toString();
    }
  } catch (e) {
    debugPrint("⚠️ Không lấy được config từ Server, dùng config mặc định .env: $e");
  }

  return {
    'url': currentUrl,
    'key': currentKey,
    'isBackup': isBackup
  };
}

Future<void> _initOneSignalSafe() async {
  try {
    final String? appId = dotenv.env['ONE_SIGNAL_APP_ID'];
    if (appId == null || appId.trim().isEmpty) {
      debugPrint("⚠️ OneSignal: Không tìm thấy APP ID trong .env. Bỏ qua thông báo đẩy.");
      return;
    }
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(appId);
    await OneSignal.Notifications.requestPermission(true);
    debugPrint("✅ OneSignal khởi tạo thành công.");

  } catch (e) {
    debugPrint("❌ Lỗi khởi tạo OneSignal: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
      return MaterialApp(
        title: 'KARAOKE PLUS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: const Color(0xFFFF00CC),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF00CC)),
          useMaterial3: true,
        ),
        navigatorKey: navigatorKey,
        home: const SplashScreen(),

        // ĐỊNH NGHĨA ROUTES
        routes: {
          '/login': (context) => const LoginScreen(),

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
                      navigatorKey.currentState?.pop();
                    },
                  ),
                ),
              );
            },
          ),
          '/recordings': (context) => const MeRecordingsScreen(),
          '/favorites': (context) => const FavoritesScreen(),
          '/black_list': (context) => const BlackListScreen(),
          '/policy_and_support': (context) => const PolicyAndSupportScreen(),
          '/review_app': (context) => const ReviewAppScreen(),
        },
      );
  }

  // --- HÀM XỬ LÝ ĐĂNG XUẤT ---
  void _handleLogout(BuildContext context) async {
    try {
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