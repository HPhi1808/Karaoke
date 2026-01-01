const express = require('express');
const router = express.Router();
const { verifyToken, requireAdmin } = require('../middlewares/auth');
const pool = require('../config/db');

// --- 1. LẤY SỐ LIỆU TỔNG QUAN (Chạy 1 lần lúc load trang) ---
// API này nặng (count toàn bộ), chỉ nên gọi khi mới vào dashboard
router.get('/stats/general', verifyToken, requireAdmin, async (req, res) => {
    try {
        const [usersRes, guestsRes] = await Promise.all([
            pool.query("SELECT COUNT(*) FROM users WHERE role != 'guest'"),
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
// API này nhẹ, chỉ count trong khoảng thời gian ngắn
router.get('/stats/online', verifyToken, requireAdmin, async (req, res) => {
    try {
        // Đếm user có hoạt động trong 5 phút qua
        const result = await pool.query("SELECT COUNT(*) FROM users WHERE last_active_at > (NOW() - INTERVAL '5 minutes')");
        
        res.json({
            status: 'success',
            online: parseInt(result.rows[0].count)
        });
    } catch (err) {
        console.error(err); // Log lỗi nhưng không cần gửi 500 để tránh spam client
        res.json({ status: 'error', online: 0 }); 
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