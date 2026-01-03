import 'package:json_annotation/json_annotation.dart';

part 'user_model.g.dart';

@JsonSerializable()
class UserModel {
  final String id;
  final String? email;
  final String? username;
  @JsonKey(name: 'full_name')
  final String? fullName;
  @JsonKey(defaultValue: 'user')
  final String? role;
  @JsonKey(name: 'avatar_url')
  final String? avatarUrl;
  final String? bio;
  final String? gender;
  final String? region;
  final int followersCount;
  final int followingCount;
  final int likesCount;

  UserModel({
    required this.id,
    this.email,
    this.username,
    this.fullName,
    required this.role,
    this.avatarUrl,
    this.bio,
    this.gender,
    this.region,
    this.followersCount = 0,
    this.followingCount = 0,
    this.likesCount = 0,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String?,
      username: json['username'] as String?,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String?,
      bio: json['bio'] as String?,
      gender: json['gender'] as String?,
      region: json['region'] as String?,
      followersCount: json['followers_count'] != null ? json['followers_count'] as int : 0,
      followingCount: json['following_count'] != null ? json['following_count'] as int : 0,
      likesCount: json['likes_count'] != null ? json['likes_count'] as int : 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'role': role,
      'bio': bio,
      'gender': gender,
      'region': region,
    };
  }
}