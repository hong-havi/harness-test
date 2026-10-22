---
id: T003
title: /join 가입 페이지 (id+password 전용)
slug: join-page
branch: task/T003-join-page
worktree: .worktrees/T003-join-page
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: claude }
  - { role: architect,  agent: claude }
  - { role: backend,    agent: claude }
  - { role: frontend,   agent: claude }
  - { role: qa,         agent: claude }
  - { role: reviewer,   agent: claude }
current_role: planner
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
