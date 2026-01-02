import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../services/auth_service.dart';
import '../main.dart';

class UserManager {
  static final UserManager instance = UserManager._internal();
  UserManager._internal();

  // --- VARIABLES ---
  StreamSubscription<List<Map<String, dynamic>>>? _userDbSubscription;
  StreamSubscription<AuthState>? _authSubscription;

  Timer? _keepAliveTimer;
  DateTime? _lastDbUpdate;
  bool _isUpdating = false;

  // Cấu hình Heartbeat
  // Throttle: Tần suất update tối đa khi user đang thao tác liên tục (tránh spam server)
  final Duration _throttleDuration = const Duration(minutes: 5);
  // Idle: Sau bao lâu không thao tác thì tự động bắn heartbeat duy trì
  final Duration _idleThreshold = const Duration(minutes: 6);

  static const String _kSessionIdKey = 'my_current_session_id';

  // Biến Cache ID trong RAM để so sánh nhanh hơn
  String? _cachedLocalSessionId;

  // ============================================================
  // PHẦN 1: INIT & DISPOSE
  // ============================================================
  Future<void> init() async {
    // 1. Kiểm tra user hiện tại
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      print("🛡️ User Manager: Không có user, bỏ qua init.");
      return;
    }

    // 2. Đồng bộ Session ID ngay lập tức
    // Ưu tiên lấy từ RAM/Disk trước nếu có, nếu không thì lấy từ Token mới
    await _getLocalSessionId();
    if (_cachedLocalSessionId == null) {
      await syncSessionFromToken(session.accessToken);
    }

    print("🛡️ User Manager: Đã khởi động (Heartbeat + Session ID Guard)");

