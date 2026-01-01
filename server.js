require('dotenv').config();
const path = require('path');
const express = require('express');
const cors = require('cors');
const { verifyToken, requireAdmin } = require('./middlewares/auth');

const app = express();
const port = process.env.PORT || 3000;

const noCache = (req, res, next) => {
    res.header('Cache-Control', 'private, no-cache, no-store, must-revalidate');
    res.header('Expires', '-1');
    res.header('Pragma', 'no-cache');
    next();
};

app.use(cors());
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



// 2. Trang Admin
app.get('/admin', noCache, (req, res) => {
    res.sendFile(path.join(__dirname, 'public/admin/login.html'));
});


// --- IMPORT ROUTERS API ---
const authRouter = require('./routes/auth');
const adminUsersRouter = require('./routes/adminUsers');
const adminSongsRouter = require('./routes/adminSongs');
const appUsersRoutes = require('./routes/appUsers');
const appSongsRouter = require('./routes/appSongs');
const adminDashboardRoute = require('./routes/adminDashboard');

// const appRoomsRouter = require('./routes/appRooms');
// const appMomentsRouter = require('./routes/appMoments');
// const appChatRouter = require('./routes/appChat');

// --- CẤU HÌNH API ENDPOINTS ---
app.use('/api/auth', authRouter);

// API Admin (Cần Token + Quyền Admin)
app.use('/api/admin/users', verifyToken, requireAdmin, adminUsersRouter);
app.use('/api/admin/songs', verifyToken, requireAdmin, adminSongsRouter);
app.use('/api/admin/dashboard', verifyToken, requireAdmin, adminDashboardRoute);

// API App (User thường)
app.use('/api/user', verifyToken, appUsersRoutes);
app.use('/api/songs', appSongsRouter);

// app.use('/api/rooms', appRoomsRouter);
// app.use('/api/moments', appMomentsRouter);
// app.use('/api/chat', verifyToken, appChatRouter);

// --- KHỞI CHẠY SERVER ---
app.listen(port, () => {
    console.log(`Server đang chạy tại: http://localhost:${port}`);
    console.log(`- Trang User: http://localhost:${port}/`);
    console.log(`- Trang Admin: http://localhost:${port}/admin`);
});