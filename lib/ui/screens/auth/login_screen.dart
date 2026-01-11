import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  final Function(bool) onLoginSuccess;
  final String? initialErrorMessage;

  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
    this.initialErrorMessage,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  StreamSubscription<AuthState>? _authSubscription;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isManualLogin = false;

  int _failedAttempts = 0;
  bool _isLocked = false;
  int _countdown = 0;
  Timer? _lockoutTimer;
  static const int maxAttempts = 5;
  static const int lockTime = 60;

  @override
  void initState() {
    super.initState();
    if (widget.initialErrorMessage != null && widget.initialErrorMessage!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showToast(widget.initialErrorMessage!, isError: true);
      });
    }
    final String? startupUserId = Supabase.instance.client.auth.currentUser?.id;
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      // Nếu có session và sự kiện là đăng nhập thành công
      if (session != null && (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.tokenRefreshed)) {
        if (session.user.isAnonymous) {
          debugPrint("🙈 LoginScreen: Phát hiện Guest đang chạy ngầm -> Không tự động Redirect.");
          return;
        }
        if (_isManualLogin) return;
        if (startupUserId != null && session.user.id == startupUserId) {
          return;
        }
        if (mounted) {
          debugPrint("✅ Phát hiện phiên đăng nhập (Web Redirect Success)");

          if (kIsWeb) {
            try {
              await AuthService.instance.finalizeWebLogin(session);
            } catch (e) {
              debugPrint("⚠️ Lỗi finalize login web: $e");
            }
          }
          widget.onLoginSuccess(true);
        }
      }
    });
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _authSubscription?.cancel();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: isError ? Colors.redAccent : Colors.black87,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Hàm bắt đầu khóa tạm thời
  void _startLockout() {
    setState(() {
      _isLocked = true;
      _isLoading = false;
      _countdown = lockTime;
    });

    _showToast("Bạn đã nhập sai quá nhiều lần. Vui lòng thử lại sau $_countdown giây.", isError: true);

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          // Mở khóa
          _isLocked = false;
          _failedAttempts = 0;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _handleLogin() async {
    if (_isLocked || _isLoading) return;

    final identifier = _identifierController.text.trim();
    final password = _passwordController.text.trim();

    if (identifier.isEmpty || password.isEmpty) {
      _showToast("Vui lòng nhập tài khoản và mật khẩu", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Future.delayed(const Duration(milliseconds: 500));

      await AuthService.instance
          .login(identifier: identifier, password: password);

      _showToast("Đăng nhập thành công!");
      _failedAttempts = 0;
      widget.onLoginSuccess(true);

    } catch (e) {
      _failedAttempts++;

      String msg = e.toString();
      if (msg.contains("Exception:")) {
        msg = msg.replaceAll("Exception:", "").trim();
      }

      // Logic khóa nếu sai quá nhiều
      if (_failedAttempts >= maxAttempts) {
        _startLockout();
      } else {
        await Future.delayed(const Duration(milliseconds: 1500));
        _showToast(msg, isError: true);

        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _handleGoogleLogin() async {
    if (_isLocked || _isLoading) return;
    _isManualLogin = true;
    setState(() => _isLoading = true);

    try {
      await AuthService.instance.loginWithGoogle();
      if (kIsWeb) {
        return;
      }

      // 📱 NẾU LÀ MOBILE: Chạy tiếp
      _showToast("Đăng nhập Google thành công!");
      _failedAttempts = 0;
      widget.onLoginSuccess(true);

    } catch (e) {
      _isManualLogin = false;
      String msg = e.toString();
      if (msg.contains("Exception:")) {
        msg = msg.replaceAll("Exception:", "").trim();
      }
      if (!msg.toLowerCase().contains("hủy") && !msg.toLowerCase().contains("canceled")) {
        _showToast("Lỗi Google: $msg", isError: true);
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF00CC);

    final bool canInput = !_isLoading && !_isLocked;

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: Colors.white,
        canvasColor: Colors.white,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        )
                      ],
                      gradient: const LinearGradient(
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
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --- INPUT FIELDS ---
                  TextField(
                    controller: _identifierController,
                    enabled: canInput,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      labelText: "Email hoặc Tên đăng nhập",
                      labelStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: Icon(Icons.person_outline, color: Colors.grey[600]),
                      filled: true,
                      fillColor: canInput ? Colors.grey[100] : Colors.grey[200],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.auto,
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _passwordController,
                    enabled: canInput,
                    obscureText: _obscurePassword,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      labelText: "Mật khẩu",
                      labelStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: Icon(Icons.lock_outline, color: Colors.grey[600]),
                      filled: true,
                      fillColor: canInput ? Colors.grey[100] : Colors.grey[200],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility : Icons.visibility_off,
                          color: Colors.grey[600],
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),

                  // Hiển thị cảnh báo nếu nhập sai
                  if (_failedAttempts > 0 && !_isLocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, right: 8.0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "Còn lại ${maxAttempts - _failedAttempts} lần thử",
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: canInput ? () {
                        Navigator.pushNamed(context, '/reset_password');
                      } : null,
                      child: Text("Quên mật khẩu?",
                          style: TextStyle(
                              color: canInput ? Colors.grey[700] : Colors.grey[400],
                              fontWeight: FontWeight.w600
                          )),
                    ),
                  ),
                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: (_isLoading || _isLocked) ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isLocked ? Colors.grey : primaryColor,
                        disabledBackgroundColor: _isLocked ? Colors.grey[400] : primaryColor.withValues(alpha: 0.6),
                        elevation: 3,
                        shadowColor: primaryColor.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(color: Colors.white))
                          : Text(
                          _isLocked
                              ? "Vui lòng chờ ${_countdown}s"
                              : "ĐĂNG NHẬP",
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey[300])),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text("Hoặc", style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                      ),
                      Expanded(child: Divider(color: Colors.grey[300])),
                    ],
                  ),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: canInput ? _handleGoogleLogin : null,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset('assets/google.png', height: 24,
                              errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.g_mobiledata, size: 30, color: Colors.blue)
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            "Tiếp tục bằng Google",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  TextButton(
                    onPressed: canInput ? () async {
                      _isManualLogin = true;
                      setState(() => _isLoading = true);
                      try {
                        await AuthService.instance.loginAsGuest();
                        if (context.mounted) {
                          widget.onLoginSuccess(true);
                        }
                      } catch (e) {
                        _isManualLogin = false;
                        _showToast("Lỗi đăng nhập khách");
                      }finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    } : null,
                    child: Text("Đăng nhập bằng tài khoản khách",
                        style: TextStyle(color: canInput ? Colors.black54 : Colors.grey[400])
                    ),
                  ),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Chưa có tài khoản? ",
                          style: TextStyle(color: canInput ? Colors.black54 : Colors.grey[400])
                      ),
                      TextButton(
                        onPressed: canInput ? () {
                          Navigator.pushNamed(context, '/register');
                        } : null,
                        child: Text("Đăng ký ngay",
                            style: TextStyle(
                                color: canInput ? const Color(0xFFFF00CC) : Colors.grey,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}