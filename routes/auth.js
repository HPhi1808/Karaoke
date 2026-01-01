const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
const supabaseAdmin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

const ALLOWED_PROVINCES = [
    "TP Hà Nội", "TP Huế", "Quảng Ninh", "Cao Bằng", "Lạng Sơn", "Lai Châu",
    "Điện Biên", "Sơn La", "Thanh Hóa", "Nghệ An", "Hà Tĩnh", "Tuyên Quang",
    "Lào Cai", "Thái Nguyên", "Phú Thọ", "Bắc Ninh", "Hưng Yên", "TP Hải Phòng",
    "Ninh Bình", "Quảng Trị", "TP Đà Nẵng", "Quảng Ngãi", "Gia Lai", "Khánh Hòa",
    "Lâm Đồng", "Đắk Lắk", "TP Hồ Chí Minh", "Đồng Nai", "Tây Ninh", "TP Cần Thơ",
    "Vĩnh Long", "Đồng Tháp", "Cà Mau", "An Giang"
];

// --- LUỒNG ĐĂNG KÝ ---

// ============================================================
// BƯỚC 1: GỬI OTP XÁC THỰC EMAIL
// ============================================================
router.post('/register/send-otp', async (req, res) => {
    const { email } = req.body;
    try {
        // 1. KIỂM TRA TÀI KHOẢN TRONG PUBLIC.USERS
        const { data: publicUser } = await supabase
            .from('users')
            .select('username') 
            .eq('email', email)
            .maybeSingle();

        // TRƯỜNG HỢP A: TÀI KHOẢN ĐÃ HOÀN TẤT
        if (publicUser && publicUser.username) {
             if (!publicUser.username.startsWith('guest_')) {
                return res.status(400).json({ status: 'error', message: 'Email này đã được đăng ký và sử dụng!' });
             }
        }
        
        // TRƯỜNG HỢP B: TÀI KHOẢN ĐANG TREO
        const { data: verifyData } = await supabase
            .from('email_verifications')
            .select('*')
            .eq('email', email)
            .maybeSingle();

        // Kiểm tra nhảy bước (Dùng expires_at mới)
        if (verifyData && verifyData.is_verified && verifyData.expires_at) {
            // Kiểm tra xem còn hạn không
            if (new Date() < new Date(verifyData.expires_at)) {
                return res.json({ 
                    status: 'already_verified', 
                    message: 'Email đã được xác thực thành công trước đó. Chuyển sang điền thông tin.' 
                });
            }
        }

        // 3. DỌN DẸP USER RÁC ĐỂ GỬI LẠI TỪ ĐẦU
        const { data: { users } } = await supabaseAdmin.auth.admin.listUsers();
        const existingAuthUser = users.find(u => u.email === email);
        
        if (existingAuthUser) {
            await supabaseAdmin.auth.admin.deleteUser(existingAuthUser.id);
        }

        // 4. GỬI OTP MỚI (Supabase tự gửi email)
        const { error: signUpError } = await supabase.auth.signUp({
            email,
            password: 'temp_password_123',
            options: { emailRedirectTo: null }
        });

        if (signUpError) {
            if (signUpError.message.includes("rate limit")) {
                throw new Error("Gửi yêu cầu quá nhanh. Vui lòng đợi 1 phút.");
            }
            throw signUpError;
        }

        // 5. KHỞI TẠO BẢNG VERIFICATION
        await supabase.from('email_verifications').upsert({
            email: email,
            is_verified: false,
            token: null,
            expires_at: null
        }, { onConflict: 'email' });

        res.json({ status: 'success', message: 'Mã OTP đã được gửi vào Email.' });

    } catch (err) {
        console.error("Lỗi send-otp:", err);
        res.status(400).json({ status: 'error', message: err.message });
    }
});

