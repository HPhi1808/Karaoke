import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/event_model.dart';

class EventDetailScreen extends StatefulWidget {
  final EventModel event;
  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  bool _isRegistering = false;
  bool _hasRegistered = false;
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkRegistrationStatus();
  }

  // Kiểm tra xem user đã đăng ký sự kiện này chưa
  Future<void> _checkRegistrationStatus() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final response = await _supabase
        .from('event_registrations')
        .select('id')
        .eq('event_id', widget.event.id)
        .eq('user_id', user.id)
        .maybeSingle();

    if (mounted && response != null) {
      setState(() => _hasRegistered = true);
    }
  }

  // Hàm thực hiện đăng ký thật lên Supabase
  Future<void> _handleRegister() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vui lòng đăng nhập để đăng ký")));
      return;
    }

    setState(() => _isRegistering = true);

    try {
      await _supabase.from('event_registrations').insert({
        'event_id': widget.event.id,
        'user_id': user.id,
      });

      if (mounted) {
        setState(() {
          _hasRegistered = true;
          _isRegistering = false;
        });
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRegistering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lỗi: ${e.toString().contains('unique') ? 'Bạn đã đăng ký rồi' : 'Không thể đăng ký lúc này'}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF00CC);
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text("Chi tiết sự kiện", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.event.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Container(width: 50, height: 5, decoration: BoxDecoration(gradient: LinearGradient(colors: [widget.event.color1, widget.event.color2]), borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 30),

            // Card thời gian
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
              child: Row(
                children: [
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.calendar_month, color: primaryColor, size: 22)),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Thời gian diễn ra", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text("${widget.event.startDate.day}/${widget.event.startDate.month} - ${widget.event.endDate.day}/${widget.event.endDate.month}/${widget.event.endDate.year}", style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            const Text("Nội dung sự kiện", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
            const SizedBox(height: 12),
            Text(widget.event.description, style: TextStyle(fontSize: 15, color: Colors.grey[800], height: 1.6)),

            const SizedBox(height: 35),
            const Text("Phần thưởng hấp dẫn", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
            const SizedBox(height: 16),
            
            if (widget.event.rewards.isEmpty)
              const Text("Đang cập nhật phần thưởng...", style: TextStyle(color: Colors.grey))
            else
              ...widget.event.rewards.map((reward) => _buildRewardItem(reward['title'] ?? 'Giải thưởng', reward['value'] ?? '...', Icons.stars, Colors.orange)),

            const SizedBox(height: 120),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        color: Colors.white,
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: (_hasRegistered || _isRegistering) ? null : _handleRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: _hasRegistered ? Colors.grey : primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isRegistering 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(_hasRegistered ? "ĐÃ ĐĂNG KÝ" : "ĐĂNG KÝ THAM GIA NGAY", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Thành công"),
        content: const Text("Bạn đã đăng ký tham gia sự kiện thành công!"),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Đóng"))],
      ),
    );
  }

  Widget _buildRewardItem(String title, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey[100]!)),
      child: Row(children: [Icon(icon, color: color, size: 26), const SizedBox(width: 16), Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)), const Spacer(), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 15))]),
    );
  }
}