'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { api, ApiError } from '@/lib/api';
import type { MemberProfile } from '@/lib/types';

type State =
  | { status: 'loading' }
  | { status: 'authed'; member: MemberProfile }
  | { status: 'anon' };

export default function HomePage() {
  const [state, setState] = useState<State>({ status: 'loading' });

  useEffect(() => {
    let active = true;
    api
      .getMe()
      .then((member) => active && setState({ status: 'authed', member }))
      .catch((e) => {
        if (!active) return;
        if (e instanceof ApiError && e.status === 401) {
          setState({ status: 'anon' });
        } else {
          setState({ status: 'anon' });
        }
      });
    return () => {
      active = false;
    };
  }, []);

  return (
    <div className="container">
      <div className="card">
        <h1>게시판에 오신 것을 환영합니다</h1>
        <p className="subtitle">
          회원 모듈 데모 — 가입, 로그인, 내 정보 수정, 로그아웃
        </p>

        {state.status === 'loading' && (
          <div className="center-state">불러오는 중…</div>
        )}

        {state.status === 'anon' && (
          <div className="stack">
            <Link href="/login" className="btn">
              로그인
            </Link>
            <Link href="/signup" className="btn btn--ghost">
              회원가입
            </Link>
          </div>
        )}

        {state.status === 'authed' && (
          <div className="stack">
            <p className="muted">
              <strong>{state.member.nickname}</strong>님으로 로그인되어 있습니다.
            </p>
            <Link href="/me" className="btn">
              내 정보 보기
            </Link>
          </div>
        )}
      </div>
    </div>
  );
}
