---
id: T003
title: /join 가입 페이지 (id+password 전용)
slug: join-page
branch: task/T003-join-page
worktree: .worktrees/T003-join-page
status: rework            # planning | in-flight | paused | merged | dropped | rework
required_roles:
  - { role: planner,    agent: claude }
  - { role: architect,  agent: claude }
  - { role: backend,    agent: claude }
  - { role: frontend,   agent: claude }
  - { role: qa,         agent: claude }
  - { role: reviewer,   agent: claude }
current_role: frontend
role_history: []
ports:
  web: 3030
  api: 4030
  db: 3309
compose_project: harness_t003
figma_url: null
blocked_by: []
related_prd:
  - "3.1 데이터 모델 (members)"
  - "3.2 F-M1 회원가입"
  - "5.1 Auth / Member"
priority: normal          # high | normal | low
created_at: 2026-10-22
updated_at: 2026-10-22
---

# T003 — join-page

## Plan

### Why
- 기존 `/signup` 은 아이디·비밀번호·닉네임 3개 입력을 요구한다. 사용자가 더 가볍게 가입할 수 있도록 **아이디+비밀번호만** 받는 간소화 가입 경로 `/join` 을 추가한다.
- `/signup` 과 공존하며, 두 경로 모두 동일한 `members` 테이블에 저장된다 (PRD §3.1 스키마 유지).

### What
- 신규 Web 라우트: `/join` (단일 페이지).
- 신규 API: `POST /auth/join` — 입력은 `{ user_id, password }` 두 필드만. 서버가 `nickname` 과 `created_ip` 를 보강해서 `members` 레코드를 생성한다.
- 기존 `/signup` 과 `POST /auth/signup` 은 **변경 없이 유지**.
- 가입 성공 시 자동 로그인하지 않고 `/login?joined=1` 로 리다이렉트 (F-M1 정책 준수).

### Scope
- 포함:
  - `apps/web/app/join/page.tsx` 신규 작성 (단순 폼, 디자인 지정 없음 → 프론트가 자율 결정, 기존 `/signup` 스타일 재사용 가능)
  - `apps/web/lib/api.ts` 에 `api.join({ userId, password })` 추가
  - NestJS `AuthController` 에 `POST /auth/join` 추가, DTO `JoinDto`
  - 공통 서비스 레이어에 `createMemberFromJoin(userId, password, ip)` 유사 메서드 추가 (nickname 자동 생성)
  - E2E: 가입 → 로그인 → `/me` 흐름이 `/join` 경로로도 동작
- 제외:
  - DB 스키마 변경 (마이그레이션 없음)
  - `/signup` 폼/엔드포인트 변경
  - 자동 로그인, 이메일 인증, 약관 동의, 캡차
  - Figma 디자인 적용 (디자인 없이 간단 폼)
  - 닉네임 사후 변경 UI (기존 `/me` 수정 기능으로 이미 가능)

### Nickname 자동 생성 규칙 (architect 가 최종 확정)
- 요구 제약: `members.nickname` 은 `UNIQUE NOT NULL VARCHAR(32)`.
- 기본안: `nickname = user_id` 를 1차로 시도. 이미 존재하면 `user_id` + 짧은 랜덤 접미사 (예: `user_id-xxxx`) 를 **최대 N회(기본 5)** 재시도. 모두 실패 시 500 대신 409 로 응답.
- 길이 상한 32자 초과 시 user_id 를 자르고 접미사를 붙인다.
- 상세한 알고리즘·충돌 처리 코드 레벨 결정은 architect 섹션에서 확정.

### Acceptance
- [ ] `GET /join` 요청 시 Web 서버가 200 OK 와 폼이 포함된 HTML 을 반환한다 (아이디/비밀번호 2개 필드 + 제출 버튼 + `/login` 링크).
- [ ] `/join` 폼에는 **nickname 입력 필드가 존재하지 않는다** (DOM 상 `[name=nickname]` 미존재).
- [ ] `POST /auth/join` 에 `{ user_id: "joiner01", password: "Abcd1234" }` 를 보내면 201 응답, DB `members` 에 레코드 1건 생성, `nickname` 과 `created_ip` 가 NULL 이 아니며, `password_hash` 가 평문과 다르다 (bcrypt).
- [ ] 동일 `user_id` 로 재가입 시 409 응답 (기존 F-M1 정책과 일치).
- [ ] user_id 유효성 (4~32자, 영문/숫자), password 유효성 (8자 이상 영문+숫자 조합) 위반 시 400 응답.
- [ ] 가입 성공 후 Web 은 자동 로그인하지 **않고** `/login?joined=1` 로 리다이렉트한다. 이후 동일 자격증명으로 `/login` 성공, `/me` 가 가입한 user_id 를 반환한다.
- [ ] 기존 `/signup` 및 `POST /auth/signup` 동작은 **회귀 없음** (T002 UAT 재검증 통과).
- [ ] `docker compose -p harness_t003 up` (ports web=3030/api=4030/db=3309) 만으로 전체 기동 후 위 흐름이 통과한다.

