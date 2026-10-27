---
id: T021
title: 회원 로그아웃 버튼
slug: me-logout
branch: task/T021-me-logout
worktree: .worktrees/T021-me-logout
status: in-flight          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: kiro }
  - { role: architect,  agent: kiro }
  - { role: backend,    agent: kiro }
  - { role: frontend,   agent: kiro }
  - { role: qa,         agent: kiro }
  - { role: reviewer,   agent: kiro }
current_role: frontend
role_history:
  - { role: architect, agent: kiro, at: 2026-10-27, note: "Design 섹션 작성, Q1/Q2 확정" }
ports:
  web: 3210
  api: 4210
  db: 3327
compose_project: harness_t021
figma_url: null
blocked_by: []
related_prd: ["§3.2 F-M3 로그아웃", "§5.1 POST /auth/logout", "§3.3 JWT 정책", "§3.4 CSRF 대응"]
priority: normal          # high | normal | low
created_at: 2026-10-27
updated_at: 2026-10-27
---

## User Request

# 회원 로그아웃 버튼

로그인한 회원이 자신의 세션을 종료할 수 있는 로그아웃 버튼이 필요하다.

---

_(T021 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_


# T021 — 회원 로그아웃 버튼

## Plan

### Why
현재 시스템은 회원가입·로그인은 구현되어 있으나(F-M1/F-M2) 로그인한 회원이 능동적으로 세션을 끝낼 수단이 없다. 공용·공유 기기에서 자리를 뜰 때 다음 사용자가 그대로 로그인 상태를 물려받는 보안 위험이 있고, PRD §9 수용 기준의 "비회원이 가입 → 로그인 → 글 작성 → **로그아웃**까지 완주 가능" 플로우가 아직 미완결이다. 로그아웃 버튼은 이 플로우를 닫는 최소 기능이다.

### What
PRD §3.2 F-M3 와 §5.1 에 정의된 로그아웃을 UI + API 양쪽으로 완성한다.

1. **Backend** — `POST /auth/logout` 엔드포인트 구현:
   - 인증된 요청(JWT 쿠키 보유)에 대해 `access_token` 쿠키를 즉시 만료(`Set-Cookie: access_token=; Max-Age=0; Path=/; HttpOnly; SameSite=Lax` + 운영 시 `Secure`).
   - 로그인 시 함께 발급되는 `csrf_token` 쿠키도 동일하게 만료시켜 잔여 쿠키를 남기지 않는다.
   - 성공 시 2xx + 간단한 JSON 바디(`{ ok: true }` 수준) 반환. JWT 는 stateless 이므로 서버측 토큰 폐기/블랙리스트는 하지 않는다(범위 밖, 쿠키 제거만으로 브라우저 세션 종료).
2. **Frontend** — 로그인 상태에서 보이는 "로그아웃" 버튼:
   - 로그인한 회원에게만 노출(로그인 여부 판단은 기존 패턴 재사용).
   - 클릭 시 `POST /auth/logout` 호출(same-origin rewrites 경유, `credentials: 'include'`). 상태 변경 요청이므로 CSRF 토큰 정책(§3.4 Double Submit Cookie: `X-CSRF-Token` 헤더) 준수.
   - 성공 응답 후 클라이언트 로그인 상태를 비우고 로그인 또는 홈 화면으로 이동.

### Scope
- **포함**:
  - `apps/api` — `POST /auth/logout` 컨트롤러/서비스, `access_token`·`csrf_token` 쿠키 만료 로직, `AuthGuard('jwt')` 보호.
  - `apps/api` — unit test: 로그아웃 응답이 두 쿠키를 `Max-Age=0`(만료)로 설정하는지 검증.
  - `apps/web` — 로그아웃 버튼 컴포넌트/배치(로그인 시 노출), 클릭 핸들러(API 호출 + CSRF 헤더 + 상태 초기화 + 리다이렉트).
- **제외**:
  - 서버측 토큰 블랙리스트 / Refresh Token 폐기 (PRD §8, §3.3 — 범위 밖).
  - "모든 기기에서 로그아웃" 같은 멀티세션 종료.
  - 자동 유휴(idle) 타임아웃 로그아웃.
  - 로그아웃 확인 모달 등 UX 고도화 (단순 버튼 1개로 한정).
  - 로그아웃 버튼의 시각 디자인 고도화 — 기존 헤더/네비 스타일 재사용으로 충분(별도 designer 역할 불필요).

### Acceptance
- [ ] 로그인 상태에서 "로그아웃" 버튼이 화면에 노출된다. 비로그인 상태에서는 노출되지 않는다.
- [ ] 버튼 클릭 시 `POST /auth/logout` 이 호출되고 2xx 응답을 받는다.
- [ ] 응답의 `Set-Cookie` 로 `access_token` 쿠키가 만료된다(`Max-Age=0`). DevTools Application 탭에서 로그아웃 후 `access_token` 쿠키가 사라진 것을 확인.
- [ ] 로그아웃 시 `csrf_token` 쿠키도 함께 만료되어 남지 않는다.
- [ ] 로그아웃 후 보호 API(`GET /members/me`) 호출 시 401 이 반환된다(쿠키 제거로 더 이상 인증되지 않음).
- [ ] 로그아웃 후 클라이언트는 로그인(또는 홈) 화면으로 이동하고, 로그아웃 버튼 대신 로그인 진입점이 보인다.
- [ ] 쿠키 없이(비로그인) `POST /auth/logout` 호출 시 401 이 반환된다(JWT 보호 라우트).
- [ ] CSRF 토큰 누락 상태에서 로그아웃 요청 시 서버 정책(§3.4)에 따라 처리된다(토큰 요구 시 403, 또는 로그아웃은 멱등하므로 CSRF 예외로 둘지 architect 가 §3.4 범위에서 결정).
- [ ] 기존 로그인/회원정보 플로우에 회귀가 없다(관련 unit test 통과).

### Files touched (예상)
- `apps/api/src/auth/auth.controller.ts` — `POST /auth/logout` 핸들러 추가
- `apps/api/src/auth/auth.service.ts` — 쿠키 만료(clear) 헬퍼 (login 의 쿠키 설정 로직과 대칭)
- `apps/api/src/auth/*.spec.ts` — 로그아웃 쿠키 만료 unit test
- `apps/web/app/...` — 헤더/네비게이션 등 로그인 상태 영역에 로그아웃 버튼 추가
- `apps/web/...` — 로그아웃 호출 클라이언트 유틸(API 호출 + CSRF 헤더) 및 상태/리다이렉트 처리

### 다음 역할로의 핸드오프 (제약 / 참고)
- **architect**: §3.4 CSRF 정책과 로그아웃의 상호작용(CSRF 토큰 요구 여부)을 명시 결정하고 API 계약에 반영할 것. 쿠키 만료 속성은 login 시 설정한 속성과 **정확히 대칭**(동일 Path/SameSite/HttpOnly, Max-Age=0)이어야 브라우저가 쿠키를 지운다 — 불일치 시 쿠키가 남는 흔한 버그에 주의.
- **backend**: JWT stateless 특성상 "로그아웃 후에도 이미 발급된 토큰은 만료까지 유효"하다는 점은 PRD §3.2 F-M3 참고 범위 내이며, 추가 폐기 로직을 구현하지 말 것(YAGNI, 범위 밖).
- **frontend**: 로그인 여부 판단 및 상태 초기화는 기존 로그인/멤버 상태 관리 패턴을 재사용. 신규 전역 상태 라이브러리 도입 금지(YAGNI).
- **related_prd**: §3.2 F-M3(로그아웃), §5.1(`POST /auth/logout` JWT), §3.3(JWT 정책), §3.4(CSRF).

### Open questions (architect 가 설계 시 확정)
- Q1: 로그아웃은 멱등(idempotent)한 세션 종료이므로 CSRF 토큰을 **요구**할지, 예외로 둘지? (§3.4 는 상태변경 요청 전반에 CSRF 적용을 명시 → 기본은 요구 쪽이 일관적)
- Q2: 로그아웃 성공 후 리다이렉트 목적지는 `/login` 과 홈(`/`) 중 어디로? (기본값 제안: `/login`)

---

## Design

> architect (kiro) — 2026-10-27. planner 의 Plan + Open questions(Q1/Q2) 를 확정하고 API 계약·쿠키 만료 규약·CSRF 정책을 고정한다. 코드는 쓰지 않으며, 아래는 backend/frontend/qa 가 따를 계약이다.

### 결정 사항 (Open questions 확정)

- **Q1 — 로그아웃에 CSRF 토큰 요구할지?** → **요구한다 (CSRF 적용).**
  - 근거: PRD §3.4 는 "상태 변경(POST/PUT/PATCH/DELETE) 요청"에 CSRF 토큰 적용을 명시. 로그아웃은 POST 로 쿠키를 만료시키는 상태 변경 요청이다.
  - 근거: 기존 `PATCH /members/me` 가 `@UseGuards(JwtAuthGuard, CsrfGuard)` 로 동일 패턴을 이미 확립 — 일관성 유지(신규 예외 규칙 도입은 YAGNI 위반).
  - 근거: PRD §9 수용 기준 "상태 변경 요청에 CSRF 토큰 누락 시 403 반환" 과 정합.
  - PRD §5.1 표가 로그아웃을 `JWT` 로만 표기한 점은 상위 원칙(§3.4)과 충돌하는 표기 누락으로 해석. §3.4 의 일반 규칙을 우선 적용한다 (PRD 설계 원칙 위배 아님 — §3.4 범위 내 해석).
  - **⚠ backend 핸드오프**: 현재 `auth.controller.ts` 의 `logout` 스텁은 `@UseGuards(JwtAuthGuard)` 만 적용되어 있다. **`CsrfGuard` 를 추가**하여 `@UseGuards(JwtAuthGuard, CsrfGuard)` 로 만들 것 (members.controller 의 `updateMe` 와 동일 패턴).

- **Q2 — 로그아웃 후 리다이렉트 목적지?** → **`/login`.**
  - 근거: planner 기본 제안이며, 로그아웃 직후 재로그인 진입점을 즉시 제공하는 것이 자연스럽다. frontend 재량으로 홈(`/`) 도 허용하나 기본값은 `/login`.

### 데이터 모델
- **스키마 변경 없음.** 로그아웃은 stateless JWT 쿠키 만료만 수행. DB 엔티티/컬럼/인덱스 변경 없음 → 마이그레이션 불필요.

### API 계약

| Method | Path | Auth | 요청 DTO | 요청 헤더 | 성공 응답 | 상태 코드 |
|--------|------|------|----------|-----------|-----------|-----------|
| POST | `/auth/logout` | JWT + CSRF | (없음, 바디 무시) | `X-CSRF-Token: <csrf_token 쿠키 값>` + `access_token`·`csrf_token` 쿠키 자동 전송 | 바디 `{ "ok": true }` + 아래 2개 `Set-Cookie` (만료) | 200 |

**응답 Set-Cookie 규약 (login 속성과 정확히 대칭 — 불일치 시 브라우저가 쿠키를 지우지 않는 흔한 버그):**

- `Set-Cookie: access_token=; Max-Age=0; Path=/; HttpOnly; SameSite=Lax` (+ `COOKIE_SECURE=true` 환경에서 `Secure`)
- `Set-Cookie: csrf_token=; Max-Age=0; Path=/; SameSite=Lax` (HttpOnly 아님, login 과 동일; + `COOKIE_SECURE=true` 시 `Secure`)
- 구현 메모: 기존 `cookieOptions(0)` 헬퍼가 login 과 동일한 `path='/'`, `sameSite='lax'`, `secure=COOKIE_SECURE` 를 보장. `access_token` 은 `httpOnly:true`, `csrf_token` 은 `httpOnly:false` 로 login 설정과 대칭 유지. (현재 스텁이 이미 이 형태 — 유지)

### 흐름 (시퀀스)

Backend (`POST /auth/logout`):
1. `JwtAuthGuard` → `access_token` 쿠키의 JWT 검증. 없거나 만료/위조 시 **401** (`인증이 필요합니다.`).
2. `CsrfGuard` → `csrf_token` 쿠키 값 ↔ `X-CSRF-Token` 헤더 값 `timingSafeEqual` 비교. 불일치/누락 시 **403** (`유효하지 않은 요청입니다.`).
3. 두 가드 통과 시 `access_token`·`csrf_token` 쿠키를 `Max-Age=0` 으로 재설정(만료) → 바디 `{ ok: true }`, **200**.

Frontend (로그아웃 버튼):
1. 로그인 상태에서만 "로그아웃" 버튼 노출 (로그인 판단은 기존 멤버 상태/`GET /members/me` 패턴 재사용).
2. 클릭 → `POST /auth/logout` 호출. `credentials: 'include'`, 헤더 `X-CSRF-Token` 에 `csrf_token` 쿠키 값 복사(기존 PATCH /members/me 호출 유틸의 CSRF 헤더 세팅 패턴 재사용).
3. 2xx 응답 → 클라이언트 로그인 상태 초기화 → `/login` 으로 이동(교체 네비게이션 권장, 뒤로가기로 보호 페이지 복귀 방지).
4. 비정상 응답(401/403/네트워크 오류) → 사용자에게 간단한 실패 피드백. 단, 쿠키가 이미 서버에서 만료됐을 수 있으므로 UX 재량. (고도화는 범위 밖)

### 보안 / 에러

- **입력 검증 지점**: 요청 바디 없음 → DTO/ValidationPipe 불필요. 신뢰 입력은 쿠키(JWT, csrf)와 CSRF 헤더뿐이며 기존 가드가 검증.
- **권한 체크**: `JwtAuthGuard`(인증) + `CsrfGuard`(CSRF) — 로그인 회원 본인 세션만 종료. 타 세션/멀티기기 종료 없음(범위 밖).
- **민감 정보 흐름**: 토큰/비밀번호 평문을 응답·로그에 노출 금지. 응답 바디는 `{ ok: true }` 로 최소화. `Set-Cookie` 의 쿠키 값은 빈 문자열이므로 토큰 노출 없음.
- **에러 응답** (PRD §5.3 형식 `{ statusCode, message, error }`):
  - 쿠키 없음/JWT 만료·위조 → **401**
  - CSRF 토큰 누락/불일치 → **403**
- **stateless 특성 명시**: 로그아웃 후에도 이미 발급된 JWT 는 만료 시각까지 기술적으로 유효(PRD §3.2 F-M3, §3.3). 서버측 블랙리스트/Refresh 폐기 **구현 금지**(범위 밖, YAGNI). 브라우저 쿠키 제거로 실질 세션 종료.

### 마이그레이션 (DB 변경 있을 때)
- **해당 없음** — DB 스키마 변경 없음.

### 테스트 포인트 (QA / backend unit test 참조)

Backend unit test (필수):
- `POST /auth/logout` 성공 응답이 `access_token` 쿠키를 `Max-Age=0`(만료)로 Set-Cookie 하는지.
- 동일 응답이 `csrf_token` 쿠키도 `Max-Age=0` 로 만료시키는지.
- 두 쿠키의 만료 속성(Path=`/`, SameSite=`lax`, Secure=env)이 login 설정과 대칭인지.
- (가능 시) 유효 JWT + 올바른 CSRF 헤더 조합에서만 200, CSRF 누락 시 403, 무인증 시 401.

QA UAT (수용 기준 대응):
- 로그인 상태에서 로그아웃 버튼 노출 / 비로그인 시 미노출.
- 버튼 클릭 → `POST /auth/logout` 200 수신.
- DevTools Application 탭에서 로그아웃 후 `access_token`·`csrf_token` 쿠키 소멸 확인.
- 로그아웃 후 `GET /members/me` 호출 시 **401**.
- 비로그인(쿠키 없음) 상태에서 `POST /auth/logout` 호출 시 **401**.
- 유효 JWT + CSRF 헤더 누락 상태로 `POST /auth/logout` 호출 시 **403**.
- 로그아웃 후 `/login` 이동 + 로그인 진입점 노출.
- 기존 login/members unit test 회귀 없음.

### 핸드오프 요약
- **backend**: 위 API 계약 구현. 스텁 `logout` 에 `CsrfGuard` 추가(`@UseGuards(JwtAuthGuard, CsrfGuard)`). 쿠키 만료는 기존 `cookieOptions(0)` 재사용(login 대칭). 쿠키 만료 검증 unit test 추가. 서버측 토큰 폐기 구현 금지.
- **frontend**: 로그인 상태 버튼 노출 + `POST /auth/logout`(`credentials: 'include'` + `X-CSRF-Token` 헤더) + 상태 초기화 + `/login` 리다이렉트. 신규 전역 상태 라이브러리 도입 금지(기존 패턴 재사용).
- **qa**: 위 QA UAT 지점 전수 확인.

---

## Implementation (Backend)

> backend (kiro) — 2026-10-27. architect 의 API 계약대로 `POST /auth/logout` 에 CSRF 가드를 추가하고 쿠키 만료 동작을 unit test 로 고정. 기존 스텁이 이미 `cookieOptions(0)` 로 두 쿠키를 `Max-Age=0` 만료시키고 있어 로직 변경은 가드 1건 + 테스트 신규가 핵심.

### 설계 메모
- 엔드포인트: `POST /auth/logout` — `@UseGuards(JwtAuthGuard, CsrfGuard)`, `@HttpCode(200)`.
- 엔티티/스키마 변경: **없음** (stateless JWT 쿠키 만료만). → 마이그레이션 불필요.
- 쿠키 만료: `access_token`(HttpOnly) · `csrf_token`(non-HttpOnly) 모두 빈 값 + `cookieOptions(0)`(Path=`/`, SameSite=`lax`, Secure=env). login 설정과 정확히 대칭.

### 변경 파일
- `apps/api/src/auth/auth.controller.ts` — `logout` 핸들러 가드에 `CsrfGuard` 추가(`@UseGuards(JwtAuthGuard, CsrfGuard)`), `CsrfGuard` import 추가. (쿠키 만료 로직은 기존 스텁 유지)
- `apps/api/src/auth/auth.controller.spec.ts` — **신규**. logout 쿠키 만료 동작 unit test (6건).

### 새 환경변수
- 없음 (기존 `COOKIE_SECURE` 재사용).

### 마이그레이션
- 해당 없음 (DB 스키마 변경 없음).

### 로컬 재현
```bash
pnpm install
pnpm --filter api typecheck     # tsc --noEmit → 통과
pnpm --filter api test          # jest → 4 suites / 37 tests 통과
```
> 주: `pnpm --filter api lint` 는 이 저장소에서 eslint 가 api 패키지 의존성/설정에 없어 실행 불가 (기존 환경 갭, 이번 변경과 무관). 정적 검증은 `tsc` 로 대체.

### API 계약 (frontend 핸드오프 — 실제 응답 형태)
- 요청: `POST /auth/logout`, 헤더 `X-CSRF-Token: <csrf_token 쿠키 값>`, `credentials: 'include'` (쿠키 자동 전송). 바디 없음.
- 성공: `200` + 바디 `{ "ok": true }` + 2개 `Set-Cookie`:
  - `access_token=; Max-Age=0; Path=/; HttpOnly; SameSite=Lax` (+ `COOKIE_SECURE=true` 시 `Secure`)
  - `csrf_token=; Max-Age=0; Path=/; SameSite=Lax` (HttpOnly 아님; + `COOKIE_SECURE=true` 시 `Secure`)
- 에러: 쿠키 없음/JWT 무효 → `401` (`인증이 필요합니다.`), CSRF 누락/불일치 → `403` (`유효하지 않은 요청입니다.`).

### 수용 기준 자가 검증 (backend 범위)
- [x] `POST /auth/logout` 은 `access_token` 쿠키를 `Max-Age=0`(HttpOnly, Path=/, SameSite=lax)로 만료 — unit test 통과.
- [x] `POST /auth/logout` 은 `csrf_token` 쿠키도 `Max-Age=0`(non-HttpOnly, Path=/, SameSite=lax)로 만료 — unit test 통과.
- [x] `COOKIE_SECURE=true` 시 두 쿠키 모두 `Secure` (login 대칭) — unit test 통과.
- [x] 성공 바디 `{ ok: true }`, `200` — unit test 통과.
- [x] 무인증(JWT 쿠키 없음) 호출 → `401`: `JwtAuthGuard` 가 보장 (guard 적용으로 커버, UAT 는 qa).
- [x] CSRF 토큰 누락/불일치 → `403`: `CsrfGuard` 추가로 보장 (기존 `csrf.guard.spec.ts` 가 가드 동작 검증, UAT 는 qa).
- [x] 서버측 토큰 블랙리스트/Refresh 폐기 미구현 (YAGNI, 범위 밖) — 준수.
- [x] 기존 login/members 테스트 회귀 없음 — 전체 37 tests 통과.
- 비고(qa 범위): 브라우저 DevTools 쿠키 소멸, 로그아웃 후 `GET /members/me` 401, `/login` 리다이렉트는 frontend 구현 후 qa UAT 로 확인.

---

## Implementation (Frontend)

> frontend (kiro) — 2026-10-27. architect 의 API 계약(CSRF 요구 + `/login` 리다이렉트)과 backend 의 실제 응답 형태(`{ ok: true }` + 2개 만료 Set-Cookie)를 교차 검증. 로그아웃 UI/호출 로직은 기존 T002/T003 스캐폴드에 이미 구현되어 있었고, 본 계약과 **정확히 일치**함을 확인 — 신규/수정 코드 없이 계약 적합성 검증 + 자가 UAT 로 마무리 (YAGNI, 범위 밖 재작업 금지).

### API 계약 교차 검증 (backend 실제 응답 ↔ architect 설계)
- `lib/api.ts` `api.logout()` → `POST /auth/logout`. 공통 `request()` 헬퍼가 상태 변경 메소드(POST 포함)에 `X-CSRF-Token` 헤더(쿠키 `csrf_token` 값 복사) 자동 세팅 + `credentials: 'include'`. → architect 계약(JWT+CSRF) 및 backend 구현(`@UseGuards(JwtAuthGuard, CsrfGuard)`)과 일치. **불일치 없음.**
- 성공 응답 `{ ok: true }` 는 `request<{ ok: boolean }>` 로 수신. 쿠키 만료는 서버 `Set-Cookie` 가 브라우저에서 처리(프런트 관여 불필요).

### 추가 라우트/페이지
- 신규 없음. 기존 자산 재사용:
  - `app/components/Nav.tsx` — 로그인 상태(`authed`)에서만 "로그아웃" 버튼 노출, 비로그인(`anon`)에서는 로그인/회원가입 진입점 노출. `onLogout` → `api.logout()` → 클라이언트 상태 `anon` 전환 → `router.push('/login')` + `router.refresh()`.
  - `app/logout/page.tsx` — `/logout` 직접 진입 시에도 로그아웃 → `/login` 교체 이동(`router.replace`) 처리.
  - `lib/api.ts` — `logout()` 클라이언트 + CSRF 헤더/쿠키 전달 공통 로직.

### 새 환경변수
- 없음. (기존 `API_PROXY_TARGET` same-origin rewrites 재사용 — `/api/*` → NestJS)

### 보안 자가 점검
- HttpOnly: `access_token` 은 JS 접근 불가(`readCsrfToken` 은 `csrf_token` 만 읽음). `document.cookie` 에 `access_token` 비노출.
- CSRF: POST 로그아웃에 `X-CSRF-Token` 헤더 포함(Double Submit Cookie).
- XSS: 사용자 입력 React 기본 escape, `dangerouslySetInnerHTML` 미사용.
- 인증 UI 분기는 UX 편의일 뿐 보안 경계 아님(서버 Guard + middleware 가 실제 접근 제어). Nav 주석에 명시.
- 토큰 `localStorage` 미저장, 신규 전역 상태 라이브러리 미도입.

### 정적 검증
```bash
pnpm --filter web typecheck   # tsc --noEmit → 통과
pnpm --filter web lint        # next lint → No ESLint warnings or errors
```

### 로컬 재현 (브라우저 시나리오 — qa 핸드오프)
1. `docker compose up` (현재 worktree 포트: WEB=:3210 / API=:4210 / DB=:3327).
2. 브라우저 `http://localhost:3210/login` → 기존 계정으로 로그인 → `/me` 이동, 상단 Nav 에 "로그아웃" 버튼 노출 확인.
3. "로그아웃" 클릭 → `POST /api/auth/logout` 200(`{ ok: true }`) → `/login` 으로 이동, Nav 가 로그인/회원가입 진입점으로 전환됨.
4. DevTools → Application → Cookies: 로그아웃 후 `access_token`·`csrf_token` 쿠키 소멸 확인.
5. DevTools Console 에서 `document.cookie` 에 `access_token` 이 없음을 확인(HttpOnly 검증).
6. 로그아웃 후 `GET /api/members/me` 호출(또는 `/me` 재접근) → 401 → `/login` 리다이렉트 확인.
7. 비로그인 상태로 `/logout` 직접 진입 → `POST /auth/logout` 401 이어도 클라이언트는 `/login` 으로 이동(멱등 UX).

### 수용 기준 자가 검증 (frontend 범위)
- [x] 로그인 상태에서 "로그아웃" 버튼 노출 / 비로그인 시 미노출 — `Nav.tsx` `authed`/`anon` 분기.
- [x] 버튼 클릭 시 `POST /auth/logout` 호출 (same-origin `/api` rewrites + `credentials: 'include'`).
- [x] 상태 변경 요청에 `X-CSRF-Token` 헤더 포함 — `request()` CSRF_METHODS(POST) 처리.
- [x] 로그아웃 후 클라이언트 상태 초기화 + `/login` 이동, 로그인 진입점 노출.
- [x] HttpOnly `access_token` JS 접근 불가 (프런트는 `csrf_token` 만 읽음).
- [x] `dangerouslySetInnerHTML` 미사용 / `localStorage` 토큰 미저장 / 신규 전역 상태 라이브러리 미도입.
- [x] 범위 밖 파일(`apps/api/**`, PRD) 변경 없음.
- [x] 린트/타입체크 통과 (회귀 없음).
- 비고(qa 범위): 쿠키 소멸·로그아웃 후 `GET /members/me` 401·`/login` 리다이렉트 등 런타임 UAT 는 위 §로컬 재현 시나리오로 qa 가 docker up 환경에서 확인.

---

## QA report
<qa 작성>

### 결과
- 결정: pass | fail
- 일자: YYYY-MM-DD
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
- 일자: YYYY-MM-DD
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
