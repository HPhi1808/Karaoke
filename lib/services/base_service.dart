import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class BaseService {

  // Hàm bao bọc: Tự động retry nếu mất mạng
  Future<T> safeExecution<T>(Future<T> Function() action) async {
    while (true) {
      try {
        return await action();
      } catch (e) {
        if (_isNetworkError(e)) {
          print("⚠️ BaseService: Mất kết nối mạng -> $e");

          final shouldRetry = await _showRetryDialog();
          if (shouldRetry) {
            continue; // Thử lại
          }
        }
        rethrow; // Ném lỗi khác ra ngoài
      }
    }
  }

  bool _isNetworkError(dynamic error) {
    String msg = error.toString().toLowerCase();
    return error is SocketException ||
        msg.contains("socketexception") ||
        msg.contains("connection refused") ||
        msg.contains("network is unreachable") ||
        msg.contains("connection timed out") ||
        msg.contains("failed to connect") ||
        msg.contains("network request failed");
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