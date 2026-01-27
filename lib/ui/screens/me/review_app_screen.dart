import 'package:flutter/material.dart';
import '../../../models/review_model.dart';
import '../../../services/review_service.dart';

class ReviewAppScreen extends StatefulWidget {
  const ReviewAppScreen({super.key});

  @override
  State<ReviewAppScreen> createState() => _ReviewAppScreenState();
}

class _ReviewAppScreenState extends State<ReviewAppScreen> {
  final TextEditingController _contentController = TextEditingController();
  int _currentRating = 5;
  bool _isLoading = true;
  ReviewModel? _myReview;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadMyData();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  // --- LOGIC ---

  Future<void> _loadMyData() async {
    setState(() => _isLoading = true);
    try {
      final review = await ReviewService.instance.fetchMyReview();
      if (mounted) {
        setState(() {
          _myReview = review;
          _isLoading = false;

          // Reset form state
          _isEditing = false;
          _contentController.clear();
          _currentRating = 5;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleSubmit() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vui lòng viết nội dung đánh giá")),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_myReview == null) {
        // Trường hợp 1: Tạo mới
        await ReviewService.instance.addReview(_currentRating, _contentController.text.trim());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cảm ơn đánh giá của bạn!")));
      } else {
        // Trường hợp 2: Cập nhật
        await ReviewService.instance.updateReview(_currentRating, _contentController.text.trim());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã cập nhật đánh giá!")));
      }

      // Load lại dữ liệu mới nhất
      await _loadMyData();

    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _handleDelete() async {
    // Show confirm dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận xoá"),
        content: const Text("Bạn có chắc muốn xoá đánh giá này không?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Xoá", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await ReviewService.instance.deleteReview();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã xoá đánh giá.")));
      await _loadMyData();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _startEditing() {
    if (_myReview != null) {
      setState(() {
        _isEditing = true;
        _currentRating = _myReview!.rating;
        _contentController.text = _myReview!.comment ?? "";
      });
    }
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _contentController.clear();
    });
  }

  // --- WIDGETS ---

  Widget _buildStarRatingInput() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return IconButton(
          onPressed: () {
            setState(() {
              _currentRating = index + 1;
            });
          },
          icon: Icon(
            index < _currentRating ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: 36,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        );
      }),
    );
  }

  // Widget hiển thị Form nhập liệu (Dùng cho cả Tạo Mới và Chỉnh Sửa)
  Widget _buildInputForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Text(
            _myReview == null ? "Bạn thấy ứng dụng thế nào?" : "Chỉnh sửa đánh giá",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 16),
          _buildStarRatingInput(),
          const SizedBox(height: 20),
          TextField(
            controller: _contentController,
            maxLines: 4,
            maxLength: 150,
            decoration: InputDecoration(
              hintText: "Nhập đánh giá của bạn (tối đa 150 ký tự)...",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              counterText: "",
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // Nút Hủy (chỉ hiện khi đang Edit)
              if (_isEditing)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: OutlinedButton(
                      onPressed: _cancelEditing,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text("Hủy"),
                    ),
                  ),
                ),

              // Nút Gửi/Lưu
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text(
                    _myReview == null ? "Gửi đánh giá" : "Cập nhật",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Widget hiển thị Review đã có
  Widget _buildExistingReview() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: Colors.blue.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 48),
          const SizedBox(height: 12),
          const Text(
            "Cảm ơn đánh giá của bạn!",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) => Icon(
              index < (_myReview?.rating ?? 0) ? Icons.star : Icons.star_border,
              color: Colors.amber,
              size: 28,
            )),
          ),

          const SizedBox(height: 16),
          Text(
            _myReview?.comment ?? "",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: _handleDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text("Xoá", style: TextStyle(color: Colors.red)),
              ),
              ElevatedButton.icon(
                onPressed: _startEditing,
                icon: const Icon(Icons.edit, size: 18),
                label: const Text("Chỉnh sửa"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  foregroundColor: Colors.blue,
                  elevation: 0,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Đánh giá ứng dụng", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // LOGIC HIỂN THỊ UI
            // 1. Nếu chưa có review -> Hiện form nhập
            // 2. Nếu đã có review VÀ đang bấm sửa -> Hiện form nhập (kèm dữ liệu cũ)
            // 3. Nếu đã có review VÀ không sửa -> Hiện thông tin review

            if (_myReview == null || _isEditing)
              _buildInputForm()
            else
              _buildExistingReview(),
          ],
        ),
      ),
    );
  }
}