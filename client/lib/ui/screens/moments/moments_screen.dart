import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import '../../../models/moment_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/moment_service.dart';
import '../../../services/user_service.dart';
import '../../../services/auth_service.dart';
import '../../widgets/moment_item.dart';
import '../me/me_recordings_screen.dart';

// Enum để phân biệt loại Feed
enum FeedType { public, following }

class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key});

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isGuest = false;

  // Key để gọi hàm refresh từ bên ngoài (khi đăng bài xong)
  final GlobalKey<_MomentFeedListState> _publicFeedKey = GlobalKey();
  final GlobalKey<_MomentFeedListState> _followingFeedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _isGuest = AuthService.instance.isGuest;
  }

  void _showLoginDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Yêu cầu đăng nhập"),
        content: const Text("Bạn cần đăng nhập để thực hiện chức năng này."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Đóng", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthService.instance.logout();
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
            child: const Text("Đăng nhập", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _onUploadPressed() async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MeRecordingsScreen(isPickingMode: true),
      ),
    );

    // Sau khi đăng bài xong, refresh cả 2 tab
    if (mounted) {
      // Đợi 1 chút để server xử lý
      await Future.delayed(const Duration(milliseconds: 500));
      _publicFeedKey.currentState?.refresh();
      _followingFeedKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text("Khám phá", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            // 1. THANH ĐĂNG BÀI (Luôn hiển thị trên cùng)
            _buildCreatePostArea(),

            // 2. TAB BAR
            const TabBar(
              labelColor: Color(0xFFA66BFF),
              unselectedLabelColor: Colors.grey,
              indicatorColor: Color(0xFFA66BFF),
              tabs: [
                Tab(text: "Đề xuất"),
                Tab(text: "Đang theo dõi"),
              ],
            ),

            // 3. NỘI DUNG TAB (Danh sách bài viết)
            Expanded(
              child: TabBarView(
                children: [
                  // Tab 1: Public Feed
                  MomentFeedList(
                    key: _publicFeedKey,
                    feedType: FeedType.public,
                    isGuest: _isGuest,
                  ),

                  // Tab 2: Following Feed
                  _isGuest
                      ? _buildGuestView()
                      : MomentFeedList(
                    key: _followingFeedKey,
                    feedType: FeedType.following,
                    isGuest: _isGuest,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreatePostArea() {
    final userProvider = context.watch<UserProvider>();
    final displayAvatar = userProvider.currentUser?.avatarUrl ??
        _supabase.auth.currentUser?.userMetadata?['avatar_url'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        // border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey[200],
            backgroundImage: (displayAvatar != null && displayAvatar.isNotEmpty)
                ? NetworkImage(displayAvatar)
                : null,
            child: (displayAvatar == null || displayAvatar.isEmpty)
                ? const Icon(Icons.person, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: _onUploadPressed,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  "Chia sẻ bản thu âm của bạn...",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 60, color: Colors.grey),
          const SizedBox(height: 16),
          const Text("Đăng nhập để xem bài viết từ bạn bè", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _showLoginDialog,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA66BFF)),
            child: const Text("Đăng nhập ngay"),
          )
        ],
      ),
    );
  }
}

// ============================================================================
// WIDGET CON: DANH SÁCH FEED (TÁI SỬ DỤNG CHO CẢ 2 TAB)
// ============================================================================

class MomentFeedList extends StatefulWidget {
  final FeedType feedType;
  final bool isGuest;

  const MomentFeedList({
    super.key,
    required this.feedType,
    required this.isGuest
  });

  @override
  State<MomentFeedList> createState() => _MomentFeedListState();
}

// Sử dụng AutomaticKeepAliveClientMixin để giữ trạng thái khi chuyển Tab
class _MomentFeedListState extends State<MomentFeedList> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  List<Moment> _moments = [];

  // Xử lý View
  final Set<int> _pendingViewIds = {};
  Timer? _viewTimer;

  // Trạng thái load
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  final int _pageSize = 10;

  @override
  bool get wantKeepAlive => true; // Giữ trạng thái Tab

  @override
  void initState() {
    super.initState();
    _loadData();

    // Timer đẩy view lên server mỗi 5 giây
    _viewTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _flushViewsToServer();
    });

    // Lazy Loading Listener
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
          !_isLoadingMore &&
          _hasMoreData &&
          !_isInitialLoading) {
        _loadMoreData();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _viewTimer?.cancel();
    _flushViewsToServer();
    super.dispose();
  }

  // --- Public Method: Gọi refresh từ bên ngoài ---
  Future<void> refresh() async {
    await _loadData();
  }

  // --- Tải dữ liệu lần đầu ---
  Future<void> _loadData() async {
    if(!mounted) return;
    setState(() {
      _isInitialLoading = true;
      _hasMoreData = true;
    });

    try {
      List<Moment> data = [];

      if (widget.feedType == FeedType.public) {
        data = await MomentService.instance.getPublicFeed(limit: _pageSize, offset: 0);
      } else {
        // Feed Following
        if (!widget.isGuest) {
          data = await MomentService.instance.getFollowingFeed(limit: _pageSize, offset: 0);
        }
      }

      if (mounted) {
        setState(() {
          _moments = data;
          if (data.length < _pageSize) _hasMoreData = false;
          _isInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi load feed (${widget.feedType}): $e");
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  // --- Tải thêm dữ liệu (Phân trang) ---
  Future<void> _loadMoreData() async {
    setState(() => _isLoadingMore = true);

    try {
      final currentOffset = _moments.length;
      List<Moment> newMoments = [];

      if (widget.feedType == FeedType.public) {
        newMoments = await MomentService.instance.getPublicFeed(limit: _pageSize, offset: currentOffset);
      } else {
        if (!widget.isGuest) {
          newMoments = await MomentService.instance.getFollowingFeed(limit: _pageSize, offset: currentOffset);
        }
      }

      if (mounted) {
        setState(() {
          if (newMoments.isEmpty) {
            _hasMoreData = false;
          } else {
            _moments.addAll(newMoments);
            if (newMoments.length < _pageSize) _hasMoreData = false;
          }
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  // --- Xử lý xóa và View ---
  void _handleDeleteMoment(int momentId) {
    setState(() {
      _moments.removeWhere((m) => m.id == momentId);
    });
  }

  void _flushViewsToServer() {
    if (_pendingViewIds.isEmpty) return;
    final listToSend = _pendingViewIds.toList();
    _pendingViewIds.clear();
    MomentService.instance.markMomentsAsViewed(listToSend);
  }

  void _onItemVisible(int momentId) {
    _pendingViewIds.add(momentId);
    if (_pendingViewIds.length >= 10) {
      _flushViewsToServer();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Cần thiết cho KeepAlive

    if (_isInitialLoading) {
      return ListView.builder(
        padding: const EdgeInsets.only(top: 10),
        itemCount: 5,
        itemBuilder: (context, index) => _buildMomentItemSkeleton(),
      );
    }

    if (_moments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                widget.feedType == FeedType.public ? Icons.public : Icons.people_outline,
                size: 50, color: Colors.grey[300]
            ),
            const SizedBox(height: 10),
            Text(
                widget.feedType == FeedType.public
                    ? "Chưa có bài đăng đề xuất nào."
                    : "Bạn chưa theo dõi ai,\nhoặc họ chưa đăng bài đăng nào.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFA66BFF),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: _moments.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _moments.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: _buildMomentItemSkeleton(),
            );
          }

          final moment = _moments[index];
          return VisibilityDetector(
            key: Key('${widget.feedType}-moment-view-${moment.id}'),
            onVisibilityChanged: (visibilityInfo) {
              if (visibilityInfo.visibleFraction > 0.85) {
                _onItemVisible(moment.id);
              }
            },
            child: MomentItem(
              moment: moment,
              onDeleted: () => _handleDeleteMoment(moment.id),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMomentItemSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(radius: 22, backgroundColor: Colors.white),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 120, height: 14, color: Colors.white),
                    const SizedBox(height: 6),
                    Container(width: 80, height: 10, color: Colors.white),
                  ],
                )
              ],
            ),
            const SizedBox(height: 12),
            Container(width: double.infinity, height: 12, color: Colors.white),
            const SizedBox(height: 12),
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}