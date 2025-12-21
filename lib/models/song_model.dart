import 'package:json_annotation/json_annotation.dart';

part 'song_model.g.dart';

@JsonSerializable()
class SongModel {
  @JsonKey(name: 'song_id')
  final int id;

  final String title;

  @JsonKey(name: 'artist_name')
  final String artistName;

  final String? genre;

  @JsonKey(name: 'image_url')
  final String? imageUrl;

  @JsonKey(name: 'beat_url')
  final String? beatUrl;

  @JsonKey(name: 'lyric_url')
  final String? lyricUrl;

  @JsonKey(name: 'vocal_url')
  final String? vocalUrl;

  @JsonKey(name: 'view_count', defaultValue: 0)
  final int viewCount;

  @JsonKey(name: 'created_at')
  final String? createdAt;

  SongModel({
    required this.id,
    required this.title,
    required this.artistName,
    this.genre,
    this.imageUrl,
    this.beatUrl,
    this.lyricUrl,
    this.vocalUrl,
    this.viewCount = 0,
    this.createdAt,
  });

  factory SongModel.fromJson(Map<String, dynamic> json) => _$SongModelFromJson(json);
  Map<String, dynamic> toJson() => _$SongModelToJson(this);
}