    // 3. Bắt đầu các logic bảo vệ
    notifyApiActivity(); // Bắn phát đầu tiên
    _setupAuthListener(); // Lắng nghe đăng xuất
    _setupAccountListener(); // Lắng nghe đá thiết bị
  }

  void dispose() {
    _keepAliveTimer?.cancel();
    _userDbSubscription?.cancel();
    _authSubscription?.cancel();
    _cachedLocalSessionId = null;
    print("🛡️ User Manager: Đã dừng.");
  }

  // ============================================================
  // PHẦN 2: HELPER (Đồng bộ ID từ Token)
  // ============================================================

  Future<String> syncSessionFromToken(String accessToken) async {
    try {
      String sessionId = "";

      // Cách 1: Decode từ JWT (như yêu cầu của bạn)
      Map<String, dynamic> decodedToken = JwtDecoder.decode(accessToken);
      if (decodedToken.containsKey('session_id')) {
        sessionId = decodedToken['session_id'];
      }

      // Cách 2: Fallback nếu JWT không có (An toàn hơn)
      if (sessionId.isEmpty) {
        sessionId = accessToken.hashCode.toString();
      }

      // Lưu vào RAM và Disk
      _cachedLocalSessionId = sessionId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSessionIdKey, sessionId);

      print("✅ Local Session Synced: $sessionId");
      return sessionId;
    } catch (e) {
      print("❌ Lỗi decode token: $e");
      return "";
    }
  }

  Future<String?> _getLocalSessionId() async {
    if (_cachedLocalSessionId != null) return _cachedLocalSessionId;
    final prefs = await SharedPreferences.getInstance();
    _cachedLocalSessionId = prefs.getString(_kSessionIdKey);
    return _cachedLocalSessionId;
  }

  // ============================================================
  // PHẦN 3: LOGIC CHECK TỪ SPLASH SCREEN
  // ============================================================

  Future<void> checkSessionValidity() async {
    if (AuthService.instance.isGuest) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final localId = await _getLocalSessionId();

    // Lấy thông tin mới nhất từ Server
    final data = await Supabase.instance.client
        .from('users')
        .select('current_session_id, locked_until')
        .eq('id', user.id)
        .maybeSingle();

    if (data == null) {
      // Có thể user chưa được tạo trong bảng users, bỏ qua hoặc throw tùy logic app
      return;
    }

    // 1. Check bị khóa
    final lockedUntilStr = data['locked_until'];
    if (lockedUntilStr != null) {
      DateTime lockedTime = DateTime.parse(lockedUntilStr).toLocal();
      if (lockedTime.isAfter(DateTime.now())) {
        throw "Tài khoản bị khóa đến ${lockedTime.toString()}";
      }
    }

    // 2. Check Session ID (Logic đá thiết bị)
    final serverSessionId = data['current_session_id'];

    if (serverSessionId != null && localId != null) {
      if (serverSessionId != localId) {
        throw "Tài khoản của bạn đã được đăng nhập trên thiết bị khác.";
      }
    }
  }

  // ============================================================
  // PHẦN 4: HEARTBEAT (Giữ kết nối)
  // ============================================================

  void notifyApiActivity() {
    final now = DateTime.now();

    // 1. LOGIC THROTTLE
    // Nếu chưa từng update HOẶC đã quá thời gian throttle -> Update ngay
    if (_lastDbUpdate == null || now.difference(_lastDbUpdate!) > _throttleDuration) {
      _sendKeepAliveHeartbeat();
    }

    // 2. LOGIC DEBOUNCE (Reset timer idle)
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer(_idleThreshold, () {
      _sendKeepAliveHeartbeat();
      notifyApiActivity();
    });
  }

  Future<void> _sendKeepAliveHeartbeat() async {
    if (_isUpdating) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _isUpdating = true;

    try {
      print("💓 Heartbeat: Updating last_active_at...");
      _lastDbUpdate = DateTime.now(); // Cập nhật local trước để chặn throttle ngay lập tức

      await Supabase.instance.client.from('users').update({
        'last_active_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);

      print("✅ Heartbeat Success");
    } catch (e) {
      print("💓 Heartbeat Error: $e");
      _lastDbUpdate = null; // Reset nếu lỗi để lần sau thử lại ngay
    } finally {
      _isUpdating = false;
    }
  }

  // ============================================================
  // PHẦN 5: REALTIME LISTENER
  // ============================================================

  void _setupAccountListener() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || AuthService.instance.isGuest) return;

    // Hủy subscription cũ nếu có để tránh trùng lặp
    _userDbSubscription?.cancel();

    print("🛡️ Realtime: Bắt đầu lắng nghe thay đổi của User...");

    _userDbSubscription = Supabase.instance.client
        .from('users')
        .stream(primaryKey: ['id'])
        .eq('id', user.id)
        .listen((List<Map<String, dynamic>> data) async {

      if (data.isEmpty) return;

      final userData = data.first;

      // 1. Check khóa tài khoản (Ưu tiên cao nhất)
      final lockedUntilStr = userData['locked_until'];
      if (lockedUntilStr != null) {
        DateTime lockedTime = DateTime.parse(lockedUntilStr).toLocal();
        if (lockedTime.isAfter(DateTime.now())) {
          _showForceLogoutDialog(
              "Tài khoản bị khóa",
              "Tài khoản bị khóa đến ${lockedTime.toString()}"
          );
          return;
        }
      }

      // 2. Check Session ID
      final serverSessionId = userData['current_session_id'] as String?;
      String? localId = await _getLocalSessionId();

      // Chỉ check nếu cả 2 đều có giá trị
      if (localId != null && serverSessionId != null && localId.isNotEmpty) {
        if (localId != serverSessionId) {
          print("🚨 KICK DEVICE: Local($localId) != Server($serverSessionId)");
          _showForceLogoutDialog(
              "Kết thúc phiên",
              "Tài khoản đã được đăng nhập trên thiết bị khác!"
          );
        }
      }
    }, onError: (err) {
      print("🔥 Realtime Error: $err");
    });
  }

  // ============================================================
  // PHẦN 6: AUTH LISTENER & UI HANDLING
  // ============================================================

  void _setupAuthListener() {
    _authSubscription?.cancel();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        dispose();
      }
    });
  }

  Future<void> _showForceLogoutDialog(String title, String message) async {
    // Ngắt kết nối ngay lập tức
    dispose();

    // Xóa Session ID
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionIdKey);
    _cachedLocalSessionId = null;

    // Đăng xuất khỏi Supabase
    try { await AuthService.instance.logout(); } catch (_) {}

    final context = navigatorKey.currentContext;

    if (context != null && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  // Đóng dialog
                  Navigator.of(ctx).pop();
                  // Chuyển về màn Login và xóa sạch stack
                  navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
                },
                child: const Text("Đồng ý", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      );
    } else {
      navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }
}