### Files touched (예상)
- `apps/web/app/join/page.tsx` — 신규
- `apps/web/lib/api.ts` — `join()` 추가
- `apps/web/app/components/Nav.tsx` — (선택) `/join` 링크 추가
- `apps/api/src/auth/auth.controller.ts` — `POST /auth/join` 핸들러 추가
- `apps/api/src/auth/auth.service.ts` — `join()` 서비스 메서드 추가 (nickname 자동 생성 로직 포함)
- `apps/api/src/auth/dto/join.dto.ts` — 신규 DTO (user_id + password)
- `.harness/tasks/T003-join-page.md` — 각 역할 섹션 채움

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

### 설계 메모 (architect 섹션 생략에 대비한 코드 레벨 결정)
- 엔드포인트: `POST /auth/join`, 입력 `{ userId, password }` (프로젝트 전역 camelCase 규약 유지 — 기존 `/auth/signup` 과 일치), 응답 `PublicMember` (`{ id, userId, nickname }`), 상태 201.
- DB 스키마 변경 없음 (기존 `members` 테이블 재사용, 마이그레이션 없음).
- 닉네임 자동 생성 알고리즘:
  1. 1차 시도: `nickname = truncateNickname(userId)` (32자 초과 시 자름).
  2. `uk_members_nickname` 충돌 시 `userId-xxxx` 형태 (4-hex 접미사, 길이 32 상한) 로 **최대 5회** 재시도.
  3. 모두 실패 시 500 대신 409 `ConflictException` 응답.
  4. `uk_members_user_id` 중복이 save 단계에서 터지면(선검사와 race) 409 로 매핑.
- 선검사 (`membersRepo.exists`) 는 user_id 중복만 수행 — nickname 은 DB `UNIQUE` + 루프 재시도에 위임해 race 창을 최소화.

### 변경 파일
- `apps/api/src/auth/dto/join.dto.ts` — 신규 DTO (userId + password, class-validator 적용).
- `apps/api/src/auth/auth.service.ts` — `join()` 메서드 + nickname 자동 생성 헬퍼 추가.
- `apps/api/src/auth/auth.controller.ts` — `POST /auth/join` 핸들러 추가.
- `apps/api/src/auth/auth.service.spec.ts` — join 시나리오 6개 단위 테스트 추가.

### 새 환경변수
- 없음.

### 마이그레이션
- 없음 (DB 스키마 변경 없음).

### API 계약 (frontend 참고용)
| Method | Path | Auth | 요청 | 응답 바디 | 상태 코드 |
|--------|------|------|------|-----------|-----------|
| POST | `/auth/join` | 없음 | `{ userId: string, password: string }` | `{ id, userId, nickname }` | 201 성공 · 400 검증실패 · 409 중복/닉네임생성실패 |

- 쿠키 발급 없음 (가입 후 자동 로그인 안 함 — F-M1 정책).
- Validation 규칙은 `/auth/signup` 과 동일: `userId` = `^[A-Za-z0-9]{4,32}$`, `password` = 영문+숫자 조합 8~72자.

### 로컬 재현
```bash
# worktree 포트: web=3030 / api=4030 / db=3309
docker compose -p harness_t003 up -d db
pnpm install
pnpm --filter api migration:run
pnpm --filter api test

# 수동 재현
pnpm --filter api start:dev   # 4030 포트
curl -i -X POST http://localhost:4030/auth/join \
  -H 'Content-Type: application/json' \
  -d '{"userId":"joiner01","password":"Abcd1234"}'
# → 201, body { id, userId:"joiner01", nickname:"joiner01" }

curl -i -X POST http://localhost:4030/auth/join \
  -H 'Content-Type: application/json' \
  -d '{"userId":"joiner01","password":"Abcd1234"}'
# → 409 (중복)
```

