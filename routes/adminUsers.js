const express = require('express');
const router = express.Router();
const { verifyToken, requireAdmin, requireOwn } = require('../middlewares/auth');
const pool = require('../config/db');
const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

// Khởi tạo Supabase Admin
const supabaseAdmin = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { autoRefreshToken: false, persistSession: false } }
);

// --- 1. LẤY DANH SÁCH USER ---
router.get('/', verifyToken, requireAdmin, async (req, res) => {
    try {
        const { rows } = await pool.query(`
            SELECT id, username, email, full_name, role, avatar_url, bio, created_at, locked_until
            FROM users 
            ORDER BY created_at DESC
        `);
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// --- 2. ĐỔI ROLE ---
router.patch('/:id/role', verifyToken, requireOwn, async (req, res) => {
    const { id } = req.params;
    const { role } = req.body;

    try {
        // 1. Cập nhật trong Database
        const { rows } = await pool.query(
            'UPDATE users SET role = $1 WHERE id = $2 RETURNING *', 
            [role, id]
        );

        if (rows.length === 0) return res.status(404).json({ message: 'User không tồn tại' });

        // 2. Cập nhật trong Supabase Auth
        await supabaseAdmin.auth.admin.updateUserById(id, { 
            user_metadata: { role: role } 
        });

        res.json({ status: 'success', message: 'Cập nhật role thành công', user: rows[0] });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: err.message });
    }
});

// --- 3. XÓA USER ---
router.delete('/:id', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    const requesterId = req.user.user_id;
    const requesterRole = req.user.role;

    try {
        // Kiểm tra user mục tiêu
        const targetUser = await pool.query('SELECT role FROM users WHERE id = $1', [id]);
        if (targetUser.rows.length === 0) return res.status(404).json({ message: 'User không tồn tại' });
        
        const targetRole = targetUser.rows[0].role;

        // Logic bảo vệ
        if (requesterRole === 'admin' && (targetRole === 'admin' || targetRole === 'own')) {
            return res.status(403).json({ message: 'Bạn không đủ quyền để xóa tài khoản này' });
        }
        if (id === requesterId) return res.status(400).json({ message: 'Không thể tự xóa chính mình tại đây' });

        // 1. Xóa khỏi Supabase Auth trước
        const { error } = await supabaseAdmin.auth.admin.deleteUser(id);
        if (error) throw error;

        // 2. Xóa khỏi Database
        await pool.query('DELETE FROM users WHERE id = $1', [id]);

        res.json({ status: 'success', message: 'Đã xóa user thành công' });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: err.message });
    }
});

// --- 4. KHÓA / MỞ KHÓA TÀI KHOẢN ---
router.post('/:id/lock', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    const { duration } = req.body; // '1h', '24h', 'unlock', 'forever'
    
    try {
        let sql = '';
        if (duration === 'unlock') {
            // Mở khóa DB
            sql = 'UPDATE users SET locked_until = NULL WHERE id = $1';
            // Mở khóa Supabase
            await supabaseAdmin.auth.admin.updateUserById(id, { ban_duration: "none" });
        } else {
            // Tính thời gian cho DB
            const intervalMap = { '1h': '1 hour', '24h': '1 day', '7d': '7 days', 'forever': '100 years' };
            const dbInterval = intervalMap[duration] || '1 hour';
            sql = `UPDATE users SET locked_until = (NOW() + interval '${dbInterval}') WHERE id = $1`;
            
            // Tính thời gian cho Supabase Auth
            let banTime = "1h";
            if (duration === '24h') banTime = "24h";
            if (duration === '7d') banTime = "168h";
            if (duration === 'forever') banTime = "876000h";

            await supabaseAdmin.auth.admin.updateUserById(id, { ban_duration: banTime });
        }
        
        await pool.query(sql, [id]);
        res.json({ status: 'success', message: 'Thao tác thành công' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});


// --- 5. GỬI TIN NHẮN CHO USER ---
router.post('/:id/message', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    const { title, message, type } = req.body;

    // Validate dữ liệu đầu vào
    if (!title || !message) {
        return res.status(400).json({ status: 'error', message: 'Vui lòng nhập tiêu đề và nội dung tin nhắn.' });
    }

    try {
        // 1. Kiểm tra xem User có tồn tại không
        const userCheck = await pool.query('SELECT id FROM users WHERE id = $1', [id]);
        if (userCheck.rows.length === 0) {
            return res.status(404).json({ status: 'error', message: 'Người dùng không tồn tại.' });
        }

        // 2. Chèn tin nhắn vào bảng notifications
        const query = `
            INSERT INTO notifications (user_id, title, message, type, is_read, created_at)
            VALUES ($1, $2, $3, $4, false, NOW())
            RETURNING *
        `;
        
        const values = [id, title, message, type || 'system'];
        
        const { rows } = await pool.query(query, values);

        res.json({ 
            status: 'success', 
            message: 'Đã gửi tin nhắn thành công', 
            data: rows[0] 
        });

    } catch (err) {
        console.error("Lỗi gửi tin nhắn:", err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

module.exports = router;