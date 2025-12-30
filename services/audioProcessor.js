const ffmpeg = require('fluent-ffmpeg');
const ffmpegPath = require('@ffmpeg-installer/ffmpeg').path;
const fs = require('fs');

// Cấu hình đường dẫn FFmpeg
ffmpeg.setFfmpegPath(ffmpegPath);

/**
 * Hàm nén file Audio
 * @param {string} inputPath - Đường dẫn file gốc (vừa upload lên temp)
 * @param {string} outputPath - Đường dẫn file đích (sau khi nén)
 * @returns {Promise<string>} - Trả về đường dẫn file đã nén
 */
const compressAudio = (inputPath, outputPath) => {
    return new Promise((resolve, reject) => {
        ffmpeg(inputPath)
            .audioBitrate('128k') // Nén xuống 128kbps (Mức tối ưu cho Karaoke)
            .audioFrequency(44100) // Chuẩn tần số âm thanh
            .audioChannels(2) // Stereo
            .noVideo() // Đảm bảo bỏ hết video/ảnh cover nếu có
            .on('end', () => {
                console.log('✅ Đã nén xong audio:', outputPath);
                resolve(outputPath);
            })
            .on('error', (err) => {
                console.error('❌ Lỗi nén audio:', err);
                reject(err);
            })
            .save(outputPath); // Bắt đầu xử lý và lưu
    });
};

module.exports = { compressAudio };