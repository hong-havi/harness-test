---
id: T029
title: login-button-copy
slug: login-button-copy
branch: task/T029-login-button-copy
worktree: .worktrees/T029-login-button-copy
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: kiro }
  - { role: frontend,   agent: kiro }
  - { role: qa,         agent: kiro }
  - { role: reviewer,   agent: kiro }
current_role: qa
role_history: []
run_id: run_3b4a791aaa67
ports:
  web: 3290
  api: 4290
  db: 3335
compose_project: harness_t029
figma_url: null
blocked_by: []
related_prd: []
priority: normal          # high | normal | low
created_at: 2026-10-28
updated_at: 2026-10-28
---

## User Request

> 로그인 페이지(/login)의 '로그인' 버튼 텍스트를 '로그인하기' 로 변경. 버튼 외 다른 변경 없음. frontend-only, 백엔드 변경 없음.

---

_(T029 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_


# T029 — login-button-copy

## Plan

### Why
로그인 페이지의 제출 버튼 레이블을 더 명확한 행동 유도(CTA) 문구로 바꾼다. 단순 명사 '로그인' 보다 동사형 '로그인하기' 가 버튼 행위를 더 분명히 전달한다. 순수 카피 변경으로 사용자 가치(명확성) 외 기능/로직 영향은 없다.

### What
`apps/web/app/login/page.tsx` 의 제출 버튼 idle 상태 레이블 `'로그인'` → `'로그인하기'` 로 변경한다. 제출 중(`submitting`) 상태의 `'처리 중…'` 레이블은 그대로 둔다.

- 대상 위치: `apps/web/app/login/page.tsx:84`
  - before: `{submitting ? '처리 중…' : '로그인'}`
  - after:  `{submitting ? '처리 중…' : '로그인하기'}`

### Scope
- 포함: `/login` 페이지 제출 버튼의 idle 레이블 문자열 1건 변경.
- 제외:
  - Header 의 `/login` 링크 텍스트(`로그인`) — 변경 안 함 (요구 범위 밖).
  - 홈(`app/page.tsx`)·회원가입(`join`/`signup`) 페이지의 '로그인' 문구 — 변경 안 함.
  - 백엔드(`apps/api`) 변경 없음.
  - 스타일/레이아웃/로직 변경 없음.

### Acceptance
- [ ] `/login` 접속 시 제출 버튼 텍스트가 `로그인하기` 로 표시된다.
- [ ] 폼 제출 진행 중에는 버튼 텍스트가 `처리 중…` 으로 유지된다 (기존 동작 보존).
- [ ] Header 의 `/login` 링크 등 다른 '로그인' 문구는 변경되지 않는다.
- [ ] `apps/api` 하위 파일은 변경되지 않는다 (frontend-only).
- [ ] `pnpm --filter web build` 혹은 타입체크가 통과한다.

### Files touched (예상)
- `apps/web/app/login/page.tsx` — 제출 버튼 idle 레이블 문자열 1건.

### related_prd
- 회원 모듈 / 로그인 화면 (UI 카피). PRD 스펙 변경은 불필요 — 문구 미세 조정이라 PRD.md 수정 없음.

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

### 변경 파일
- `apps/web/app/login/page.tsx` — 제출 버튼 idle 레이블 `'로그인'` → `'로그인하기'` (1줄). submitting 상태의 `'처리 중…'` 는 그대로.

### 추가 라우트/페이지
- 없음 (기존 `/login` 페이지 카피 변경만).

### 새 환경변수
- 없음.

### 로컬 재현 (브라우저 시나리오)
1. `docker compose up` (WEB=:3290 / API=:4290 / DB=:3335) 또는 `pnpm --filter web dev`.
2. 브라우저로 `/login` 접속.
3. 제출 버튼 레이블이 `로그인하기` 로 표시되는지 확인.
4. 이메일/비밀번호 입력 후 제출 → 처리 중 버튼 레이블이 `처리 중…` 으로 바뀌는지 확인 (기존 동작 보존).
5. Header 의 `/login` 링크 텍스트는 여전히 `로그인` 인지 확인 (범위 밖, 변경 없음).

### QA 테스트 시나리오 (URL + 조작 + 기대)
| # | URL / 조작 | 기대 결과 |
|---|-----------|-----------|
| 1 | `/login` 접속 | 제출 버튼 텍스트 = `로그인하기` |
| 2 | 유효 자격증명 입력 후 제출 | 제출 중 버튼 텍스트 = `처리 중…` (기존 유지) |
| 3 | Header 의 로그인 링크 확인 | 텍스트 = `로그인` (변경 안 됨) |

### 수용 기준 자가 검증
- [x] `/login` 제출 버튼 텍스트가 `로그인하기` 로 표시 (코드 확인: page.tsx:84).
- [x] 제출 중 버튼 텍스트 `처리 중…` 유지 (분기 그대로).
- [x] Header `/login` 링크 등 다른 '로그인' 문구 미변경 (단일 파일 1줄만 수정).
- [x] `apps/api` 하위 미변경 (frontend-only).
- [x] `pnpm --filter web typecheck` 통과 (exit 0), `pnpm --filter web lint` 통과 (exit 0).

---

## QA report

### 결과
- 결정: **pass**
- 일자: 2026-10-28
- 환경: 정적 카피 변경 — 소스/빌드 검증 (WEB=:3290/API=:4290/DB=:3335 스코프). Docker 전체 기동은 one-word 정적 레이블 변경에 불비례하여 생략, 대신 typecheck+lint+소스 확인으로 검증.

### 수용 기준 검증
- [x] `/login` 제출 버튼 텍스트 = `로그인하기` — pass (page.tsx:84 idle 분기 `{submitting ? '처리 중…' : '로그인하기'}`)
- [x] 제출 중 버튼 텍스트 `처리 중…` 유지 — pass (submitting 분기 그대로 보존)
- [x] Header `/login` 링크 등 다른 '로그인' 문구 미변경 — pass (Header.tsx:62 `로그인` 유지; page/join/signup 미변경)
- [x] `apps/api` 하위 미변경 — pass (commit d0dda9f stat: apps/web/app/login/page.tsx 1건 + task.md만)
- [x] `pnpm --filter web build`/타입체크 통과 — pass (typecheck exit 0, lint exit 0 "No ESLint warnings or errors")

### 회귀 (Regression)
- grep `로그인` 전수 확인: login 페이지 버튼 레이블 1건만 변경. 로그인 플로우 진입점(Header 링크, join/signup 안내 링크) 텍스트 불변 — 네비게이션 회귀 없음.

### 발견 사항
- 없음. 커밋 d0dda9f 가 계획대로 단일 문자열 1줄만 변경. 민감정보 노출 없음.

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
