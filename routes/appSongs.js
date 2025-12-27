const express = require('express');
const router = express.Router();
const pool = require('../config/db');

// --- 1. LẤY DỮ LIỆU HOME ---
router.get('/home', async (req, res) => {
    try {
        const limit = 10;
        // Sử dụng Promise.all để chạy 3 câu lệnh song song
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
        console.error("Lỗi API /home:", err);
        res.status(500).json({ error: 'Lỗi tải trang chủ' });
    }
});

// --- 2. TÍNH VIEW ---
router.post('/:id/view', async (req, res) => {
    const { id: songId } = req.params;
    
    // Lấy IP người dùng 
    const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress; 
    const userId = req.body.user_id || null;

    try {
        // A. Kiểm tra xem IP này đã xem bài này trong 1 giờ qua chưa
        const checkQuery = `
            SELECT created_at FROM song_views 
            WHERE song_id = $1 AND ip_address = $2 
            ORDER BY created_at DESC LIMIT 1
        `;
        const checkResult = await pool.query(checkQuery, [songId, ip]);

        if (checkResult.rows.length > 0) {
            const lastViewTime = new Date(checkResult.rows[0].created_at);
            const now = new Date();
            const diffMinutes = (now - lastViewTime) / (1000 * 60);

            // Nếu chưa qua 60 phút -> KHÔNG CỘNG VIEW
            if (diffMinutes < 60) {
                return res.json({ status: 'ignored', message: 'View already counted recently' });
            }
        }

        // B. Nếu hợp lệ -> Ghi log vào song_views VÀ cộng view vào songs
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

module.exports = router;