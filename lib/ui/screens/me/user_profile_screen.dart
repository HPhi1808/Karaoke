import 'package:flutter/material.dart';
import '../../../models/user_model.dart';

class UserProfileScreen extends StatelessWidget {
  final UserModel user;

  const UserProfileScreen({Key? key, required this.user}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(user.fullName ?? "Trang cá nhân"),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        titleTextStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar tạm
            CircleAvatar(
              radius: 50,
              backgroundImage: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                  ? NetworkImage(user.avatarUrl!)
                  : null,
              child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                  ? Text(
                (user.fullName?.isNotEmpty == true) ? user.fullName![0].toUpperCase() : "?",
                style: const TextStyle(fontSize: 40),
              )
                  : null,
            ),
            const SizedBox(height: 20),
            Text(
              "Đây là Profile của ${user.fullName}",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Username: @${user.username}",
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            const Text(
              "Tính năng đang phát triển...",
              style: TextStyle(color: Colors.blue),
            )
          ],
        ),
      ),
    );
  }
}