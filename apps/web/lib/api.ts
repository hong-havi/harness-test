import type {
  JoinInput,
  LoginInput,
  MemberProfile,
  PublicMember,
  SignupInput,
  UpdateMeInput,
} from './types';

// 브라우저는 same-origin 경로(/api/*)로만 호출한다. Next.js rewrites 가
// 백엔드로 프록시하므로 쿠키가 same-origin 으로 전달된다 (task.md §10-4).
const API_BASE = '/api';

const CSRF_COOKIE = 'csrf_token';
// 상태 변경 메소드는 CSRF 헤더가 필요하다 (백엔드 CsrfGuard).
const CSRF_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

/** 백엔드(NestJS) 에러 응답을 감싸는 타입. UI 에서 메시지/상태로 분기. */
export class ApiError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}

/**
 * document.cookie 에서 csrf_token 값을 읽는다.
 * access_token 은 HttpOnly 라 여기서 읽히지 않는다 (의도된 동작).
 * 서버 컴포넌트/SSR 에서는 document 가 없으므로 undefined.
 */
function readCsrfToken(): string | undefined {
  if (typeof document === 'undefined') return undefined;
  const match = document.cookie
    .split('; ')
    .find((row) => row.startsWith(`${CSRF_COOKIE}=`));
  if (!match) return undefined;
  const value = match.slice(CSRF_COOKIE.length + 1);
  return value ? decodeURIComponent(value) : undefined;
}

type JsonBody = Record<string, unknown> | undefined;

async function request<T>(
  method: string,
  path: string,
  body?: JsonBody,
): Promise<T> {
  const headers: Record<string, string> = {};
  const init: RequestInit = {
    method,
    // 쿠키(access_token/csrf_token) 전달 — same-origin 이라도 명시.
    credentials: 'include',
    headers,
  };

  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(body);
  }

  if (CSRF_METHODS.has(method.toUpperCase())) {
    const csrf = readCsrfToken();
    if (csrf) {
      headers['X-CSRF-Token'] = csrf;
    }
  }

  const res = await fetch(`${API_BASE}${path}`, init);

  if (res.status === 204) {
    return undefined as T;
  }

  // 응답이 JSON 이 아닐 수도 있으므로 방어적으로 파싱.
  const text = await res.text();
  let data: unknown = undefined;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }

  if (!res.ok) {
    throw new ApiError(res.status, extractErrorMessage(data, res.status));
  }

  return data as T;
}

/** NestJS 에러 바디 { statusCode, message, error } 에서 사람이 읽을 메시지 추출. */
function extractErrorMessage(data: unknown, status: number): string {
  if (data && typeof data === 'object' && 'message' in data) {
    const msg = (data as { message: unknown }).message;
    if (Array.isArray(msg)) return msg.join(', ');
    if (typeof msg === 'string') return msg;
  }
  if (typeof data === 'string' && data.length > 0) return data;
  return `요청에 실패했습니다. (HTTP ${status})`;
}

export const api = {
  signup(input: SignupInput): Promise<PublicMember> {
    return request<PublicMember>('POST', '/auth/signup', { ...input });
  },
  join(input: JoinInput): Promise<PublicMember> {
    return request<PublicMember>('POST', '/auth/join', { ...input });
  },
  login(input: LoginInput): Promise<PublicMember> {
    return request<PublicMember>('POST', '/auth/login', { ...input });
  },
  logout(): Promise<{ ok: boolean }> {
    return request<{ ok: boolean }>('POST', '/auth/logout');
  },
  getMe(): Promise<MemberProfile> {
    return request<MemberProfile>('GET', '/members/me');
  },
  updateMe(input: UpdateMeInput): Promise<MemberProfile> {
    return request<MemberProfile>('PATCH', '/members/me', { ...input });
  },
};
