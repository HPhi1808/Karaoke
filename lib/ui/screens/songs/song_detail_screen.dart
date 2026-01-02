import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart';

import '../../../models/song_model.dart';
import '../../../services/song_service.dart';
import '../../../utils/lrc_parser.dart';

// 1. CẬP NHẬT MODEL ĐỂ LƯU CẢ THỜI GIAN KẾT THÚC
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
  SongModel? _song;
  List<LyricLine> _lyrics = [];
  List<SongSection> _sections = [];
  bool _isLoading = true;
  bool _isFavorite = false;

  final AudioPlayer _beatPlayer = AudioPlayer();
  final AudioPlayer _vocalPlayer = AudioPlayer();
  final AutoScrollController _scrollController = AutoScrollController();
  final int _syncOffset = -99;

  bool _isVocalEnabled = false;
  bool _hasVocalUrl = false;
  bool _isCompleted = false;

  int _lastAutoScrollIndex = -1;
  bool _isUserScrolling = false;
  Timer? _userScrollTimeoutTimer;
  final StreamController<Duration> _positionStreamController = StreamController.broadcast();

  late final AudioRecorder _audioRecorder;
  bool _isRecording = false;
  String? _recordingPath;

  // --- CÁC BIẾN QUẢN LÝ SECTION ---
  Duration? _targetEndTime;
  int _selectedSectionIndex = -1;
  bool _isCountingDown = false;
  int _countdownValue = 3;
  Timer? _countdownTimer;

  // --- CÁC BIẾN QUẢN LÝ TRẠNG THÁI UI/SLIDER ---
  bool _isDraggingSeekBar = false;
  double? _dragValue;

  bool _isSwitchingSection = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _audioRecorder = AudioRecorder();
    _initAudioSession();

    _beatPlayer.positionStream.listen((position) {
      if (!_positionStreamController.isClosed) {
        _positionStreamController.add(position);
      }

      // Nếu đang bận chuyển đoạn thì KHÔNG được kích hoạt dừng nhạc
      if (_targetEndTime != null && !_isSwitchingSection && position >= _targetEndTime!) {
        _stopAtSectionEnd();
      }

      // Chỉ cuộn khi đang phát và KHÔNG kéo slider
      if (_beatPlayer.playing && !_isUserScrolling && !_isDraggingSeekBar) {
        _autoScroll(position);
      }
    });

    _beatPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_targetEndTime == null) {
          if (mounted) setState(() => _isCompleted = true);
          _beatPlayer.pause();
          if (_hasVocalUrl) _vocalPlayer.pause();
          _beatPlayer.seek(Duration.zero);
          if (_hasVocalUrl) _vocalPlayer.seek(Duration.zero);
          _lastAutoScrollIndex = -1;
          setState(() {
            _selectedSectionIndex = -1;
            _isUserScrolling = false;
          });
          if (_scrollController.hasClients && _lyrics.isNotEmpty) {
            _scrollController.scrollToIndex(0, preferPosition: AutoScrollPosition.middle);
          }
        }
      }
      else if (state.playing) {
        if (_isCompleted && mounted) setState(() => _isCompleted = false);
        if (_hasVocalUrl && _isVocalEnabled && !_vocalPlayer.playing) {
          _vocalPlayer.play();
        }
      }
      else if (!state.playing) {
        if (_hasVocalUrl && _vocalPlayer.playing) {
          _vocalPlayer.pause();
        }
      }
    });

    _loadData();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _audioRecorder.dispose();
    _beatPlayer.dispose();
    _vocalPlayer.dispose();
    _scrollController.dispose();
    _userScrollTimeoutTimer?.cancel();
    _countdownTimer?.cancel();
    _positionStreamController.close();
    super.dispose();
  }

  void _stopAtSectionEnd() {
    _beatPlayer.pause();
    if (_hasVocalUrl) _vocalPlayer.pause();
    _countdownTimer?.cancel();
    _isCountingDown = false;

    setState(() {
      _isCompleted = false;
      _targetEndTime = null;
      _selectedSectionIndex = -1;
    });
  }


  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth |
      AVAudioSessionCategoryOptions.defaultToSpeaker |
      AVAudioSessionCategoryOptions.mixWithOthers, // Quan trọng: Cho phép trộn
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music, // Dùng Music để ưu tiên chất lượng
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck, // Nhường quyền nhưng không tắt
      androidWillPauseWhenDucked: false,
    ));
  }

  Future<void> _prepareToPlaySection(int index) async {
    // 1. Bật cờ hiệu "Đang chuyển đoạn" để chặn Listener gây lỗi
    _isSwitchingSection = true;

    _beatPlayer.pause();
    if (_hasVocalUrl) _vocalPlayer.pause();
    _countdownTimer?.cancel();

    // Reset UI tạm thời
    setState(() {
      _isCompleted = false;
      _selectedSectionIndex = index;
      _isUserScrolling = false;
      _isCountingDown = false;
      // Tạm thời xóa target cũ để an toàn tuyệt đối
      _targetEndTime = null;
    });

    _lastAutoScrollIndex = -1;

    if (index == -1) {
      // --- CHẾ ĐỘ CẢ BÀI ---
      await _beatPlayer.seek(Duration.zero);
      if (_hasVocalUrl) await _vocalPlayer.seek(Duration.zero);

      if (_scrollController.hasClients && _lyrics.isNotEmpty) {
        _scrollController.scrollToIndex(0, preferPosition: AutoScrollPosition.middle, duration: const Duration(milliseconds: 600));
      }

      // Xong xuôi thì tắt cờ hiệu và phát
      _isSwitchingSection = false;
      _playAfterSetup();

    } else {
      // --- CHẾ ĐỘ SECTION ---
      final section = _sections[index];

      // 2. Thực hiện Seek trước (QUAN TRỌNG: Dùng await để đảm bảo vị trí đã thay đổi)
      await _beatPlayer.seek(section.startTime);
      if (_hasVocalUrl) await _vocalPlayer.seek(section.startTime);

      // 3. Sau khi Seek xong, mới cập nhật _targetEndTime mới
      if (mounted) {
        setState(() {
          _targetEndTime = section.endTime;
        });

        // Xử lý cuộn lời
        int targetLineIndex = _lyrics.indexWhere((line) => line.startTime >= section.startTime.inMilliseconds - 100);
        if (targetLineIndex == -1) {
          targetLineIndex = _findActiveLineIndex(section.startTime.inMilliseconds);
        }

        if (targetLineIndex != -1 && _scrollController.hasClients) {
          _lastAutoScrollIndex = targetLineIndex;
          _scrollController.scrollToIndex(
            targetLineIndex,
            preferPosition: AutoScrollPosition.middle,
            duration: const Duration(milliseconds: 800),
          );
        }
      }

      // 4. Tắt cờ hiệu và bắt đầu đếm ngược
      _isSwitchingSection = false;
      _startCountdown();
    }
  }

  void _startCountdown() {
    if (!mounted) return;
    setState(() {
      _isCountingDown = true;
      _countdownValue = 3;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownValue > 1) {
        setState(() {
          _countdownValue--;
        });
      } else {
        timer.cancel();
        setState(() {
          _isCountingDown = false;
        });
        _playAfterSetup();
      }
    });
  }

  void _playAfterSetup() {
    if (!mounted) return;
    _beatPlayer.play();
    if (_hasVocalUrl) _vocalPlayer.play();
    setState(() => _isCompleted = false);
  }

  Future<void> _loadData() async {
    try {
      final song = await SongService.instance.getSongDetail(widget.songId);
      if (mounted) setState(() => _song = song);

      List<Future> setupFutures = [];
      await _beatPlayer.setSpeed(1.0);
      await _vocalPlayer.setSpeed(1.0);

      if (song.beatUrl != null) setupFutures.add(_beatPlayer.setUrl(song.beatUrl!));
      if (song.vocalUrl != null && song.vocalUrl!.isNotEmpty) {
        _hasVocalUrl = true;
        setupFutures.add(_vocalPlayer.setUrl(song.vocalUrl!));
        await _vocalPlayer.setVolume(0.0);
      }

      await Future.wait(setupFutures);

      _beatPlayer.play();
      if (_hasVocalUrl) _vocalPlayer.play();

      if (song.lyricUrl != null) {
        final response = await http.get(Uri.parse(song.lyricUrl!));
        if (response.statusCode == 200) {
          final lrcContent = utf8.decode(response.bodyBytes);
          final result = await compute(_parseSectionsAndCleanLrc, lrcContent);
          final cleanContent = result['content'] as String;
          final sections = result['sections'] as List<SongSection>;
          final parsedLyrics = await compute(LrcParser.parse, cleanContent);

          if (mounted) {
            setState(() {
              _lyrics = parsedLyrics;
              _sections = sections;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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

  void _toggleVocal() {
    if (!_hasVocalUrl) return;
    setState(() => _isVocalEnabled = !_isVocalEnabled);
    _vocalPlayer.setVolume(_isVocalEnabled ? 1.0 : 0.0);
  }

  void _performSeek(double value) {
    if (_isCountingDown) return;
    final position = Duration(milliseconds: value.toInt());

    if (_isCompleted) {
      setState(() => _isCompleted = false);
    }

    if (_selectedSectionIndex != -1) {
      final currentSection = _sections[_selectedSectionIndex];
      // Nếu kéo ra ngoài phạm vi section (cho phép lệch 1s) -> Thoát chế độ section
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

    if (_beatPlayer.playing && _hasVocalUrl && _isVocalEnabled) {
      _vocalPlayer.play();
    }

    _lastAutoScrollIndex = -1;
    setState(() => _isUserScrolling = false);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      // Nếu tua về đầu bài -> Cuộn lên đầu
      if (position < const Duration(seconds: 2) && _lyrics.isNotEmpty) {
        _scrollController.scrollToIndex(0, preferPosition: AutoScrollPosition.middle, duration: const Duration(milliseconds: 300));
      } else {
        _scrollToCurrentLine();
      }
    });
  }

  void _onPlayPause() {
    if (_isCountingDown) return;

    if (_isCompleted) {
      // Replay từ đầu
      setState(() {
        _isCompleted = false;
        _targetEndTime = null;
        _selectedSectionIndex = -1;
      });
      _beatPlayer.seek(Duration.zero);
      if (_hasVocalUrl) _vocalPlayer.seek(Duration.zero);
      _beatPlayer.play();
      if (_hasVocalUrl) _vocalPlayer.play();
      if (_scrollController.hasClients && _lyrics.isNotEmpty) {
        _scrollController.scrollToIndex(0, preferPosition: AutoScrollPosition.middle);
      }
    } else if (_beatPlayer.playing) {
      _beatPlayer.pause();
      if (_hasVocalUrl) _vocalPlayer.pause();
    } else {
      if (_hasVocalUrl) {
        _vocalPlayer.seek(_beatPlayer.position);
        _vocalPlayer.play();
      }
      _beatPlayer.play();
    }
    setState(() {});
  }

  int _findActiveLineIndex(int currentMs) {
    if (_lyrics.isEmpty) return -1;
    return _lyrics.lastIndexWhere((line) => currentMs >= line.startTime);
  }

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

  void _autoScroll(Duration position) {
    if (_lyrics.isEmpty) return;
    // Chặn cuộn khi đang kéo
    if (_isDraggingSeekBar) return;

    int currentMs = position.inMilliseconds;
    // Chặn cuộn ở đoạn Outro để tránh giật
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

  Future<void> _onRecordPressed() async {
    // --- TRƯỜNG HỢP 1: ĐANG GHI -> DỪNG ---
    if (_isRecording) {
      try {
        // Dừng ghi âm
        final path = await _audioRecorder.stop();

        // Dừng nhạc
        _beatPlayer.pause();
        if (_hasVocalUrl) _vocalPlayer.pause();

        debugPrint("Đã dừng ghi âm. File thô tại: $path");

        if (mounted) _showRecordingOptionsDialog();
      } catch (e) {
        debugPrint("Lỗi dừng: $e");
      }
    }
    // --- TRƯỜNG HỢP 2: BẮT ĐẦU GHI ---
    else {
      // 1. Xin quyền (Thêm quyền storage nếu Android < 13)
      Map<Permission, PermissionStatus> statuses = await [
        Permission.microphone,
        Permission.storage,
        Permission.manageExternalStorage, // Thử xin quyền cao nhất nếu máy cho phép
      ].request();

      if (statuses[Permission.microphone] != PermissionStatus.granted) {
        return;
      }

      try {
        // 2. Tạo đường dẫn TRỰC TIẾP ra thư mục Download
        Directory dir;
        if (Platform.isAndroid) {
          dir = Directory('/storage/emulated/0/Download/KaraokeTemp');
        } else {
          dir = await getApplicationDocumentsDirectory();
        }

        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        // Dùng đuôi .wav cho an toàn nhất
        final fileName = 'rec_${DateTime.now().millisecondsSinceEpoch}.wav';
        final path = '${dir.path}/$fileName';

        // 3. TẮT NHẠC HOÀN TOÀN TRƯỚC KHI GHI
        if (_beatPlayer.playing) await _beatPlayer.pause();
        if (_hasVocalUrl && _vocalPlayer.playing) await _vocalPlayer.pause();

        // 4. Cấu hình WAV
        const config = RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
        );

        // 5. Bắt đầu ghi
        await _audioRecorder.start(config, path: path);

        // CHỜ 1 GIÂY (1000ms) ĐỂ MIC KHỞI ĐỘNG XONG HẲN
        await Future.delayed(const Duration(milliseconds: 1000));

        setState(() {
          _isRecording = true;
          _recordingPath = path;
        });

        // 6. PHÁT LẠI NHẠC (SỬA ĐOẠN NÀY ĐỂ FIX LỖI MẤT VOCAL)

        // A. Phát Beat trước
        _beatPlayer.play();

        // B. Xử lý Vocal kỹ hơn
        if (_hasVocalUrl && _isVocalEnabled) {
          await _vocalPlayer.seek(_beatPlayer.position);

          await _vocalPlayer.setVolume(1.0);

          // 3. Phát Vocal
          _vocalPlayer.play();
        } else if (_hasVocalUrl && !_isVocalEnabled) {
          await _vocalPlayer.seek(_beatPlayer.position);
          await _vocalPlayer.setVolume(0.0);
          _vocalPlayer.play();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Đang thu âm")));
        }

      } catch (e) {
        debugPrint("Lỗi Start: $e");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: $e")));
        _beatPlayer.play();
      }
    }
  }

  void _showRecordingOptionsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("Tạm dừng thu âm", style: TextStyle(color: Colors.white)),
          content: const Text(
            "Bạn muốn làm gì với bản thu này?",
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            // NÚT 1: KHÔNG LƯU (Hủy)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _discardRecording();
              },
              child: const Text("Không lưu", style: TextStyle(color: Colors.redAccent)),
            ),

            // NÚT 2: TIẾP TỤC HÁT
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _resumeRecording();
              },
              child: const Text("Tiếp tục hát", style: TextStyle(color: Colors.blueAccent)),
            ),

            // NÚT 3: LƯU
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF00CC)),
              onPressed: () {
                Navigator.pop(context);
                _showSaveNameDialog();
              },
              child: const Text("Lưu", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showSaveNameDialog() {
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
                  _saveRecording(name);
                }
              },
              child: const Text("Xác nhận", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // --- LOGIC TIẾP TỤC ---
  Future<void> _resumeRecording() async {
    try {
      await _audioRecorder.resume();
      _beatPlayer.play();
      if (_hasVocalUrl && _isVocalEnabled) _vocalPlayer.play();
    } catch (e) {
      debugPrint("Lỗi resume: $e");
    }
  }

  // --- LOGIC HỦY BỎ ---
  Future<void> _discardRecording() async {
    try {
      await _audioRecorder.stop();

      // Xóa file tạm
      if (_recordingPath != null) {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      setState(() {
        _isRecording = false;
        _recordingPath = null;
      });

      // Nhạc vẫn dừng, muốn reset nhạc về đầu hay không tùy bạn
      // _beatPlayer.seek(Duration.zero);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Đã hủy bản thu âm"))
        );
      }
    } catch (e) {
      debugPrint("Lỗi hủy file: $e");
    }
  }

  // --- LOGIC LƯU FILE CHÍNH THỨC ---
  Future<void> _saveRecording(String fileName) async {
    try {
      await _audioRecorder.stop();

      if (_recordingPath == null) {
        debugPrint("Lỗi: Không tìm thấy đường dẫn file gốc");
        return;
      }

      final File sourceFile = File(_recordingPath!);
      if (!await sourceFile.exists()) {
        debugPrint("Lỗi: File gốc không tồn tại ở $_recordingPath");
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi: File ghi âm bị mất!")));
        return;
      }

      // Tạo đường dẫn mới
      final downloadDir = Directory('/storage/emulated/0/Download/KaraokeApp');
      if (!await downloadDir.exists()) await downloadDir.create(recursive: true);

      String cleanName = fileName.replaceAll(RegExp(r'[^\w\s\-]'), '');
      final newPath = '${downloadDir.path}/$cleanName.wav';

      // Đổi tên (Move)
      await sourceFile.rename(newPath);

      setState(() {
        _isRecording = false;
        _recordingPath = newPath;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Đã lưu: $cleanName.wav")));
      }

    } catch (e) {
      debugPrint("Lỗi lưu file: $e");
      try {
        final sourceFile = File(_recordingPath!);
        String cleanName = fileName.replaceAll(RegExp(r'[^\w\s\-]'), '');
        final downloadDir = Directory('/storage/emulated/0/Download/KaraokeApp');
        final newPath = '${downloadDir.path}/$cleanName.wav';

        await sourceFile.copy(newPath);
        await sourceFile.delete();

        setState(() {
          _isRecording = false;
          _recordingPath = newPath;
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Đã lưu (copy): $cleanName.wav")));
      } catch (e2) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi lưu file: $e2")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          onPressed: widget.onBack,
        ),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _isFavorite = !_isFavorite;
              });

              // (Tuỳ chọn) Hiện thông báo nhỏ cho người dùng biết
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isFavorite ? "Đã thêm vào yêu thích ❤️" : "Đã bỏ yêu thích"),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_outline, // Nếu True thì tim đặc, False thì tim rỗng
              color: _isFavorite ? Colors.red : Colors.white,        // Nếu True thì màu đỏ, False thì màu trắng
            ),
            tooltip: _isFavorite ? "Bỏ thích" : "Yêu thích",
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
              _prepareToPlaySection(isFullSongBtn ? -1 : actualSectionIndex);
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
              final nextLine = _lyrics[activeIndex + 1];
              if (currentMs < nextLine.startTime) highlightActiveLine = false;
            } else {
              highlightActiveLine = false;
            }
          }
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              if (notification.dragDetails != null) {
                _isUserScrolling = true;
                _userScrollTimeoutTimer?.cancel();
              }
            } else if (notification is ScrollEndNotification) {
              if (_isUserScrolling) {
                _userScrollTimeoutTimer = Timer(const Duration(seconds: 2), () {
                  if (mounted) {
                    setState(() => _isUserScrolling = false);
                    _scrollToCurrentLine();
                  }
                });
              }
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            // Giữ padding lớn đáy để tránh lỗi giật
            padding: EdgeInsets.fromLTRB(20, 40, 20, MediaQuery.of(context).size.height * 0.6),
            itemCount: _lyrics.length,
            physics: const BouncingScrollPhysics(),
            cacheExtent: 500,
            itemBuilder: (context, index) {
              final line = _lyrics[index];
              int? countdownValue;
              int timeUntilStart = line.startTime - currentMs;
              if (timeUntilStart > 0 && timeUntilStart <= 4000) {
                if (index == 0) countdownValue = (timeUntilStart / 1000).ceil();
                else {
                  final prevLine = _lyrics[index - 1];
                  if (line.startTime - prevLine.endTime >= 10000) countdownValue = (timeUntilStart / 1000).ceil();
                }
                if (countdownValue != null && countdownValue! > 3) countdownValue = null;
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
                      onChangeStart: (value) {
                        setState(() {
                          _isDraggingSeekBar = true;
                          _dragValue = value;
                        });
                      },
                      onChanged: (value) {
                        setState(() {
                          _dragValue = value;
                        });
                      },
                      onChangeEnd: (value) {
                        setState(() {
                          _isDraggingSeekBar = false;
                          _dragValue = null;
                        });
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
                      IconButton(
                        onPressed: _onRecordPressed,
                        iconSize: 30,
                        tooltip: _isRecording ? "Dừng thu âm" : "Bắt đầu thu âm",
                        icon: _isRecording
                            ? const Icon(Icons.stop_circle_rounded, color: Colors.redAccent)
                            : const Icon(Icons.mic_none_rounded, color: Colors.white54),
                      ),
                      IconButton(onPressed: () {}, iconSize: 40, icon: const Icon(Icons.skip_previous_rounded, color: Colors.white)),
                      GestureDetector(
                        onTap: _onPlayPause,
                        child: Container(
                          width: 70, height: 70,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFF00CC), boxShadow: [BoxShadow(color: Color(0x66FF00CC), blurRadius: 20, spreadRadius: 2)]),
                          child: Icon(playIcon, color: Colors.white, size: 38),
                        ),
                      ),
                      IconButton(onPressed: () {}, iconSize: 40, icon: const Icon(Icons.skip_next_rounded, color: Colors.white)),
                      IconButton(
                        onPressed: _toggleVocal,
                        iconSize: 28,
                        tooltip: "Bật/Tắt lời ca sĩ",
                        icon: Icon(Icons.record_voice_over, color: _isVocalEnabled ? const Color(0xFFFF00CC) : Colors.white54),
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

// --- CLASS KaraokeLineItem GIỮ NGUYÊN ---
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