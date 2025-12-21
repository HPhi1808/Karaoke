// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserModel _$UserModelFromJson(Map<String, dynamic> json) => UserModel(
      id: json['id'] as String,
      email: json['email'] as String?,
      username: json['username'] as String?,
      fullName: json['full_name'] as String?,
      role: json['role'] as String? ?? 'user',
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      gender: json['gender'] as String?,
      region: json['region'] as String?,
    );

Map<String, dynamic> _$UserModelToJson(UserModel instance) => <String, dynamic>{
      'id': instance.id,
      'email': instance.email,
      'username': instance.username,
      'full_name': instance.fullName,
      'role': instance.role,
      'avatar_url': instance.avatarUrl,
      'bio': instance.bio,
      'gender': instance.gender,
      'region': instance.region,
    };
