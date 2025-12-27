import 'package:dio/dio.dart';
import '../models/song_model.dart';
import 'api_client.dart';

class SongService {
  static final SongService instance = SongService._internal();
  SongService._internal();

  final Dio _dio = ApiClient.instance.dio;

  // --- API METHODS ---

  Future<SongResponse> getSongsOverview() async {
    try {
      final response = await _dio.get('/api/songs/songs');

      return SongResponse.fromJson(response.data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<SongModel>> searchSongs(String query) async {
    try {
      final response = await _dio.get('/api/songs', queryParameters: {'q': query});

      if (response.data is List) {
        return (response.data as List).map((e) => SongModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<SongModel> getSongDetail(int id) async {
    try {
      final response = await _dio.get('/api/songs/$id');
      return SongModel.fromJson(response.data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> incrementView(int id) async {
    try {
      await _dio.post('/api/songs/$id/view');
    } catch (e) {
      print("Error increment view: $e");
    }
  }

  // --- HELPER XỬ LÝ LỖI ---
  Exception _handleError(dynamic error) {
    if (error is DioException) {
      if (error.response?.data != null && error.response?.data is Map) {
        final data = error.response?.data as Map;
        if (data['message'] != null) return Exception(data['message']);
        if (data['error'] != null) return Exception(data['error']);
      }
      return Exception(error.message ?? "Lỗi kết nối server");
    }
    return Exception("Lỗi không xác định: $error");
  }
}