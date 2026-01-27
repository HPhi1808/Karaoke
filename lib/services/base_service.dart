import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart';

class BaseService {

  static bool _isDialogShowing = false;

  static Completer<bool>? _retryCompleter;

  Future<T> safeExecution<T>(Future<T> Function() action, {int maxSilentRetries = 2}) async {
    int attempt = 0;
    while (true) {
      try {
        return await action();
      } catch (e) {
        if (_isNetworkError(e)) {
          if (attempt < maxSilentRetries) {
            attempt++;
            debugPrint("🔄 Lỗi mạng ($e). Thử lại lần $attempt...");
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          }
          debugPrint("⚠️ Thất bại sau $attempt lần thử -> Cần hiện Dialog.");
          bool shouldRetry;
          if (_isDialogShowing) {
            debugPrint("⏳ Đang có Dialog khác, chờ kết quả...");
            shouldRetry = await _retryCompleter!.future;
          } else {
            _isDialogShowing = true;
            _retryCompleter = Completer<bool>();
            shouldRetry = await _showRetryDialog();
            _retryCompleter!.complete(shouldRetry);
            _isDialogShowing = false;
            _retryCompleter = null;
          }
          if (shouldRetry) {
            attempt = 0;
            continue;
          }
        }
        rethrow;
      }
    }
  }

  bool _isNetworkError(dynamic error) {
    String msg = error.toString().toLowerCase();
    return error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException ||
        msg.contains("socketexception") ||
        msg.contains("timeout") ||
        msg.contains("connection refused") ||
        msg.contains("network is unreachable") ||
        msg.contains("connection timed out") ||
        msg.contains("failed to connect") ||
        msg.contains("network request failed") ||
        msg.contains("connection reset by peer") ||
        msg.contains("broken pipe") ||
        msg.contains("clientexception");
  }

  Future<bool> _showRetryDialog() async {
    final context = navigatorKey.currentContext;
    if (context == null) return true;
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text("Kết nối không ổn định"),
          content: const Text("Không thể kết nối đến máy chủ!"),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop(true);
              },
              child: const Text("Thử lại"),
            ),
          ],
        ),
      ),
    ) ?? true;
  }
}