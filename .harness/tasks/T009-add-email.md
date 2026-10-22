---
id: T009
title: add-email
slug: add-email
branch: task/T009-add-email
worktree: .worktrees/T009-add-email
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
  web: 3090
  api: 4090
  db: 3315
compose_project: harness_t009
figma_url: null
blocked_by: []
related_prd: []
priority: normal          # high | normal | low
created_at: 2026-10-22
updated_at: 2026-10-22
---

## User Request

> 회원가입에 이메일 필드 추가

---

_(T009 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_


# T009 — add-email

## Plan

### Why
PRD의 회원 데이터 모델은 식별자로 `user_id`/`nickname`만 보유하여 추후 공지·계정복구 등 이메일 기반 커뮤니케이션이 불가하다. 본 작업은 이메일을 **수집·수정**할 수 있는 기반만 추가한다. 메일 발송·인증·중복 체크는 범위 밖(사용자 확정).

> PRD 변경 사유: PRD §3.1 members 테이블에 `email` 컬럼 추가. 선택 입력, UNIQUE 없음, 254자 이하.

### What
- `members.email` 컬럼 신규 추가 (nullable, UNIQUE 아님)
- 회원가입 API/화면에서 이메일을 **선택 입력**으로 받음
- 내 정보 조회(GET /me) 응답에 `email` 포함
- 내 정보 수정(PATCH /me) 으로 이메일 수정/삭제 가능
- 이메일 **포맷 검증**만 서버에서 수행 (class-validator `@IsEmail`), 메일 발송·확인 링크 없음

### Scope
- 포함:
  - `member.entity.ts`, 신규 TypeORM 마이그레이션 (up/down)
  - `signup.dto.ts` (optional email 필드)
  - `auth.service.ts` signup 분기 (email 저장)
  - `update-me.dto.ts`, `members.service.ts`, `members.controller.ts` (GET/PATCH /me email)
  - `apps/web/app/signup/page.tsx` 폼 필드 1개 추가
  - `apps/web/app/me/page.tsx` 폼 필드 1개 추가 (수정 가능)
  - `apps/web/lib/api.ts` 요청/응답 타입에 email 반영
- 제외:
  - 메일 발송 / 인증 링크 / 이메일로 로그인 / 비밀번호 찾기
  - email 중복(UNIQUE) 체크
  - 자동 로그인/세션 변경
  - 로그인 폼 변경 (여전히 user_id 기반)

### Acceptance
- [ ] DB `members` 테이블에 `email VARCHAR(254) NULL` 컬럼이 존재한다 (UNIQUE 인덱스 없음, 왕복 마이그레이션 성공)
- [ ] `POST /auth/signup` 에서 `email` 생략 시 **201/200** 로 가입 성공, 저장된 레코드의 `email`은 `NULL`
- [ ] `POST /auth/signup` 에서 유효한 email 포함 시 가입 성공, DB에 그 값이 저장됨
- [ ] `POST /auth/signup` 에서 포맷 오류(e.g. `"not-an-email"`) 또는 254자 초과 → **400** 응답
- [ ] email이 서로 다른 두 회원이 **같은 email**로 가입 가능 (중복 허용 확인)
- [ ] `GET /me` 응답 바디에 `email` 필드가 포함되며, 저장값이 없으면 `null`
- [ ] `PATCH /me` 로 email 신규 설정 / 변경 / `""`(또는 `null`) 전송으로 **삭제** 가능
- [ ] 회원가입 화면 `/signup` 에 `이메일 (선택)` input 노출, 비워도 제출 가능하며 성공 시 `/login?signup=1` 로 이동
- [ ] 내 정보 화면 `/me` 에 email 필드가 저장값으로 프리필, 수정·저장 가능
- [ ] 기존 가입/로그인/글쓰기 플로우 회귀 없음 (QA가 UAT 로 확인)

### Files touched (예상)
- `apps/api/src/members/member.entity.ts`
- `apps/api/src/migrations/<timestamp>-add-member-email.ts` (신규)
- `apps/api/src/auth/dto/signup.dto.ts`
- `apps/api/src/auth/auth.service.ts`
- `apps/api/src/auth/auth.service.spec.ts`
- `apps/api/src/members/dto/update-me.dto.ts`
- `apps/api/src/members/members.service.ts`
- `apps/api/src/members/members.controller.ts`
- `apps/api/src/members/members.service.spec.ts`
- `apps/web/app/signup/page.tsx`
- `apps/web/app/me/page.tsx`
- `apps/web/lib/api.ts`

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
