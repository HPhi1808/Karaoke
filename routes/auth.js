const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
// Client với Service Role để thao tác admin khi cần
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
        
        // TRƯỜNG HỢP B: TÀI KHOẢN ĐANG TREO (Username là NULL) HOẶC CHƯA CÓ
        const { data: verifyData } = await supabase
            .from('email_verifications')
            .select('*')
            .eq('email', email)
            .maybeSingle();

        if (verifyData && verifyData.is_verified) {
            const now = new Date();
            const verifiedTime = new Date(verifyData.verified_at);
            const diffMinutes = (now - verifiedTime) / (1000 * 60);

            // Nếu còn hạn 15 phút -> CHO PHÉP NHẢY BƯỚC (Không gửi OTP nữa)
            if (diffMinutes <= 15) {
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

        // 4. GỬI OTP MỚI
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

        // 5. KHỞI TẠO TRẠNG THÁI VERIFY LÀ FALSE
        await supabase.from('email_verifications').upsert({
            email: email,
            is_verified: false,
            verified_at: new Date(0).toISOString()
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

        // 2. Cập nhật bảng email_verifications thành TRUE
        await supabase.from('email_verifications').upsert({ 
            email, 
            is_verified: true, 
            verified_at: new Date().toISOString()
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

        // 2. KIỂM TRA QUYỀN
        const { data: verifyData } = await supabase
            .from('email_verifications')
            .select('*')
            .eq('email', email)
            .maybeSingle();

        if (!verifyData || !verifyData.is_verified) {
            return res.status(400).json({ status: 'error', message: "Vui lòng xác thực OTP trước." });
        }
        
        // Kiểm tra thời hạn 15 phút
        const diffMinutes = (new Date() - new Date(verifyData.verified_at)) / (1000 * 60);
        if (diffMinutes > 15) {
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

        // 6. DỌN DẸP: Xóa verification để kết thúc quy trình
        await supabase.from('email_verifications').delete().eq('email', email);

        res.json({ status: 'success', message: 'Đăng ký thành công!' });

    } catch (err) {
        console.error("Lỗi register/complete:", err);
        res.status(400).json({ status: 'error', message: err.message });
    }
});


// --- LUỒNG QUÊN MẬT KHẨU ---
// Bước 1: Gửi OTP recovery (Có kiểm tra nhảy bước)
router.post('/forgot-password/send-otp', async (req, res) => {
    const { email } = req.body;
    try {
        // 1. Kiểm tra Email có tồn tại và lấy Role
        const { data: user } = await supabase
            .from('users')
            .select('username, role') 
            .eq('email', email)
            .maybeSingle();

        // Kiểm tra tồn tại
        if (!user || !user.username) {
            return res.status(404).json({ status: 'error', message: 'Email này chưa được đăng ký tài khoản.' });
        }

        // --- CHẶN ADMIN & OWNER ---
        if (user.role === 'admin' || user.role === 'own') {
            return res.status(403).json({ 
                status: 'error', 
                message: 'Tài khoản Quản trị không được phép khôi phục mật khẩu qua App. Vui lòng liên hệ Owner hoặc dùng Web Admin.' 
            });
        }
        // ----------------------------------------------

        // 2. KIỂM TRA NHẢY BƯỚC: Nếu đã verify trong vòng 15p
        const { data: verifyData } = await supabase
            .from('email_verifications')
            .select('*')
            .eq('email', email)
            .maybeSingle();

        if (verifyData && verifyData.is_verified) {
            const diffMinutes = (new Date() - new Date(verifyData.verified_at)) / (1000 * 60);
            if (diffMinutes <= 15) {
                return res.json({ status: 'already_verified', message: 'Phiên xác thực vẫn còn hiệu lực.' });
            }
        }

        // 3. Gửi OTP Recovery từ Supabase
        const { error } = await supabase.auth.resetPasswordForEmail(email);
        
        if (error) throw error;

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

        // Lưu trạng thái vào bảng tạm để đánh dấu đã xác thực (để check 15p ở bước sau)
        await supabase.from('email_verifications').upsert({ 
            email, 
            is_verified: true, 
            verified_at: new Date() 
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
    const { email, new_password } = req.body;

    try {
        // 1. Lấy biên lai xác thực
        const { data: verifyData } = await supabase
            .from('email_verifications')
            .select('*')
            .eq('email', email)
            .maybeSingle();

        // Kiểm tra xem đã verify chưa
        if (!verifyData || !verifyData.is_verified) {
            return res.status(403).json({ status: 'error', message: 'Vui lòng xác thực mã OTP trước.' });
        }

        // 2. Kiểm tra thời gian
        const diffMs = new Date().getTime() - new Date(verifyData.verified_at).getTime();
        const diffMinutes = diffMs / (1000 * 60);

        if (diffMinutes > 15) {
            // Nếu quá hạn thì xóa luôn bản ghi cũ
            await supabase.from('email_verifications').delete().eq('email', email);
            return res.status(403).json({ status: 'error', message: 'Phiên xác thực đã hết hạn (15 phút). Vui lòng gửi lại mã.' });
        }

        // 3. Thực hiện đổi mật khẩu bằng quyền Admin (supabaseAdmin)
        const { data: { users } } = await supabaseAdmin.auth.admin.listUsers();
        const user = users.find(u => u.email === email);
        
        if (!user) throw new Error("Không tìm thấy người dùng.");

        const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
            user.id,
            { password: new_password }
        );

        if (updateError) throw updateError;

        // 4. Xóa biên lai sau khi thành công để không dùng lại được lần 2
        await supabase.from('email_verifications').delete().eq('email', email);

        res.json({ status: 'success', message: 'Đổi mật khẩu thành công!' });

    } catch (err) {
        res.status(400).json({ status: 'error', message: err.message });
    }
});

// --- LUỒNG ĐĂNG NHẬP (LOGIN) ---
router.post('/login', async (req, res) => {
    const { identifier, password } = req.body; // identifier có thể là email hoặc username

    try {
        let emailToLogin = identifier.trim();

        // 1. Nếu người dùng nhập Username, ta cần tìm Email tương ứng
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

        // 2. Gọi Supabase để đăng nhập
        const { data, error } = await supabase.auth.signInWithPassword({
            email: emailToLogin,
            password: password,
        });

        if (error) throw error;

        // 3. (Tùy chọn) Kiểm tra xem user này có phải Admin không
        // Nếu trang này chỉ dành cho Admin, bạn cần check role trong bảng users
        const { data: userProfile } = await supabase
            .from('users')
            .select('role, full_name, username')
            .eq('id', data.user.id)
            .single();

        // Ví dụ: chặn nếu không phải admin (bỏ comment nếu cần)
        if (userProfile.role !== 'admin' && userProfile.role !== 'own') {
           return res.status(403).json({ status: 'error', message: 'Bạn không có quyền truy cập Admin!' });
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
        res.status(400).json({ status: 'error', message: 'Sai tài khoản hoặc mật khẩu!' });
    }
});


// API dọn dẹp Guest (Chỉ server mới xóa được user khỏi auth.users)
router.post('/cleanup-guest', async (req, res) => {
    const { guest_id } = req.body;

    if (!guest_id) return res.status(400).json({ message: 'Thiếu guest_id' });

    try {
        // Cần dùng supabaseAdmin (Service Role Key) để xóa user
        const { error } = await supabaseAdmin.auth.admin.deleteUser(guest_id);
        
        if (error) throw error;

        // Xóa luôn dữ liệu trong bảng public.users (nếu chưa cascade)
        await supabaseAdmin.from('users').delete().eq('id', guest_id);

        res.json({ status: 'success', message: 'Đã xóa guest thành công' });
    } catch (err) {
        console.error("Lỗi xóa guest:", err);
        res.status(500).json({ status: 'error', message: err.message });
    }
});

module.exports = router;