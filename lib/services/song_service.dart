import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/song_model.dart';
import 'base_service.dart';

class SongService extends BaseService {
  static final SongService instance = SongService._internal();
  SongService._internal();
  final SupabaseClient _supabase = Supabase.instance.client;
  static const Duration _timeOutDuration = Duration(seconds: 15);
  String? _cachedDeviceId;

  // ===========================
  // 1. CÁC HÀM LẤY DỮ LIỆU
  // ===========================

  Future<SongResponse> getSongsOverview() async {
    return await safeExecution(() async {
      final results = await Future.wait([
        _getNewestSongs(10),
        _getPopularSongs(10),
        _getRandomSongs(10),
      ]);

      return SongResponse(
        newest: results[0],
        popular: results[1],
        recommended: results[2],
      );
    });
  }

  Future<List<SongModel>> getTopViewedSongs({int limit = 5}) async {
    try {
      final List<dynamic> response = await _supabase.rpc(
        'get_top_viewed_songs',
        params: {'p_limit': limit},
      );

      if (response.isEmpty) return [];

      return response.map((item) => SongModel.fromJson(item)).toList();
    } catch (e) {
      debugPrint("🔴 Lỗi lấy Top Songs: $e");
      return [];
    }
  }

  Future<List<SongModel>> searchSongs(String query) async {
    return await safeExecution(() async {
      final response = await _supabase
          .from('songs')
          .select()
          .ilike('title', '%$query%')
          .timeout(_timeOutDuration);

      return (response as List).map((e) => SongModel.fromJson(e)).toList();
    });
  }

  Future<SongModel> getSongDetail(int id) async {
    return await safeExecution(() async {
      final response = await _supabase
          .from('songs')
          .select()
          .eq('song_id', id)
          .single()
          .timeout(_timeOutDuration);

      return SongModel.fromJson(response);
    });
  }

  Future<String> _getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('device_uuid');

    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('device_uuid', id);
    }

    _cachedDeviceId = id;
    return id;
  }

  Future<void> incrementView(int id) async {
    try {
      final deviceId = await _getDeviceId();
      await _supabase
          .rpc('increment_view', params: {
        'row_id': id,
        'device_id': deviceId
      })
          .timeout(const Duration(seconds: 5));

    } catch (e) {
      debugPrint("Lỗi tăng view: $e");
    }
  }

  Future<List<SongModel>> getSongsPagination(int page, int limit) async {
    try {
      final int from = page * limit;
      final int to = from + limit - 1;
      final response = await _supabase
          .from('songs')
          .select()
          .order('view_count', ascending: false)
          .range(from, to);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => SongModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint("Lỗi getSongsPagination: $e");
      rethrow;
    }
  }

  // =========================
  // 2. CÁC HÀM FAVORITE
  // =========================

  Future<List<SongModel>> getFavoriteSongs() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    return await safeExecution(() async {
      final response = await _supabase
          .from('songs')
          .select('*, favorites!inner(*)')
          .eq('favorites.user_id', userId)
          .order('created_at', ascending: false, referencedTable: 'favorites')
          .timeout(_timeOutDuration);

      return (response as List).map((e) => SongModel.fromJson(e)).toList();
    });
  }

  Future<bool> isSongLiked(int songId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;
    return await safeExecution(() async {
      final response = await _supabase
          .from('favorites')
          .select('id')
          .eq('user_id', userId)
          .eq('song_id', songId)
          .maybeSingle()
          .timeout(_timeOutDuration);
      return response != null;
    });
  }

  Future<bool> toggleFavorite(int songId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception("Vui lòng đăng nhập");

    return await safeExecution(() async {
      final checkResponse = await _supabase
          .from('favorites')
          .select('id')
          .eq('user_id', userId)
          .eq('song_id', songId)
          .maybeSingle()
          .timeout(_timeOutDuration);

      final isLiked = checkResponse != null;

      if (isLiked) {
        await _supabase
            .from('favorites')
            .delete()
            .eq('user_id', userId)
            .eq('song_id', songId)
            .timeout(_timeOutDuration);
        return false;
      } else {
        await _supabase
            .from('favorites')
            .insert({'user_id': userId, 'song_id': songId})
            .timeout(_timeOutDuration);
        return true;
      }
    });
  }

  // =============================
  // 3. PRIVATE HELPER METHODS
  // =============================

  Future<List<SongModel>> _getNewestSongs(int limit) async {
    final response = await _supabase
        .from('songs')
        .select()
        .order('created_at', ascending: false)
        .limit(limit)
        .timeout(_timeOutDuration);
    return (response as List).map((e) => SongModel.fromJson(e)).toList();
  }

  Future<List<SongModel>> _getPopularSongs(int limit) async {
    final response = await _supabase
        .from('songs')
        .select()
        .order('view_count', ascending: false)
        .limit(limit)
        .timeout(_timeOutDuration);
    return (response as List).map((e) => SongModel.fromJson(e)).toList();
  }

  Future<List<SongModel>> _getRandomSongs(int limit) async {
    try {
      final response = await _supabase
          .rpc('get_random_songs', params: {'limit_count': limit})
          .timeout(_timeOutDuration);
      return (response as List).map((e) => SongModel.fromJson(e)).toList();
    } catch (e) {
      return _getNewestSongs(limit);
    }
  }
}