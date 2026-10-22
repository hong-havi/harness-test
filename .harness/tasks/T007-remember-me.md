---
id: T007
title: remember-me
slug: remember-me
branch: task/T007-remember-me
worktree: .worktrees/T007-remember-me
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: claude }
  - { role: architect,  agent: claude }
  # - { role: designer,   agent: claude, mcp: [figma] }
  - { role: backend,    agent: claude }
  # - { role: frontend,   agent: claude }
  - { role: qa,         agent: claude }
  - { role: reviewer,   agent: claude }
current_role: backend
role_history: []
ports:
  web: 3070
  api: 4070
  db: 3313
compose_project: harness_t007
figma_url: null
blocked_by: []
related_prd: ["§3.2 F-M2 로그인", "§3.3 JWT 정책"]
priority: normal          # high | normal | low
created_at: 2026-10-22
updated_at: 2026-10-22
---

## User Request

# 로그인 "로그인 상태 유지" 체크박스

## 배경 (Why)
현재 로그인은 쿠키 1시간 만료라 자주 재로그인해야 함. 체크박스로 **유지 기간 선택** 할 수 있게 하면 신뢰 기기에서는 편의성, 공용 기기에서는 보안이 모두 가능.

## 요구사항 (What)
`/login` 페이지 폼에 "로그인 상태 유지" 체크박스 추가:
- 체크 → 쿠키 7일 유지 (`Max-Age=604800`)
- 미체크 → 세션 쿠키 (`Max-Age` 생략, 브라우저 종료 시 만료)
- 기본 미체크

## 범위 (Scope)
- **포함**:
  - `apps/web/app/login/page.tsx` 체크박스 UI 추가
  - `apps/api` 로그인 DTO 에 `rememberMe: boolean` optional 필드
  - 로그인 성공 시 쿠키 `Max-Age` 를 조건부 설정
  - unit test: rememberMe=true/false 각각 쿠키 속성 검증
- **제외**:
  - "Remember my email" 같은 다른 저장 기능
  - 모바일 전용 처리
  - "자동 로그인" (biometric 등)

## 수용 기준 (예상)
- [ ] `/login` 체크박스가 보이고 기본 미체크
- [ ] 체크 후 로그인 → 쿠키 `Max-Age=604800` 로 설정됨 (DevTools 확인)
- [ ] 미체크 후 로그인 → `Max-Age` 없음 (session cookie)
- [ ] API 로그인 DTO 가 `rememberMe` 받고 class-validator 검증 통과
- [ ] 기존 로그인 플로우 회귀 없음 (unit test + e2e)

## 제약 / 참고
- PRD §3.3 (JWT 1시간 → 지금 유지 기간 변경 가능하다는 전제)
- 쿠키 속성: HttpOnly·Secure(운영)·SameSite=Lax 유지
- JWT 자체 만료는 그대로 (쿠키 Max-Age 만 조정 — 토큰은 1시간, 쿠키는 7일 보유 중일 수 있음)
  → 실제 세션 유효성은 서버 재발급 로직에 의존 (지금은 미구현. 명시 결정 필요)

## Open questions
- Q1: JWT 자체 만료를 7일로 늘릴지, 아니면 쿠키만 7일 유지하고 만료된 토큰은 재로그인 유도할지?
- Q2: 체크박스 default 값은 **미체크**로 OK?
- Q3: 체크했는데 쿠키가 하루 뒤에 토큰 만료 → 재로그인 시에도 자동 "체크" 유지?

---

