'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { api, ApiError } from '@/lib/api';

export default function SignupPage() {
  const router = useRouter();
  const [userId, setUserId] = useState('');
  const [password, setPassword] = useState('');
  const [nickname, setNickname] = useState('');
  const [agreedToTerms, setAgreedToTerms] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    // 약관 미동의 시 제출 차단 (버튼 disabled 와 이중 방어).
    if (!agreedToTerms) {
      setError('이용약관에 동의해야 가입할 수 있습니다.');
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      await api.signup({ userId, password, nickname });
      // 가입 성공 시 자동 로그인하지 않음 (백엔드 정책). 로그인 페이지로 유도.
      router.push('/login?signup=1');
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
        <h1>가입하기</h1>
        <p className="subtitle">계정을 만들어 게시판을 이용하세요.</p>

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

          <div className="field">
            <label htmlFor="nickname">닉네임</label>
            <input
              id="nickname"
              name="nickname"
              type="text"
              value={nickname}
              onChange={(e) => setNickname(e.target.value)}
              disabled={submitting}
              required
            />
            <span className="field__hint">2~32자</span>
          </div>

          <div className="field field--check">
            <label htmlFor="agreeTerms" className="checkbox">
              <input
                id="agreeTerms"
                name="agreeTerms"
                type="checkbox"
                checked={agreedToTerms}
                onChange={(e) => setAgreedToTerms(e.target.checked)}
                disabled={submitting}
              />
              <span>
                <strong>이용약관</strong>에 동의합니다. (필수)
              </span>
            </label>
          </div>

          <button
            type="submit"
            className="btn"
            disabled={submitting || !agreedToTerms}
          >
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
