import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../providers/user_provider.dart';
import '../../../services/auth_service.dart';
import '../../../models/user_model.dart';
import 'follow_list_screen.dart';
import 'edit_profile_screen.dart';
import 'user_profile_screen.dart';


class MeScreen extends StatefulWidget {
  final VoidCallback onLogoutClick;

  const MeScreen({super.key, required this.onLogoutClick});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  final bool _isGuest = AuthService.instance.isGuest;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isGuest) {
        context.read<UserProvider>().fetchUserProfile();
      }
    });
  }

  // --- HÀM ĐIỀU HƯỚNG ---
  Future<void> _goToEditProfile() async {
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;

    if (currentUser == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(currentUser: currentUser),
      ),
    );

    if (result == true) {
      userProvider.fetchUserProfile();
    }
  }

  void _handleLogoutOrLogin() {
    if (_isGuest) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
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
              await context.read<UserProvider>().clearUser();
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
    return Icons.transgender;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
            "Hồ sơ cá nhân",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)
        ),
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Consumer<UserProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.currentUser == null && !_isGuest) {
            return const _MeSkeletonLoading();
          }

          // Lấy user từ Provider
          final userProfile = provider.currentUser;

          return RefreshIndicator(
            onRefresh: () async {
              await provider.fetchUserProfile();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopHeader(userProfile),
                  const SizedBox(height: 12),
                  _buildUserInfo(userProfile),
                  const SizedBox(height: 16),
                  if (!_isGuest) _buildEditButton(),
                  const SizedBox(height: 20),
                  const Divider(thickness: 1, height: 1),
                  const SizedBox(height: 10),
                  _buildMenuButtons(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Truyền UserModel vào hàm build
  Widget _buildTopHeader(UserModel? userProfile) {
    String avatarUrl = userProfile?.avatarUrl ?? "";
    bool hasAvatar = avatarUrl.isNotEmpty && avatarUrl.startsWith('http');

    return Row(
      children: [
        InkWell(
          onTap: () {
            if (userProfile != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfileScreen(user: userProfile),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(50),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300, width: 2),
            ),
            child: CircleAvatar(
              radius: 42,
              backgroundColor: Colors.grey[200],
              backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
              child: !hasAvatar
                  ? Icon(Icons.person, size: 45, color: Colors.grey[400])
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 20),

        Expanded(
          child: _isGuest
              ? const Center(
              child: Text("Đăng nhập để xem thống kê",
                  style: TextStyle(color: Colors.grey)))
              : Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                userProfile?.followingCount.toString() ?? "0",
                "Đang follow",
                onTap: () async {
                  if (userProfile != null) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FollowListScreen(
                          targetUser: userProfile,
                          initialTabIndex: 0,
                        ),
                      ),
                    );
                    if (context.mounted) {
                      context.read<UserProvider>().fetchUserProfile();
                    }
                  }
                },
              ),
              _buildStatItem(
                userProfile?.followersCount.toString() ?? "0",
                "Follower",
                onTap: () async {
                  if (userProfile != null) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FollowListScreen(
                          targetUser: userProfile,
                          initialTabIndex: 1,
                        ),
                      ),
                    );
                    if (context.mounted) {
                      context.read<UserProvider>().fetchUserProfile();
                    }
                  }
                },
              ),
              _buildStatItem(
                userProfile?.likesCount.toString() ?? "0",
                "Thích",
                onTap: null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String count, String label, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          children: [
            Text(count, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfo(UserModel? userProfile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          userProfile?.fullName ?? "Người dùng mới",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),

        if (!_isGuest) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Text("@${userProfile?.username ?? 'user'}", style: const TextStyle(color: Colors.black87)),
              const SizedBox(width: 8),
              if (userProfile?.gender != null) ...[
                Icon(_getGenderIcon(userProfile?.gender), size: 16, color: const Color(0xFFFF00CC)),
                const SizedBox(width: 8),
              ],
              if (userProfile?.region != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                  child: Text(userProfile!.region!, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            userProfile?.bio != null && userProfile!.bio!.isNotEmpty
                ? userProfile!.bio!
                : "Chưa có giới thiệu.",
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ] else ...[
          const SizedBox(height: 4),
          const Text("Khách vãng lai", style: TextStyle(color: Colors.grey)),
        ]
      ],
    );
  }

  Widget _buildEditButton() {
    return SizedBox(
      width: double.infinity,
      height: 36,
      child: OutlinedButton(
        onPressed: _goToEditProfile,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey.shade400),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text("Chỉnh sửa trang cá nhân", style: TextStyle(color: Colors.black, fontSize: 13)),
      ),
    );
  }

  Widget _buildMenuButtons() {
    return Column(
      children: [
        _buildMenuRow(Icons.favorite_border, "Yêu thích", () => Navigator.pushNamed(context, '/favorites')),
        _buildMenuRow(Icons.mic_none_rounded, "Bản thu âm của tôi", () => Navigator.pushNamed(context, '/recordings')),
        if (!_isGuest) ...[
          const Divider(),
          _buildMenuRow(Icons.person_off, "Danh sách chặn", () => Navigator.pushNamed(context, '/black_list')),
          _buildMenuRow(Icons.help_outline, "Chính sách & Hỗ trợ", () =>Navigator.pushNamed(context, '/policy_and_support')),
          _buildMenuRow(Icons.star_outline, "Đánh giá", () => Navigator.pushNamed(context, '/review_app')),
        ],

        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(_isGuest ? Icons.login : Icons.logout, color: Colors.red),
          title: Text(
            _isGuest ? "Đăng nhập / Đăng ký" : "Đăng xuất",
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
          ),
          onTap: _handleLogoutOrLogin,
        ),
      ],
    );
  }

  Widget _buildMenuRow(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.black87),
      title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

// SKELETON (Giữ nguyên)
class _MeSkeletonLoading extends StatelessWidget {
  const _MeSkeletonLoading();
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 84, height: 84, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                const SizedBox(width: 20),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(3, (index) => Column(
                      children: [
                        Container(width: 30, height: 20, color: Colors.white),
                        const SizedBox(height: 5),
                        Container(width: 50, height: 10, color: Colors.white),
                      ],
                    )),
                  ),
                )
              ],
            ),
            const SizedBox(height: 12),
            Container(width: 150, height: 20, color: Colors.white),
            const SizedBox(height: 8),
            Container(width: 200, height: 14, color: Colors.white),
            const SizedBox(height: 20),
            Container(width: double.infinity, height: 36, color: Colors.white),
          ],
        ),
      ),
    );
  }
}