const ffmpeg = require('fluent-ffmpeg');
const ffmpegPath = require('@ffmpeg-installer/ffmpeg').path;
const fs = require('fs');

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
            .audioBitrate('128k')
            .audioFrequency(44100)
            .audioChannels(2)
            .noVideo()
            .on('end', () => {
                console.log('✅ Đã nén xong audio:', outputPath);
                resolve(outputPath);
            })
            .on('error', (err) => {
                console.error('❌ Lỗi nén audio:', err);
                reject(err);
            })
            .save(outputPath);
    });
};

module.exports = { compressAudio };