import 'package:flutter/material.dart';

class MomentsScreen extends StatefulWidget {
  const MomentsScreen({Key? key}) : super(key: key);

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  final List<Map<String, dynamic>> _posts = [];
  final TextEditingController _contentController = TextEditingController();

  final List<Map<String, dynamic>> _reactions = [
    {'icon': '👍', 'label': 'Thích', 'color': Colors.blue},
    {'icon': '❤️', 'label': 'Yêu', 'color': Colors.red},
    {'icon': '😆', 'label': 'Haha', 'color': Colors.orange},
    {'icon': '😮', 'label': 'Wow', 'color': Colors.amber},
    {'icon': '😢', 'label': 'Buồn', 'color': Colors.blueGrey},
    {'icon': '😡', 'label': 'Giận', 'color': Colors.deepOrange},
  ];

  // Hàm thêm bài viết
  void _addNewPost(String content, String type) {
    if (content.trim().isEmpty) return;
    setState(() {
      _posts.insert(0, {
        'id': DateTime.now().toString(),
        'user': 'Người dùng',
        'content': content,
        'type': type,
        'selectedReaction': null,
        'comments': <String>[],
      });
    });
    _contentController.clear();
  }

  // Hàm xử lý Thả/Hủy cảm xúc
  void _handleReaction(int postIndex, Map<String, dynamic>? reaction) {
    setState(() {
      var post = _posts[postIndex];
      // Nếu nhấn vào cái đã có -> Hủy (null)
      if (post['selectedReaction'] != null &&
          post['selectedReaction']['label'] == reaction?['label']) {
        post['selectedReaction'] = null;
      } else {
        // Thả mới hoặc đổi loại cảm xúc
        post['selectedReaction'] = reaction;
      }
    });
  }

  // --- SỬA LỖI BÀN PHÍM VÀ DẤU TIẾNG VIỆT KHI ĐĂNG BÀI ---
  void _showCreatePostDialog() {
    String type = 'text';
    final FocusNode postFocusNode = FocusNode();

    showDialog(
      context: context,
      builder: (context) {
        // Kích hoạt bàn phím ngay sau khi khung hình đầu tiên được dựng
        WidgetsBinding.instance.addPostFrameCallback((_) {
          postFocusNode.requestFocus();
        });

        return StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text("Đăng khoảnh khắc"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _contentController,
                  focusNode: postFocusNode,
                  keyboardType: TextInputType.text, // Đảm bảo hỗ trợ gõ dấu
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: "Bạn đang nghĩ gì?",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(label: const Text("Ảnh"), selected: type == 'image', onSelected: (v) => setModalState(() => type = 'image')),
                    const SizedBox(width: 8),
                    ChoiceChip(label: const Text("Nhạc"), selected: type == 'audio', onSelected: (v) => setModalState(() => type = 'audio')),
                  ],
                )
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
              ElevatedButton(
                onPressed: () {
                  _addNewPost(_contentController.text, type);
                  Navigator.pop(context);
                },
                child: const Text("Đăng bài"),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- SỬA LỖI BÀN PHÍM KHI BÌNH LUẬN ---
  void _showCommentDialog(int postIndex) {
    TextEditingController commentController = TextEditingController();
    final FocusNode commentFocusNode = FocusNode();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          commentFocusNode.requestFocus();
        });

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20, left: 15, right: 15,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Bình luận", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 10),
              TextField(
                controller: commentController,
                focusNode: commentFocusNode,
                keyboardType: TextInputType.text, // Hỗ trợ gõ dấu
                decoration: const InputDecoration(
                  hintText: "Viết bình luận...",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (commentController.text.isNotEmpty) {
                      setState(() {
                        _posts[postIndex]['comments'].add(commentController.text);
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("Gửi bình luận"),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showReactionMenu(BuildContext context, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 40),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(40),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)]
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: _reactions.map((r) => GestureDetector(
            onTap: () {
              _handleReaction(index, r);
              Navigator.pop(context);
            },
            child: Text(r['icon'], style: const TextStyle(fontSize: 35)),
          )).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("Khoảnh khắc", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: _posts.isEmpty
          ? const Center(child: Text("Bấm nút + để chia sẻ khoảnh khắc nhé!"))
          : ListView.builder(
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
          final currentReact = post['selectedReaction'];

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(post['user'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => setState(() => _posts.removeAt(index)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(post['content'], style: const TextStyle(fontSize: 16)),
                ),

                // Phần hiển thị nội dung đính kèm giả lập
                if (post['type'] == 'image')
                  Container(height: 180, width: double.infinity, margin: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.image, size: 50, color: Colors.blue)),
                if (post['type'] == 'audio')
                  Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(10)), child: const Row(children: [Icon(Icons.mic, color: Colors.orange), SizedBox(width: 10), Text("Đoạn ghi âm 01.mp3")])),

                const Divider(height: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // NÚT CẢM XÚC
                    GestureDetector(
                      onLongPress: () => _showReactionMenu(context, index),
                      child: TextButton.icon(
                        onPressed: () => _handleReaction(index, _reactions[0]),
                        icon: Text(currentReact != null ? currentReact['icon'] : "👍", style: const TextStyle(fontSize: 18)),
                        label: Text(
                          currentReact != null ? currentReact['label'] : "Thích",
                          style: TextStyle(color: currentReact != null ? currentReact['color'] : Colors.grey),
                        ),
                      ),
                    ),
                    // NÚT BÌNH LUẬN
                    TextButton.icon(
                      onPressed: () => _showCommentDialog(index),
                      icon: const Icon(Icons.comment_outlined, color: Colors.grey, size: 20),
                      label: Text("${post['comments'].length} Bình luận", style: const TextStyle(color: Colors.grey)),
                    ),
                    // NÚT CHIA SẺ
                    IconButton(
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã chia sẻ!"))),
                      icon: const Icon(Icons.share_outlined, color: Colors.grey, size: 20),
                    ),
                  ],
                ),
                // HIỂN THỊ BÌNH LUẬN
                if (post['comments'].isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    color: Colors.grey[50],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: (post['comments'] as List).map((c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text("• $c", style: const TextStyle(color: Colors.black87)),
                      )).toList(),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreatePostDialog,
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}