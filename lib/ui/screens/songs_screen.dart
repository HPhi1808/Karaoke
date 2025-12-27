import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../models/song_model.dart';
import '../../providers/songs_provider.dart';
import '../widgets/song_card.dart';

class SongsScreen extends StatefulWidget {
  final Function(SongModel) onSongClick;

  const SongsScreen({Key? key, required this.onSongClick}) : super(key: key);

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> with AutomaticKeepAliveClientMixin {
  // [SỬA] Dùng SongsProvider thay vì HomeProvider
  late SongsProvider _songsProvider;

  // [SỬA] Biến static cache theo kiểu SongsProvider
  static SongsProvider? _cachedProvider;
  static double _cachedScrollPosition = 0.0;

  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();

    // 1. Khôi phục Provider
    if (_cachedProvider == null) {
      _cachedProvider = SongsProvider();
    }
    _songsProvider = _cachedProvider!;

    // 2. Khôi phục vị trí cuộn
    _scrollController = ScrollController(initialScrollOffset: _cachedScrollPosition);

    // 3. Lắng nghe cuộn để lưu vị trí mới
    _scrollController.addListener(() {
      _cachedScrollPosition = _scrollController.offset;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ChangeNotifierProvider.value(
      value: _songsProvider,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          // Đổi tiêu đề
          title: const Text("Kho nhạc",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
          actions: [
            IconButton(
              icon: const Icon(Icons.search, color: Colors.black),
              onPressed: () {
                // Xử lý tìm kiếm sau
              },
            ),
          ],
        ),
        // Consumer lắng nghe SongsProvider
        body: Consumer<SongsProvider>(
          builder: (context, provider, child) {
            // Skeleton Loading
            if (provider.isLoading) {
              return const _SongsSkeletonLoading();
            }

            // Error View
            if (provider.errorMessage != null) {
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
                      // [SỬA] Gọi hàm fetchSongsData
                      onPressed: () => provider.fetchSongsData(),
                      icon: const Icon(Icons.refresh),
                      label: const Text("Thử lại"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF00CC)),
                    )
                  ],
                ),
              );
            }

            // Lấy dữ liệu từ getter
            final data = provider.data;
            if (data == null) return const SizedBox();

            // Main Content
            return RefreshIndicator(
              color: const Color(0xFFFF00CC),
              //Gọi hàm fetchSongsData khi kéo xuống
              onRefresh: () async {
                await provider.fetchSongsData();
              },
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle(title: "🔥 Thịnh hành nhất"),
                    _SongHorizontalList(
                      songs: data.popular,
                      onSongTap: (song) {
                        provider.onSongSelected(song.id);
                        widget.onSongClick(song);
                      },
                    ),
                    const _SectionTitle(title: "✨ Bài hát mới"),
                    _SongHorizontalList(
                      songs: data.newest,
                      onSongTap: (song) {
                        provider.onSongSelected(song.id);
                        widget.onSongClick(song);
                      },
                    ),
                    const _SectionTitle(title: "🎧 Gợi ý cho bạn"),
                    _SongHorizontalList(
                      songs: data.recommended,
                      onSongTap: (song) {
                        provider.onSongSelected(song.id);
                        widget.onSongClick(song);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ==========================================
// 3. WIDGET SKELETON LOADING
// ==========================================
class _SongsSkeletonLoading extends StatelessWidget {
  const _SongsSkeletonLoading({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSkeletonSection(),
            _buildSkeletonSection(),
            _buildSkeletonSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 24, bottom: 8),
          child: Container(
            width: 150,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        SizedBox(
          height: 240,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) => const _SkeletonCardItem(),
          ),
        ),
      ],
    );
  }
}

class _SkeletonCardItem extends StatelessWidget {
  const _SkeletonCardItem({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 120,
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 100, height: 14, color: Colors.white),
                const SizedBox(height: 8),
                Container(width: 80, height: 12, color: Colors.white),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// CÁC WIDGET PHỤ
// ==========================================

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 24, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
      ),
    );
  }
}

class _SongHorizontalList extends StatelessWidget {
  final List<SongModel> songs;
  final Function(SongModel) onSongTap;

  const _SongHorizontalList({
    required this.songs,
    required this.onSongTap,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text("Chưa có dữ liệu", style: TextStyle(color: Colors.grey)),
      );
    }

    return SizedBox(
      height: 240,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: songs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return SongCard(
            song: songs[index],
            onTap: () => onSongTap(songs[index]),
          );
        },
      ),
    );
  }
}