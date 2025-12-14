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
app.use(express.static(path.join(__dirname, 'public')));

app.use(express.static(path.join(__dirname, 'public'), {
    setHeaders: function (res, path) {
        if (path.endsWith('.html')) {
            res.header('Cache-Control', 'private, no-cache, no-store, must-revalidate');
            res.header('Expires', '-1');
            res.header('Pragma', 'no-cache');
        }
    }
}));

// Phục vụ các trang admin riêng
app.use('/admin', express.static(path.join(__dirname, 'public/admin')));
app.use('/assets', express.static(path.join(__dirname, 'public/assets')));

// Trang login
app.get('/', noCache, (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'login.html'));
});

// Vào thẳng base khi gõ /admin
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'public/admin/base.html'));
});

// Import routers
const authRouter = require('./routes/auth');
const adminUsersRouter = require('./routes/adminUsers');
const adminSongsRouter = require('./routes/adminSongs');
const appUsersRoutes = require('./routes/appUsers');
const appSongsRouter = require('./routes/appSongs');
const appRoomsRouter = require('./routes/appRooms');
const appMomentsRouter = require('./routes/appMoments');
const appChatRouter = require('./routes/appChat');

// Use routers
app.use('/api/auth', authRouter);
app.use('/api/admin/users', verifyToken, requireAdmin, adminUsersRouter);
app.use('/api/admin/songs', verifyToken, requireAdmin, adminSongsRouter);
app.use('/api/user', verifyToken, appUsersRoutes);
app.use('/api/songs', appSongsRouter);
app.use('/api/rooms', appRoomsRouter);
app.use('/api/moments', appMomentsRouter);
app.use('/api/chat', verifyToken, appChatRouter);

app.listen(port, () => {
  console.log(`Server đang chạy tại: http://localhost:${port}`);
});