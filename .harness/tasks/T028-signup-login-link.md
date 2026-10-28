---
id: T028
title: signup-login-link
slug: signup-login-link
branch: task/T028-signup-login-link
worktree: .worktrees/T028-signup-login-link
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: kiro }
  - { role: frontend,   agent: kiro }
  - { role: qa,         agent: kiro }
  - { role: reviewer,   agent: kiro }
current_role: planner
role_history: []
ports:
  web: 3280
  api: 4280
  db: 3334
compose_project: harness_t028
figma_url: null
blocked_by: []
related_prd: []
priority: normal          # high | normal | low
created_at: 2026-10-28
updated_at: 2026-10-28
---

# T028 — signup-login-link

## Plan

### Why
회원가입(/signup) 페이지에 이미 계정이 있는 사용자가 로그인 페이지로 빠르게 이동할 수 있는 동선을 제공한다. /login 페이지에는 이미 대칭되는 "계정이 없으신가요? 회원가입" 링크가 존재하므로, /signup → /login 방향의 상호 링크를 맞춰 UX 일관성을 확보한다.

### What
/signup 페이지 제출 버튼(`가입하기`) 아래에 "이미 계정이 있으신가요?" 안내 텍스트와 /login 으로 가는 링크를 노출한다. frontend-only 변경이며 백엔드/DB/API 변경은 없다.

### 현황 확인 (planner 조사 결과)
- **이미 구현되어 있음**: `apps/web/app/signup/page.tsx` 의 `</form>` 직후에 다음 요소가 존재한다.
  ```tsx
  <p className="form-footer">
    이미 계정이 있으신가요? <Link href="/login">로그인</Link>
  </p>
  ```
- `Link` 는 `next/link` 에서 이미 import 되어 있음.
- `.form-footer` 스타일은 `apps/web/app/globals.css:214` 에 정의되어 있음.
- /login 페이지도 동일한 `form-footer` 패턴으로 대칭 링크를 제공 중 (`계정이 없으신가요? 회원가입`).
- 결론: 요구사항은 코드 수준에서 **이미 충족**되어 있다. 신규 구현 작업은 불필요하며, 남은 것은 렌더 검증과 리뷰다.

### Scope
- 포함: /signup 제출 버튼 하단의 "이미 계정이 있으신가요?" 텍스트 + /login 링크 노출 확인/보정.
- 제외: 백엔드/DB/API 변경, /login 페이지 변경, 신규 스타일 토큰, 레이아웃 리팩터.

### Acceptance
- [ ] /signup 렌더 시 제출 버튼 아래에 "이미 계정이 있으신가요?" 텍스트가 보인다.
- [ ] 해당 영역의 "로그인" 링크가 `/login` 으로 이동한다 (클릭 시 href="/login").
- [ ] 링크가 `<form>` 바깥, 제출 버튼보다 아래(DOM 순서상 form 다음)에 위치한다.
- [ ] 백엔드/API/DB 변경이 없다 (git diff 에 apps/api 변경 없음).

### Files touched (예상)
- `apps/web/app/signup/page.tsx` — 이미 요구 요소 존재. frontend 는 현황 재확인 후 무변경 또는 미세 보정만.

### 다음 역할 참고
- **frontend**: 이미 요소가 존재하므로 신규 코드 추가 금지(YAGNI). `/signup` 하단 링크가 요구와 일치하는지 확인만. 불일치가 없으면 무변경 보고.
- **qa**: 위 Acceptance 4개 항목을 /signup 렌더 기준으로 검증.
- **reviewer**: frontend-only·무변경(혹은 미세 보정) 전제 확인 후 승인.

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
