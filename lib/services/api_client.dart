import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;
import '../utils/user_manager.dart';

class ApiClient {
  static final ApiClient instance = ApiClient._internal();

  late final Dio dio;

  // static const String baseUrl = "http://10.0.2.2:3000";
  static const String baseUrl = 'https://karaokeplus.cloud';

  ApiClient._internal() {
    BaseOptions options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );

    dio = Dio(options);

    // --- INTERCEPTOR: Tự động gắn Token & BÁO CÁO HOẠT ĐỘNG ---
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        UserManager.instance.notifyApiActivity();

        final session = Supabase.instance.client.auth.currentSession;
        final token = session?.accessToken;

        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) {
        print("🔴 API Error: ${e.response?.statusCode} - ${e.requestOptions.path}");
        return handler.next(e);
      },
    ));

    // Log body
    dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }
}