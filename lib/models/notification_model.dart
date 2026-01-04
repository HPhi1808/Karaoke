class NotificationModel {
  final int id;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final String type; // 'like', 'comment', 'follow', 'system'
  final String category; // 'personal' hoặc 'system'

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
    required this.type,
    required this.category,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'],
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      createdAt: DateTime.parse(json['created_at']).toLocal(),
      isRead: json['is_read'] ?? false,
      type: json['type'] ?? 'system',
      category: json['category'] ?? 'personal',
    );
  }
}