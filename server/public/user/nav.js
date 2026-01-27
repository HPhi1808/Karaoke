// --- File: nav.js ---

document.addEventListener('click', (e) => {
    // 1. Bắt sự kiện click vào thẻ A
    const link = e.target.closest('a');
    
    // Kiểm tra: Link nội bộ, không phải download, không mở tab mới
    if (link && 
        link.href.startsWith(window.location.origin) && 
        !link.getAttribute('download') && 
        link.getAttribute('target') !== '_blank' &&
        link.getAttribute('href') !== '#') {
        
        e.preventDefault(); // Chặn reload trang
        navigateTo(link.href);
    }
});

// Xử lý nút Back/Forward của trình duyệt
window.addEventListener('popstate', () => {
    navigateTo(window.location.href, false);
});

async function navigateTo(url, pushState = true) {
    try {
        // Hiệu ứng mờ nhẹ để biết đang load
        const content = document.getElementById('app-content');
        if (!content) {
            window.location.href = url; // Nếu không có khung #app-content thì load thường
            return;
        }
        
        content.style.opacity = '0.5';
        content.style.transition = 'opacity 0.2s';

        // Tải nội dung trang mới
        const response = await fetch(url);
        const html = await response.text();

        // Parse HTML lấy được
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');

        // Lấy nội dung mới từ #app-content của trang kia
        const newContent = doc.getElementById('app-content');
        if (!newContent) {
            window.location.href = url; // Fallback an toàn
            return;
        }

        // --- THAY THẾ NỘI DUNG ---
        content.innerHTML = newContent.innerHTML;
        document.title = doc.title; // Đổi tên Tab

        if (pushState) {
            window.history.pushState({}, '', url);
        }

        // --- QUAN TRỌNG: TÌM VÀ CHẠY LẠI SCRIPT TRONG NỘI DUNG MỚI ---
        // (Vì thay innerHTML thì script bên trong không tự chạy)
        const scripts = content.querySelectorAll('script');
        
        scripts.forEach(oldScript => {
            const newScript = document.createElement('script');
            
            // Copy thuộc tính (src, type...)
            Array.from(oldScript.attributes).forEach(attr => {
                newScript.setAttribute(attr.name, attr.value);
            });

            // Copy nội dung code
            if (oldScript.innerHTML) {
                newScript.innerHTML = oldScript.innerHTML;
            }

            // Chèn vào ngay sau script cũ (hoặc append vào body) để chạy
            oldScript.parentNode.replaceChild(newScript, oldScript);
        });

        // Kết thúc hiệu ứng loading
        content.style.opacity = '1';
        window.scrollTo({ top: 0, behavior: 'smooth' });

    } catch (error) {
        console.error('Nav Error:', error);
        window.location.href = url; // Lỗi thì tải thường
    }
}