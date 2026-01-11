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
  final Duration _throttleDuration = const Duration(minutes: 5);
  final Duration _idleThreshold = const Duration(minutes: 6);

  static const String _kSessionIdKey = 'my_current_session_id';

  // Biến Cache ID trong RAM để so sánh nhanh hơn
  String? _cachedLocalSessionId;
  bool _isLoginProcess = false;

  // THÊM HÀM NÀY ĐỂ BẬT/TẮT CHẾ ĐỘ ĐĂNG NHẬP
  void setLoginProcess(bool value) {
    _isLoginProcess = value;
    debugPrint("🛡️ User Manager: Chế độ đăng nhập = $value");
  }

  // =============================
  // PHẦN 1: INIT & DISPOSE
  // =============================
  Future<void> init() async {
    // 1. Kiểm tra user hiện tại
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      debugPrint("🛡️ User Manager: Không có user, bỏ qua init.");
      return;
    }

    // 2. Đồng bộ Session ID ngay lập tức
    await _getLocalSessionId();
    if (_cachedLocalSessionId == null) {
      await syncSessionFromToken(session.accessToken);
    }

    debugPrint("🛡️ User Manager: Đã khởi động (Heartbeat + Session ID Guard)");

    // 3. Bắt đầu các logic bảo vệ
    notifyApiActivity();
    _setupAuthListener();
    _setupAccountListener();
  }

  void dispose() {
    _keepAliveTimer?.cancel();
    _userDbSubscription?.cancel();
    _authSubscription?.cancel();
    _cachedLocalSessionId = null;
    debugPrint("🛡️ User Manager: Đã dừng.");
  }

  // ==========================================
  // PHẦN 2: HELPER (Đồng bộ ID từ Token)
  // ==========================================

  Future<String> syncSessionFromToken(String accessToken) async {
    try {
      String sessionId = "";

      // Cách 1: Decode từ JWT
      Map<String, dynamic> decodedToken = JwtDecoder.decode(accessToken);
      if (decodedToken.containsKey('session_id')) {
        sessionId = decodedToken['session_id'];
      }

      // Cách 2: Fallback nếu JWT không có
      if (sessionId.isEmpty) {
        sessionId = accessToken.hashCode.toString();
      }

      // Lưu vào RAM và Disk
      _cachedLocalSessionId = sessionId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSessionIdKey, sessionId);

      debugPrint("✅ Local Session Synced: $sessionId");
      return sessionId;
    } catch (e) {
      debugPrint("❌ Lỗi decode token: $e");
      return "";
    }
  }

  Future<String?> _getLocalSessionId() async {
    if (_cachedLocalSessionId != null) return _cachedLocalSessionId;
    final prefs = await SharedPreferences.getInstance();
    _cachedLocalSessionId = prefs.getString(_kSessionIdKey);
    return _cachedLocalSessionId;
  }

  // ==========================================
  // PHẦN 3: LOGIC CHECK TỪ SPLASH SCREEN
  // ==========================================

  Future<void> checkSessionValidity() async {
    if (AuthService.instance.isGuest) return;
    if (_isLoginProcess) {
      debugPrint("🛡️ User Manager: Đang trong quá trình login -> Bỏ qua check valid.");
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final localId = await _getLocalSessionId();

    final data = await Supabase.instance.client
        .from('users')
        .select('current_session_id, locked_until')
        .eq('id', user.id)
        .maybeSingle();

    if (data == null) {
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

  // ======================================
  // PHẦN 4: HEARTBEAT (Giữ kết nối)
  // ======================================

  void notifyApiActivity() {
    final now = DateTime.now();

    // 1. LOGIC THROTTLE
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
      debugPrint("💓 Heartbeat: Updating last_active_at...");
      _lastDbUpdate = DateTime.now();

      await Supabase.instance.client.from('users').update({
        'last_active_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);

      debugPrint("✅ Heartbeat Success");
    } catch (e) {
      debugPrint("💓 Heartbeat Error: $e");
      _lastDbUpdate = null;
    } finally {
      _isUpdating = false;
    }
  }

  // ===============================
  // PHẦN 5: REALTIME LISTENER
  // ===============================

  void _setupAccountListener() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || AuthService.instance.isGuest) return;

    _userDbSubscription?.cancel();

    debugPrint("🛡️ Realtime: Bắt đầu lắng nghe thay đổi của User...");

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

      if (localId == null || serverSessionId == null) return;
      if (localId == serverSessionId) {
        return;
      }

      if (_isLoginProcess) {
        debugPrint("🛡️ Safe: Đang login, bỏ qua xung đột (Local: $localId != Server: $serverSessionId)");
        return;
      }
      debugPrint("🚨 KICK DEVICE: Local($localId) != Server($serverSessionId)");
      _showForceLogoutDialog(
          "Kết thúc phiên",
          "Tài khoản đã được đăng nhập trên thiết bị khác!"
      );
    }, onError: (err) {
      debugPrint("🔥 Realtime Error: $err");
    });
  }

  // =========================================
  // PHẦN 6: AUTH LISTENER & UI HANDLING
  // =========================================

  void _setupAuthListener() {
    _authSubscription?.cancel();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        dispose();
      }
    });
  }

  Future<void> _showForceLogoutDialog(String title, String message) async {
    dispose();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionIdKey);
    _cachedLocalSessionId = null;

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
                  Navigator.of(ctx).pop();
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