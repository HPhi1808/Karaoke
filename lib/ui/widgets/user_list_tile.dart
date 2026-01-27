import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../screens/me/user_profile_screen.dart';
import '../../services/notification_service.dart';
import '../../services/user_service.dart';

class UserListTile extends StatefulWidget {
  final UserModel user;
  final bool showFollowButton;
  final VoidCallback? onActionComplete;

  const UserListTile({
    super.key,
    required this.user,
    this.showFollowButton = false,
    this.onActionComplete,
  });

  @override
  State<UserListTile> createState() => _UserListTileState();
}

class _UserListTileState extends State<UserListTile> {
  bool _isFollowing = false;
  bool _isFollowedByTarget = false;
  bool _isBlockedByMe = false;
  bool _isLocked = false;
  bool _isLoading = true;
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  // Gộp chung các logic kiểm tra trạng thái
  Future<void> _checkStatus() async {
    final currentUser = _supabase.auth.currentUser;
    if (!widget.showFollowButton || currentUser == null || currentUser.id == widget.user.id) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        // 1. Check Following
        _supabase
            .from('follows')
            .count(CountOption.exact)
            .eq('follower_id', currentUser.id)
            .eq('following_id', widget.user.id),

        // 2. Check Follower
        _supabase
            .from('follows')
            .count(CountOption.exact)
            .eq('follower_id', widget.user.id)
            .eq('following_id', currentUser.id),

        // 3. Check Block
        UserService.instance.checkBlockStatus(currentUser.id, widget.user.id),

        // 4. Check Locked
        _supabase
            .from('users')
            .select('locked_until')
            .eq('id', widget.user.id)
            .single(),
      ]);

      final followCount = results[0] as int;
      final followedByCount = results[1] as int;
      final blockStatus = results[2] as BlockStatus;
      final userData = results[3] as Map<String, dynamic>;

      bool isLockedRealtime = false;
      if (userData['locked_until'] != null) {
        final lockedUntil = DateTime.parse(userData['locked_until']);
        if (lockedUntil.isAfter(DateTime.now())) {
          isLockedRealtime = true;
        }
      }

      if (mounted) {
        setState(() {
          _isFollowing = followCount > 0;
          _isFollowedByTarget = followedByCount > 0;
          _isBlockedByMe = blockStatus.blockedByMe;
          _isLocked = isLockedRealtime;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("UserListTile - Lỗi check status: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Xử lý Bỏ chặn
  Future<void> _handleUnblock() async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;

    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      await UserService.instance.unblockUser(currentUser.id, widget.user.id);
      if (mounted) {
        setState(() {
          _isBlockedByMe = false;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã bỏ chặn")));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi kết nối!")));
      }
    }
  }

  // Xử lý Follow/Unfollow
  Future<void> _handleFollowPress() async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vui lòng đăng nhập!")));
      return;
    }
    if (_isLoading) return;
    final oldState = _isFollowing;
    setState(() {
      _isFollowing = !oldState;
    });

    bool success;
    if (!oldState) {
      success = await NotificationService.instance.followUser(targetUserId: widget.user.id);
    } else {
      success = await NotificationService.instance.unfollowUser(targetUserId: widget.user.id);
    }

    if (!success) {
      if (mounted) {
        setState(() => _isFollowing = oldState);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi kết nối!")));
      }
    } else {
      if (widget.onActionComplete != null) {
        widget.onActionComplete!();
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
        backgroundImage: (!_isLocked && widget.user.avatarUrl != null && widget.user.avatarUrl!.isNotEmpty)
            ? NetworkImage(widget.user.avatarUrl!)
            : null,
        child: (_isLocked || widget.user.avatarUrl == null || widget.user.avatarUrl!.isEmpty)
            ? Icon(Icons.person, color: Colors.grey.shade400)
            : null,
      ),

      // Tên User
      title: Text(
        widget.user.fullName ?? "Người dùng",
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),

      subtitle: _isLocked
          ? const Text("Tài khoản đang bị tạm khoá", style: TextStyle(color: Colors.red, fontSize: 12))
          : (widget.user.region != null ? Text(widget.user.region!, style: const TextStyle(fontSize: 12)) : null),
      trailing: shouldShowButton ? _buildActionButton() : null,
    );
  }

  Widget _buildActionButton() {
    if (_isLoading) {
      return const SizedBox(
        height: 32, width: 80,
        child: Center(child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_isLocked) {
      return const SizedBox.shrink();
    }

    if (_isBlockedByMe) {
      return SizedBox(
        height: 32,
        width: 90,
        child: ElevatedButton(
          onPressed: _handleUnblock,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black87,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: const Text("Bỏ chặn", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      );
    }

    String text;
    Color bgColor;
    Color textColor;
    IconData? icon;

    if (_isFollowing) {
      if (_isFollowedByTarget) {
        text = "Bạn bè";
        bgColor = Colors.grey[300]!;
        textColor = Colors.black87;
        icon = Icons.swap_horiz;
      } else {
        text = "Đang follow";
        bgColor = Colors.grey[300]!;
        textColor = Colors.black87;
      }
    } else {
      if (_isFollowedByTarget) {
        text = "Follow lại";
        bgColor = const Color(0xFFFF00CC);
        textColor = Colors.white;
      } else {
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: textColor), const SizedBox(width: 4)],
            Text(text, style: TextStyle(fontSize: 12, color: textColor, fontWeight: _isFollowing ? FontWeight.normal : FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}