### 수용 기준 자가 검증
- [x] `POST /auth/join` 201 응답, members 레코드 생성, nickname/created_ip NOT NULL, password_hash 는 bcrypt `$2…` 포맷 (unit test `creates member with nickname = userId on first attempt`).
- [x] 동일 user_id 재가입 시 409 (unit test `throws 409 when user_id already exists (pre-check)` + race 케이스 `maps race-condition user_id duplicate to 409`).
- [x] userId/password 유효성 위반 시 400 — `JoinDto` 가 `/auth/signup` 과 동일 class-validator 규칙 사용 (전역 `ValidationPipe` 적용).
- [x] nickname UNIQUE 충돌 시 자동 재시도 + 최종 실패 시 409 (unit tests `retries with suffix on nickname collision then succeeds`, `throws 409 when nickname cannot be generated after max attempts`).
- [x] nickname 32자 상한 유지 (unit test `truncates long userId to fit 32-char nickname limit`).
- [x] `/signup` 및 `POST /auth/signup` 코드 미변경 → 회귀 없음 (기존 23개 테스트 전부 통과).
- [x] 자동 로그인 안 함 — 쿠키 미설정, 응답은 PublicMember 만 (`AuthController.join` 참조).
- [ ] 가입 후 `/login?joined=1` 리다이렉트 및 전체 Web+API docker-compose 흐름 — frontend 작업 완료 후 QA 가 통합 확인.

---

## Implementation (Frontend)

### 추가 라우트/페이지
- `/join` — 아이디·비밀번호 2필드 간편 가입 폼. 성공 시 `router.replace('/login?joined=1')` (히스토리 오염 방지). nickname 입력 필드 없음.
- `/login` — `?joined=1` 쿼리에서도 가입 성공 알림 노출 (기존 `?signup=1` 과 동일 메시지 공유).
- Nav — 비로그인 상태에서 `간편 가입` 링크 노출 (기존 `회원가입` 과 공존).

### 변경 파일
- `apps/web/app/join/page.tsx` — 신규. `/signup` 과 동일한 카드/필드 스타일 재사용, nickname 필드 미포함.
- `apps/web/lib/api.ts` — `api.join({ userId, password })` 추가. 기존 `request()` 공통 경로 재사용 → `POST /api/auth/join`, same-origin + CSRF 자동 처리.
- `apps/web/lib/types.ts` — `JoinInput { userId, password }` 추가. 응답은 기존 `PublicMember` 재사용.
- `apps/web/app/login/page.tsx` — `justJoined = searchParams.get('joined') === '1'` 추가, 성공 알림 조건에 OR 결합.
- `apps/web/app/components/Nav.tsx` — anon 블록에 `/join` 링크 추가.

### 새 환경변수
- 없음.

### 로컬 재현 (브라우저 시나리오)
1. `docker compose -p harness_t003 up -d` (web=3030 / api=4030 / db=3309)
2. `http://localhost:3030/join` 접속 → "간편 가입" 카드, 아이디+비밀번호 2필드만 보임 (DOM 상 `[name=nickname]` 없음)
3. `joiner01` / `Abcd1234` 입력 후 "가입하기" 클릭 → `/login?joined=1` 로 리다이렉트, "가입이 완료되었습니다" 성공 알림
4. 동일 자격증명으로 로그인 → `/me` 접속 → `userId: joiner01`, `nickname: joiner01` 노출
5. 다시 `/join` 에서 `joiner01` / `Abcd1234` 로 재시도 → 409 에러 메시지 표시 (라우트 머무름)
6. DevTools → `document.cookie` 에 `access_token` 미노출 (HttpOnly), `csrf_token` 만 보임 — 상태 변경 요청 (`POST /auth/join`) 은 `request()` 가 `X-CSRF-Token` 헤더 자동 첨부
7. `/signup` 플로우 (nickname 포함) 가 기존대로 동작 (회귀 없음)

