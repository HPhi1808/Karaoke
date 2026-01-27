const axios = require('axios');
const pool = require('../config/db');

// Cấu hình OneSignal
const ONESIGNAL_APP_ID = process.env.ONESIGNAL_APP_ID;
const ONESIGNAL_API_KEY = process.env.ONESIGNAL_API_KEY;

// --- 1. HELPER: Gửi thông báo qua OneSignal ---
async function sendPushNotification(userIds, heading, content, data) {
    try {
        const body = {
            app_id: ONESIGNAL_APP_ID,
            include_external_user_ids: userIds,
            headings: { en: heading },
            contents: { en: content },
            data: data,
            channel_for_external_user_ids: "push",
            small_icon: "ic_stat_icon_notification",
            android_accent_color: "FFFF00CC"
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
            console.warn("⚠️ OneSignal: Gửi thành công nhưng 0 người nhận.");
        }

        return response.data; 
    } catch (error) {
        console.error("❌ OneSignal Error:", error.response?.data || error.message);
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
        console.log(`🗑️ Đã thu hồi thông báo OneSignal: ${notificationId}`);
    } catch (error) {
        console.error("❌ Cancel Push Error:", error.response?.data || error.message);
    }
}

// --- HELPER: Xây dựng nội dung thông báo ---
function buildNotificationMessage(actorName, type, count) {
    const actionText = type === 'like' ? 'thích' : 'bình luận về';
    if (count <= 1) {
        return `${actorName} đã ${actionText} bài viết của bạn.`;
    } else {
        return `${actorName} và ${count - 1} người khác đã ${actionText} bài viết của bạn.`;
    }
}

// --- 2. MAIN FUNCTION: Lưu DB + Gửi Push ---
async function createAndSendNotification({ userId, title, message, type, actorId, data }) {
    try {
        let oneSignalId = null;

        // A. Gửi Push Notification trước (để lấy ID nếu cần, hoặc gửi song song)
        if (userId) {
            // Chuyển userId về mảng string vì hàm helper yêu cầu array
            const pushResult = await sendPushNotification([userId.toString()], title, message, data);
            if (pushResult && pushResult.id) {
                oneSignalId = pushResult.id;
            }
        }

        // B. Lưu vào Database
        const query = `
            INSERT INTO notifications (user_id, title, message, type, actor_id, onesignal_id, is_read)
            VALUES ($1, $2, $3, $4, $5, $6, false)
            RETURNING id
        `;
        
        await pool.query(query, [userId, title, message, type, actorId, oneSignalId]);
        
        console.log(`✅ Đã tạo thông báo cho User ${userId}`);

    } catch (err) {
        console.error("❌ Lỗi quy trình tạo thông báo:", err);
    }
}

module.exports = { createAndSendNotification, cancelPushNotification, sendPushNotification, buildNotificationMessage };