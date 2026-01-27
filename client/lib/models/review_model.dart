class ReviewModel {
  final int id;
  final String userId;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  // Thông tin người dùng
  final String userName;
  final String avatarUrl;

  ReviewModel({
    required this.id,
    required this.userId,
    required this.rating,
    this.comment,
    required this.createdAt,
    required this.userName,
    required this.avatarUrl,
  });

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    final profile = json['users'] as Map<String, dynamic>?;

    return ReviewModel(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      rating: json['rating'] as int,
      comment: json['comment'] as String?,
      createdAt: DateTime.parse(json['created_at']),
      userName: profile?['full_name'] ?? profile?['username'] ?? 'Người dùng ẩn danh',
      avatarUrl: profile?['avatar_url'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'rating': rating,
      'comment': comment,
    };
  }
}