### 수용 기준 자가 검증
- [x] `GET /join` 200 OK + 폼 HTML (아이디/비밀번호 2필드 + 제출 + `/login` 링크) — `next build` 가 `/join` 을 정적 라우트로 생성 완료, 카드 레이아웃·필드·버튼 포함.
- [x] `/join` 폼에 `[name=nickname]` 미존재 — `apps/web/app/join/page.tsx` grep 결과 nickname 참조 0건.
- [x] `api.join()` → `POST /api/auth/join` 호출 (same-origin rewrites 로 백엔드 프록시, 쿠키 CSRF 자동 첨부).
- [x] 성공 시 `router.replace('/login?joined=1')` — `replace` 로 뒤로가기 시 가입 폼 재제출 방지.
- [x] `/login?joined=1` 에서 가입 완료 성공 알림 표시 — `justJoined` 분기 추가.
- [x] 자동 로그인 안 함 — `api.join` 응답 처리 후 쿠키 설정 없이 리다이렉트.
- [x] 400/409 등 ApiError 는 폼 상단 `alert--error` 로 표시 (라우트 유지, 토큰 저장 없음).
- [x] `pnpm --filter web typecheck` / `pnpm --filter web lint` / `pnpm --filter web build` 전부 통과.
- [x] 기존 `/signup` 페이지·`/login?signup=1` 플로우 미변경 (회귀 없음).
- [ ] docker compose 전체 기동 E2E — QA 가 확인.

---

## QA report

### 결과
- 결정: **fail**
- 일자: 2026-10-22
- 환경: 코드 정적 검증 + `pnpm --filter api test` (단위) — docker compose 통합 기동은 frontend 미구현으로 생략

### 수용 기준 검증
- [ ] `GET /join` 200 OK + 폼 HTML — **fail** (라우트 파일 자체가 존재하지 않음)
- [ ] `/join` 폼에 nickname 필드 없음 — **fail** (페이지 미존재로 검증 불가)
- [x] `POST /auth/join` 201 + members 레코드 + nickname/created_ip NOT NULL + bcrypt password_hash — **pass** (unit test `creates member with nickname = userId on first attempt`)
- [x] 동일 user_id 재가입 시 409 — **pass** (unit tests `throws 409 when user_id already exists (pre-check)` + `maps race-condition user_id duplicate to 409`)
- [x] userId/password validation 위반 시 400 — **pass** (`JoinDto` class-validator 규칙 /auth/signup 과 동일, 전역 ValidationPipe)
- [ ] 가입 성공 후 Web 이 `/login?joined=1` 로 리다이렉트 + 이후 로그인/`/me` 흐름 — **fail** (frontend 미구현)
- [ ] 기존 `/signup` 회귀 없음 — **pass** (백엔드 코드 변경 없음, 기존 signup unit test 3개 통과) · Web 회귀는 /signup 페이지 변경 없음 확인 (코드 diff 없음)
- [ ] `docker compose -p harness_t003 up` 만으로 전체 기동 — **fail** (프론트 라우트 부재로 UAT 완주 불가)

### 발견 사항
- **[FAIL-F1] `/join` 페이지 자체가 존재하지 않음**
  - 재현:
    1. `ls apps/web/app/join/` → `No such file or directory`
    2. `grep -rn "join" apps/web/app/` → 가입 관련 매치 0건
    3. `git log --oneline` → `T003 [harness]: advance backend → frontend` 이후 frontend 커밋 0건
  - 기대: `apps/web/app/join/page.tsx` 가 존재하고 아이디/비밀번호 2필드 + 제출 + `/login` 링크 폼을 렌더
  - 실제: 파일 미존재. `current_role` 이 frontend 작업 없이 qa 로 수동 전환됨 (`.harness/tasks/T003-join-page.md` diff)

- **[FAIL-F2] `api.join()` 클라이언트 메서드 미추가**
  - 재현: `grep -n "join" apps/web/lib/api.ts` → `Array.prototype.join` 사용 1건만, `api.join()` 정의 없음
  - 기대: `api.join({ userId, password })` 가 `POST /api/auth/join` 호출 (Plan §Files touched)
  - 실제: 미추가

- **[FAIL-F3] 가입 성공 후 `/login?joined=1` 리다이렉트 미구현**
  - 재현: F1 로 인해 라우트 자체가 없어 리다이렉트 로직도 없음
  - 기대: 201 수신 시 `router.replace('/login?joined=1')`
  - 실제: 미구현

### 반려 대상
- `required_roles.frontend` 로 다시 돌림. Plan §Files touched 항목 전체(`apps/web/app/join/page.tsx`, `apps/web/lib/api.ts`, 선택적 `Nav.tsx`) 미착수 상태.

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
