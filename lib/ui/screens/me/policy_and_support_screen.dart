import 'package:flutter/material.dart';

class PolicyAndSupportScreen extends StatefulWidget {
  const PolicyAndSupportScreen({super.key});

  @override
  State<PolicyAndSupportScreen> createState() => _PolicyAndSupportScreenState();
}

class _PolicyAndSupportScreenState extends State<PolicyAndSupportScreen> {
  final List<Map<String, String>> policies = [
    {
      "title": "1. Chính sách Bản quyền và Sở hữu trí tuệ",
      "content": "Mọi bài hát, nhạc nền (beat) và lời bài hát trên ứng dụng đều thuộc quyền sở hữu của ứng dụng hoặc bên cấp phép. Người dùng chỉ được quyền sử dụng để hát và ghi âm trong phạm vi ứng dụng. Nghiêm cấm mọi hành vi trích xuất, sao chép hoặc phát tán nội dung ra ngoài nền tảng khi chưa có sự đồng ý bằng văn bản."
    },
    {
      "title": "2. Chính sách Nội dung do người dùng tạo (UGC)",
      "content": "Khi người dùng đăng tải bản thu âm (audio) hoặc video karaoke lên hệ thống, người dùng cam kết nội dung đó không vi phạm bản quyền của bên thứ ba, không chứa hình ảnh nhạy cảm, bạo lực hoặc kích động. Ứng dụng có quyền gỡ bỏ bất kỳ nội dung nào vi phạm mà không cần thông báo trước."
    },
    {
      "title": "3. Chính sách Quyền riêng tư và Truy cập thiết bị",
      "content": "Để ứng dụng hoạt động tối ưu, người dùng cần cấp quyền truy cập vào: Micro (để thu âm), Máy ảnh (để quay video/livestream), và Bộ nhớ (để lưu bản nháp). Chúng tôi cam kết không thu thập dữ liệu hội thoại cá nhân ngoài mục đích phục vụ tính năng hát và ghi âm."
    },
    {
      "title": "4. Chính sách Thanh toán và Tiền ảo",
      "content": "Các đơn vị tiền tệ trong app (Xu, Kim cương, Sao...) được dùng để mua vật phẩm hoặc tặng quà. Tiền ảo sau khi đã nạp thành công sẽ không được hoàn lại thành tiền mặt, trừ trường hợp lỗi hệ thống được xác nhận bởi bộ phận kỹ thuật."
    },
    {
      "title": "5. Chính sách Bảo vệ trẻ em",
      "content": "Người dùng dưới 13 tuổi (hoặc theo quy định pháp luật địa phương) phải có sự giám sát của phụ huynh khi sử dụng. Ứng dụng có quyền hạn chế các tính năng giao tiếp xã hội hoặc livestream đối với tài khoản trẻ em để đảm bảo an toàn môi trường mạng."
    },
    {
      "title": "6. Chính sách Ứng xử cộng đồng",
      "content": "Nghiêm cấm các hành vi bắt nạt, xúc phạm, quấy rối hoặc phân biệt đối xử trong phần bình luận, tin nhắn hoặc phòng hát trực tuyến. Các tài khoản vi phạm sẽ bị cảnh cáo, khóa tính năng tương tác hoặc khóa tài khoản vĩnh viễn tùy theo mức độ vi phạm."
    },
    {
      "title": "7. Chính sách Quảng cáo và Khuyến mãi",
      "content": "Người dùng sử dụng phiên bản miễn phí có thể thấy quảng cáo từ bên thứ ba. Ứng dụng cam kết các quảng cáo này không chứa phần mềm độc hại. Các chương trình khuyến mãi nạp thẻ hoặc sự kiện hát có thưởng đều có điều khoản riêng và quyền quyết định cuối cùng thuộc về Ban quản trị App."
    },
    {
      "title": "8. Chính sách Xử lý lỗi kỹ thuật (Bồi hoàn trải nghiệm)",
      "content": "Trong trường hợp hệ thống bảo trì đột xuất hoặc gặp lỗi lớn khiến người dùng mất dữ liệu bản thu đang thực hiện hoặc mất quà tặng khi đang gửi, ứng dụng sẽ có chính sách đền bù bằng tiền ảo hoặc gói VIP tương ứng dựa trên bằng chứng xác thực."
    },
    {
      "title": "9. Chính sách Xóa tài khoản và Dữ liệu",
      "content": "Người dùng có quyền yêu cầu xóa tài khoản vĩnh viễn bất kỳ lúc nào thông qua mục Cài đặt. Sau khi xác nhận xóa, toàn bộ thông tin cá nhân, danh sách bản thu và số dư tiền ảo sẽ bị hủy bỏ và không thể khôi phục để bảo vệ quyền riêng tư."
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Chính sách & Hỗ trợ",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple, Colors.purpleAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 5,
      ),
      body: Column(
        children: [
          // Phần thông tin Hotline và Gmail mới thêm
          _buildContactHeader(),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              itemCount: policies.length,
              itemBuilder: (context, index) {
                return _buildPolicyCard(
                  policies[index]['title']!,
                  policies[index]['content']!,
                );
              },
            ),
          ),

          // Nút xác nhận ở dưới cùng
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text("TÔI ĐÃ HIỂU VÀ ĐỒNG Ý"),
            ),
          ),
        ],
      ),
    );
  }

  // Widget hiển thị Hotline và Email
  Widget _buildContactHeader() {
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.deepPurple.withOpacity(0.2)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Cần hỗ trợ trực tiếp?",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.deepPurple
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.email, size: 20, color: Colors.deepPurple),
              SizedBox(width: 10),
              Text(
                "Email: karaokeplusapp@gmail.com",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyCard(String title, String content) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ExpansionTile(
        initiallyExpanded: false, // Để mặc định đóng cho gọn
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 15,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              content,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.5,
              ),
              textAlign: TextAlign.justify,
            ),
          ),
        ],
      ),
    );
  }
}