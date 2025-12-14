const express = require('express');
const router = express.Router();
const pool = require('../config/db');

// --- 1. LẤY DANH SÁCH BÀI HÁT
router.get('/', async (req, res) => {
    try {
        // Lấy tham số từ App gửi lên
        const keyword = req.query.q;
        const sortType = req.query.sort;

        let query = `
            SELECT song_id, title, artist_name, genre, image_url, beat_url, lyric_url, vocal_url, view_count, created_at 
            FROM songs 
            WHERE 1=1 
        `;
        let params = [];

        // Tìm kiếm (Nếu có từ khóa)
        if (keyword) {
            query += ` AND (title ILIKE $1 OR artist_name ILIKE $1)`;
            params.push(`%${keyword}%`);
        }

        // Sắp xếp
        if (sortType === 'popular') {
            // Sắp xếp theo lượt xem giảm dần (Bài Hot)
            query += ` ORDER BY view_count DESC`;
        } else {
            // Mặc định: Sắp xếp theo ngày tạo mới nhất
            query += ` ORDER BY created_at DESC`;
        }

        // Giới hạn trả về 50 bài thôi để App đỡ lag (Pagination đơn giản)
        query += ` LIMIT 50`;

        const result = await pool.query(query, params);
        res.json(result.rows);

    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Lỗi lấy danh sách bài hát' });
    }
});

// --- 2. TĂNG LƯỢT XEM (View Count) ---
// App gọi API này khi người dùng bấm vào bài hát để hát
// GET /api/app/songs/:id/view
router.post('/:id/view', async (req, res) => {
    const { id } = req.params;
    try {
        // Cộng thêm 1 vào view_count
        await pool.query('UPDATE songs SET view_count = view_count + 1 WHERE song_id = $1', [id]);
        res.json({ status: 'success', message: 'Đã tăng lượt xem' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// --- 3. LẤY CHI TIẾT 1 BÀI HÁT (Optional) ---
router.get('/:id', async (req, res) => {
    const { id } = req.params;
    try {
        const result = await pool.query('SELECT * FROM songs WHERE song_id = $1', [id]);
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Không tìm thấy bài hát' });
        }
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;