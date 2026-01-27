import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../../models/user_model.dart';
import '../../../models/message_model.dart';
import '../../widgets/chat_item.dart';
import '../../../services/auth_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/message_service.dart'; // [MỚI] Import MessageService
import '../../widgets/friends_sidebar.dart';
import 'chat_screen.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => MessagesTabState();
}

class MessagesTabState extends State<MessagesTab> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  // Realtime channel để lắng nghe tin nhắn mới
  RealtimeChannel? _msgChannel;

  bool _isGuest = false;
  bool _isSidebarOpen = false;

  List<ChatPreviewModel> _recentChats = [];
  bool _isLoadingChats = true;
  bool _isLoadingMoreChats = false;
  bool _hasMoreChats = true;
  final int _chatLimit = 20;
  int _chatOffset = 0;

  List<UserModel> _allFriends = [];
  List<UserModel> _localSearchResults = [];
  List<UserModel> _globalSearchResults = [];
  bool _isSearching = false;
  bool _isGlobalLoading = false;
  bool _showGlobalResults = false;

  @override
  void initState() {
    super.initState();
    _isGuest = AuthService.instance.isGuest;
    if (!_isGuest) {
      _fetchRecentChats(isRefresh: true);
      _fetchFriends();
      _setupRealtimeMessages();
    } else {
      setState(() => _isLoadingChats = false);
    }
  }

  Future<void> refresh() async {
    if (mounted) {
      setState(() => _isLoadingChats = true);
      await _fetchRecentChats(isRefresh: true);
    }
  }

  @override
  void dispose() {
    if (_msgChannel != null) _supabase.removeChannel(_msgChannel!);
    _searchController.dispose();
    super.dispose();
  }

  void _setupRealtimeMessages() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    if (_msgChannel != null) _supabase.removeChannel(_msgChannel!);

    _msgChannel = _supabase.channel('messages_tab_realtime')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'receiver_id',
          value: userId
      ),
      callback: (payload) {
        if (mounted) {
          _fetchRecentChats(isRefresh: true, showLoading: false);
        }
      },
    )
        .subscribe();
  }

  Future<void> _fetchRecentChats({bool isRefresh = false, bool showLoading = true}) async {
    if (_isGuest) {
      if(mounted) setState(() => _isLoadingChats = false);
      return;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    if (isRefresh) {
      if (mounted && showLoading) setState(() => _isLoadingChats = true);
      _chatOffset = 0;
      _hasMoreChats = true;
    } else {
      if (_isLoadingMoreChats || !_hasMoreChats) return;
      if (mounted) setState(() => _isLoadingMoreChats = true);
    }

    try {
      final newChats = await MessageService.instance.getRecentChats(
        userId: userId,
        limit: _chatLimit,
        offset: _chatOffset,
      );

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
      if (mounted) setState(() { _isLoadingChats = false; _isLoadingMoreChats = false; });
    }
  }

  Future<void> _fetchFriends() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final loadedFriends = await MessageService.instance.getFriends(userId);
      if (mounted) setState(() => _allFriends = loadedFriends);
    } catch (e) {
      debugPrint("Lỗi tải bạn bè: $e");
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
      _showGlobalResults = false;
      if (query.isEmpty) {
        _localSearchResults = [];
      } else {
        final lowerQuery = query.toLowerCase();
        _localSearchResults = _allFriends.where((user) {
          return (user.fullName ?? "").toLowerCase().contains(lowerQuery) ||
              (user.username ?? "").toLowerCase().contains(lowerQuery);
        }).toList();
      }
    });
  }

  Future<void> _searchGlobal() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isGlobalLoading = true;
      _showGlobalResults = true;
    });

    try {
      final results = await MessageService.instance.searchUsersGlobal(query);
      final friendIds = _allFriends.map((f) => f.id).toSet();
      final filteredGlobal = results.where((u) => !friendIds.contains(u.id)).toList();

      if (mounted) {
        setState(() {
          _globalSearchResults = filteredGlobal;
          _isGlobalLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tìm kiếm: $e');
      if (mounted) setState(() => _isGlobalLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isGuest) {
      return _buildGuestPlaceholder();
    }
    return Stack(
      children: [
        Column(
          children: [
            _buildSearchHeader(),
            Expanded(
              child: _isSearching ? _buildSearchResultsView() : _buildRecentChatsView(),
            ),
          ],
        ),
        if (_isSidebarOpen) GestureDetector(onTap: () => setState(() => _isSidebarOpen = false), child: Container(color: Colors.black26)),
        FriendsSidebar(isOpen: _isSidebarOpen, onClose: () => setState(() => _isSidebarOpen = false)),
      ],
    );
  }

  Widget _buildGuestPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 20),
            const Text(
              "Đăng nhập để nhắn tin",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 10),
            const Text(
              "Kết nối với bạn bè và chia sẻ những khoảnh khắc thú vị ngay bây giờ.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF00CC),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: const Text("Đăng nhập", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _searchGlobal(),
              enabled: !_isGuest,
              decoration: InputDecoration(
                hintText: "Tìm bạn bè, username...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _onSearchChanged(''); }) : null,
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed:_isGuest
                ? null
                : () => setState(() => _isSidebarOpen = true),
            icon: const Icon(Icons.people_alt_outlined, color: Color(0xFFFF00CC)),
            style: IconButton.styleFrom(backgroundColor: Colors.grey[100]),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentChatsView() {
    if (_isLoadingChats) {
      return _buildSkeletonList();
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _isLoadingChats = true);
        await _fetchRecentChats(isRefresh: true);
        NotificationService.instance.fetchCounts();
      },
      child: _recentChats.isEmpty
          ? LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: _buildEmptyState(),
          ),
        ),
      )
          : ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _recentChats.length + (_hasMoreChats ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _recentChats.length) {
            if (!_isLoadingMoreChats) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _fetchRecentChats();
              });
            }
            return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
          }
          final chat = _recentChats[index];
          return ChatItem(
            chat: chat,
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(targetUser: UserModel(id: chat.partnerId, fullName: chat.fullName, avatarUrl: chat.avatarUrl, role: 'user'))));
              if (mounted) {
                NotificationService.instance.fetchCounts();
                _fetchRecentChats(isRefresh: true, showLoading: false);
              }
            },
            onDeleteChat: (id) => _fetchRecentChats(isRefresh: true, showLoading: false),
            onBlockUser: (id) => _fetchRecentChats(isRefresh: true, showLoading: false),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: 10,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const CircleAvatar(radius: 28, backgroundColor: Colors.white),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(width: 120, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                          Container(width: 40, height: 10, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(width: double.infinity, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResultsView() {
    return ListView(
      children: [
        if (_localSearchResults.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text("Bạn bè", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
          ..._localSearchResults.map((u) => _buildUserItem(u, isFriend: true)),
        ],

        if (!_showGlobalResults && _searchController.text.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.public, color: Colors.blue),
            title: Text("Tìm kiếm '${_searchController.text}'"),
            subtitle: const Text("Nhấn Enter để tìm người lạ"),
            onTap: _searchGlobal,
          ),

        if (_isGlobalLoading) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),

        if (_showGlobalResults) ...[
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text("Người lạ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
          if (_globalSearchResults.isEmpty && !_isGlobalLoading)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("Không tìm thấy người dùng này", style: TextStyle(color: Colors.grey)))),
          ..._globalSearchResults.map((u) => _buildUserItem(u, isFriend: false)),
        ],
      ],
    );
  }

  Widget _buildUserItem(UserModel user, {required bool isFriend}) {
    return ListTile(
        leading: CircleAvatar(
          backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty ? NetworkImage(user.avatarUrl!) : null,
          child: (user.avatarUrl == null || user.avatarUrl!.isEmpty) ? Text(user.fullName?[0] ?? "?") : null,
        ),
        title: Text(user.fullName ?? "Người dùng"),
        subtitle: Text("@${user.username ?? 'user'}${isFriend ? ' • Bạn bè' : ''}"),
        onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatScreen(targetUser: user))
          );
          if (mounted) {
            _fetchRecentChats(isRefresh: true, showLoading: false);
            NotificationService.instance.fetchCounts();
          }
        }
    );
  }

  Widget _buildEmptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.chat_bubble_outline, size: 50, color: Colors.grey[300]), const SizedBox(height: 10), const Text("Chưa có tin nhắn nào", style: TextStyle(color: Colors.grey))]));
}