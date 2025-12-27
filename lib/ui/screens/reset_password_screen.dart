import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  final VoidCallback onBackClick;

  const ResetPasswordScreen({Key? key, required this.onBackClick}) : super(key: key);

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

  // Bước 1: Gửi OTP
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

  // Bước 2: Xác thực OTP và LẤY TOKEN
  Future<void> _verifyRecoveryOtp() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    // Kiểm tra < 6 để hỗ trợ cả mã 6 số và 8 số
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

  // Bước 3: Đổi mật khẩu (Gửi kèm Token)
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
      widget.onBackClick(); // Quay về màn hình Login
    } catch (e) {
      _showToast(e.toString().replaceAll("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- GIAO DIỆN (UI) ---

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF00CC);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text("Khôi phục tài khoản", style: TextStyle(color: Colors.black)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: _step > 0 ? () => setState(() => _step--) : widget.onBackClick,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Thanh tiến trình
              LinearProgressIndicator(
                value: (_step + 1) / 3,
                color: primaryColor,
                backgroundColor: Colors.grey[200],
                minHeight: 6,
              ),
              const SizedBox(height: 32),

              if (_step == 0) _buildStepEmail(),
              if (_step == 1) _buildStepOTP(),
              if (_step == 2) _buildStepNewPass(),

              const SizedBox(height: 16),
              if (_step == 0)
                TextButton(
                  onPressed: widget.onBackClick,
                  child: const Text("Nhớ mật khẩu? Đăng nhập ngay", style: TextStyle(color: Colors.grey)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepEmail() {
    return Column(
      children: [
        const Icon(Icons.lock_reset, size: 80, color: Color(0xFFFF00CC)),
        const SizedBox(height: 16),
        const Text("QUÊN MẬT KHẨU?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        const SizedBox(height: 8),
        const Text(
            "Nhập email liên kết với tài khoản của bạn để nhận mã xác thực.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey)
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
              labelText: "Nhập Email tài khoản",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email_outlined)
          ),
        ),
        const SizedBox(height: 24),
        _buildBtn("GỬI MÃ XÁC THỰC", _sendRecoveryOtp),
      ],
    );
  }

  // UI phần nhập OTP để chặn chữ và giới hạn ký tự
  Widget _buildStepOTP() {
    return Column(
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 80, color: Color(0xFFFF00CC)),
        const SizedBox(height: 16),
        const Text("XÁC THỰC EMAIL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        const SizedBox(height: 8),
        Text(
            "Mã xác thực đã được gửi tới:\n${_emailController.text}",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey)
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,

          // Giới hạn và chặn nhập chữ
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],

          style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
              hintText: "OTP CODE",
              counterText: "",
              border: OutlineInputBorder()
          ),
        ),
        const SizedBox(height: 24),
        _buildBtn("XÁC NHẬN MÃ", _verifyRecoveryOtp),
        TextButton(
            onPressed: () => setState(() => _step = 0),
            child: const Text("Gửi lại mã hoặc đổi Email", style: TextStyle(color: Colors.blue))
        ),
      ],
    );
  }

  Widget _buildStepNewPass() {
    return Column(
      children: [
        const Icon(Icons.security, size: 80, color: Color(0xFFFF00CC)),
        const SizedBox(height: 16),
        const Text("ĐẶT LẠI MẬT KHẨU", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        const SizedBox(height: 8),
        const Text(
            "Vui lòng nhập mật khẩu mới cho tài khoản của bạn.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey)
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _newPassController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: "Mật khẩu mới",
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _confirmPassController,
          obscureText: _obscurePassword,
          decoration: const InputDecoration(
            labelText: "Xác nhận mật khẩu mới",
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock_reset),
          ),
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
        ),
        child: _isLoading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}