const express = require('express');
const router = express.Router();
const { switchDatabase } = require('../config/supabaseClient');

// API chuyển đổi Database
router.post('/convert', (req, res) => {
    const { secret, use_backup } = req.body;
    if (secret !== 'convert_database_in_supabase') {
        return res.status(403).json({ error: "Sai mật khẩu quản trị" });
    }

    try {
        const status = switchDatabase(use_backup === true);
        return res.json({ 
            success: true, 
            message: `Đã chuyển sang database: ${status ? 'BACKUP' : 'MAIN'}` 
        });
    } catch (e) {
        return res.status(400).json({ error: e.message });
    }
});

module.exports = router;