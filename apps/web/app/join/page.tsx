'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { api, ApiError } from '@/lib/api';

export default function JoinPage() {
  const router = useRouter();
  const [userId, setUserId] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await api.join({ userId, password });
      // 가입 성공 시 자동 로그인하지 않음 (F-M1 정책). 로그인 페이지로 유도.
      router.replace('/login?joined=1');
    } catch (err) {
      setError(
        err instanceof ApiError
          ? err.message
          : '가입 중 오류가 발생했습니다.',
      );
      setSubmitting(false);
    }
  }

  return (
    <div className="container">
      <div className="card">
        <h1>간편 가입</h1>
        <p className="subtitle">아이디와 비밀번호만 입력하면 가입됩니다.</p>

        {error && (
          <div className="alert alert--error" role="alert">
            {error}
          </div>
        )}

        <form onSubmit={onSubmit} noValidate>
          <div className="field">
            <label htmlFor="userId">아이디</label>
            <input
              id="userId"
              name="userId"
              type="text"
              value={userId}
              autoComplete="username"
              onChange={(e) => setUserId(e.target.value)}
              disabled={submitting}
              required
            />
            <span className="field__hint">영문·숫자 4~32자</span>
          </div>

          <div className="field">
            <label htmlFor="password">비밀번호</label>
            <input
              id="password"
              name="password"
              type="password"
              value={password}
              autoComplete="new-password"
              onChange={(e) => setPassword(e.target.value)}
              disabled={submitting}
              required
            />
            <span className="field__hint">8자 이상, 영문과 숫자 조합</span>
          </div>

          <button type="submit" className="btn" disabled={submitting}>
            {submitting ? '처리 중…' : '가입하기'}
          </button>
        </form>

        <p className="form-footer">
          이미 계정이 있으신가요? <Link href="/login">로그인</Link>
        </p>
      </div>
    </div>
  );
}
