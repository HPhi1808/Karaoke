import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../../models/user_model.dart';
import '../../../services/user_service.dart';

const List<String> kRegions = [
  "TP Hà Nội", "TP Huế", "Quảng Ninh", "Cao Bằng", "Lạng Sơn", "Lai Châu",
  "Điện Biên", "Sơn La", "Thanh Hóa", "Nghệ An", "Hà Tĩnh", "Tuyên Quang",
  "Lào Cai", "Thái Nguyên", "Phú Thọ", "Bắc Ninh", "Hưng Yên", "TP Hải Phòng",
  "Ninh Bình", "Quảng Trị", "TP Đà Nẵng", "Quảng Ngãi", "Gia Lai", "Khánh Hòa",
  "Lâm Đồng", "Đắk Lắk", "TP Hồ Chí Minh", "Đồng Nai", "Tây Ninh", "TP Cần Thơ",
  "Vĩnh Long", "Đồng Tháp", "Cà Mau", "An Giang"
];

class EditProfileScreen extends StatefulWidget {
  final UserModel currentUser; // Nhận data hiện tại để fill vào form

  const EditProfileScreen({super.key, required this.currentUser});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  String _selectedGender = 'Nam';
  String? _selectedRegion;
  XFile? _pickedImage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentUser.fullName);
    _usernameController = TextEditingController(text: widget.currentUser.username);
    _bioController = TextEditingController(text: widget.currentUser.bio);

    _selectedGender = widget.currentUser.gender ?? 'Nam';

    // Kiểm tra xem region hiện tại có trong list không, nếu không thì để null
    if (widget.currentUser.region != null && kRegions.contains(widget.currentUser.region)) {
      _selectedRegion = widget.currentUser.region;
    }
  }

  // --- Chọn ảnh từ thư viện ---
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _pickedImage = pickedFile;
      });
    }
  }

  // --- Lưu thông tin ---
  Future<void> _saveUserData() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await UserService.instance.updateUserProfile(
        fullName: _nameController.text.trim(),
        username: _usernameController.text.trim(),
        bio: _bioController.text.trim(),
        gender: _selectedGender,
        region: _selectedRegion,
        avatarFile: _pickedImage,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật thành công!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      String errorMessage = 'Đã có lỗi xảy ra';
      if (e is DioException) {
        if (e.response != null && e.response?.data is Map) {
          errorMessage = e.response?.data['error'] ?? e.message ?? 'Lỗi kết nối';
        } else {
          errorMessage = e.message ?? 'Không thể kết nối đến máy chủ';
        }
      } else {
        errorMessage = e.toString();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ $errorMessage'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Chỉnh sửa cá nhân", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Avatar Section ---
                  Center(child: _buildAvatarPicker()),
                  const SizedBox(height: 30),

                  // --- Username ---
                  _buildLabel("Username (ID)"),
                  TextFormField(
                    controller: _usernameController,
                    decoration: _inputDecoration("Ví dụ: user123 (3-20 ký tự)"),
                    validator: (value) {
                      if (value == null || value.isEmpty) return "Vui lòng nhập username";
                      if (value.length < 3 || value.length > 20) return "Độ dài từ 3-20 ký tự";
                      if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(value)) {
                        return "Chỉ chứa chữ cái và số, không dấu cách";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // --- Fullname ---
                  _buildLabel("Họ và tên"),
                  TextFormField(
                    controller: _nameController,
                    decoration: _inputDecoration("Nhập họ tên của bạn"),
                    validator: (v) => v!.trim().isEmpty ? "Không được để trống" : null,
                  ),
                  const SizedBox(height: 20),

                  // --- Gender ---
                  _buildLabel("Giới tính"),
                  Row(
                    children: [
                      _buildGenderButton("Nam", Icons.male, Colors.blue),
                      const SizedBox(width: 10),
                      _buildGenderButton("Nữ", Icons.female, Colors.pink),
                      const SizedBox(width: 10),
                      _buildGenderButton("Khác", Icons.transgender, Colors.purple),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // --- Region Dropdown ---
                  _buildLabel("Vùng miền / Tỉnh thành"),
                  DropdownButtonFormField<String>(
                    value: _selectedRegion,
                    decoration: _inputDecoration("Chọn tỉnh thành"),
                    items: kRegions.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedRegion = val),
                    validator: (val) => val == null ? "Vui lòng chọn vùng miền" : null,
                  ),
                  const SizedBox(height: 20),

                  // --- Bio ---
                  _buildLabel("Lời giới thiệu"),
                  TextFormField(
                    controller: _bioController,
                    maxLines: 3,
                    maxLength: 150,
                    decoration: _inputDecoration("Nhập giới thiệu ngắn..."),
                  ),
                  const SizedBox(height: 30),

                  // --- Button Save ---
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveUserData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("LƯU THAY ĐỔI", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_isLoading)
            Container(
              color: Colors.black12,
              child: const Center(child: CircularProgressIndicator()),
            )
        ],
      ),
    );
  }

  Widget _buildAvatarPicker() {
    ImageProvider? imageProvider;
    if (_pickedImage != null) {
      if (kIsWeb) {
        // Trên Web: image_picker trả về path là blob url, dùng NetworkImage để load
        imageProvider = NetworkImage(_pickedImage!.path);
      } else {
        // Trên Mobile: Dùng FileImage
        imageProvider = FileImage(File(_pickedImage!.path));
      }
    } else if (widget.currentUser.avatarUrl != null && widget.currentUser.avatarUrl!.isNotEmpty) {
      imageProvider = NetworkImage(widget.currentUser.avatarUrl!);
    }

    return GestureDetector(
      onTap: () {
        if (kIsWeb) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Tính năng đổi ảnh đại diện chỉ hỗ trợ trên ứng dụng điện thoại (Mobile App).'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          _pickImage();
        }
      },
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.blueAccent, width: 2)),
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[200],
              backgroundImage: imageProvider,
              child: imageProvider == null
                  ? const Icon(Icons.person, size: 50, color: Colors.grey)
                  : null,
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
            ),
          )
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
  );

  Widget _buildGenderButton(String gender, IconData icon, Color color) {
    bool isSelected = _selectedGender == gender;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedGender = gender),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.1) : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? color : Colors.transparent, width: 2),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? color : Colors.grey),
              Text(gender, style: TextStyle(color: isSelected ? color : Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}