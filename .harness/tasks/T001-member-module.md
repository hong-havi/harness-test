---
id: T001
title: member-module
slug: member-module
branch: task/T001-member-module
worktree: .worktrees/T001-member-module
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: kiro }
  - { role: architect,  agent: kiro }
  # - { role: designer,   agent: claude, mcp: [figma] }
  - { role: backend,    agent: kiro }
  - { role: frontend,   agent: claude }
  - { role: qa,         agent: kiro }
  - { role: reviewer,   agent: kiro }
current_role: planner
role_history: []
ports:
  web: 3010
  api: 4010
  db: 3307
compose_project: harness_t001
figma_url: null
blocked_by: []
related_prd: ["§3", "§5.1", "§1.2", "§7.4", "§9"]
priority: normal          # high | normal | low
created_at: 2026-10-20
updated_at: 2026-10-20
---

# T001 — member-module

## Plan

### Why
- 게시판의 모든 쓰기 기능(글 작성/수정/삭제)은 로그인 회원만 가능하다(PRD §4.2 권한 매트릭스). 따라서 **회원 모듈은 게시판 모듈(T002 예정)의 선행 기반**이며, 인증/인가 토대가 없으면 후속 작업이 불가능하다.
- 사용자 가치: 방문자가 가입 → 로그인 → (이후) 글 작성 → 로그아웃까지 완주할 수 있는 인증 흐름을 제공한다(PRD §9 1번 수용 기준).

### What
PRD §3(회원) 및 §5.1(Auth/Member)에 정의된 회원 모듈 백엔드 + 프런트엔드를 구현한다.

- **데이터 모델**: `members` 테이블(PRD §3.1) — TypeORM `MemberEntity` + 명시적 마이그레이션(`synchronize: false`, PRD §7.4).
- **인증 기반**: JWT(HS256, 1h) HttpOnly 쿠키 전달, bcrypt(saltRounds ≥ 10) 해시, `cookie-parser` + 쿠키 기반 `JwtStrategy` + `AuthGuard('jwt')` (PRD §3.3, §3.5).
- **CSRF 방어**: Double Submit Cookie (`csrf_token` 쿠키 + `X-CSRF-Token` 헤더 일치 검증), `SameSite=Lax` (PRD §3.4).
- **API 5종** (PRD §5.1):
  - `POST /auth/signup` — 회원가입 (F-M1)
  - `POST /auth/login` — 로그인, `Set-Cookie: access_token`, `csrf_token` (F-M2)
  - `POST /auth/logout` — 쿠키 만료 (F-M3)
  - `GET /members/me` — 내 정보 조회
  - `PATCH /members/me` — 닉네임/비밀번호 수정 (F-M4)
- **프런트엔드**: 회원가입 / 로그인 / 로그아웃 / 내 정보 수정 화면 + API 연동 (Next.js rewrites same-origin 프록시, PRD §1.2).

### Scope
- **포함**:
  - `members` 엔티티 + 마이그레이션 (스키마, 인덱스 `UNIQUE(user_id)`, `UNIQUE(nickname)`, `utf8mb4_unicode_ci`)
  - 회원가입 / 로그인 / 로그아웃 / 내 정보 조회·수정 API (PRD §5.1 5종)
  - JWT 발급·검증, bcrypt 해시, HttpOnly 쿠키, CSRF Double Submit Cookie
  - DTO 입력 검증 (`class-validator` + `ValidationPipe`, PRD §3.2 검증 규칙)
  - 회원 관련 프런트 화면 4종 + 보호 라우트 가드
  - 가입 IP 기록 (`created_ip`) — `X-Forwarded-For` 처리 정책은 architect가 §10-1 기준으로 확정
- **제외**:
  - 게시판 모듈 전체 (posts, PRD §4) → 별도 task(T002 예정)
  - 이메일 인증, 비밀번호 찾기, 소셜 로그인 (PRD §8)
  - 로그인 실패 횟수 제한, 2FA, Refresh Token, 토큰 블랙리스트 (PRD §8)
  - 닉네임 변경 주기 제한 (PRD §10-2 — 미결정, 이번 범위 제외)
  - Docker Compose / 인프라 전체 구성은 공통 과제이나, 본 task는 회원 모듈 UAT에 필요한 최소 기동만 사용 (web/api/db)

