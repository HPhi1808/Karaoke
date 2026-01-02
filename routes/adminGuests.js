const express = require('express');
const router = express.Router();
const { verifyToken, requireAdmin } = require('../middlewares/auth');
const pool = require('../config/db');


// --- LẤY DANH SÁCH TẤT CẢ GUEST ---
router.get('/', verifyToken, requireAdmin, async (req, res) => {
    try {
        // 1. Lấy tham số phân trang từ URL
        const page = parseInt(req.query.page) || 1;
        const limit = parseInt(req.query.limit) || 50;
        const offset = (page - 1) * limit; // Vị trí bắt đầu lấy trong Database

        // 2. Query lấy dữ liệu (Sắp xếp người mới tạo lên đầu)
        const sqlUsers = `
            SELECT id, username, created_at, last_active_at, role
            FROM users 
            WHERE role = 'guest' 
            ORDER BY created_at DESC 
            LIMIT $1 OFFSET $2
        `;

        // 3. Query đếm tổng số guest
        const sqlCount = `SELECT COUNT(*) FROM users WHERE role = 'guest'`;

        // Chạy song song 2 câu lệnh cho nhanh (như đã bàn về Pool)
        const [usersRes, countRes] = await Promise.all([
            pool.query(sqlUsers, [limit, offset]),
            pool.query(sqlCount)
        ]);

        const totalGuests = parseInt(countRes.rows[0].count);

        res.json({
            status: 'success',
            data: usersRes.rows,
            pagination: {
                current_page: page,
                limit: limit,
                total_records: totalGuests,
                total_pages: Math.ceil(totalGuests / limit)
            }
        });
    } catch (err) {
        res.status(500).json({ status: 'error', message: err.message });
    }
});


// --- LẤY DANH SÁCH GUEST KHÔNG HOẠT ĐỘNG (Inactive Guests) ---
router.get('/inactive', verifyToken, requireAdmin, async (req, res) => {
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

// --- XÓA MỘT GUEST CỤ THỂ ---
router.delete('/:id', verifyToken, requireAdmin, async (req, res) => {
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