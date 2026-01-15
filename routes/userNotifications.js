const express = require('express');
const router = express.Router();
const { getSafeActorName } = require('../services/stringHelper');
const axios = require('axios');
const { getSupabaseClient } = require('../config/supabaseClient');

// Cấu hình OneSignal
const ONESIGNAL_APP_ID = process.env.ONESIGNAL_APP_ID;
const ONESIGNAL_API_KEY = process.env.ONESIGNAL_API_KEY;

// --- HELPER: Gửi thông báo qua OneSignal ---
async function sendPushNotification(userIds, heading, content, data) {
    try {
        const body = {
            app_id: ONESIGNAL_APP_ID,
            include_external_user_ids: userIds,
            headings: { en: heading },
            contents: { en: content },
            data: data,
            channel_for_external_user_ids: "push",
        };

        const response = await axios.post(
            'https://onesignal.com/api/v1/notifications',
            body,
            {
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Basic ${ONESIGNAL_API_KEY}`
                }
            }
        );

        if (response.data.recipients === 0) {
            console.warn("⚠️ OneSignal: Gửi thành công nhưng 0 người nhận (User ID chưa map trên Client).");
        }

        return response.data; 
    } catch (error) {
        console.error("❌ OneSignal Error Details:", error.response?.data || error.message);
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
    const supabase = getSupabaseClient();
    const { follower_id, following_id } = req.body;

    if (!follower_id || !following_id) {
        return res.status(400).json({ error: "Thiếu follower_id hoặc following_id" });
    }

    try {
        const { error: followError } = await supabase
            .from('follows')
            .insert({ follower_id, following_id });

        if (followError) {
            if (followError.code === '23505') return res.status(200).json({ message: "Đã follow rồi" });
            throw followError;
        }

        const { data: actor } = await supabase
            .from('users')
            .select('username, full_name')
            .eq('id', follower_id)
            .single();

        const actorName = getSafeActorName(actor);

        const pushResult = await sendPushNotification(
            [following_id],
            "Người theo dõi mới",
            `${actorName} đã bắt đầu theo dõi bạn.`,
            { type: 'profile', userId: follower_id }
        );
        console.log("⚠️ Cảnh báo: Push trả về null, có thể do lỗi cấu hình hoặc User ID chưa map.");
        console.log("Push Result OneSignal ID: ", pushResult?.id);
        await supabase.from('notifications').insert({
            user_id: following_id,
            actor_id: follower_id,
            type: 'follow',
            title: actorName,
            message: "đã bắt đầu theo dõi bạn.",
            onesignal_id: pushResult?.id || null
        });

        return res.json({ success: true, message: "Follow thành công" });

    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: err.message });
    }
});

// 2. UNFOLLOW USER (POST /api/user/notifications/unfollow)
router.post('/unfollow', async (req, res) => {
    const supabase = getSupabaseClient();
    const { follower_id, following_id } = req.body;

    try {
        await supabase
            .from('follows')
            .delete()
            .match({ follower_id, following_id });

        const { data: notiToDelete } = await supabase
            .from('notifications')
            .select('id, onesignal_id')
            .match({
                user_id: following_id,
                actor_id: follower_id,
                type: 'follow'
            })
            .single();

        if (notiToDelete) {
            await supabase
                .from('notifications')
                .delete()
                .eq('id', notiToDelete.id);

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
    const supabase = getSupabaseClient();
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
            .limit(50);

        if (error) throw error;

        return res.json(data);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

// 4. MARK AS READ (PUT /api/user/notifications/read/:id)
router.put('/read/:id', async (req, res) => {
    const supabase = getSupabaseClient();
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


// 5. SEND CHAT NOTIFICATION (POST /api/user/notifications/chat)
router.post('/chat', async (req, res) => {
    const supabase = getSupabaseClient();
    // sender_id: Người gửi
    // receiver_id: Người nhận
    // message_content: Nội dung tin nhắn
    const { sender_id, receiver_id, message_content } = req.body;

    if (!sender_id || !receiver_id) {
        return res.status(400).json({ error: "Thiếu thông tin người gửi/nhận" });
    }

    try {
        const { data: sender } = await supabase
            .from('users')
            .select('full_name, username')
            .eq('id', sender_id)
            .single();
        
        const senderName = getSafeActorName(sender);
        
        const previewContent = message_content.length > 50 
            ? message_content.substring(0, 50) + "..." 
            : message_content;

        const pushResult = await sendPushNotification(
            [receiver_id], 
            `Tin nhắn mới từ ${senderName}`,
            previewContent,
            { 
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

module.exports = router;