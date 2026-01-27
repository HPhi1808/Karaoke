import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dio/dio.dart';
import '../models/moment_model.dart';
import 'api_client.dart';
import 'base_service.dart';

class MomentService extends BaseService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static final MomentService instance = MomentService._internal();
  MomentService._internal();

  // --- HÀM TẠO MOMENT (Gồm 3 bước: Presigned -> Upload R2 -> Save DB) ---
  Future<void> createAudioMoment({
    required File file,
    required String description,
    required String visibility,
  }) async {
    return await safeExecution(() async {
      final dio = ApiClient.instance.dio;
      final fileName = file.path.split('/').last;

      // B1: Lấy link upload
      final presignedRes = await dio.post('/api/user/upload/presigned-url', data: {
        "fileName": fileName,
        "fileType": "audio/wav",
      });

      if (presignedRes.data['success'] != true) throw Exception("Lỗi lấy link upload");

      final String uploadUrl = presignedRes.data['uploadUrl'];
      final String publicUrl = presignedRes.data['publicUrl'];

      // B2: Upload lên R2
      final fileBytes = await file.readAsBytes();
      await Dio().put(
          uploadUrl,
          data: Stream.fromIterable([fileBytes]),
          options: Options(
            headers: {
              "Content-Type": "audio/wav",
              "Content-Length": fileBytes.length
            },
          )
      );

      // B3: Lưu DB
      final saveRes = await dio.post('/api/user/upload/save-metadata', data: {
        "audioUrl": publicUrl,
        "description": description,
        "visibility": visibility,
      });

      if (saveRes.data['success'] != true) {
        throw Exception("Lỗi lưu metadata");
      }
    });
  }

  // --- HÀM CẬP NHẬT MOMENT ---
  Future<void> updateMoment({
    required int momentId,
    required String description,
    required String visibility,
  }) async {
    return await safeExecution(() async {
      final dio = ApiClient.instance.dio;
      final res = await dio.put('/api/user/moments/$momentId', data: {
        "description": description,
        "visibility": visibility,
      });

      if (res.data['success'] != true) {
        throw Exception(res.data['message']);
      }
    });
  }

  // --- Xóa Moment ---
  Future<void> deleteMoment(int momentId) async {
    return await safeExecution(() async {
      final response = await ApiClient.instance.dio.delete('/api/user/moments/$momentId');
      if (response.data['success'] != true) {
        throw Exception("Xóa thất bại");
      }
    });
  }

  // -- Hàm lấy một moment dựa vào ID ---
  Future<Moment?> getMomentById(int momentId) async {
    return await safeExecution(() async {
      final response = await _supabase
          .from('moments')
          .select('*, users:user_id(full_name, avatar_url)')
          .eq('moment_id', momentId)
          .single();

      final stats = await _internalGetMomentStats(momentId);

      var moment = Moment.fromJson(response);

      if (stats != null) {
        moment = moment.copyWith(
          likesCount: stats['likes_count'],
          commentsCount: stats['comments_count'],
          isLiked: stats['is_liked'],
        );
      }
      return moment;
    });
  }

  //--- Feed Public ---
  Future<List<Moment>> getPublicFeed({int limit = 20, int offset = 0}) async {
    return await safeExecution(() => _callFeedRpc('get_public_feed', limit, offset));
  }

  // --- Feed Following ---
  Future<List<Moment>> getFollowingFeed({int limit = 20, int offset = 0}) async {
    return await safeExecution(() => _callFeedRpc('get_following_feed', limit, offset));
  }

  // --- Lấy Top Moments (Xếp hạng theo lượt like, Public) ---
  Future<List<Moment>> getTopLikedMoments({int limit = 5}) async {
    return await safeExecution(() async {
      final List<dynamic> response = await _supabase.rpc(
        'get_top_liked_moments',
        params: {
          'p_limit': limit,
        },
      );
      return response.map((item) => Moment.fromJson(item)).toList();
    });
  }

  // --- User Moments ---
  Future<List<Moment>> getUserMoments(String targetUserId, {int limit = 10, int offset = 0}) async {
    return await safeExecution(() async {
      final List<dynamic> response = await _supabase.rpc(
        'get_user_moments',
        params: {
          'p_target_user_id': targetUserId,
          'p_limit': limit,
          'p_offset': offset,
        },
      );
      return response.map((item) => Moment.fromJson(item)).toList();
    });
  }

  // --- Like/Unlike ---
  Future<void> toggleLike(int momentId, bool shouldLike, String ownerId) async {
    // Action người dùng, nên bọc safeExecution để đảm bảo tut like được thực hiện
    return await safeExecution(() async {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      if (shouldLike) {
        await _supabase
            .from('moment_likes')
            .upsert({'user_id': userId, 'moment_id': momentId});
        _triggerNotification(ownerId, momentId, 'like');
      } else {
        await _supabase
            .from('moment_likes')
            .delete()
            .match({'user_id': userId, 'moment_id': momentId});
      }
    });
  }

  // --- Hàm gửi Comment ---
  Future<void> sendComment(int momentId, String content, String ownerId) async {
    return await safeExecution(() async {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('moment_comments').insert({
        'user_id': userId,
        'moment_id': momentId,
        'content': content,
      });
      _triggerNotification(ownerId, momentId, 'comment');
    });
  }

  // --- Hàm chỉnh sửa comment
  Future<void> editComment(int commentId, String newContent) async {
    return await safeExecution(() async {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase
          .from('moment_comments')
          .update({
        'content': newContent,
        'created_at': DateTime.now().toUtc().toIso8601String()
      })
          .eq('id', commentId)
          .eq('user_id', userId);
    });
  }

  // --- Hàm xoá Comment ---
  Future<bool> deleteComment(int commentId) async {
    return await safeExecution(() async {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await _supabase
          .from('moment_comments')
          .delete()
          .eq('id', commentId)
          .eq('user_id', userId);
      return true;
    });
  }

  // --- Helper: RPC Call ---
  Future<List<Moment>> _callFeedRpc(String rpcName, int limit, int offset) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final List<dynamic> response = await _supabase.rpc(
      rpcName,
      params: {
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return response.map((item) => Moment.fromJson(item)).toList();
  }

  // --- Helper: Get Stats ---
  Future<Map<String, dynamic>?> _internalGetMomentStats(int momentId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final resLikes = await _supabase.from('moment_likes').count(CountOption.exact).eq('moment_id', momentId);
      final resComments = await _supabase.from('moment_comments').count(CountOption.exact).eq('moment_id', momentId);

      bool isLiked = false;
      if (userId != null) {
        final checkLike = await _supabase.from('moment_likes').select('user_id').eq('moment_id', momentId).eq('user_id', userId).maybeSingle();
        isLiked = checkLike != null;
      }
      return {'likes_count': resLikes, 'comments_count': resComments, 'is_liked': isLiked};
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getMomentStats(int momentId) async {
    return safeExecution(() => _internalGetMomentStats(momentId));
  }

  // --- Trigger Notification ---
  Future<void> _triggerNotification(String receiverId, int momentId, String type) async {
    final actorId = _supabase.auth.currentUser?.id;
    if (actorId == null || actorId == receiverId) return;
    try {
      await ApiClient.instance.dio.post("/api/user/notifications/trigger",
        data: {'actor_id': actorId, 'receiver_id': receiverId, 'moment_id': momentId, 'type': type},
      );
    } catch (e) {
      debugPrint("⚠️ Trigger Noti Failed: $e");
    }
  }

  // --- Mark Viewed ---
  Future<void> markMomentsAsViewed(List<int> momentIds) async {
    if (momentIds.isEmpty) return;
    try {
      await _supabase.rpc('mark_moments_as_viewed', params: {'moment_ids': momentIds});
    } catch (e) {
      debugPrint("Lỗi mark view: $e");
    }
  }

  Stream<List<Map<String, dynamic>>> getCommentsStream(int momentId) {
    return _supabase.from('moment_comments').stream(primaryKey: ['id']).eq('moment_id', momentId).order('created_at', ascending: true).map((event) => event);
  }

  // Get User Profile
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try { return await _supabase.from('users').select('full_name, avatar_url').eq('id', userId).single(); } catch(e) { return null; }
  }
}