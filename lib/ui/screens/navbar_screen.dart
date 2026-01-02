import 'package:flutter/material.dart';
import '../../models/song_model.dart';
import '../../utils/user_manager.dart';
import 'home/home_screen.dart';
import 'me/me_screen.dart';
import 'songs/songs_screen.dart';
import 'moments/moments_screen.dart';
import 'message/message_screen.dart';

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

  @override
  void initState() {
    super.initState();
    UserManager.instance.init();
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
      case 3: return const MessageScreen();
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
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: primaryColor), label: 'Trang chủ'),
            NavigationDestination(icon: Icon(Icons.access_time_outlined), selectedIcon: Icon(Icons.access_time_filled, color: primaryColor), label: 'Khoảnh khắc'),
            NavigationDestination(icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic, color: primaryColor), label: 'Hát'),
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble, color: primaryColor), label: 'Tin nhắn'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: primaryColor), label: 'Tôi'),
          ],
        ),
      ),
    );
  }
}