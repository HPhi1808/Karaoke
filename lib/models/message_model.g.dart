// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MessageModel _$MessageModelFromJson(Map<String, dynamic> json) => MessageModel(
      messageId: json['message_id'],
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String,
      content: json['content'] as String,
      isRead: json['is_read'] as bool? ?? false,
      sentAt: json['sent_at'] == null
          ? null
          : DateTime.parse(json['sent_at'] as String),
    );

Map<String, dynamic> _$MessageModelToJson(MessageModel instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('message_id', instance.messageId);
  val['sender_id'] = instance.senderId;
  val['receiver_id'] = instance.receiverId;
  val['content'] = instance.content;
  val['is_read'] = instance.isRead;
  writeNotNull('sent_at', instance.sentAt?.toIso8601String());
  return val;
}

ChatPreviewModel _$ChatPreviewModelFromJson(Map<String, dynamic> json) =>
    ChatPreviewModel(
      partnerId: json['partner_id'] as String,
      fullName: json['full_name'] as String? ?? 'Người dùng',
      avatarUrl: json['avatar_url'] as String?,
      lastMessage: json['last_message'] as String? ?? '',
      lastMessageTime: DateTime.parse(json['last_message_time'] as String),
      isRead: json['is_read'] as bool? ?? true,
    );

Map<String, dynamic> _$ChatPreviewModelToJson(ChatPreviewModel instance) =>
    <String, dynamic>{
      'partner_id': instance.partnerId,
      'full_name': instance.fullName,
      'avatar_url': instance.avatarUrl,
      'last_message': instance.lastMessage,
      'last_message_time': instance.lastMessageTime.toIso8601String(),
      'is_read': instance.isRead,
    };
