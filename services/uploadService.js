require('dotenv').config();
const { S3Client, DeleteObjectCommand } = require('@aws-sdk/client-s3');
const { Upload } = require('@aws-sdk/lib-storage');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// 1. Khởi tạo kết nối với Cloudflare R2
const r2Client = new S3Client({
    region: 'auto',
    endpoint: process.env.R2_ENDPOINT,
    credentials: {
        accessKeyId: process.env.R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
    },
});

// 2. Cấu hình Multer: LƯU FILE VÀO Ổ CỨNG
const tempDir = 'uploads/temp/';
if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
}

const storage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, tempDir);
    },
    filename: function (req, file, cb) {
        // Đặt tên file tạm: fieldname-timestamp.ext
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
    }
});

const upload = multer({
    storage: storage,
    limits: { fileSize: 50 * 1024 * 1024 }, // 50MB
});

// Hàm hỗ trợ: Slugify
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
 * 3. Hàm upload file lên R2 (Sửa để đọc từ path thay vì buffer)
 */
async function uploadToR2(file, folderName, { songTitle, artistName, fileType } = {}) {
    if (!file) return null;

    // Đảm bảo file tồn tại trước khi upload
    if (!fs.existsSync(file.path)) {
        throw new Error(`File không tồn tại tại đường dẫn: ${file.path}`);
    }

    let fileName;
    const fileExt = path.extname(file.originalname).toLowerCase();

    // LOGIC ĐẶT TÊN
    if (songTitle && artistName) {
        const cleanTitle = slugify(songTitle);
        const cleanArtist = slugify(artistName);
        let baseName = `${cleanTitle}_${cleanArtist}`;

        if (fileType === 'vocal') baseName += '[vocal]';
        else if (fileType === 'beat') baseName += '[beat]';

        fileName = `${folderName}/${baseName}${fileExt}`;
    } else {
        const originalNameSanitized = slugify(path.basename(file.originalname, fileExt));
        fileName = `${folderName}/${Date.now()}-${originalNameSanitized}${fileExt}`;
    }

    try {
        // Tạo stream đọc file từ ổ cứng
        const fileStream = fs.createReadStream(file.path);

        const uploadParallel = new Upload({
            client: r2Client,
            params: {
                Bucket: process.env.R2_BUCKET_NAME,
                Key: fileName,
                Body: fileStream, // Dùng Stream thay vì Buffer
                ContentType: file.mimetype,
            },
        });

        await uploadParallel.done();

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