import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../services/moment_service.dart';
import '../../services/report_service.dart';
import 'report_dialog.dart';

class CommentItem extends StatefulWidget {
  final int commentId;
  final String userId;
  final String content;
  final DateTime createdAt;

  const CommentItem({
    super.key,
    required this.commentId,
    required this.userId,
    required this.content,
    required this.createdAt
  });

  @override
  State<CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem> {
  String _name = '...';
  String? _avatar;

  bool get _isMyComment {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    return currentUserId != null && currentUserId == widget.userId;
  }

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  void _loadUser() async {
    final data = await MomentService.instance.getUserProfile(widget.userId);
    if (mounted && data != null) {
      setState(() {
        _name = data['full_name'] ?? 'Ẩn danh';
        _avatar = data['avatar_url'];
      });
    }
  }

  // --- Hàm hiện Menu ---
  void _showOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- TRƯỜNG HỢP 1: COMMENT CỦA MÌNH (Sửa / Xóa) ---
            if (_isMyComment) ...[
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text("Chỉnh sửa"),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("Xóa bình luận"),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete();
                },
              ),
            ],

            // --- TRƯỜNG HỢP 2: COMMENT NGƯỜI KHÁC (Báo cáo) ---
            if (!_isMyComment)
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.orange),
                title: const Text("Báo cáo vi phạm"),
                onTap: () {
                  Navigator.pop(context);
                  _openReportDialog();
                },
              ),
          ],
        ),
      ),
    );
  }

  // --- Hàm mở Dialog báo cáo ---
  void _openReportDialog() {
    String shortContent = widget.content.length > 20
        ? "${widget.content.substring(0, 20)}..."
        : widget.content;

    ReportModal.show(
      context,
      targetType: ReportTargetType.comment,
      targetId: widget.commentId.toString(),
      contentTitle: "Bình luận: \"$shortContent\"",
    );
  }

  void _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xóa bình luận?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Xóa", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await MomentService.instance.deleteComment(widget.commentId);
      } catch (e) {
      }
    }
  }

  void _showEditDialog() {
    final controller = TextEditingController(text: widget.content);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Chỉnh sửa"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () async {
              final newText = controller.text.trim();
              if (newText == widget.content) {
                Navigator.pop(ctx);
                return;
              }

              if (newText.isNotEmpty) {
                try {
                  await MomentService.instance.editComment(widget.commentId, newText);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {

                }
              }
            },
            child: const Text("Lưu"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: _showOptions,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: _avatar != null ? NetworkImage(_avatar!) : null,
              child: _avatar == null ? const Icon(Icons.person, size: 16) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(_name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 5),
                      Text(
                          timeago.format(widget.createdAt, locale: 'vi'),
                          style: const TextStyle(color: Colors.grey, fontSize: 11)
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(widget.content, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}