// ============================================================
// BƯỚC 2: XÁC THỰC MÃ OTP
// ============================================================
router.post('/register/verify-otp', async (req, res) => {
    const { email, token } = req.body;
    try {
        // 1. Xác thực với Supabase Auth
        const { error } = await supabase.auth.verifyOtp({
            email,
            token,
            type: 'signup'
        });

        if (error) throw error;

        // 2. Cập nhật bảng email_verifications
        await supabase.from('email_verifications').upsert({ 
            email, 
            token: token,
            is_verified: true
        }, { onConflict: 'email' }); 

        res.json({ status: 'success', message: 'Xác thực Email thành công.' });
    } catch (err) {
        res.status(400).json({ status: 'error', message: 'Mã OTP không chính xác hoặc đã hết hạn.' });
    }
});

// ============================================================
// BƯỚC 3: HOÀN TẤT ĐĂNG KÝ
// ============================================================
router.post('/register/complete', async (req, res) => {
    const { email, password, full_name, username, gender, region } = req.body;
    
    try {
        // 1. VALIDATION CƠ BẢN
        if (!['Nam', 'Nữ', 'Khác'].includes(gender)) {
            return res.status(400).json({ status: 'error', message: 'Giới tính không hợp lệ.' });
        }
        if (!ALLOWED_PROVINCES.includes(region)) {
             return res.status(400).json({ status: 'error', message: 'Khu vực không hợp lệ.' });
        }

        const usernameRegex = /^[a-zA-Z0-9]+$/;
        if (!usernameRegex.test(username)) {
             return res.status(400).json({ status: 'error', message: 'Tên đăng nhập chỉ được chứa chữ cái và số.' });
        }

        const { data: duplicateUser } = await supabase
            .from('users')
            .select('id')
            .eq('username', username)
            .maybeSingle();

        if (duplicateUser) {
            return res.status(400).json({ status: 'error', message: 'Tên đăng nhập đã được sử dụng. Vui lòng chọn tên khác.' });
        }

        // 2. KIỂM TRA QUYỀN VÀ THỜI HẠN
        const { data: verifyData } = await supabase
            .from('email_verifications')
            .select('*')
            .eq('email', email)
            .maybeSingle();

        if (!verifyData || !verifyData.is_verified) {
            return res.status(400).json({ status: 'error', message: "Vui lòng xác thực OTP trước." });
        }
        
        // Kiểm tra bằng cột expires_at
        if (!verifyData.expires_at || new Date() > new Date(verifyData.expires_at)) {
            return res.status(400).json({ status: 'error', message: "Phiên xác thực đã hết hạn. Vui lòng gửi lại OTP." });
        }

        // 3. TÌM USER AUTH
        const { data: { users } } = await supabaseAdmin.auth.admin.listUsers();
        const existingUser = users.find(u => u.email === email);

        if (!existingUser) {
            return res.status(404).json({ status: 'error', message: "Không tìm thấy tài khoản chờ kích hoạt." });
        }

        // 4. CẬP NHẬT AUTH
        await supabaseAdmin.auth.admin.updateUserById(existingUser.id, { 
            password: password,
            email_confirm: true,
            user_metadata: {
                full_name, username, gender, region, role: 'user'
            }
        });

        // 5. CẬP NHẬT PUBLIC.USERS
        let avatarUrl = 'https://pub-4b88f65058c84573bfc0002391a01edf.r2.dev/PictureApp/defautl.jpg';
        if (gender === 'Nam') avatarUrl = 'https://pub-4b88f65058c84573bfc0002391a01edf.r2.dev/PictureApp/man.jpg';
        if (gender === 'Nữ') avatarUrl = 'https://pub-4b88f65058c84573bfc0002391a01edf.r2.dev/PictureApp/woman.jpg';

        const { error: dbError } = await supabaseAdmin
            .from('users')
            .update({ 
                username: username,
                full_name: full_name,
                role: 'user',
                gender: gender,
                region: region,
                avatar_url: avatarUrl
            })
            .eq('id', existingUser.id);

        if (dbError) throw dbError;

        // 6. DỌN DẸP
        await supabase.from('email_verifications').delete().eq('email', email);

        res.json({ status: 'success', message: 'Đăng ký thành công!' });

    } catch (err) {
        console.error("Lỗi register/complete:", err);
        res.status(400).json({ status: 'error', message: err.message });
    }
});


// --- LUỒNG QUÊN MẬT KHẨU ---

