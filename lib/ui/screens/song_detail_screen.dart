import 'dart:async';
import 'dart:ui'; // Để dùng ImageFilter nếu cần

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart'; // Thay thế ExoPlayer
import 'package:scroll_to_index/scroll_to_index.dart'; // Hỗ trợ scroll tới index
import 'package:http/http.dart' as http; // Để tải file lrc

// Import models & utils
import '../../models/song_model.dart';
import '../../services/api_service.dart';
import '../../utils/lrc_parser.dart'; // Giả sử bạn đã có class LrcParser.dart (code cũ)

class SongDetailScreen extends StatefulWidget {
  final int songId; // Flutter dùng int
  final VoidCallback onBack;

  const SongDetailScreen({
    Key? key,
    required this.songId,
    required this.onBack,
  }) : super(key: key);

  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen> with SingleTickerProviderStateMixin {
  // Data State
  SongModel? _song;
  List<LyricLine> _lyrics = [];
  bool _isLoading = true;

  // Player State
  final AudioPlayer _player = AudioPlayer();
  final AutoScrollController _scrollController = AutoScrollController();

  // Animation Controller cho đĩa quay (Optional visual effect)
  late AnimationController _diskController;

  // Stream Subscription
  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;

  @override
  void initState() {
    super.initState();
    _diskController = AnimationController(vsync: this, duration: const Duration(seconds: 10));
    _loadData();
  }

  @override
  void dispose() {
    _player.dispose();
    _scrollController.dispose();
    _diskController.dispose();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // 1. Gọi API lấy chi tiết bài hát
      final song = await ApiService.instance.getSongDetail(widget.songId);

      if (mounted) {
        setState(() {
          _song = song;
        });
      }

      // 2. Chuẩn bị nhạc (Beat)
      if (song.beatUrl != null) {
        await _player.setUrl(song.beatUrl!);
        _player.play(); // Auto play
        _diskController.repeat(); // Quay đĩa
      }

      // 3. Tải và Parse Lyric
      if (song.lyricUrl != null) {
        final response = await http.get(Uri.parse(song.lyricUrl!));
        if (response.statusCode == 200) {
          // Xử lý parse trên isolate khác để tránh lag UI nếu file nặng (Optional)
          // Ở đây parse trực tiếp vì lrc nhẹ
          final lrcContent = response.body; // utf8.decode(response.bodyBytes) nếu lỗi font
          final parsedLyrics = LrcParser.parse(lrcContent);

          if (mounted) {
            setState(() {
              _lyrics = parsedLyrics;
            });
          }
        }
      }

    } catch (e) {
      debugPrint("Error loading song detail: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Hàm scroll tự động
  void _autoScroll(Duration position) {
    if (_lyrics.isEmpty) return;

    // Tìm index dòng đang hát
    final activeIndex = _lyrics.indexWhere((line) =>
    position.inMilliseconds >= line.startTime &&
        position.inMilliseconds <= line.endTime);

    if (activeIndex != -1) {
      // Chỉ scroll nếu chưa scroll tới đó (tránh spam lệnh scroll)
      // AutoScrollController hỗ trợ scroll tới index cụ thể
      _scrollController.scrollToIndex(
        activeIndex,
        preferPosition: AutoScrollPosition.middle,
        duration: const Duration(milliseconds: 500),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Gradient Background: Tím đậm -> Đen
    return Scaffold(
      extendBodyBehindAppBar: true, // Để AppBar đè lên background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text("Đang phát", style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3E005E), Color(0xFF000000)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _isLoading || _song == null
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Column(
          children: [
            SizedBox(height: kToolbarHeight + MediaQuery.of(context).padding.top + 20),

            // 1. Đĩa nhạc + Info
            _buildHeader(),

            const SizedBox(height: 20),

            // 2. Lyric (Chiếm phần lớn không gian)
            Expanded(
              child: _buildLyricSection(),
            ),

            // 3. Controls (Slider + Play/Pause)
            _buildControls(),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Đĩa quay
        RotationTransition(
          turns: _diskController,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey, width: 2),
              image: DecorationImage(
                image: NetworkImage(_song!.imageUrl ?? "https://via.placeholder.com/220"),
                fit: BoxFit.cover,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _song!.title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        Text(
          _song!.artistName,
          style: const TextStyle(fontSize: 14, color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLyricSection() {
    if (_lyrics.isEmpty) {
      return const Center(child: Text("Đang tải lời...", style: TextStyle(color: Colors.grey)));
    }

    // Lắng nghe position để update UI lyric
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;

        // Trigger auto scroll (Debounce logic đã được xử lý trong thư viện hoặc gọi hàm riêng)
        // Tuy nhiên gọi trực tiếp ở đây cũng tạm ổn vì scrollToIndex có cơ chế check
        // Tốt nhất là dùng Listener riêng, nhưng để đơn giản code thì đặt ở đây.
        WidgetsBinding.instance.addPostFrameCallback((_) => _autoScroll(position));

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 120), // Padding lớn để active item ở giữa
          itemCount: _lyrics.length,
          itemBuilder: (context, index) {
            final line = _lyrics[index];

            // Bọc bằng AutoScrollTag để controller tìm được index
            return AutoScrollTag(
              key: ValueKey(index),
              controller: _scrollController,
              index: index,
              child: KaraokeLineItem(
                line: line,
                currentPositionMs: position.inMilliseconds,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildControls() {
    return StreamBuilder<Duration?>(
      stream: _player.durationStream,
      builder: (context, snapshotDuration) {
        final duration = snapshotDuration.data ?? Duration.zero;

        return StreamBuilder<Duration>(
          stream: _player.positionStream,
          builder: (context, snapshotPosition) {
            var position = snapshotPosition.data ?? Duration.zero;
            if (position > duration) position = duration;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbColor: const Color(0xFFFF00CC),
                      activeTrackColor: const Color(0xFFFF00CC),
                      inactiveTrackColor: Colors.grey,
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    ),
                    child: Slider(
                      value: position.inMilliseconds.toDouble(),
                      max: duration.inMilliseconds.toDouble() > 0
                          ? duration.inMilliseconds.toDouble()
                          : 1.0,
                      onChanged: (value) {
                        _player.seek(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),

                  // Time Labels
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatTime(position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                      Text(_formatTime(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Play/Pause Button
                  StreamBuilder<PlayerState>(
                    stream: _player.playerStateStream,
                    builder: (context, snapshot) {
                      final playerState = snapshot.data;
                      final processingState = playerState?.processingState;
                      final playing = playerState?.playing;

                      if (processingState == ProcessingState.loading || processingState == ProcessingState.buffering) {
                        return const CircularProgressIndicator(color: Color(0xFFFF00CC));
                      }

                      final isPlaying = playing == true && processingState != ProcessingState.completed;

                      return GestureDetector(
                        onTap: () {
                          if (isPlaying) {
                            _player.pause();
                            _diskController.stop();
                          } else {
                            _player.play();
                            _diskController.repeat();
                          }
                        },
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFFF00CC),
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }
}

// --- WIDGET XỬ LÝ LYRIC TÔ MÀU (KARAOKE EFFECT) ---
class KaraokeLineItem extends StatelessWidget {
  final LyricLine line;
  final int currentPositionMs;

  const KaraokeLineItem({
    Key? key,
    required this.line,
    required this.currentPositionMs,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 1. Xác định trạng thái dòng
    final isCurrentLine = currentPositionMs >= line.startTime && currentPositionMs <= line.endTime;
    final isPastLine = currentPositionMs > line.endTime;

    // Animation scale & opacity (giản lược bằng AnimatedDefaultTextStyle/AnimatedOpacity)
    // Flutter không có animateFloatAsState dùng trực tiếp trong build như Compose,
    // nhưng có thể dùng Implicit Animations

    return AnimatedScale(
      scale: isCurrentLine ? 1.2 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: AnimatedOpacity(
        opacity: isCurrentLine ? 1.0 : (isPastLine ? 0.4 : 0.6), // Past mờ hơn, Future hơi mờ
        duration: const Duration(milliseconds: 300),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: isCurrentLine
              ? _buildKaraokeText() // Nếu đang hát dòng này -> Tô màu từng chữ
              : Text( // Nếu không phải dòng này -> Text thường
            line.content, // Giả sử LyricLine có field content (ghép các words lại)
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.normal
            ),
          ),
        ),
      ),
    );
  }

  // Logic tô màu gradient từng chữ (Phức tạp nhất)
  Widget _buildKaraokeText() {
    // Dùng RichText để ghép từng từ lại
    List<InlineSpan> spans = [];

    for (var i = 0; i < line.words.length; i++) {
      final word = line.words[i];
      final isWordPast = currentPositionMs >= word.endTime;
      final isWordFuture = currentPositionMs < word.startTime;

      if (isWordPast) {
        // Đã hát xong -> Màu Hồng (Full)
        spans.add(TextSpan(
          text: word.text + " ",
          style: const TextStyle(color: Color(0xFFFF00CC)),
        ));
      } else if (isWordFuture) {
        // Chưa hát tới -> Màu Trắng (Full)
        spans.add(TextSpan(
          text: word.text + " ",
          style: const TextStyle(color: Colors.white),
        ));
      } else {
        // --- ĐANG HÁT TỪ NÀY ---
        // Tính % đã hát của từ đó
        final double progress = (currentPositionMs - word.startTime) / (word.endTime - word.startTime);
        final clampedProgress = progress.clamp(0.0, 1.0); // 0.0 -> 1.0

        // Dùng ShaderMask để tô màu gradient cho TỪNG TỪ ĐANG HÁT
        // Đây là kỹ thuật tô màu Karaoke chuẩn trong Flutter
        spans.add(WidgetSpan(
          child: ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                colors: const [Color(0xFFFF00CC), Colors.white],
                stops: [clampedProgress, clampedProgress], // Cắt màu tại điểm progress
                tileMode: TileMode.clamp,
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcIn, // Chỉ tô màu vào vùng text
            child: Text(
              word.text + " ",
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white // Màu nền cơ bản (bị shader đè lên)
              ),
            ),
          ),
        ));
      }
    }

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        children: spans,
      ),
    );
  }
}