import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart'; // [QUAN TRỌNG] Nhớ import thư viện này

import '../../services/auth_service.dart';
import '../../services/user_service.dart';
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

  Future<void> _loadUserData() async {
    // Giả lập delay 1 chút để bạn kịp nhìn thấy hiệu ứng skeleton (nếu mạng quá nhanh)
    // await Future.delayed(const Duration(seconds: 1));

    final isGuest = AuthService.instance.isGuest;
    if (mounted) setState(() => _isGuest = isGuest);

    try {
      final profile = await UserService.instance.getUserProfile();
      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("LỖI LOAD PROFILE: $e");
      if (mounted) {
        if (isGuest) {
          // Tạo user ảo cho khách
          _userProfile = UserModel(
            id: 'guest',
            email: '',
            username: 'guest_mode',
            fullName: 'Khách Trải Nghiệm',
            role: 'guest',
            avatarUrl: '', // Để trống để hiện icon mặc định
            gender: null,
            region: null,
          );
        }
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleMainAction() {
    if (_isGuest) {
      // Điều hướng đến trang đăng nhập (Cần định nghĩa route '/login' ở main.dart)
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
      // [THAY ĐỔI] Kiểm tra loading để hiện Skeleton
      body: _isLoading
          ? const _MeSkeletonLoading() // Widget khung xương mới
          : RefreshIndicator(
        onRefresh: _loadUserData, // Kéo xuống để tải lại
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SizedBox(height: 10),
              _buildHeader(),
              const SizedBox(height: 32),
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
      ),
    );
  }

  Widget _buildHeader() {
    String displayName = "Người dùng";
    String avatarUrl = "";

    if (_userProfile != null) {
      displayName = _userProfile!.fullName ?? _userProfile!.username ?? _userProfile!.email?.split('@')[0] ?? "Người dùng";
      avatarUrl = _userProfile!.avatarUrl ?? "";
      if (_isGuest) displayName = "Khách Trải Nghiệm";
    }

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

        if (!_isGuest && _userProfile != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getGenderIcon(_userProfile?.gender),
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 6),
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
              onTap: () => Navigator.pushNamed(context, '/history')),
          const Divider(height: 1),
          _buildMenuItem(
              icon: Icons.favorite,
              color: Colors.red,
              text: "Bài hát yêu thích",
              onTap: () => Navigator.pushNamed(context, '/favorites')),
          const Divider(height: 1),
          _buildMenuItem(
              icon: Icons.settings,
              color: Colors.grey,
              text: "Cài đặt ứng dụng",
              onTap: () {}),
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

// ==========================================
// WIDGET SKELETON CHO MÀN HÌNH ME (MỚI)
// ==========================================
class _MeSkeletonLoading extends StatelessWidget {
  const _MeSkeletonLoading({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 10),
            // 1. Header Skeleton (Avatar + Info)
            _buildHeaderSkeleton(),

            const SizedBox(height: 32),

            // 2. Menu Skeleton
            _buildMenuSkeleton(),

            const SizedBox(height: 40),

            // 3. Button Skeleton
            Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSkeleton() {
    return Column(
      children: [
        // Avatar tròn giả
        Container(
          width: 108, // 50*2 + 4*2 padding
          height: 108,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 16),

        // Tên user giả
        Container(
          width: 150,
          height: 24,
          color: Colors.white,
        ),
        const SizedBox(height: 6),

        // Role badge giả
        Container(
          width: 100,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const SizedBox(height: 8),

        // Info text giả
        Container(
          width: 120,
          height: 14,
          color: Colors.white,
        ),
      ],
    );
  }

  Widget _buildMenuSkeleton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _buildMenuItemSkeleton(),
          const SizedBox(height: 16), // Khoảng cách thay cho Divider
          _buildMenuItemSkeleton(),
          const SizedBox(height: 16),
          _buildMenuItemSkeleton(),
        ],
      ),
    );
  }

  Widget _buildMenuItemSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Icon tròn giả
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Colors.white, // Do Shimmer base là grey[300] nên white sẽ nổi bật trong effect
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          // Text giả
          Container(
            width: 120,
            height: 16,
            color: Colors.white,
          ),
          const Spacer(),
          // Arrow giả
          Container(
            width: 14,
            height: 14,
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}