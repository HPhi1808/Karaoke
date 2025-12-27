import '../models/song_model.dart'; // <--- 1. Import model từ file chung

class LrcParser {
  // Regex cho Enhanced LRC (Karaoke từng chữ): <00:00.00>
  static final RegExp _enhancedRegex = RegExp(r'<(\d{2}):(\d{2})\.(\d{2,3})>');

  // Regex cho Standard LRC (Cả dòng): [00:00.00]
  static final RegExp _standardRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

  static List<LyricLine> parse(String lrcContent) {
    List<LyricLine> lines = [];
    List<String> rawLines = lrcContent.split(RegExp(r'\r?\n'));

    for (int i = 0; i < rawLines.length; i++) {
      String line = rawLines[i].trim();
      if (line.isEmpty) continue;

      // --- TRƯỜNG HỢP 1: ENHANCED LRC (<mm:ss.xx> từ này <mm:ss.xx> từ kia) ---
      if (_enhancedRegex.hasMatch(line)) {
        lines.add(_parseEnhancedLine(line));
      }
      // --- TRƯỜNG HỢP 2: STANDARD LRC ([mm:ss.xx] Cả nội dung dòng) ---
      else if (_standardRegex.hasMatch(line)) {
        lines.add(_parseStandardLine(line, i, rawLines));
      }
    }

    // Sắp xếp lại theo thời gian cho chắc chắn
    lines.sort((a, b) => a.startTime.compareTo(b.startTime));
    return lines;
  }

  // --- LOGIC XỬ LÝ ENHANCED LRC (Code cũ của bạn, đã tinh chỉnh) ---
  static LyricLine _parseEnhancedLine(String line) {
    Iterable<RegExpMatch> matches = _enhancedRegex.allMatches(line);
    List<_TempWord> tempWords = [];
    int lastMatchEnd = 0;

    for (var match in matches) {
      // Lấy text phía trước thẻ thời gian (nếu có)
      if (tempWords.isNotEmpty) {
        String prevText = line.substring(lastMatchEnd, match.start).trim();
        if (prevText.isNotEmpty) {
          tempWords.last.text = prevText;
        }
      }

      // Parse Time
      int timestamp = _timeToMs(match.group(1), match.group(2), match.group(3));

      // Thêm timestamp mới
      tempWords.add(_TempWord(timestamp, ""));
      lastMatchEnd = match.end;
    }

    // Lấy text cuối cùng
    if (tempWords.isNotEmpty && lastMatchEnd < line.length) {
      String lastText = line.substring(lastMatchEnd).trim();
      if (lastText.isNotEmpty) tempWords.last.text = lastText;
    }

    // Convert sang LyricWord chuẩn
    List<LyricWord> finalWords = [];
    for (int i = 0; i < tempWords.length; i++) {
      var current = tempWords[i];
      if (current.text.isEmpty) continue;

      int nextStartTime = (i < tempWords.length - 1)
          ? tempWords[i + 1].timestamp
          : current.timestamp + 1000; // Mặc định từ cuối dài 1s

      finalWords.add(LyricWord(
        text: current.text,
        startTime: current.timestamp,
        endTime: nextStartTime,
      ));
    }

    // Tạo Line
    int lineStart = finalWords.isNotEmpty ? finalWords.first.startTime : 0;
    int lineEnd = finalWords.isNotEmpty ? finalWords.last.endTime : 0;
    String content = finalWords.map((e) => e.text).join(" ");

    return LyricLine(
      startTime: lineStart,
      endTime: lineEnd,
      content: content,
      words: finalWords,
    );
  }

  // --- LOGIC XỬ LÝ STANDARD LRC (Logic tôi đã đưa ở bước trước) ---
  static LyricLine _parseStandardLine(String line, int index, List<String> allLines) {
    final match = _standardRegex.firstMatch(line)!;

    int startTime = _timeToMs(match.group(1), match.group(2), match.group(3));
    String content = match.group(4)?.trim() ?? "";

    // Tìm endTime bằng cách nhìn dòng tiếp theo
    int endTime = startTime + 5000; // Mặc định 5s
    if (index + 1 < allLines.length) {
      final nextMatch = _standardRegex.firstMatch(allLines[index + 1]);
      if (nextMatch != null) {
        endTime = _timeToMs(nextMatch.group(1), nextMatch.group(2), nextMatch.group(3));
      }
    }

    // Giả lập Words (Chia đều thời gian để có hiệu ứng chạy chữ)
    List<String> rawWords = content.split(' ');
    List<LyricWord> words = [];
    if (content.isNotEmpty) {
      int duration = endTime - startTime;
      int wordDuration = (duration / rawWords.length).floor();

      for (int j = 0; j < rawWords.length; j++) {
        words.add(LyricWord(
          text: rawWords[j],
          startTime: startTime + (j * wordDuration),
          endTime: startTime + ((j + 1) * wordDuration),
        ));
      }
    }

    return LyricLine(
      startTime: startTime,
      endTime: endTime,
      content: content,
      words: words,
    );
  }

  // Helper chuyển đổi mm:ss.xx -> milliseconds
  static int _timeToMs(String? minStr, String? secStr, String? msStr) {
    int min = int.parse(minStr ?? "0");
    int sec = int.parse(secStr ?? "0");
    // Xử lý ms: nếu 2 số (.15) -> 150ms, nếu 3 số (.150) -> 150ms
    int ms = 0;
    if (msStr != null) {
      ms = (msStr.length == 2) ? int.parse(msStr) * 10 : int.parse(msStr);
    }
    return min * 60 * 1000 + sec * 1000 + ms;
  }
}

// Class nội bộ dùng tạm cho Logic Enhanced
class _TempWord {
  int timestamp;
  String text;
  _TempWord(this.timestamp, this.text);
}