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
current_role: planner
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
<architect 작성>

### 데이터 모델
<엔티티/스키마 변경 — DDL 수준>

### API 계약
| Method | Path | Auth | 요청 DTO | 응답 | 상태 코드 |

### 흐름
- 1. ...
- 2. ...

### 보안 / 에러
- 입력 검증 지점:
- 권한 체크:
- 에러 응답:

### 마이그레이션 (DB 변경 있을 때)
- 이름: `<timestamp>-<name>`
- Up: ...
- Down: ...

### 테스트 포인트
- QA가 확인할 지점 ...

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
<backend 작성>

### 변경 파일
- `apps/api/.../...` — 설명

### 새 환경변수
- `VAR_NAME` — 용도

### 마이그레이션
- 파일명: ...

### 로컬 재현
```bash
# 명령
```

### 수용 기준 자가 검증
- [x] ...

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
