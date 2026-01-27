const express = require('express');
const router = express.Router();
const { generatePresignedUrl } = require('../services/uploadService');
const { verifyToken } = require('../middlewares/auth');
const { getSupabaseClient } = require('../config/supabaseClient');
const pool = require('../config/db');
const path = require('path');

const VALID_REGIONS = [
    "TP Hà Nội", "TP Huế", "Quảng Ninh", "Cao Bằng", "Lạng Sơn", "Lai Châu",
    "Điện Biên", "Sơn La", "Thanh Hóa", "Nghệ An", "Hà Tĩnh", "Tuyên Quang",
    "Lào Cai", "Thái Nguyên", "Phú Thọ", "Bắc Ninh", "Hưng Yên", "TP Hải Phòng",
    "Ninh Bình", "Quảng Trị", "TP Đà Nẵng", "Quảng Ngãi", "Gia Lai", "Khánh Hòa",
    "Lâm Đồng", "Đắk Lắk", "TP Hồ Chí Minh", "Đồng Nai", "Tây Ninh", "TP Cần Thơ",
    "Vĩnh Long", "Đồng Tháp", "Cà Mau", "An Giang"
];

const VALID_GENDERS = ['Nam', 'Nữ', 'Khác'];

// Hàm xử lý tên thư mục an toàn (Slugify)
const slugify = (text) => {
    if (!text) return '';
    return text.toString().toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/\s+/g, '-')       
        .replace(/[^\w\-]+/g, '')   
        .replace(/\-\-+/g, '-')     
        .replace(/^-+/, '')         
        .replace(/-+$/, '');        
};

// --- 1. API Lấy link upload (Presigned URL) ---
router.post('/presigned-url', verifyToken, async (req, res) => {
    try {
        const { fileName, fileType } = req.body;
        const userId = req.user.user_id;

        const userQuery = await pool.query(
            'SELECT email FROM users WHERE id = $1',
            [userId]
        );

        let folderName = userId;

        if (userQuery.rows.length > 0 && userQuery.rows[0].email) {
            const email = userQuery.rows[0].email;
            
            const emailPrefix = email.split('@')[0];
            
            folderName = slugify(emailPrefix);
        }

        const fileExt = path.extname(fileName);
        const uniqueFileName = `${Date.now()}-${Math.round(Math.random() * 1E9)}${fileExt}`;
        
        const r2Key = `users/${folderName}/${uniqueFileName}`;

        const urls = await generatePresignedUrl(r2Key, fileType);
        
        res.json({ 
            success: true, 
            folder: folderName,
            ...urls 
        });

    } catch (error) {
        console.error("Lỗi lấy presigned url:", error);
        res.status(500).json({ 
            error: 'Lỗi tạo link upload', 
            details: error.message 
        });
    }
});

// --- 2. API Cập nhật thông tin Profile (Bao gồm cả Avatar) ---
router.put('/update-profile', verifyToken, async (req, res) => {
    try {
        const userId = req.user.user_id;
        const { username, full_name, gender, region, bio, avatarUrl } = req.body;
        if (username) {
            const usernameRegex = /^[a-zA-Z0-9]{3,20}$/;
            if (!usernameRegex.test(username)) {
                return res.status(400).json({ 
                    error: "Username không hợp lệ. Chỉ chứa chữ, số và dài từ 3-20 ký tự." 
                });
            }
        }

        if (bio && bio.length > 200) {
            return res.status(400).json({ 
                error: "Bio quá dài. Tối đa 200 ký tự." 
            });
        }

        if (gender && !VALID_GENDERS.includes(gender)) {
            return res.status(400).json({ 
                error: "Giới tính không hợp lệ." 
            });
        }

        if (region && !VALID_REGIONS.includes(region)) {
            return res.status(400).json({ error: "Tên vùng miền không hợp lệ." });
        }

        let updateFields = [];
        let values = [];
        let index = 1;

        // Xây dựng câu query động (Chỉ update những trường client gửi lên)
        if (username) {
            updateFields.push(`username = $${index++}`);
            values.push(username);
        }
        if (full_name) {
            updateFields.push(`full_name = $${index++}`);
            values.push(full_name);
        }
        if (gender) {
            updateFields.push(`gender = $${index++}`);
            values.push(gender);
        }
        if (region) {
            updateFields.push(`region = $${index++}`);
            values.push(region);
        }
        if (bio !== undefined) {
            updateFields.push(`bio = $${index++}`);
            values.push(bio);
        }
        if (avatarUrl) {
            updateFields.push(`avatar_url = $${index++}`);
            values.push(avatarUrl);
        }

        if (updateFields.length === 0) {
            return res.status(400).json({ error: "Không có dữ liệu nào để cập nhật" });
        }

        values.push(userId);

        const query = `
            UPDATE public.users 
            SET ${updateFields.join(', ')} 
            WHERE id = $${index} 
            RETURNING id, username, full_name, avatar_url, gender, region, bio
        `;

        const result = await pool.query(query, values);

        if (result.rows.length === 0) {
            return res.status(404).json({ error: "Người dùng không tồn tại" });
        }

        res.json({
            success: true,
            message: 'Cập nhật hồ sơ thành công',
            data: result.rows[0]
        });

    } catch (error) {
        console.error("Lỗi update profile:", error);
        if (error.code === '23505') { 
            return res.status(409).json({ error: "Username đã tồn tại, vui lòng chọn tên khác." });
        }
        res.status(500).json({ error: error.message });
    }
});

// --- 3. API Lưu metadata Moment (Audio) ---
router.post('/save-metadata', verifyToken, async (req, res) => {
    try {
        const { audioUrl, description, visibility } = req.body;
        const uId = req.user.user_id;

        const supabase = getSupabaseClient();
        const { data, error } = await supabase
            .from('moments')
            .insert({
                user_id: uId,
                audio_url: audioUrl,
                description: description || '',
                visibility: visibility || 'public',
            })
            .select()
            .single();

        if (error) throw error;

        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;