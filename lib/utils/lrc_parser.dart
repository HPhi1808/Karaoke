import 'dart:math';

// 1. Data Classes
class LyricWord {
  final int startTime;
  final int endTime;
  final String text;

  LyricWord({
    required this.startTime,
    required this.endTime,
    required this.text,
  });

  @override
  String toString() => 'Word($text, $startTime-$endTime)';
}

class LyricLine {
  final int startTime;
  final int endTime;
  final String content;
  final List<LyricWord> words;

  LyricLine({
    required this.startTime,
    required this.endTime,
    required this.content,
    required this.words,
  });

  @override
  String toString() => 'Line($startTime, $content)';
}

// 2. Class Parser Logic
class LrcParser {
  static final RegExp _wordTimeRegex = RegExp(r'<(\d{2}):(\d{2})\.(\d{2,3})>');

  static List<LyricLine> parse(String lrcContent) {
    List<LyricLine> lines = [];

    List<String> rawLines = lrcContent.split(RegExp(r'\r?\n'));

    for (String line in rawLines) {
      if (line.trim().isEmpty) continue;

      // Tìm tất cả các thẻ thời gian trong dòng
      Iterable<RegExpMatch> matches = _wordTimeRegex.allMatches(line);
      if (matches.isEmpty) continue;

      // Danh sách tạm lưu (Timestamp, Text)
      // Dùng class _TempWord nội bộ để dễ xử lý
      List<_TempWord> tempWords = [];
      int lastMatchEnd = 0;

      for (var match in matches) {
        if (tempWords.isNotEmpty) {
          String prevText = line.substring(lastMatchEnd, match.start).trim();
          if (prevText.isNotEmpty) {
            tempWords.last.text = prevText;
          }
        }

        // Parse Time (min:sec.ms)
        int min = int.parse(match.group(1)!);
        int sec = int.parse(match.group(2)!);
        String msStr = match.group(3)!;

        // Xử lý ms: nếu 2 số (0.15) -> 150ms, nếu 3 số (0.150) -> 150ms
        int ms = (msStr.length == 2) ? int.parse(msStr) * 10 : int.parse(msStr);
        int timestamp = min * 60 * 1000 + sec * 1000 + ms;

        // Thêm timestamp mới với text rỗng
        tempWords.add(_TempWord(timestamp, ""));
        lastMatchEnd = match.end;
      }

      // Xử lý text cuối cùng của dòng
      if (tempWords.isNotEmpty && lastMatchEnd < line.length) {
        String lastText = line.substring(lastMatchEnd).trim();
        if (lastText.isNotEmpty) {
          tempWords.last.text = lastText;
        }
      }

      // 3. Chuyển đổi sang LyricWord chuẩn (Có StartTime và EndTime)
      List<LyricWord> finalWords = [];
      for (int i = 0; i < tempWords.length; i++) {
        var current = tempWords[i];
        if (current.text.isEmpty) continue; // Bỏ qua từ rỗng

        // EndTime của từ này là StartTime của từ sau
        // Nếu là từ cuối, cộng thêm 1000ms (1 giây) giả định
        int nextStartTime = (i < tempWords.length - 1)
            ? tempWords[i + 1].timestamp
            : current.timestamp + 1000;

        finalWords.add(LyricWord(
          startTime: current.timestamp,
          endTime: nextStartTime,
          text: current.text,
        ));
      }

      if (finalWords.isNotEmpty) {
        int lineStart = finalWords.first.startTime;
        int lineEnd = finalWords.last.endTime;
        // Join text lại để hiển thị cả câu nếu cần
        String content = finalWords.map((e) => e.text).join(" ");

        lines.add(LyricLine(
          startTime: lineStart,
          endTime: lineEnd,
          content: content,
          words: finalWords,
        ));
      }
    }

    // Sắp xếp theo thời gian
    lines.sort((a, b) => a.startTime.compareTo(b.startTime));
    return lines;
  }
}

// Helper class dùng nội bộ để xử lý logic "nhìn trước lấy sau"
class _TempWord {
  int timestamp;
  String text;
  _TempWord(this.timestamp, this.text);
}