/** @type {import('next').NextConfig} */

// same-origin 프록시: 브라우저는 /api/* 로만 호출하고, Next.js 서버가
// 백엔드(NestJS)로 rewrite 한다. 이렇게 하면 쿠키가 same-origin 으로
// 전달되어 CORS/Cookie Domain 설정이 단순해진다 (task.md Design §10-4).
//
// API_PROXY_TARGET:
//   - Docker Compose: http://api:4000 (compose 내부 DNS)
//   - 로컬 dev:        http://localhost:4020 (override 포트)
const API_PROXY_TARGET = process.env.API_PROXY_TARGET ?? 'http://api:4000';

const nextConfig = {
  reactStrictMode: true,
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: `${API_PROXY_TARGET}/:path*`,
      },
    ];
  },
};

module.exports = nextConfig;
