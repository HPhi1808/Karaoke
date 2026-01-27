import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/event_model.dart';
import 'base_service.dart';

class EventService extends BaseService {
  static final EventService instance = EventService._internal();
  EventService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // Lấy danh sách sự kiện từ Supabase
  Future<List<EventModel>> getEvents() async {
    return await safeExecution(() async {
      try {
        final response = await _supabase
            .from('events')
            .select()
            .order('start_date', ascending: false);
        
        final List<dynamic> data = response as List;
        return data.map((json) => EventModel.fromJson(json)).toList();
      } catch (e) {
        debugPrint("🔴 Lỗi lấy danh sách sự kiện từ Supabase: $e");
        return [];
      }
    });
  }

  // Lấy thông tin chi tiết một sự kiện
  Future<EventModel?> getEventDetail(String eventId) async {
    return await safeExecution(() async {
      try {
        final response = await _supabase
            .from('events')
            .select()
            .eq('id', eventId)
            .single();
        
        return EventModel.fromJson(response);
      } catch (e) {
        debugPrint("🔴 Lỗi lấy chi tiết sự kiện: $e");
        return null;
      }
    });
  }
}