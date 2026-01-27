const express = require('express');
const router = express.Router();
const pool = require('../config/db');
const { verifyToken } = require('../middlewares/auth');
const { deleteFromR2 } = require('../services/uploadService');

// --- API XÓA MOMENT (KÈM XÓA FILE R2) ---
// Method: DELETE
// Endpoint: /api/user/moments/:id
router.delete('/:id', verifyToken, async (req, res) => {
    const momentId = req.params.id;
    const userId = req.user.user_id;

    try {
        const checkQuery = `SELECT moment_id, user_id, audio_url FROM moments WHERE moment_id = $1`;
        const checkRes = await pool.query(checkQuery, [momentId]);

        if (checkRes.rows.length === 0) {
            return res.status(404).json({ success: false, message: "Bài viết không tồn tại." });
        }

        const moment = checkRes.rows[0];

        // BƯỚC 2: Kiểm tra chính chủ (Bảo mật)
        if (moment.user_id !== userId) {
            return res.status(403).json({ success: false, message: "Bạn không có quyền xóa bài viết này." });
        }

        // BƯỚC 3: Xóa file trên Cloudflare R2
        if (moment.audio_url) {
            try {
                await deleteFromR2(moment.audio_url);
                console.log(`🗑️ Đã xóa file R2: ${moment.audio_url}`);
            } catch (r2Error) {
                console.error("⚠️ Lỗi xóa file R2 (vẫn tiếp tục xóa DB):", r2Error.message);
            }
        }

        // BƯỚC 4: Xóa record trong Database
        await pool.query('DELETE FROM moments WHERE moment_id = $1', [momentId]);

        res.json({ success: true, message: "Đã xóa bài viết thành công." });

    } catch (err) {
        console.error("Lỗi xóa moment:", err);
        res.status(500).json({ success: false, message: "Lỗi Server: " + err.message });
    }
});


// --- API SỬA MOMENT ---
// Method: PUT
// Endpoint: /api/user/moments/:id
router.put('/:id', verifyToken, async (req, res) => {
    const momentId = req.params.id;
    const userId = req.user.user_id;
    const { description, visibility } = req.body;

    try {
        // 1. Kiểm tra bài viết có tồn tại và thuộc về user không
        const check = await pool.query(
            'SELECT moment_id FROM moments WHERE moment_id = $1 AND user_id = $2', 
            [momentId, userId]
        );

        if (check.rows.length === 0) {
            return res.status(403).json({ success: false, message: "Không tìm thấy bài viết hoặc bạn không có quyền sửa." });
        }

        // 2. Cập nhật
        const updateQuery = `
            UPDATE moments 
            SET description = $1, visibility = $2
            WHERE moment_id = $3
            RETURNING *
        `;
        
        const result = await pool.query(updateQuery, [description, visibility, momentId]);

        res.json({ 
            success: true, 
            message: "Cập nhật thành công", 
            data: result.rows[0] 
        });

    } catch (err) {
        console.error("Lỗi sửa moment:", err);
        res.status(500).json({ success: false, message: "Lỗi server: " + err.message });
    }
});

module.exports = router;