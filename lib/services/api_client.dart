import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;
import '../utils/user_manager.dart';
import '../main.dart';

class ApiClient {
  static final ApiClient instance = ApiClient._internal();

  late final Dio dio;
  // static const String baseUrl = "http://10.0.2.2:3000";
  static const String baseUrl = 'https://karaokeplus.cloud';

  ApiClient._internal() {
    BaseOptions options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );

    dio = Dio(options);

    // 1. Interceptor gắn Token & Notify
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
    ));

    // 2. Interceptor Xử lý lỗi mạng & Retry
    dio.interceptors.add(InterceptorsWrapper(
      onError: (DioException e, handler) async {
        // Kiểm tra xem có phải lỗi mạng không
        if (_isNetworkError(e)) {
          print("🔴 Mất kết nối mạng: ${e.message}");

          // Hiện Dialog và chờ người dùng chọn
          bool shouldRetry = await _showRetryDialog();

          if (shouldRetry) {
            try {
              // Gửi lại chính request vừa bị lỗi
              // e.requestOptions chứa đầy đủ thông tin của request cũ (url, data, header...)
              final response = await dio.fetch(e.requestOptions);

              // Nếu gửi lại thành công -> Trả về kết quả như chưa từng có cuộc chia ly
              return handler.resolve(response);
            } catch (retryError) {
              // Nếu thử lại mà vẫn lỗi -> Trả về lỗi mới (để vòng lặp sau bắt tiếp hoặc văng ra ngoài)
              return handler.next(retryError as DioException);
            }
          }
        }

        // Nếu không phải lỗi mạng hoặc người dùng chọn "Hủy" -> Ném lỗi ra ngoài
        print("🔴 API Error: ${e.response?.statusCode} - ${e.requestOptions.path}");
        return handler.next(e);
      },
    ));

    // 3. Log
    dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }

  // --- Các hàm hỗ trợ private ---

  bool _isNetworkError(DioException error) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        (error.error is SocketException) ||
        (error.message != null && error.message!.contains("SocketException"));
  }

  Future<bool> _showRetryDialog() async {
    final context = navigatorKey.currentContext;
    if (context == null) return true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text("Mất kết nối Internet"),
          content: const Text("Vui lòng kiểm tra đường truyền và thử lại."),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              child: const Text("Thử lại"),
            ),
          ],
        ),
      ),
    );
    return true;
  }
}