---
id: T006
title: remember-me
slug: remember-me
branch: task/T006-remember-me
worktree: .worktrees/T006-remember-me
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
  web: 3060
  api: 4060
  db: 3312
compose_project: harness_t006
figma_url: null
blocked_by: []
related_prd: []
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

_(T006 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_


# T006 — remember-me

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
