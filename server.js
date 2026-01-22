require('dotenv').config();
const path = require('path');
const express = require('express');
const cors = require('cors');
const { verifyToken, requireAdmin } = require('./middlewares/auth');
const { isUsingBackup } = require('./config/supabaseClient');

const app = express();
const corsOptions = {
    origin: [
        'https://app.karaokeplus.cloud',
        'https://karaokeplus.cloud',
        'http://localhost:3000',
    ],
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true
};

app.use(cors(corsOptions));
const port = process.env.PORT || 3000;

const noCache = (req, res, next) => {
    res.header('Cache-Control', 'private, no-cache, no-store, must-revalidate');
    res.header('Expires', '-1');
    res.header('Pragma', 'no-cache');
    next();
};

app.use(express.json());

// --- CẤU HÌNH TĨNH (STATIC FILES) ---

// 1. Phục vụ toàn bộ thư mục public
app.use(express.static(path.join(__dirname, 'public'), {
    setHeaders: function (res, path) {
        if (path.endsWith('.html')) {
            res.header('Cache-Control', 'private, no-cache, no-store, must-revalidate');
            res.header('Expires', '-1');
        }
    }
}));

// 2. Phục vụ riêng thư mục admin
app.use('/admin', express.static(path.join(__dirname, 'public/admin')));


// --- ĐỊNH TUYẾN TRANG WEB (ROUTING VIEW) ---

// 1. Trang chủ (Người dùng thường)
app.get('/', noCache, (req, res) => {
    res.sendFile(path.join(__dirname, 'public/user/welcome.html'));
});

app.get('/support', noCache, (req, res) => {
    res.sendFile(path.join(__dirname, 'public/user/support.html'));
});

app.get('/policy', noCache, (req, res) => {
    res.sendFile(path.join(__dirname, 'public/user/policy.html'));
});

app.get('/reviews', noCache, (req, res) => {
    res.sendFile(path.join(__dirname, 'public/user/reviews.html'));
});



// Lấy cấu hình Supabase cho trang Admin
app.get('/api/admin-config', (req, res) => {
    const useBackup = isUsingBackup();
    if (useBackup) {
        console.log("⚠️ Admin UI đang yêu cầu config của BACKUP DB");
        return res.json({
            supabaseUrl: process.env.BACKUP_SUPABASE_URL,
            supabaseAnonKey: process.env.BACKUP_SUPABASE_ANON_KEY,
            mode: 'backup'
        });
    }
    res.json({
        supabaseUrl: process.env.SUPABASE_URL,
        supabaseAnonKey: process.env.SUPABASE_ANON_KEY,
        mode: 'main'
    });
});

// Lấy cấu hình Supabase cho app người dùng
app.get('/api/app-config', (req, res) => {
    const useBackup = isUsingBackup();

    if (useBackup) {
        return res.json({
            supabaseUrl: process.env.BACKUP_SUPABASE_URL,
            supabaseAnonKey: process.env.BACKUP_SUPABASE_ANON_KEY,
            isBackup: true
        });
    }

    return res.json({
        supabaseUrl: process.env.SUPABASE_URL,
        supabaseAnonKey: process.env.SUPABASE_ANON_KEY,
        isBackup: false
    });
});

// 2. Trang Admin
app.get('/admin', noCache, (req, res) => {
    res.sendFile(path.join(__dirname, 'public/admin/login.html'));
});


// --- IMPORT ROUTERS API ---
const authRouter = require('./routes/auth');
const adminUsersRouter = require('./routes/adminUsers');
const adminSongsRouter = require('./routes/adminSongs');
const adminDashboardRouter = require('./routes/adminDashboard');
const adminGuestsRouter = require('./routes/adminGuests');
const adminNotificationsRouter = require('./routes/adminNotifications');
const adminReportsRouter = require('./routes/adminReports');
const adminMomentsRouter = require('./routes/adminMoments');
const adminEventsRouter = require('./routes/adminEvents');
const userNotificationsRouter = require('./routes/userNotifications');
const userReviewsRouter = require('./routes/reviewsUser');
const userMomentsRouter = require('./routes/userMoments');
const userUploadAudioRouter = require('./routes/userUploadAudio');
const convertDatabaseRouter = require('./routes/convertDataBase');



// --- CẤU HÌNH API ENDPOINTS ---
app.use('/api/auth', authRouter);
app.use('/api/admin/switch-db', convertDatabaseRouter);
// API get Reviews
app.get('/api/reviews-list', userReviewsRouter.getPublicReviews);

// API User
app.use('/api/user/notifications', userNotificationsRouter);
app.use('/api/user/moments', userMomentsRouter);
app.use('/api/user/upload-audio', userUploadAudioRouter);

// API Admin (Cần Token + Quyền Admin)
app.use('/api/admin/users', verifyToken, requireAdmin, adminUsersRouter);
app.use('/api/admin/songs', verifyToken, requireAdmin, adminSongsRouter);
app.use('/api/admin/dashboard', verifyToken, requireAdmin, adminDashboardRouter);
app.use('/api/admin/guests', verifyToken, requireAdmin, adminGuestsRouter);
app.use('/api/admin/notifications', verifyToken, requireAdmin, adminNotificationsRouter);
app.use('/api/admin/reports', verifyToken, requireAdmin, adminReportsRouter);
app.use('/api/admin/moments', verifyToken, requireAdmin, adminMomentsRouter);
app.use('/api/admin/events', verifyToken, requireAdmin, adminEventsRouter);


// --- KHỞI CHẠY SERVER ---
app.listen(port, () => {
    console.log(`- Trang User: http://localhost:${port}/`);
    console.log(`- Trang Admin: http://localhost:${port}/admin`);
});