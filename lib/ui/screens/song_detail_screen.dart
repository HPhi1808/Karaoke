import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:http/http.dart' as http;

import '../../models/song_model.dart';
import '../../services/song_service.dart';
import '../../utils/lrc_parser.dart';

class SongDetailScreen extends StatefulWidget {
  final int songId;
  final VoidCallback onBack;

  const SongDetailScreen({
    Key? key,
    required this.songId,
    required this.onBack,
  }) : super(key: key);

  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen> with TickerProviderStateMixin {
  SongModel? _song;
  List<LyricLine> _lyrics = [];
  bool _isLoading = true;

  final AudioPlayer _beatPlayer = AudioPlayer();
  final AudioPlayer _vocalPlayer = AudioPlayer();

  final AutoScrollController _scrollController = AutoScrollController();
  late AnimationController _diskController;

  bool _isVocalEnabled = false;
  bool _hasVocalUrl = false;

  int _lastAutoScrollIndex = -1;
  bool _isUserScrolling = false;
  Timer? _scrollResumeTimer;

  final StreamController<Duration> _positionStreamController = StreamController.broadcast();

  @override
  void initState() {
    super.initState();
    _diskController = AnimationController(vsync: this, duration: const Duration(seconds: 10));

    _beatPlayer.positionStream.listen((position) {
      if (!_positionStreamController.isClosed) {
        _positionStreamController.add(position);
      }

      if (_beatPlayer.playing && !_isUserScrolling) {
        _autoScroll(position);
      }
    });

    _beatPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _vocalPlayer.pause();
        _vocalPlayer.seek(Duration.zero);
        _diskController.stop();
      }
    });

    _loadData();
  }

  @override
  void dispose() {
    _beatPlayer.dispose();
    _vocalPlayer.dispose();
    _scrollController.dispose();
    _diskController.dispose();
    _scrollResumeTimer?.cancel();
    _positionStreamController.close();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final song = await SongService.instance.getSongDetail(widget.songId);
      if (mounted) setState(() => _song = song);

      List<Future> setupFutures = [];

      // Set tốc độ chuẩn
      await _beatPlayer.setSpeed(1.0);
      await _vocalPlayer.setSpeed(1.0);

      if (song.beatUrl != null) {
        setupFutures.add(_beatPlayer.setUrl(song.beatUrl!));
      }
      if (song.vocalUrl != null && song.vocalUrl!.isNotEmpty) {
        _hasVocalUrl = true;
        setupFutures.add(_vocalPlayer.setUrl(song.vocalUrl!));
        await _vocalPlayer.setVolume(0.0);
      }

      await Future.wait(setupFutures);

      _beatPlayer.play();
      if (_hasVocalUrl) _vocalPlayer.play();
      _diskController.repeat();

      if (song.lyricUrl != null) {
        final response = await http.get(Uri.parse(song.lyricUrl!));
        if (response.statusCode == 200) {
          final lrcContent = utf8.decode(response.bodyBytes);

          final parsedLyrics = await compute(LrcParser.parse, lrcContent);

          if (mounted) setState(() => _lyrics = parsedLyrics);
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleVocal() {
    if (!_hasVocalUrl) return;
    setState(() => _isVocalEnabled = !_isVocalEnabled);
    _vocalPlayer.setVolume(_isVocalEnabled ? 1.0 : 0.0);
  }

  void _onSeek(double value) {
    final position = Duration(milliseconds: value.toInt());
    _beatPlayer.seek(position);
    if (_hasVocalUrl) _vocalPlayer.seek(position);
  }

  void _onPlayPause() {
    if (_beatPlayer.playing) {
      _beatPlayer.pause();
      if (_hasVocalUrl) _vocalPlayer.pause();
      _diskController.stop();
    } else {
      if (_hasVocalUrl) {
        _vocalPlayer.seek(_beatPlayer.position);
        _vocalPlayer.play();
      }
      _beatPlayer.play();
      if (!_diskController.isAnimating) _diskController.repeat();
    }
    setState(() {});
  }

  void _autoScroll(Duration position) {
    if (_lyrics.isEmpty) return;
    int currentMs = position.inMilliseconds;

    final activeIndex = _lyrics.indexWhere((line) =>
    currentMs >= line.startTime && currentMs <= line.endTime);

    if (activeIndex != -1 && activeIndex != _lastAutoScrollIndex) {
      _lastAutoScrollIndex = activeIndex;
      if (_scrollController.hasClients) {
        _scrollController.scrollToIndex(
          activeIndex,
          preferPosition: AutoScrollPosition.middle,
          duration: const Duration(milliseconds: 600),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
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
            _buildHeader(),
            const SizedBox(height: 20),

            Expanded(
              child: RepaintBoundary(
                child: _buildLyricSection(),
              ),
            ),

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
        RotationTransition(
          turns: _diskController,
          child: Container(
            width: 220, height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey, width: 2),
              image: DecorationImage(
                image: NetworkImage(_song!.imageUrl ?? "https://via.placeholder.com/220"),
                fit: BoxFit.cover,
              ),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(_song!.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(_song!.artistName, style: const TextStyle(fontSize: 14, color: Colors.white70)),
      ],
    );
  }

  Widget _buildLyricSection() {
    if (_lyrics.isEmpty) {
      return const Center(child: Text("Đang tải lời...", style: TextStyle(color: Colors.grey)));
    }

    return StreamBuilder<Duration>(
      stream: _positionStreamController.stream,
      initialData: Duration.zero,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              _isUserScrolling = true;
              _scrollResumeTimer?.cancel();
            } else if (notification is ScrollEndNotification) {
              _scrollResumeTimer = Timer(const Duration(seconds: 3), () {
                _isUserScrolling = false;
              });
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 120),
            itemCount: _lyrics.length,
            physics: const BouncingScrollPhysics(),
            cacheExtent: 500,
            itemBuilder: (context, index) {
              final line = _lyrics[index];
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
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return StreamBuilder<Duration?>(
      stream: _beatPlayer.durationStream,
      builder: (context, snapshotDuration) {
        final duration = snapshotDuration.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _beatPlayer.positionStream,
          builder: (context, snapshotPosition) {
            var position = snapshotPosition.data ?? Duration.zero;
            if (position > duration) position = duration;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbColor: const Color(0xFFFF00CC),
                      activeTrackColor: const Color(0xFFFF00CC),
                      inactiveTrackColor: Colors.grey,
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    ),
                    child: Slider(
                      value: position.inMilliseconds.toDouble(),
                      max: duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                      onChanged: _onSeek,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatTime(position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                      Text(_formatTime(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: _toggleVocal,
                        iconSize: 32,
                        icon: Icon(Icons.mic, color: _isVocalEnabled ? const Color(0xFFFF00CC) : Colors.grey),
                      ),
                      GestureDetector(
                        onTap: _onPlayPause,
                        child: Container(
                          width: 64, height: 64,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFFF00CC),
                            boxShadow: [BoxShadow(color: Color(0x66FF00CC), blurRadius: 15, spreadRadius: 2)],
                          ),
                          child: Icon(
                            _beatPlayer.playing ? Icons.pause : Icons.play_arrow,
                            color: Colors.white, size: 32,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        iconSize: 32,
                        icon: const Icon(Icons.playlist_play, color: Colors.grey),
                      ),
                    ],
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

// --- WIDGET KARAOKE  ---
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
    final isCurrentLine = currentPositionMs >= line.startTime && currentPositionMs <= line.endTime;
    final isPastLine = currentPositionMs > line.endTime;

    // 1. CỐ ĐỊNH FONT SIZE (Tuyệt đối không đổi số này)
    // Chọn font vừa phải để khi phóng to lên là vừa đẹp
    const double fixedFontSize = 20.0;

    final TextStyle commonStyle = TextStyle(
      fontSize: fixedFontSize,
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: Colors.white,
    );

    return AnimatedOpacity(
      opacity: isCurrentLine ? 1.0 : (isPastLine ? 0.4 : 0.6),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        // Chỉ thay đổi margin dọc để đẩy các dòng khác ra xa khi dòng này to lên
        // Không thay đổi margin ngang ở đây
        margin: EdgeInsets.symmetric(
          vertical: isCurrentLine ? 16.0 : 6.0,
        ),

        // [MẤU CHỐT VẤN ĐỀ Ở ĐÂY]
        // Tạo một Padding ngang ĐỦ LỚN (ví dụ 32.0).
        // Wrap sẽ tính toán xuống dòng dựa trên không gian hẹp này.
        // Khi Scale lên 1.25, nó sẽ lấp đầy khoảng trống 32.0 này mà không tràn ra ngoài.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: AnimatedScale(
            // Chỉ thay đổi Scale: Bố cục giữ nguyên, chỉ hình ảnh to lên
            scale: isCurrentLine ? 1.2 : 1.0, // Giảm scale xuống 1.2 cho an toàn
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.center,
            child: isCurrentLine
                ? _buildActiveLine(commonStyle)
                : Text(
              line.content,
              textAlign: TextAlign.center,
              style: commonStyle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveLine(TextStyle style) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 5.0,
      runSpacing: 2.0,
      children: line.words.map((word) {
        return _buildSingleWord(word, style);
      }).toList(),
    );
  }

  Widget _buildSingleWord(LyricWord word, TextStyle style) {
    final isWordPast = currentPositionMs >= word.endTime;
    final isWordFuture = currentPositionMs < word.startTime;

    if (isWordPast) {
      return Text(word.text, style: style.copyWith(color: const Color(0xFFFF00CC)));
    }

    if (isWordFuture) {
      return Text(word.text, style: style.copyWith(color: Colors.white));
    }

    // ĐANG HÁT
    final double progress = (currentPositionMs - word.startTime) / (word.endTime - word.startTime);
    final clampedProgress = progress.clamp(0.0, 1.0);

    return ShaderMask(
      shaderCallback: (bounds) {
        if (bounds.width == 0) return const LinearGradient(colors: [Colors.white, Colors.white]).createShader(bounds);
        return LinearGradient(
          colors: const [Color(0xFFFF00CC), Colors.white],
          stops: [clampedProgress, clampedProgress],
          tileMode: TileMode.clamp,
        ).createShader(bounds);
      },
      blendMode: BlendMode.srcIn,
      child: Text(
        word.text,
        style: style.copyWith(color: Colors.white),
      ),
    );
  }
}