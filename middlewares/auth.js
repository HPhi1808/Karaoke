const { createClient } = require('@supabase/supabase-js');
const pool = require('../config/db');
require('dotenv').config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseKey) {
    throw new Error('Thiếu cấu hình Supabase trong .env');
}

const supabase = createClient(supabaseUrl, supabaseKey);

// Hàm giải mã Token nhanh để lấy thông tin user_id
const decodeTokenPayload = (token) => {
    try {
        const base64Url = token.split('.')[1];
        const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
        const jsonPayload = decodeURIComponent(atob(base64).split('').map(function(c) {
            return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
        }).join(''));
        return JSON.parse(jsonPayload);
    } catch (e) {
        return null;
    }
};

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
        // Nếu session đã bị xóa (do đăng nhập nơi khác), hàm này sẽ trả về error hoặc user null
        const { data: { user }, error } = await supabase.auth.getUser(token);

        if (error || !user) {
            throw new Error('AuthFailed');
        }

        // 2. Kiểm tra thông tin bổ sung trong Database (Role, Lock status)
        const userQuery = await pool.query(
            'SELECT role, locked_until FROM users WHERE id = $1',
            [user.id]
        );
        
        const publicUser = userQuery.rows[0];

        // 3. Kiểm tra khóa tài khoản
        if (publicUser) {
            if (publicUser.locked_until && new Date(publicUser.locked_until) > new Date()) {
                const unlockTime = new Date(publicUser.locked_until).toLocaleString('vi-VN');
                return res.status(403).json({
                    status: 'locked',
                    message: `Tài khoản tạm khoá đến: ${unlockTime}. Liên hệ Admin.`
                });
            }
        }

        // 4. Xác định Role cuối cùng
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
        // === LOGIC TẠI SAO TOKEN CHẾT? ===
        
        // Cố gắng giải mã token chết để lấy user_id
        const payload = decodeTokenPayload(token);
        
        if (payload && payload.sub) {
            const userId = payload.sub;

            // Kiểm tra xem User này có đang Online bằng session KHÁC không?
            try {
                // Nếu tìm thấy session -> User đã đăng nhập thành công ở nơi khác
                const activeSession = await pool.query(
                    "SELECT id FROM auth.sessions WHERE user_id = $1 LIMIT 1",
                    [userId]
                );

                if (activeSession.rows.length > 0) {
                    return res.status(409).json({ 
                        status: 'conflict',
                        message: 'Tài khoản đang đăng nhập ở nơi khác' 
                    });
                }
            } catch (dbErr) {
                console.error("Lỗi truy xuất:", dbErr.message);
            }
        }

        // Nếu không có session nào khác -> Hết hạn thật sự hoặc token rác
        console.error("Auth Middleware Error:", err.message);
        return res.status(401).json({
            status: 'error',
            message: 'Phiên đăng nhập hết hạn hoặc không hợp lệ'
        });
    }
};

const requireAdmin = (req, res, next) => {
    if (!req.user) return res.status(401).json({ message: 'Chưa xác thực' });
    
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

const updateActivityMiddleware = async (req, res, next) => {
    // Middleware này phải đặt SAU verifyToken
    if (req.user && req.user.user_id) {
        const userId = req.user.user_id;
        
        // Fire and Forget
        pool.query("UPDATE users SET last_active_at = NOW() WHERE id = $1", [userId])
            .catch(err => console.error("Update Active Error:", err.message));
    }
    next();
};

module.exports = { verifyToken, requireAdmin, requireOwn, updateActivityMiddleware };