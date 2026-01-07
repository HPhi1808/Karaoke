const express = require('express');
const router = express.Router();
const pool = require('../config/db');
const fs = require('fs');
const path = require('path');

const { verifyToken, requireAdmin } = require('../middlewares/auth');
const { upload, uploadToR2, deleteFromR2 } = require('../services/uploadService');
const { compressAudio } = require('../services/audioProcessor');

// Cấu hình nhận file
const songUploads = upload.fields([
    { name: 'beat', maxCount: 1 },
    { name: 'lyric', maxCount: 1 },
    { name: 'vocal', maxCount: 1 },
    { name: 'image', maxCount: 1 }
]);

// --- HÀM TIỆN ÍCH: DỌN DẸP FILE TẠM ---
const cleanupFile = (filePath) => {
    if (filePath && fs.existsSync(filePath)) {
        try {
            fs.unlinkSync(filePath);
        } catch (e) {
            console.error(`Không thể xóa file tạm: ${filePath}`, e.message);
        }
    }
};

// Hàm dọn dẹp toàn bộ req.files khi có lỗi validation
const cleanupAllUploadedFiles = (files) => {
    if (!files) return;
    Object.values(files).flat().forEach(file => cleanupFile(file.path));
};

// --- HÀM XỬ LÝ VÀ UPLOAD ---
const processAndUpload = async (file, folder, metadata) => {
    if (!file) return null;

    let fileToUpload = file;
    let compressedPath = null;
    let originalPath = file.path;

    // Chỉ nén nếu là file beat hoặc vocal
    if (metadata.fileType === 'beat' || metadata.fileType === 'vocal') {
        try {
            const tempDir = path.dirname(file.path);
            const originalName = path.basename(file.originalname, path.extname(file.originalname));
            // Tạo tên file nén mới
            compressedPath = path.join(tempDir, `compressed_${Date.now()}_${originalName}.mp3`);

            console.log(`⏳ Đang nén file ${metadata.fileType}: ${file.path}`);
            
            // Nén file
            await compressAudio(file.path, compressedPath);
            
            // Cập nhật object file để trỏ tới file đã nén
            fileToUpload = {
                ...file,
                path: compressedPath,
                mimetype: 'audio/mpeg',
                size: fs.statSync(compressedPath).size
            };
             console.log(`✅ Nén thành công ${metadata.fileType}`);

        } catch (error) {
            console.error(`❌ Lỗi nén ${metadata.fileType}, sẽ upload file gốc:`, error);
            // Nếu lỗi nén, fileToUpload vẫn giữ nguyên là file gốc
        }
    }

    try {
        // Upload lên R2
        const url = await uploadToR2(fileToUpload, folder, metadata);
        return url;
    } finally {
        // Dọn dẹp sau khi upload xong (dù thành công hay thất bại)
        // 1. Xóa file gốc do Multer tạo ra
        cleanupFile(originalPath);
        // 2. Xóa file nén nếu có tạo ra
        if (compressedPath) cleanupFile(compressedPath);
    }
};


