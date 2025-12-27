import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../models/song_model.dart';
import '../../providers/home_provider.dart';

class HomeScreen extends StatefulWidget {
  final Function(SongModel) onSongClick;

  const HomeScreen({Key? key, required this.onSongClick}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  late HomeProvider _homeProvider;

  // Biến static để lưu trạng thái khi chuyển tab
  static HomeProvider? _cachedProvider;
  static double _cachedScrollPosition = 0.0; // Lưu vị trí cuộn

  // Khai báo ScrollController
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();

    // 1. Khôi phục Provider
    if (_cachedProvider == null) {
      _cachedProvider = HomeProvider();
    }
    _homeProvider = _cachedProvider!;

    // 2. Khôi phục vị trí cuộn
    _scrollController = ScrollController(initialScrollOffset: _cachedScrollPosition);

    // 3. Lắng nghe cuộn để lưu vị trí mới
    _scrollController.addListener(() {
      _cachedScrollPosition = _scrollController.offset;
    });
  }

  @override
  void dispose() {
    // Giải phóng controller để tránh rò rỉ bộ nhớ
    _scrollController.dispose();
    super.dispose();
  }

  // Giữ cho trang không bị hủy khi chuyển tab
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Bắt buộc khi dùng AutomaticKeepAliveClientMixin

    return ChangeNotifierProvider.value(
      value: _homeProvider,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text("Trang chủ",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
          actions: [
            IconButton(
              icon: const Icon(Icons.search, color: Colors.black),
              onPressed: () {},
            ),
          ],
        ),
        body: Consumer<HomeProvider>(
          builder: (context, provider, child) {
            // Skeleton Loading
            if (provider.isLoading) {
              return const _HomeSkeletonLoading();
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
                      onPressed: () => provider.fetchHomeData(),
                      icon: const Icon(Icons.refresh),
                      label: const Text("Thử lại"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF00CC)),
                    )
                  ],
                ),
              );
            }

            final data = provider.homeData;
            if (data == null) return const SizedBox();

            // Main Content
            return RefreshIndicator(
              color: const Color(0xFFFF00CC),
              onRefresh: () async {
                await provider.fetchHomeData();
                // Nếu muốn refresh xong cuộn lên đầu thì bỏ comment dòng dưới:
                // _cachedScrollPosition = 0.0;
                // if (_scrollController.hasClients) _scrollController.jumpTo(0);
              },
              child: SingleChildScrollView(
                controller: _scrollController, // Gán controller vào đây
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

// ... (Giữ nguyên các Widget con bên dưới: _HomeSkeletonLoading, _SectionTitle, v.v...)
// ==========================================
// 3. WIDGET SKELETON LOADING
// ==========================================
class _HomeSkeletonLoading extends StatelessWidget {
  const _HomeSkeletonLoading({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Shimmer.fromColors tạo hiệu ứng lấp lánh
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!, // Màu nền xám nhạt
      highlightColor: Colors.grey[100]!, // Màu sáng chạy qua
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Giả lập 3 section giống trang thật
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
        // Title giả
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
        // List ngang giả
        SizedBox(
          height: 240,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: 3, // Hiển thị 3 card giả
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) => const _SkeletonCardItem(),
          ),
        ),
      ],
    );
  }
}

// Card giả lập cấu trúc của _SongCardItem
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
          // Ảnh giả
          Container(
            height: 120,
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white, // Shimmer sẽ đổi màu này
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tên bài hát giả
                Container(
                  width: 100,
                  height: 14,
                  color: Colors.white,
                ),
                const SizedBox(height: 8),
                // Tên ca sĩ giả
                Container(
                  width: 80,
                  height: 12,
                  color: Colors.white,
                ),
                const SizedBox(height: 12),
                // Nút bấm giả
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
          return _SongCardItem(
            song: songs[index],
            onTap: () => onSongTap(songs[index]),
          );
        },
      ),
    );
  }
}

class _SongCardItem extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;

  const _SongCardItem({
    required this.song,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 120,
                width: double.infinity,
                child: Image.network(
                  song.imageUrl ?? "https://via.placeholder.com/150",
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.music_note, color: Colors.grey),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      song.artistName,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: ElevatedButton(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF00CC),
                          padding: EdgeInsets.zero,
                          shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.mic, size: 16, color: Colors.white),
                            SizedBox(width: 4),
                            Text("Hát ngay",
                                style: TextStyle(
                                    fontSize: 12, color: Colors.white)),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}