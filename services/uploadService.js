// services/uploadService.js
require('dotenv').config();
const { S3Client, DeleteObjectCommand } = require('@aws-sdk/client-s3');
const { Upload } = require('@aws-sdk/lib-storage');
const multer = require('multer');

// 1. Khởi tạo kết nối với Cloudflare R2
const r2Client = new S3Client({
    region: 'auto',
    endpoint: process.env.R2_ENDPOINT,
    credentials: {
        accessKeyId: process.env.R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
    },
});

// 2. Cấu hình Multer: Lưu file tạm vào RAM
const upload = multer({
    storage: multer.memoryStorage(),
    limits: {
        fileSize: 50 * 1024 * 1024, // Giới hạn 50MB
    }
});

// Hàm hỗ trợ: Chuyển tiếng Việt có dấu thành không dấu và slugify
// Ví dụ: "Sơn Tùng M-TP.mp3" -> "son-tung-m-tp.mp3"
const slugify = (text) => {
    return text.toString().toLowerCase()
        .normalize('NFD') // Tách dấu ra khỏi ký tự
        .replace(/[\u0300-\u036f]/g, '') // Xóa các dấu
        .replace(/\s+/g, '-') // Thay khoảng trắng bằng dấu gạch ngang
        .replace(/[^\w\-.]+/g, '') // Xóa các ký tự đặc biệt (giữ lại dấu chấm và gạch ngang)
        .replace(/\-\-+/g, '-') // Thay thế nhiều dấu gạch ngang bằng 1 cái
        .replace(/^-+/, '') // Xóa gạch ngang đầu
        .replace(/-+$/, ''); // Xóa gạch ngang cuối
};

// 3. Hàm upload file lên R2
async function uploadToR2(file, folderName) {
    if (!file) return null;

    const originalNameSanitized = slugify(file.originalname);
    const fileName = `${folderName}/${Date.now()}-${originalNameSanitized}`;

    try {
        const uploadParallel = new Upload({
            client: r2Client,
            params: {
                Bucket: process.env.R2_BUCKET_NAME,
                Key: fileName,
                Body: file.buffer,
                ContentType: file.mimetype,
                // ACL: 'public-read', // R2 thường set public ở level bucket, dòng này có thể bỏ nếu lỗi
            },
        });

        await uploadParallel.done();

        // Trả về đường dẫn công khai
        const domain = process.env.R2_PUBLIC_DOMAIN.replace(/\/$/, ""); 
        return `${domain}/${fileName}`;
    } catch (error) {
        console.error("Lỗi upload R2:", error);
        throw error;
    }
}

// 4. Hàm xóa file trên R2
async function deleteFromR2(fullUrl) {
    if (!fullUrl) return;

    try {
        // [NÂNG CẤP] Logic lấy Key an toàn hơn
        // Ví dụ URL: https://pub-xxx.r2.dev/beats/123-bai-hat.mp3
        // Key cần lấy: beats/123-bai-hat.mp3
        
        // Cách 1: Dùng replace
        const domain = process.env.R2_PUBLIC_DOMAIN.replace(/\/$/, ""); 
        const key = fullUrl.replace(`${domain}/`, "");

        // Cách 2 (An toàn hơn nếu URL chuẩn): 
        // const urlObj = new URL(fullUrl);
        // const key = urlObj.pathname.substring(1); // Bỏ dấu / đầu tiên

        const command = new DeleteObjectCommand({
            Bucket: process.env.R2_BUCKET_NAME,
            Key: key,
        });

        await r2Client.send(command);
        console.log("Đã xóa file cũ trên R2:", key);
    } catch (error) {
        console.error("Lỗi xóa file R2:", error);
        // Không throw lỗi để luồng chính tiếp tục chạy
    }
}

module.exports = { upload, uploadToR2, deleteFromR2 };