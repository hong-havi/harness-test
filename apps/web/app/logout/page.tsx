'use client';

import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { api } from '@/lib/api';

/**
 * /logout 로 직접 진입 시에도 동작하도록 하는 경로.
 * (주 로그아웃 경로는 Header 의 로그아웃 버튼.)
 */
export default function LogoutPage() {
  const router = useRouter();

  useEffect(() => {
    let active = true;
    api
      .logout()
      .catch(() => {
        // 실패해도 클라이언트는 로그인 페이지로 이동.
      })
      .finally(() => {
        if (!active) return;
        router.replace('/login');
        router.refresh();
      });
    return () => {
      active = false;
    };
  }, [router]);

  return (
    <div className="container">
      <div className="card center-state">로그아웃 중…</div>
    </div>
  );
}
