---
id: T015
title: show-updated-date
slug: show-updated-date
branch: task/T015-show-updated-date
worktree: .worktrees/T015-show-updated-date
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: kiro }
  # architect 제외: 신규 엔티티/API 계약 없음 (updatedAt 는 이미 /members/me 응답에 존재)
  # designer 제외: 신규 화면/컴포넌트 없음, 기존 profile-row 재사용
  # backend 제외: API 응답에 updatedAt 이미 포함 (members.service.ts toView)
  - { role: frontend,   agent: kiro }
  - { role: qa,         agent: kiro }
  - { role: reviewer,   agent: kiro }
current_role: planner
role_history: []
run_id: run_4bee4185e304
ports:
  web: 3150
  api: 4150
  db: 3321
compose_project: harness_t015
figma_url: null
blocked_by: []
related_prd: ["3.1 데이터 모델 (members.updated_at)", "5.1 GET /members/me"]
priority: normal          # high | normal | low
created_at: 2026-10-26
updated_at: 2026-10-26
---

## User Request

> 회원 내 정보(/me) 페이지에 '최종 수정일(updated_at)' 을 가입일(created_at) 바로 아래에 YYYY-MM-DD 포맷으로 표시해주세요. API 응답에 이미 updated_at 이 포함되어 있다면 UI 추가만 하면 됨. 범위: frontend 중심.

---

_(T015 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_


# T015 — show-updated-date

## Plan

### Why
- 회원이 내 정보(/me) 페이지에서 **본인 계정이 마지막으로 수정된 시점**을 한눈에 확인할 수 있어야 한다 (닉네임/비밀번호 변경 추적).
- `updated_at` 은 PRD §3.1 에 정의된 필드이며, 이미 `GET /members/me` 응답(`members.service.ts` `toView`)에 `updatedAt` 으로 포함되어 프런트 타입(`MemberProfile.updatedAt`)까지 노출돼 있다. 즉 **데이터는 이미 흐르고 있고, 표시 포맷/위치만 요구사항에 맞추면 된다.**

### 현황 조사 (planner 확인)
- `apps/web/app/me/page.tsx` 는 이미 `updatedAt` 을 "최근 수정" 라벨로 **가입일 바로 아래** 렌더 중 (L128~134).
- 다만 현재 포맷이 `formatDate()` → `new Date(iso).toLocaleString('ko-KR')` 로 **날짜+시각 전체**가 출력됨. 요구사항은 **`YYYY-MM-DD` (날짜만)**.
- 가입일(createdAt) 도 동일 `formatDate` 를 쓰므로 날짜+시각으로 출력됨. 요구사항은 updated_at 에 한정되나, "가입일 바로 아래 YYYY-MM-DD" 라는 user 의도상 **두 값의 포맷을 일관되게 YYYY-MM-DD 로 맞추는 것**이 자연스럽다. → 아래 Scope 에서 명시.

### What
- `/me` 페이지의 **최종 수정일(updatedAt)** 을 `YYYY-MM-DD` 포맷으로, **가입일(createdAt) 바로 아래 행**에 표시한다 (위치는 이미 충족, 포맷만 변경).
- 가입일(createdAt) 도 일관성을 위해 동일한 `YYYY-MM-DD` 포맷으로 표시한다.
- 날짜 포맷팅 로직을 `toLocaleString` → `YYYY-MM-DD` 반환 헬퍼로 교체.

### Scope
- 포함:
  - `apps/web/app/me/page.tsx` 의 날짜 표시 포맷을 `YYYY-MM-DD` 로 변경 (updatedAt 필수, createdAt 일관성 차원 동일 적용).
  - 유효하지 않은 날짜 문자열에 대한 방어 (NaN 시 원문 fallback 유지).
- 제외:
  - 백엔드/API 변경 — `updatedAt` 은 이미 응답에 존재.
  - 시각(HH:mm) 표시 — 요구사항은 날짜만.
  - 타임존 정책 재설계 — 로컬 타임존 기준 표기 유지 (별도 UTC 고정 요구 없음).
  - 다른 페이지(게시글 목록/상세 등)의 날짜 포맷 — 이번 범위 밖 (YAGNI).
  - "최근 수정" 라벨 문구의 "최종 수정일" 등 리네이밍 — 기능 영향 없음. frontend 재량(선택).

### Acceptance
- [ ] `/me` 페이지에 최종 수정일(updatedAt) 이 `YYYY-MM-DD` 형식(예: `2026-10-26`)으로 표시된다 (시각 미표시).
- [ ] 최종 수정일 행이 가입일 행 **바로 아래**에 위치한다.
- [ ] 가입일(createdAt) 도 `YYYY-MM-DD` 형식으로 표시된다.
- [ ] 월/일이 한 자리일 때 **zero-padding** 되어 항상 10자리(`YYYY-MM-DD`)로 렌더된다 (예: `2026-01-05`).
- [ ] 정보 수정(닉네임/비번 변경) 성공 후 `updateMe` 응답 반영으로 최종 수정일이 갱신되어 보인다.
- [ ] 날짜 문자열이 유효하지 않은 경우 페이지가 깨지지 않는다 (원문 또는 안전 fallback).
- [ ] `pnpm --filter web build` (또는 lint/tsc) 가 통과한다.

### Files touched (예상)
- `apps/web/app/me/page.tsx` — `formatDate` 헬퍼를 `YYYY-MM-DD` 반환으로 교체 (또는 날짜 전용 헬퍼 추가).

### 다음 역할 참고 (frontend)
- 로컬 타임존 기준으로 `getFullYear()/getMonth()+1/getDate()` 를 2자리 zero-pad 하여 조합 권장 (`toISOString()` 은 UTC 로 변환되어 날짜가 하루 밀릴 수 있으니 주의).
- 기존 `formatDate` 는 createdAt/updatedAt 두 곳에서 쓰이므로 헬퍼 한 곳만 수정하면 두 값 모두 반영됨.
- `MemberProfile.createdAt/updatedAt` 은 `string`(ISO) 계약. 변경 불필요.

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
- 일자: 2026-10-26
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
- 일자: 2026-10-26
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
