const pool = require('../config/db');
const { getSupabaseClient } = require('../config/supabaseClient');
require('dotenv').config();

const supabase = getSupabaseClient();

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
        // ============================================================
        // BƯỚC 1: XÁC THỰC VỚI SUPABASE
        // ============================================================
        let userAuth;
        try {
            const { data, error } = await supabase.auth.getUser(token);
            if (error) throw error;
            userAuth = data.user;
        } catch (networkOrAuthError) {
            if (networkOrAuthError.message.includes('fetch failed') || 
                networkOrAuthError.code === 'ECONNRESET') {
                console.error("🔥 Lỗi kết nối Supabase:", networkOrAuthError.message);
                return res.status(503).json({ 
                    status: 'error', 
                    message: 'Lỗi kết nối đến server xác thực. Vui lòng thử lại sau.' 
                });
            }
            // Nếu là lỗi Auth (hết hạn, sai token) thì ném xuống catch dưới
            throw networkOrAuthError;
        }

        if (!userAuth) throw new Error('AuthFailed');

        // ============================================================
        // BƯỚC 2: LẤY THÔNG TIN DB & SESSION ID
        // ============================================================
        
        // Lấy thêm cột current_session_id để so sánh
        const userQuery = await pool.query(
            'SELECT role, locked_until, current_session_id FROM users WHERE id = $1',
            [userAuth.id]
        );
        
        const dbUser = userQuery.rows[0];

        // 2.1. Kiểm tra tài khoản bị xóa
        if (!dbUser && !userAuth.is_anonymous) {
             return res.status(401).json({ status: 'error', message: 'Tài khoản không tồn tại trong hệ thống.' });
        }

        // 2.2. Kiểm tra khóa tài khoản
        if (dbUser && dbUser.locked_until && new Date(dbUser.locked_until) > new Date()) {
            const unlockTime = new Date(dbUser.locked_until).toLocaleString('vi-VN');
            return res.status(403).json({
                status: 'locked',
                message: `Tài khoản tạm khoá đến: ${unlockTime}. Liên hệ Admin.`
            });
        }

        // 2.3. KIỂM TRA SESSION MATCHING
        if (dbUser && dbUser.current_session_id) {
            // Giải mã token để lấy session_id bên trong nó
            const payload = decodeTokenPayload(token);
            const tokenSessionId = payload?.session_id;

            // Nếu DB có session ID mà khác với Session ID trong Token -> ĐÁ
            if (tokenSessionId && dbUser.current_session_id !== tokenSessionId) {
                return res.status(401).json({
                    status: 'error',
                    message: 'Phiên đăng nhập hết hạn hoặc không hợp lệ (Logged in elsewhere)'
                });
            }
        }

        // ============================================================
        // BƯỚC 3: XÁC ĐỊNH ROLE & GẮN VÀO REQ
        // ============================================================
        let finalRole = 'user';
        
        if (dbUser?.role) {
            finalRole = dbUser.role;
        } else if (userAuth.app_metadata?.role) {
            finalRole = userAuth.app_metadata.role; 
        } else if (userAuth.is_anonymous) {
            finalRole = 'guest';
        }

        req.user = {
            user_id: userAuth.id,
            email: userAuth.email || (userAuth.is_anonymous ? 'guest' : null),
            role: finalRole,
            is_guest: userAuth.is_anonymous || false
        };

        next();

    } catch (err) {
        // console.error("Auth Middleware Verify Error:", err.message);
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
        
        // Fire and Forget (Chạy ngầm không chờ)
        pool.query("UPDATE users SET last_active_at = NOW() WHERE id = $1", [userId])
            .catch(err => {
                // Không log lỗi connection reset để tránh rác log
                if (err.code !== 'ECONNRESET') {
                    console.error("Update Active Error:", err.message);
                }
            });
    }
    next();
};

module.exports = { verifyToken, requireAdmin, requireOwn, updateActivityMiddleware };