'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '@/lib/api';
import type { MemberProfile } from '@/lib/types';

type AuthState =
  | { status: 'loading' }
  | { status: 'authed'; member: MemberProfile }
  | { status: 'anon' };

/**
 * 상단 네비게이션. 로그인 여부에 따라 링크를 분기한다.
 * 주의: 이 분기는 UX 편의일 뿐이며 보안 경계가 아니다.
 * 실제 접근 제어는 서버 Guard + middleware 가 담당한다.
 */
export default function Nav() {
  const router = useRouter();
  const [auth, setAuth] = useState<AuthState>({ status: 'loading' });

  const refresh = useCallback(async () => {
    try {
      const member = await api.getMe();
      setAuth({ status: 'authed', member });
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) {
        setAuth({ status: 'anon' });
      } else {
        // 네트워크 등 그 외 에러는 비로그인으로 간주 (UI 는 서버 권위에 의존).
        setAuth({ status: 'anon' });
      }
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const onLogout = useCallback(async () => {
    try {
      await api.logout();
    } catch {
      // 로그아웃 실패여도 클라이언트는 비로그인으로 전환하고 이동.
    }
    setAuth({ status: 'anon' });
    router.push('/login');
    router.refresh();
  }, [router]);

  return (
    <nav className="nav">
      <Link href="/" className="nav__brand">
        게시판
      </Link>
      <div className="nav__links">
        {auth.status === 'loading' && <span className="muted">…</span>}

        {auth.status === 'anon' && (
          <>
            <Link href="/login">로그인</Link>
            <Link href="/signup">회원가입</Link>
            <Link href="/join">간편 가입</Link>
          </>
        )}

        {auth.status === 'authed' && (
          <>
            <span className="muted">{auth.member.nickname}님</span>
            <Link href="/me">내 정보</Link>
            <button
              type="button"
              className="btn btn--ghost"
              onClick={onLogout}
            >
              로그아웃
            </button>
          </>
        )}
      </div>
    </nav>
  );
}
