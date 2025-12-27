import 'package:json_annotation/json_annotation.dart';

part 'song_model.g.dart';

// ==========================================
// 1. MODEL BÀI HÁT (Map từ API JSON)
// ==========================================
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

// ==========================================
// 2. MODEL LỜI BÀI HÁT (Dùng để hiển thị Karaoke)
// ==========================================

class LyricLine {
  final int startTime; // Thời gian bắt đầu (ms)
  final int endTime;   // Thời gian kết thúc (ms)
  final String content; // Nội dung cả dòng
  final List<LyricWord> words; // Danh sách các từ (để tô màu karaoke)

  LyricLine({
    required this.startTime,
    required this.endTime,
    required this.content,
    required this.words,
  });
}

class LyricWord {
  final String text;
  final int startTime;
  final int endTime;

  LyricWord({
    required this.text,
    required this.startTime,
    required this.endTime,
  });
}