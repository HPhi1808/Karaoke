class Moment {
  final int id;
  final String userId;
  final String audioUrl;
  final String? description;
  final DateTime createdAt;
  final String visibility;
  final String? userName;
  final String? userAvatar;
  final int likesCount;
  final int commentsCount;
  final bool isLiked;

  Moment({
    required this.id,
    required this.userId,
    required this.audioUrl,
    this.description,
    required this.createdAt,
    required this.visibility,
    this.userName,
    this.userAvatar,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.isLiked = false,
  });

  factory Moment.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    String getUserName() {
      if (json['user_full_name'] != null) return json['user_full_name'];
      if (json['users'] != null && json['users']['full_name'] != null) {
        return json['users']['full_name'];
      }
      return 'Người dùng';
    }

    String? getUserAvatar() {
      if (json['user_avatar_url'] != null) return json['user_avatar_url'];
      if (json['users'] != null) return json['users']['avatar_url'];
      return null;
    }

    return Moment(
      id: parseInt(json['moment_id']),
      userId: json['user_id'] ?? '',
      audioUrl: json['audio_url'] ?? '',
      description: json['description'],

      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),

      visibility: json['visibility'] ?? 'public',

      userName: getUserName(),
      userAvatar: getUserAvatar(),

      likesCount: parseInt(json['likes_count']),
      commentsCount: parseInt(json['comments_count']),

      isLiked: json['is_liked'] ?? false,
    );
  }

  Moment copyWith({bool? isLiked, int? likesCount, int? commentsCount}) {
    return Moment(
      id: id, userId: userId, audioUrl: audioUrl, description: description,
      createdAt: createdAt, visibility: visibility, userName: userName, userAvatar: userAvatar,
      isLiked: isLiked ?? this.isLiked,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
    );
  }
}