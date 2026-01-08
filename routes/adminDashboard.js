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

// --- 2. LẤY SỐ NGƯỜI ONLINE ---
router.get('/stats/online', verifyToken, requireAdmin, async (req, res) => {
    try {
        const query = `
            SELECT id, avatar_url, full_name, username, role, last_active_at 
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


// --- 3. LẤY LỊCH SỬ NGƯỜI DÙNG HOẠT ĐỘNG TRONG 24 GIỜ QUA ---
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

module.exports = router;