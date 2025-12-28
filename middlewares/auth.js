const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseKey) {
    throw new Error('Thiếu cấu hình Supabase trong .env');
}

const supabase = createClient(supabaseUrl, supabaseKey);

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
        // 1. Xác thực Token với Supabase Auth
        const { data: { user }, error } = await supabase.auth.getUser(token);

        if (error || !user) {
            return res.status(403).json({
                status: 'error',
                message: 'Token không hợp lệ hoặc đã hết hạn'
            });
        }

        // 2. Kiểm tra thông tin bổ sung trong Database (Role, Lock status)
        const { data: publicUser, error: dbError } = await supabase
            .from('users')
            .select('locked_until, role')
            .eq('id', user.id)
            .maybeSingle();

        // 3. Kiểm tra khóa tài khoản
        if (!dbError && publicUser) {
            if (publicUser.locked_until && new Date(publicUser.locked_until) > new Date()) {
                const unlockTime = new Date(publicUser.locked_until).toLocaleString('vi-VN');
                return res.status(403).json({
                    status: 'locked',
                    message: `Tài khoản tạm khoá đến: ${unlockTime}. Liên hệ Admin.`
                });
            }
        }

        // 4. Xác định Role cuối cùng
        // Ưu tiên 1: Lấy từ bảng users
        // Ưu tiên 2: Lấy từ app_metadata
        // Ưu tiên 3: Nếu là guest anonymous thì role là guest
        // Mặc định: user
        
        let finalRole = 'user';
        
        if (publicUser?.role) {
            finalRole = publicUser.role;
        } else if (user.app_metadata?.role) {
            finalRole = user.app_metadata.role;
        } else if (user.is_anonymous) {
            finalRole = 'guest';
        }

        // 5. Gắn thông tin vào Request
        req.user = {
            user_id: user.id,
            email: user.email || (user.is_anonymous ? 'guest' : null),
            role: finalRole,
            is_guest: user.is_anonymous || false
        };

        next();

    } catch (err) {
        console.error("Auth Middleware Error:", err.message);
        return res.status(500).json({
            status: 'error',
            message: 'Lỗi xác thực hệ thống'
        });
    }
};

const requireAdmin = (req, res, next) => {
    if (!req.user) return res.status(401).json({ message: 'Chưa xác thực' });
    
    // Chấp nhận cả admin và owner
    if (req.user.role === 'own' || req.user.role === 'admin') {
        return next();
    }

    return res.status(403).json({ 
        status: 'error', 
        message: 'Truy cập bị từ chối. Cần quyền Admin.' 
    });
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