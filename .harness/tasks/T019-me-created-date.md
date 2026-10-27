---
id: T019
title: /me 가입일을 YYYY-MM-DD(로컬 TZ) 포맷으로 표시
slug: me-created-date
branch: task/T019-me-created-date
worktree: .worktrees/T019-me-created-date
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,   agent: kiro }
  - { role: frontend,  agent: kiro }
  - { role: qa,        agent: kiro }
  - { role: reviewer,  agent: kiro }
current_role: planner
role_history: []
ports:
  web: 3190
  api: 4190
  db: 3325
compose_project: harness_t019
figma_url: null
blocked_by: []
related_prd: ["3.1 데이터 모델", "5.1 Auth / Member (GET /members/me)"]
priority: normal          # high | normal | low
created_at: 2026-10-27
updated_at: 2026-10-27
---

# T019 — /me 가입일을 YYYY-MM-DD(로컬 TZ) 포맷으로 표시

## Plan

### Why
회원 `/me` 페이지의 '가입일' 값이 현재 `toLocaleString('ko-KR')` 로 렌더되어
날짜 + 시각 전체(예: `2024. 1. 15. 오후 3:30:12`)가 노출된다. 사용자는 가입일을
간결한 `YYYY-MM-DD` 형태로만 보기를 원한다. 가독성·일관성 개선이 목적이며,
백엔드가 이미 `createdAt`(ISO8601 문자열)을 내려주므로 프론트 표시 로직만 바꾸면 된다.

### What
`/me` 페이지의 '가입일' 라벨에 대응하는 값을 `user.createdAt` 기준
**`YYYY-MM-DD` (브라우저 로컬 타임존)** 포맷으로 표시한다.

- 대상: '가입일' 행만. '최근 수정'(updatedAt) 행은 **범위 밖** — 기존 표시 유지.
- 포맷 기준: 로컬 TZ의 연·월·일을 2자리 zero-pad 하여 `YYYY-MM-DD`.
  - UTC 기준이 아니라 **브라우저 로컬 타임존** 기준 날짜를 사용한다
    (예: ISO 가 `2024-01-15T23:30:00Z` 이고 로컬이 KST(+09:00)면 `2024-01-16`).
- 잘못된/빈 `createdAt` 방어: 파싱 실패 시 원본 문자열 그대로 노출(기존 방어 로직 유지).

### Scope
- 포함:
  - `apps/web/app/me/page.tsx` — '가입일' 값 렌더에 사용할 `YYYY-MM-DD` 포맷 함수 적용.
  - 날짜 포맷 유틸(신규 `formatDateYmd` 또는 기존 `formatDate` 와 분리된 함수) 추가.
- 제외:
  - 백엔드(`apps/api`) / DB / 마이그레이션 변경 **없음**.
  - API 응답 계약(`lib/types.ts`) 변경 없음 — `createdAt` 은 이미 존재.
  - '최근 수정'(updatedAt) 표시 포맷 변경 없음.
  - 타임존 선택 UI, 국제화(i18n) 라이브러리 도입 등 추가 기능 없음(YAGNI).

### Acceptance
- [ ] `/me` 페이지 로드 시 '가입일' 값이 정규식 `^\d{4}-\d{2}-\d{2}$` 에 매칭된다
      (연 4자리 - 월 2자리 - 일 2자리, 시각 미표시).
- [ ] 표시되는 날짜는 `createdAt` 을 **브라우저 로컬 타임존**으로 변환한 연/월/일과 일치한다
      (UTC 자정 근처 경계 케이스에서 로컬 날짜로 넘어가는지 확인).
- [ ] 월·일이 한 자리일 때 zero-pad 되어 2자리로 표시된다 (예: `2024-03-05`).
- [ ] '최근 수정' 행은 기존(날짜+시각) 표시가 그대로 유지된다 — 회귀 없음.
- [ ] `createdAt` 이 비정상 값일 때 페이지가 깨지지 않는다(원본 문자열 노출 등 방어 유지).
- [ ] `apps/api` / DB 관련 파일에 변경 커밋이 없다(frontend-only 확인).

### Files touched (예상)
- `apps/web/app/me/page.tsx` — 가입일 렌더 포맷 교체 + `YYYY-MM-DD` 포맷 함수 추가.

### 다음 역할 참고 (frontend)
- 기존 `formatDate(iso)` 는 `toLocaleString('ko-KR')` 로 날짜+시각을 반환하므로
  updatedAt 용으로 그대로 두고, 가입일 전용 `formatDateYmd(iso)` 를 신규 추가 권장.
- 로컬 TZ `YYYY-MM-DD` 구현 예시(권장):
  `const d = new Date(iso); const p=(n)=>String(n).padStart(2,'0');
   return \`${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}\`;`
  (`getFullYear/getMonth/getDate` 는 로컬 TZ 기준이므로 toISOString().slice(0,10)
   같은 UTC 기반 절단은 금지 — 경계 케이스에서 날짜가 틀어짐.)
- 파싱 실패 방어: `Number.isNaN(d.getTime())` 이면 원본 `iso` 반환.
- QA 는 로컬 TZ(KST) 기준으로 날짜 포맷·zero-pad·updatedAt 회귀만 확인하면 됨.
