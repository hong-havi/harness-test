---
id: T020
title: me-logout-button
slug: me-logout-button
branch: task/T020-me-logout-button
worktree: .worktrees/T020-me-logout-button
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: kiro }
  - { role: architect,  agent: kiro }
  # - { role: designer,   agent: kiro, mcp: [figma] }
  - { role: backend,    agent: kiro }
  # - { role: frontend,   agent: kiro }
  - { role: qa,         agent: kiro }
  - { role: reviewer,   agent: kiro }
current_role: planner
role_history: []
ports:
  web: 3200
  api: 4200
  db: 3326
compose_project: harness_t020
figma_url: null
blocked_by: []
related_prd: []
priority: normal          # high | normal | low
created_at: 2026-10-27
updated_at: 2026-10-27
---

## User Request

> 회원 /me 페이지에 '로그아웃' 버튼 추가. 클릭 시 백엔드 POST /auth/logout 호출하고 /login 으로 리다이렉트. 백엔드 변경 없음 (API 가 이미 있다고 가정, 없으면 planner 가 scope 재조정). 프론트엔드 전용.

---

_(T020 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_


# T020 — me-logout-button

## Plan
<planner 작성>

### Why
<사용자 가치 또는 기술적 이유>

### What
<결과물 기준 — 무엇을 바꾸는가>

### Scope
- 포함: ...
- 제외: ...

### Acceptance
- [ ] <측정 가능한 수용 기준>
- [ ] ...

### Files touched (예상)
- `apps/.../...`

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
- 일자: 2026-10-27
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
- 일자: 2026-10-27
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
