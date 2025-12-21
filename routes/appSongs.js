const express = require('express');
const router = express.Router();
const pool = require('../config/db');

router.get('/home', async (req, res) => {
    try {
        const limit = 10;
        const [newest, popular, recommended] = await Promise.all([
            pool.query(`SELECT song_id, title, artist_name, image_url, beat_url, lyric_url, vocal_url, view_count FROM songs ORDER BY created_at DESC LIMIT $1`, [limit]),
            pool.query(`SELECT song_id, title, artist_name, image_url, beat_url, lyric_url, vocal_url, view_count FROM songs ORDER BY view_count DESC LIMIT $1`, [limit]),
            pool.query(`SELECT song_id, title, artist_name, image_url, beat_url, lyric_url, vocal_url, view_count FROM songs ORDER BY RANDOM() LIMIT $1`, [limit])
        ]);
        res.json({ newest: newest.rows, popular: popular.rows, recommended: recommended.rows });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi tải trang chủ' });
    }
});

router.get('/', async (req, res) => {
    try {
        const { q: keyword, sort: sortType } = req.query;
        let query = `SELECT song_id, title, artist_name, genre, image_url, beat_url, lyric_url, vocal_url, view_count, created_at FROM songs WHERE 1=1`;
        let params = [];
        if (keyword) {
            query += ` AND (title ILIKE $1 OR artist_name ILIKE $1)`;
            params.push(`%${keyword}%`);
        }
        query += sortType === 'popular' ? ` ORDER BY view_count DESC` : ` ORDER BY created_at DESC`;
        query += ` LIMIT 50`;
        const result = await pool.query(query, params);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

router.post('/:id/view', async (req, res) => {
    const { id } = req.params;
    try {
        await pool.query('UPDATE songs SET view_count = view_count + 1 WHERE song_id = $1', [id]);
        res.json({ status: 'success' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

router.get('/:id', async (req, res) => {
    const { id } = req.params;
    try {
        const result = await pool.query('SELECT * FROM songs WHERE song_id = $1', [id]);
        if (result.rows.length === 0) return res.status(404).json({ error: 'Not found' });
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;