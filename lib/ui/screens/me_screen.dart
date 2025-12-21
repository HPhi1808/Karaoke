import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../models/user_model.dart';

class MeScreen extends StatefulWidget {
  final VoidCallback onLogoutClick;

  const MeScreen({Key? key, required this.onLogoutClick}) : super(key: key);

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  UserModel? _userProfile;
  bool _isLoading = true;
  bool _isGuest = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  /// Hàm tải dữ liệu thông minh cho cả Guest và User
  Future<void> _loadUserData() async {
    final isGuest = AuthService.instance.isGuest;

    if (mounted) {
      setState(() => _isGuest = isGuest);
    }

    try {
      final profile = await ApiService.instance.getUserProfile();

      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("LỖI LOAD PROFILE: $e");
      if (mounted) {
        if (isGuest) {
          final user = AuthService.instance.currentUser;
          _userProfile = UserModel(
            id: user?.id ?? 'guest',
            email: '',
            username: 'guest_mode',
            fullName: 'Khách Trải Nghiệm',
            role: 'guest',
            avatarUrl: 'https://pub-4b88f65058c84573bfc0002391a01edf.r2.dev/PictureApp/defautl.jpg',
            gender: null,
            region: null,
          );
        }
        setState(() => _isLoading = false);
      }
    }
  }

  // Xử lý nút hành động chính
  void _handleMainAction() {
    if (_isGuest) {
      Navigator.pushNamed(context, '/login');
    } else {
      _showLogoutDialog();
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Đăng xuất"),
        content: const Text("Bạn có chắc chắn muốn đăng xuất không?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              await AuthService.instance.logout();
              widget.onLogoutClick();
            },
            child: const Text("Đồng ý", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Hàm lấy icon theo giới tính (Chấp nhận null)
  IconData _getGenderIcon(String? gender) {
    if (gender == 'Nam') return Icons.male;
    if (gender == 'Nữ') return Icons.female;
    return Icons.help_outline;
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF00CC);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
          title: const Text("Hồ sơ cá nhân", style: TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          centerTitle: true,
          elevation: 0
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 10),
            // Header Avatar & Tên & Giới tính/Khu vực
            _buildHeader(),

            const SizedBox(height: 32),

            // Menu Chức năng
            _buildMenu(context, primaryColor),

            const SizedBox(height: 40),

            // Nút Hành động Chính
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _handleMainAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isGuest ? primaryColor : Colors.red.shade400,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                ),
                icon: Icon(_isGuest ? Icons.login : Icons.logout, color: Colors.white),
                label: Text(
                  _isGuest ? "ĐĂNG NHẬP / ĐĂNG KÝ NGAY" : "ĐĂNG XUẤT",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),

            if (_isGuest)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: const Text(
                  "Đăng nhập để lưu bài hát vĩnh viễn và tham gia cộng đồng!",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    String displayName = "Người dùng";
    if (_userProfile != null) {
      if (_userProfile!.fullName != null && _userProfile!.fullName!.isNotEmpty) {
        displayName = _userProfile!.fullName!;
      } else if (_userProfile!.username != null && _userProfile!.username!.isNotEmpty) {
        displayName = _userProfile!.username!;
      } else if (_userProfile!.email != null && _userProfile!.email!.isNotEmpty) {
        displayName = _userProfile!.email!.split('@')[0];
      } else if (_isGuest) {
        displayName = "Khách Trải Nghiệm";
      }
    }

    String avatarUrl = _userProfile?.avatarUrl ?? "";
    bool hasAvatar = avatarUrl.isNotEmpty;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _isGuest ? Colors.grey : const Color(0xFFFF00CC), width: 2),
          ),
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey[200],
            backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
            child: !hasAvatar
                ? Icon(Icons.person, size: 50, color: Colors.grey[400])
                : null,
          ),
        ),
        const SizedBox(height: 16),

        Text(
          displayName,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 6),

        // Role Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _isGuest ? Colors.grey[200] : Colors.blue[50],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _isGuest ? "Khách vãng lai" : "Thành viên chính thức",
            style: TextStyle(
                color: _isGuest ? Colors.grey[700] : Colors.blue[700],
                fontWeight: FontWeight.bold,
                fontSize: 12
            ),
          ),
        ),

        // --- HIỂN THỊ GIỚI TÍNH & KHU VỰC (Chỉ cho User thật) ---
        if (!_isGuest && _userProfile != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon Giới tính
                Icon(
                  _getGenderIcon(_userProfile?.gender),
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 6),

                // Text: Giới tính | Khu vực
                Text(
                  "${_userProfile?.gender ?? '---'}  •  ${_userProfile?.region ?? 'Chưa cập nhật'}",
                  style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                      fontWeight: FontWeight.w500
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMenu(BuildContext context, Color primaryColor) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _buildMenuItem(
              icon: Icons.history,
              color: Colors.orange,
              text: "Lịch sử hát",
              onTap: () {
                Navigator.pushNamed(context, '/history');
              }
          ),
          const Divider(height: 1),
          _buildMenuItem(
              icon: Icons.favorite,
              color: Colors.red,
              text: "Bài hát yêu thích",
              onTap: () {
                Navigator.pushNamed(context, '/favorites');
              }
          ),
          const Divider(height: 1),
          _buildMenuItem(
              icon: Icons.settings,
              color: Colors.grey,
              text: "Cài đặt ứng dụng",
              onTap: () {
                // Mở màn hình cài đặt
              }
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({required IconData icon, required Color color, required String text, required VoidCallback onTap}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }
}