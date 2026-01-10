import 'package:flutter/material.dart';
import '../../../models/review_model.dart';
import '../../../models/user_model.dart'; // <--- NHỚ IMPORT MODEL NÀY
import '../../../services/review_service.dart';
import 'user_profile_screen.dart';

class ReviewAppScreen extends StatefulWidget {
  const ReviewAppScreen({super.key});

  @override
  State<ReviewAppScreen> createState() => _ReviewAppScreenState();
}

class _ReviewAppScreenState extends State<ReviewAppScreen> {
  // --- STATE VARIABLES ---
  final TextEditingController _contentController = TextEditingController();
  int _currentRating = 5;

  List<ReviewModel> _reviews = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  final int _limit = 10;
  int _currentOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  // --- LOGIC GỌI SUPABASE ---

  // 1. Tải dữ liệu lần đầu
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      _currentOffset = 0;
      final reviews = await ReviewService.instance.fetchReviews(limit: _limit, offset: 0);

      if (mounted) {
        setState(() {
          _reviews = reviews;
          _isLoading = false;
          _hasMore = reviews.length >= _limit;
          _currentOffset = reviews.length;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi tải dữ liệu: $e")));
      }
    }
  }

  // 2. Tải thêm dữ liệu
  Future<void> _loadMoreReviews() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final moreReviews = await ReviewService.instance.fetchReviews(limit: _limit, offset: _currentOffset);

      if (mounted) {
        setState(() {
          _reviews.addAll(moreReviews);
          _isLoadingMore = false;
          _currentOffset += moreReviews.length;
          if (moreReviews.length < _limit) {
            _hasMore = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi tải thêm: $e")));
      }
    }
  }

  // 3. Gửi đánh giá mới
  Future<void> _submitReview() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vui lòng viết nội dung đánh giá")),
      );
      return;
    }

    try {
      await ReviewService.instance.addReview(_currentRating, _contentController.text.trim());

      _contentController.clear();
      setState(() => _currentRating = 5);

      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cảm ơn bạn đã đánh giá!")),
      );

      _loadInitialData();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  // --- WIDGET BUILDERS ---

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
            size: 32,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        );
      }),
    );
  }

  // --- PHẦN QUAN TRỌNG: SỬA LOGIC CLICK AVATAR ---
  Widget _buildReviewItem(ReviewModel review) {
    bool hasAvatar = review.avatarUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // BỌC GESTURE DETECTOR ĐỂ BẮT SỰ KIỆN CLICK
              GestureDetector(
                onTap: () {
                  // 1. Tạo UserModel tạm thời từ thông tin Review
                  // (UserProfileScreen sẽ tự load thêm bio/stats sau)
                  final userFromReview = UserModel(
                    id: review.userId, // QUAN TRỌNG: ReviewModel PHẢI CÓ userId
                    fullName: review.userName,
                    avatarUrl: review.avatarUrl,
                    role: 'user', // Mặc định
                    // Các trường khác để null hoặc mặc định
                  );

                  // 2. Chuyển hướng
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfileScreen(user: userFromReview),
                    ),
                  );
                },
                child: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  backgroundImage: hasAvatar ? NetworkImage(review.avatarUrl) : null,
                  child: !hasAvatar
                      ? Text(
                    review.userName.isNotEmpty ? review.userName[0].toUpperCase() : "?",
                    style: const TextStyle(color: Colors.blue),
                  )
                      : null,
                ),
              ),

              const SizedBox(width: 12),

              // Thông tin tên và rating
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Bạn cũng có thể bọc tên trong GestureDetector nếu muốn click tên cũng mở profile
                    Text(review.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Row(
                      children: List.generate(5, (index) => Icon(
                        index < review.rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 14,
                      )),
                    ),
                  ],
                ),
              ),

              Text(
                "${review.createdAt.day}/${review.createdAt.month}/${review.createdAt.year}",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(review.comment ?? "", style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Đánh giá ứng dụng", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitialData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PHẦN 1: USER VIẾT ĐÁNH GIÁ
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text("Bạn cảm thấy ứng dụng thế nào?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    _buildStarRatingInput(),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _contentController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: "Viết cảm nhận của bạn...",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitReview,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("Gửi đánh giá", style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Text("Đánh giá từ cộng đồng", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              // PHẦN 2: DANH SÁCH ĐÁNH GIÁ
              if (_isLoading)
                const Center(child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(),
                ))
              else if (_reviews.isEmpty)
                const Center(child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text("Chưa có đánh giá nào. Hãy là người đầu tiên!", style: TextStyle(color: Colors.grey)),
                ))
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _reviews.length,
                  itemBuilder: (context, index) {
                    return _buildReviewItem(_reviews[index]);
                  },
                ),

              // PHẦN 3: NÚT TẢI THÊM
              if (_hasMore && !_isLoading && _reviews.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 20),
                  child: Center(
                    child: _isLoadingMore
                        ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2)
                    )
                        : TextButton(
                      onPressed: _loadMoreReviews,
                      child: const Text("Tải thêm đánh giá", style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),

              if (!_hasMore && _reviews.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: Text("Đã hiển thị tất cả đánh giá", style: TextStyle(color: Colors.grey))),
                ),
            ],
          ),
        ),
      ),
    );
  }
}