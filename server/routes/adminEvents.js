const express = require('express');
const router = express.Router();
const eventService = require('../services/eventService');

// Tạo sự kiện mới
router.post('/', async (req, res) => {
    try {
        const event = await eventService.createEvent(req.body);
        res.status(201).json(event);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Lấy danh sách sự kiện
router.get('/', async (req, res) => {
    try {
        const events = await eventService.getAllEvents();
        res.json(events);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Lấy chi tiết sự kiện
router.get('/:id', async (req, res) => {
    try {
        const event = await eventService.getEventById(req.params.id);
        if (!event) return res.status(404).json({ error: 'Không tìm thấy sự kiện' });
        res.json(event);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Cập nhật sự kiện
router.put('/:id', async (req, res) => {
    try {
        const event = await eventService.updateEvent(req.params.id, req.body);
        if (!event) return res.status(404).json({ error: 'Không tìm thấy sự kiện' });
        res.json(event);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Xóa sự kiện
router.delete('/:id', async (req, res) => {
    try {
        await eventService.deleteEvent(req.params.id);
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;
