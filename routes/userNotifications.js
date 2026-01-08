const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');
const axios = require('axios');

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const supabase = createClient(supabaseUrl, supabaseKey);

// Cấu hình OneSignal
const ONESIGNAL_APP_ID = process.env.ONESIGNAL_APP_ID;
const ONESIGNAL_API_KEY = process.env.ONESIGNAL_API_KEY;

// --- HELPER: Gửi thông báo qua OneSignal ---
async function sendPushNotification(userIds, heading, content, data) {
    try {
        const response = await axios.post(
            'https://onesignal.com/api/v1/notifications',
            {
                app_id: ONESIGNAL_APP_ID,
                include_external_user_ids: userIds,
                headings: { en: heading },
                contents: { en: content },
                data: data,
            },
            {
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Basic ${ONESIGNAL_API_KEY}`
                }
            }
        );
        return response.data; // Trả về { id: '...', recipients: ... }
    } catch (error) {
        console.error("OneSignal Error:", error.response?.data || error.message);
        return null;
    }
}

// --- HELPER: Thu hồi thông báo OneSignal ---
async function cancelPushNotification(notificationId) {
    if (!notificationId) return;
    try {
        await axios.delete(
            `https://onesignal.com/api/v1/notifications/${notificationId}?app_id=${ONESIGNAL_APP_ID}`,
            {
                headers: { 'Authorization': `Basic ${ONESIGNAL_API_KEY}` }
            }
        );
        console.log(`Đã thu hồi thông báo: ${notificationId}`);
    } catch (error) {
        console.error("Cancel Push Error:", error.response?.data || error.message);
    }
}

// ================= API ENDPOINTS =================

// 1. FOLLOW USER (POST /api/user/notifications/follow)
router.post('/follow', async (req, res) => {
    const { follower_id, following_id } = req.body;

    if (!follower_id || !following_id) {
        return res.status(400).json({ error: "Thiếu follower_id hoặc following_id" });
    }

    try {
        // A. Insert vào bảng follows
        const { error: followError } = await supabase
            .from('follows')
            .insert({ follower_id, following_id });

        if (followError) {
            // Nếu đã follow rồi (duplicate key) thì thôi, không báo lỗi
            if (followError.code === '23505') return res.status(200).json({ message: "Đã follow rồi" });
            throw followError;
        }

        // B. Lấy thông tin người đi follow (để lấy tên hiển thị thông báo)
        const { data: actor } = await supabase
            .from('users')
            .select('username, full_name')
            .eq('id', follower_id)
            .single();

        const actorName = actor?.full_name || actor?.username || "Một người dùng";

        // C. Gửi Push Notification
        const pushResult = await sendPushNotification(
            [following_id], // Gửi cho người được follow
            "Người theo dõi mới",
            `${actorName} đã bắt đầu theo dõi bạn.`,
            { type: 'profile', userId: follower_id }
        );
        console.log("⚠️ Cảnh báo: Push trả về null, có thể do lỗi cấu hình hoặc User ID chưa map.");
        console.log("Push Result OneSignal ID: ", pushResult?.id);
        // D. Lưu vào bảng notifications (Lưu cả OneSignal ID)
        await supabase.from('notifications').insert({
            user_id: following_id, // Người nhận (B)
            actor_id: follower_id, // Người gây ra (A)
            type: 'follow',
            title: "Người theo dõi mới",
            message: "đã bắt đầu theo dõi bạn.",
            onesignal_id: pushResult?.id || null // Lưu ID để sau này xoá
        });

        return res.json({ success: true, message: "Follow thành công" });

    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: err.message });
    }
});

// 2. UNFOLLOW USER (POST /api/user/notifications/unfollow)
router.post('/unfollow', async (req, res) => {
    const { follower_id, following_id } = req.body;

    try {
        // A. Xóa khỏi bảng follows
        await supabase
            .from('follows')
            .delete()
            .match({ follower_id, following_id });

        // B. Tìm thông báo cũ trong DB để xóa
        const { data: notiToDelete } = await supabase
            .from('notifications')
            .select('id, onesignal_id')
            .match({
                user_id: following_id,
                actor_id: follower_id,
                type: 'follow'
            })
            .single(); // Lấy 1 cái gần nhất

        if (notiToDelete) {
            // C. Xóa thông báo trong DB
            await supabase
                .from('notifications')
                .delete()
                .eq('id', notiToDelete.id);

            // D. Thu hồi Push Notification (Nếu có ID)
            if (notiToDelete.onesignal_id) {
                await cancelPushNotification(notiToDelete.onesignal_id);
            }
        }

        return res.json({ success: true, message: "Unfollow và dọn dẹp thành công" });

    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: err.message });
    }
});

// 3. GET NOTIFICATIONS (GET /api/user/notifications/:userId)
router.get('/:userId', async (req, res) => {
    const { userId } = req.params;

    try {
        const { data, error } = await supabase
            .from('notifications')
            .select(`
                *,
                actor:users!actor_id (
                    id, username, full_name, avatar_url
                )
            `)
            .eq('user_id', userId)
            .order('created_at', { ascending: false })
            .limit(50); // Lấy 50 cái mới nhất

        if (error) throw error;

        return res.json(data);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

// 4. MARK AS READ (PUT /api/user/notifications/read/:id)
router.put('/read/:id', async (req, res) => {
    const { id } = req.params;
    try {
        await supabase
            .from('notifications')
            .update({ is_read: true })
            .eq('id', id);
        return res.json({ success: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

module.exports = router;