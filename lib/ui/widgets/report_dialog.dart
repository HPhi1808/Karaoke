import 'package:flutter/material.dart';
import '../../services/report_service.dart';

class ReportModal {
  static void show(BuildContext context, {
    required ReportTargetType targetType,
    required String targetId,
    required String contentTitle,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ReportContent(
        targetType: targetType,
        targetId: targetId,
        contentTitle: contentTitle,
      ),
    );
  }
}

class _ReportContent extends StatefulWidget {
  final ReportTargetType targetType;
  final String targetId;
  final String contentTitle;

  const _ReportContent({
    required this.targetType,
    required this.targetId,
    required this.contentTitle,
  });

  @override
  State<_ReportContent> createState() => _ReportContentState();
}

class _ReportContentState extends State<_ReportContent> {
  // Lấy danh sách lý do tương ứng với loại đối tượng
  List<String> get _reasons {
    switch (widget.targetType) {
      case ReportTargetType.user:
        return ReportService.userReasons;
      case ReportTargetType.song:
        return ReportService.songReasons;
      case ReportTargetType.moment:
        return ReportService.momentReasons;
      case ReportTargetType.comment:
        return ReportService.commentReasons;
    }
  }

  String? _selectedReason;
  final TextEditingController _descController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (_selectedReason == null) return;

    setState(() => _isSubmitting = true);

    try {
      await ReportService.instance.submitReport(
        targetType: widget.targetType,
        targetId: widget.targetId,
        reason: _selectedReason!,
        description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context); // Đóng modal
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cảm ơn bạn đã báo cáo. Chúng tôi sẽ xem xét sớm."),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lỗi gửi báo cáo. Vui lòng thử lại.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Để modal full chiều cao khi bàn phím hiện lên
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text("Báo cáo '${widget.contentTitle}'", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text("Hãy chọn lý do phù hợp:", style: TextStyle(color: Colors.grey)),

          const SizedBox(height: 15),

          // Danh sách lý do (Radio List)
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _reasons.length,
              itemBuilder: (context, index) {
                final reason = _reasons[index];
                return RadioListTile<String>(
                  title: Text(reason),
                  value: reason,
                  groupValue: _selectedReason,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFFF00CC),
                  onChanged: (val) => setState(() => _selectedReason = val),
                );
              },
            ),
          ),

          // Ô nhập thêm chi tiết (nếu cần)
          if (_selectedReason == "Khác" || _selectedReason != null) ...[
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                hintText: "Mô tả thêm (tuỳ chọn)...",
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 15),
          ],

          const SizedBox(height: 10),

          // Nút Gửi
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: (_selectedReason == null || _isSubmitting) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF00CC),
                foregroundColor: Colors.white,
              ),
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Gửi báo cáo", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}