import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import '../models/home_model.dart';
import '../models/song_model.dart';
import '../models/user_model.dart';

class ApiService {
  // 1. Cấu hình Singleton
  static final ApiService instance = ApiService._internal();

  late final Dio _dio;

  final SupabaseClient _supabase = Supabase.instance.client;

  // static const String _baseUrl = "http://10.0.2.2:3000";

  final String _baseUrl = 'https://karaoke-server-paan.onrender.com';


  ApiService._internal() {
    BaseOptions options = BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );

    _dio = Dio(options);

    // --- QUAN TRỌNG: INTERCEPTOR GẮN TOKEN SUPABASE ---
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Lấy Access Token hiện tại từ Supabase SDK
        final session = Supabase.instance.client.auth.currentSession;
        final token = session?.accessToken;

        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) {
        print("API Error: ${e.response?.statusCode} - ${e.requestOptions.path}");
        return handler.next(e);
      },
    ));

    // Log body để debug (tùy chọn)
    _dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }

  // --- 1. USER DATA APIs ---

  // Lấy thông tin profile chi tiết từ DB (Node.js gọi bảng users)
  Future<UserModel> getUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("Chưa đăng nhập");

    try {
      // 1. Gọi trực tiếp vào bảng 'users' của Supabase
      // SDK này tự động gửi Token, không lo bị lỗi 401
      final data = await _supabase
          .from('users')
          .select()           // Lấy tất cả các cột
          .eq('id', user.id)  // Điều kiện: ID trùng với user đang đăng nhập
          .single();          // Lấy 1 dòng duy nhất

      // 2. Map dữ liệu trả về vào Model
      return UserModel.fromJson(data);

    } catch (e) {
      print("❌ Lỗi lấy profile từ Supabase: $e");

      // Kiểm tra xem lỗi có phải do chưa bật RLS không
      if (e.toString().contains("PGRST116") || e.toString().contains("Row not found")) {
        throw Exception("Không tìm thấy dữ liệu. Hãy kiểm tra lại Policy RLS trong Database!");
      }

      rethrow;
    }
  }

  // --- 2. SONG APIs ---

  // Lấy dữ liệu trang chủ (Node.js tổng hợp Newest, Popular...)
  Future<HomeResponse> getHomeData() async {
    try {
      final response = await _dio.get('api/songs/home');
      return HomeResponse.fromJson(response.data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // Tìm kiếm bài hát
  Future<List<SongModel>> searchSongs(String query) async {
    try {
      final response = await _dio.get(
        'api/songs',
        queryParameters: {'q': query},
      );

      if (response.data is List) {
        return (response.data as List).map((e) => SongModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  // Lấy chi tiết bài hát
  Future<SongModel> getSongDetail(int id) async {
    try {
      final response = await _dio.get('api/songs/$id');
      return SongModel.fromJson(response.data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // Tăng lượt view (Gửi request fire-and-forget)
  Future<void> incrementView(int id) async {
    try {
      await _dio.post('api/songs/$id/view');
    } catch (e) {
      print("Error increment view: $e");
    }
  }

  // --- HELPER: XỬ LÝ LỖI ---
  Exception _handleError(dynamic error) {
    if (error is DioException) {
      if (error.response?.data != null && error.response?.data is Map) {
        final data = error.response?.data as Map;
        // Ưu tiên lấy message từ server trả về
        if (data['message'] != null) {
          return Exception(data['message']);
        }
        if (data['error'] != null) {
          return Exception(data['error']);
        }
      }
      return Exception(error.message ?? "Lỗi kết nối server");
    }
    return Exception("Lỗi không xác định: $error");
  }
}