const express = require('express');
const router = express.Router();
const { verifyToken, requireAdmin } = require('../middlewares/auth');
const pool = require('../config/db');

// --- 1. LẤY SỐ LIỆU TỔNG QUAN (Chạy 1 lần lúc load trang) ---
router.get('/stats/general', verifyToken, requireAdmin, async (req, res) => {
    try {
        const [usersRes, guestsRes] = await Promise.all([
            pool.query("SELECT COUNT(*) FROM users WHERE role = 'user' AND username IS NOT NULL"),
            pool.query("SELECT COUNT(*) FROM users WHERE role = 'guest'")
        ]);

        res.json({
            status: 'success',
            data: {
                total_users: parseInt(usersRes.rows[0].count),
                total_guests: parseInt(guestsRes.rows[0].count)
            }
        });
    } catch (err) {
        res.status(500).json({ status: 'error', message: err.message });
    }
});

// --- 2. LẤY SỐ NGƯỜI ONLINE (Realtime - Gọi mỗi 30s) ---
router.get('/stats/online', verifyToken, requireAdmin, async (req, res) => {
    try {
        const query = `
            SELECT id, username, role, last_active_at 
            FROM users 
            WHERE last_active_at > (NOW() - INTERVAL '7 minutes')
            ORDER BY last_active_at DESC
        `;
        
        const result = await pool.query(query);
        
        res.json({
            status: 'success',
            online: result.rows.length,
            users: result.rows
        });
    } catch (err) {
        console.error(err);
        res.json({ status: 'error', online: 0, users: [] });
    }
});


router.get('/active-history', verifyToken, requireAdmin, async (req, res) => {
    try {
        const queryText = `
            SELECT recorded_at, active_count
            FROM active_users_history
            WHERE recorded_at >= (NOW() - INTERVAL '24 hours')
            ORDER BY recorded_at ASC
        `;

        const { rows } = await pool.query(queryText);

        res.json(rows);
    } catch (err) {
        console.error("Lỗi lấy lịch sử hoạt động:", err);
        res.status(500).json({ error: err.message });
    }
});
// --- 3. LẤY DANH SÁCH GUEST KHÔNG HOẠT ĐỘNG (Inactive Guests) ---
router.get('/guests/inactive', verifyToken, requireAdmin, async (req, res) => {
    try {
        // Lấy Guest không hoạt động > 30 ngày
        // Tính luôn số ngày đã trôi qua (days_inactive)
        const sql = `
            SELECT id, username, created_at, last_active_at,
            EXTRACT(DAY FROM (NOW() - last_active_at))::int as days_inactive
            FROM users 
            WHERE role = 'guest' 
            AND last_active_at < (NOW() - INTERVAL '30 days')
            ORDER BY last_active_at ASC
            LIMIT 100 -- Giới hạn 100 người để không làm lag giao diện
        `;
        
        const { rows } = await pool.query(sql);
        res.json({ status: 'success', data: rows });
    } catch (err) {
        res.status(500).json({ status: 'error', message: err.message });
    }
});

// --- 4. XÓA MỘT GUEST CỤ THỂ ---
router.delete('/guests/:id', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    try {
        // Kiểm tra xem có đúng là guest không để tránh xóa nhầm user thật
        const check = await pool.query("SELECT role FROM users WHERE id = $1", [id]);
        if (check.rows.length === 0) return res.status(404).json({ message: 'User không tồn tại' });
        if (check.rows[0].role !== 'guest') return res.status(403).json({ message: 'Chỉ được phép xóa tài khoản Guest tại đây' });

        // Trigger 'on_public_user_deleted' sẽ tự lo phần auth.users
        await pool.query("DELETE FROM users WHERE id = $1", [id]);

        res.json({ status: 'success', message: 'Đã xóa guest thành công' });
    } catch (err) {
        res.status(500).json({ status: 'error', message: err.message });
    }
});

module.exports = router;