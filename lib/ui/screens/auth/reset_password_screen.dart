import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/auth_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  final VoidCallback onBackClick;

  const ResetPasswordScreen({super.key, required this.onBackClick});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPassController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();

  // State variables
  int _step = 0; // 0: Email, 1: OTP, 2: New Password
  bool _isLoading = false;
  bool _obscurePassword = true;

  String? _tempToken;

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- LOGIC XỬ LÝ ---
  Future<void> _sendRecoveryOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showToast("Vui lòng nhập Email hợp lệ");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService.instance.sendRecoveryOtp(email);
      _showToast("Mã OTP đã được gửi!");
      setState(() => _step = 1);

    } catch (e) {
      _showToast(e.toString().replaceAll("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyRecoveryOtp() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (otp.length < 6) {
      _showToast("Vui lòng nhập đủ mã OTP");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService.instance.verifyRecoveryOtp(email, otp);
      setState(() {
        _tempToken = otp;
        _step = 2;
      });
      _showToast("Xác thực thành công!");

    } catch (e) {
      _showToast(e.toString().replaceAll("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleReset() async {
    final email = _emailController.text.trim();
    final pass = _newPassController.text;
    final confirmPass = _confirmPassController.text;

    if (pass.length < 6) {
      _showToast("Mật khẩu tối thiểu 6 ký tự");
      return;
    }
    if (pass != confirmPass) {
      _showToast("Mật khẩu xác nhận không khớp!");
      return;
    }

    if (_tempToken == null) {
      _showToast("Lỗi xác thực phiên làm việc. Vui lòng thử lại từ đầu.");
      setState(() => _step = 0);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService.instance.resetPasswordFinal(
          email,
          pass,
          _tempToken!
      );

      _showToast("Đổi mật khẩu thành công! Hãy đăng nhập lại.");
      widget.onBackClick();
    } catch (e) {
      _showToast(e.toString().replaceAll("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- HELPER STYLE INPUT ---
  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[600]),
      prefixIcon: Icon(icon, color: Colors.grey[600]),
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
    );
  }

  // --- GIAO DIỆN (UI) ---
  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF00CC);

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: Colors.white,
        canvasColor: Colors.white,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: _step > 0 ? () => setState(() => _step--) : widget.onBackClick,
                    ),
                    const Expanded(
                      child: Text(
                        "Khôi phục tài khoản",
                        style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (_step + 1) / 3,
                          color: primaryColor,
                          backgroundColor: Colors.grey[200],
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 32),

                      if (_step == 0) _buildStepEmail(),
                      if (_step == 1) _buildStepOTP(),
                      if (_step == 2) _buildStepNewPass(),

                      const SizedBox(height: 16),
                      if (_step == 0)
                        TextButton(
                          onPressed: widget.onBackClick,
                          child: Text("Nhớ mật khẩu? Đăng nhập ngay",
                              style: TextStyle(color: Colors.grey[700])),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepEmail() {
    const primaryColor = Color(0xFFFF00CC);
    return Column(
      children: [
        const Icon(Icons.lock_reset, size: 80, color: primaryColor),
        const SizedBox(height: 16),
        const Text("QUÊN MẬT KHẨU?",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black)),
        const SizedBox(height: 8),
        Text(
            "Nhập email liên kết với tài khoản của bạn để nhận mã xác thực.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600])
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.black87),
          decoration: _inputDecoration("Nhập Email tài khoản", Icons.email_outlined),
        ),
        const SizedBox(height: 24),
        _buildBtn("GỬI MÃ XÁC THỰC", _sendRecoveryOtp),
      ],
    );
  }

  Widget _buildStepOTP() {
    const primaryColor = Color(0xFFFF00CC);
    return Column(
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 80, color: primaryColor),
        const SizedBox(height: 16),
        const Text("XÁC THỰC EMAIL",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black)),
        const SizedBox(height: 8),
        Text(
            "Mã xác thực đã được gửi tới:\n${_emailController.text}",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600])
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold, color: Colors.black87),
          decoration: InputDecoration(
            hintText: "OTP CODE",
            counterText: "",
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 24),
        _buildBtn("XÁC NHẬN MÃ", _verifyRecoveryOtp),
        TextButton(
            onPressed: () => setState(() => _step = 0),
            child: const Text("Gửi lại mã hoặc đổi Email", style: TextStyle(color: Color(0xFFFF00CC)))
        ),
      ],
    );
  }

  Widget _buildStepNewPass() {
    const primaryColor = Color(0xFFFF00CC);
    return Column(
      children: [
        const Icon(Icons.security, size: 80, color: primaryColor),
        const SizedBox(height: 16),
        const Text("ĐẶT LẠI MẬT KHẨU",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black)),
        const SizedBox(height: 8),
        Text(
            "Vui lòng nhập mật khẩu mới cho tài khoản của bạn.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600])
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _newPassController,
          obscureText: _obscurePassword,
          style: const TextStyle(color: Colors.black87),
          decoration: _inputDecoration("Mật khẩu mới", Icons.lock_outline).copyWith(
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off, color: Colors.grey[600]),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _confirmPassController,
          obscureText: _obscurePassword,
          style: const TextStyle(color: Colors.black87),
          decoration: _inputDecoration("Xác nhận mật khẩu mới", Icons.lock_reset),
        ),
        const SizedBox(height: 32),
        _buildBtn("ĐỔI MẬT KHẨU", _handleReset),
      ],
    );
  }

  Widget _buildBtn(String text, VoidCallback onPres) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPres,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF00CC),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
        ),
        child: _isLoading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}