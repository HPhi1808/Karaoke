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

    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _currentPlayingPath = null;
            _isPlaying = false;
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
    if (await Permission.storage.request().isDenied && await Permission.manageExternalStorage.request().isDenied) {
      // Xử lý khi không có quyền (tùy chọn)
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
      if (_currentPlayingPath == path && _isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.setFilePath(path);
        await _audioPlayer.play();
        setState(() => _currentPlayingPath = path);
      }
    } catch (e) {
      debugPrint("Lỗi phát file: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Không thể phát file này")));
    }
  }

  Future<void> _deleteRecording(FileSystemEntity file) async {
    try {
      if (_currentPlayingPath == file.path) {
        await _audioPlayer.stop();
        _currentPlayingPath = null;
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
          final String fileName = file.path.split('/').last;
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
              trailing: PopupMenuButton(
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share, size: 18), SizedBox(width: 8), Text("Chia sẻ")])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8), Text("Xóa", style: TextStyle(color: Colors.red))])),
                ],
                onSelected: (value) {
                  if (value == 'delete') _deleteRecording(file);
                  if (value == 'share') _shareRecording(file.path);
                },
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