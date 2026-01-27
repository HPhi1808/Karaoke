import 'package:flutter/material.dart';

class EventModel {
  final String id;
  final String title;
  final String sub; // Khôi phục trường sub
  final String description;
  final Color color1;
  final Color color2;
  final DateTime startDate;
  final DateTime endDate;
  final String? imageUrl;
  final List<dynamic> rewards;

  EventModel({
    required this.id,
    required this.title,
    required this.sub,
    required this.description,
    required this.color1,
    required this.color2,
    required this.startDate,
    required this.endDate,
    this.imageUrl,
    this.rewards = const [],
  });

  factory EventModel.fromJson(Map<String, dynamic> json) {
    const defaultColor1 = Color(0xFFFF00CC);
    const defaultColor2 = Color(0xFF6600FF);

    return EventModel(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      sub: json['sub'] ?? '', // Lấy sub từ database
      description: json['description'] ?? '',
      color1: json['color1'] != null ? Color(int.parse(json['color1'])) : defaultColor1,
      color2: json['color2'] != null ? Color(int.parse(json['color2'])) : defaultColor2,
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      imageUrl: json['image_url'],
      rewards: json['rewards'] as List<dynamic>? ?? [],
    );
  }

  static List<EventModel> get mockEvents => [
    EventModel(
      id: '1',
      title: 'ĐẠI NHẠC HỘI 2024',
      sub: 'Tham gia và nhận quà khủng',
      description: 'Chào mừng bạn đến với Đại Nhạc Hội 2024! Đây là sự kiện âm nhạc quy mô nhất năm dành cho tất cả mọi người yêu âm nhạc. Hãy đăng ký ngay để tỏa sáng!',
      color1: const Color(0xFFFF00CC),
      color2: const Color(0xFF6600FF),
      startDate: DateTime(2024, 12, 20),
      endDate: DateTime(2024, 12, 30),
    ),
  ];
}
