import 'package:flutter/material.dart';
import 'package:karaoke/models/user_model.dart';
import 'package:karaoke/ui/screens/me/user_profile_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/notification_model.dart';
import '../screens/moments/moment_detail_screen.dart';

class NotificationItem extends StatefulWidget {
  final NotificationModel notification;

  const NotificationItem({super.key, required this.notification});

  @override
  State<NotificationItem> createState() => _NotificationItemState();
}

class _NotificationItemState extends State<NotificationItem> {
  late bool _isRead;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isRead = widget.notification.isRead;
  }

  @override
  void didUpdateWidget(NotificationItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notification.isRead != oldWidget.notification.isRead) {
      _isRead = widget.notification.isRead;
    }
  }

  Future<void> _markAsRead() async {
    if (_isRead) return;
    setState(() {
      _isRead = true;
    });

    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', widget.notification.id);
    } catch (e) {
      debugPrint("Lỗi mark read: $e");
      if (mounted) setState(() => _isRead = false);
    }
  }

  Future<bool> _deleteNotification(BuildContext context) async {
    try {
      final response = await Supabase.instance.client
          .from('notifications')
          .delete()
          .eq('id', widget.notification.id)
          .select();
      return response.isNotEmpty;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lỗi: Không thể xoá thông báo này")),
        );
      }
      return false;
    }
  }

  void _handleNavigation() async {
    _markAsRead();
    final type = widget.notification.type;
    final momentId = widget.notification.momentId;
    final actorId = widget.notification.actorId;
    if (type == 'follow' && actorId != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => UserProfileScreen(user: UserModel(id: actorId, role: 'user')),
      ));
      debugPrint("Nav đến Profile User: $actorId");
    } else if ((type == 'like' || type == 'comment') && momentId != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => MomentDetailScreen(momentId: momentId),
      ));
      debugPrint("Nav đến Moment ID: $momentId");

    } else {
      setState(() {
        _isExpanded = !_isExpanded;
      });
      debugPrint("Không xác định đích đến");
    }
  }

  String? _getAvatarUrl() {
    return widget.notification.actorAvatarUrl;
  }

  Future<String?> _fetchActorAvatarLocal() async {
    if (widget.notification.actorId == null) return null;
    try {
      final data = await Supabase.instance.client
          .from('users')
          .select('avatar_url')
          .eq('id', widget.notification.actorId!)
          .single();
      return data['avatar_url'] as String?;
    } catch (e) { return null; }
  }
  @override
  Widget build(BuildContext context) {
    final bool isUnreadLocal = !_isRead;

    return Dismissible(
      key: Key(widget.notification.id.toString()),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: Colors.redAccent,
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 30),
      ),
      confirmDismiss: (direction) async {
        return await _deleteNotification(context);
      },
      child: InkWell(
        onTap: _handleNavigation,
        child: Container(
          color: isUnreadLocal ? const Color(0xFFF0F7FF) : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatarStack(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 4),
                    RichText(
                      maxLines: _isExpanded ? null : 2,
                      overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      text: TextSpan(
                        style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4, fontFamily: 'Roboto'),
                        children: [
                          TextSpan(
                            text: widget.notification.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: " ${widget.notification.message}",
                            style: TextStyle(
                              color: isUnreadLocal ? Colors.black87 : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatTime(widget.notification.updatedAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: isUnreadLocal ? const Color(0xFFFF00CC) : Colors.grey[500],
                        fontWeight: isUnreadLocal ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnreadLocal)
                Container(
                  margin: const EdgeInsets.only(left: 8, top: 18),
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: Color(0xFFFF00CC), shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarStack() {
    final avatarUrl = _getAvatarUrl();

    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade200),
                color: Colors.grey.shade100,
              ),
              child: ClipOval(
                child: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? Image.network(avatarUrl, fit: BoxFit.cover)
                    : FutureBuilder<String?>(
                  future: _fetchActorAvatarLocal(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      return Image.network(snapshot.data!, fit: BoxFit.cover);
                    }
                    return Icon(Icons.person, color: Colors.grey.shade400, size: 30);
                  },
                ),
              ),
            ),
          ),
          // Icon nhỏ ở góc (Like/Comment/Follow)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: _getIconColor(),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]
              ),
              child: Icon(_getIconData(), size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconData() {
    final type = (widget.notification.type).toLowerCase();
    switch (type) {
      case 'like': return Icons.favorite_rounded;
      case 'comment': return Icons.chat_bubble_rounded;
      case 'follow': return Icons.person_add_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _getIconColor() {
    final type = (widget.notification.type).toLowerCase();
    switch (type) {
      case 'like': return const Color(0xFFFF4D4F);
      case 'comment': return const Color(0xFF1890FF);
      case 'follow': return const Color(0xFFFF00CC);
      default: return Colors.grey;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return "Vừa xong";
    if (diff.inMinutes < 60) return "${diff.inMinutes} phút trước";
    if (diff.inHours < 24) return "${diff.inHours} giờ trước";
    if (diff.inDays < 7) return "${diff.inDays} ngày trước";
    return "${time.day}/${time.month}/${time.year}";
  }
}