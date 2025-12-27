import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

class ApiClient {
  static final ApiClient instance = ApiClient._internal();

  late final Dio dio;

  static const String baseUrl = "http://10.0.2.2:3000";

  // static const String baseUrl = 'https://karaoke-server-paan.onrender.com';

  ApiClient._internal() {
    BaseOptions options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );

    dio = Dio(options);

    // --- INTERCEPTOR: Tự động gắn Token Supabase vào header ---
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
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

    // Log body để debug
    dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }
}