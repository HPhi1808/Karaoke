require('dotenv').config();
const path = require('path');
const express = require('express');
const cors = require('cors');
const { verifyToken, requireAdmin } = require('./middlewares/auth');

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


// Lấy cấu hình Supabase cho trang Admin
app.get('/api/admin-config', (req, res) => {
    res.json({
        supabaseUrl: process.env.SUPABASE_URL,
        supabaseAnonKey: process.env.SUPABASE_ANON_KEY
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
const userNotificationsRouter = require('./routes/userNotifications');


// --- CẤU HÌNH API ENDPOINTS ---
app.use('/api/auth', authRouter);

// API User
app.use('/api/user/notifications', userNotificationsRouter);

// API Admin (Cần Token + Quyền Admin)
app.use('/api/admin/users', verifyToken, requireAdmin, adminUsersRouter);
app.use('/api/admin/songs', verifyToken, requireAdmin, adminSongsRouter);
app.use('/api/admin/dashboard', verifyToken, requireAdmin, adminDashboardRouter);
app.use('/api/admin/guests', verifyToken, requireAdmin, adminGuestsRouter);
app.use('/api/admin/notifications', verifyToken, requireAdmin, adminNotificationsRouter);


// --- KHỞI CHẠY SERVER ---
app.listen(port, () => {
    console.log(`- Trang User: http://localhost:${port}/`);
    console.log(`- Trang Admin: http://localhost:${port}/admin`);
});