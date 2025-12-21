import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// [QUAN TRỌNG] Import đúng SongModel
import '../../models/song_model.dart';
import '../../providers/home_provider.dart';

class HomeScreen extends StatelessWidget {
  final Function(int) onSongClick;

  const HomeScreen({
    Key? key,
    required this.onSongClick,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeProvider(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            "Karaoke Zone",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search, color: Colors.black),
              onPressed: () {},
            ),
          ],
        ),
        body: Consumer<HomeProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.errorMessage != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(provider.errorMessage!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => provider.fetchHomeData(),
                      icon: const Icon(Icons.refresh),
                      label: const Text("Thử lại"),
                    )
                  ],
                ),
              );
            }

            final data = provider.homeData;
            if (data != null) {
              return SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(title: "🔥 Thịnh hành nhất"),
                    _SongHorizontalList(
                      songs: data.popular,
                      onSongTap: (song) {
                        provider.onSongSelected(song.id);
                        onSongClick(song.id);
                      },
                    ),

                    _SectionTitle(title: "✨ Bài hát mới"),
                    _SongHorizontalList(
                      songs: data.newest,
                      onSongTap: (song) {
                        provider.onSongSelected(song.id);
                        onSongClick(song.id);
                      },
                    ),

                    _SectionTitle(title: "🎧 Gợi ý cho bạn"),
                    _SongHorizontalList(
                      songs: data.recommended,
                      onSongTap: (song) {
                        provider.onSongSelected(song.id);
                        onSongClick(song.id);
                      },
                    ),
                  ],
                ),
              );
            }

            return const SizedBox();
          },
        ),
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
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
      ),
    );
  }
}

class _SongHorizontalList extends StatelessWidget {
  // [SỬA LỖI] Dùng SongModel thay vì Song
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
  // [SỬA LỖI] Dùng SongModel thay vì Song
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
                height: 140,
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.mic, size: 16, color: Colors.white),
                            SizedBox(width: 4),
                            Text("Hát ngay", style: TextStyle(fontSize: 12, color: Colors.white)),
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