import 'package:json_annotation/json_annotation.dart';

part 'message_model.g.dart';

@JsonSerializable(includeIfNull: false)
class MessageModel {
  @JsonKey(name: 'message_id')
  final dynamic messageId;
  @JsonKey(name: 'sender_id')
  final String senderId;
  @JsonKey(name: 'receiver_id')
  final String receiverId;
  final String content;
  @JsonKey(name: 'is_read', defaultValue: false)
  final bool isRead;
  @JsonKey(name: 'sent_at')
  final DateTime? sentAt;

  MessageModel({
    this.messageId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.isRead = false,
    this.sentAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) => _$MessageModelFromJson(json);
  Map<String, dynamic> toJson() => _$MessageModelToJson(this);
}

class ChatPreviewModel {
  final String partnerId;
  final String fullName;
  final String? avatarUrl;
  final String lastMessage;
  final DateTime lastMessageTime;
  final bool isRead;
  final int unreadCount;

  ChatPreviewModel({
    required this.partnerId,
    required this.fullName,
    this.avatarUrl,
    required this.lastMessage,
    required this.lastMessageTime,
    this.isRead = true,
    this.unreadCount = 0,
  });

  // Tự viết hàm fromJson để đảm bảo nhận được unread_count từ SQL
  factory ChatPreviewModel.fromJson(Map<String, dynamic> json) {
    return ChatPreviewModel(
      partnerId: json['partner_id'] as String,
      fullName: json['full_name'] as String? ?? 'Người dùng',
      avatarUrl: json['avatar_url'] as String?,
      lastMessage: json['last_message'] as String? ?? '',
      lastMessageTime: DateTime.parse(json['last_message_time'] as String),
      isRead: json['is_read'] as bool? ?? true,
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'partner_id': partnerId,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime.toIso8601String(),
      'is_read': isRead,
      'unread_count': unreadCount,
    };
  }
}