const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

// Khởi tạo Supabase
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseKey) {
    throw new Error('Thiếu cấu hình Supabase trong .env');
}

const supabase = createClient(supabaseUrl, supabaseKey);

// --- 1. Middleware Xác thực & Lấy Metadata ---
const verifyToken = async (req, res, next) => {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({
            status: 'error',
            message: 'Token không tồn tại hoặc sai định dạng'
        });
    }

    const token = authHeader.split(' ')[1];

    try {
        // Gọi Supabase Auth để kiểm tra Token và lấy thông tin User mới nhất
        const { data: { user }, error } = await supabase.auth.getUser(token);

        if (error || !user) {
            return res.status(403).json({
                status: 'error',
                message: 'Token không hợp lệ hoặc đã hết hạn'
            });
        }

        // --- QUAN TRỌNG: LẤY ROLE TỪ METADATA ---
        // user.user_metadata tương ứng với cột raw_user_meta_data trong DB
        const userRole = user.user_metadata?.role || 'user';

        // Gắn thông tin vào request
        req.user = {
            user_id: user.id,
            email: user.email,
            role: userRole 
        };

        next();

    } catch (err) {
        console.error("Auth Middleware Error:", err);
        return res.status(500).json({
            status: 'error',
            message: 'Lỗi xác thực hệ thống'
        });
    }
};

// --- 2. Các hàm kiểm tra quyền (Giữ nguyên) ---
const requireAdmin = (req, res, next) => {
    if (!req.user) return res.status(401).json({ message: 'Chưa xác thực' });
    
    // Role 'own' quyền cao nhất
    if (req.user.role === 'own') return next(); 

    if (req.user.role !== 'admin') {
        return res.status(403).json({ 
            status: 'error', 
            message: 'Truy cập bị từ chối. Cần quyền Admin.' 
        });
    }
    next();
};

const requireOwn = (req, res, next) => {
    if (!req.user || req.user.role !== 'own') {
        return res.status(403).json({ 
            status: 'error', 
            message: 'Truy cập bị từ chối. Cần quyền Owner.' 
        });
    }
    next();
};

module.exports = { verifyToken, requireAdmin, requireOwn };