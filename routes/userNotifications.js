const express = require('express');
const router = express.Router();
const pool = require('../config/db');
const { 
    sendPushNotification,
    cancelPushNotification,
    createAndSendNotification,
    buildNotificationMessage
} = require('../services/notificationService');

// ================= API ENDPOINTS =================

// 1. FOLLOW USER (POST /api/user/notifications/follow)
router.post('/follow', async (req, res) => {
    const { follower_id, following_id } = req.body;

    if (!follower_id || !following_id) {
        return res.status(400).json({ error: "Thiếu follower_id hoặc following_id" });
    }

    try {
        // 1. Insert vào bảng follows
        const insertQuery = `
            INSERT INTO follows (follower_id, following_id) 
            VALUES ($1, $2)
            ON CONFLICT (follower_id, following_id) DO NOTHING
            RETURNING *;
        `;
        const result = await pool.query(insertQuery, [follower_id, following_id]);

        if (result.rowCount === 0) {
             return res.status(200).json({ message: "Đã follow rồi" });
        }

        // 2. Lấy tên người follow
        const actorRes = await pool.query(
            `SELECT email, raw_user_meta_data 
             FROM auth.users WHERE id = $1`, 
            [follower_id]
        );
        
        if (actorRes.rows.length > 0) {
            const actor = actorRes.rows[0];
            const meta = actor.raw_user_meta_data || {};
            
            const actorName = meta.full_name || meta.username || actor.email || "Ai đó";

            // 3. Gửi thông báo
            createAndSendNotification({
                userId: following_id,
                title: "Người theo dõi mới",
                message: `${actorName} đã bắt đầu theo dõi bạn.`,
                type: 'follow',
                actorId: follower_id,
                data: { 
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                    type: 'profile', 
                    userId: follower_id 
                }
            });
        }

        return res.json({ success: true, message: "Follow thành công" });

    } catch (err) {
        console.error("Lỗi Follow:", err);
        return res.status(500).json({ error: err.message });
    }
});

// 2. UNFOLLOW USER (POST /api/user/notifications/unfollow)
router.post('/unfollow', async (req, res) => {
    const { follower_id, following_id } = req.body;

    try {
        // Xóa Follow
        await pool.query(
            "DELETE FROM follows WHERE follower_id = $1 AND following_id = $2",
            [follower_id, following_id]
        );

        // Tìm thông báo cũ
        const notiRes = await pool.query(
            `SELECT id, onesignal_id FROM notifications 
             WHERE user_id = $1 AND actor_id = $2 AND type = 'follow'
             LIMIT 1`,
            [following_id, follower_id]
        );

        if (notiRes.rows.length > 0) {
            const notiToDelete = notiRes.rows[0];

            // Xóa DB
            await pool.query("DELETE FROM notifications WHERE id = $1", [notiToDelete.id]);

            // Thu hồi Push
            if (notiToDelete.onesignal_id) {
                cancelPushNotification(notiToDelete.onesignal_id);
            }
        }

        return res.json({ success: true, message: "Unfollow và dọn dẹp thành công" });

    } catch (err) {
        console.error("Lỗi Unfollow:", err);
        return res.status(500).json({ error: err.message });
    }
});

