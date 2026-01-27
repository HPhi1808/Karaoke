import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/song_model.dart';
import '../../../services/song_service.dart';
import '../../../providers/songs_provider.dart';
import '../../widgets/song_item.dart';
import '../songs/song_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<SongModel> _fetchedSongs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final songs = await SongService.instance.getFavoriteSongs();
      if (mounted) {
        setState(() {
          _fetchedSongs = songs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi load favorites: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openSongDetail(BuildContext context, int songId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SongDetailScreen(
          songId: songId,
          onBack: () => Navigator.pop(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
            "Yêu thích",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
      ),

      body: Consumer<SongsProvider>(
        builder: (context, provider, child) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFF00CC)));
          }
          final displayList = _fetchedSongs.where((song) {
            return provider.isSongLiked(song.id);
          }).toList();

          if (displayList.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: displayList.length,
            itemBuilder: (context, index) {
              final song = displayList[index];
              return SongItem(
                song: song,
                isLiked: true,
                onLike: () {
                  provider.toggleLike(song.id);

                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Đã bỏ khỏi danh sách yêu thích 💔"),
                        duration: Duration(seconds: 1),
                      )
                  );
                },
                onTap: () => _openSongDetail(context, song.id),
              );
            },
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
          Icon(Icons.favorite_border, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text("Chưa có bài hát yêu thích nào", style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }
}