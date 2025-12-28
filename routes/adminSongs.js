const express = require('express');
const router = express.Router();
const pool = require('../config/db');

const { verifyToken, requireAdmin } = require('../middlewares/auth');

// Service upload Cloudflare R2
const { upload, uploadToR2, deleteFromR2 } = require('../services/uploadService');

// Cấu hình nhận 4 file
const songUploads = upload.fields([
    { name: 'beat', maxCount: 1 },
    { name: 'lyric', maxCount: 1 },
    { name: 'vocal', maxCount: 1 },
    { name: 'image', maxCount: 1 }
]);

// --- 1. LẤY DANH SÁCH BÀI HÁT  ---
router.get('/', verifyToken, requireAdmin, async (req, res) => {
    try {
        const result = await pool.query('SELECT * FROM songs ORDER BY created_at DESC');
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// --- 2. THÊM BÀI HÁT MỚI (PRIVATE) ---
router.post('/', verifyToken, requireAdmin, songUploads, async (req, res) => {
    try {
        const { title, artist, genre } = req.body;
        const files = req.files || {};

        // [SỬA ĐỔI] Truyền thêm metadata (title, artist, fileType) vào hàm uploadToR2
        const [beatUrl, lyricUrl, vocalUrl, imageUrl] = await Promise.all([
            uploadToR2(files['beat']?.[0], 'beats', { 
                songTitle: title, 
                artistName: artist, 
                fileType: 'beat' 
            }),
            uploadToR2(files['lyric']?.[0], 'lyrics', { 
                songTitle: title, 
                artistName: artist, 
                fileType: 'lyric' 
            }),
            uploadToR2(files['vocal']?.[0], 'vocals', { 
                songTitle: title, 
                artistName: artist, 
                fileType: 'vocal' 
            }),
            uploadToR2(files['image']?.[0], 'images', { 
                songTitle: title, 
                artistName: artist, 
                fileType: 'image' 
            })
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
        res.status(500).json({ status: 'error', message: err.message });
    }
});

// --- 3. CẬP NHẬT BÀI HÁT (PRIVATE) ---
router.put('/:id', verifyToken, requireAdmin, songUploads, async (req, res) => {
    const { id } = req.params;
    const { title, artist, genre } = req.body;
    const files = req.files || {};

    try {
        // Lấy thông tin bài cũ
        const currentSongRes = await pool.query('SELECT * FROM songs WHERE song_id = $1', [id]);
        if (currentSongRes.rows.length === 0) return res.status(404).json({ message: 'Bài hát không tồn tại' });
        const currentSong = currentSongRes.rows[0];

        let newBeatUrl = currentSong.beat_url;
        let newLyricUrl = currentSong.lyric_url;
        let newVocalUrl = currentSong.vocal_url;
        let newImageUrl = currentSong.image_url;

        // [SỬA ĐỔI] Truyền metadata khi upload file mới trong quá trình update
        
        if (files['beat']?.[0]) { 
            await deleteFromR2(currentSong.beat_url); 
            newBeatUrl = await uploadToR2(files['beat'][0], 'beats', { 
                songTitle: title, 
                artistName: artist, 
                fileType: 'beat' 
            }); 
        }

        if (files['lyric']?.[0]) { 
            await deleteFromR2(currentSong.lyric_url); 
            newLyricUrl = await uploadToR2(files['lyric'][0], 'lyrics', { 
                songTitle: title, 
                artistName: artist, 
                fileType: 'lyric' 
            }); 
        }

        if (files['vocal']?.[0]) { 
            await deleteFromR2(currentSong.vocal_url); 
            newVocalUrl = await uploadToR2(files['vocal'][0], 'vocals', { 
                songTitle: title, 
                artistName: artist, 
                fileType: 'vocal' 
            }); 
        }

        if (files['image']?.[0]) { 
            await deleteFromR2(currentSong.image_url); 
            newImageUrl = await uploadToR2(files['image'][0], 'images', { 
                songTitle: title, 
                artistName: artist, 
                fileType: 'image' 
            }); 
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
        res.status(500).json({ error: err.message });
    }
});

// --- 4. XÓA BÀI HÁT (PRIVATE) ---
router.delete('/:id', verifyToken, requireAdmin, async (req, res) => {
    const { id } = req.params;
    try {
        const resSong = await pool.query('SELECT * FROM songs WHERE song_id = $1', [id]);
        if (resSong.rows.length === 0) return res.status(404).json({ message: 'Bài hát không tồn tại' });
        const song = resSong.rows[0];

        const filesToDelete = [song.beat_url, song.lyric_url, song.vocal_url, song.image_url];
        
        await Promise.all(filesToDelete.map(async (url) => {
            if (url) {
                try {
                    await deleteFromR2(url);
                } catch (e) {
                    console.error(`Lỗi xóa file R2 (${url}):`, e.message); 
                }
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