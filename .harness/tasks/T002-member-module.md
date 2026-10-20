---
id: T002
title: 회원 모듈 — 가입/로그인/정보수정 + JWT·CSRF
slug: member-module
branch: task/T002-member-module
worktree: .worktrees/T002-member-module
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: claude }
  - { role: architect,  agent: claude }
  # - { role: designer,   agent: claude, mcp: [figma] }
  - { role: backend,    agent: claude }
  - { role: frontend,   agent: claude }
  - { role: qa,         agent: claude }
  - { role: reviewer,   agent: claude }
current_role: architect
role_history: []
ports:
  web: 3020
  api: 4020
  db: 3308
compose_project: harness_t002
figma_url: null
blocked_by: []
related_prd: ["§1.2", "§3", "§5.1", "§6", "§7.4", "§9"]
priority: normal          # high | normal | low
created_at: 2026-10-20
updated_at: 2026-10-20
---

# T002 — member-module

## Plan

### Why
- PRD §4.2 권한 매트릭스상 게시판의 모든 쓰기 기능(글 작성/수정/삭제)은 로그인 회원만 가능하므로, **회원 모듈은 게시판 모듈(후속 task)의 선행 기반**이다. 인증/인가 토대 없이는 후속 작업이 성립하지 않는다.
- 사용자 가치: 방문자가 가입 → 로그인 → (이후) 글 작성 → 로그아웃까지 완주할 수 있는 인증 흐름을 제공한다 (PRD §9 수용기준 1번).

### What
PRD §3(회원), §5.1(Auth/Member), §6(공통 비기능), §7.4(TypeORM 세부)에 정의된 회원 모듈을 백엔드 + 프런트엔드로 구현한다.

- **데이터 모델**: `members` 테이블(PRD §3.1) — TypeORM `MemberEntity` + 명시적 **마이그레이션** 파일 (`synchronize: false`, PRD §7.4).
- **인증 기반**: JWT HS256 1h, HttpOnly 쿠키(`access_token`), bcrypt(saltRounds ≥ 10) 해시, `cookie-parser` + 쿠키 기반 `JwtStrategy` + `AuthGuard('jwt')` (PRD §3.3, §3.5).
- **CSRF 방어**: Double Submit Cookie — 로그인 시 `csrf_token` 쿠키(HttpOnly 아님) 발급, 상태 변경 요청은 `X-CSRF-Token` 헤더와 일치해야 통과 (PRD §3.4). 쿠키 `SameSite=Lax` 1차 방어 포함.
- **API 5종** (PRD §5.1):
  - `POST /auth/signup` — 회원가입 (F-M1)
  - `POST /auth/login` — 로그인, `Set-Cookie: access_token` + `csrf_token` (F-M2)
  - `POST /auth/logout` — 쿠키 만료 (F-M3)
  - `GET /members/me` — 내 정보 조회
  - `PATCH /members/me` — 닉네임/비밀번호 수정 (F-M4)
- **프런트엔드**: 회원가입 / 로그인 / 로그아웃 / 내 정보 수정 4개 화면 + 보호 라우트 가드. Next.js **rewrites** same-origin 프록시 경유로 쿠키 전달 (PRD §1.2 기본안).
- **공통**: `ValidationPipe` + `class-validator` DTO 검증, CORS `credentials: true` + 명시 origin, 민감정보 미노출 에러 메시지 (PRD §6).

### Scope
- **포함**:
  - `members` 엔티티 + 마이그레이션 (스키마, 인덱스 `UNIQUE(user_id)`, `UNIQUE(nickname)`, `utf8mb4_unicode_ci`)
  - 회원가입 / 로그인 / 로그아웃 / 내 정보 조회·수정 API 5종 (PRD §5.1)
  - JWT 발급·검증, bcrypt 해시, HttpOnly 쿠키, CSRF Double Submit Cookie
  - DTO 입력 검증(`class-validator` + `ValidationPipe`, PRD §3.2 검증 규칙)
  - 회원 관련 프런트 화면 4종 + 보호 라우트 가드 + Next.js rewrites 설정
  - 가입 IP 기록(`created_ip`) — `X-Forwarded-For` 처리 정책은 architect가 PRD §10-1 기준으로 확정
  - 회원 UAT에 필요한 최소 Docker 기동 (`web` / `api` / `db`)
- **제외**:
  - 게시판 모듈 전체 (posts, PRD §4) — 별도 후속 task
  - 이메일 인증, 비밀번호 찾기, 소셜 로그인 (PRD §8)
  - 로그인 실패 횟수 제한, 2FA, Refresh Token, 토큰 블랙리스트 (PRD §8)
  - 닉네임 변경 주기 제한 (PRD §10-2 — 미결정)
  - SSR 인증 / 프로덕션 배포 파이프라인 / 외부 비밀관리 (PRD §8)

