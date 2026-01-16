const express = require('express');
const router = express.Router();
const pool = require('../config/db');
const { verifyToken, requireAdmin } = require('../middlewares/auth');
const { createAndSendNotification } = require('../services/notificationService');

// --- 1. LẤY DANH SÁCH BÁO CÁO ---
// routes/adminReports.js

router.get('/', verifyToken, requireAdmin, async (req, res) => {
    try {
        const query = `
            SELECT 
                r.id, r.reporter_id, r.target_type, r.target_id, 
                r.reason, r.description, r.status, r.created_at,
                
                -- 1. Thông tin NGƯỜI BÁO CÁO (reporter)
                u.email as reporter_email,
                u.raw_user_meta_data->>'full_name' as reporter_name,
                u.raw_user_meta_data->>'avatar_url' as reporter_avatar,

                -- 2. Thông tin BÀI HÁT (nếu target là song)
                s.title as song_title,
                s.artist_name as song_artist,
                s.image_url as song_image,

                -- 3. Thông tin NGƯỜI BỊ BÁO CÁO (Target User)
                tu.email as target_user_email,
                tu.raw_user_meta_data->>'full_name' as target_user_name,
                tu.raw_user_meta_data->>'avatar_url' as target_user_avatar,

                res_user.email as resolver_email,
                res_user.raw_user_meta_data->>'full_name' as resolver_name

            FROM reports r
            -- Join lấy người báo cáo
            LEFT JOIN auth.users u ON r.reporter_id = u.id
            
            -- Join lấy bài hát (so sánh text = text)
            LEFT JOIN songs s ON (
                r.target_type = 'song' 
                AND r.target_id = s.song_id::text 
            )

            -- Join lấy User bị báo cáo
            LEFT JOIN auth.users tu ON (
                r.target_type = 'user'
                AND r.target_id = tu.id::text
            )
            -- Join lấy người xử lý báo cáo
            LEFT JOIN auth.users res_user ON r.resolver_id = res_user.id

            ORDER BY 
                CASE WHEN r.status = 'pending' THEN 1 ELSE 2 END,
                r.created_at DESC
        `;

        const result = await pool.query(query);
        res.json(result.rows);

    } catch (err) {
        console.error("Lỗi lấy danh sách report:", err);
        res.status(500).json({ error: err.message });
    }
});

// --- 2. CẬP NHẬT TRẠNG THÁI REPORT ---
router.put('/:id', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    const { status } = req.body;
    
    const adminId = req.user.user_id;

    if (!['pending', 'resolved', 'rejected'].includes(status)) {
        return res.status(400).json({ message: 'Trạng thái không hợp lệ' });
    }

    try {
        // 1. CẬP NHẬT REPORT
        const result = await pool.query(
            `UPDATE reports 
             SET status = $1, resolver_id = $3 
             WHERE id = $2 
             RETURNING *`,
            [status, id, adminId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ message: 'Không tìm thấy báo cáo' });
        }

        const report = result.rows[0];
        
        // 2. LOGIC TẠO THÔNG BÁO (Chỉ chạy nếu đã xử lý xong và có người báo cáo)
        if (status !== 'pending' && report.reporter_id) {
            
            // --- A. Lấy tên đối tượng (Bài hát hoặc User) ---
            let targetName = report.target_id;
            
            try {
                if (report.target_type === 'song') {
                    if (/^\d+$/.test(report.target_id)) {
                        const songRes = await pool.query(`SELECT title FROM songs WHERE song_id = $1`, [report.target_id]);
                        if (songRes.rows.length > 0) targetName = songRes.rows[0].title;
                    }
                } else if (report.target_type === 'user') {
                    const userRes = await pool.query(`SELECT raw_user_meta_data->>'full_name' as name FROM auth.users WHERE id = $1`, [report.target_id]);
                    if (userRes.rows.length > 0) targetName = userRes.rows[0].name || 'Người dùng';
                }
            } catch (e) {
                console.error("⚠️ Lỗi lấy tên target cho thông báo (không ảnh hưởng luồng chính):", e.message);
            }

            // --- Soạn nội dung tin nhắn ---
            const typeText = report.target_type === 'song' ? 'bài hát' : 'người dùng';
            
            let actionText = '';
            if (status === 'resolved') {
                actionText = 'đã được xử lý!';
            } else if (status === 'rejected') {
                actionText = 'đã bị từ chối xử lý!';
            }

            const notifTitle = "Kết quả báo cáo";
            const notifMessage = `Báo cáo của bạn về ${typeText}: "${targetName}" ${actionText}.`;

            // --- C. Gọi Service tạo thông báo ---
            createAndSendNotification({
                userId: report.reporter_id,
                title: notifTitle,
                message: notifMessage,
                type: 'system',
                actorId: adminId,
                data: {
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                    targetType: report.target_type,
                    reportId: report.id,
                    status: status
                }
            });
        }

        res.json({ status: 'success', data: report });

    } catch (err) {
        console.error("Lỗi cập nhật report:", err);
        res.status(500).json({ error: err.message });
    }
});

// --- 3. THỐNG KÊ NHANH (Số lượng Pending) ---
router.get('/count-pending', verifyToken, requireAdmin, async (req, res) => {
    try {
        const result = await pool.query("SELECT COUNT(*) FROM reports WHERE status = 'pending'");
        res.json({ count: parseInt(result.rows[0].count) });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;