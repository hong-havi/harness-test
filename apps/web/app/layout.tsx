import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import './globals.css';
import Nav from './components/Nav';

export const metadata: Metadata = {
  title: '게시판 — 회원',
  description: '회원 가입 / 로그인 / 내 정보',
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="ko">
      <body>
        <Nav />
        <main>{children}</main>
      </body>
    </html>
  );
}
