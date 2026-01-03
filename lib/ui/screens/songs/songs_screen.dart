import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../models/song_model.dart';
import '../../../providers/songs_provider.dart';
import '../../widgets/song_card.dart';

class SongsScreen extends StatefulWidget {
  final Function(SongModel) onSongClick;

  const SongsScreen({Key? key, required this.onSongClick}) : super(key: key);

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> with AutomaticKeepAliveClientMixin {

  @override
  void initState() {
    super.initState();
    final provider = context.read<SongsProvider>();
    if (provider.data == null) {
      Future.microtask(() => provider.fetchSongsData());
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            "Kho nhạc",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search, color: Colors.black),
              onPressed: () {
                // Xử lý tìm kiếm
              },
            ),
          ],
          bottom: const TabBar(
            labelColor: Color(0xFFFF00CC),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFFFF00CC),
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            tabs: [
              Tab(text: "Gợi ý"),
              Tab(text: "Thịnh hành"),
              Tab(text: "Mới nhất"),
            ],
          ),
        ),

        body: Consumer<SongsProvider>(
          builder: (context, provider, child) {
            // 1. Loading
            if (provider.isLoading) {
              return const _SongsSkeletonLoading();
            }

            // 2. Error
            if (provider.errorMessage != null) {
              return _buildErrorView(provider);
            }

            final data = provider.data;
            if (data == null) return const SizedBox();

            // 3. TabBarView
            return TabBarView(
              children: [
                _SongTabContent(
                  listKey: "recommended_list",
                  songs: data.recommended,
                  onRefresh: provider.fetchSongsData,
                  onSongTap: (song) {
                    provider.onSongSelected(song.id);
                    widget.onSongClick(song);
                  },
                ),

                _SongTabContent(
                  listKey: "popular_list",
                  songs: data.popular,
                  onRefresh: provider.fetchSongsData,
                  onSongTap: (song) {
                    provider.onSongSelected(song.id);
                    widget.onSongClick(song);
                  },
                ),

                _SongTabContent(
                  listKey: "newest_list",
                  songs: data.newest,
                  onRefresh: provider.fetchSongsData,
                  onSongTap: (song) {
                    provider.onSongSelected(song.id);
                    widget.onSongClick(song);
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildErrorView(SongsProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(provider.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => provider.fetchSongsData(),
            icon: const Icon(Icons.refresh),
            label: const Text("Thử lại"),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF00CC)),
          )
        ],
      ),
    );
  }
}

// ==========================================
// WIDGET HIỂN THỊ DANH SÁCH DỌC (Cho từng Tab)
// ==========================================
class _SongTabContent extends StatelessWidget {
  final List<SongModel> songs;
  final Future<void> Function() onRefresh;
  final Function(SongModel) onSongTap;
  final String listKey;

  const _SongTabContent({
    Key? key,
    required this.songs,
    required this.onRefresh,
    required this.onSongTap,
    this.listKey = "default_list",
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 100),
            Center(child: Text("Chưa có dữ liệu", style: TextStyle(color: Colors.grey))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFFF00CC),
      onRefresh: onRefresh,
      child: ListView.builder(
        key: PageStorageKey(listKey),
        padding: const EdgeInsets.symmetric(vertical: 12),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return Consumer<SongsProvider>(
            builder: (context, provider, child) {
              final isLiked = provider.isSongLiked(song.id);
              return SongCard(
                song: song,
                isLiked: isLiked,
                onLike: () {
                  provider.toggleLike(song.id);
                },
                onTap: () => onSongTap(song),
              );
            },
          );
        },
      ),
    );
  }
}

// ==========================================
// SKELETON LOADING
// ==========================================
class _SongsSkeletonLoading extends StatelessWidget {
  const _SongsSkeletonLoading({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        itemCount: 6, // Giả lập 6 item
        itemBuilder: (context, index) => const _SkeletonCardItem(),
      ),
    );
  }
}

class _SkeletonCardItem extends StatelessWidget {
  const _SkeletonCardItem({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Avatar giả
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 12),
          // Info giả
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 120, height: 16, color: Colors.white),
                const SizedBox(height: 8),
                Container(width: 80, height: 12, color: Colors.white),
                const SizedBox(height: 8),
                Container(width: 60, height: 10, color: Colors.white),
              ],
            ),
          ),
          // Nút giả
          Column(
            children: [
              Container(width: 20, height: 20, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
              const SizedBox(height: 10),
              Container(width: 40, height: 20, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
            ],
          )
        ],
      ),
    );
  }
}