// --- 1. LẤY DANH SÁCH BÀI HÁT ---
router.get('/', verifyToken, requireAdmin, async (req, res) => {
    try {
        const result = await pool.query('SELECT * FROM songs ORDER BY created_at DESC');
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// --- 2. THÊM BÀI HÁT MỚI ---
router.post('/', verifyToken, requireAdmin, songUploads, async (req, res) => {
    const files = req.files || {};
    try {
        const { title, artist, genre } = req.body;
        if (!title || !artist) {
            cleanupAllUploadedFiles(files);
            return res.status(400).json({ 
                status: 'error', 
                message: 'Vui lòng nhập tên bài hát và tên ca sĩ' 
            });
        }

        // ---CHECK TRÙNG BÀI HÁT ---
        const checkDuplicate = await pool.query(
            'SELECT song_id FROM songs WHERE LOWER(title) = LOWER($1) AND LOWER(artist_name) = LOWER($2)',
            [title.toString().trim(), artist.toString().trim()]
        );

        if (checkDuplicate.rows.length > 0) {
            cleanupAllUploadedFiles(files);
            
            // Trả về 409 Conflict
            return res.status(409).json({ 
                status: 'error', 
                message: `Bài hát "${title}" của "${artist}" đã tồn tại trên hệ thống!` 
            });
        }

        // BƯỚC 2: XỬ LÝ VÀ UPLOAD
        const [beatUrl, lyricUrl, vocalUrl, imageUrl] = await Promise.all([
            processAndUpload(files['beat']?.[0], 'beats', { 
                songTitle: title, artistName: artist, fileType: 'beat' 
            }),
            // Lyric upload thẳng, không cần nén, nhưng cần xóa file tạm sau khi up
            (async () => {
                const f = files['lyric']?.[0];
                if (!f) return null;
                try {
                    return await uploadToR2(f, 'lyrics', { songTitle: title, artistName: artist, fileType: 'lyric' });
                } finally { cleanupFile(f.path); }
            })(),
            processAndUpload(files['vocal']?.[0], 'vocals', { 
                songTitle: title, artistName: artist, fileType: 'vocal' 
            }),
            // Image upload thẳng
            (async () => {
                const f = files['image']?.[0];
                if (!f) return null;
                try {
                    return await uploadToR2(f, 'images', { songTitle: title, artistName: artist, fileType: 'image' });
                } finally { cleanupFile(f.path); }
            })()
        ]);

        const query = `
            INSERT INTO songs (title, artist_name, genre, beat_url, lyric_url, vocal_url, image_url, view_count) 
            VALUES ($1, $2, $3, $4, $5, $6, $7, 0) 
            RETURNING *
        `;
        const newSong = await pool.query(query, [title, artist, genre, beatUrl, lyricUrl, vocalUrl, imageUrl]);
        
        res.json({ status: 'success', data: newSong.rows[0] });

    } catch (err) {
        console.error(err);
        // Xóa file nếu có lỗi server xảy ra
        cleanupAllUploadedFiles(files);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

// --- 3. CẬP NHẬT BÀI HÁT ---
router.put('/:id', verifyToken, requireAdmin, songUploads, async (req, res) => {
    const { id } = req.params;
    const files = req.files || {};
    
    try {
        const { title, artist, genre } = req.body;

        // 1. Validate dữ liệu cơ bản
        if (!title || !artist) {
            cleanupAllUploadedFiles(files);
            return res.status(400).json({ 
                status: 'error', 
                message: 'Tên bài hát và tên ca sĩ không được để trống' 
            });
        }

        // 2. Check bài hát có tồn tại không
        const currentSongRes = await pool.query('SELECT * FROM songs WHERE song_id = $1', [id]);
        if (currentSongRes.rows.length === 0) {
            cleanupAllUploadedFiles(files);
            return res.status(404).json({ message: 'Bài hát không tồn tại' });
        }
        const currentSong = currentSongRes.rows[0];

        // 3.CHECK TRÙNG TÊN BÀI HÁT + CA SĨ (Loại trừ ID hiện tại)
        const checkDuplicate = await pool.query(
            `SELECT song_id FROM songs 
             WHERE LOWER(title) = LOWER($1) 
             AND LOWER(artist_name) = LOWER($2) 
             AND song_id != $3`,
            [title.trim(), artist.trim(), id]
        );

        if (checkDuplicate.rows.length > 0) {
            cleanupAllUploadedFiles(files);
            return res.status(409).json({ 
                status: 'error', 
                message: `Bài hát "${title}" của "${artist}" đã tồn tại (ID: ${checkDuplicate.rows[0].song_id})` 
            });
        }

        // --- NẾU KHÔNG TRÙNG THÌ TIẾP TỤC XỬ LÝ ---

        let newBeatUrl = currentSong.beat_url;
        let newLyricUrl = currentSong.lyric_url;
        let newVocalUrl = currentSong.vocal_url;
        let newImageUrl = currentSong.image_url;

        // Xử lý từng file
        if (files['beat']?.[0]) { 
            await deleteFromR2(currentSong.beat_url); 
            newBeatUrl = await processAndUpload(files['beat'][0], 'beats', { songTitle: title, artistName: artist, fileType: 'beat' }); 
        }

        if (files['lyric']?.[0]) { 
            await deleteFromR2(currentSong.lyric_url);
            const f = files['lyric'][0];
            try {
                newLyricUrl = await uploadToR2(f, 'lyrics', { songTitle: title, artistName: artist, fileType: 'lyric' }); 
            } finally { cleanupFile(f.path); }
        }

        if (files['vocal']?.[0]) { 
            await deleteFromR2(currentSong.vocal_url); 
            newVocalUrl = await processAndUpload(files['vocal'][0], 'vocals', { songTitle: title, artistName: artist, fileType: 'vocal' }); 
        }

        if (files['image']?.[0]) { 
            await deleteFromR2(currentSong.image_url); 
            const f = files['image'][0];
            try {
                newImageUrl = await uploadToR2(f, 'images', { songTitle: title, artistName: artist, fileType: 'image' }); 
            } finally { cleanupFile(f.path); }
        }

        const query = `
            UPDATE songs 
            SET title=$1, artist_name=$2, genre=$3, beat_url=$4, lyric_url=$5, vocal_url=$6, image_url=$7 
            WHERE song_id=$8 
            RETURNING *
        `;
        const result = await pool.query(query, [title, artist, genre, newBeatUrl, newLyricUrl, newVocalUrl, newImageUrl, id]);
        
        res.json({ status: 'success', data: result.rows[0] });

    } catch (err) {
        console.error(err);
        cleanupAllUploadedFiles(files);
        res.status(500).json({ error: err.message });
    }
});

// --- 4. XÓA BÀI HÁT ---
router.delete('/:id', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    try {
        const resSong = await pool.query('SELECT * FROM songs WHERE song_id = $1', [id]);
        if (resSong.rows.length === 0) return res.status(404).json({ message: 'Bài hát không tồn tại' });
        const song = resSong.rows[0];

        const filesToDelete = [song.beat_url, song.lyric_url, song.vocal_url, song.image_url];
        
        await Promise.all(filesToDelete.map(async (url) => {
            if (url) {
                try { await deleteFromR2(url); } catch (e) { console.error(`Lỗi xóa file R2 (${url}):`, e.message); }
            }
        }));

        await pool.query('DELETE FROM songs WHERE song_id = $1', [id]);
        res.json({ status: 'success', message: 'Đã xóa bài hát' });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;