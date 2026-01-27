import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:async';
import '../../models/moment_model.dart';
import '../screens/me/user_profile_screen.dart';
import '../screens/moments/create_moment_screen.dart';
import '../../models/user_model.dart';
import '../../services/moment_service.dart';
import '../../services/report_service.dart';
import '../../services/auth_service.dart';
import 'report_dialog.dart';
import 'comments_sheet.dart';

class MomentItem extends StatefulWidget {
  final Moment moment;
  final VoidCallback? onDeleted;

  const MomentItem({super.key, required this.moment, this.onDeleted,});

  @override
  State<MomentItem> createState() => _MomentItemState();
}

class _MomentItemState extends State<MomentItem> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  late bool _isLiked;
  late int _likesCount;
  late int _commentsCount;
  bool _isGuest = false;
  RealtimeChannel? _subscription;
  Timer? _debounce;
  late Moment _currentMoment;


  @override
  void initState() {
    super.initState();
    _currentMoment = widget.moment;
    _setupAudio();
    _isLiked = _currentMoment.isLiked;
    _likesCount = _currentMoment.likesCount;
    _commentsCount = _currentMoment.commentsCount;
    _isGuest = AuthService.instance.isGuest;
    _subscribeToRealtimeChanges();
  }


  //  Hàm hiển thị thông báo yêu cầu đăng nhập
  void _showGuestRestrictedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Yêu cầu đăng nhập"),
        content: const Text("Bạn cần đăng nhập tài khoản chính thức để thực hiện hành động này."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Đóng", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (ctx.mounted) {
                Navigator.of(ctx).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
            child: const Text("Đăng nhập / Đăng ký", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant MomentItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.moment.likesCount != oldWidget.moment.likesCount ||
        widget.moment.commentsCount != oldWidget.moment.commentsCount ||
        widget.moment.isLiked != oldWidget.moment.isLiked) {
      setState(() {
        _currentMoment = widget.moment;
        _likesCount = _currentMoment.likesCount;
        _commentsCount = _currentMoment.commentsCount;
        _isLiked = _currentMoment.isLiked;
      });
    }
  }

  Future<void> _refreshLocalData() async {
    final newMoment = await MomentService.instance.getMomentById(_currentMoment.id);

    if (newMoment != null && mounted) {
      setState(() {
        _currentMoment = newMoment;
      });
    }
  }

  void _setupAudio() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _audioPlayer.onPlayerComplete.listen((event) {
      if(mounted) setState(() => _position = Duration.zero);
    });
  }

  bool get _isMyMoment {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    return currentUserId != null && currentUserId == widget.moment.userId;
  }

  void _toggleLike() {
    if (_isGuest) {
      _showGuestRestrictedDialog();
      return;
    }
    setState(() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
    });
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 900), () async {
      try {
        await MomentService.instance.toggleLike(widget.moment.id, _isLiked, widget.moment.userId);

      } catch (e) {
        debugPrint("Lỗi sync like: $e");
        if (mounted) {
          setState(() {
            _isLiked = !_isLiked;
            _likesCount += _isLiked ? 1 : -1;
          });
        }
      }
    });
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),

              // --- TRƯỜNG HỢP 1: BÀI CỦA MÌNH (Sửa / Xóa) ---
              if (_isMyMoment) ...[
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blue),
                  title: const Text("Chỉnh sửa bài viết"),
                  onTap: () async {
                    Navigator.pop(context); // Đóng menu bottom sheet

                    // Mở màn hình Edit
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CreateMomentScreen(
                          selectedFile: null,
                          editingMoment: widget.moment,
                        ),
                      ),
                    );

                    // Nếu edit thành công (result == true), ta cần làm mới dữ liệu
                    if (result == true) {
                      await _refreshLocalData();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Đã cập nhật bài viết"))
                        );
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text("Xóa bài viết"),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDeleteMoment();
                  },
                ),
              ],

              // --- TRƯỜNG HỢP 2: BÀI NGƯỜI KHÁC (Báo cáo) ---
              if (!_isMyMoment && !_isGuest)
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: Colors.orange),
                  title: const Text("Báo cáo vi phạm"),
                  onTap: () {
                    Navigator.pop(context);
                    _openReportDialog();
                  },
                ),

              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteMoment() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xóa bài viết?"),
        content: const Text("Hành động này không thể hoàn tác."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Xóa", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await MomentService.instance.deleteMoment(widget.moment.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã xóa bài viết.")));
          widget.onDeleted?.call();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi xóa bài viết.")));
        }
      }
    }
  }

  void _openReportDialog() {
    ReportModal.show(
      context,
      targetType: ReportTargetType.moment,
      targetId: widget.moment.id.toString(),
      contentTitle: "Bài đăng của ${widget.moment.userName ?? 'Người dùng'}",
    );
  }

  void _showComments() async {
    if (_isGuest) {
      _showGuestRestrictedDialog();
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentsSheet(momentId: widget.moment.id, momentOwnerId: widget.moment.userId),
    );
    _refreshStats();
  }

  void _subscribeToRealtimeChanges() {
    final momentId = widget.moment.id;

    // Tạo kênh lắng nghe riêng cho Moment này
    _subscription = Supabase.instance.client
        .channel('moment_changes_$momentId')
    // Lắng nghe bảng Likes
        .onPostgresChanges(
      event: PostgresChangeEvent.all, // Insert, Update, Delete
      schema: 'public',
      table: 'moment_likes',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'moment_id',
        value: momentId,
      ),
      callback: (payload) => _refreshStats(), // Có thay đổi -> Load lại số liệu
    )
    // Lắng nghe bảng Comments
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'moment_comments',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'moment_id',
        value: momentId,
      ),
      callback: (payload) => _refreshStats(),
    )
        .subscribe();
  }

  Future<void> _refreshStats() async {
    final stats = await MomentService.instance.getMomentStats(widget.moment.id);
    if (stats != null && mounted) {
      setState(() {
        _likesCount = stats['likes_count'];
        _commentsCount = stats['comments_count'];
        _isLiked = stats['is_liked'];
      });
    }
  }

  @override
  void dispose() {
    Supabase.instance.client.removeChannel(_subscription!);
    _audioPlayer.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  String _formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  void _navigateToUserProfile() {
    final targetUser = UserModel(
      id: widget.moment.userId,
      fullName: widget.moment.userName,
      avatarUrl: widget.moment.userAvatar,
      role: 'user',
      email: null,
      username: null,
      bio: null,
      gender: null,
      region: null,
      lastActiveAt: null,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(user: targetUser),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeAgo = timeago.format(widget.moment.createdAt, locale: 'vi');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar + Tên + Thời gian
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Avatar
              GestureDetector(
                onTap: _navigateToUserProfile,
                child: CircleAvatar(
                  radius: 22,
                  backgroundImage: widget.moment.userAvatar != null
                      ? NetworkImage(widget.moment.userAvatar!)
                      : null,
                  child: widget.moment.userAvatar == null
                      ? Text(widget.moment.userName?[0] ?? "?") : null,
                ),
              ),
              const SizedBox(width: 12),

              // 2. Tên & Thời gian
              Expanded(
                child: GestureDetector(
                  onTap: _navigateToUserProfile,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.moment.userName ?? "Ẩn danh",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Row(
                        children: [
                          Text(
                            "$timeAgo • ",
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                          Icon(
                            widget.moment.visibility == 'public' ? Icons.public : Icons.people,
                            size: 12, color: Colors.grey.shade600,
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ---  NÚT MENU / REPORT ---
              if(!_isGuest)
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _showOptionsMenu,
                  tooltip: "Tùy chọn",
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Description
          if (widget.moment.description != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                widget.moment.description!,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ),

          // --- AUDIO PLAYER UI (MÀU TÍM) ---
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFE6D6FC), // Màu tím nhạt nền
              borderRadius: BorderRadius.circular(30),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Thời gian hiện tại
                Text(
                  _formatTime(_position),
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),

                // Thanh trượt
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      min: 0,
                      max: _duration.inSeconds.toDouble(),
                      value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble()),
                      activeColor: Colors.white,
                      inactiveColor: Colors.white.withOpacity(0.5),
                      onChanged: (value) async {
                        final position = Duration(seconds: value.toInt());
                        await _audioPlayer.seek(position);
                      },
                    ),
                  ),
                ),

                // Nút Play/Pause
                GestureDetector(
                  onTap: () async {
                    if (_isPlaying) {
                      await _audioPlayer.pause();
                    } else {
                      await _audioPlayer.play(UrlSource(widget.moment.audioUrl));
                    }
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFA66BFF), // Màu tím đậm nút bấm
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // --- FOOTER: LIKE, COMMENT ---
          Row(
            children: [
              TextButton.icon(
                onPressed: _toggleLike,
                style: TextButton.styleFrom(
                  foregroundColor: _isLiked ? Colors.red : Colors.grey.shade600,
                ),
                icon: Icon(_isLiked ? Icons.favorite : Icons.favorite_border, size: 20),
                label: Text("$_likesCount", style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 36),
              // NÚT COMMENT
              TextButton.icon(
                onPressed: _showComments,
                style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
                icon: const Icon(Icons.comment_outlined, size: 20),
                label: Text("$_commentsCount", style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

}