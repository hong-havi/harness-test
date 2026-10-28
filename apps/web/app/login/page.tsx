'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useState } from 'react';
import { api, ApiError } from '@/lib/api';

function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const justSignedUp = searchParams.get('signup') === '1';
  const justJoined = searchParams.get('joined') === '1';

  const [userId, setUserId] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await api.login({ userId, password });
      router.push('/me');
      router.refresh();
    } catch (err) {
      setError(
        err instanceof ApiError
          ? err.message
          : '로그인 중 오류가 발생했습니다.',
      );
      setSubmitting(false);
    }
  }

  return (
    <div className="card">
      <h1>로그인</h1>
      <p className="subtitle">계정 정보를 입력하세요.</p>

      {(justSignedUp || justJoined) && !error && (
        <div className="alert alert--success" role="status">
          가입이 완료되었습니다. 로그인해 주세요.
        </div>
      )}

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
        </div>

        <div className="field">
          <label htmlFor="password">비밀번호</label>
          <input
            id="password"
            name="password"
            type="password"
            value={password}
            autoComplete="current-password"
            onChange={(e) => setPassword(e.target.value)}
            disabled={submitting}
            required
          />
        </div>

        <button type="submit" className="btn" disabled={submitting}>
          {submitting ? '처리 중…' : '로그인하기'}
        </button>
      </form>

      <p className="form-footer">
        계정이 없으신가요? <Link href="/signup">회원가입</Link>
      </p>
    </div>
  );
}

export default function LoginPage() {
  return (
    <div className="container">
      <Suspense fallback={<div className="card center-state">불러오는 중…</div>}>
        <LoginForm />
      </Suspense>
    </div>
  );
}
