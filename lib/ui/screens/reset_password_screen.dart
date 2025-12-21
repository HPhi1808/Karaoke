import 'package:flutter/material.dart';
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
  bool _obscurePassword = true; // Để ẩn/hiện mật khẩu

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- LOGIC XỬ LÝ (Giữ nguyên logic cũ, chỉ cập nhật UI) ---

  // Bước 1: Gửi OTP khôi phục
  Future<void> _sendRecoveryOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showToast("Vui lòng nhập Email hợp lệ");
      return;
    }

    setState(() => _isLoading = true);
    try {
      final status = await AuthService.instance.sendRecoveryOtp(email);
      if (status == 'already_verified') {
        _showToast("Email đã được xác thực trước đó!");
        setState(() => _step = 2); // NHẢY BƯỚC SANG ĐỔI PASS
      } else {
        _showToast("Mã OTP đã được gửi!");
        setState(() => _step = 1);
      }
    } catch (e) {
      _showToast(e.toString().replaceAll("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Bước 2: Xác thực OTP khôi phục
  Future<void> _verifyRecoveryOtp() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (otp.length < 8) {
      _showToast("Vui lòng nhập đủ 8 số");
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Gọi verify để Server đánh dấu vào bảng email_verifications
      await AuthService.instance.verifyRecoveryOtp(email, otp);
      _showToast("Xác thực thành công!");
      setState(() => _step = 2);
    } catch (e) {
      _showToast("Mã OTP sai hoặc hết hạn!");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Bước 3: Đổi mật khẩu mới
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

    setState(() => _isLoading = true);
    try {
      // Gọi AuthService mới: Chỉ cần email và pass (Server dùng Admin API)
      await AuthService.instance.resetPasswordFinal(email, pass);

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
          // Nếu đang ở bước > 0 thì quay lại bước trước, ngược lại thoát ra login
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

              // Nội dung thay đổi theo từng bước
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

  // Widget Bước 1: Nhập Email
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

  // Widget Bước 2: Nhập OTP
  Widget _buildStepOTP() {
    return Column(
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 80, color: Color(0xFFFF00CC)),
        const SizedBox(height: 16),
        const Text("XÁC THỰC EMAIL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        const SizedBox(height: 8),
        Text(
            "Mã xác thực 8 số đã được gửi tới:\n${_emailController.text}",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey)
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 8, // Giới hạn 8 số
          style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
              hintText: "00000000",
              counterText: "", // Ẩn bộ đếm ký tự
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

  // Widget Bước 3: Đổi mật khẩu mới
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

        // Mật khẩu mới
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

        // Xác nhận mật khẩu
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

  // Helper tạo nút bấm
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