import 'package:flutter/material.dart';
import '../../models/song_model.dart';

class SongItem extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;
  final VoidCallback? onLike;
  final bool isLiked;

  const SongItem({
    super.key,
    required this.song,
    required this.onTap,
    this.onLike,
    this.isLiked = false,
  });

  String _formatViewCount(int? views) {
    if (views == null || views < 0) return "0";
    if (views >= 1000000) {
      return '${(views / 1000000).toStringAsFixed(1)}M';
    } else if (views >= 1000) {
      return '${(views / 1000).toStringAsFixed(1)}k';
    }
    return views.toString();
  }

  bool _isValidImageUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.endsWith('.mp3') || lowerUrl.endsWith('.wav') || lowerUrl.endsWith('.m4a')) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = song.imageUrl;
    final bool hasValidImage = _isValidImageUrl(imageUrl);

    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: [
                // --- 1. AVATAR ---
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 70,
                    height: 70,
                    child: hasValidImage
                        ? Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      cacheWidth: 200,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildPlaceholder();
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey[100],
                          child: const Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2)
                              )
                          ),
                        );
                      },
                    )
                        : _buildPlaceholder(),
                  ),
                ),

                const SizedBox(width: 12),

                // --- 2. THÔNG TIN BÀI HÁT ---
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        song.title ?? "Không xác định",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),

                      Text(
                        song.artistName ?? "Nghệ sĩ chưa cập nhật",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.mic, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              "${_formatViewCount(song.viewCount)} lượt hát",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // --- 3. NÚT TIM ---
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onLike,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.red : Colors.grey[400],
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.music_note, color: Colors.grey, size: 30),
      ),
    );
  }
}