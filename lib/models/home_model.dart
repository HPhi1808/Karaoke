import 'package:json_annotation/json_annotation.dart';
import 'song_model.dart';

part 'home_model.g.dart';

@JsonSerializable()
class HomeResponse {
  final List<SongModel> newest;
  final List<SongModel> popular;
  final List<SongModel> recommended;

  HomeResponse({
    required this.newest,
    required this.popular,
    required this.recommended,
  });

  factory HomeResponse.fromJson(Map<String, dynamic> json) => _$HomeResponseFromJson(json);
  Map<String, dynamic> toJson() => _$HomeResponseToJson(this);
}