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
