'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '@/lib/api';
import type { MemberProfile, UpdateMeInput } from '@/lib/types';

type LoadState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; member: MemberProfile };

function formatDate(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleString('ko-KR');
}

// 가입일 전용: 브라우저 로컬 타임존 기준 YYYY-MM-DD.
// getFullYear/getMonth/getDate 는 로컬 TZ 기준이므로 UTC 절단(toISOString)과 달리
// 자정 경계에서 로컬 날짜가 올바르게 반영된다. 파싱 실패 시 원본 문자열 유지.
function formatDateYmd(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export default function MePage() {
  const router = useRouter();
  const [load, setLoad] = useState<LoadState>({ status: 'loading' });

  // 수정 폼 상태
  const [nickname, setNickname] = useState('');
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [formSuccess, setFormSuccess] = useState<string | null>(null);

  const fetchMe = useCallback(async () => {
    setLoad({ status: 'loading' });
    try {
      const member = await api.getMe();
      setLoad({ status: 'ready', member });
      setNickname(member.nickname);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) {
        // 서버가 미인증으로 판정 — 로그인 페이지로.
        router.replace('/login');
        return;
      }
      setLoad({
        status: 'error',
        message:
          e instanceof ApiError ? e.message : '정보를 불러오지 못했습니다.',
      });
    }
  }, [router]);

  useEffect(() => {
    void fetchMe();
  }, [fetchMe]);

  async function onSave(e: React.FormEvent) {
    e.preventDefault();
    setFormError(null);
    setFormSuccess(null);

    if (load.status !== 'ready') return;

    const payload: UpdateMeInput = {};
    const trimmedNick = nickname.trim();
    if (trimmedNick && trimmedNick !== load.member.nickname) {
      payload.nickname = trimmedNick;
    }
    if (newPassword) {
      payload.newPassword = newPassword;
      payload.currentPassword = currentPassword;
    }

    if (Object.keys(payload).length === 0) {
      setFormError('변경할 항목이 없습니다.');
      return;
    }

    setSaving(true);
    try {
      const updated = await api.updateMe(payload);
      setLoad({ status: 'ready', member: updated });
      setNickname(updated.nickname);
      setCurrentPassword('');
      setNewPassword('');
      setFormSuccess('변경사항이 저장되었습니다.');
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) {
        router.replace('/login');
        return;
      }
      setFormError(
        e instanceof ApiError ? e.message : '저장 중 오류가 발생했습니다.',
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="container">
      <div className="card">
        <h1>내 정보</h1>

        {load.status === 'loading' && (
          <div className="center-state">불러오는 중…</div>
        )}

        {load.status === 'error' && (
          <>
            <div className="alert alert--error" role="alert">
              {load.message}
            </div>
            <button type="button" className="btn" onClick={() => void fetchMe()}>
              다시 시도
            </button>
          </>
        )}

        {load.status === 'ready' && (
          <>
            <div className="profile-row">
              <span className="profile-row__label">아이디</span>
              <span>{load.member.userId}</span>
            </div>
            <div className="profile-row">
              <span className="profile-row__label">닉네임</span>
              <span>{load.member.nickname}</span>
            </div>
            <div className="profile-row">
              <span className="profile-row__label">가입일</span>
              <span>{formatDateYmd(load.member.createdAt)}</span>
            </div>
            <div className="profile-row">
              <span className="profile-row__label">최근 수정</span>
              <span>{formatDate(load.member.updatedAt)}</span>
            </div>

            <hr className="divider" />

            <h1 style={{ fontSize: '1.2rem' }}>정보 수정</h1>
            <p className="subtitle">
              닉네임 변경 또는 비밀번호 변경을 할 수 있습니다.
            </p>

            {formError && (
              <div className="alert alert--error" role="alert">
                {formError}
              </div>
            )}
            {formSuccess && (
              <div className="alert alert--success" role="status">
                {formSuccess}
              </div>
            )}

            <form onSubmit={onSave} noValidate>
              <div className="field">
                <label htmlFor="nickname">닉네임</label>
                <input
                  id="nickname"
                  name="nickname"
                  type="text"
                  value={nickname}
                  onChange={(e) => setNickname(e.target.value)}
                  disabled={saving}
                />
                <span className="field__hint">2~32자</span>
              </div>

              <div className="field">
                <label htmlFor="newPassword">새 비밀번호</label>
                <input
                  id="newPassword"
                  name="newPassword"
                  type="password"
                  value={newPassword}
                  autoComplete="new-password"
                  onChange={(e) => setNewPassword(e.target.value)}
                  disabled={saving}
                />
                <span className="field__hint">
                  변경할 때만 입력 · 8자 이상, 영문과 숫자 조합
                </span>
              </div>

              <div className="field">
                <label htmlFor="currentPassword">현재 비밀번호</label>
                <input
                  id="currentPassword"
                  name="currentPassword"
                  type="password"
                  value={currentPassword}
                  autoComplete="current-password"
                  onChange={(e) => setCurrentPassword(e.target.value)}
                  disabled={saving}
                />
                <span className="field__hint">
                  비밀번호 변경 시 확인용으로 필요합니다.
                </span>
              </div>

              <button type="submit" className="btn" disabled={saving}>
                {saving ? '저장 중…' : '변경사항 저장'}
              </button>
            </form>
          </>
        )}
      </div>
    </div>
  );
}
