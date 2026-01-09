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
