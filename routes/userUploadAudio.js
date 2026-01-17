// routes/userUploadAudio.js
const express = require('express');
const router = express.Router();
const { generatePresignedUrl } = require('../services/uploadService');
const { verifyToken } = require('../middlewares/auth');
const { getSupabaseClient } = require('../config/supabaseClient');
const pool = require('../config/db');
const path = require('path');

const slugify = (text) => {
    if (!text) return '';
    return text.toString().toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/\s+/g, '-')       // Thay khoảng trắng bằng dấu gạch ngang
        .replace(/[^\w\-]+/g, '')   // Bỏ ký tự đặc biệt
        .replace(/\-\-+/g, '-')     // Bỏ dấu gạch ngang kép
        .replace(/^-+/, '')         // Cắt gạch ngang đầu
        .replace(/-+$/, '');        // Cắt gạch ngang cuối
};

// 1. API Lấy link upload
router.post('/presigned-url', verifyToken, async (req, res) => {
    try {
        const { fileName, fileType } = req.body;
        const userId = req.user.user_id;

        // BƯỚC A: Lấy username từ Database
        const userQuery = await pool.query(
            'SELECT username FROM users WHERE id = $1',
            [userId]
        );

        let folderName = userId;
        if (userQuery.rows.length > 0 && userQuery.rows[0].username) {
            folderName = slugify(userQuery.rows[0].username);
        }

        if (!folderName) folderName = userId;

        const fileExt = path.extname(fileName);
        const uniqueFileName = `${Date.now()}-${Math.round(Math.random() * 1E9)}${fileExt}`;
        
        const r2Key = `moments/${folderName}/${uniqueFileName}`;
        const urls = await generatePresignedUrl(r2Key, fileType);
        res.json({ success: true, ...urls });

    } catch (error) {
        console.error("Lỗi chi tiết:", error);
        res.status(500).json({ 
            error: 'Lỗi tạo link upload', 
            details: error.message,
            stack: error.stack
        });
    }
});

// 2. API Lưu thông tin vào DB
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