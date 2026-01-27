const express = require('express');
const router = express.Router();
const pool = require('../config/db');
const { verifyToken, requireAdmin } = require('../middlewares/auth');
const { createAndSendNotification } = require('../services/notificationService');

// --- 1. LẤY DANH SÁCH BÁO CÁO ---
// routes/adminReports.js

// routes/adminReports.js

router.get('/', verifyToken, requireAdmin, async (req, res) => {
    try {
        const query = `
            SELECT 
                r.id, r.reporter_id, r.target_type, r.target_id, 
                r.reason, r.description, r.status, r.created_at,
                
                -- 1. Thông tin NGƯỜI BÁO CÁO (Lấy từ public.users)
                u.email as reporter_email,
                u.full_name as reporter_name,
                u.avatar_url as reporter_avatar,

                -- 2. Thông tin BÀI HÁT
                s.title as song_title,
                s.artist_name as song_artist,
                s.image_url as song_image,

                -- 3. Thông tin NGƯỜI BỊ BÁO CÁO (Target User - public.users)
                tu.email as target_user_email,
                tu.full_name as target_user_name,
                tu.avatar_url as target_user_avatar,

                -- 4. Thông tin MOMENT
                m.description as moment_desc,
                m.audio_url as moment_audio,
                m.user_id as moment_owner_id,
                mu.full_name as moment_owner_name, -- (Lấy từ public.users)
                
                -- 5. Thông tin COMMENT
                mc.content as comment_content,
                mc.moment_id as comment_moment_id,
                mc.user_id as comment_owner_id,
                cu.email as comment_owner_email, 
                cu.full_name as comment_owner_name, -- (Lấy từ public.users)
                cu.avatar_url as comment_owner_avatar,

                -- Người xử lý báo cáo
                res_user.email as resolver_email,
                res_user.full_name as resolver_name

            FROM reports r
            -- Thay auth.users bằng public.users
            LEFT JOIN public.users u ON r.reporter_id = u.id
            
            LEFT JOIN songs s ON (r.target_type = 'song' AND r.target_id = s.song_id::text)
            
            -- Thay auth.users bằng public.users
            LEFT JOIN public.users tu ON (r.target_type = 'user' AND r.target_id = tu.id::text)
            
            LEFT JOIN moments m ON (r.target_type = 'moment' AND r.target_id = m.moment_id::text)
            -- Thay auth.users bằng public.users
            LEFT JOIN public.users mu ON m.user_id = mu.id 
            
            LEFT JOIN moment_comments mc ON (r.target_type = 'comment' AND r.target_id = mc.id::text)
            -- Thay auth.users bằng public.users
            LEFT JOIN public.users cu ON mc.user_id = cu.id

            LEFT JOIN public.users res_user ON r.resolver_id = res_user.id

            ORDER BY CASE WHEN r.status = 'pending' THEN 1 ELSE 2 END, r.created_at DESC
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
                }
                else if (report.target_type === 'user') {
                    const userRes = await pool.query(`SELECT raw_user_meta_data->>'full_name' as name FROM auth.users WHERE id = $1`, [report.target_id]);
                    if (userRes.rows.length > 0) targetName = userRes.rows[0].name || 'Người dùng';
                }
                else if (report.target_type === 'moment') {
                    const momentRes = await pool.query(`SELECT description FROM moments WHERE moment_id = $1`, [report.target_id]);
                    if (momentRes.rows.length > 0) {
                        const desc = momentRes.rows[0].description || 'Khoảnh khắc không tên';
                        targetName = desc.length > 30 ? desc.substring(0, 30) + '...' : desc;
                    }
                }
                else if (report.target_type === 'comment') {
                    const commentRes = await pool.query(`SELECT content FROM moment_comments WHERE id = $1`, [report.target_id]);
                    if (commentRes.rows.length > 0) {
                        const content = commentRes.rows[0].content || '';
                        targetName = content.length > 30 ? content.substring(0, 30) + '...' : content;
                    }
                }
            } catch (e) {
                console.error("⚠️ Lỗi lấy tên target cho thông báo (không ảnh hưởng luồng chính):", e.message);
            }

            // --- Soạn nội dung tin nhắn ---
            let typeText = 'đối tượng';
            if (report.target_type === 'song') typeText = 'bài hát';
            else if (report.target_type === 'user') typeText = 'người dùng';
            else if (report.target_type === 'moment') typeText = 'bài đăng';
            else if (report.target_type === 'comment') typeText = 'bình luận';

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