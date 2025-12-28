require('dotenv').config();
const { S3Client, DeleteObjectCommand } = require('@aws-sdk/client-s3');
const { Upload } = require('@aws-sdk/lib-storage');
const multer = require('multer');
const path = require('path');

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
const slugify = (text) => {
    if (!text) return '';
    return text.toString().toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/\s+/g, '-')
        .replace(/[^\w\-]+/g, '')
        .replace(/\-\-+/g, '-')
        .replace(/^-+/, '')
        .replace(/-+$/, '');
};

/**
 * 3. Hàm upload file lên R2 
 * * @param {Object} file - File object từ multer
 * @param {String} folderName - Tên thư mục trên R2 (beats, images, lyrics...)
 * @param {Object} metadata - Thông tin bổ sung { songTitle, artistName, fileType }
 * - fileType: 'vocal', 'beat', 'image', 'lyric'
 */
async function uploadToR2(file, folderName, { songTitle, artistName, fileType } = {}) {
    if (!file) return null;

    let fileName;

    // Lấy đuôi file gốc (ví dụ: .mp3, .jpg, .lrc)
    const fileExt = path.extname(file.originalname).toLowerCase();

    // LOGIC ĐẶT TÊN MỚI
    if (songTitle && artistName) {
        const cleanTitle = slugify(songTitle);
        const cleanArtist = slugify(artistName);

        // Tạo phần cơ bản: ten-bai-hat_ten-ca-si
        let baseName = `${cleanTitle}_${cleanArtist}`;

        // Thêm hậu tố tùy vào loại file
        if (fileType === 'vocal') {
            baseName += '[vocal]';
        } else if (fileType === 'beat') {
            baseName += '[beat]';
        }

        // Ghép thành tên đầy đủ: ten-bai-hat_ten-ca-si[vocal].mp3
        fileName = `${folderName}/${baseName}${fileExt}`;
    } else {
        // Nếu không truyền tên bài hát/ca sĩ, dùng cách đặt tên cũ (timestamp)
        const originalNameSanitized = slugify(path.basename(file.originalname, fileExt));
        fileName = `${folderName}/${Date.now()}-${originalNameSanitized}${fileExt}`;
    }

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
        const domain = process.env.R2_PUBLIC_DOMAIN.replace(/\/$/, ""); 
        // Lấy Key bằng cách loại bỏ domain
        const key = decodeURI(fullUrl.replace(`${domain}/`, ""));

        const command = new DeleteObjectCommand({
            Bucket: process.env.R2_BUCKET_NAME,
            Key: key,
        });

        await r2Client.send(command);
        console.log("Đã xóa file cũ trên R2:", key);
    } catch (error) {
        console.error("Lỗi xóa file R2:", error);
    }
}

module.exports = { upload, uploadToR2, deleteFromR2 };