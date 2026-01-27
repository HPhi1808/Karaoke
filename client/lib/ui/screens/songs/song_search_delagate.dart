import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/song_model.dart';
import '../../../providers/songs_provider.dart';
import '../../../services/song_service.dart';
import '../../widgets/song_item.dart';

class SongSearchDelegate extends SearchDelegate {
  final Function(SongModel) onSongClick;

  SongSearchDelegate({required this.onSongClick});

  // 1. Nút "X" để xóa text tìm kiếm
  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
            showSuggestions(context); // Hiển thị lại gợi ý khi xóa
          },
        ),
    ];
  }

  // 2. Nút mũi tên quay lại
  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  // 3. Hiển thị kết quả tìm kiếm (Khi nhấn Enter hoặc khi đang gõ)
  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  // 4. Hiển thị gợi ý khi đang gõ (Live Search)
  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 60, color: Colors.grey),
            SizedBox(height: 10),
            Text("Nhập tên bài hát...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    // Gọi hàm hiển thị kết quả luôn để có tính năng tìm kiếm realtime
    return _buildSearchResults(context);
  }

  // Hàm chung để gọi API và hiển thị list
  Widget _buildSearchResults(BuildContext context) {
    if (query.trim().length < 2) {
      return const Center(child: Text("Nhập ít nhất 2 ký tự"));
    }

    return FutureBuilder<List<SongModel>>(
      future: SongService.instance.searchSongs(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFF00CC)));
        }

        if (snapshot.hasError) {
          return Center(child: Text("Lỗi: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
        }

        final results = snapshot.data;

        if (results == null || results.isEmpty) {
          return Center(child: Text("Không tìm thấy kết quả cho '$query'"));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final song = results[index];

            return Consumer<SongsProvider>(
              builder: (context, provider, child) {
                final isLiked = provider.isSongLiked(song.id);
                return SongItem(
                  song: song,
                  isLiked: isLiked,
                  onLike: () {
                    provider.toggleLike(song.id);
                  },
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    close(context, null);
                    onSongClick(song);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // Tùy chỉnh text "Tìm kiếm..."
  @override
  String get searchFieldLabel => 'Tìm bài hát...';

  @override
  TextStyle? get searchFieldStyle => const TextStyle(fontSize: 16);
}