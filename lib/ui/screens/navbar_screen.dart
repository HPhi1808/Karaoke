import 'dart:async';
import 'package:flutter/material.dart';
import 'package:karaoke/models/song_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import 'home_screen.dart';
import 'me_screen.dart';
import 'song_detail_screen.dart';

class NavbarScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final Function(SongModel) onSongClick;

  const NavbarScreen({
    Key? key,
    required this.onLogout,
    required this.onSongClick,
  }) : super(key: key);

  @override
  State<NavbarScreen> createState() => _NavbarScreenState();
}

class _NavbarScreenState extends State<NavbarScreen> {
  int _selectedIndex = 0;

  // Biến quản lý việc lắng nghe Database
  StreamSubscription? _userSubscription;

  @override
  void initState() {
    super.initState();
    _setupAccountListener();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  // --- LOGIC LẮNG NGHE KHÓA TÀI KHOẢN (REALTIME) ---
  void _setupAccountListener() {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null || AuthService.instance.isGuest) return;

    _userSubscription = Supabase.instance.client
        .from('users')
        .stream(primaryKey: ['id'])
        .eq('id', user.id)
        .listen((List<Map<String, dynamic>> data) {

      if (data.isNotEmpty) {
        final userData = data.first;
        final lockedUntilStr = userData['locked_until'];

        // Kiểm tra xem có bị khóa không
        if (lockedUntilStr != null) {
          DateTime lockedTime = DateTime.parse(lockedUntilStr);
          if (lockedTime.isAfter(DateTime.now())) {
            _forceLogout();
          }
        }
      }
    });
  }

  // Hàm xử lý đăng xuất cưỡng chế
  Future<void> _forceLogout() async {
    // 1. Ngừng lắng nghe ngay lập tức
    _userSubscription?.cancel();

    // 2. Gọi AuthService đăng xuất
    await AuthService.instance.logout();

    if (!mounted) return;

    // 3. Hiện thông báo chặn
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Tài khoản bị khóa"),
        content: const Text("Tài khoản của bạn đã bị Quản trị viên khóa quyền truy cập do vi phạm quy định."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();

              widget.onLogout();
            },
            child: const Text("Đã hiểu", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- UI CHÍNH ---

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return HomeScreen(
          onSongClick: (song) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Đang mở: ${song.title}"),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );

            // 2. Chuyển sang màn hình SongDetailScreen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SongDetailScreen(
                  songId: song.id,
                  onBack: () {
                    Navigator.pop(context);
                  },
                ),
              ),
            );
          },
        );
      case 1:
        return const _CenteredText("Nội dung Khoảnh Khắc");
      case 2:
        return const _CenteredText("Màn hình Hát (Karaoke Mode)");
      case 3:
        return const _CenteredText("Màn hình Chat");
      case 4:
        return MeScreen(
          onLogoutClick: widget.onLogout,
        );
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF00CC);

    return Scaffold(
      backgroundColor: Colors.white,
      body: _buildBody(),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          indicatorColor: Colors.transparent,
          labelTextStyle: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black);
            }
            return const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.black);
          }),
        ),
        child: NavigationBar(
          backgroundColor: Colors.white,
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home, color: primaryColor),
              label: 'Trang chủ',
            ),
            NavigationDestination(
              icon: Icon(Icons.access_time_outlined),
              selectedIcon: Icon(Icons.access_time_filled, color: primaryColor),
              label: 'Khoảnh khắc',
            ),
            NavigationDestination(
              icon: Icon(Icons.mic_none),
              selectedIcon: Icon(Icons.mic, color: primaryColor),
              label: 'Hát',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble, color: primaryColor),
              label: 'Trò chuyện',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: primaryColor),
              label: 'Tôi',
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredText extends StatelessWidget {
  final String text;
  const _CenteredText(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, color: Colors.grey),
      ),
    );
  }
}