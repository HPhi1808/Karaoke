import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../moments/create_moment_screen.dart';
class MeRecordingsScreen extends StatefulWidget {
  final bool isPickingMode;
  const MeRecordingsScreen({super.key, this.isPickingMode = false,});

  @override
  State<MeRecordingsScreen> createState() => _MeRecordingsScreenState();
}

class _MeRecordingsScreenState extends State<MeRecordingsScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<FileSystemEntity> _files = [];
  bool _isLoading = true;
  String? _currentPlayingPath;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadRecordings();

    // Lắng nghe trạng thái player
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _currentPlayingPath = null;
            _isPlaying = false;
            _audioPlayer.stop();
            _audioPlayer.seek(Duration.zero);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadRecordings() async {
    // --- LOGIC CHO WEB ---
    if (kIsWeb) {
      // Web không thể quét file local.
      // Ta set danh sách rỗng và tắt loading ngay.
      setState(() {
        _files = [];
        _isLoading = false;
      });
      return;
    }
    // ---------------------

    // --- LOGIC CHO MOBILE (ANDROID/IOS) ---
    if (await Permission.storage.request().isDenied &&
        await Permission.manageExternalStorage.request().isDenied) {
      // Handle permission denied if needed
    }

    try {
      final Directory dir = Directory('/storage/emulated/0/Download/KaraokeApp');

      if (await dir.exists()) {
        setState(() {
          // Lọc file wav và cả m4a (nếu bạn đã đổi code save sang m4a)
          _files = dir.listSync()
              .where((item) => item.path.endsWith('.wav') || item.path.endsWith('.m4a'))
              .toList()
            ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
          _isLoading = false;
        });
      } else {
        setState(() {
          _files = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi load file: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _playRecording(String path) async {
    if (kIsWeb) return; // Web không play path local được

    try {
      if (_currentPlayingPath == path) {
        if (_isPlaying) {
          await _audioPlayer.pause();
        } else {
          await _audioPlayer.play();
        }
      } else {
        await _audioPlayer.stop();
        await _audioPlayer.setFilePath(path); // setFilePath chỉ dùng cho file trên máy

        setState(() => _currentPlayingPath = path);
        await _audioPlayer.play();
      }
    } catch (e) {
      debugPrint("Lỗi phát file: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Không thể phát file này"))
        );
      }
    }
  }

  Future<void> _deleteRecording(FileSystemEntity file) async {
    if (kIsWeb) return;

    try {
      if (_currentPlayingPath == file.path) {
        await _audioPlayer.stop();
        setState(() {
          _currentPlayingPath = null;
          _isPlaying = false;
        });
      }
      await file.delete();
      setState(() {
        _files.remove(file);
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã xóa bản ghi")));
    } catch (e) {
      debugPrint("Lỗi xóa file: $e");
    }
  }

  Future<void> _shareRecording(String path) async {
    if (kIsWeb) return;
    await Share.shareXFiles([XFile(path)], text: 'Nghe bản thu âm karaoke của tôi này!');
  }

  Future<void> _postRecording(FileSystemEntity file) async {
    await _audioPlayer.stop();
    setState(() {
      _isPlaying = false;
      _currentPlayingPath = null;
    });
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CreateMomentScreen(selectedFile: File(file.path)),
        ),
      ).then((_) {
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
            widget.isPickingMode ? "Chọn bản thu để đăng" : "Bản thu âm của tôi",
            style: const TextStyle(color: Colors.black)
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // 1. Giao diện riêng cho Web
    if (kIsWeb) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.download_done_rounded, size: 80, color: Color(0xFFFF00CC)),
            const SizedBox(height: 20),
            const Text(
              "Trên trình duyệt Web",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Các bản thu âm của bạn đã được tải trực tiếp về thư mục Downloads trên máy tính.\n\nTrình duyệt không cho phép ứng dụng quét lại các file này vì lý do bảo mật.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                // Có thể mở 1 dialog hướng dẫn hoặc quay về Home
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text("Quay lại"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            )
          ],
        ),
      );
    }

    // 2. Giao diện cho Mobile (Giữ nguyên logic cũ)
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_files.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final String fileName = file.path.split('/').last.replaceAll('.wav', '').replaceAll('.m4a', '');

        DateTime modified;
        try {
          modified = file.statSync().modified;
        } catch(e) {
          modified = DateTime.now();
        }

        final bool isPlayingThis = _currentPlayingPath == file.path && _isPlaying;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: isPlayingThis ? const Color(0xFFFF00CC) : Colors.grey[200],
              child: Icon(
                isPlayingThis ? Icons.pause : Icons.play_arrow,
                color: isPlayingThis ? Colors.white : Colors.black,
              ),
            ),
            title: Text(
              fileName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isPlayingThis ? const Color(0xFFFF00CC) : Colors.black,
              ),
            ),
            subtitle: Text(
              "${modified.day}/${modified.month}/${modified.year}",
              style: const TextStyle(fontSize: 12),
            ),
            trailing: widget.isPickingMode
                ? ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF00CC),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () {
                _audioPlayer.stop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateMomentScreen(selectedFile: File(file.path)),
                  ),
                );
              },
              child: const Text("Chọn"),
            )
            : PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'post') _postRecording(file);
                if (value == 'delete') _deleteRecording(file);
                if (value == 'share') _shareRecording(file.path);
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                // Menu items giữ nguyên
                const PopupMenuItem<String>(value: 'post', child: Text("Đăng tải")),
                const PopupMenuItem<String>(value: 'share', child: Text("Chia sẻ")),
                const PopupMenuItem<String>(value: 'delete', child: Text("Xóa", style: TextStyle(color: Colors.red))),
              ],
            ),
            onTap: () => _playRecording(file.path),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_none, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text("Chưa có bản thu âm nào trong máy", style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }
}