// Bước 1: Gửi OTP recovery
router.post('/forgot-password/send-otp', async (req, res) => {
    const { email } = req.body;
    try {
        // 1. Kiểm tra Email
        const { data: user } = await supabase
            .from('users')
            .select('username, role') 
            .eq('email', email)
            .maybeSingle();

        if (!user || !user.username) {
            return res.status(404).json({ status: 'error', message: 'Email này chưa được đăng ký tài khoản.' });
        }

        if (user.role === 'admin' || user.role === 'own') {
            return res.status(403).json({ 
                status: 'error', 
                message: 'Tài khoản Quản trị không được phép khôi phục mật khẩu qua App.' 
            });
        }

        // 2. KIỂM TRA NHẢY BƯỚC (Dùng expires_at mới)
        const { data: verifyData } = await supabase
            .from('email_verifications')
            .select('*')
            .eq('email', email)
            .maybeSingle();

        if (verifyData && verifyData.is_verified && verifyData.expires_at) {
            if (new Date() < new Date(verifyData.expires_at)) {
                return res.json({ status: 'already_verified', message: 'Phiên xác thực vẫn còn hiệu lực.' });
            }
        }

        // 3. Gửi OTP Recovery
        const { error } = await supabase.auth.resetPasswordForEmail(email);
        if (error) throw error;

        // Reset lại bảng verification
        await supabase.from('email_verifications').upsert({
            email: email,
            is_verified: false,
            token: null,
            expires_at: null
        }, { onConflict: 'email' });

        res.json({ status: 'success', message: 'Mã OTP đặt lại mật khẩu đã được gửi.' });

    } catch (err) {
        res.status(400).json({ status: 'error', message: err.message });
    }
});

// Bước 2: Verify OTP recovery
router.post('/forgot-password/verify-otp', async (req, res) => {
    const { email, token } = req.body;
    try {
        const { data, error } = await supabase.auth.verifyOtp({ email, token, type: 'recovery' });
        if (error) throw error;

        // Trigger DB sẽ tự động set expires_at
        await supabase.from('email_verifications').upsert({ 
            email, 
            token: token,
            is_verified: true
        }, { onConflict: 'email' });

        res.json({ 
            status: 'success', 
            temp_token: data.session.access_token 
        });
    } catch (err) {
        res.status(400).json({ status: 'error', message: 'Mã OTP không đúng hoặc hết hạn.' });
    }
});

// Bước 3: Đặt lại mật khẩu mới
router.post('/forgot-password/reset', async (req, res) => {
    // Client cần gửi: email, new_password, và token (là OTP đã nhập)
    const { email, new_password, token } = req.body; 

    try {
        if (!token) {
            return res.status(400).json({ status: 'error', message: 'Thiếu token xác thực.' });
        }

        // 2. Truy vấn token trong DB và kiểm tra expires_at
        const { data: verifyData } = await supabaseAdmin
            .from('email_verifications')
            .select('*')
            .eq('email', email)
            .eq('token', token)
            .maybeSingle();

        if (!verifyData || !verifyData.is_verified) {
            return res.status(403).json({ status: 'error', message: 'Mã OTP không hợp lệ hoặc chưa được xác thực.' });
        }

        // 3. Kiểm tra thời gian bằng cột expires_at
        if (!verifyData.expires_at || new Date() > new Date(verifyData.expires_at)) {
            // Xóa bản ghi hết hạn
            await supabase.from('email_verifications').delete().eq('email', email);
            return res.status(403).json({ status: 'error', message: 'Phiên xác thực đã hết hạn. Vui lòng thử lại.' });
        }

        // 4. Thực hiện đổi mật khẩu
        const { data: { users } } = await supabaseAdmin.auth.admin.listUsers();
        const user = users.find(u => u.email === email);
        
        if (!user) throw new Error("Không tìm thấy người dùng.");

        const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
            user.id,
            { password: new_password }
        );

        if (updateError) throw updateError;

        // 5. Dọn dẹp
        await supabase.from('email_verifications').delete().eq('email', email);

        res.json({ status: 'success', message: 'Đổi mật khẩu thành công!' });

    } catch (err) {
        res.status(400).json({ status: 'error', message: err.message });
    }
});

