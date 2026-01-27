const express = require('express');
const router = express.Router();
const pool = require('../config/db');
const { verifyToken, requireAdmin } = require('../middlewares/auth');
const { deleteFromR2 } = require('../services/uploadService');

// --- 1. LẤY DANH SÁCH MOMENTS ---
router.get('/', verifyToken, requireAdmin, async (req, res) => {
    try {
        const query = `
            SELECT 
                m.moment_id, 
                m.user_id, 
                m.audio_url, 
                m.description, 
                m.view_count, 
                m.created_at, 
                m.visibility,
                
                -- Thông tin người đăng
                u.email,
                u.raw_user_meta_data->>'full_name' as full_name,
                u.raw_user_meta_data->>'avatar_url' as avatar_url,

                -- Thống kê (Subquery cho chính xác)
                (SELECT COUNT(*) FROM moment_likes WHERE moment_id = m.moment_id) as like_count,
                (SELECT COUNT(*) FROM moment_comments WHERE moment_id = m.moment_id) as comment_count

            FROM moments m
            JOIN auth.users u ON m.user_id = u.id
            ORDER BY m.created_at DESC
        `;
        const { rows } = await pool.query(query);
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// --- 2. XÓA MOMENT (Và file trên R2) ---
// Route này dùng cho cả trang Moments và Reports (khi chọn xóa bài đăng)
router.delete('/:id', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    try {
        // 1. Lấy thông tin để xóa file R2 trước
        const resMoment = await pool.query('SELECT audio_url FROM moments WHERE moment_id = $1', [id]);
        if (resMoment.rows.length === 0) {
            return res.status(404).json({ message: 'Moment không tồn tại' });
        }
        
        const audioUrl = resMoment.rows[0].audio_url;

        // 2. Xóa record trong DB (Cascade sẽ tự xóa comment/like liên quan)
        await pool.query('DELETE FROM moments WHERE moment_id = $1', [id]);

        // 3. Xóa file trên Cloud (R2)
        if (audioUrl) {
            await deleteFromR2(audioUrl);
        }

        res.json({ status: 'success', message: 'Đã xóa moment thành công' });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: err.message });
    }
});

// --- 3. LẤY DANH SÁCH COMMENT CỦA 1 MOMENT ---
// Dùng để hiện trong Modal chi tiết
router.get('/:id/comments', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    try {
        const query = `
            SELECT 
                c.id, c.content, c.created_at,
                u.email,
                u.raw_user_meta_data->>'full_name' as full_name,
                u.raw_user_meta_data->>'avatar_url' as avatar_url
            FROM moment_comments c
            JOIN auth.users u ON c.user_id = u.id
            WHERE c.moment_id = $1
            ORDER BY c.created_at DESC
        `;
        const { rows } = await pool.query(query, [id]);
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// --- 4. XÓA COMMENT ---
// Route này dùng cho Modal Moments và Reports (khi chọn xóa bình luận)
router.delete('/comments/:commentId', verifyToken, requireAdmin, async (req, res) => {
    const { commentId } = req.params;
    try {
        const result = await pool.query('DELETE FROM moment_comments WHERE id = $1 RETURNING id', [commentId]);
        
        if (result.rows.length === 0) {
            return res.status(404).json({ message: 'Comment không tồn tại' });
        }

        res.json({ status: 'success', message: 'Đã xóa bình luận' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;