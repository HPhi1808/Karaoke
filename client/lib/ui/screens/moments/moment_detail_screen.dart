import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shimmer/shimmer.dart';

import '../../../models/moment_model.dart';
import '../../../services/moment_service.dart';
import '../../../services/user_service.dart';
import '../../widgets/moment_item.dart';
import '../../widgets/comment_item.dart';

class MomentDetailScreen extends StatefulWidget {
  final int momentId;
  final Moment? initialMoment;

  const MomentDetailScreen({
    super.key,
    required this.momentId,
    this.initialMoment
  });

  @override
  State<MomentDetailScreen> createState() => _MomentDetailScreenState();
}

class _MomentDetailScreenState extends State<MomentDetailScreen> {
  final TextEditingController _commentController = TextEditingController();

  Moment? _moment;
  bool _isLoading = true; // Loading cho bài viết chính
  bool _isSending = false;

  // State cho Avatar Input (Đồng bộ)
  String? _realUserAvatar;
  bool _isAvatarLoading = true;

  @override
  void initState() {
    super.initState();
    // 1. Setup dữ liệu bài viết
    if (widget.initialMoment != null) {
      _moment = widget.initialMoment;
      _isLoading = false;
    }
    _fetchMomentDetail();

    // 2. Fetch Avatar người dùng hiện tại (cho Input bar)
    _fetchCurrentUserAvatar();
  }

  Future<void> _fetchMomentDetail() async {
    final moment = await MomentService.instance.getMomentById(widget.momentId);
    if (mounted) {
      setState(() {
        _moment = moment;
        _isLoading = false;
      });
    }
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
    if (text.isEmpty || _isSending || _moment == null) return;
    setState(() => _isSending = true);
    // FocusScope.of(context).unfocus(); // Tùy chọn: Giữ bàn phím để chat tiếp

    try {
      await MomentService.instance.sendComment(widget.momentId, text, _moment!.userId);
      _commentController.clear();
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: $e")));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Chi tiết bài viết", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // --- PHẦN 1: NỘI DUNG CHÍNH (Cuộn) ---
            Expanded(
              child: _isLoading
                  ? _buildFullPageSkeleton() // Hiện Skeleton toàn trang nếu chưa có data
                  : _moment == null
                  ? const Center(child: Text("Bài viết không tồn tại hoặc đã bị xóa"))
                  : RefreshIndicator(
                onRefresh: _fetchMomentDetail,
                child: CustomScrollView(
                  slivers: [
                    // 1. Bài viết chính (Moment)
                    SliverToBoxAdapter(
                      child: MomentItem(moment: _moment!),
                    ),

                    // 2. Tiêu đề Bình luận
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text("Bình luận", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),

                    // 3. Danh sách Comment (Stream)
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: MomentService.instance.getCommentsStream(widget.momentId),
                      builder: (context, snapshot) {
                        // Loading -> Hiện Skeleton list comment
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return _buildCommentListSkeleton();
                        }

                        if (snapshot.hasError) {
                          return SliverToBoxAdapter(child: Center(child: Text("Lỗi tải bình luận")));
                        }

                        final comments = snapshot.data ?? [];
                        if (comments.isEmpty) {
                          return const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text("Chưa có bình luận nào.\nHãy là người đầu tiên!",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey)
                              ),
                            ),
                          );
                        }

                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) {
                              final comment = comments[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: CommentItem(
                                  commentId: comment['id'],
                                  userId: comment['user_id'],
                                  content: comment['content'],
                                  createdAt: DateTime.parse(comment['created_at']),
                                ),
                              );
                            },
                            childCount: comments.length,
                          ),
                        );
                      },
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ],
                ),
              ),
            ),

            // --- PHẦN 2: INPUT BAR ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, -2))]
              ),
              child: Row(
                children: [
                  // Avatar User (Có Skeleton riêng)
                  _buildCurrentUserAvatar(),

                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: "Viết bình luận...",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= SKELETON & WIDGETS =================

  // 1. Avatar User Input (Logic Skeleton)
  Widget _buildCurrentUserAvatar() {
    if (_isAvatarLoading) {
      return Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: const CircleAvatar(radius: 16, backgroundColor: Colors.white),
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: Colors.grey[200],
      backgroundImage: (_realUserAvatar != null && _realUserAvatar!.isNotEmpty)
          ? NetworkImage(_realUserAvatar!)
          : null,
      child: (_realUserAvatar == null || _realUserAvatar!.isEmpty)
          ? const Icon(Icons.person, color: Colors.grey, size: 20)
          : null,
    );
  }

  // 2. Full Page Skeleton (Dùng khi vào từ Notification)
  Widget _buildFullPageSkeleton() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Moment Skeleton
          Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const CircleAvatar(radius: 22, backgroundColor: Colors.white),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 100, height: 14, color: Colors.white),
                      const SizedBox(height: 6),
                      Container(width: 60, height: 10, color: Colors.white),
                    ])
                  ]),
                  const SizedBox(height: 12),
                  Container(width: double.infinity, height: 12, color: Colors.white),
                  const SizedBox(height: 12),
                  Container(height: 60, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30))),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Container(width: 60, height: 20, color: Colors.white),
                    Container(width: 60, height: 20, color: Colors.white),
                  ])
                ],
              ),
            ),
          ),
          const Divider(thickness: 8, color: Color(0xFFF5F5F5)),

          // Comment List Skeleton
          // Lưu ý: Không bọc CustomScrollView trong SingleChildScrollView để tránh lỗi,
          // nên ở đây ta code chay UI giả lập danh sách
          for (int i=0; i<5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Row(
                  children: [
                    const CircleAvatar(radius: 16, backgroundColor: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(width: 80, height: 12, color: Colors.white),
                        const SizedBox(height: 4),
                        Container(width: 150, height: 12, color: Colors.white),
                      ]),
                    )
                  ],
                ),
              ),
            )
        ],
      ),
    );
  }

  // 3. Comment List Skeleton (Dùng trong StreamBuilder)
  Widget _buildCommentListSkeleton() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        childCount: 5, // Hiện 5 dòng skeleton
      ),
    );
  }
}