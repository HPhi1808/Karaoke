import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';
import '../screens/mailbox/chat_screen.dart';

class FriendsSidebar extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;

  const FriendsSidebar({
    super.key,
    required this.isOpen,
    required this.onClose,
  });

  @override
  State<FriendsSidebar> createState() => _FriendsSidebarState();
}

class _FriendsSidebarState extends State<FriendsSidebar> {
  final TextEditingController _searchController = TextEditingController();
  final _supabase = Supabase.instance.client;
  List<UserModel> _friends = [];
  List<UserModel> _filteredFriends = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFriends();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getStatusText(String? lastActiveAtStr) {
    if (lastActiveAtStr == null) return "Ngoại tuyến";

    final lastActive = DateTime.parse(lastActiveAtStr).toLocal();
    final now = DateTime.now();
    final diff = now.difference(lastActive);

    if (diff.inMinutes <= 5) {
      return "Đang hoạt động";
    }

    if (diff.inDays > 0) {
      return "Hoạt động ${lastActive.day}/${lastActive.month}";
    }

    if (diff.inHours > 0) {
      return "Hoạt động ${diff.inHours} giờ trước";
    }
    
    if (diff.inMinutes > 0) {
      return "Hoạt động ${diff.inMinutes} phút trước";
    }
    
    return "Vừa xong";
  }

  Color _getStatusColor(String? lastActiveAtStr) {
    if (lastActiveAtStr == null) return Colors.grey;
    final lastActive = DateTime.parse(lastActiveAtStr).toLocal();
    final diff = DateTime.now().difference(lastActive);
    return diff.inMinutes <= 5 ? Colors.green : Colors.grey;
  }

  Future<void> _fetchFriends() async {
    final friends = await UserService.instance.getFriendsList();
    if (mounted) {
      setState(() {
        _friends = friends;
        _filteredFriends = friends;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredFriends = _friends;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredFriends = _friends.where((friend) {
          final fullName = (friend.fullName ?? "").toLowerCase();
          final username = (friend.username ?? "").toLowerCase();
          return fullName.contains(lowerQuery) || username.contains(lowerQuery);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width * 0.7;
    
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      right: widget.isOpen ? 0 : -width,
      top: 0,
      bottom: 0,
      width: width,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(-2, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.only(top: 40, bottom: 10, left: 16, right: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Bạn bè",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            
            // Search
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: "Tìm bạn bè...",
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // List bạn bè
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _friends.isEmpty
                      ? _buildEmptyState() 
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: _filteredFriends.length,
                          itemBuilder: (context, index) {
                            return _buildFriendItem(_filteredFriends[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendItem(UserModel friend) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase.from('users').stream(primaryKey: ['id']).eq('id', friend.id),
      builder: (context, snapshot) {
        String? lastActiveAt = friend.lastActiveAt;
        String? avatarUrl = friend.avatarUrl;
        String fullName = friend.fullName ?? "Người dùng";

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final data = snapshot.data!.first;
          lastActiveAt = data['last_active_at'];
          avatarUrl = data['avatar_url'];
          fullName = data['full_name'] ?? fullName;
        }

        final statusText = _getStatusText(lastActiveAt);
        final statusColor = _getStatusColor(lastActiveAt);

        return ListTile(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatScreen(targetUser: friend)),
            );
          },
          leading: Stack(
            children: [
              CircleAvatar(
                backgroundColor: Colors.grey[200],
                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? NetworkImage(avatarUrl)
                    : null,
                child: (avatarUrl == null || avatarUrl.isEmpty)
                    ? Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : "?")
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          title: Text(
            fullName,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          subtitle: Text(
            statusText, 
            style: TextStyle(
              fontSize: 12, 
              color: statusColor == Colors.green ? Colors.green : Colors.grey
            )
          ),
          trailing: const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFFFF00CC)),
        );
      }
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 40, color: Colors.grey[300]),
          const SizedBox(height: 10),
          const Text("Chưa có bạn bè nào", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}