// --- LUỒNG ĐĂNG NHẬP (LOGIN) ---
router.post('/login', async (req, res) => {
    const { identifier, password } = req.body;

    try {
        let emailToLogin = identifier.trim();

        if (!emailToLogin.includes('@')) {
            const { data: user, error } = await supabase
                .from('users')
                .select('email')
                .eq('username', emailToLogin)
                .maybeSingle();

            if (error || !user) {
                return res.status(404).json({ status: 'error', message: 'Tên đăng nhập không tồn tại!' });
            }
            emailToLogin = user.email;
        }

        const { data, error } = await supabase.auth.signInWithPassword({
            email: emailToLogin,
            password: password,
        });

        if (error) {
            return res.status(400).json({ status: 'error', message: 'Mật khẩu không chính xác!' });
        }

        const { data: userProfile, error: profileError } = await supabase
            .from('users')
            .select('role, full_name, username, locked_until') 
            .eq('id', data.user.id)
            .maybeSingle(); 

        if (profileError || !userProfile) {
            await supabase.auth.admin.signOut(data.user.id, 'global');
            return res.status(500).json({ status: 'error', message: 'Lỗi hệ thống: Không tìm thấy hồ sơ người dùng.' });
        }

        if (userProfile.role !== 'admin' && userProfile.role !== 'own') {
            await supabaseAdmin.rpc('force_revoke_user', { 
                target_user_id: data.user.id
            });
            return res.status(403).json({ status: 'error', message: 'Bạn không có quyền truy cập Admin!' });
        }

        const now = new Date().getTime();
        const lockTime = userProfile.locked_until ? new Date(userProfile.locked_until).getTime() : 0;

        if (lockTime > now) {
            const unlockTimeStr = new Date(userProfile.locked_until).toLocaleString('vi-VN', {
                timeZone: 'Asia/Ho_Chi_Minh',
                hour12: false
            });

            await supabaseAdmin.rpc('force_revoke_user', { 
                target_user_id: data.user.id 
            });

            return res.status(403).json({ 
                status: 'locked', 
                message: `Tài khoản đang bị tạm khóa đến: ${unlockTimeStr}. Vui lòng quay lại sau.` 
            });
        }

        res.json({
            status: 'success',
            message: 'Đăng nhập thành công!',
            access_token: data.session.access_token,
            refresh_token: data.session.refresh_token,
            user: {
                id: data.user.id,
                email: emailToLogin,
                username: userProfile.username,
                full_name: userProfile.full_name,
                role: userProfile.role
            }
        });

    } catch (err) {
        console.error("Login System Error:", err); 
        res.status(500).json({ status: 'error', message: 'Lỗi Server: ' + err.message });
    }
});

// --- LUỒNG ĐĂNG XUẤT (LOGOUT) ---
router.post('/logout', async (req, res) => {
    const { userId } = req.body;
    if (!userId) return res.status(400).json({ status: 'error', message: 'Thiếu userId' });

    try {
        const { error } = await supabaseAdmin.rpc('force_revoke_user', {
            target_user_id: userId 
        });

        if (error) {
            console.error("Lỗi RPC:", error);
            throw error;
        }

        res.json({ status: 'success', message: 'Đăng xuất và thu hồi token thành công.' });

    } catch (err) {
        console.error("[Logout Error]", err);
        res.status(200).json({ status: 'success', message: 'Đã xử lý (có cảnh báo).' });
    }
});

router.post('/cleanup-guest', async (req, res) => {
    const { guest_id } = req.body;
    if (!guest_id) return res.status(400).json({ message: 'Thiếu guest_id' });

    try {
        const { error } = await supabaseAdmin.auth.admin.deleteUser(guest_id);
        if (error) throw error;
        await supabaseAdmin.from('users').delete().eq('id', guest_id);
        res.json({ status: 'success', message: 'Đã xóa guest thành công' });
    } catch (err) {
        console.error("Lỗi xóa guest:", err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

module.exports = router;