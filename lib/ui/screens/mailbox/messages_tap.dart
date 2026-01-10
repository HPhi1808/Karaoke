import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../../models/user_model.dart';
import '../../../models/message_model.dart';
import '../../widgets/chat_item.dart';
import '../../../services/auth_service.dart';
import 'chat_screen.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _isGuest = false;

  // --- STATE: DANH SÁCH CHAT (RECENT) ---
  List<ChatPreviewModel> _recentChats = [];
  bool _isLoadingChats = true;
  bool _isLoadingMoreChats = false;
  bool _hasMoreChats = true;
  final int _chatLimit = 10;
  int _chatOffset = 0;

  // --- STATE: TÌM KIẾM (SEARCH) ---
  List<UserModel> _allFriends = [];
  List<UserModel> _localSearchResults = [];
  List<UserModel> _globalSearchResults = [];
  bool _isLoadingFriends = true;
  bool _isSearching = false;
  bool _isGlobalLoading = false;
  bool _showGlobalResults = false;

  @override
  void initState() {
    super.initState();
    _checkGuestAndLoadData();
  }

  void _checkGuestAndLoadData() {
    _isGuest = AuthService.instance.isGuest;

    if (!_isGuest) {
      _fetchRecentChats(isRefresh: true);
      _fetchFriends();
    } else {
      setState(() {
        _isLoadingChats = false;
      });
    }
  }

  // ==========================================================
  // PHẦN 1: LOGIC QUẢN LÝ DANH SÁCH CHAT (MỚI)
  // ==========================================================

  // 1.1 Tải danh sách chat (Có phân trang)
  Future<void> _fetchRecentChats({bool isRefresh = false}) async {
    if (_isGuest) return;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    if (isRefresh) {
      if (mounted) setState(() { _isLoadingChats = true; _chatOffset = 0; _hasMoreChats = true; });
    } else {
      if (_isLoadingMoreChats || !_hasMoreChats) return;
      if (mounted) setState(() => _isLoadingMoreChats = true);
    }

    try {
      final List<dynamic> data = await _supabase.rpc(
        'get_recent_chats_v2',
        params: {
          'current_user_id': userId,
          'limit_count': _chatLimit,
          'offset_count': _chatOffset,
        },
      );

      final List<ChatPreviewModel> newChats = data
          .map((e) => ChatPreviewModel.fromJson(e))
          .toList();

      if (mounted) {
        setState(() {
          if (isRefresh) {
            _recentChats = newChats;
            _isLoadingChats = false;
          } else {
            _recentChats.addAll(newChats);
            _isLoadingMoreChats = false;
          }

          _chatOffset += newChats.length;
          if (newChats.length < _chatLimit) _hasMoreChats = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải chat: $e");
      if (mounted) setState(() { _isLoadingChats = false; _isLoadingMoreChats = false; });
    }
  }

  // 1.2 Xử lý xoá cuộc trò chuyện
  Future<void> _handleDeleteChat(String partnerId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      _recentChats.removeWhere((chat) => chat.partnerId == partnerId);
    });

    try {
      await _supabase.from('deleted_conversations').upsert(
        {
          'user_id': userId,
          'partner_id': partnerId,
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id, partner_id',
      );
    } catch (e) {
      debugPrint("Lỗi xoá chat: $e");
      // Nếu lỗi thì load lại danh sách để hiện lại
      _fetchRecentChats(isRefresh: true);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi kết nối!")));
    }
  }

  // 1.3 Xử lý chặn người dùng
  Future<void> _handleBlockUser(String partnerId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      _recentChats.removeWhere((chat) => chat.partnerId == partnerId);
    });

    try {
      // 1. Thêm vào danh sách chặn
      await _supabase.from('blocked_users').insert({
        'blocker_id': userId,
        'blocked_id': partnerId,
      });

      // 2. Ẩn luôn cuộc trò chuyện
      await _supabase.from('deleted_conversations').upsert({
        'user_id': userId,
        'partner_id': partnerId,
        'deleted_at': DateTime.now().toIso8601String(),
      });

      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã chặn người dùng")));

    } catch (e) {
      debugPrint("Lỗi chặn: $e");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi chặn người dùng!")));
    }
  }

  // ==========================================================
  // PHẦN 2: LOGIC TÌM KIẾM (CŨ - GIỮ NGUYÊN)
  // ==========================================================

  Future<void> _fetchFriends() async {
    if (_isGuest) return;
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await _supabase.from('friends_view').select().eq('user_id', userId);
      final List<UserModel> loadedFriends = (response as List).map((data) => UserModel.fromFriendView(data)).toList();

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

  void _onSearchChanged(String query) {
    setState(() {
      _isSearching = query.isNotEmpty; // Nếu có chữ -> Chuyển sang mode tìm kiếm
      _showGlobalResults = false;
      _globalSearchResults = [];

      if (query.isEmpty) {
        _localSearchResults = _allFriends;
      } else {
        final lowerQuery = query.toLowerCase();
        _localSearchResults = _allFriends.where((user) {
          final isUser = user.role == 'user';
          final matchesName = (user.fullName ?? "").toLowerCase().contains(lowerQuery) ||
              (user.username ?? "").toLowerCase().contains(lowerQuery);
          return isUser && matchesName;
        }).toList();
      }
    });
  }

  Future<void> _searchGlobal() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() { _isGlobalLoading = true; _showGlobalResults = true; });

    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      final response = await _supabase
          .from('users')
          .select()
          .or('username.ilike.%$query%, email.eq.$query, full_name.ilike.%$query%')
          .eq('role', 'user')
          .neq('id', currentUserId!)
          .limit(10);

      final List<UserModel> results = (response as List).map((data) => UserModel.fromSearch(data, isFriend: false)).toList();
      final friendIds = _allFriends.map((e) => e.id).toSet();
      final filteredResults = results.where((u) => !friendIds.contains(u.id)).toList();

      if (mounted) setState(() { _globalSearchResults = filteredResults; _isGlobalLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _isGlobalLoading = false; _globalSearchResults = []; });
    }
  }

  // ==========================================================
  // PHẦN 3: GIAO DIỆN (BUILD)
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    if (_isGuest) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline_rounded, size: 60, color: Colors.grey[400]),
              ),
              const SizedBox(height: 24),
              const Text(
                "Tính năng dành cho thành viên",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                "Hãy đăng nhập hoặc đăng ký để nhắn tin và kết nối với bạn bè.",
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF00CC),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Đăng nhập/ Đăng ký",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        // 1. THANH TÌM KIẾM
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

        // 2. NỘI DUNG CHÍNH (SWITCH GIỮA 2 VIEW)
        Expanded(
          child: _isSearching
              ? _buildSearchResultsView() // View Tìm kiếm (Cũ)
              : _buildRecentChatsView(),  // View Tin nhắn (Mới)
        ),
      ],
    );
  }

  // VIEW 1: DANH SÁCH TIN NHẮN (RECENT CHATS)
  Widget _buildRecentChatsView() {
    if (_isLoadingChats) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_recentChats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text("Chưa có tin nhắn nào", style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchRecentChats(isRefresh: true),
      child: ListView.builder(
        // +1 để dành chỗ cho nút loading more ở cuối
        itemCount: _recentChats.length + 1,
        itemBuilder: (context, index) {
          // Xử lý nút Load More ở cuối danh sách
          if (index == _recentChats.length) {
            if (!_hasMoreChats) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: Text("Đã hiển thị hết tin nhắn", style: TextStyle(color: Colors.grey, fontSize: 12))),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: _isLoadingMoreChats
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(
                  onPressed: () => _fetchRecentChats(isRefresh: false),
                  child: const Text("Tải thêm"),
                ),
              ),
            );
          }

          // Hiển thị Chat Item
          final chat = _recentChats[index];
          return ChatItem(
            chat: chat,
            onTap: () async {
              final user = UserModel(
                id: chat.partnerId,
                fullName: chat.fullName,
                avatarUrl: chat.avatarUrl,
                role: 'user',
              );

              await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ChatScreen(targetUser: user))
              );
              _fetchRecentChats(isRefresh: true);
            },
            onDeleteChat: _handleDeleteChat,
            onBlockUser: _handleBlockUser,
          );
        },
      ),
    );
  }

  // VIEW 2: KẾT QUẢ TÌM KIẾM (BẠN BÈ + GLOBAL)
  Widget _buildSearchResultsView() {
    if (_isLoadingFriends) return const Center(child: CircularProgressIndicator());

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        // List local
        if (!_showGlobalResults)
          ..._localSearchResults.map((user) => _buildUserItem(user)),

        // Nút tìm global
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
                    decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
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

        // List global
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
    );
  }

  // Widget con dùng cho list search
  Widget _buildUserItem(UserModel user) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.grey[200],
        backgroundImage: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) ? NetworkImage(user.avatarUrl!) : null,
        child: (user.avatarUrl == null || user.avatarUrl!.isEmpty) ? Text(user.fullName?[0].toUpperCase() ?? "?") : null,
      ),
      title: Text(user.fullName ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(user.isFriend ? "@${user.username} • Bạn bè" : "@${user.username} • Người lạ"),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(targetUser: user)));
        // Quay lại thì refresh list chat
        _fetchRecentChats(isRefresh: true);
      },
    );
  }
}