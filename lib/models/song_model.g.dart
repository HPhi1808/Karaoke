// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'song_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SongModel _$SongModelFromJson(Map<String, dynamic> json) => SongModel(
      id: (json['song_id'] as num).toInt(),
      title: json['title'] as String,
      artistName: json['artist_name'] as String,
      genre: json['genre'] as String?,
      imageUrl: json['image_url'] as String?,
      beatUrl: json['beat_url'] as String?,
      lyricUrl: json['lyric_url'] as String?,
      vocalUrl: json['vocal_url'] as String?,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String?,
    );

Map<String, dynamic> _$SongModelToJson(SongModel instance) => <String, dynamic>{
      'song_id': instance.id,
      'title': instance.title,
      'artist_name': instance.artistName,
      'genre': instance.genre,
      'image_url': instance.imageUrl,
      'beat_url': instance.beatUrl,
      'lyric_url': instance.lyricUrl,
      'vocal_url': instance.vocalUrl,
      'view_count': instance.viewCount,
      'created_at': instance.createdAt,
    };
