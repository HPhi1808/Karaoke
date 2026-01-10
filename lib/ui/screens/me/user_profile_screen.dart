import 'package:flutter/material.dart';
import '../mailbox/chat_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/user_model.dart';
import '../../../services/auth_service.dart';
import '../../../services/notification_service.dart';
import 'follow_list_screen.dart';
import 'me_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final UserModel user;

  const UserProfileScreen({super.key, required this.user});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _supabase = Supabase.instance.client;

  late UserModel _displayUser;

  bool _isFollowing = false;
  bool _isFollowedByTarget = false;
  bool _isFriend = false;
  bool _isLoadingFollow = false;

  // Stats
  int _followerCount = 0;
  int _followingCount = 0;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _displayUser = widget.user;

    _followerCount = widget.user.followersCount;
    _followingCount = widget.user.followingCount;
    _likeCount = widget.user.likesCount;

    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _fetchUserDetails(),
      _checkFollowStatus(),
      _fetchStats(),
    ]);
    if (mounted) {
    }
  }

  // --- 1. LẤY CHI TIẾT USER (BIO, GENDER, UPDATE LẠI INFO) ---
  Future<void> _fetchUserDetails() async {
    try {
      final data = await _supabase
          .from('users')
          .select()
          .eq('id', widget.user.id)
          .single();

      if (mounted) {
        setState(() {
          _displayUser = UserModel.fromJson(data);
        });
      }
    } catch (e) {
      debugPrint("Lỗi lấy user detail: $e");
    }
  }

  // 2. Kiểm tra follow
  Future<void> _checkFollowStatus() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      final results = await Future.wait([
        _supabase.from('follows').count().eq('follower_id', currentUserId).eq('following_id', widget.user.id),
        _supabase.from('follows').count().eq('follower_id', widget.user.id).eq('following_id', currentUserId),
      ]);

      if (mounted) {
        setState(() {
          _isFollowing = results[0] > 0;
          _isFollowedByTarget = results[1] > 0;
          _isFriend = _isFollowing && _isFollowedByTarget;
        });
      }
    } catch (e) {
      debugPrint("Lỗi check follow: $e");
    }
  }

  // 3. Lấy số liệu (Cập nhật lại đè lên dữ liệu cũ nếu có thay đổi)
  Future<void> _fetchStats() async {
    try {
      final followers = await _supabase.from('follows').count().eq('following_id', widget.user.id);
      final following = await _supabase.from('follows').count().eq('follower_id', widget.user.id);

      if (mounted) {
        setState(() {
          _followerCount = followers;
          _followingCount = following;
        });
      }
    } catch (e) {
      debugPrint("Lỗi lấy stats: $e");
    }
  }

  // 4. Xử lý nút Follow
  Future<void> _handleFollowAction() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;
    if (_isLoadingFollow) return;

    if (_isFollowing) {
      // UNFOLLOW LOGIC
      final String dialogTitle = _isFriend
          ? "Huỷ kết bạn với ${_displayUser.fullName}?"
          : "Huỷ theo dõi ${_displayUser.fullName}?";

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(dialogTitle),
          content: const Text("Bạn sẽ không nhận được thông báo mới từ họ nữa."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Huỷ")),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Đồng ý", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        setState(() {
          _isLoadingFollow = true;
          _isFollowing = false;
          _isFriend = false;
          _followerCount--;
        });

        bool success = await NotificationService.instance.unfollowUser(targetUserId: widget.user.id);

        if (!success && mounted) {
          setState(() {
            _isFollowing = true;
            _isFriend = _isFollowedByTarget;
            _followerCount++;
            _isLoadingFollow = false;
          });
        } else {
          if(mounted) setState(() => _isLoadingFollow = false);
        }
      }
    } else {
      // FOLLOW LOGIC
      setState(() {
        _isLoadingFollow = true;
        _isFollowing = true;
        if (_isFollowedByTarget) _isFriend = true;
        _followerCount++;
      });

      bool success = await NotificationService.instance.followUser(targetUserId: widget.user.id);

      if (!success && mounted) {
        setState(() {
          _isFollowing = false;
          _isFriend = false;
          _followerCount--;
          _isLoadingFollow = false;
        });
      } else {
        if(mounted) setState(() => _isLoadingFollow = false);
      }
    }
  }

  void _navigateToFollowList(int initialTab) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowListScreen(
          targetUser: _displayUser,
          initialTabIndex: initialTab,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id;

    if (currentUserId != null && widget.user.id == currentUserId) {
      return MeScreen(
        onLogoutClick: () async {
          await AuthService.instance.logout();
          if (context.mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
          }
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () {},
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade200, width: 2),
              ),
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: (_displayUser.avatarUrl != null && _displayUser.avatarUrl!.isNotEmpty)
                    ? NetworkImage(_displayUser.avatarUrl!)
                    : null,
                child: (_displayUser.avatarUrl == null || _displayUser.avatarUrl!.isEmpty)
                    ? Text(
                  (_displayUser.fullName?.isNotEmpty == true) ? _displayUser.fullName![0].toUpperCase() : "?",
                  style: const TextStyle(fontSize: 40, color: Colors.grey),
                )
                    : null,
              ),
            ),

            const SizedBox(height: 16),

            Text(
              _displayUser.fullName ?? "Người dùng",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 4),
            Text(
              "@${_displayUser.username ?? 'unknown'}",
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            ),

            const SizedBox(height: 12),

            // Gender & Region
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_displayUser.gender != null) ...[
                  Icon(
                    _displayUser.gender == 'male' ? Icons.male : Icons.female,
                    size: 16,
                    color: _displayUser.gender == 'male' ? Colors.blue : Colors.pink,
                  ),
                  const SizedBox(width: 4),
                  Text(_displayUser.gender == 'male' ? "Nam" : "Nữ"),
                  const SizedBox(width: 15),
                ],
                if (_displayUser.region != null && _displayUser.region!.isNotEmpty) ...[
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(_displayUser.region!),
                ]
              ],
            ),

            // --- PHẦN HIỂN THỊ BIO  ---
            if (_displayUser.bio != null && _displayUser.bio!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  _displayUser.bio!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[800],
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Stats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem("Đang follow", _followingCount, () => _navigateToFollowList(0)),
                  Container(width: 1, height: 30, color: Colors.grey.shade300),
                  _buildStatItem("Follower", _followerCount, () => _navigateToFollowList(1)),
                  Container(width: 1, height: 30, color: Colors.grey.shade300),
                  _buildStatItem("Thích", _likeCount, () {}),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 45,
                      child: ElevatedButton(
                        onPressed: _isLoadingFollow ? null : _handleFollowAction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (_isFriend || _isFollowing)
                              ? Colors.grey[200]
                              : const Color(0xFFFF00CC),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isLoadingFollow
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isFriend
                                  ? Icons.people_alt_rounded
                                  : (_isFollowing ? Icons.check : Icons.add),
                              color: (_isFriend || _isFollowing) ? Colors.black87 : Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isFriend
                                  ? "Bạn bè"
                                  : (_isFollowing ? "Đang follow" : "Follow"),
                              style: TextStyle(
                                  color: (_isFriend || _isFollowing) ? Colors.black87 : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 45,
                    width: 45,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(targetUser: _displayUser)));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[100],
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Icon(Icons.chat_bubble_outline, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),
            const Divider(thickness: 1, height: 1),

            // Moments
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Khoảnh khắc",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.image_not_supported_outlined, size: 60, color: Colors.grey[300]),
                        const SizedBox(height: 10),
                        Text(
                          "${_displayUser.fullName} chưa có khoảnh khắc nào.",
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Text(
              "$value",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}