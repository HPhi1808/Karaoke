import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/auth_service.dart';
import '../../../services/song_service.dart';
import '../../../services/event_service.dart';
import '../../../services/moment_service.dart';
import '../../../models/song_model.dart';
import '../../../models/event_model.dart';
import '../../../models/moment_model.dart';
import '../../widgets/event_banner.dart';
import '../../widgets/home_song_item.dart';
import '../moments/moment_detail_screen.dart';
import '../songs/song_detail_screen.dart';
import 'event_detail_screen.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  String _userName = "Người dùng";
  
  List<SongModel> _topSongs = [];
  List<Moment> _topMoments = [];
  List<EventModel> _activeEvents = [];
  bool _isLoadingData = true;

  late PageController _pageController;
  int _activePage = 0;
  Timer? _timer;
  static const int _infiniteCount = 10000;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _pageController = PageController(initialPage: (_infiniteCount ~/ 2), viewportFraction: 0.9);
    _startAutoScroll();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() => _isLoadingData = true);
    await Future.wait([_loadUserData(), _loadRankings(), _loadEventsData()]);
    if (mounted) setState(() => _isLoadingData = false);
  }

  Future<void> _loadUserData() async {
    if (AuthService.instance.isGuest) {
      if (mounted) setState(() => _userName = "Khách");
      return;
    }
    final user = _supabase.auth.currentUser;
    if (user != null) {
      final data = await _supabase.from('users').select('full_name').eq('id', user.id).maybeSingle();
      if (mounted && data != null) setState(() => _userName = data['full_name'] ?? "Người dùng");
    }
  }

  Future<void> _loadRankings() async {
    try {
      final songs = await SongService.instance.getTopViewedSongs(limit: 5);
      if (mounted) {
        setState(() => _topSongs = songs);
      }
    } catch (e) {
      debugPrint("Lỗi tải Top Songs: $e");
    }
    try {
      final moments = await MomentService.instance.getTopLikedMoments(limit: 5);
      if (mounted) {
        setState(() => _topMoments = moments);
      }
    } catch (e) {
      debugPrint("Lỗi tải Top Moments: $e");
    }
  }

  Future<void> _loadEventsData() async {
    try {
      final events = await EventService.instance.getEvents();
      if (mounted) setState(() => _activeEvents = events);
    } catch (e) {
      debugPrint("Lỗi load sự kiện: $e");
    }
  }

  void _startAutoScroll() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (_pageController.hasClients && _activeEvents.isNotEmpty) {
        _pageController.nextPage(duration: const Duration(milliseconds: 1000), curve: Curves.easeInOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF00CC);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        color: primaryColor,
        child: _isLoadingData 
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  if (_activeEvents.isNotEmpty)
                    EventBanner(
                      events: _activeEvents,
                      controller: _pageController,
                      activePage: _activePage,
                      onPageChanged: (index) => setState(() => _activePage = index % _activeEvents.length),
                      onTap: (event) => Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailScreen(event: event))),
                    ),
                  
                  const SizedBox(height: 32),
                  _buildEventsSection(primaryColor),
                  
                  const SizedBox(height: 32),
                  _buildCombinedRankingSection(primaryColor),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      title: Text(
        'Chào, $_userName', 
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: -0.5)),
    );
  }

  Widget _buildCombinedRankingSection(Color primaryColor) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Bảng xếp hạng'),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TabBar(
              labelColor: primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: primaryColor,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Bài hát'),
                Tab(text: 'Khoảnh khắc'),
              ],
            ),
          ),
          SizedBox(
            height: 450, 
            child: TabBarView(
              children: [
                _buildSongRankingList(),
                _buildMomentRankingList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongRankingList() {
    if (_topSongs.isEmpty) return _buildEmptyRanking();
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _topSongs.length.clamp(0, 5),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemBuilder: (context, index) {
        final song = _topSongs[index];
        return HomeSongItem(
          song: song, 
          rank: index + 1,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SongDetailScreen(
                  songId: song.id,
                  onBack: () => Navigator.pop(context),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMomentRankingList() {
    if (_topMoments.isEmpty) return _buildEmptyRanking();
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _topMoments.length.clamp(0, 5),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemBuilder: (context, index) {
        final moment = _topMoments[index];
        // Lấy tên và avatar, fallback nếu null
        final String displayName = (moment.userName != null && moment.userName!.isNotEmpty)
            ? moment.userName!
            : "Người dùng";
        final String? avatarUrl = moment.userAvatar;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MomentDetailScreen(
                  momentId: moment.id,
                  initialMoment: moment,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[100]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  )
                ]
            ),
            child: Row(
              children: [
                // Số thứ tự ranking
                SizedBox(
                  width: 30,
                  child: Text(
                      '${index + 1}',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: index == 0 ? Colors.orange : Colors.grey[400]
                      )
                  ),
                ),
                const SizedBox(width: 8),

                // Avatar người đăng
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey[100],
                    backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: (avatarUrl == null || avatarUrl.isEmpty)
                        ? Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : "?",
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                    )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),

                // Thông tin Moment
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tên người đăng
                        Text(
                          displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        // Mô tả moment
                        Text(
                            moment.description ?? 'Chia sẻ khoảnh khắc',
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis
                        ),
                      ]
                  ),
                ),

                // Số lượt like
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12)
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.favorite, color: Colors.red, size: 14),
                      const SizedBox(width: 4),
                      Text(
                          '${moment.likesCount}',
                          style: TextStyle(
                              color: Colors.red[400],
                              fontSize: 12,
                              fontWeight: FontWeight.bold
                          )
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyRanking() {
    return const Center(child: Text("Chưa có dữ liệu bảng xếp hạng!", style: TextStyle(color: Colors.grey)));
  }

  Widget _buildEventsSection(Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Sự kiện & Cuộc thi'),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _activeEvents.length,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemBuilder: (context, index) {
            final event = _activeEvents[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[100]!)),
              child: ListTile(
                leading: Container(
                  width: 45, 
                  height: 45, 
                  decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), 
                  child: const Icon(Icons.stars, color: Colors.orange, size: 24),
                ),
                title: Text(event.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: Text('Hạn: ${event.endDate.day}/${event.endDate.month}', style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EventDetailScreen(event: event))),
              ),
            );
          },
        ),
      ],
    );
  }
}