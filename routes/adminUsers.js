const express = require('express');
const router = express.Router();
const { verifyToken, requireAdmin, requireOwn } = require('../middlewares/auth');
const pool = require('../config/db');
const { createClient } = require('@supabase/supabase-js');
const axios = require('axios');
require('dotenv').config();

const ONESIGNAL_APP_ID = process.env.ONESIGNAL_APP_ID;
const ONESIGNAL_API_KEY = process.env.ONESIGNAL_API_KEY;
// Khởi tạo Supabase Admin
const supabaseAdmin = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { autoRefreshToken: false, persistSession: false } }
);

// --- 1. LẤY DANH SÁCH USER  ---
router.get('/', verifyToken, requireAdmin, async (req, res) => {
    try {
        const requesterRole = req.user.role; 

        let sql = `
            SELECT id, username, email, full_name, role, avatar_url, bio, created_at, locked_until
            FROM users 
            WHERE username IS NOT NULL 
              AND username != ''
              AND role != 'guest'
        `;

        if (requesterRole !== 'own') {
            sql += ` AND role != 'own'`;
        }

        sql += ` ORDER BY created_at DESC`;

        const { rows } = await pool.query(sql);
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
        // Kiểm tra user có username không trước khi thao tác
        const userCheck = await pool.query('SELECT username FROM users WHERE id = $1', [id]);
        if (userCheck.rows.length === 0) return res.status(404).json({ message: 'User không tồn tại' });
        if (!userCheck.rows[0].username) return res.status(400).json({ message: 'Không thể thao tác với tài khoản chưa hoàn tất đăng ký' });

        // 1. Cập nhật trong Database
        const { rows } = await pool.query(
            'UPDATE users SET role = $1 WHERE id = $2 RETURNING *', 
            [role, id]
        );

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
        const targetUser = await pool.query('SELECT role, username FROM users WHERE id = $1', [id]);
        if (targetUser.rows.length === 0) return res.status(404).json({ message: 'User không tồn tại' });
        
        if (!targetUser.rows[0].username) return res.status(400).json({ message: 'Không thể thao tác với tài khoản chưa hoàn tất đăng ký' });

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
    const { duration } = req.body; 
    
    try {
        // Kiểm tra user có username không
        const userCheck = await pool.query('SELECT username FROM users WHERE id = $1', [id]);
        if (userCheck.rows.length === 0) return res.status(404).json({ message: 'User không tồn tại' });
        if (!userCheck.rows[0].username) return res.status(400).json({ message: 'Không thể thao tác với tài khoản chưa hoàn tất đăng ký' });

        let sql = '';
        
        if (duration === 'unlock') {
            sql = 'UPDATE users SET locked_until = NULL WHERE id = $1';
            
        } else {
            const intervalMap = { '1h': '1 hour', '24h': '1 day', '7d': '7 days', 'forever': '100 years' };
            const dbInterval = intervalMap[duration] || '1 hour';
            
            sql = `UPDATE users SET locked_until = (NOW() + interval '${dbInterval}') WHERE id = $1`;
            
            try {
                await supabaseAdmin.auth.admin.signOut(id, 'global');
            } catch (e) {
                console.log("User session cleared or not found.");
            }
        }
        
        await pool.query(sql, [id]);
        
        res.json({ status: 'success', message: 'Thao tác thành công' });
    } catch (err) {
        console.error("Lock Error:", err);
        res.status(500).json({ error: err.message });
    }
});


// --- 5. GỬI TIN NHẮN CHO USER ---
router.post('/:id/message', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    const { title, message, type } = req.body;

    if (!title || !message) {
        return res.status(400).json({ status: 'error', message: 'Vui lòng nhập tiêu đề và nội dung tin nhắn.' });
    }

    try {
        // 1. Kiểm tra User tồn tại
        const userCheck = await pool.query('SELECT id, username FROM users WHERE id = $1', [id]);
        if (userCheck.rows.length === 0) {
            return res.status(404).json({ status: 'error', message: 'Người dùng không tồn tại.' });
        }
        if (!userCheck.rows[0].username) {
            return res.status(400).json({ status: 'error', message: 'Không thể gửi tin nhắn cho tài khoản chưa hoàn tất đăng ký' });
        }

        // 2. Lưu vào Database
        const query = `
            INSERT INTO notifications (user_id, title, message, type, is_read, created_at)
            VALUES ($1, $2, $3, $4, false, NOW())
            RETURNING *
        `;
        
        const notifType = type || 'system';
        const values = [id, title, message, notifType];
        const { rows } = await pool.query(query, values);

        // 3. GỬI THÔNG BÁO ĐẨY (PUSH NOTIFICATION) QUA ONESIGNAL
        try {
            const pushBody = {
                app_id: ONESIGNAL_APP_ID,
                headings: { "en": title, "vi": title },
                contents: { "en": message, "vi": message },
                include_aliases: {
                    external_id: [id] 
                },
                target_channel: "push", 
                data: {
                    type: notifType,
                    notification_id: rows[0].id
                }
            };

            await axios.post('https://onesignal.com/api/v1/notifications', pushBody, {
                headers: {
                    "Content-Type": "application/json; charset=utf-8",
                    "Authorization": `Basic ${ONESIGNAL_API_KEY}`
                }
            });
            console.log(`✅ Đã push thông báo cho user: ${id}`);

        } catch (pushErr) {
            console.error("❌ Lỗi gửi Push OneSignal:", pushErr.response ? pushErr.response.data : pushErr.message);
        }

        // 4. Trả về kết quả thành công
        res.json({ 
            status: 'success', 
            message: 'Đã lưu và gửi tin nhắn thành công', 
            data: rows[0] 
        });

    } catch (err) {
        console.error("Lỗi hệ thống:", err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

module.exports = router;