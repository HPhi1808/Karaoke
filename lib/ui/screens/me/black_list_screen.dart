import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/user_model.dart';
import '../../../services/user_service.dart';

class BlackListScreen extends StatefulWidget {
  const BlackListScreen({super.key});

  @override
  State<BlackListScreen> createState() => _BlackListScreenState();
}

class _BlackListScreenState extends State<BlackListScreen> {
  final _supabase = Supabase.instance.client;

  List<UserModel> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBlockedUsers();
  }

  // --- 1. TẢI DANH SÁCH CHẶN ---
  Future<void> _fetchBlockedUsers() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      final users = await UserService.instance.fetchBlockedUsers(currentUserId);

      if (mounted) {
        setState(() {
          _blockedUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải blacklist: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 2. XỬ LÝ BỎ CHẶN ---
  Future<void> _handleUnblock(UserModel user) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Bỏ chặn người dùng?"),
        content: Text("Bạn sẽ có thể nhận tin nhắn từ ${user.fullName} và họ có thể tìm thấy bạn."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Huỷ"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Bỏ chặn", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await UserService.instance.unblockUser(currentUserId, user.id);

      setState(() {
        _blockedUsers.removeWhere((element) => element.id == user.id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Đã bỏ chặn ${user.fullName}")),
        );
      }

    } catch (e) {
      debugPrint("Lỗi bỏ chặn: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Có lỗi xảy ra, vui lòng thử lại!")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Danh sách chặn", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blockedUsers.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: _blockedUsers.length,
        itemBuilder: (context, index) {
          final user = _blockedUsers[index];
          return _buildBlockedUserItem(user);
        },
      ),
    );
  }

  Widget _buildBlockedUserItem(UserModel user) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Colors.grey[300],
          backgroundImage: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
              ? NetworkImage(user.avatarUrl!)
              : null,
          child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
              ? Text(user.fullName?[0].toUpperCase() ?? "?", style: const TextStyle(color: Colors.black54))
              : null,
        ),
        title: Text(
          user.fullName ?? "Người dùng",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text("@${user.username ?? '...'}", style: const TextStyle(fontSize: 13)),
        trailing: SizedBox(
          height: 36,
          child: OutlinedButton(
            onPressed: () => _handleUnblock(user),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.grey),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text("Bỏ chặn", style: TextStyle(color: Colors.black87, fontSize: 13)),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            "Danh sách chặn trống",
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );
  }
}