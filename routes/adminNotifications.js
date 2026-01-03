const express = require('express');
const router = express.Router();
const { verifyToken, requireAdmin } = require('../middlewares/auth');
const pool = require('../config/db');

// GET: Lấy danh sách thông báo hệ thống
router.get('/', verifyToken, requireAdmin, async (req, res) => {
    try {
        const sql = `
            SELECT id, title, message, created_at, 'system' as type
            FROM system_notifications
            ORDER BY created_at DESC
        `;
        
        const { rows } = await pool.query(sql);
        
        res.json({
            status: 'success',
            data: rows
        });
    } catch (err) {
        console.error("Error fetching system notifications:", err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

// POST: Tạo thông báo hệ thống mới
router.post('/', verifyToken, requireAdmin, async (req, res) => {
    const { title, message } = req.body;

    if (!title || !message) {
        return res.status(400).json({ status: 'error', message: 'Thiếu title hoặc message' });
    }

    try {
        // Chỉ insert title và message. ID tự tăng, created_at tự tạo.
        const sql = `
            INSERT INTO system_notifications (title, message)
            VALUES ($1, $2)
            RETURNING *
        `;
        
        const { rows } = await pool.query(sql, [title, message]);
        
        res.json({
            status: 'success',
            message: 'Tạo thông báo thành công',
            data: rows[0]
        });
    } catch (err) {
        console.error("Error creating notification:", err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

// PUT: Cập nhật thông báo hệ thống
router.put('/:id', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    const { title, message } = req.body;

    if (!title || !message) {
        return res.status(400).json({ status: 'error', message: 'Thiếu title hoặc message' });
    }

    try {
        const sql = `
            UPDATE system_notifications 
            SET title = $1, message = $2
            WHERE id = $3
            RETURNING *
        `;
        
        const { rows, rowCount } = await pool.query(sql, [title, message, id]);

        if (rowCount === 0) {
            return res.status(404).json({ status: 'error', message: 'Không tìm thấy thông báo để sửa' });
        }

        res.json({
            status: 'success',
            message: 'Cập nhật thành công',
            data: rows[0]
        });
    } catch (err) {
        console.error("Error updating notification:", err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

// DELETE: Xóa thông báo hệ thống
router.delete('/:id', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;

    try {
        // Xóa trong bảng system_notifications. 
        // Do bạn đã set CASCADE ở bảng system_read_status, nó sẽ tự sạch data bên kia.
        const sql = 'DELETE FROM system_notifications WHERE id = $1 RETURNING id';
        const { rowCount } = await pool.query(sql, [id]);

        if (rowCount === 0) {
            return res.status(404).json({ status: 'error', message: 'Không tìm thấy thông báo' });
        }

        res.json({ status: 'success', message: 'Đã xóa thông báo' });
    } catch (err) {
        console.error("Error deleting notification:", err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

module.exports = router;