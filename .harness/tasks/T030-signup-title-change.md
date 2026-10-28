---
id: T030
title: signup-title-change
slug: signup-title-change
branch: task/T030-signup-title-change
worktree: .worktrees/T030-signup-title-change
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: kiro }
  - { role: frontend,   agent: kiro }
  - { role: qa,         agent: kiro }
  - { role: reviewer,   agent: kiro }
current_role: planner
role_history: []
ports:
  web: 3300
  api: 4300
  db: 3336
compose_project: harness_t030
figma_url: null
blocked_by: []
related_prd: []
priority: normal          # high | normal | low
created_at: 2026-10-28
updated_at: 2026-10-28
---

## User Request

> 회원가입 페이지(/signup) 상단 제목 '회원가입' 을 '가입하기' 로 변경. 다른 변경 없음. frontend-only, 백엔드/DB 변경 없음.

---

_(T030 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_


# T030 — signup-title-change

## Plan

### Why
회원가입 페이지(`/signup`) 상단 제목 문구를 '회원가입' → '가입하기' 로 바꿔 사용자에게 더 행동 지향적인(call-to-action) 표현을 제공한다. 순수 카피(문구) 변경 요청.

### What
- `/signup` 페이지의 **상단 제목** `<h1>` 텍스트를 `회원가입` → `가입하기` 로 변경.
- 그 외 어떤 변경도 하지 않는다 (user: "다른 변경 없음").

### Scope
- 포함: `apps/web/app/signup/page.tsx` 의 `<h1>회원가입</h1>` → `<h1>가입하기</h1>` 한 줄.
- 제외:
  - 네비게이션/링크 라벨의 '회원가입' (Header.tsx, login/page.tsx, page.tsx) — 이들은 `/signup` 로 이동하는 **링크 텍스트**이지 페이지 상단 제목이 아니므로 변경 금지.
  - 백엔드(`apps/api`) / DB / 마이그레이션 — 변경 없음 (frontend-only).
  - 스타일/레이아웃/subtitle 문구 — 변경 없음.

### Acceptance
- [ ] `apps/web/app/signup/page.tsx` 의 상단 `<h1>` 텍스트가 정확히 `가입하기` 이다.
- [ ] `/signup` 페이지 렌더 시 상단 제목이 '가입하기' 로 표시된다.
- [ ] Header 네비게이션의 '회원가입' 링크 텍스트는 그대로 유지된다 (변경 없음).
- [ ] login 페이지 하단 '회원가입' 링크 텍스트는 그대로 유지된다 (변경 없음).
- [ ] 홈(page.tsx) 의 '회원가입' 링크 텍스트는 그대로 유지된다 (변경 없음).
- [ ] `apps/api` / DB / 마이그레이션 변경 0건.
- [ ] `apps/web` 빌드(lint/type)가 통과한다.

### Files touched (예상)
- `apps/web/app/signup/page.tsx` — 상단 `<h1>` 텍스트 1줄 변경 (line 43 부근)

### related_prd
- 해당 없음 (UI 카피 변경, 스펙 변경 아님 → PRD.md 수정 불필요)

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
- 일자: 2026-10-28
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
- 일자: 2026-10-28
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
