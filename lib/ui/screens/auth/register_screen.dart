import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  final VoidCallback onRegisterSuccess;
  final VoidCallback onBackClick;

  const RegisterScreen({super.key, required this.onRegisterSuccess, required this.onBackClick});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  // State Variables
  int _currentStep = 0; // 0: Email, 1: OTP, 2: Info
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Dữ liệu cho bước 3
  String _selectedGender = "Nam";
  String? _selectedRegion;

  final List<String> _provinces = [
    "TP Hà Nội", "TP Huế", "Quảng Ninh", "Cao Bằng", "Lạng Sơn", "Lai Châu",
    "Điện Biên", "Sơn La", "Thanh Hóa", "Nghệ An", "Hà Tĩnh", "Tuyên Quang",
    "Lào Cai", "Thái Nguyên", "Phú Thọ", "Bắc Ninh", "Hưng Yên", "TP Hải Phòng",
    "Ninh Bình", "Quảng Trị", "TP Đà Nẵng", "Quảng Ngãi", "Gia Lai", "Khánh Hòa",
    "Lâm Đồng", "Đắk Lắk", "TP Hồ Chí Minh", "Đồng Nai", "Tây Ninh", "TP Cần Thơ",
    "Vĩnh Long", "Đồng Tháp", "Cà Mau", "An Giang"
  ];

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- LOGIC ---
  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showToast("Vui lòng nhập Email hợp lệ");
      return;
    }

    setState(() => _isLoading = true);
    try {
      final String status = await AuthService.instance.sendRegisterOtp(email);

      if (status == 'already_verified') {
        _showToast("Email đã được xác thực. Vui lòng điền thông tin!");
        setState(() => _currentStep = 2);
      } else {
        _showToast("Mã OTP đã được gửi!");
        setState(() => _currentStep = 1);
      }
    } catch (e) {
      _showToast(e.toString().replaceAll("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();

    if (otp.length < 6) {
      _showToast("Vui lòng nhập đủ mã OTP");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService.instance.verifyRegisterOtp(_emailController.text.trim(), otp);
      _showToast("Xác thực thành công!");
      setState(() => _currentStep = 2);
    } catch (e) {
      _showToast("Mã OTP không đúng hoặc đã hết hạn");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completeRegister() async {
    final username = _usernameController.text.trim();
    final fullName = _fullNameController.text.trim();
    final password = _passwordController.text;
    final confirmPass = _confirmPasswordController.text;

    // 1. Check trống
    if (username.isEmpty || fullName.isEmpty || password.isEmpty) {
      _showToast("Vui lòng điền đủ thông tin");
      return;
    }

    // 2.Check độ dài mật khẩu (Tối thiểu 6 ký tự)
    if (password.length < 6) {
      _showToast("Mật khẩu phải có tối thiểu 6 ký tự");
      return;
    }

    // 3. Check mật khẩu xác nhận
    if (password != confirmPass) {
      _showToast("Mật khẩu xác nhận không khớp");
      return;
    }

    // 4. Check chọn Tỉnh/Thành
    if (_selectedRegion == null) {
      _showToast("Vui lòng chọn Tỉnh/Thành phố");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService.instance.completeRegister(
        email: _emailController.text.trim(),
        username: username,
        fullName: fullName,
        password: password,
        gender: _selectedGender,
        region: _selectedRegion!,
      );

      _showToast("Đăng ký thành công!");
      widget.onRegisterSuccess();
    } catch (e) {
      _showToast(e.toString().replaceAll("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- HÀM HELPER STYLE INPUT ---
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
                      onPressed: _currentStep > 0 ? () => setState(() => _currentStep--) : widget.onBackClick,
                    ),
                    const Expanded(
                      child: Text(
                        "Đăng ký tài khoản",
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (_currentStep + 1) / 3,
                          color: primaryColor,
                          backgroundColor: Colors.grey[200],
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 32),

                      if (_currentStep == 0) _buildStepEmail(),
                      if (_currentStep == 1) _buildStepOTP(),
                      if (_currentStep == 2) _buildStepForm(),

                      const SizedBox(height: 16),
                      if (_currentStep == 0)
                        TextButton(
                          onPressed: widget.onBackClick,
                          child: Text("Đã có tài khoản? Đăng nhập",
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

  // Widget Bước 1: Email
  Widget _buildStepEmail() {
    const primaryColor = Color(0xFFFF00CC);
    return Column(
      children: [
        const Icon(Icons.email_outlined, size: 80, color: primaryColor),
        const SizedBox(height: 16),
        const Text("XÁC THỰC EMAIL",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black)),
        const SizedBox(height: 8),
        Text("Chúng tôi sẽ gửi mã OTP để xác minh email của bạn",
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 32),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.black87),
          decoration: _inputDecoration("Nhập Email đăng ký", Icons.mail),
        ),
        const SizedBox(height: 24),
        _buildButton("GỬI MÃ OTP", _sendOtp),
      ],
    );
  }

  // Widget Bước 2: OTP
  Widget _buildStepOTP() {
    const primaryColor = Color(0xFFFF00CC);
    return Column(
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 80, color: primaryColor),
        const SizedBox(height: 16),
        const Text("NHẬP MÃ OTP",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black)),
        const SizedBox(height: 8),
        Text("Mã xác thực đã được gửi tới:\n${_emailController.text}",
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 32),

        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold, color: Colors.black87),
          decoration: InputDecoration(
            hintText: "OTP Code",
            counterText: "",
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 24),
        _buildButton("XÁC NHẬN MÃ", _verifyOtp),
        TextButton(
            onPressed: () => setState(() => _currentStep = 0),
            child: const Text("Sửa lại Email", style: TextStyle(color: Color(0xFFFF00CC)))
        ),
      ],
    );
  }

  // Widget Bước 3: Form
  Widget _buildStepForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(child: Text("THÔNG TIN TÀI KHOẢN",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black))),
        const SizedBox(height: 24),

        TextField(
            controller: _usernameController,
            style: const TextStyle(color: Colors.black87),
            decoration: _inputDecoration("Tên đăng nhập", Icons.person)
        ),
        const SizedBox(height: 16),

        TextField(
            controller: _fullNameController,
            style: const TextStyle(color: Colors.black87),
            decoration: _inputDecoration("Họ và tên", Icons.badge)
        ),
        const SizedBox(height: 16),

        const Text("Giới tính:", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black)),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _buildGenderRadio("Nam"),
            _buildGenderRadio("Nữ"),
            _buildGenderRadio("Khác"),
          ],
        ),
        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          initialValue: _selectedRegion,
          style: const TextStyle(color: Colors.black87, fontSize: 16),
          dropdownColor: Colors.white,
          decoration: _inputDecoration("Tỉnh / Thành phố", Icons.location_on),
          items: _provinces.map((province) => DropdownMenuItem(
            value: province,
            child: Text(province),
          )).toList(),
          onChanged: (value) => setState(() => _selectedRegion = value),
        ),
        const SizedBox(height: 16),

        TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.black87),
            decoration: _inputDecoration("Mật khẩu", Icons.lock).copyWith(
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off, color: Colors.grey[600]),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            )
        ),
        const SizedBox(height: 16),

        TextField(
            controller: _confirmPasswordController,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.black87),
            decoration: _inputDecoration("Xác nhận mật khẩu", Icons.lock_reset)
        ),
        const SizedBox(height: 32),

        _buildButton("HOÀN TẤT ĐĂNG KÝ", _completeRegister),
      ],
    );
  }

  Widget _buildGenderRadio(String val) {
    return Row(
      children: [
        Theme(
          data: Theme.of(context).copyWith(
            unselectedWidgetColor: Colors.grey[600],
          ),
          child: Radio<String>(
            value: val,
            groupValue: _selectedGender,
            activeColor: const Color(0xFFFF00CC),
            onChanged: (value) => setState(() => _selectedGender = value!),
          ),
        ),
        Text(val, style: const TextStyle(color: Colors.black)),
        const SizedBox(width: 10),
      ],
    );
  }

  Widget _buildButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity, height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
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