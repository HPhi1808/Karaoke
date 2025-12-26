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
        const { data: { user }, error } = await supabase.auth.getUser(token);

        if (error || !user) {
            return res.status(403).json({
                status: 'error',
                message: 'Token không hợp lệ hoặc đã hết hạn'
            });
        }

        const { data: publicUser, error: dbError } = await supabase
            .from('users')
            .select('locked_until, role')
            .eq('id', user.id)
            .single();

        if (!dbError && publicUser) {
            if (publicUser.locked_until && new Date(publicUser.locked_until) > new Date()) {
                
                const unlockTime = new Date(publicUser.locked_until).toLocaleString('vi-VN');
                
                return res.status(403).json({
                    status: 'locked',
                    message: `Tài khoản của bạn đang bị tạm khoá đến: ${unlockTime}. Vui lòng liên hệ Quản trị viên.`
                });
            }
        }
        // ==================================================================

        const finalRole = publicUser?.role || user.user_metadata?.role || 'user';

        req.user = {
            user_id: user.id,
            email: user.email,
            role: finalRole
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

const requireAdmin = (req, res, next) => {
    if (!req.user) return res.status(401).json({ message: 'Chưa xác thực' });
    
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