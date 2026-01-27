class NotificationModel {
  final int id;
  final String title;
  final String message;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isRead;
  final String type; // 'like', 'comment', 'follow', 'system'
  final String category; // 'personal' hoặc 'system'
  final String? actorId;
  final String? actorAvatarUrl;
  final int? momentId;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.updatedAt,
    required this.isRead,
    required this.type,
    required this.category,
    this.actorId,
    this.actorAvatarUrl,
    this.momentId

  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'],
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      createdAt: DateTime.parse(json['created_at']).toLocal(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : DateTime.parse(json['created_at']),
      isRead: json['is_read'] ?? false,
      type: json['type'] ?? 'system',
      category: json['category'] ?? 'personal',
      actorId: json['actor_id'],
      actorAvatarUrl: json['actor_avatar_url'],
      momentId: json['moment_id'],
    );
  }
}