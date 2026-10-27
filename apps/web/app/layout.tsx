import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import './globals.css';
import Header from './components/Header';

export const metadata: Metadata = {
  title: '게시판 — 회원',
  description: '회원 가입 / 로그인 / 내 정보',
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="ko">
      <body>
        <Header />
        <main>{children}</main>
      </body>
    </html>
  );
}
