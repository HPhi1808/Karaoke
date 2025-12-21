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
  final String role;
  @JsonKey(name: 'avatar_url')
  final String? avatarUrl;
  final String? bio;
  final String? gender;
  final String? region;

  UserModel({
    required this.id,
    this.email,
    this.username,
    this.fullName,
    required this.role,
    this.avatarUrl,
    this.bio,
    this.gender,
    this.region
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => _$UserModelFromJson(json);
  Map<String, dynamic> toJson() => _$UserModelToJson(this);
}