_(T007 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_


# T007 — remember-me

## Plan

### Why
현재 로그인 쿠키는 `Max-Age=3600` (1시간) 세션으로 신뢰 기기에서도 매일 수차례 재로그인이 필요하다. "로그인 상태 유지" 체크박스로 쿠키 Max-Age 와 JWT 만료를 조건부로 연장해 신뢰 기기의 편의성(7일)과 공용 기기의 보안(세션 쿠키)을 둘 다 지원한다.

### What
- `/login` 폼에 "로그인 상태 유지" 체크박스 추가 (기본 미체크, 재로그인 시에도 매번 미체크 — localStorage 저장 안 함).
- `POST /auth/login` 요청 바디에 `rememberMe?: boolean` optional 필드 추가.
- `rememberMe === true` → access_token/csrf_token 쿠키 `Max-Age=604800` (7일) + **JWT `expiresIn` 도 7일로 동일 연장**.
- `rememberMe !== true` → 세션 쿠키 (`Max-Age` 미설정) + JWT 만료 기존 1시간 유지.
- 쿠키 그 외 속성(HttpOnly, Secure, SameSite=Lax, Path=/) 변경 없음.

### Scope

**포함**
- `apps/api` `LoginDto` 에 optional `rememberMe: boolean` 필드 (class-validator `@IsBoolean() @IsOptional()`).
- `apps/api` `AuthService.login` — rememberMe 분기로 `expiresIn` 결정, `LoginResult.maxAgeSeconds` 는 쿠키 Max-Age 제어용 (0 이면 session cookie 로 해석).
- `apps/api` `AuthController.login` — `maxAgeSeconds === 0` 일 때 cookie `maxAge` 생략 (session cookie), 아니면 ms 변환해서 설정. `csrf_token` 쿠키도 동일 만료 적용.
- `apps/web` `/login` 페이지 — `<input type="checkbox" id="rememberMe">` + state + 폼 submit 에 전달.
- `apps/web/lib/types.ts` `LoginInput` 에 `rememberMe?: boolean` 추가.
- `apps/web/lib/api.ts` `login()` 가 body 로 그대로 전달 (이미 `...input` 패턴).
- Unit test (`apps/api/src/auth/auth.service.spec.ts`): rememberMe=true/false/undefined 3 케이스 — `maxAgeSeconds` 와 JWT 서명 `expiresIn` 검증.

**제외**
- Refresh token 도입. JWT 만료 뒤 자동 재발급 없음 (PRD §3.3 Refresh 범위 밖 유지).
- "Remember my email", biometric 자동 로그인, 모바일 전용 처리.
- localStorage 로 체크박스 선택값 persist (매번 미체크).
- `logout` 동작 — 기존 그대로 (Max-Age=0 로 즉시 만료).
- 신규 환경변수 추가. 7일(=604800초) 은 서버 상수로 하드코딩.

### Acceptance

**UI (`/login`)**
- [ ] `/login` 페이지에 label "로그인 상태 유지" 와 `type="checkbox"` 입력이 렌더링되고, 초기 상태는 unchecked.
- [ ] 체크박스는 `?signup=1`, `?joined=1`, 에러 상태와 무관하게 노출된다.
- [ ] 로그인 submit 요청 바디에 `rememberMe` (boolean) 필드가 포함된다 (DevTools Network 확인).

**API 쿠키 동작**
- [ ] `POST /auth/login` 바디 `rememberMe: true` 로 요청 → 응답 `Set-Cookie: access_token=...; Max-Age=604800; HttpOnly; SameSite=Lax; Path=/` 과 동일 Max-Age 의 `csrf_token` 쿠키 2개.
- [ ] `POST /auth/login` 바디 `rememberMe: false` (또는 미전송) → 응답 `Set-Cookie` 에 `Max-Age`/`Expires` 속성 **없음** (세션 쿠키).
- [ ] 두 경우 모두 `HttpOnly` (access_token), `SameSite=Lax`, `Path=/` 속성은 유지.

**JWT 만료**
- [ ] `rememberMe: true` 로 로그인 → 응답 쿠키의 JWT payload `exp - iat === 604800`.
- [ ] `rememberMe: false|undefined` 로 로그인 → `exp - iat === 3600` (환경변수 `JWT_EXPIRES_IN` 기본 또는 설정값, 현재 코드와 동일).

**DTO/검증**
- [ ] `LoginDto` 가 `rememberMe` 로 non-boolean (문자열 "yes" 등) 을 받으면 400 Bad Request.
- [ ] `rememberMe` 미전송 (기존 호출자) → 200 OK, 세션 쿠키 경로로 처리 (회귀 없음).

**회귀**
- [ ] 기존 e2e: signup → login (rememberMe 미전송) → `GET /members/me` 200 OK 통과.
- [ ] `AuthService.spec.ts` 기존 테스트 전부 통과 + rememberMe 3 케이스 신규 추가 통과.

### Files touched (예상)

**Backend (`apps/api`)**
- `src/auth/dto/login.dto.ts` — `rememberMe?: boolean` + `@IsBoolean() @IsOptional()`
- `src/auth/auth.service.ts` — `login` 에 rememberMe 분기, `LoginResult.maxAgeSeconds` 를 쿠키 Max-Age 전달 매개로 재해석 (0 = session cookie)
- `src/auth/auth.controller.ts` — `cookieOptions` 가 `maxAgeMs === 0` 이면 `maxAge` 를 넘기지 않도록 (express `res.cookie` 는 maxAge 생략 시 session cookie)
- `src/auth/auth.service.spec.ts` — rememberMe=true/false/undefined unit test 추가

**Frontend (`apps/web`)**
- `app/login/page.tsx` — `rememberMe` state + checkbox 필드 + `api.login` 호출에 전달
- `lib/types.ts` — `LoginInput.rememberMe?: boolean`
- `lib/api.ts` — 변경 없음 (body 를 그대로 spread 중)

**관련 PRD**
- §3.2 F-M2 (로그인), §3.3 JWT 정책 — "Access Token 1시간" 은 rememberMe=false 기본값으로 유지되나 rememberMe=true 분기만 7일로 연장. PRD 본문 수정 없음 (범위 내 조건부 확장). 필요 시 architect 단계에서 PRD 보조 각주 검토.

---

## Design

### 데이터 모델
- 스키마/엔티티 변경 **없음**. `members` 테이블·마이그레이션 영향 없음.
- 쿠키/토큰 수명만 조정 — 서버 상태는 stateless JWT 그대로.

### API 계약

| Method | Path | Auth | 요청 DTO | 응답 바디 | 응답 쿠키 | 상태 코드 |
|---|---|---|---|---|---|---|
| POST | `/auth/login` | 없음 | `LoginDto { userId: string; password: string; rememberMe?: boolean }` | `PublicMember { id, userId, nickname }` | `access_token` (HttpOnly), `csrf_token` (readable), 둘 다 동일 Max-Age 또는 둘 다 session cookie | 200 OK / 400 (DTO) / 401 (자격 불일치) |

- 요청 DTO 검증:
  - `userId: string` (기존)
  - `password: string` (기존)
  - `rememberMe?: boolean` — `@IsBoolean() @IsOptional()`. `transform: true` 상태의 `ValidationPipe` 에서 비-boolean(문자열 "true", 숫자, 등) 은 400 Bad Request.
- 응답 바디·에러 응답 포맷은 PRD §5.3 (성공=리소스/`ok`, 실패=`{ statusCode, message }`) 와 일치 — 기존과 동일, 변경 없음.
- `rememberMe` 값 → 서버 결정 테이블:

  | `dto.rememberMe` | JWT `expiresIn` | 쿠키 Max-Age |
  |---|---|---|
  | `true` | `604800` (7일, 상수) | `Max-Age=604800` |
  | `false` 또는 미전송(`undefined`) | `JWT_EXPIRES_IN` env (기본 `3600`) | 미설정 → session cookie |

- 상수: `REMEMBER_ME_EXPIRES_SECONDS = 604800` — `apps/api/src/auth/auth.service.ts` 상단에 선언. 환경변수화하지 않음 (Plan 범위 외).

### 흐름

로그인 (rememberMe=true)
1. 클라이언트 `/login` 폼 submit → `POST /auth/login` body `{ userId, password, rememberMe: true }`.
2. `AuthController.login` → `AuthService.login(dto)`.
3. `AuthService.login`:
   - 자격 검증 (기존 로직 그대로 — 타이밍 공격 완화 포함).
   - `expiresIn = REMEMBER_ME_EXPIRES_SECONDS` (= 604800).
   - `jwtService.signAsync(payload, { expiresIn })`.
   - `csrfToken = randomBytes(32).hex`.
   - 반환 `LoginResult { member, accessToken, csrfToken, maxAgeSeconds: 604800 }`.
4. 컨트롤러에서 `res.cookie('access_token', ..., cookieOptions(result.maxAgeSeconds))` + `res.cookie('csrf_token', ..., { ..., httpOnly: false })`. 두 쿠키 모두 `Max-Age=604800`.
5. 응답 200 OK + `PublicMember`.

로그인 (rememberMe=false 또는 미전송)
1~2. 동일.
3. `AuthService.login`:
   - `expiresIn = Number(process.env.JWT_EXPIRES_IN ?? 3600)` — 기존 그대로.
   - 반환 `maxAgeSeconds: null` (세션 쿠키 신호).
4. 컨트롤러는 `maxAgeSeconds === null` 이면 `maxAge` **키를 포함하지 않는** 쿠키 옵션으로 설정 → Express 가 `Max-Age`/`Expires` 둘 다 생략 → 브라우저 세션 쿠키.
5. 응답 200 OK.

로그아웃 (회귀 없음)
1. `POST /auth/logout` → 기존 그대로. `cookieOptions(0)` 는 "즉시 만료" 의미로 **의미 보존** — 아래 설계 결정 참조.

### 설계 결정: 세션 쿠키 신호 (Plan 수정)

Plan 초안은 `maxAgeSeconds === 0 → session cookie` 라고 적었으나, 이는 기존 **logout** 이 사용하는 `cookieOptions(0)` ("Max-Age=0 으로 즉시 만료") 과 충돌한다. 두 의미(세션 쿠키 vs 즉시 만료)를 하나의 센티넬로 공유하면 logout 쿠키가 session cookie 로 재해석돼 **클라이언트가 로그아웃되지 않을 수 있다**.

→ 신호를 **`maxAgeSeconds: number | null`** 로 변경:
- `number > 0` : 해당 초 만큼 Max-Age (로그인 성공 시 7일, 또는 레거시 1시간 등).
- `number === 0` : `Max-Age=0` 유지 — logout 전용 즉시 만료.
- `null` : session cookie — Express 가 `maxAge` 를 생략.

`cookieOptions(maxAge: number | null)` 로 시그니처 변경, `maxAge === null` 이면 반환 객체에 `maxAge` 키 자체를 포함하지 않도록 수정. `LoginResult.maxAgeSeconds` 타입을 `number | null` 로 변경.

### 보안 / 에러

- **입력 검증 지점**: `LoginDto` — `rememberMe` 는 `@IsBoolean() @IsOptional()`. ValidationPipe `transform: true, whitelist: true` (현 설정 유지) 에서 unknown 필드 제거, 타입 불일치는 400. `main.ts`/`app.module.ts` ValidationPipe 설정은 변경 없음을 전제로 함 — architect 가 설정이 이와 다르면 backend 역할에서 플래그.
- **권한 체크**: 로그인 엔드포인트는 비인증. 변경 없음. 체크박스 값이 민감 자원 접근을 바꾸지 않으므로 추가 Guard 불필요.
- **쿠키 속성 유지 (CRITICAL)**:
  - `access_token`: `HttpOnly`, `SameSite=Lax`, `Path=/`, `Secure`(prod).
  - `csrf_token`: `HttpOnly=false` (JS 가 읽어 X-CSRF-Token 헤더로 송신), `SameSite=Lax`, `Path=/`.
  - rememberMe 분기로 **어느 속성도 바꾸지 않는다**. Max-Age 만 조정.
- **세션 수명 ↔ 토큰 수명 정합성**: Plan 의 Q1 답 (b) 에 따라 쿠키 Max-Age 와 JWT `exp` 가 **동일** 하므로 "쿠키는 살아있는데 토큰은 만료" 간극이 사라진다. Refresh token 미구현이지만 UX 리스크 없음.
- **공용 기기 리스크**: rememberMe=false 가 **기본값**(unchecked) 이어야 공용 PC 에서 실수로 7일 유지가 발생하지 않는다 (수용 기준에 체크 완료).
- **에러 응답 (불변)**:
  - 400 Bad Request: `{ statusCode: 400, message: ["rememberMe must be a boolean value"], error: "Bad Request" }` (NestJS 기본).
  - 401 Unauthorized: `{ statusCode: 401, message: "아이디 또는 비밀번호가 일치하지 않습니다." }`.
- **로그 노출 금지**: `rememberMe` 값은 로그에 남기지 않음 (현재 request body 로깅 없음 — 변경 없음).

### 마이그레이션
- 해당 없음 — DB 스키마 변경 없음.

### 테스트 포인트 (QA 참고)

Unit (backend)
- `AuthService.spec.ts` — `login`:
  - `rememberMe: true` → `LoginResult.maxAgeSeconds === 604800`, JWT 디코드 결과 `exp - iat === 604800`.
  - `rememberMe: false` → `maxAgeSeconds === null`, `exp - iat === 3600` (또는 `JWT_EXPIRES_IN` 값).
  - `rememberMe: undefined` → `rememberMe: false` 와 동일 결과.
  - 자격 불일치 경로가 rememberMe 와 **무관** 하게 401 (기존 2 케이스 회귀).

E2E/API 레벨 (수용 기준 ↔ 수동 확인)
- `curl -i -X POST /auth/login -d '{"userId":"...","password":"...","rememberMe":true}'`
  - 응답 헤더 `Set-Cookie` 2개(access_token, csrf_token) 각각 `Max-Age=604800` 포함.
  - access_token 에 `HttpOnly`, 두 쿠키 모두 `SameSite=Lax; Path=/`.
- 동일 요청 `rememberMe:false` → `Max-Age`/`Expires` 토큰 **없음**.
- 동일 요청 `rememberMe` **omit** → session cookie 동작 (회귀).
- `rememberMe: "yes"` 와 같은 non-boolean → 400.
- 로그인 후 `GET /members/me` 200 OK (기존 e2e).
- Logout 회귀: 로그인(rememberMe=true) 후 `/auth/logout` → `Set-Cookie: access_token=; Max-Age=0; ...` 로 즉시 만료 (설계 결정 §세션 쿠키 신호 검증).

Frontend
- `/login` 체크박스 초기 unchecked, `?signup=1`/`?joined=1`/에러 상태 조합과 무관하게 렌더링.
- 폼 submit payload 에 `rememberMe` boolean 필드 포함 — DevTools Network.
- 체크 후 로그인 → DevTools Application → Cookies 에 `access_token` Expires=`7일 뒤`, 미체크 → Expires=`Session`.
- 재접속(브라우저 재시작) 시: rememberMe=true 세션은 유지, false 세션은 로그아웃됨 (수동 스모크, 자동화 범위 외).

---

## Design (UX)
<designer 작성 — required면>

### Figma
- URL: <figma-url>

### 화면 목록
- `<Route>` — states: default | loading | error | empty

### 컴포넌트 트리
```
<PageName>
  └─ <HeaderBar>
  └─ <FormCard>
```

### Frontend 참고
- 디자인 토큰 import 경로
- 상태 분기 TODO 위치

---

## Implementation (Backend)

### 설계 메모
- 엔드포인트: `POST /auth/login` — DTO 에 `rememberMe?: boolean` 추가. 응답 바디/다른 엔드포인트 계약 변경 없음.
- 엔티티 변경: 없음. DB 스키마 변경 없음.
- 마이그레이션: 없음.
- 쿠키 세션 신호: `LoginResult.maxAgeSeconds: number | null` — `null` 이면 Express `res.cookie` 에 `maxAge` 키 자체를 넘기지 않음 → `Set-Cookie` 에 `Max-Age`/`Expires` 생략 (session cookie). `0` 은 로그아웃 전용 (즉시 만료).

### 변경 파일
- `apps/api/src/auth/dto/login.dto.ts` — `rememberMe?: boolean` + `@IsOptional() @IsBoolean()` 추가.
- `apps/api/src/auth/auth.service.ts`
  - `REMEMBER_ME_EXPIRES_SECONDS = 604800` 상수 추가.
  - `LoginResult.maxAgeSeconds` 타입을 `number | null` 로 확장.
  - `login()`: `dto.rememberMe === true` 분기로 JWT `expiresIn` 와 `maxAgeSeconds` 를 7일/`null` 로 결정. 그 외는 기존 동작 유지 (`JWT_EXPIRES_IN` env 기본 3600, `maxAgeSeconds=null` 세션 쿠키).
- `apps/api/src/auth/auth.controller.ts`
  - `cookieOptions(maxAgeMs: number | null)` 로 시그니처 확장. `null` 이면 `maxAge` 키 자체를 포함하지 않도록 변경. `0` 유지(logout 즉시 만료).
  - `login()` 핸들러에서 `result.maxAgeSeconds === null ? null : * 1000` 로 변환해 두 쿠키에 동일하게 적용.
  - `logout()` 변경 없음 (`cookieOptions(0)` 즉시 만료 유지).
- `apps/api/src/auth/auth.service.spec.ts`
  - 기존 happy path 를 `rememberMe` 미전송 → `maxAgeSeconds=null` 로 업데이트.
  - rememberMe=true / rememberMe=false / rememberMe=undefined 3 케이스 추가 — `maxAgeSeconds` 와 `jwt.signAsync` 의 `expiresIn` 검증.

### 새 환경변수
- 없음.

### 마이그레이션
- 없음.

### 로컬 재현
```bash
pnpm install
pnpm --filter api build            # 타입체크 (nest build)
pnpm --filter api test             # 전체 유닛 테스트 (26 passed)
pnpm --filter api test --testPathPattern=auth   # auth 모듈만 (20 passed)
```

Docker + curl 수동 검증 (QA 참고):
```bash
docker compose up -d db
pnpm --filter api migration:run
pnpm --filter api start:dev &

# rememberMe=true → Max-Age=604800 쿠키 2개
curl -i -X POST http://localhost:4070/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"userId":"alice01","password":"password12","rememberMe":true}'

# rememberMe=false → session cookie (Max-Age 없음)
curl -i -X POST http://localhost:4070/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"userId":"alice01","password":"password12","rememberMe":false}'

# rememberMe 생략 → 세션 쿠키 (회귀)
curl -i -X POST http://localhost:4070/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"userId":"alice01","password":"password12"}'

# 비-boolean → 400
curl -i -X POST http://localhost:4070/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"userId":"alice01","password":"password12","rememberMe":"yes"}'
```

### API 계약 (실제 응답)
- 요청: `POST /auth/login` body `{ userId: string, password: string, rememberMe?: boolean }`
- 성공 200: body `{ id, userId, nickname }` + 쿠키 2개
  - `rememberMe:true` → `Set-Cookie: access_token=<jwt>; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800` + `csrf_token=<hex>; Path=/; SameSite=Lax; Max-Age=604800`
  - `rememberMe:false` 또는 미전송 → 동일 쿠키이되 `Max-Age`/`Expires` 미설정 (session cookie)
  - 운영 (`COOKIE_SECURE=true`) 에선 `Secure` 추가
- 400 (DTO): `rememberMe` 가 boolean 이 아니면 `{ statusCode: 400, message: ["rememberMe must be a boolean value"], error: "Bad Request" }`
- 401: `{ statusCode: 401, message: "아이디 또는 비밀번호가 일치하지 않습니다." }`
- JWT payload: `rememberMe:true` → `exp - iat === 604800`, 그 외 → `JWT_EXPIRES_IN` env (기본 3600)

### 범위 참고 (frontend 미포함)
- `required_roles` 에 frontend 가 포함되어 있지 않아 본 세션에서는 `apps/web` 을 수정하지 않았다 (role 경계: backend 는 `apps/web/**` 수정 금지). UI 수용 기준(체크박스 렌더링·폼 payload) 은 별도 frontend task 또는 후속 QA 결정이 필요하다.

### 수용 기준 자가 검증
- [x] API 쿠키: `rememberMe:true` → 두 쿠키 모두 `Max-Age=604800`, access_token `HttpOnly`, 둘 다 `SameSite=Lax; Path=/` (unit test + `cookieOptions` 로직 확인).
- [x] API 쿠키: `rememberMe:false|undefined` → `Max-Age`/`Expires` 없음 (session cookie); `cookieOptions(null)` 이 `maxAge` 키 생략.
- [x] JWT 만료: rememberMe=true → `expiresIn: 604800`, 미전송/false → `3600` (`JWT_EXPIRES_IN` env 기본).
- [x] DTO 검증: `rememberMe` non-boolean → 400 (ValidationPipe `transform/whitelist/forbidNonWhitelisted` + `@IsBoolean()`).
- [x] `rememberMe` 미전송 회귀: 200 OK + 세션 쿠키 경로 (유닛 테스트 "rememberMe=undefined").
- [x] 로그아웃 회귀: `cookieOptions(0)` 유지 — Max-Age=0 즉시 만료 (설계 결정 반영, logout 핸들러 변경 없음).
- [x] 유닛 테스트: `AuthService.spec.ts` 전부 통과 (login 5 케이스 포함, 전체 26 테스트 passed).
- [x] 빌드/타입체크: `pnpm --filter api build` 성공.
- [ ] UI (`/login` 체크박스 렌더링·폼 payload) — frontend 역할 미포함으로 본 세션 범위 외.
- [ ] 로그인 후 `GET /members/me` 200 OK e2e — e2e 하네스 미구성 (QA 수동 확인 필요).

---

## Implementation (Frontend)
<frontend 작성>

### 추가 라우트/페이지
- `/path` — 설명

### 새 환경변수
- `NEXT_PUBLIC_...`

### 로컬 재현 (브라우저 시나리오)
1. ...

### 수용 기준 자가 검증
- [x] ...

---

## QA report
<qa 작성>

### 결과
- 결정: pass | fail
- 일자: 2026-10-22
- 환경: WEB=:<port>/API=:<port>/DB=:<port>

### 수용 기준 검증
- [x] <기준> — pass
- [ ] <기준> — fail → 아래 참조

### 발견 사항
- 없음 또는
- **[FAIL]** <요약>
  - 재현:
    1. ...
  - 기대: ...
  - 실제: ...

---

## Review notes
<reviewer 작성>

### 결과
- 결정: pass | rework
- 일자: 2026-10-22
- 병합 SHA: <sha> (pass 시)

### Blocker
- 없음 또는
- `file.ts:42` — <문제>, <수정 가이드>

### Suggest
- `file.ts:88` — <개선 아이디어>

### 체크리스트 요약
- PRD 정합성: ✅
- 보안: ✅
- 리소스/누수: ✅
- 성능/데이터: ✅
- 코드 품질: ✅
- 테스트: ✅
- 범위: ✅
