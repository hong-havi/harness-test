import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

// 보호 라우트 1차 가드.
// access_token 쿠키 유무만으로 빠르게 미인증 사용자를 /login 으로 보낸다.
// 이는 UX 편의일 뿐이며 보안 경계가 아니다 — 쿠키 유효성(만료/위조) 검증은
// 서버 Guard(AuthGuard('jwt'))가, 2차 방어는 /me 페이지의 401 처리가 담당한다.
// (access_token 은 HttpOnly 라 미들웨어(서버)에서만 읽을 수 있고 JS 는 접근 불가.)
const PROTECTED_PREFIXES = ['/me'];

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  const isProtected = PROTECTED_PREFIXES.some(
    (p) => pathname === p || pathname.startsWith(`${p}/`),
  );
  if (!isProtected) {
    return NextResponse.next();
  }

  const hasToken = Boolean(req.cookies.get('access_token')?.value);
  if (hasToken) {
    return NextResponse.next();
  }

  const loginUrl = req.nextUrl.clone();
  loginUrl.pathname = '/login';
  loginUrl.search = '';
  return NextResponse.redirect(loginUrl);
}

export const config = {
  // /me 및 하위 경로에만 미들웨어 적용.
  matcher: ['/me/:path*', '/me'],
};
