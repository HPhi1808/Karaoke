const express = require('express');
const router = express.Router();
const { verifyToken, requireAdmin } = require('../middlewares/auth');
const pool = require('../config/db');
const axios = require('axios');
require('dotenv').config();

// CẤU HÌNH ONESIGNAL
const ONESIGNAL_APP_ID = process.env.ONESIGNAL_APP_ID;
const ONESIGNAL_API_KEY = process.env.ONESIGNAL_API_KEY;

// Hàm gửi thông báo (Helper)
async function sendPushNotification(title, message, target) {
    const headers = {
        "Content-Type": "application/json; charset=utf-8",
        "Authorization": `Basic ${ONESIGNAL_API_KEY}`
    };

    let body = {
        app_id: ONESIGNAL_APP_ID,
        headings: { "en": title, "vi": title },
        contents: { "en": message, "vi": message },
    };

    // Xử lý logic chọn đối tượng
    if (target === 'user') {
        // Chỉ gửi cho User đã đăng ký (Dựa vào Tag: role = user)
        body.filters = [
            { field: "tag", key: "role", relation: "=", value: "user" }
        ];
    } else {
        // Gửi cho TẤT CẢ (Bao gồm cả Guest)
        body.included_segments = ["All"];
    }

    try {
        await axios.post('https://onesignal.com/api/v1/notifications', body, { headers });
        console.log(`✅ Push sent to [${target}]`);
    } catch (error) {
        console.error("❌ Push failed:", error.response ? error.response.data : error.message);
    }
}

// GET: Lấy danh sách thông báo
router.get('/', verifyToken, requireAdmin, async (req, res) => {
    try {
        const sql = `
            SELECT id, title, message, created_at, 'system' as type
            FROM system_notifications
            ORDER BY created_at DESC
        `;
        const { rows } = await pool.query(sql);
        res.json({ status: 'success', data: rows });
    } catch (err) {
        res.status(500).json({ status: 'error', message: err.message });
    }
});

// POST: Tạo thông báo mới
router.post('/', verifyToken, requireAdmin, async (req, res) => {
    // Nhận thêm tham số target ('all' hoặc 'user')
    const { title, message, target } = req.body; 

    if (!title || !message) {
        return res.status(400).json({ status: 'error', message: 'Thiếu thông tin' });
    }

    const targetAudience = target || 'all'; // Mặc định là tất cả nếu không chọn

    try {
        // 1. Lưu vào Database
        const sql = `
            INSERT INTO system_notifications (title, message)
            VALUES ($1, $2)
            RETURNING *
        `;
        const { rows } = await pool.query(sql, [title, message]);

        // 2. Gửi Push Notification qua OneSignal
        sendPushNotification(title, message, targetAudience);
        
        res.json({
            status: 'success',
            message: 'Đã tạo và đang gửi thông báo...',
            data: rows[0]
        });
    } catch (err) {
        console.error("Error creating notification:", err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

// PUT: Cập nhật thông báo
router.put('/:id', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    const { title, message } = req.body;

    if (!title || !message) return res.status(400).json({ status: 'error', message: 'Thiếu dữ liệu' });

    try {
        const sql = `
            UPDATE system_notifications 
            SET title = $1, message = $2
            WHERE id = $3
            RETURNING *
        `;
        const { rows, rowCount } = await pool.query(sql, [title, message, id]);

        if (rowCount === 0) return res.status(404).json({ status: 'error', message: 'Không tìm thấy' });

        res.json({ status: 'success', message: 'Cập nhật thành công', data: rows[0] });
    } catch (err) {
        res.status(500).json({ status: 'error', message: err.message });
    }
});

// DELETE: Xóa thông báo
router.delete('/:id', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    try {
        const sql = 'DELETE FROM system_notifications WHERE id = $1 RETURNING id';
        const { rowCount } = await pool.query(sql, [id]);

        if (rowCount === 0) return res.status(404).json({ status: 'error', message: 'Không tìm thấy' });

        res.json({ status: 'success', message: 'Đã xóa thông báo' });
    } catch (err) {
        res.status(500).json({ status: 'error', message: err.message });
    }
});

module.exports = router;