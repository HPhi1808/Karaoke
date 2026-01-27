import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/user_model.dart';
import '../../widgets/user_list_tile.dart';
import '../../../services/user_service.dart';
import '../../../providers/user_provider.dart';

class FollowListScreen extends StatefulWidget {
  final UserModel targetUser; // Người mà chúng ta đang xem danh sách của họ
  final int initialTabIndex;

  const FollowListScreen({
    super.key,
    required this.targetUser,
    this.initialTabIndex = 0
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTileActionComplete() {
    context.read<UserProvider>().fetchUserProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("@${widget.targetUser.username}"),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        titleTextStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFFF00CC),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFFFF00CC),
          tabs: const [
            Tab(text: "Đang follow"),
            Tab(text: "Follower"),
            Tab(text: "Đề xuất"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUserList(type: 'following'),
          _buildUserList(type: 'follower'),
          _buildSuggestedList(),
        ],
      ),
    );
  }

  // --- 1. WIDGET HIỂN THỊ DANH SÁCH FOLLOWING/FOLLOWER ---
  Widget _buildUserList({required String type}) {
    return FutureBuilder<List<UserModel>>(
      future: UserService.instance.fetchFollowList(
          targetUserId: widget.targetUser.id,
          type: type
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Center(child: Text("Lỗi: ${snapshot.error}"));

        final users = snapshot.data ?? [];
        if (users.isEmpty) return const Center(child: Text("Chưa có danh sách."));

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            return UserListTile(
              user: users[index],
              showFollowButton: true,
              onActionComplete: _onTileActionComplete,
            );
          },
        );
      },
    );
  }

  // --- 2. WIDGET HIỂN THỊ DANH SÁCH ĐỀ XUẤT ---
  Widget _buildSuggestedList() {
    return FutureBuilder<List<UserModel>>(
      future: UserService.instance.fetchSuggestions(
          currentProfileViewingId: widget.targetUser.id
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data ?? [];
        if (users.isEmpty) return const Center(child: Text("Không có đề xuất phù hợp."));

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) => UserListTile(
              user: users[index],
              showFollowButton: true,
            onActionComplete: _onTileActionComplete,
          ),
        );
      },
    );
  }
}