require('dotenv').config();
const { S3Client, PutObjectCommand, DeleteObjectCommand } = require('@aws-sdk/client-s3');
const { Upload } = require('@aws-sdk/lib-storage');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// 1. Khởi tạo kết nối R2
const r2Client = new S3Client({
    region: 'auto',
    endpoint: process.env.R2_ENDPOINT,
    credentials: {
        accessKeyId: process.env.R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
    },
});

// 2. Cấu hình Multer
const tempDir = 'uploads/temp/';
if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
}

const storage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, tempDir);
    },
    filename: function (req, file, cb) {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
    }
});

const upload = multer({
    storage: storage,
    limits: { fileSize: 50 * 1024 * 1024 }, // 50MB
    fileFilter: (req, file, cb) => {
        if (file.mimetype.startsWith('audio/') || file.mimetype === 'application/octet-stream') {
            cb(null, true);
        } else {
            cb(new Error('Chỉ chấp nhận file âm thanh!'), false);
        }
    }
});

// Hàm Slugify
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

// Hàm hỗ trợ xóa file local
const cleanupLocalFile = (filePath) => {
    if (fs.existsSync(filePath)) {
        fs.unlink(filePath, (err) => {
            if (err) console.error("Lỗi xóa file temp:", err);
        });
    }
};

/**
 * 3. Hàm upload file lên R2
 */
async function uploadToR2(file, folderName, { songTitle, artistName, fileType } = {}) {
    if (!file) return null;

    if (!fs.existsSync(file.path)) {
        throw new Error(`File không tồn tại tại đường dẫn: ${file.path}`);
    }

    let fileName;
    const fileExt = path.extname(file.originalname).toLowerCase();

    // Logic đặt tên file
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
        const fileStream = fs.createReadStream(file.path);

        const uploadParallel = new Upload({
            client: r2Client,
            params: {
                Bucket: process.env.R2_BUCKET_NAME,
                Key: fileName,
                Body: fileStream,
                ContentType: file.mimetype,
            },
        });

        await uploadParallel.done();
        fileStream.destroy(); 
        cleanupLocalFile(file.path);

        const domain = process.env.R2_PUBLIC_DOMAIN.replace(/\/$/, "");
        return `${domain}/${fileName}`;
    } catch (error) {
        // Nếu lỗi cũng phải xóa file tạm
        cleanupLocalFile(file.path);
        console.error("Lỗi upload R2:", error);
        throw error;
    }
}

async function generatePresignedUrl(fileName, fileType) {
    const command = new PutObjectCommand({
        Bucket: process.env.R2_BUCKET_NAME,
        Key: fileName,
        ContentType: fileType,
        ACL: 'public-read',
    });

    const uploadUrl = await getSignedUrl(r2Client, command, { expiresIn: 300 });
    
    const domain = process.env.R2_PUBLIC_DOMAIN.replace(/\/$/, "");
    const publicUrl = `${domain}/${fileName}`;

    return { uploadUrl, publicUrl };
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

module.exports = { upload, uploadToR2, deleteFromR2, generatePresignedUrl };