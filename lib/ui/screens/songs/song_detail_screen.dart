import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart';

import '../../../models/song_model.dart';
import '../../../services/song_service.dart';
import '../../../utils/lrc_parser.dart';

// --- MODEL SECTIONS ---
class SongSection {
  final String name;
  final Duration startTime;
  final Duration endTime;

  SongSection({
    required this.name,
    required this.startTime,
    required this.endTime,
  });
}

// --- MAIN SCREEN ---
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

class _SongDetailScreenState extends State<SongDetailScreen> {
  // 1. Data Variables
  SongModel? _song;
  List<LyricLine> _lyrics = [];
  List<SongSection> _sections = [];
  bool _isLoading = true;
  bool _isLyricsLoaded = false; // Kiểm soát việc hiện nút/lời
  bool _isFavorite = false;
  String? _errorMessage;
  Timer? _bufferingWatchdog;
  bool _isHandlingCompletion = false;

  // 2. Audio & Players
  final AudioPlayer _beatPlayer = AudioPlayer();
  final AudioPlayer _vocalPlayer = AudioPlayer();
  bool _isVocalEnabled = false;
  bool _hasVocalUrl = false;
  double _beatVolume = 1.0;
  double _vocalVolume = 0.0;
  double _savedVocalVolume = 1.0;

  // 3. Recording State
  late final AudioRecorder _audioRecorder;
  bool _isRecording = false;
  String? _recordingPath;
  Timer? _recordTimer;
  Duration _currentRecDuration = Duration.zero;
  bool _isSessionStarted = false; // Đã bắt đầu phiên hát chưa
  bool _isCompleted = false;      // Đã hát xong bài chưa

  // 4. UI & Scrolling
  final AutoScrollController _scrollController = AutoScrollController();
  final int _syncOffset = -99;
  int _lastAutoScrollIndex = -1;
  bool _isUserScrolling = false;
  Timer? _userScrollTimeoutTimer;
  final StreamController<Duration> _positionStreamController = StreamController.broadcast();
  bool _isDraggingSeekBar = false;
  double? _dragValue;

  // 5. Section & Countdown
  Duration? _targetEndTime;
  int _selectedSectionIndex = -2; // -2: Init, -1: Full Song, >=0: Section
  bool _isSwitchingSection = false;
  bool _isCountingDown = false;
  int _countdownValue = 3;
  Timer? _countdownTimer;

