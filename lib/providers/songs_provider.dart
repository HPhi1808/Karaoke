import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../services/song_service.dart';

class SongsProvider extends ChangeNotifier {
  SongResponse? _data;
  SongResponse? get data => _data;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Set<int> _likedSongIds = {};

  List<SongModel> _drawerSongs = [];
  List<SongModel> get drawerSongs => _drawerSongs;

  bool _isDrawerLoading = false;
  bool get isDrawerLoading => _isDrawerLoading;

  bool _hasMoreDrawerSongs = true;
  int _drawerPage = 0;
  final int _drawerLimit = 10;

  SongsProvider() {
    fetchSongsData();
  }

  bool isSongLiked(int songId) {
    return _likedSongIds.contains(songId);
  }

  // ===============================================
  // HÀM LẤY DỮ LIỆU
  // ===============================================
  Future<void> fetchSongsData() async {
    _isLoading = true;
    _errorMessage = null;

    try {
      final results = await Future.wait([
        SongService.instance.getSongsOverview(),
        SongService.instance.getFavoriteSongs(),
      ]);

      _data = results[0] as SongResponse;

      final favoriteSongs = results[1] as List<SongModel>;
      _likedSongIds = favoriteSongs.map((e) => e.id).toSet();

    } catch (e) {
      _errorMessage = "Lỗi kết nối: ${e.toString()}";
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> initDrawerData() async {
    _drawerSongs = [];
    _drawerPage = 0;
    _hasMoreDrawerSongs = true;
    _isDrawerLoading = false;
    notifyListeners();
    await loadMoreDrawerSongs();
  }

  Future<void> loadMoreDrawerSongs() async {
    if (_isDrawerLoading || !_hasMoreDrawerSongs) return;

    _isDrawerLoading = true;
    notifyListeners();

    try {
      final newSongs = await SongService.instance.getSongsPagination(_drawerPage, _drawerLimit);

      if (newSongs.isEmpty) {
        _hasMoreDrawerSongs = false;
      } else {
        _drawerSongs.addAll(newSongs);
        _drawerPage++;

        if (newSongs.length < _drawerLimit) {
          _hasMoreDrawerSongs = false;
        }
      }
    } catch (e) {
      debugPrint("Lỗi load drawer: $e");
    } finally {
      _isDrawerLoading = false;
      notifyListeners();
    }
  }

  // ===============================================
  // HÀM THẢ TIM / BỎ TIM
  // ===============================================
  Future<void> toggleLike(int songId) async {
    // 1. Optimistic Update
    final isCurrentlyLiked = _likedSongIds.contains(songId);

    if (isCurrentlyLiked) {
      _likedSongIds.remove(songId);
    } else {
      _likedSongIds.add(songId);
    }
    notifyListeners();

    // 2. Gọi API Supabase xử lý ngầm
    try {
      await SongService.instance.toggleFavorite(songId);
    } catch (e) {
      debugPrint("Lỗi toggle like: $e");

      // 3. Rollback (Nếu API lỗi thì hoàn tác lại trạng thái cũ)
      if (isCurrentlyLiked) {
        _likedSongIds.add(songId);
      } else {
        _likedSongIds.remove(songId);
      }
      notifyListeners();
    }
  }

  // Hàm tăng view khi chọn bài
  Future<void> onSongSelected(int songId) async {
    try {
      await SongService.instance.incrementView(songId);
    } catch (e) {
      debugPrint("Lỗi tăng view: $e");
    }
  }
}