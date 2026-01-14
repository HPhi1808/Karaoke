import 'package:flutter/material.dart';
import '../../models/song_model.dart';
import '../../services/notification_service.dart';
import '../../utils/user_manager.dart';
import 'home/home_screen.dart';
import 'me/me_screen.dart';
import 'songs/songs_screen.dart';
import 'moments/moments_screen.dart';
import 'mailbox/mailbox_screen.dart';

class NavbarScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final Function(SongModel) onSongClick;

  const NavbarScreen({
    super.key,
    required this.onLogout,
    required this.onSongClick,
  });

  @override
  State<NavbarScreen> createState() => _NavbarScreenState();
}

class _NavbarScreenState extends State<NavbarScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    UserManager.instance.init();
    // Kích hoạt lắng nghe thông báo ngay khi vào màn hình chính
    NotificationService.instance.init(); 
  }

  @override
  void dispose() {
    UserManager.instance.dispose();
    super.dispose();
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0: return const HomeScreen();
      case 1: return const MomentsScreen();
      case 2: return SongsScreen(onSongClick: widget.onSongClick);
      case 3: return const MailboxScreen();
      case 4: return MeScreen(onLogoutClick: widget.onLogout);
      default: return const SizedBox();
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
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
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
          destinations: [
            const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: primaryColor), label: 'Trang chủ'),
            const NavigationDestination(icon: Icon(Icons.access_time_outlined), selectedIcon: Icon(Icons.access_time_filled, color: primaryColor), label: 'Khám phá'),
            const NavigationDestination(icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic, color: primaryColor), label: 'Hát'),
            NavigationDestination(
              icon: StreamBuilder<int>(
                stream: NotificationService.instance.getTotalUnreadCountStream(),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Badge(
                    label: Text(count > 9 ? "9+" : "$count"),
                    isLabelVisible: count > 0,
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.mail_outline),
                  );
                },
              ),
              selectedIcon: StreamBuilder<int>(
                stream: NotificationService.instance.getTotalUnreadCountStream(),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Badge(
                    label: Text(count > 9 ? "9+" : "$count"),
                    isLabelVisible: count > 0,
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.mail, color: primaryColor),
                  );
                },
              ),
              label: 'Hộp thư',
            ),
            const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: primaryColor), label: 'Tôi'),
          ],
        ),
      ),
    );
  }
}