# 🎤 KARAOKE PLUS
# 1. Giới thiệu:
Dự án xây dựng một ứng dụng di động  (Mobile App) kết hợp giữa trải nghiệm hát Karaoke và Mạng xã hội. Ứng dụng cho phép người dùng tìm kiếm bài hát, thu âm giọng hát trên nền nhạc beat, và chia sẻ các bản thu (Moments) lên bảng tin chung. Cho phép các tương tác xã hội (chat, like, comment, follow) giúp nâng cao trải nghiệm người dùng.

# 2. Các tính năng chính:
**Thu âm & Xử lý âm thanh:** Người dùng có thể hát và thu âm với beat nhạc chất lượng cao, hệ thống tự động trộn (merge) giọng hát và nhạc nền.

**Mạng xã hội:** Đăng tải bản thu dưới dạng bài viết (Moment), hiển thị bài đăng từ bạn bè và cộng đồng.

**Tương tác thời gian thực:** Tính năng Thả tim (Like), Bình luận (Comment) và nhận Thông báo (Notification) ngay lập tức khi có tương tác mới.

**Hệ thống quản trị (Admin Dashboard):** Trang web quản trị giúp theo dõi thống kê hệ thống, quản lý người dùng, bài hát và xử lý các báo cáo vi phạm.

# 3. Cấu trúc dự án:
Dự án được chia thành 2 thư mục chính:
```text
Karaoke/
├── client/          # Mã nguồn ứng dụng Mobile (Flutter)
│   ├── lib/         # Logic chính và giao diện
│   ├── android/     # Cấu hình Android native
│   └── web/         # Cấu hình web native
│
└── server/          # Mã nguồn Backend (Node.js)
    ├── routes/      # Các API endpoints
    └── public/      # Web Admin Dashboard & Static files
    └── services/    # Hỗ trợ upload Media, push Notifications
```

# 4. Công nghệ sử dụng:
**Mobile App:** Flutter (Dart).

**Web Admin:** Node.js.

**Cơ sở dữ liệu (Database):** Supabase (PostgreSQL), Supabase Auth.

**Lưu trữ (Storage):** Cloudflare R2 (Lưu trữ file âm thanh & hình ảnh).

**Realtime:** Supabase Realtime.

# 5. Cài đặt & triển khai:
## 1. Yêu cầu môi trường:
**Đối với client:**

Flutter SDK: Phiên bản Stable mới nhất (>= 3.24.x).

Java JDK: Phiên bản 17 (Bắt buộc cho Android Gradle Plugin mới). Kiểm tra bằng lệnh:

        flutter --version
        java -version
**Đối với server:**

 Node.js phiên bản v22.0.x trở lên, npm phiên bản 10.8.x trở lên. Kiểm tra bằng lệnh:

        node -v
        npm -v
## 2. Triển khai
### Clone Repository:

        https://github.com/HPhi1808/Karaoke.git

### Đối với server:
#### 1. Di chuyển vào folder server:

        cd server
#### 2. Cài đặt môi trường:

        npm install
#### 3. Tạo file biến môi trường:

        copy .env.example .env
#### 4. Gán giá trị vào các Key trong file .env vừa tạo
#### 5. Khởi chạy:

        npm start

### Đối với client:
#### 1. Di chuyển vào folder client:

        cd client
#### 2. Cài đặt môi trường:

        flutter pub get
#### 3. Tạo file biến môi trường:

        copy .env.example .env
#### 4. Gán giá trị vào các Key trong file .env vừa tạo
#### 5. Khởi chạy:

        flutter run

# 6. Sơ đồ hoạt động:

```mermaid
graph TD
    %% --- Define Styles ---
    classDef user fill:#f9f,stroke:#333,stroke-width:2px;
    classDef client fill:#e1f5fe,stroke:#0277bd,stroke-width:2px;
    classDef network fill:#fff9c4,stroke:#fbc02d,stroke-width:2px,stroke-dasharray: 5 5;
    classDef server fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef db fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px;
    classDef external fill:#ffe0b2,stroke:#ef6c00,stroke-width:2px;

    %% --- Actors ---
    subgraph Users [👥 Người Dùng]
        Admin("🧑‍💼 Admin"):::user
        User("👤 End User"):::user
    end

    %% --- Frontend Clients ---
    subgraph Clients [💻 Client Side Apps]
        MobileApp("📱 Mobile App Flutter"):::client
        WebApp("🌐 Web App Flutter"):::client
        AdminPanel("🛠️ Admin Web Panel"):::client
        PublicPage("📄 Static HTML Intro"):::client
    end

    %% --- Network / Proxy Layer ---
    subgraph Network [☁️ Network Proxy]
        CF_Proxy("🛡️ Cloudflare Proxy"):::network
    end

    %% --- Backend Server ---
    subgraph Backend [⚙️ Backend Server - Node.js]
        NodeServer("Server Logic"):::server
        
        %% Chức năng cụ thể của Server
        subgraph ServerFuncs [Chức năng Server]
            API_Auth("API: Reg/Reset/Noti")
            Serve_Static("Static Files Host")
        end
    end

    %% --- Infrastructure & Services ---
    subgraph Infra [🏗️ Infrastructure & 3rd Party]
        Supabase("🗄️ Supabase DB & Auth"):::db
        R2("☁️ Cloudflare R2 Storage"):::db
        OneSignal("🔔 OneSignal Push"):::external
    end

    %% ================= CONNECTIONS =================

    %% 1. CHI TIẾT LUỒNG ADMIN (UPDATED)
    Admin -->|1. Mở trình duyệt| AdminPanel
    
    %% a. Tải giao diện (HTML/CSS/JS)
    AdminPanel -->|2. GET URL Admin| CF_Proxy
    CF_Proxy -->|3. Forward Request| Serve_Static
    Serve_Static -.->|4. Trả về HTML| CF_Proxy
    CF_Proxy -.->|5. Cache & Return| AdminPanel

    %% b. Tác vụ API (Upload/Delete/Edit)
    AdminPanel -->|6. POST API| CF_Proxy
    CF_Proxy -->|7. WAF Check & Forward| NodeServer
    NodeServer -->|8. Upload File| R2
    
    %% 2. Luồng End User (Web & Mobile)
    User -->|Sử dụng App| MobileApp
    User -->|Truy cập Web| WebApp
    User -->|Xem giới thiệu| PublicPage

    %% 3. Node.js Hosting Static Sites (Public Page cũng qua Proxy)
    PublicPage -->|Request HTML| CF_Proxy
    
    %% 4. Luồng App/Web -> Backend (Hybrid)
    %% a. Logic đặc thù đi qua Cloudflare Proxy về Server
    MobileApp & WebApp -->|HTTPS Request| CF_Proxy
    CF_Proxy -->|Forward Request| API_Auth
    
    %% b. Logic CRUD thông thường đi thẳng Supabase (SDK)
    MobileApp & WebApp -->|Supabase SDK Data| Supabase

    %% 5. Luồng Server Logic
    API_Auth -->|Xử lý Auth/Logic| Supabase
    API_Auth -->|Trigger Push| OneSignal
    
    %% 6. Luồng Media & Notification
    MobileApp & WebApp -.->|Load MP3/Image CDN| R2
    OneSignal -.->|Push Notification| MobileApp
    
    %% Link logic trong Node
    NodeServer --- API_Auth
    NodeServer --- Serve_Static
```