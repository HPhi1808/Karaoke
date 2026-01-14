import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../../models/user_model.dart';
import '../../../models/message_model.dart';
import '../../widgets/chat_item.dart';
import '../../../services/auth_service.dart';
import 'chat_screen.dart';
import '../../widgets/friends_sidebar.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _msgSubscription;

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
  bool _isLoadingFriends = true;
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

  @override
  void dispose() {
    _msgSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _setupRealtimeMessages() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    _msgSubscription = _supabase
        .from('messages')
        .stream(primaryKey: ['message_id'])
        .eq('receiver_id', userId)
        .listen((_) => _fetchRecentChats(isRefresh: true, showLoading: false));
  }

  Future<void> _fetchRecentChats({bool isRefresh = false, bool showLoading = true}) async {
    if (_isGuest) return;
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
      final data = await _supabase.rpc(
        'get_recent_chats_v2',
        params: {
          'current_user_id': userId,
          'limit_count': _chatLimit,
          'offset_count': _chatOffset,
        },
      );

      final List<ChatPreviewModel> newChats = (data as List)
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
      if (mounted) setState(() { _isLoadingChats = false; _isLoadingMoreChats = false; });
    }
  }

  Future<void> _fetchFriends() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final response = await _supabase.from('friends_view').select().eq('user_id', userId);
      final List<UserModel> loadedFriends = (response as List).map((data) => UserModel.fromFriendView(data)).toList();
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
      final currentUserId = _supabase.auth.currentUser?.id;
      final response = await _supabase
          .from('users')
          .select()
          .or('username.ilike.%$query%, full_name.ilike.%$query%')
          .eq('role', 'user')
          .neq('id', currentUserId!)
          .limit(20);

      final List<UserModel> results = (response as List).map((data) => UserModel.fromSearch(data)).toList();
      
      final friendIds = _localSearchResults.map((f) => f.id).toSet();
      final filteredGlobal = results.where((u) => !friendIds.contains(u.id)).toList();

      if (mounted) {
        setState(() { 
          _globalSearchResults = filteredGlobal; 
          _isGlobalLoading = false; 
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isGlobalLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: () => setState(() => _isSidebarOpen = true),
            icon: const Icon(Icons.people_alt_outlined, color: Color(0xFFFF00CC)),
            style: IconButton.styleFrom(backgroundColor: Colors.grey[100]),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentChatsView() {
    if (_isLoadingChats) return const Center(child: CircularProgressIndicator());
    if (_recentChats.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      onRefresh: () => _fetchRecentChats(isRefresh: true),
      child: ListView.builder(
        itemCount: _recentChats.length + (_hasMoreChats ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _recentChats.length) {
            _fetchRecentChats();
            return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
          }
          final chat = _recentChats[index];
          return ChatItem(
            chat: chat,
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(targetUser: UserModel(id: chat.partnerId, fullName: chat.fullName, avatarUrl: chat.avatarUrl, role: 'user'))));
              _fetchRecentChats(isRefresh: true, showLoading: false);
            },
            onDeleteChat: (id) => _fetchRecentChats(isRefresh: true, showLoading: false),
            onBlockUser: (id) => _fetchRecentChats(isRefresh: true, showLoading: false),
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
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(targetUser: user))),
    );
  }

  Widget _buildEmptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.chat_bubble_outline, size: 50, color: Colors.grey[300]), const SizedBox(height: 10), const Text("Chưa có tin nhắn nào", style: TextStyle(color: Colors.grey))]));
}