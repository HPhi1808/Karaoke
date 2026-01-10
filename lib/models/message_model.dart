import 'package:json_annotation/json_annotation.dart';

part 'message_model.g.dart';

// --- MODEL 1: TIN NHẮN CHI TIẾT ---
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

// --- MODEL 2: XEM TRƯỚC TIN NHẮN ---
@JsonSerializable()
class ChatPreviewModel {
  @JsonKey(name: 'partner_id')
  final String partnerId;

  @JsonKey(name: 'full_name', defaultValue: 'Người dùng')
  final String fullName;

  @JsonKey(name: 'avatar_url')
  final String? avatarUrl;

  @JsonKey(name: 'last_message', defaultValue: '')
  final String lastMessage;

  @JsonKey(name: 'last_message_time')
  final DateTime lastMessageTime;

  @JsonKey(name: 'is_read', defaultValue: true)
  final bool isRead;

  ChatPreviewModel({
    required this.partnerId,
    required this.fullName,
    this.avatarUrl,
    required this.lastMessage,
    required this.lastMessageTime,
    this.isRead = true,
  });

  factory ChatPreviewModel.fromJson(Map<String, dynamic> json) => _$ChatPreviewModelFromJson(json);
  Map<String, dynamic> toJson() => _$ChatPreviewModelToJson(this);
}