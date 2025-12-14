const express = require('express');
const router = express.Router();
const pool = require('../config/db');
const { upload, uploadToR2, deleteFromR2 } = require('../services/uploadService');

// Cấu hình nhận file
const songUploads = upload.fields([
    { name: 'beat', maxCount: 1 },
    { name: 'lyric', maxCount: 1 },
    { name: 'vocal', maxCount: 1 },
    { name: 'image', maxCount: 1 }
]);

// --- 1. LẤY DANH SÁCH BÀI HÁT (GET) ---
router.get('/', async (req, res) => {
    try {
        const result = await pool.query('SELECT * FROM songs ORDER BY created_at DESC');
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// --- 2. THÊM BÀI HÁT (POST) ---
router.post('/', songUploads, async (req, res) => {
    try {
        const { title, artist, genre } = req.body;
        const files = req.files || {};

        console.log("Admin đang upload:", title);

        const [beatUrl, lyricUrl, vocalUrl, imageUrl] = await Promise.all([
            uploadToR2(files['beat']?.[0], 'beats'),
            uploadToR2(files['lyric']?.[0], 'lyrics'),
            uploadToR2(files['vocal']?.[0], 'vocals'),
            uploadToR2(files['image']?.[0], 'images')
        ]);

        const query = `
            INSERT INTO songs (title, artist_name, genre, beat_url, lyric_url, vocal_url, image_url, view_count) 
            VALUES ($1, $2, $3, $4, $5, $6, $7, 0) RETURNING *
        `;

        const newSong = await pool.query(query, [title, artist, genre, beatUrl, lyricUrl, vocalUrl, imageUrl]);
        res.json({ status: 'success', data: newSong.rows[0] });
    } catch (err) {
        console.error(err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

// --- 3. SỬA THÔNG TIN BÀI HÁT (PUT) ---
router.put('/:id', songUploads, async (req, res) => {
    const { id } = req.params;
    const { title, artist, genre } = req.body;
    const files = req.files || {};

    try {
        // Lấy thông tin bài hát hiện tại
        const currentSongResult = await pool.query('SELECT * FROM songs WHERE song_id = $1', [id]);
        if (currentSongResult.rows.length === 0) {
            return res.status(404).json({ status: 'error', message: 'Không tìm thấy bài hát' });
        }
        const currentSong = currentSongResult.rows[0];

        // Chuẩn bị các biến URL mới
        let newBeatUrl = currentSong.beat_url;
        let newLyricUrl = currentSong.lyric_url;
        let newVocalUrl = currentSong.vocal_url;
        let newImageUrl = currentSong.image_url;

        // Kiểm tra từng loại file, nếu có mới thì: Xóa cũ -> Up mới

        // --- Xử lý Beat ---
        if (files['beat']?.[0]) {
            await deleteFromR2(currentSong.beat_url); // Xóa file cũ
            newBeatUrl = await uploadToR2(files['beat'][0], 'beats'); // Up file mới
        }

        // --- Xử lý Lyric ---
        if (files['lyric']?.[0]) {
            await deleteFromR2(currentSong.lyric_url);
            newLyricUrl = await uploadToR2(files['lyric'][0], 'lyrics');
        }

        // --- Xử lý Vocal ---
        if (files['vocal']?.[0]) {
            await deleteFromR2(currentSong.vocal_url);
            newVocalUrl = await uploadToR2(files['vocal'][0], 'vocals');
        }

        // --- Xử lý Image ---
        if (files['image']?.[0]) {
            await deleteFromR2(currentSong.image_url);
            newImageUrl = await uploadToR2(files['image'][0], 'images');
        }

        // BƯỚC 4: Cập nhật Database
        const query = `
            UPDATE songs 
            SET title = $1, artist_name = $2, genre = $3, 
                beat_url = $4, lyric_url = $5, vocal_url = $6, image_url = $7
            WHERE song_id = $8 RETURNING *
        `;

        const result = await pool.query(query, [
            title, artist, genre,
            newBeatUrl, newLyricUrl, newVocalUrl, newImageUrl,
            id
        ]);

        res.json({ status: 'success', message: 'Cập nhật thành công', data: result.rows[0] });

    } catch (err) {
        console.error(err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

// --- 4. XÓA BÀI HÁT (DELETE) ---
router.delete('/:id', async (req, res) => {
    const { id } = req.params;

    try {
        // BƯỚC 1: Lấy thông tin bài hát để lấy link file
        const result = await pool.query('SELECT * FROM songs WHERE song_id = $1', [id]);

        if (result.rows.length === 0) {
            return res.status(404).json({ status: 'error', message: 'Bài hát không tồn tại' });
        }

        const song = result.rows[0];

        // BƯỚC 2: Xóa các file trên Cloudflare R2
        // Dùng Promise.all để xóa đồng thời 4 file cho nhanh
        console.log(`Đang xóa file của bài: ${song.title}`);

        await Promise.all([
            deleteFromR2(song.beat_url),
            deleteFromR2(song.lyric_url),
            deleteFromR2(song.vocal_url),
            deleteFromR2(song.image_url)
        ]);

        // BƯỚC 3: Xóa dữ liệu trong Database
        await pool.query('DELETE FROM songs WHERE song_id = $1', [id]);

        res.json({ status: 'success', message: 'Đã xóa bài hát và dọn sạch file trên Cloud' });

    } catch (err) {
        console.error("Lỗi khi xóa:", err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

module.exports = router;