### Acceptance
- [ ] `members` 테이블이 PRD §3.1 스키마대로 생성됨 (`user_id`/`nickname` UNIQUE, `password_hash` NOT NULL, `created_ip`, `utf8mb4_unicode_ci`) — 마이그레이션 실행으로 확인
- [ ] `POST /auth/signup`: 유효한 입력 시 201/200, DB에 회원 1행 생성, `password_hash`가 bcrypt 해시(평문 아님)로 저장됨
- [ ] 회원가입 검증 실패(user_id 길이·형식 위반, password 8자 미만/영문숫자 미조합, nickname 길이 위반) 시 **400** 반환
- [ ] 중복 `user_id` 또는 `nickname` 가입 시 **409** 반환
- [ ] `POST /auth/login`: 성공 시 응답 바디는 `{ id, user_id, nickname }`만 포함(토큰 미노출), `Set-Cookie: access_token`이 **HttpOnly**로 설정됨 + `csrf_token` 쿠키 발급
- [ ] 로그인 실패(아이디 없음 / 비번 불일치) 시 **동일한 에러 메시지** + 401 (계정 존재 여부 비노출)
- [ ] `access_token` 쿠키를 브라우저 `document.cookie`로 접근 불가 (HttpOnly 확인)
- [ ] `GET /members/me`: 유효 JWT 쿠키로 200 + 내 정보 반환, 토큰 없음/만료/위조 시 **401**
- [ ] `PATCH /members/me`: 닉네임 변경 시 중복이면 409, password 변경 시 현재 비밀번호 재확인 실패하면 400, `user_id`/`created_at`/`created_ip`는 수정 불가, 성공 시 `updated_at` 갱신
- [ ] 상태 변경 요청(`PATCH /members/me`)에 **CSRF 토큰 누락/불일치** 시 **403**
- [ ] `POST /auth/logout`: `Set-Cookie: access_token=; Max-Age=0`로 쿠키 만료 처리
- [ ] 비밀번호가 서버 로그/응답 어디에도 평문으로 노출되지 않음
- [ ] 프런트: 가입 → 로그인 → 내 정보 수정 → 로그아웃 시나리오를 브라우저에서 완주 가능

### Files touched (예상)
> 가이드용 — architect/backend/frontend가 실제 구조에 맞게 조정 가능.

- Backend (`apps/api`):
  - `apps/api/src/members/member.entity.ts` — `MemberEntity`
  - `apps/api/src/auth/auth.module.ts`, `auth.controller.ts`, `auth.service.ts`
  - `apps/api/src/auth/dto/signup.dto.ts`, `login.dto.ts`
  - `apps/api/src/auth/jwt.strategy.ts` (cookieExtractor), `jwt-auth.guard.ts`
  - `apps/api/src/auth/csrf.middleware.ts` (또는 guard) — Double Submit Cookie
  - `apps/api/src/members/members.module.ts`, `members.controller.ts`, `members.service.ts`
  - `apps/api/src/members/dto/update-me.dto.ts`
  - `apps/api/src/migrations/<timestamp>-create-members.ts`
  - `apps/api/src/main.ts` — `cookie-parser`, `ValidationPipe`, CORS(`credentials: true`) 설정
- Frontend (`apps/web`):
  - `apps/web/app/(auth)/signup/page.tsx`
  - `apps/web/app/(auth)/login/page.tsx`
  - `apps/web/app/account/page.tsx` — 내 정보 수정
  - `apps/web/lib/api.ts` — fetch 래퍼(`credentials: 'include'`, `X-CSRF-Token` 주입)
  - `apps/web/next.config.*` — `/api/*` rewrites

### related_prd
- §3 (회원 모듈 — 데이터 모델, F-M1~F-M4, JWT 정책, CSRF)
- §5.1 (Auth/Member API 엔드포인트)
- §1.2 (rewrites same-origin 프록시), §7.4 (TypeORM 마이그레이션), §9 (수용 기준)

### Open questions (architect 확정 필요)
- PRD §10-1: `created_ip` 추출 시 `X-Forwarded-For` 신뢰 여부 / Nest `trust proxy` 설정 → architect가 결정하여 Design에 명시.
- PRD §10-4: 브라우저→API 경로는 rewrites(기본) 채택 전제. 변경 시 CORS/Cookie Domain 재검토.

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
- 일자: 2026-10-20
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
- 일자: 2026-10-20
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
