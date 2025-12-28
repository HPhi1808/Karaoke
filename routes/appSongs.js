const express = require('express');
const router = express.Router();
const pool = require('../config/db');
// [MỚI] Import middleware xác thực
const { verifyToken } = require('../middleware/auth'); 

// [MỚI] Áp dụng middleware cho TOÀN BỘ các routes bên dưới
// Bất kỳ request nào vào đây đều phải có Token hợp lệ (Guest hoặc User)
router.use(verifyToken);

// --- 1. LẤY DỮ LIỆU HOME ---
// Lưu ý: Nếu app.js mount là '/api/songs', thì đường dẫn thực tế là '/api/songs/songs'
router.get('/songs', async (req, res) => {
    try {
        const limit = 10;
        
        // Bạn có thể dùng req.user.user_id ở đây nếu muốn gợi ý nhạc theo cá nhân hóa sau này
        
        const [newest, popular, recommended] = await Promise.all([
            // Bài hát mới nhất
            pool.query(`
                SELECT song_id, title, artist_name, image_url, view_count 
                FROM songs ORDER BY created_at DESC LIMIT $1`, [limit]),
            
            // Thịnh hành (View cao nhất)
            pool.query(`
                SELECT song_id, title, artist_name, image_url, view_count 
                FROM songs ORDER BY view_count DESC LIMIT $1`, [limit]),
            
            // Gợi ý ngẫu nhiên
            pool.query(`
                SELECT song_id, title, artist_name, image_url, view_count 
                FROM songs ORDER BY RANDOM() LIMIT $1`, [limit])
        ]);

        res.json({ 
            newest: newest.rows, 
            popular: popular.rows, 
            recommended: recommended.rows 
        });
    } catch (err) {
        console.error("Lỗi API /songs:", err);
        res.status(500).json({ error: 'Lỗi tải trang chủ' });
    }
});

// --- 2. TÍNH VIEW (ĐÃ BẢO MẬT USER ID) ---
router.post('/:id/view', async (req, res) => {
    const { id: songId } = req.params;
    
    // Xử lý IP (Logic cũ của bạn đã chuẩn)
    let rawIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress || '';
    if (Array.isArray(rawIp)) {
        rawIp = rawIp[0];
    }
    const ip = typeof rawIp === 'string' ? rawIp.split(',')[0].trim() : rawIp;

    // [THAY ĐỔI QUAN TRỌNG]
    // Không lấy userId từ body nữa (req.body.user_id -> KHÔNG AN TOÀN)
    // Lấy userId từ Token đã xác thực (AN TOÀN TUYỆT ĐỐI)
    // Vì middleware verifyToken đã chạy, req.user chắc chắn tồn tại.
    // Nếu là Guest, đây là ID ẩn danh. Nếu là User, đây là ID chính chủ.
    const userId = req.user.user_id; 

    try {
        // A. LOGIC KIỂM TRA CHẶT CHẼ
        let checkQuery, checkParams;

        // Nếu là Guest thì userId vẫn có giá trị (UUID từ Supabase), nên ta có thể check cả 2
        // Tuy nhiên để logic giống cũ, ta check cờ is_guest từ middleware gán vào
        
        if (!req.user.is_guest) {
            // === TRƯỜNG HỢP: USER ĐÃ ĐĂNG KÝ ===
            // Kiểm tra xem User này (ID) HOẶC IP này đã xem chưa
            checkQuery = `
                SELECT created_at FROM song_views 
                WHERE song_id = $1 AND (ip_address = $2 OR user_id = $3)
                ORDER BY created_at DESC LIMIT 1
            `;
            checkParams = [songId, ip, userId];
        } else {
            // === TRƯỜNG HỢP: GUEST (KHÁCH) ===
            // Chỉ kiểm tra theo IP (vì Guest ID có thể thay đổi mỗi lần cài lại app)
            checkQuery = `
                SELECT created_at FROM song_views 
                WHERE song_id = $1 AND ip_address = $2
                ORDER BY created_at DESC LIMIT 1
            `;
            checkParams = [songId, ip];
        }

        const checkResult = await pool.query(checkQuery, checkParams);

        if (checkResult.rows.length > 0) {
            const lastViewTime = new Date(checkResult.rows[0].created_at);
            const now = new Date();
            const diffMinutes = (now - lastViewTime) / (1000 * 60);

            if (diffMinutes < 60) {
                console.log(`[View Spam Blocked] Song: ${songId} | IP: ${ip} | User: ${userId}`);
                return res.json({ status: 'ignored', message: 'View already counted recently' });
            }
        }

        // B. Ghi log (Lưu userId vào DB để tracking)
        // Lưu ý: userId ở đây là UUID chuẩn của Supabase (dù là Guest hay User)
        await pool.query(`
            INSERT INTO song_views (song_id, ip_address, user_id) VALUES ($1, $2, $3)
        `, [songId, ip, userId]);

        await pool.query(`
            UPDATE songs SET view_count = view_count + 1 WHERE song_id = $1
        `, [songId]);

        res.json({ status: 'success', message: 'View counted' });

    } catch (err) {
        console.error("Lỗi tăng view:", err);
        res.status(500).json({ error: err.message });
    }
});

// --- 3. TÌM KIẾM ---
router.get('/', async (req, res) => {
    try {
        const { q: keyword, sort: sortType } = req.query;
        let query = `SELECT song_id, title, artist_name, image_url, view_count, created_at FROM songs WHERE 1=1`;
        let params = [];
        
        if (keyword) {
            query += ` AND (title ILIKE $1 OR artist_name ILIKE $1)`;
            params.push(`%${keyword}%`);
        }

        query += sortType === 'popular' ? ` ORDER BY view_count DESC` : ` ORDER BY created_at DESC`;
        query += ` LIMIT 50`;

        const result = await pool.query(query, params);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});


// --- 4. LẤY CHI TIẾT BÀI HÁT ---
router.get('/:id', async (req, res) => {
    try {
        const { id } = req.params;

        const query = `
            SELECT 
                song_id,
                title,
                artist_name,
                genre,
                image_url,
                beat_url,
                lyric_url,
                vocal_url,
                view_count,
                created_at 
            FROM songs
            WHERE song_id = $1
        `;
        
        const result = await pool.query(query, [id]);

        if (result.rows.length === 0) {
            return res.status(404).json({ message: "Không tìm thấy bài hát" });
        }

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Lỗi lấy chi tiết bài hát:", err);
        if (err.code === '22P02') {
             return res.status(400).json({ error: "ID bài hát không hợp lệ" });
        }
        res.status(500).json({ error: "Lỗi Server khi lấy chi tiết bài hát" });
    }
});

module.exports = router;