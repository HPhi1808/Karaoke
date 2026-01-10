import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../screens/me/user_profile_screen.dart';
import '../../services/notification_service.dart';

class UserListTile extends StatefulWidget {
  final UserModel user;
  final bool showFollowButton;

  const UserListTile({
    super.key,
    required this.user,
    this.showFollowButton = false
  });

  @override
  State<UserListTile> createState() => _UserListTileState();
}

class _UserListTileState extends State<UserListTile> {
  bool _isFollowing = false;       // Mình có đang follow họ không
  bool _isFollowedByTarget = false; // Họ có đang follow mình không
  bool _isLoading = true;
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    if (widget.showFollowButton) {
      _checkRelationshipStatus();
    } else {
      _isLoading = false;
    }
  }

  // 1. Kiểm tra mối quan hệ 2 chiều
  Future<void> _checkRelationshipStatus() async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null || currentUser.id == widget.user.id) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final results = await Future.wait([
        _supabase
            .from('follows')
            .count(CountOption.exact)
            .eq('follower_id', currentUser.id)
            .eq('following_id', widget.user.id),

        _supabase
            .from('follows')
            .count(CountOption.exact)
            .eq('follower_id', widget.user.id)
            .eq('following_id', currentUser.id),
      ]);

      if (mounted) {
        setState(() {
          _isFollowing = results[0] > 0;
          _isFollowedByTarget = results[1] > 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi check follow: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. Xử lý bấm nút
  Future<void> _handleFollowPress() async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null || currentUser.id == 'guest') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vui lòng đăng nhập để theo dõi!")),
      );
      return;
    }

    if (_isLoading) return;

    final oldState = _isFollowing;
    setState(() {
      _isFollowing = !oldState;
    });

    bool success;
    if (!oldState) {
      // Action: Follow
      success = await NotificationService.instance.followUser(
        targetUserId: widget.user.id,
      );
    } else {
      // Action: Unfollow
      success = await NotificationService.instance.unfollowUser(
        targetUserId: widget.user.id,
      );
    }

    if (!success) {
      if (mounted) {
        setState(() {
          _isFollowing = oldState;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lỗi kết nối!")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMe = _supabase.auth.currentUser?.id == widget.user.id;
    final shouldShowButton = widget.showFollowButton && !isMe;

    return ListTile(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => UserProfileScreen(user: widget.user)),
        );
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),

      // Avatar
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey[200],
        backgroundImage: (widget.user.avatarUrl != null && widget.user.avatarUrl!.isNotEmpty)
            ? NetworkImage(widget.user.avatarUrl!)
            : null,
        child: (widget.user.avatarUrl == null || widget.user.avatarUrl!.isEmpty)
            ? Text(
          (widget.user.fullName?.isNotEmpty == true)
              ? widget.user.fullName![0].toUpperCase()
              : "?",
          style: const TextStyle(fontWeight: FontWeight.bold),
        )
            : null,
      ),

      // Tên User
      title: Text(
        widget.user.fullName ?? "Người dùng",
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),

      // Vùng miền
      subtitle: widget.user.region != null
          ? Text(widget.user.region!, style: const TextStyle(fontSize: 12))
          : null,

      // Nút Follow tuỳ biến theo trạng thái
      trailing: shouldShowButton ? _buildFollowButton() : null,
    );
  }

  Widget _buildFollowButton() {
    if (_isLoading) {
      return const SizedBox(
        height: 32, width: 80,
        child: Center(child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    // Xác định trạng thái để hiển thị
    String text;
    Color bgColor;
    Color textColor;
    IconData? icon;

    if (_isFollowing) {
      if (_isFollowedByTarget) {
        // Cả 2 cùng follow -> Bạn bè
        text = "Bạn bè";
        bgColor = Colors.grey[300]!;
        textColor = Colors.black87;
        icon = Icons.swap_horiz;
      } else {
        // Mình follow họ, họ chưa follow lại -> Đang follow
        text = "Đang follow";
        bgColor = Colors.grey[300]!;
        textColor = Colors.black87;
      }
    } else {
      if (_isFollowedByTarget) {
        // Họ follow mình, mình chưa follow lại -> Follow lại
        text = "Follow lại";
        bgColor = const Color(0xFFFF00CC);
        textColor = Colors.white;
      } else {
        // Người lạ -> Follow
        text = "Follow";
        bgColor = const Color(0xFFFF00CC);
        textColor = Colors.white;
      }
    }

    double width = 90;
    if (text == "Bạn bè") width = 100;
    if (text == "Follow lại") width = 100;
    if (text == "Đang follow") width = 110;

    return SizedBox(
      height: 32,
      width: width,
      child: ElevatedButton(
        onPressed: _handleFollowPress,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide.none,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: textColor),
              const SizedBox(width: 4),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                fontWeight: _isFollowing ? FontWeight.normal : FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}