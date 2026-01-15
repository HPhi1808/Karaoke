const { createClient } = require('@supabase/supabase-js');

const supabaseOptions = {
    auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false
    }
};

// 1. Khởi tạo Client CHÍNH
const mainClient = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    supabaseOptions
);

// 2. Khởi tạo Client DỰ PHÒNG (Backup)
const backupClient = (process.env.BACKUP_SUPABASE_URL && process.env.BACKUP_SUPABASE_SERVICE_ROLE_KEY)
    ? createClient(process.env.BACKUP_SUPABASE_URL, process.env.BACKUP_SUPABASE_SERVICE_ROLE_KEY, supabaseOptions)
    : null;

// 3. Biến cờ để theo dõi trạng thái (Lưu trên RAM của server)
let isUsingBackup = false;

// 4. Hàm lấy client hiện tại
const getSupabaseClient = () => {
    if (isUsingBackup && backupClient) {
        console.log("⚠️ Đang sử dụng BACKUP Database");
        return backupClient;
    }
    return mainClient;
};

// 5. Hàm chuyển đổi (Switch)
const switchDatabase = (useBackup) => {
    if (useBackup && !backupClient) {
        throw new Error("Không có cấu hình Backup trong .env");
    }
    isUsingBackup = useBackup;
    console.log(`🔄 Đã chuyển sang chế độ: ${isUsingBackup ? 'BACKUP' : 'MAIN'}`);
    return isUsingBackup;
};

module.exports = {
    getSupabaseClient,
    switchDatabase,
    isUsingBackup: () => isUsingBackup
};