  // ========================
  // LIFECYCLE METHODS
  // ========================

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Giữ màn hình luôn sáng
    _audioRecorder = AudioRecorder();
    _initAudioSession();
    _setupAudioListeners();
    _loadData();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _bufferingWatchdog?.cancel();
    _audioRecorder.dispose();
    _beatPlayer.dispose();
    _vocalPlayer.dispose();
    _scrollController.dispose();
    _userScrollTimeoutTimer?.cancel();
    _countdownTimer?.cancel();
    _positionStreamController.close();
    _stopRecordTimer();
    super.dispose();
  }

  // Thiết lập các listener cho Audio Player
  void _setupAudioListeners() {
    _beatPlayer.positionStream.listen((position) {
      if (!_positionStreamController.isClosed) {
        _positionStreamController.add(position);
      }
      // Dừng nếu hát theo đoạn (Section)
      if (_targetEndTime != null && !_isSwitchingSection && position >= _targetEndTime!) {
        _stopAtSectionEnd();
      }
      // Tự động cuộn lời
      if (_beatPlayer.playing && !_isUserScrolling && !_isDraggingSeekBar) {
        _autoScroll(position);
      }
    });

    _beatPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.loading) {
        _startBufferingWatchdog();

      } else {
        _bufferingWatchdog?.cancel();
      }
      // Xử lý khi hát xong
      if (state.processingState == ProcessingState.completed) {
        if (_targetEndTime == null) {
          _handleSongCompletion();
        }
      }
      // Đồng bộ Vocal Player dừng theo Beat Player
      else if (!state.playing) {
        if (_hasVocalUrl && _vocalPlayer.playing) {
          _vocalPlayer.pause();
        }
      }
    });

    _beatPlayer.playbackEventStream.listen(
          (event) {},
      onError: (Object e, StackTrace st) {
        debugPrint("Playback Error detected: $e");
        _handlePlaybackError(e);
      },
    );
  }

  void _startBufferingWatchdog() {
    _bufferingWatchdog?.cancel();
    _bufferingWatchdog = Timer(const Duration(seconds: 10), () async {
      if (_beatPlayer.processingState == ProcessingState.buffering ||
          _beatPlayer.processingState == ProcessingState.loading) {
        debugPrint("TIMEOUT: Buffering quá lâu -> Kích hoạt lỗi mạng");
        _handlePlaybackError(Exception("Timeout: Mạng yếu hoặc mất kết nối."));
      }
    });
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Cấu hình phiên âm thanh
  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth |
      AVAudioSessionCategoryOptions.defaultToSpeaker |
      AVAudioSessionCategoryOptions.mixWithOthers,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
    ));
  }

  // ==============================
  // DATA LOADING & PARSING
  // ==============================

  // Tải thông tin bài hát, beat, vocal và lời
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isLyricsLoaded = false;
    });

    try {
      final song = await SongService.instance.getSongDetail(widget.songId);
      if (mounted) setState(() => _song = song);

      List<Future> setupFutures = [];
      await _beatPlayer.setSpeed(1.0);
      await _vocalPlayer.setSpeed(1.0);

      if (song.beatUrl != null) {
        setupFutures.add(
            _beatPlayer.setUrl(song.beatUrl!)
                .timeout(const Duration(seconds: 15), onTimeout: () {
              throw Exception("Quá thời gian tải nhạc nền. Mạng quá yếu.");
            })
                .catchError((e) {
              throw Exception("Không thể tải nhạc nền (Beat). ${e.toString()}");
            })
        );
      } else {
        throw Exception("Dữ liệu bài hát lỗi: Không có link Beat.");
      }

      if (song.vocalUrl != null && song.vocalUrl!.isNotEmpty) {
        _hasVocalUrl = true;
        setupFutures.add(
            _vocalPlayer.setUrl(song.vocalUrl!)
                .timeout(const Duration(seconds: 10))
                .catchError((e) {
              debugPrint("⚠️ Lỗi tải vocal (bỏ qua): $e");
              _hasVocalUrl = false;
            })
        );
      }

      await _beatPlayer.setVolume(_beatVolume);
      if (_hasVocalUrl) await _vocalPlayer.setVolume(_vocalVolume);

      await Future.wait(setupFutures);

      if (song.lyricUrl == null || song.lyricUrl!.isEmpty) {
        throw Exception("Bài hát này chưa có dữ liệu lời (Lyrics).");
      }

      final response = await http.get(Uri.parse(song.lyricUrl!))
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception("Internet không ổn định, không thể tải lời bài hát.");
      });

      if (response.statusCode == 200) {
        final lrcContent = utf8.decode(response.bodyBytes);

        final result = await compute(_parseSectionsAndCleanLrc, lrcContent);
        final cleanContent = result['content'] as String;
        final sections = result['sections'] as List<SongSection>;
        final parsedLyrics = await compute(LrcParser.parse, cleanContent);

        if (parsedLyrics.isEmpty) {
          throw Exception("File lời bài hát bị lỗi!");
        }

        if (mounted) {
          setState(() {
            _lyrics = parsedLyrics;
            _sections = sections;
            _isLyricsLoaded = true;
          });
        }
      } else {
        throw Exception("Lỗi máy chủ khi tải lời: Mã ${response.statusCode}");
      }

    } catch (e) {
      debugPrint("❌ Error loading data: $e");
      if (mounted) {
        setState(() {
          _errorMessage = _getFriendlyErrorMessage(e);
          _isLoading = false;
        });
      }
    } finally {
      if (mounted && _errorMessage == null) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getFriendlyErrorMessage(dynamic error) {
    String msg = error.toString();
    String lowerMsg = msg.toLowerCase();

    if (msg.startsWith("Exception: ")) {
      msg = msg.substring(11);
    }

    if (lowerMsg.contains("socketexception") ||
        lowerMsg.contains("connection refused") ||
        lowerMsg.contains("network") ||
        lowerMsg.contains("timed out")) {
      return "Mất kết nối Internet.\nKhông thể tải lời bài hát.";
    }

    return msg;
  }

  Future<void> _handlePlaybackError(dynamic error) async {
    await _pauseSession();

    String errorMsg = _getFriendlyErrorMessage(error);

    bool canSave = _isSessionStarted && _isRecording && _currentRecDuration.inSeconds >= 10;

    if (canSave) {
      if (mounted) {
        _showNetworkErrorSaveDialog(errorMsg);
      }
    } else {
      if (mounted) {
        _discardRecording();
        setState(() {
          _errorMessage = "$errorMsg\n(Lỗi xảy ra trong quá trình phát nhạc)";
        });
      }
    }
  }

  // Tách các thẻ [SECTION] ra khỏi file LRC và trả về nội dung sạch
  static Map<String, dynamic> _parseSectionsAndCleanLrc(String content) {
    final lines = content.split('\n');
    final StringBuffer cleanBuffer = StringBuffer();
    final Map<String, Duration> tempStarts = {};
    final List<SongSection> finalSections = [];

    final RegExp sectionStartRegex = RegExp(r'\[(\d{1,2}):(\d{1,2})\.(\d{1,3})\]\s*\[SECTION:(.*?)\]');
    final RegExp sectionEndRegex = RegExp(r'\[(\d{1,2}):(\d{1,2})\.(\d{1,3})\]\s*\[ENDSECTION:(.*?)\]');

    Duration parseTime(Match match) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      String millisecondStr = match.group(3)!;
      if (millisecondStr.length == 2) millisecondStr += "0";
      return Duration(minutes: minutes, seconds: seconds, milliseconds: int.parse(millisecondStr));
    }

    for (var line in lines) {
      final startMatch = sectionStartRegex.firstMatch(line);
      if (startMatch != null) {
        final time = parseTime(startMatch);
        final name = startMatch.group(4)!.trim();
        tempStarts[name] = time;
        continue;
      }
      final endMatch = sectionEndRegex.firstMatch(line);
      if (endMatch != null) {
        final time = parseTime(endMatch);
        final name = endMatch.group(4)!.trim();
        if (tempStarts.containsKey(name)) {
          finalSections.add(SongSection(name: name, startTime: tempStarts[name]!, endTime: time));
          tempStarts.remove(name);
        }
        continue;
      }
      cleanBuffer.writeln(line);
    }
    finalSections.sort((a, b) => a.startTime.compareTo(b.startTime));
    return {'content': cleanBuffer.toString(), 'sections': finalSections};
  }

  // ==============================================
  // SESSION MANAGEMENT (PLAY, PAUSE, RECORD)
  // ==============================================

  // Xử lý logic nút Play/Pause chính
  Future<void> _togglePlayPause() async {
    if (_isCountingDown) return;

    if (!_beatPlayer.playing) {
      bool hasNet = await _hasInternet();
      if (!hasNet) {
        _handlePlaybackError(Exception("Không có kết nối Internet"));
        return;
      }
    }

    if (!_isSessionStarted) {
      setState(() => _selectedSectionIndex = -1);
      await _startFreshSession();
      return;
    }

    bool isAtEndOfSection = _selectedSectionIndex != -1 &&
        _targetEndTime != null &&
        _beatPlayer.position >= (_targetEndTime! - const Duration(milliseconds: 600));

    if (isAtEndOfSection) {
      debugPrint("Hết đoạn -> Chuyển sang hát Full bài");

      setState(() {
        _selectedSectionIndex = -1;
        _targetEndTime = null;
        _isCompleted = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Đang phát tiếp phần còn lại..."), duration: Duration(milliseconds: 800))
      );

      if (_isRecording) {
        final currentPos = _beatPlayer.position;
        if (currentPos < (_beatPlayer.duration ?? Duration.zero)) {
          await _beatPlayer.seek(currentPos + const Duration(milliseconds: 50));
          if (_hasVocalUrl) await _vocalPlayer.seek(currentPos + const Duration(milliseconds: 50));
        }
        await _resumeSession();

      } else {
        await _startFreshSession(skipSeek: true);
      }
      return;
    }

    if (_beatPlayer.playing) {
      await _pauseSession();
    } else {
      if (_isCompleted) {
        await _restartSession();
      } else {
        await _resumeSession();
      }
    }
  }

  // Bắt đầu một phiên thu âm mới từ đầu (hoặc tại vị trí hiện tại nếu skipSeek=true)
  Future<void> _startFreshSession({bool skipSeek = false}) async {
    bool hasNet = await _hasInternet();
    if (!hasNet) {
      _handlePlaybackError(Exception("Mất kết nối Internet. Không thể bắt đầu."));
      return;
    }
    if (await Permission.microphone.request().isDenied) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cần quyền Micro")));
      return;
    }

    try {
      Directory dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download/KaraokeTemp');
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      if (!await dir.exists()) await dir.create(recursive: true);

      final fileName = 'rec_${DateTime.now().millisecondsSinceEpoch}.wav';
      final path = '${dir.path}/$fileName';
      const config = RecordConfig(encoder: AudioEncoder.wav, sampleRate: 44100, numChannels: 1);

      if (_beatPlayer.playing) await _beatPlayer.pause();
      if (_hasVocalUrl) await _vocalPlayer.pause();

      await _audioRecorder.start(config, path: path);
      _startRecordTimer(reset: true);
      await Future.delayed(const Duration(milliseconds: 36));

      setState(() {
        _isRecording = true;
        _recordingPath = path;
        _isSessionStarted = true;
        _isCompleted = false;
      });

      if (!skipSeek) {
        await _beatPlayer.seek(Duration.zero).timeout(const Duration(seconds: 5));;
        if (_hasVocalUrl) await _vocalPlayer.seek(Duration.zero);
      }

      _beatPlayer.play();
      _beatPlayer.setVolume(_beatVolume);
      if (_hasVocalUrl) {
        await _vocalPlayer.seek(_beatPlayer.position);
        await _vocalPlayer.setVolume(_vocalVolume);
        _vocalPlayer.play();
      }
    } catch (e) {
      debugPrint("Start Session Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: $e")));
    }
  }

  // Tạm dừng nhạc và thu âm
  Future<void> _pauseSession() async {
    try {
      await _beatPlayer.pause();
      if (_hasVocalUrl) await _vocalPlayer.pause();
      _stopRecordTimer();
      if (_isRecording) await _audioRecorder.pause();
      setState(() {});
    } catch (e) {
      debugPrint("Pause Error: $e");
    }
  }

  // Tiếp tục nhạc và thu âm
  Future<void> _resumeSession() async {
    try {
      if (_targetEndTime != null) {
        final currentPos = _beatPlayer.position;
        if (currentPos >= _targetEndTime! - const Duration(milliseconds: 650)) {
          debugPrint("Resume tại điểm cuối đoạn -> Mở khóa sang Full Bài");

          setState(() {
            _targetEndTime = null;
            _selectedSectionIndex = -1;
            _isCompleted = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Đang phát tiếp phần còn lại của bài hát..."),
                duration: Duration(milliseconds: 1000),
              ),
            );
          }
        }
      }
      if (!_isRecording) {
        await _startFreshSession(skipSeek: true);
        return;
      }
      if (await _audioRecorder.isPaused()) {
        await _audioRecorder.resume();
        _startRecordTimer(reset: false);
      }
      await Future.delayed(const Duration(milliseconds: 36));
      _beatPlayer.play();
      if (_hasVocalUrl) {
        if ((_vocalPlayer.position - _beatPlayer.position).abs().inMilliseconds > 100) {
          await _vocalPlayer.seek(_beatPlayer.position);
        }
        await _vocalPlayer.setVolume(_isVocalEnabled ? 1.0 : 0.0);
        _vocalPlayer.play();
      }
    } catch (e) {
      debugPrint("Resume Error: $e");
      _beatPlayer.play();
    }
  }

  // Reset toàn bộ để hát lại từ đầu
  Future<void> _restartSession() async {
    try {
      await _beatPlayer.stop();
      if (_hasVocalUrl) _vocalPlayer.stop();
      if (_isRecording) await _audioRecorder.stop();

      Duration startPosition = Duration.zero;
      if (_selectedSectionIndex >= 0 && _selectedSectionIndex < _sections.length) {
        final section = _sections[_selectedSectionIndex];
        startPosition = section.startTime;

        setState(() {
          _targetEndTime = section.endTime;
        });
      } else {
        setState(() {
          _targetEndTime = null;
        });
      }

      await _beatPlayer.seek(startPosition);
      if (_hasVocalUrl) await _vocalPlayer.seek(startPosition);

      setState(() {
        _isSessionStarted = false;
        _isRecording = false;
        _isCompleted = false;
        _isUserScrolling = false;
      });

      _lastAutoScrollIndex = -1;
      _isHandlingCompletion = false;

      if (_scrollController.hasClients && _lyrics.isNotEmpty) {
        if (_selectedSectionIndex == -1) {
          _scrollController.scrollToIndex(0, preferPosition: AutoScrollPosition.middle, duration: const Duration(milliseconds: 500));
        } else {
          int targetIndex = _lyrics.indexWhere((line) => line.startTime >= startPosition.inMilliseconds - 100);
          if (targetIndex == -1) targetIndex = _findActiveLineIndex(startPosition.inMilliseconds);
          if (targetIndex != -1) {
            _scrollController.scrollToIndex(targetIndex, preferPosition: AutoScrollPosition.middle, duration: const Duration(milliseconds: 500));
          }
        }
      }
      await _startFreshSession(skipSeek: true);
    } catch (e) {
      debugPrint("Restart Error: $e");
    }
  }

  // Xử lý sự kiện khi bài hát kết thúc tự nhiên
  Future<void> _handleSongCompletion() async {
    if (_isHandlingCompletion || _isCompleted) return;

    _isHandlingCompletion = true;

    if (mounted) setState(() => _isCompleted = true);
    await _pauseSession();

    Duration startPosition = Duration.zero;
    if (_selectedSectionIndex >= 0 && _selectedSectionIndex < _sections.length) {
      startPosition = _sections[_selectedSectionIndex].startTime;
    }

    _beatPlayer.seek(startPosition);
    if (_hasVocalUrl) _vocalPlayer.seek(startPosition);

    _lastAutoScrollIndex = -1;
    setState(() {
      _isUserScrolling = false;
      _isSessionStarted = false;
    });

    if (_scrollController.hasClients && _lyrics.isNotEmpty) {
      int targetIndex = _findActiveLineIndex(startPosition.inMilliseconds);
      if(targetIndex == -1) targetIndex = 0;

      _scrollController.scrollToIndex(targetIndex, preferPosition: AutoScrollPosition.middle);
    }
    if (_isRecording && _recordingPath != null) {
      if (mounted) {
        _showRecordingOptionsDialog(allowContinue: false);
      }
    }
  }

  // Kết thúc thu âm chủ động (nút Check V)
  Future<void> _finishRecordingSession() async {
    await _pauseSession();
    if (mounted) _showRecordingOptionsDialog(allowContinue: true);
  }

  // ================================
  // NAVIGATION & UI INTERACTION
  // ================================

  // Xử lý sự kiện tua nhạc (Seek)
  void _performSeek(double value) async {
    if (_isCountingDown) return;

    bool hasNet = await _hasInternet();
    if (!hasNet) {
      _handlePlaybackError(Exception("Không có kết nối Internet"));
      return;
    }
    final position = Duration(milliseconds: value.toInt());

    if (_isCompleted) setState(() => _isCompleted = false);

    // Kiểm tra nếu tua ra ngoài phạm vi Section đang chọn
    if (_selectedSectionIndex != -1) {
      final currentSection = _sections[_selectedSectionIndex];
      if (position < currentSection.startTime - const Duration(seconds: 1) ||
          position > currentSection.endTime + const Duration(seconds: 1)) {
        setState(() {
          _selectedSectionIndex = -1;
          _targetEndTime = null;
        });
      }
    }

    _beatPlayer.seek(position);
    if (_hasVocalUrl) _vocalPlayer.seek(position);

    _lastAutoScrollIndex = -1;
    setState(() => _isUserScrolling = false);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      if (position < const Duration(seconds: 2) && _lyrics.isNotEmpty) {
        _scrollController.scrollToIndex(0, preferPosition: AutoScrollPosition.middle, duration: const Duration(milliseconds: 300));
      } else {
        _scrollToCurrentLine();
      }
    });
  }

  // Xử lý nút Back trên AppBar
  Future<void> _onBackPressed() async {
    if (!_isSessionStarted || _beatPlayer.position.inSeconds < 10) {
      _discardRecording();
      widget.onBack();
      return;
    }
    await _pauseSession();
    if (!mounted) return;
    _showExitConfirmationDialog();
  }

  // Xử lý khi bấm vào các nút chọn đoạn (Section)
  Future<void> _handleSectionTap(int newIndex) async {
    // Nếu chuyển từ Đoạn -> Cả bài: Mở rộng phạm vi, không ngắt quãng
    if (_isSessionStarted && _selectedSectionIndex != -1 && newIndex == -1) {
      setState(() {
        _selectedSectionIndex = -1;
        _targetEndTime = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã mở rộng sang chế độ Cả Bài")));
      return;
    }

    // Nếu chuyển đoạn khác: Cần hỏi lưu nếu đã hát lâu
    if (_isSessionStarted && _beatPlayer.position.inSeconds >= 10) {
      await _pauseSession();
      if (!mounted) return;
      _showSwitchSectionDialog(newIndex);
    } else {
      if (_isSessionStarted) _discardRecording();
      _prepareToPlaySection(newIndex);
    }
  }

  // Chuẩn bị và chuyển đến đoạn nhạc được chọn
  Future<void> _prepareToPlaySection(int index) async {
    bool hasNet = await _hasInternet();
    if (!hasNet) {
      _handlePlaybackError(Exception("Không có kết nối Internet để tải nhạc."));
      return;
    }

    setState(() => _isSwitchingSection = true);

    await _pauseSession();
    _countdownTimer?.cancel();

    try {
      Duration targetPosition = Duration.zero;
      Duration? newTargetEndTime;

      if (index != -1) {
        final section = _sections[index];
        targetPosition = section.startTime;
        newTargetEndTime = section.endTime;
      }

      await _beatPlayer.seek(targetPosition).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception("Mạng quá yếu, không thể tải đoạn nhạc này."),
      );

      if (_hasVocalUrl) {
        await _vocalPlayer.seek(targetPosition).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint("Vocal seek timeout (ignored)");
              return;
            }
        ).catchError((e) {
          debugPrint("Vocal seek error: $e");
        });
      }

      if (mounted) {
        setState(() {
          _isCompleted = false;
          _selectedSectionIndex = index;
          _targetEndTime = newTargetEndTime;

          _isUserScrolling = false;
          _isCountingDown = false;
        });
      }

      _lastAutoScrollIndex = -1;

      const scrollDuration = Duration(milliseconds: 800);

      if (index == -1) {
        if (_scrollController.hasClients && _lyrics.isNotEmpty) {
          _scrollController.scrollToIndex(0, preferPosition: AutoScrollPosition.middle, duration: scrollDuration);
        }
      } else {
        int targetLineIndex = _lyrics.indexWhere((line) => line.startTime >= targetPosition.inMilliseconds - 100);

        if (targetLineIndex == -1) targetLineIndex = _findActiveLineIndex(targetPosition.inMilliseconds);

        if (targetLineIndex != -1 && _scrollController.hasClients) {
          _lastAutoScrollIndex = targetLineIndex;
          _scrollController.scrollToIndex(targetLineIndex, preferPosition: AutoScrollPosition.middle, duration: scrollDuration);
        }
      }
      await Future.delayed(scrollDuration);

      if (mounted) {
        setState(() => _isSwitchingSection = false);
        if (index == -1) {
          _startFreshSession(skipSeek: true);
        } else {
          _startCountdown();
        }
      }

    } catch (e) {
      debugPrint("Seek error: $e");

      if (mounted) {
        setState(() => _isSwitchingSection = false);
        _handlePlaybackError(e);
      }
    }
  }

  // Đếm ngược trước khi bắt đầu
  void _startCountdown() {
    if (!mounted) return;
    setState(() {
      _isCountingDown = true;
      _countdownValue = 3;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownValue > 1) {
        setState(() => _countdownValue--);
      } else {
        timer.cancel();
        setState(() => _isCountingDown = false);
        if (!_isSessionStarted) {
          await _startFreshSession(skipSeek: true);
        } else {
          await _resumeSession();
        }
      }
    });
  }

  // Dừng nhạc khi hát hết đoạn (Section)
  void _stopAtSectionEnd() {
    _pauseSession();
    _countdownTimer?.cancel();
    _isCountingDown = false;
    setState(() {
      // _isCompleted = false;
      // _targetEndTime = null;
    });
  }

  // ===========================
  // SCROLLING & LYRICS LOGIC
  // ===========================

  // Tìm dòng đang hát
  int _findActiveLineIndex(int currentMs) {
    if (_lyrics.isEmpty) return -1;
    return _lyrics.lastIndexWhere((line) => currentMs >= line.startTime);
  }

  // Cuộn đến dòng đang hát
  void _scrollToCurrentLine() {
    if (_lyrics.isEmpty) return;
    final currentMs = _beatPlayer.position.inMilliseconds;
    final activeIndex = _findActiveLineIndex(currentMs);

    if (activeIndex != -1 && _scrollController.hasClients) {
      _scrollController.scrollToIndex(
        activeIndex,
        preferPosition: AutoScrollPosition.middle,
        duration: const Duration(milliseconds: 300),
      );
      _lastAutoScrollIndex = activeIndex;
    }
  }

  // Tự động cuộn
  void _autoScroll(Duration position) {
    if (_lyrics.isEmpty) return;
    if (_isDraggingSeekBar) return;

    int currentMs = position.inMilliseconds;
    if (currentMs > _lyrics.last.endTime + 2000) return;

    final activeIndex = _findActiveLineIndex(currentMs);
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

  // ===========================
  // VOLUME & VOCAL CONTROL
  // ===========================

  // Bật/ tắt tiếng ca sĩ
  void _toggleVocal() {
    if (!_hasVocalUrl) return;
    setState(() {
      if (_vocalVolume > 0) {
        _vocalVolume = 0.0;
        _isVocalEnabled = false;
      } else {
        _vocalVolume = _savedVocalVolume;
        _isVocalEnabled = true;
      }
    });
    _vocalPlayer.setVolume(_vocalVolume);
  }

  // Chỉnh âm Beat
  void _updateBeatVolume(double value) {
    setState(() => _beatVolume = value);
    _beatPlayer.setVolume(value);
  }

  // Chỉnh âm Vocal
  void _updateVocalVolume(double value) {
    setState(() {
      _vocalVolume = value;
      if (value > 0) {
        _isVocalEnabled = true;
        _savedVocalVolume = value;
      } else {
        _isVocalEnabled = false;
      }
    });
    _vocalPlayer.setVolume(value);
  }

  // ============================
  // FILE & RECORDING UTILS
  // ============================

  // Bắt đầu thu âm
  void _startRecordTimer({bool reset = false}) {
    if (reset) _currentRecDuration = Duration.zero;
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _currentRecDuration += const Duration(seconds: 1));
    });
  }

  // Dừng thu âm
  void _stopRecordTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  // Hủy và xóa file thu âm tạm
  Future<void> _discardRecording() async {
    _stopRecordTimer();
    try {
      await _audioRecorder.stop();
      if (_recordingPath != null) {
        final file = File(_recordingPath!);
        if (await file.exists()) await file.delete();
      }
      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _isSessionStarted = false;
      });
      // if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã hủy bản thu âm")));
    } catch (e) {
      debugPrint("Discard Error: $e");
    }
  }

  // Lưu file thu âm vào thư mục chính thức
  Future<void> _saveRecording(String fileName) async {
    _stopRecordTimer();
    try {
      await _audioRecorder.stop();
      if (_recordingPath == null) return;
      final File sourceFile = File(_recordingPath!);
      if (!await sourceFile.exists()) return;

      final downloadDir = Directory('/storage/emulated/0/Download/KaraokeApp');
      if (!await downloadDir.exists()) await downloadDir.create(recursive: true);

      String cleanName = fileName.replaceAll(RegExp(r'[^\w\s\-]'), '');
      final newPath = '${downloadDir.path}/$cleanName.wav';

      await sourceFile.rename(newPath);

      setState(() {
        _isRecording = false;
        _recordingPath = newPath;
        _isSessionStarted = true;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Đã lưu: $cleanName.wav")));
    } catch (e) {
      debugPrint("Save Error: $e");
    }
  }

  void _resetUIState() {
    _lastAutoScrollIndex = -1;
    setState(() {
      _selectedSectionIndex = -1;
      _isUserScrolling = false;
      _isSessionStarted = false;
    });
    if (_scrollController.hasClients && _lyrics.isNotEmpty) {
      _scrollController.scrollToIndex(0, preferPosition: AutoScrollPosition.middle);
    }
  }

  // =======================
  // DIALOGS & POPUPS
  // =======================

  // Hiện bảng chỉnh volume
  void _showVolumeDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
            builder: (context, setModalState) {
              return Container(
                padding: const EdgeInsets.all(20),
                height: 250,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: Text("Tuỳ chỉnh âm thanh", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                    const SizedBox(height: 20),
                    // Beat Volume
                    Row(
                      children: [
                        const Icon(Icons.music_note, color: Colors.white70),
                        const SizedBox(width: 10),
                        const Text("Nhạc nền", style: TextStyle(color: Colors.white)),
                        Expanded(
                          child: Slider(
                            value: _beatVolume,
                            min: 0.0, max: 1.0,
                            activeColor: const Color(0xFFFF00CC),
                            inactiveColor: Colors.white24,
                            onChanged: (val) {
                              _updateBeatVolume(val);
                              setModalState(() {});
                            },
                          ),
                        ),
                        Text("${(_beatVolume * 100).toInt()}%", style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                    // Vocal Volume
                    Row(
                      children: [
                        const Icon(Icons.mic, color: Colors.white70),
                        const SizedBox(width: 10),
                        const Text("Giọng ca sĩ", style: TextStyle(color: Colors.white)),
                        Expanded(
                          child: Slider(
                            value: _vocalVolume,
                            min: 0.0, max: 1.0,
                            activeColor: const Color(0xFFFF00CC),
                            inactiveColor: Colors.white24,
                            onChanged: (val) {
                              _updateVocalVolume(val);
                              setModalState(() {});
                            },
                          ),
                        ),
                        Text("${(_vocalVolume * 100).toInt()}%", style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              );
            }
        );
      },
    );
  }

  // Hiện lựa chọn thu âm
  void _showRecordingOptionsDialog({bool allowContinue = true}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("Kết thúc thu âm", style: TextStyle(color: Colors.white)),
          content: const Text("Bạn muốn lưu bài hát này không?", style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _discardRecording();
                _isHandlingCompletion = false;
              },
              child: const Text("Hủy bỏ", style: TextStyle(color: Colors.redAccent)),
            ),
            if (allowContinue)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _resumeSession();
                },
                child: const Text("Tiếp tục hát", style: TextStyle(color: Colors.white)),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF00CC)),
              onPressed: () {
                Navigator.pop(context);
                _showSaveNameDialog();
              },
              child: const Text("Lưu bài", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // Đăt tên file lưu
  void _showSaveNameDialog({bool shouldPopAfterSave = false}) {
    final TextEditingController nameController = TextEditingController();
    nameController.text = "${_song?.title ?? 'Record'}_${DateTime.now().hour}${DateTime.now().minute}";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("Lưu bản thu", style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: "Tên bản ghi âm",
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF00CC))),
                suffixText: ".wav",
                suffixStyle: TextStyle(color: Colors.white30)
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _discardRecording();
              },
              child: const Text("Hủy", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF00CC)),
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context);
                  _saveRecording(name).then((_) {
                    if (shouldPopAfterSave) widget.onBack();
                  });
                }
              },
              child: const Text("Xác nhận", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showExitConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Thoát màn hình?", style: TextStyle(color: Colors.white)),
        content: const Text("Bạn đang thu âm. Bạn có muốn lưu lại trước khi thoát không?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _discardRecording();
              widget.onBack();
            },
            child: const Text("Thoát (Không lưu)", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF00CC)),
            onPressed: () {
              Navigator.pop(context);
              _showSaveNameDialog(shouldPopAfterSave: true);
            },
            child: const Text("Lưu & Thoát", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSwitchSectionDialog(int newIndex) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Đổi đoạn hát?", style: TextStyle(color: Colors.white)),
        content: const Text("Bạn có muốn lưu bản thu hiện tại trước khi chuyển đoạn không?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _discardRecording();
              _prepareToPlaySection(newIndex);
            },
            child: const Text("Không lưu", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF00CC)),
            onPressed: () {
              Navigator.pop(context);
              _showSaveNameDialogAndThenSwitch(newIndex);
            },
            child: const Text("Lưu", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSaveNameDialogAndThenSwitch(int nextSectionIndex) {
    final TextEditingController nameController = TextEditingController();
    nameController.text = "${_song?.title ?? 'Rec'}_Section";
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text("Lưu bản thu", style: TextStyle(color: Colors.white)),
            content: TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF00CC))),
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () {Navigator.pop(context);},
                child: const Text("Quay lại", style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF00CC)),
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isNotEmpty) {
                    Navigator.pop(context);
                    _saveRecording(name).then((_) {
                      _prepareToPlaySection(nextSectionIndex);
                    });
                  }
                },
                child: const Text("Lưu", style: TextStyle(color: Colors.white)),
              )
            ]
        )
    );
  }

  void _showNetworkErrorSaveDialog(String errorMsg) {
    showDialog(
      context: context,
      barrierDismissible: false, // Bắt buộc chọn
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.redAccent),
              SizedBox(width: 10),
              Expanded(child: Text("Mất kết nối!", style: TextStyle(color: Colors.white))),
            ],
          ),
          content: Text(
            "Không thể tải tiếp nhạc nền do lỗi mạng.\n\nBạn đã hát được ${_formatTime(_currentRecDuration)}. Bạn có muốn lưu lại bản thu này trước khi thoát không?",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Đóng dialog
                _discardRecording(); // Xóa file

                // Chuyển sang màn hình lỗi
                setState(() {
                  _errorMessage = "$errorMsg\n(Bản thu đã bị hủy)";
                });
              },
              child: const Text("Không lưu", style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF00CC)),
              onPressed: () {
                Navigator.pop(context); // Đóng dialog hỏi lưu

                // Mở dialog đặt tên file (Logic cũ)
                // Tuy nhiên ta cần sửa logic sau khi lưu xong -> Hiện màn hình lỗi
                _showSaveNameDialogForError(errorMsg);
              },
              child: const Text("Lưu bản thu", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showSaveNameDialogForError(String errorMsg) {
    final TextEditingController nameController = TextEditingController();
    nameController.text = "${_song?.title ?? 'Record'}_ErrSave";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("Lưu bản thu khẩn cấp", style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: "Tên bản ghi âm",
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF00CC))),
                suffixText: ".wav",
                suffixStyle: TextStyle(color: Colors.white30)
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _discardRecording();
                setState(() {
                  _errorMessage = "$errorMsg\n(Đã hủy lưu)";
                });
              },
              child: const Text("Hủy", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF00CC)),
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context);
                  // Lưu xong thì hiện màn hình lỗi
                  _saveRecording(name).then((_) {
                    if (mounted) {
                      setState(() {
                        _errorMessage = errorMsg; // Trigger hiện _buildErrorUI
                      });
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã lưu thành công!")));
                    }
                  });
                }
              },
              child: const Text("Lưu", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // Hát lại từ đầu
  Future<void> _confirmRestartSession() async {
    await _pauseSession();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("Hát lại từ đầu?", style: TextStyle(color: Colors.white)),
          content: const Text("Bản thu âm hiện tại sẽ bị xóa. Bạn có chắc chắn muốn hát lại không?", style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _resumeSession();
              },
              child: const Text("Tiếp tục hát", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
              onPressed: () {
                Navigator.pop(context);
                _restartSession();
              },
              child: const Text("Hát lại", style: TextStyle(color: Colors.black)),
            ),
          ],
        );
      },
    );
  }

  // ========================
  // BUILD METHODS (UI)
  // ========================

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
        ),
        body: _buildErrorUI(),
      );
    }

    final topPadding = MediaQuery.of(context).padding.top;
    final appBarHeight = kToolbarHeight;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            Text(
              _song?.title ?? "Đang tải...",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _song?.artistName ?? "",
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Colors.white70),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _onBackPressed,
        ),
        actions: [
          IconButton(
            onPressed: () {
              setState(() => _isFavorite = !_isFavorite);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_isFavorite ? "Đã thêm vào yêu thích ❤️" : "Đã bỏ yêu thích"), duration: const Duration(seconds: 1)),
              );
            },
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_outline,
              color: _isFavorite ? Colors.red : Colors.white,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.black],
          ),
        ),
        child: Column(
          children: [
            SizedBox(height: appBarHeight + topPadding),
            if (_sections.isNotEmpty) _buildSectionButtons(),
            Expanded(
              child: Stack(
                children: [
                  _buildLyricSection(),
                  if (_isCountingDown)
                    Container(
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("Chuẩn bị...", style: TextStyle(color: Colors.white70, fontSize: 20)),
                          const SizedBox(height: 10),
                          Text(
                            "$_countdownValue",
                            style: const TextStyle(color: Color(0xFFFF00CC), fontSize: 80, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 20, color: Color(0xFFFF00CC), offset: Offset(0,0))]),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.only(bottom: 20, top: 10),
              child: _buildControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionButtons() {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: _sections.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final bool isFullSongBtn = index == 0;
          final int actualSectionIndex = index - 1;
          final bool isSelected = (isFullSongBtn && _selectedSectionIndex == -1) ||
              (!isFullSongBtn && _selectedSectionIndex == actualSectionIndex);

          String btnText = isFullSongBtn ? "CẢ BÀI" : _sections[actualSectionIndex].name.toUpperCase();
          IconData btnIcon = isFullSongBtn ? Icons.all_inclusive : Icons.bolt;

          return GestureDetector(
            onTap: () {
              if (isSelected) return;
              _handleSectionTap(isFullSongBtn ? -1 : actualSectionIndex);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFF00CC) : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? const Color(0xFFFF00CC) : const Color(0xFFFF00CC).withOpacity(0.5)),
                boxShadow: isSelected ? [const BoxShadow(color: Color(0x66FF00CC), blurRadius: 8, offset: Offset(0, 2))] : [],
              ),
              child: Row(
                children: [
                  Icon(btnIcon, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(btnText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLyricSection() {
    if (!_isLyricsLoaded) return const Center(child: SkeletonLoadingEffect());
    if (_lyrics.isEmpty) {
      if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFFFF00CC)));
      return const Center(child: Text("Chưa có lời bài hát", style: TextStyle(color: Colors.white54)));
    }

    return StreamBuilder<Duration>(
      stream: _positionStreamController.stream,
      initialData: Duration.zero,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final currentMs = position.inMilliseconds + _syncOffset;
        int activeIndex = _findActiveLineIndex(currentMs);
        bool highlightActiveLine = true;

        if (activeIndex != -1 && activeIndex < _lyrics.length) {
          final currentLine = _lyrics[activeIndex];
          if (currentMs > currentLine.endTime + 5000) {
            if (activeIndex + 1 < _lyrics.length) {
              if (currentMs < _lyrics[activeIndex + 1].startTime) highlightActiveLine = false;
            } else {
              highlightActiveLine = false;
            }
          }
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification && notification.dragDetails != null) {
              _isUserScrolling = true;
              _userScrollTimeoutTimer?.cancel();
            } else if (notification is ScrollEndNotification && _isUserScrolling) {
              _userScrollTimeoutTimer = Timer(const Duration(seconds: 2), () {
                if (mounted) {
                  setState(() => _isUserScrolling = false);
                  _scrollToCurrentLine();
                }
              });
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(20, 40, 20, MediaQuery.of(context).size.height * 0.6),
            itemCount: _lyrics.length,
            physics: const BouncingScrollPhysics(),
            cacheExtent: 500,
            itemBuilder: (context, index) {
              final line = _lyrics[index];
              int? countdownValue;
              int timeUntilStart = line.startTime - currentMs;
              if (timeUntilStart > 0 && timeUntilStart <= 4000) {
                if (index == 0){
                  countdownValue = (timeUntilStart / 1000).ceil();
                } else {
                  if (line.startTime - _lyrics[index - 1].endTime >= 10000) countdownValue = (timeUntilStart / 1000).ceil();
                }
                if (countdownValue != null && countdownValue > 3) countdownValue = null;
              }
              bool isFastFlow = false;
              if (index < _lyrics.length - 1) {
                if (_lyrics[index + 1].startTime - line.endTime < 600) isFastFlow = true;
              }

              return AutoScrollTag(
                key: ValueKey(index),
                controller: _scrollController,
                index: index,
                child: KaraokeLineItem(
                  line: line,
                  currentPositionMs: currentMs,
                  index: index,
                  activeIndex: activeIndex,
                  highlightActiveLine: highlightActiveLine,
                  countdownValue: countdownValue,
                  isFastFlow: isFastFlow,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    if (!_isLyricsLoaded) return const ControlsSkeleton();
    return StreamBuilder<Duration?>(
      stream: _beatPlayer.durationStream,
      builder: (context, snapshotDuration) {
        final duration = snapshotDuration.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _beatPlayer.positionStream,
          builder: (context, snapshotPosition) {
            var position = snapshotPosition.data ?? Duration.zero;
            if (position > duration) position = duration;
            IconData playIcon = Icons.play_arrow;
            if (_isCompleted) playIcon = Icons.replay;
            else if (_beatPlayer.playing) playIcon = Icons.pause;
            final displayPosition = _isDraggingSeekBar ? Duration(milliseconds: _dragValue!.toInt()) : position;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbColor: const Color(0xFFFF00CC),
                      activeTrackColor: const Color(0xFFFF00CC),
                      inactiveTrackColor: Colors.white24,
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: _isDraggingSeekBar ? _dragValue! : position.inMilliseconds.toDouble().clamp(0.0, duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 0.0),
                      max: duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                      onChangeStart: (value) => setState(() { _isDraggingSeekBar = true; _dragValue = value; }),
                      onChanged: (value) => setState(() => _dragValue = value),
                      onChangeEnd: (value) {
                        setState(() { _isDraggingSeekBar = false; _dragValue = null; });
                        _performSeek(value);
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatTime(displayPosition), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      Text(_formatTime(duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (_isSessionStarted)
                        IconButton(onPressed: _confirmRestartSession, iconSize: 30, tooltip: "Hát lại từ đầu", icon: const Icon(Icons.refresh_rounded, color: Colors.orangeAccent))
                      else const SizedBox(width: 48),

                      IconButton(onPressed: _showVolumeDialog, iconSize: 30, tooltip: "Chỉnh âm lượng", icon: const Icon(Icons.tune_rounded, color: Colors.white)),

                      GestureDetector(
                        onTap: _isSwitchingSection ? null : _togglePlayPause,
                        child: Container(
                          width: 70, height: 70,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFF00CC), boxShadow: [BoxShadow(color: Color(0x66FF00CC), blurRadius: 20, spreadRadius: 2)]),
                          child: Center(
                            child: _isSwitchingSection
                                ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                                : Icon(!_isSessionStarted ? Icons.fiber_manual_record_rounded : playIcon, color: Colors.white, size: !_isSessionStarted ? 45 : 38),
                          ),
                        ),
                      ),

                      if (_isSessionStarted)
                        Builder(builder: (context) {
                          final bool canSave = _currentRecDuration.inSeconds >= 10;
                          return IconButton(
                            onPressed: canSave ? _finishRecordingSession : null,
                            iconSize: 40,
                            tooltip: canSave ? "Kết thúc & Lưu (${_formatTime(_currentRecDuration)})" : "Cần thu thêm ${10 - _currentRecDuration.inSeconds}s",
                            icon: Icon(Icons.check_circle_rounded, color: canSave ? Colors.greenAccent : Colors.white24),
                          );
                        })
                      else const SizedBox(width: 48),

                      IconButton(
                        onPressed: _toggleVocal,
                        iconSize: 28,
                        tooltip: "Bật/Tắt lời ca sĩ",
                        icon: Icon(Icons.record_voice_over, color: _vocalVolume > 0 ? const Color(0xFFFF00CC) : Colors.white54),
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

  Widget _buildErrorUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 80, color: Colors.white38),
            const SizedBox(height: 20),
            const Text(
              "Đã xảy ra lỗi! Vui lòng kiểm tra kết nối Internet!",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),

            // const SizedBox(height: 10),
            // Text(
            //   _errorMessage ?? "",
            //   textAlign: TextAlign.center,
            //   style: const TextStyle(color: Colors.white70),
            // ),

            const SizedBox(height: 30),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF00CC),
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text("Thử lại", style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

}

// =====================
// HELPER WIDGETS
// =====================

class KaraokeLineItem extends StatelessWidget {
  final LyricLine line;
  final int currentPositionMs;
  final int index;
  final int activeIndex;
  final bool highlightActiveLine;
  final int? countdownValue;
  final bool isFastFlow;

  const KaraokeLineItem({
    Key? key,
    required this.line,
    required this.currentPositionMs,
    required this.index,
    required this.activeIndex,
    this.highlightActiveLine = true,
    this.countdownValue,
    this.isFastFlow = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool isActive = (index == activeIndex);
    bool isNextFocus = (index == activeIndex + 1);

    double scale = 1.0;
    double opacity = 0.5;

    if (isActive) {
      if (highlightActiveLine) {
        scale = 1.1;
        opacity = 1.0;
      } else {
        scale = 1.0;
        opacity = 0.6;
      }
    }
    else if (isNextFocus) {
      if (!highlightActiveLine) {
        scale = 1.05;
        opacity = 0.9;
      } else {
        scale = 1.0;
        opacity = 0.6;
      }
    } else if (index < activeIndex) {
      scale = 0.95;
      opacity = 0.3;
    }

    const double fixedFontSize = 18.0;
    const TextStyle commonStyle = TextStyle(
      fontSize: fixedFontSize,
      fontWeight: FontWeight.w600,
      height: 1.5,
      color: Colors.white,
      fontFamily: 'Roboto',
    );

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12.0),
        width: double.infinity,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6.0,
            runSpacing: 6.0,
            children: [
              if (countdownValue != null)
                Container(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    "$countdownValue",
                    style: const TextStyle(
                      color: Color(0xFFFF00CC),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ...line.words.asMap().entries.map((entry) {
                final wordIndex = entry.key;
                final word = entry.value;
                final isLastWord = wordIndex == line.words.length - 1;

                return _buildWord(
                  word,
                  commonStyle,
                  isActive && highlightActiveLine,
                  index < activeIndex,
                  isLastWord,
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWord(LyricWord word, TextStyle style, bool shouldKaraoke, bool isPastLine, bool isLastWord) {
    if (isPastLine) {
      return Text(word.text, style: style.copyWith(color: const Color(0xFFFF00CC)));
    }

    if (!shouldKaraoke) {
      if (currentPositionMs >= word.endTime) {
        return Text(word.text, style: style.copyWith(color: const Color(0xFFFF00CC)));
      }
      return Text(word.text, style: style);
    }

    if (currentPositionMs >= word.endTime) {
      return Text(word.text, style: style.copyWith(color: const Color(0xFFFF00CC)));
    }

    if (currentPositionMs < word.startTime) {
      return Text(word.text, style: style.copyWith(color: Colors.white));
    }

    double effectiveEndTime = word.endTime.toDouble();

    if (isLastWord && isFastFlow) {
      double fakeEnd = effectiveEndTime - 250;
      if (fakeEnd > word.startTime) {
        effectiveEndTime = fakeEnd;
      }
    }

    final double progress = (currentPositionMs - word.startTime) / (effectiveEndTime - word.startTime);
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

class SkeletonLoadingEffect extends StatefulWidget {
  const SkeletonLoadingEffect({Key? key}) : super(key: key);

  @override
  _SkeletonLoadingEffectState createState() => _SkeletonLoadingEffectState();
}

class _SkeletonLoadingEffectState extends State<SkeletonLoadingEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
      lowerBound: 0.3,
      upperBound: 0.7,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(6, (index) =>
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 40),
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              width: double.infinity,
            )
        ),
      ),
    );
  }
}

class ControlsSkeleton extends StatelessWidget {
  const ControlsSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            height: 4,
            width: double.infinity,
            color: Colors.white12,
            margin: const EdgeInsets.symmetric(vertical: 20),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CircleAvatar(radius: 15, backgroundColor: Colors.white10),
              CircleAvatar(radius: 15, backgroundColor: Colors.white10),
              Container(width: 70, height: 70, decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle)),
              CircleAvatar(radius: 20, backgroundColor: Colors.white10),
              CircleAvatar(radius: 14, backgroundColor: Colors.white10),
            ],
          )
        ],
      ),
    );
  }
}