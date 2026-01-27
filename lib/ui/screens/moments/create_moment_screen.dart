import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/moment_model.dart';
import '../../../services/moment_service.dart';

class CreateMomentScreen extends StatefulWidget {
  final File? selectedFile;
  final Moment? editingMoment;

  const CreateMomentScreen({
    super.key,
    this.selectedFile,
    this.editingMoment
  });

  @override
  State<CreateMomentScreen> createState() => _CreateMomentScreenState();
}

class _CreateMomentScreenState extends State<CreateMomentScreen> {
  final TextEditingController _contentController = TextEditingController();
  String _visibility = 'public';
  bool _isUploading = false;
  final _supabase = Supabase.instance.client;

  bool get _isEditing => widget.editingMoment != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _contentController.text = widget.editingMoment!.description ?? "";
      _visibility = widget.editingMoment!.visibility ?? 'public';
    }
  }

  Future<void> _handleSubmit() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nội dung không được để trống!")));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isUploading = true);

    try {
      if (_isEditing) {
        await MomentService.instance.updateMoment(
          momentId: widget.editingMoment!.id,
          description: _contentController.text.trim(),
          visibility: _visibility,
        );
        if (mounted) _finish("Cập nhật thành công!");
      } else {
        if (widget.selectedFile == null) return;
        await MomentService.instance.createAudioMoment(
          file: widget.selectedFile!,
          description: _contentController.text.trim(),
          visibility: _visibility,
        );
        if (mounted) _finish("Đăng thành công!");
      }
    } catch (e) {
      debugPrint("Lỗi submit: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: ${e.toString()}")));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _finish(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    String fileNameDisplay = "File âm thanh";
    if (_isEditing) {
      fileNameDisplay = "Audio hiện tại (Không thể thay đổi)";
    } else if (widget.selectedFile != null) {
      fileNameDisplay = widget.selectedFile!.path.split('/').last;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? "Chỉnh sửa bài viết" : "Tạo bài viết"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isUploading ? null : _handleSubmit,
            child: _isUploading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isEditing ? "LƯU" : "ĐĂNG",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFFF00CC))),
          )
        ],
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView( // Thêm Scroll để tránh overflow khi bàn phím hiện
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: NetworkImage(_supabase.auth.currentUser?.userMetadata?['avatar_url'] ?? ''),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _supabase.auth.currentUser?.userMetadata?['full_name'] ?? "Tôi",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      // Dropdown Visibility
                      Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(5)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _visibility,
                            icon: const Icon(Icons.arrow_drop_down, size: 18),
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                            onChanged: (String? newValue) => setState(() => _visibility = newValue!),
                            items: const [
                              DropdownMenuItem(value: 'public', child: Row(children: [Icon(Icons.public, size: 14, color: Colors.grey), SizedBox(width: 5), Text("Công khai")])),
                              DropdownMenuItem(value: 'friends', child: Row(children: [Icon(Icons.people, size: 14, color: Colors.grey), SizedBox(width: 5), Text("Bạn bè")])),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 20),

              // TextField nhập nội dung
              TextField(
                controller: _contentController,
                decoration: InputDecoration(
                  hintText: _isEditing ? "Sửa mô tả của bạn..." : "Bạn đang nghĩ gì về bản thu này?",
                  border: InputBorder.none,
                  hintStyle: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
                maxLines: 5,
                style: const TextStyle(fontSize: 18),
              ),

              const SizedBox(height: 20),

              // Card hiển thị file audio
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isEditing ? Colors.grey.shade100 : const Color(0xFFF3E5F5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _isEditing ? Colors.grey.shade300 : const Color(0xFFE1BEE7)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.audio_file, color: _isEditing ? Colors.grey : const Color(0xFFFF00CC), size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_isEditing ? "Audio gốc" : "Bản ghi âm đã chọn", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(fileNameDisplay, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
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