// 3. GET NOTIFICATIONS
router.get('/:userId', async (req, res) => {
    const { userId } = req.params;

    try {
        const query = `
            SELECT 
                n.*,
                json_build_object(
                    'id', u.id,
                    'email', u.email,
                    'full_name', u.raw_user_meta_data->>'full_name',
                    'avatar_url', u.raw_user_meta_data->>'avatar_url'
                ) as actor
            FROM notifications n
            LEFT JOIN auth.users u ON n.actor_id = u.id
            WHERE n.user_id = $1
            ORDER BY n.created_at DESC
            LIMIT 50
        `;
        
        const result = await pool.query(query, [userId]);
        return res.json(result.rows);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

// 4. MARK AS READ
router.put('/read/:id', async (req, res) => {
    const { id } = req.params;
    try {
        await pool.query("UPDATE notifications SET is_read = true WHERE id = $1", [id]);
        return res.json({ success: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

// 5. SEND CHAT NOTIFICATION
router.post('/chat', async (req, res) => {
    const { sender_id, receiver_id, message_content } = req.body;

    if (!sender_id || !receiver_id) {
        return res.status(400).json({ error: "Thiếu thông tin người gửi/nhận" });
    }

    try {
        const senderRes = await pool.query(
            `SELECT email, raw_user_meta_data 
             FROM auth.users WHERE id = $1`, 
            [sender_id]
        );
        
        let senderName = "Ai đó";
        if (senderRes.rows.length > 0) {
            const u = senderRes.rows[0];
            const meta = u.raw_user_meta_data || {};
            senderName = meta.full_name || meta.username || u.email || "Người dùng";
        }

        const previewContent = message_content.length > 50 
            ? message_content.substring(0, 50) + "..." 
            : message_content;

        const pushResult = await sendPushNotification(
            [receiver_id.toString()],
            `Tin nhắn mới từ ${senderName}`,
            previewContent,
            { 
                click_action: "FLUTTER_NOTIFICATION_CLICK_CHAT",
                type: 'chat', 
                senderId: sender_id, 
                senderName: senderName 
            }
        );

        return res.json({ 
            success: true, 
            message: "Đã gửi thông báo tin nhắn",
            debug_onesignal: pushResult 
        });

    } catch (err) {
        console.error("Chat Notification Error:", err);
        return res.status(500).json({ error: err.message });
    }
});

// 6. TRIGGER NOTIFICATION FOR LIKE/COMMENT WITH MERGE LOGIC
router.post('/trigger', async (req, res) => {
    // actor_id: Người vừa bấm like/comment
    // receiver_id: Chủ bài viết
    // moment_id: ID bài viết
    // type: 'like' hoặc 'comment'
    const { actor_id, receiver_id, moment_id, type } = req.body;

    if (!actor_id || !receiver_id || !moment_id || !type) {
        return res.status(400).json({ error: "Thiếu thông tin bắt buộc" });
    }

    // 1. Chặn tự thông báo cho chính mình
    if (actor_id.toString() === receiver_id.toString()) {
        return res.json({ status: 'ignored', message: 'Self action' });
    }

    try {
        // 2. Lấy tên người vừa hành động (Actor)
        const actorRes = await pool.query(
            `SELECT email, raw_user_meta_data FROM auth.users WHERE id = $1`, 
            [actor_id]
        );
        
        let actorName = "Ai đó";
        if (actorRes.rows.length > 0) {
            const u = actorRes.rows[0];
            const meta = u.raw_user_meta_data || {};
            actorName = meta.full_name || meta.username || u.email || "Người dùng";
        }

        // 3. Kiểm tra xem đã có thông báo CŨ (Chưa đọc, cùng bài, cùng loại) chưa?
        // Logic: Tìm thông báo gần nhất của user này về bài này mà chưa đọc
        const existQuery = await pool.query(`
            SELECT id, action_count, onesignal_id 
            FROM notifications 
            WHERE user_id = $1 
              AND moment_id = $2 
              AND type = $3 
              AND is_read = false
            LIMIT 1
        `, [receiver_id, moment_id, type]);

        if (existQuery.rows.length > 0) {
            // ===============================================
            // TRƯỜNG HỢP A: ĐÃ CÓ THÔNG BÁO CŨ -> GỘP (MERGE)
            // ===============================================
            const oldNotif = existQuery.rows[0];
            const newCount = (oldNotif.action_count || 1) + 1;
            
            // Tạo câu thông báo mới: "An và X người khác..."
            const newMessage = buildNotificationMessage(actorName, type, newCount);

            // Cập nhật DB:
            // - actor_id: cập nhật thành người mới nhất
            // - message: cập nhật text
            // - action_count: tăng số lượng
            // - updated_at: đẩy lên đầu danh sách
            await pool.query(`
                UPDATE notifications 
                SET actor_id = $1, 
                    action_count = $2, 
                    message = $3,
                    updated_at = NOW()
                WHERE id = $4
            `, [actor_id, newCount, newMessage, oldNotif.id]);

            // [CHIẾN THUẬT CHỐNG SPAM]:
            // Ta KHÔNG gọi sendPushNotification ở đây.
            // Người dùng sẽ thấy số badge tăng hoặc danh sách cập nhật khi vào app, 
            // nhưng điện thoại sẽ không rung bần bật vì spam.
            
            return res.json({ status: 'merged', message: 'Notification merged, no push sent.' });

        } else {
            // ===============================================
            // TRƯỜNG HỢP B: THÔNG BÁO MỚI TINH -> TẠO MỚI & PUSH
            // ===============================================
            const title = type === 'like' ? 'Lượt thích mới' : 'Bình luận mới';
            const message = buildNotificationMessage(actorName, type, 1);

            // A. Gửi Push trước lấy ID
            const pushData = { 
                click_action: "FLUTTER_NOTIFICATION_CLICK_MOMENT",
                type: type, 
                momentId: moment_id 
            };
            
            const pushResult = await sendPushNotification(
                [receiver_id.toString()], 
                title, 
                message, 
                pushData
            );
            
            const oneSignalId = pushResult ? pushResult.id : null;

            // B. Lưu vào DB
            await pool.query(`
                INSERT INTO notifications (user_id, actor_id, moment_id, type, title, message, action_count, onesignal_id)
                VALUES ($1, $2, $3, $4, $5, $6, 1, $7)
            `, [receiver_id, actor_id, moment_id, type, title, message, oneSignalId]);

            return res.json({ status: 'created', message: 'Notification created and pushed.' });
        }

    } catch (err) {
        console.error("Trigger Error:", err);
        return res.status(500).json({ error: err.message });
    }
});

module.exports = router;