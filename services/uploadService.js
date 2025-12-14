// services/uploadService.js
require('dotenv').config();
const { S3Client } = require('@aws-sdk/client-s3');
const { Upload } = require('@aws-sdk/lib-storage');
const { DeleteObjectCommand } = require('@aws-sdk/client-s3');
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

// 2. Cấu hình Multer: Lưu file tạm vào RAM để upload cho nhanh
const upload = multer({ storage: multer.memoryStorage() });

// 3. Hàm upload file lên R2
async function uploadToR2(file, folderName) {
    if (!file) return null; // Nếu không có file thì bỏ qua

    // Tạo tên file: folder/thời-gian-tên-gốc (để tránh trùng tên)
    // Ví dụ: beats/170252525-em-cua-ngay-hom-qua.mp3
    const fileName = `${folderName}/${Date.now()}-${file.originalname.replace(/\s+/g, '-')}`;

    try {
        const uploadParallel = new Upload({
            client: r2Client,
            params: {
                Bucket: process.env.R2_BUCKET_NAME,
                Key: fileName,
                Body: file.buffer,
                ContentType: file.mimetype,
            },
        });

        await uploadParallel.done();

        // Trả về đường dẫn công khai để lưu vào Database
        return `${process.env.R2_PUBLIC_DOMAIN}/${fileName}`;
    } catch (error) {
        console.error("Lỗi upload R2:", error);
        throw error;
    }
}


async function deleteFromR2(fullUrl) {
    if (!fullUrl) return;

    try {
        const domain = process.env.R2_PUBLIC_DOMAIN + '/';
        const key = fullUrl.replace(domain, '');

        const command = new DeleteObjectCommand({
            Bucket: process.env.R2_BUCKET_NAME,
            Key: key,
        });

        await r2Client.send(command);
        console.log("Đã xóa file cũ:", key);
    } catch (error) {
        console.error("Lỗi xóa file R2:", error);
        // Không throw lỗi ở đây để tránh làm sập luồng update nếu xóa file cũ thất bại
    }
}

module.exports = { upload, uploadToR2, deleteFromR2 };