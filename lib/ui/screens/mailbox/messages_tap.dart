import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../../models/user_model.dart';
import '../me/user_profile_screen.dart';
import 'chat_screen.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({Key? key}) : super(key: key);

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  // Dữ liệu
  List<UserModel> _allFriends = []; // Danh sách gốc (tất cả bạn bè)
  List<UserModel> _localSearchResults = []; // Kết quả tìm bạn bè (đã lọc)
  List<UserModel> _globalSearchResults = []; // Kết quả tìm người lạ

  // Trạng thái UI
  bool _isLoadingFriends = true; 
  bool _isSearching = false; 
  bool _isGlobalLoading = false; 
  bool _showGlobalResults = false; 

  @override
  void initState() {
    super.initState();
    _fetchFriends();
  }

  // 1. TẢI DANH SÁCH BẠN BÈ
  Future<void> _fetchFriends() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await _supabase
          .from('friends_view')
          .select()
          .eq('user_id', userId);

      final List<UserModel> loadedFriends = (response as List)
          .map((data) => UserModel.fromFriendView(data))
          .toList();

      if (mounted) {
        setState(() {
          _allFriends = loadedFriends;
          _localSearchResults = loadedFriends;
          _isLoadingFriends = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải bạn bè: $e");
      if (mounted) setState(() => _isLoadingFriends = false);
    }
  }

  // 2. XỬ LÝ KHI GÕ TEXT (Lọc Local) - ĐÃ THÊM BỘ LỌC ROLE
  void _onSearchChanged(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
      _showGlobalResults = false;
      _globalSearchResults = [];

      if (query.isEmpty) {
        _localSearchResults = _allFriends;
      } else {
        final lowerQuery = query.toLowerCase();
        _localSearchResults = _allFriends.where((user) {
          // CHỈ HIỆN USER (Bỏ qua admin, guess)
          final isUser = user.role == 'user';
          final matchesName = (user.fullName ?? "").toLowerCase().contains(lowerQuery) ||
                              (user.username ?? "").toLowerCase().contains(lowerQuery);
          return isUser && matchesName;
        }).toList();
      }
    });
  }

  // 3. XỬ LÝ KHI BẤM "TÌM NGƯỜI LẠ" (Global) - ĐÃ THÊM BỘ LỌC ROLE
  Future<void> _searchGlobal() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isGlobalLoading = true;
      _showGlobalResults = true;
    });

    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      final response = await _supabase
          .from('users')
          .select()
          .or('username.ilike.%$query%, email.eq.$query, full_name.ilike.%$query%')
          .eq('role', 'user') // CHỈ TÌM NHỮNG NGƯỜI CÓ ROLE LÀ USER
          .neq('id', currentUserId!)
          .limit(10);

      final List<UserModel> results = (response as List)
          .map((data) => UserModel.fromSearch(data, isFriend: false))
          .toList();

      final friendIds = _allFriends.map((e) => e.id).toSet();
      final filteredResults = results.where((u) => !friendIds.contains(u.id)).toList();

      if (mounted) {
        setState(() {
          _globalSearchResults = filteredResults;
          _isGlobalLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tìm người lạ: $e");
      if (mounted) {
        setState(() {
          _isGlobalLoading = false;
          _globalSearchResults = [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchGlobal(),
            decoration: InputDecoration(
              hintText: "Tìm bạn bè, username...",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isSearching
                  ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                  FocusScope.of(context).unfocus();
                },
              )
                  : null,
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        Expanded(
          child: _isLoadingFriends
              ? const Center(child: CircularProgressIndicator())
              : ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (!_showGlobalResults)
                ..._localSearchResults.map((user) => _buildUserItem(user)),

              if (_isSearching && !_showGlobalResults)
                InkWell(
                  onTap: _searchGlobal,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    margin: const EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey[200]!))),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
                          child: const Icon(Icons.public, color: Colors.blue, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                text: TextSpan(
                                  style: const TextStyle(color: Colors.black87, fontSize: 15),
                                  children: [
                                    const TextSpan(text: "Tìm người lạ: "),
                                    TextSpan(text: '"${_searchController.text}"', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                  ],
                                ),
                              ),
                              const Text("Tìm kiếm trên toàn hệ thống", style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      ],
                    ),
                  ),
                ),

              if (_isGlobalLoading) const Padding(padding: EdgeInsets.all(20.0), child: Center(child: CircularProgressIndicator())),

              if (_showGlobalResults) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text("Kết quả từ hệ thống", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                if (_globalSearchResults.isEmpty && !_isGlobalLoading)
                  const Padding(padding: EdgeInsets.all(20.0), child: Center(child: Text("Không tìm thấy người dùng này.", style: TextStyle(color: Colors.grey)))),
                ..._globalSearchResults.map((user) => _buildUserItem(user)),
              ]
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserItem(UserModel user) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.grey[200],
        backgroundImage: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) ? NetworkImage(user.avatarUrl!) : null,
        child: (user.avatarUrl == null || user.avatarUrl!.isEmpty) ? Text(user.fullName?[0].toUpperCase() ?? "?") : null,
      ),
      title: Text(user.fullName ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(user.isFriend ? "@${user.username} • Bạn bè" : "@${user.username} • Người lạ"),
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(targetUser: user)));
      },
    );
  }
}
