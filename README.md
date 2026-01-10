# **Karaoke Entertainment Plus**

# 1. Giới thiệu:
**Karaoke Entertainment Plus** là một app karaoke để người dùng ca hát giải trí, ở đây người dùng có thể
hát một hoặc hát cùng mọi người, tạo các phòng hát và chia sẻ những đoạn cover 'đỉnh cao' để mọi người
cùng nhau thưởng thức.

# 2. Yêu cầu môi trường:
Để chạy dự án này, máy tính của bạn BẮT BUỘC phải có:
1. **Flutter SDK:** Phiên bản Stable mới nhất (>= 3.24.x).
    - Kiểm tra bằng lệnh: `flutter --version`
2. **Java JDK:** Phiên bản 17 (Bắt buộc cho Android Gradle Plugin mới).
    - Kiểm tra bằng lệnh: `java -version`
    - Nếu chưa có, hãy cài đặt OpenJDK 17.

# 3. Cách chạy dự án:

1. Clone dự án về máy:

        git clone https://github.com/Phap625/App-karaoke.git

2. Cài đặt môi trường:
    
        flutter pub get

3. Khởi chạy máy ảo

4. Chọn máy ảo và chạy:

        flutter run

5. Fix lỗi(nếu có) bằng lệnh:

        https://gemini.google.com

# 4. Sơ đồ hoạt động hệ thống:

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
