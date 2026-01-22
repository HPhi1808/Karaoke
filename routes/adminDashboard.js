const express = require('express');
const router = express.Router();
const { verifyToken, requireAdmin } = require('../middlewares/auth');
const pool = require('../config/db');

// --- 1. LẤY SỐ LIỆU TỔNG QUAN  ---
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
        const allActive = result.rows;

        // Phân loại
        const activeMembers = allActive.filter(u => u.role !== 'guest');
        const activeGuests = allActive.filter(u => u.role === 'guest');
        
        res.json({
            status: 'success',
            data: {
                total: allActive.length,
                members: activeMembers.length,
                guests: activeGuests.length,
                users_list: allActive
            }
        });
    } catch (err) {
        console.error(err);
        res.json({ 
            status: 'error', 
            data: { total: 0, members: 0, guests: 0, users_list: [] } 
        });
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


// --- 4. THỐNG KÊ TĂNG TRƯỞNG TRONG 7 NGÀY QUA ---
router.get('/stats/growth', verifyToken, requireAdmin, async (req, res) => {
    try {
        const timeFrame = "NOW() - INTERVAL '7 days'";

        // 1. User mới
        const newUsersQuery = `SELECT COUNT(*) FROM users WHERE created_at >= (${timeFrame}) AND role = 'user'`;
        
        // 2. Bài đăng (Moment) mới
        const newMomentsQuery = `SELECT COUNT(*) FROM moments WHERE created_at >= (${timeFrame})`;

        // 3. Bài hát (Song) mới [MỚI THÊM]
        const newSongsQuery = `SELECT COUNT(*) FROM songs WHERE created_at >= (${timeFrame})`;

        const [usersRes, momentsRes, songsRes] = await Promise.all([
            pool.query(newUsersQuery),
            pool.query(newMomentsQuery),
            pool.query(newSongsQuery)
        ]);

        res.json({
            status: 'success',
            data: {
                new_users_7d: parseInt(usersRes.rows[0].count),
                new_moments_7d: parseInt(momentsRes.rows[0].count),
                new_songs_7d: parseInt(songsRes.rows[0].count)
            }
        });

    } catch (err) {
        console.error("Lỗi thống kê tăng trưởng:", err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

module.exports = router;