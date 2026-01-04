import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class MeRecordingsScreen extends StatefulWidget {
  const MeRecordingsScreen({super.key});

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
          // Khi phát xong thì reset trạng thái
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
    if (await Permission.storage.request().isDenied &&
        await Permission.manageExternalStorage.request().isDenied) {
      // Handle permission denied
    }

    final Directory dir = Directory('/storage/emulated/0/Download/KaraokeApp');

    if (await dir.exists()) {
      setState(() {
        _files = dir.listSync()
            .where((item) => item.path.endsWith('.wav'))
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
  }

  Future<void> _playRecording(String path) async {
    try {
      // Nếu đang chọn đúng bài này
      if (_currentPlayingPath == path) {
        if (_isPlaying) {
          await _audioPlayer.pause();
        } else {
          await _audioPlayer.play();
        }
      } else {
        // Nếu chọn bài mới
        await _audioPlayer.stop();
        await _audioPlayer.setFilePath(path);

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
    await Share.shareXFiles([XFile(path)], text: 'Nghe bản thu âm karaoke của tôi này!');
  }

  Future<void> _postRecording(FileSystemEntity file) async {
    final shouldPost = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Đăng tải bản thu"),
        content: Text("Bạn có muốn đăng bản thu '${file.path.split('/').last.replaceAll('.wav', '')}' lên cộng đồng không?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF00CC)),
            child: const Text("Đăng tải", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (shouldPost == true) {
      // TODO

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tính năng đang phát triển (Sử dụng Dio để upload)")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Bản thu âm của tôi", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final file = _files[index];

          final String fileName = file.path.split('/').last.replaceAll('.wav', '');

          final DateTime modified = file.statSync().modified;

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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isPlayingThis ? const Color(0xFFFF00CC) : Colors.black,
                ),
              ),
              subtitle: Text(
                "${modified.day}/${modified.month}/${modified.year} • ${_formatSize(file.statSync().size)}",
                style: const TextStyle(fontSize: 12),
              ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'post') _postRecording(file);
                    if (value == 'delete') _deleteRecording(file);
                    if (value == 'share') _shareRecording(file.path);
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'post',
                      child: Row(
                        children: [
                          Icon(Icons.cloud_upload, color: Colors.blue, size: 18),
                          SizedBox(width: 8),
                          Text("Đăng tải", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    // Nút Chia sẻ
                    const PopupMenuItem<String>(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share, size: 18),
                          SizedBox(width: 8),
                          Text("Chia sẻ"),
                        ],
                      ),
                    ),
                    // Nút Xóa
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Text("Xóa", style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              onTap: () => _playRecording(file.path),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_none, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text("Chưa có bản thu âm nào", style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }
}