### Acceptance
- [ ] `members` 테이블이 PRD §3.1 스키마대로 생성됨 (`user_id`/`nickname` UNIQUE, `password_hash` NOT NULL, `created_ip` NOT NULL, `utf8mb4_unicode_ci`) — 마이그레이션 실행으로 확인
- [ ] `POST /auth/signup`: 유효한 입력 시 **201**, DB에 회원 1행 생성, `password_hash`가 bcrypt 해시(평문 아님)로 저장됨
- [ ] 회원가입 검증 실패(user_id 길이·형식 위반, password 8자 미만/영문+숫자 미조합, nickname 길이 위반) 시 **400** 반환
- [ ] 중복 `user_id` 또는 `nickname` 가입 시 **409** 반환
- [ ] `POST /auth/login`: 성공 시 응답 바디는 `{ id, user_id, nickname }`만 포함(토큰 미노출), `Set-Cookie: access_token`이 **HttpOnly**로 설정됨 + `csrf_token` 쿠키 발급
- [ ] 로그인 실패(아이디 없음 / 비번 불일치) 시 **동일한 에러 메시지** + **401** (계정 존재 여부 비노출)
- [ ] `access_token` 쿠키를 브라우저 `document.cookie`로 접근 불가 (HttpOnly 확인)
- [ ] `GET /members/me`: 유효 JWT 쿠키로 **200** + 내 정보 반환, 토큰 없음/만료/위조 시 **401**
- [ ] `PATCH /members/me`: 닉네임 중복이면 **409**, password 변경 시 현재 비밀번호 재확인 실패하면 **400**, `user_id`/`created_at`/`created_ip`는 수정 불가, 성공 시 `updated_at` 갱신
- [ ] 상태 변경 요청(`PATCH /members/me`)에 **CSRF 토큰 누락/불일치** 시 **403**
- [ ] `POST /auth/logout`: `Set-Cookie: access_token=; Max-Age=0`로 쿠키 만료 처리
- [ ] 비밀번호가 서버 로그/응답 어디에도 평문으로 노출되지 않음
- [ ] 가입 시 요청 IP가 `created_ip` 컬럼에 기록됨 (프록시 환경 정책은 architect가 확정)
- [ ] 프런트: 가입 → 로그인 → 내 정보 수정 → 로그아웃 시나리오를 브라우저에서 완주 가능
- [ ] `docker compose up` 만으로 web/api/db 전체가 기동되고 위 UAT 통과

### Files touched (예상)
> 가이드용 — architect / backend / frontend 가 실제 구조에 맞게 조정 가능.

- Backend (`apps/api`):
  - `apps/api/src/members/member.entity.ts` — `MemberEntity`
  - `apps/api/src/auth/{auth.module.ts, auth.controller.ts, auth.service.ts}`
  - `apps/api/src/auth/dto/{signup.dto.ts, login.dto.ts}`
  - `apps/api/src/auth/{jwt.strategy.ts, jwt-auth.guard.ts}` (cookieExtractor 포함)
  - `apps/api/src/auth/csrf.{middleware,guard}.ts` — Double Submit Cookie 검증
  - `apps/api/src/members/{members.module.ts, members.controller.ts, members.service.ts}`
  - `apps/api/src/members/dto/update-me.dto.ts`
  - `apps/api/src/migrations/<timestamp>-create-members.ts`
  - `apps/api/src/main.ts` — `cookie-parser`, `ValidationPipe`, CORS(`credentials: true`) 설정
- Frontend (`apps/web`):
  - `apps/web/app/signup/page.tsx`, `apps/web/app/login/page.tsx`, `apps/web/app/me/page.tsx`
  - `apps/web/app/logout/route.ts` (또는 로그아웃 핸들러)
  - `apps/web/lib/api.ts` — fetch 래퍼(`credentials: 'include'`, `X-CSRF-Token` 자동 첨부)
  - `apps/web/middleware.ts` 또는 route guard — 보호 라우트 처리
  - `apps/web/next.config.{js,ts}` — `/api/*` → `http://api:4000` rewrites
- 인프라:
  - `docker-compose.yml`, `.env.example`, `apps/api/Dockerfile`, `apps/web/Dockerfile` (PRD §7)

### Open questions (architect로 전달)
- PRD §10-1: 프록시 뒤 `X-Forwarded-For` 신뢰 정책 — 로컬 Docker 환경 기본값과 운영 전환 조건을 architect가 결정.
- PRD §10-4: 브라우저 → API 경로. 본 task는 PRD 기본안인 **Next.js rewrites same-origin** 채택. 직접 호출로 전환할 경우 architect가 CORS/Cookie Domain 정책을 재검토.
- PRD §10-5: TypeORM 마이그레이션 실행 주체 (컨테이너 start-up hook vs `compose run --rm api pnpm migration:run`) — architect가 선택 후 backend가 반영.

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
