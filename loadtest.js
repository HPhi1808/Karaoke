import http from 'k6/http';
import { check, sleep } from 'k6';
require('dotenv').config();

// 1. CẤU HÌNH TẢI (100 Users)
export const options = {
  stages: [
    { duration: '30s', target: 20 },   // Khởi động
    { duration: '1m', target: 100 },   // Tăng tốc lên 100
    { duration: '1m', target: 100 },   // Giữ tải 100
    { duration: '30s', target: 0 },    // Giảm tải
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'], // 95% request phải nhanh hơn 2s
    http_req_failed: ['rate<0.01'],    // Tỉ lệ lỗi dưới 1%
  },
};

const NODE_SERVER_URL = 'https://api.karaokeplus.cloud';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;

export default function () {
  
  // --- HÀNH ĐỘNG 1: Gọi Server Node.js (Lấy Config) ---
  const resNode = http.get(`${NODE_SERVER_URL}/api/app-config`);
  
  check(resNode, {
    'NodeJS: Status 200': (r) => r.status === 200,
    'NodeJS: Speed < 500ms': (r) => r.timings.duration < 500,
  });

  sleep(1); 

  // --- HÀNH ĐỘNG 2: Gọi Trực Tiếp Supabase (Lấy Bài Hát) ---
  
  const supabaseParams = {
    headers: {
      'apikey': SUPABASE_ANON_KEY,
      'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
    },
  };

  // Giả sử lấy 10 bài hát đầu tiên
  const resSupabase = http.get(
    `${SUPABASE_URL}/rest/v1/songs?select=*&limit=10`, 
    supabaseParams
  );

  check(resSupabase, {
    'Supabase: Status 200': (r) => r.status === 200,
    'Supabase: Speed < 1s': (r) => r.timings.duration < 1000,
  });

  sleep(2); 
}