import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../services/moment_service.dart';
import '../../services/user_service.dart';
import '../../services/auth_service.dart';
import 'comment_item.dart';

class CommentsSheet extends StatefulWidget {
  final int momentId;
  final String momentOwnerId;

  const CommentsSheet({super.key, required this.momentId, required this.momentOwnerId});

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final TextEditingController _commentController = TextEditingController();

  bool _isSending = false;
  String? _realUserAvatar;
  bool _isAvatarLoading = true;
  bool _isGuest = false;

  @override
  void initState() {
    super.initState();
    _isGuest = AuthService.instance.isGuest;
    if (!_isGuest) {
      _fetchCurrentUserAvatar();
    } else {
      setState(() => _isAvatarLoading = false);
    }
  }

  void _goToLogin() {
    Navigator.pop(context);
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _fetchCurrentUserAvatar() async {
    try {
      final avatar = await UserService.instance.getCurrentUserAvatar();
      if (mounted) {
        setState(() {
          _realUserAvatar = avatar;
          _isAvatarLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isAvatarLoading = false);
    }
  }

  void _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    if (_isSending) return;

    setState(() => _isSending = true);

    try {
      await MomentService.instance.sendComment(widget.momentId, text, widget.momentOwnerId);
      _commentController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: ${e.toString()}")));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // HEADER
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ],
            ),
          ),
          const Text("Bình luận", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),

          // LIST COMMENTS
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: MomentService.instance.getCommentsStream(widget.momentId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildListSkeleton();
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Lỗi tải bình luận", style: TextStyle(color: Colors.grey[500])));
                }
                final comments = snapshot.data ?? [];
                if (comments.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 10),
                        Text("Chưa có bình luận nào.\nHãy là người đầu tiên!",
                            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    return CommentItem(
                      commentId: comment['id'],
                      userId: comment['user_id'],
                      content: comment['content'],
                      createdAt: DateTime.parse(comment['created_at']),
                    );
                  },
                );
              },
            ),
          ),

          // INPUT BOX
          Container(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: _isGuest ? _buildGuestLoginPrompt() : _buildCommentInput(),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestLoginPrompt() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "Đăng nhập để bình luận",
          style: TextStyle(color: Colors.grey, fontSize: 15),
        ),
        ElevatedButton(
          onPressed: _goToLogin,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF00CC),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: const Text("Đăng nhập"),
        ),
      ],
    );
  }

  Widget _buildCommentInput() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildCurrentUserAvatar(),

        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _commentController,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: "Thêm bình luận...",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              filled: true,
              fillColor: Colors.grey[100],
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        IconButton(
          onPressed: _isSending ? null : _sendComment,
          icon: _isSending
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send, color: Color(0xFFFF00CC)),
        ),
      ],
    );
  }

  // Dùng Skeleton chờ Load xong mới hiện Avatar thật
  Widget _buildCurrentUserAvatar() {
    // 1. Nếu đang load -> Hiện Skeleton tròn
    if (_isAvatarLoading) {
      return Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: const CircleAvatar(
          radius: 18,
          backgroundColor: Colors.white,
        ),
      );
    }

    // 2. Load xong -> Hiện Avatar thật (hoặc icon default nếu null)
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.grey[200],
      backgroundImage: (_realUserAvatar != null && _realUserAvatar!.isNotEmpty)
          ? NetworkImage(_realUserAvatar!)
          : null,
      child: (_realUserAvatar == null || _realUserAvatar!.isEmpty)
          ? const Icon(Icons.person, color: Colors.grey, size: 20)
          : null,
    );
  }

  Widget _buildListSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(radius: 16, backgroundColor: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(width: 80, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                        const SizedBox(width: 8),
                        Container(width: 40, height: 10, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                      ]),
                      const SizedBox(height: 6),
                      Container(width: double.infinity, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 4),
                      Container(width: 150, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}