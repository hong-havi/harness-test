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
current_role: reviewer
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


## Implementation (Frontend)

### 변경 라우트/페이지
- `apps/web/app/me/page.tsx` — '가입일'(createdAt) 값 렌더를 `formatDateYmd()` 로 교체.
  - 신규 `formatDateYmd(iso)` 추가: 브라우저 로컬 TZ 기준 `YYYY-MM-DD`,
    `getFullYear/getMonth(+1)/getDate` + `padStart(2,'0')` zero-pad.
    파싱 실패(`Number.isNaN(d.getTime())`) 시 원본 `iso` 반환.
  - 기존 `formatDate()` 는 '최근 수정'(updatedAt) 전용으로 그대로 유지 (날짜+시각, 회귀 없음).

### 새 환경변수
- 없음.

### 범위
- frontend-only. `apps/web/app/me/page.tsx` 1개 파일만 코드 변경.
- `apps/api` / DB / 마이그레이션 / `lib/types.ts` 변경 없음 (git status 로 확인).

### 수용 기준 자가 검증
- [x] 린트 통과 — `pnpm exec next lint` → "No ESLint warnings or errors".
- [x] 타입체크 통과 — `pnpm exec tsc --noEmit` → exit 0.
- [x] '가입일' 포맷 `^\d{4}-\d{2}-\d{2}$` (시각 미표시) — `formatDateYmd` 로직상 보장.
- [x] zero-pad — `padStart(2,'0')` 로 월·일 2자리 보장 (예: `2024-03-05`).
- [x] 로컬 TZ 기준 — `getFullYear/getMonth/getDate` 사용 (UTC 절단 아님). KST 환경에서
      `2024-01-15T23:30:00Z` → `2024-01-16` 로 날짜 경계 반영.
- [x] updatedAt 회귀 없음 — '최근 수정' 행은 `formatDate()` 그대로.
- [x] 비정상 createdAt 방어 — NaN 시 원본 문자열 노출, 페이지 비파괴.
- [x] `dangerouslySetInnerHTML` 미사용.

### 로컬 재현 / QA 테스트 시나리오
전제: `docker compose up` (이 worktree 포트 web=3190 / api=4190 / db=3325), 회원 로그인 완료.

1. 브라우저에서 `http://localhost:3190/me` 접속.
   - 기대: '가입일' 행이 `YYYY-MM-DD` (예: `2024-01-16`) 형태. 시각 미표시.
   - 기대: '최근 수정' 행은 기존처럼 날짜+시각(`YYYY. M. D. 오후 h:mm:ss`) 유지.
2. zero-pad 확인: createdAt 이 1~9월/1~9일인 계정으로 접속 → `2024-03-05` 처럼 2자리.
3. 로컬 TZ 경계: KST(+09:00) 환경에서 createdAt 의 UTC 시각이 15:00Z 이후면
   로컬 날짜가 +1 일로 표시되는지 확인 (UTC 절단이면 하루 어긋남 → 버그).
4. DevTools Console 에서 `document.cookie` 조회 → `access_token` 미노출 (HttpOnly 유지, 회귀 확인용).
5. (선택) 비정상 createdAt 방어: 정상 경로에선 재현 불가하나, 코드상 NaN 시 원본 반환으로 페이지 비파괴.



## QA report

### 결정: PASS → reviewer

frontend-only 날짜 포맷 변경. 수용 기준은 전부 client-side `formatDateYmd` 출력에 대한
결정적(deterministic) 검증이므로, 실제 소스 로직을 그대로 Node(TZ=Asia/Seoul, offset -540 확인)
에서 실행하여 전수 검증 + 프로젝트 lint/typecheck/next build 로 교차 확인했다.

### 1. 수용 기준 (task.md Acceptance) — 전수 PASS
- [PASS] '가입일' 값이 `^\d{4}-\d{2}-\d{2}$` 매칭 (시각 미표시).
  검증: `formatDateYmd('2024-01-15T06:30:00Z')` → `2024-01-15` (regex 매칭).
- [PASS] 브라우저 로컬 TZ 기준 변환.
  검증(KST): `2024-01-15T23:30:00Z` → `2024-01-16` (UTC 날짜 `01-15` 아님 — 경계 올바름).
  `2024-01-15T06:30:00Z` → `2024-01-15` (같은 날 15:30 로컬).
- [PASS] zero-pad 2자리.
  검증: `2024-03-05T03:00:00Z` → `2024-03-05`.
- [PASS] '최근 수정'(updatedAt) 회귀 없음.
  검증: `formatDate('2024-01-15T23:30:00Z')` → 날짜+시각(`toLocaleString('ko-KR')`), YYYY-MM-DD 아님.
  git diff 확인: updatedAt 렌더는 여전히 `formatDate()` 사용, 변경 없음.
- [PASS] 비정상 createdAt 방어.
  검증: `'not-a-date'`/`''` → 원본 문자열 그대로 반환 (NaN 가드), 페이지 비파괴.
- [PASS] frontend-only (apps/api / DB 변경 커밋 없음).
  검증: `git diff --name-only main..HEAD` → `apps/web/app/me/page.tsx` + task.md 만. API/DB/migration/lib/types.ts 무변경.
- [EXTRA PASS] 연 경계: `2024-12-31T15:00:00Z` (KST) → `2025-01-01`.

검증 결과: 결정적 로직 테스트 9/9 PASS (TZ=Asia/Seoul).

### 2. 회귀 (Regression)
- [PASS] '최근 수정'(updatedAt) 표시 포맷 유지 — 위 참조.
- [PASS] `next build` 전체 성공, `/me` 라우트 포함 9개 페이지 컴파일 (2.38 kB).

### 3. 비기능
- [PASS] lint — `next lint` → "No ESLint warnings or errors".
- [PASS] typecheck — `tsc --noEmit` → exit 0.
- [PASS] `dangerouslySetInnerHTML` 미사용 (신규 코드는 순수 문자열 포맷, XSS 경로 없음).
- [N/A 이번 변경과 무관] HttpOnly 쿠키/상태코드/401/403/CSRF — 본 변경은 백엔드·인증 경로를
  건드리지 않음(frontend 표시 로직만). 라이브 docker UAT 미수행(아래 한계 참조).

### 4. 환경 — 라이브 docker UAT 미수행 (한계 명시)
- Docker Desktop 가용(29.1.2) 하나, 이 worktree `.env` 는 포트 스코프만 포함하고
  `JWT_SECRET`/`DB_PASSWORD` 등 compose 필수 시크릿이 없어 end-to-end 기동(이미지 빌드 +
  migration + 로그인 → /me) 을 안전하게 수행할 수 없음(시크릿 임의 생성 지양).
- 다만 본 task 의 수용 기준은 전부 결정적 client-side 포맷 출력이며, 실제 소스 로직을
  그대로 실행 검증 + next build 산출물 확인으로 동등 보장됨. API/DB 계약 변경이 없어
  런타임 기동이 새로 드러낼 동작은 없음.
- reviewer/user 가 원하면 시크릿 포함 `.env` 로 `docker compose up` 후 `/me` 육안 확인 +
  DevTools `document.cookie` HttpOnly 점검(회귀용)을 추가 라운드로 수행 가능.

### 검증에 사용한 명령 (재현용)
- 로직: `TZ=Asia/Seoul node <formatDateYmd 미러 스크립트>` (임시, 검증 후 삭제) → 9/9 PASS.
- `cd apps/web && npx next lint` → clean.
- `cd apps/web && npx tsc --noEmit -p tsconfig.json` → exit 0.
- `cd apps/web && npx next build` → Compiled successfully, `/me` 포함.
- `git diff --name-only main..HEAD` → frontend-only 확인.



## Review notes

### 결정: PASS → approve for merge (user 승인 대기)

Blocker 없음. 7개 영역 체크리스트 전수 통과. 변경은 frontend-only, 최소 범위.

### 리뷰 대상
- 커밋: 565a2b3 (plan) → c20c556 (frontend) → b109528 (qa report)
- diff vs main: `apps/web/app/me/page.tsx` + `.harness/tasks/T019-me-created-date.md` 만.

### 체크리스트 (7영역) — 근거

1. PRD 정합성 [PASS]
   - 수용 기준 전수 충족(아래 2 참조). §7 Out of Scope 미혼입(updatedAt/백엔드/i18n 無).
   - API 계약 변경 없음 — `createdAt` 은 기존 `MemberProfile` 필드 그대로 사용.

2. 보안 [PASS]
   - 순수 문자열 포맷(`formatDateYmd`). `dangerouslySetInnerHTML` 미사용 → XSS 경로 없음
     (page.tsx:17-25 신규 함수, page.tsx:139 렌더).
   - 사용자/외부 입력을 쿼리·HTML 로 삽입하는 신규 경로 없음.
   - 비밀값/토큰 git 미혼입: `git diff --name-only main..HEAD -- *.env *.env.* apps/api/* **/migration*/*` → 빈 결과.
   - 401 리다이렉트·HttpOnly 쿠키 경로 무변경(회귀 없음).

3. 리소스/누수 [PASS]
   - 신규 timer/listener/구독 없음. `formatDateYmd` 는 순수 동기 함수.
   - 기존 `useEffect(fetchMe)` 의존성 `[fetchMe]` 유지, 변경 없음.

4. 성능/데이터 [PASS/N/A]
   - 쿼리·스키마·마이그레이션 변경 없음(frontend-only). N+1/인덱스/페이지네이션 해당 없음.

5. 코드 품질 [PASS]
   - `formatDateYmd` 단일 책임, 명명이 의도를 드러냄(가입일 전용 YYYY-MM-DD).
   - 과도한 추상화·플래그 없음(YAGNI). 미사용 import/변수 없음. `console.log`/디버그 無.
   - 커밋 메시지 `T019 [kiro]:` 접두어 정상.

6. 테스트 [PASS]
   - QA report PASS. reviewer 독립 재현(TZ=Asia/Seoul, offset -540):
     결정적 로직 6/6 PASS — `06:30Z→01-15`, `23:30Z→01-16`(UTC 경계), `03-05`(zero-pad),
     `12-31 15:00Z→2025-01-01`(연 경계), `'not-a-date'`/`''`→원본(NaN 가드).
     전 출력 `^\d{4}-\d{2}-\d{2}$` 매칭.
   - lint: `next lint` → "No ESLint warnings or errors". typecheck: `tsc --noEmit` → exit 0.

7. 범위 [PASS]
   - task 범위 밖 리팩터/수정 없음. '최근 수정'(updatedAt) 행은 `formatDate()` 그대로(회귀 없음).

### Suggest (비차단)
- 없음.

### 병합 참고
- `main` 이 HEAD 조상이 아님(main 에 `bc5c36e` task 생성 커밋 존재) → rebase 필요.
  `tasks.sh merge` 가 rebase + ff-only 수행. 의미적 충돌 없음(파일 분리).

### 환경 한계 승계
- QA 와 동일하게 라이브 docker UAT 는 compose 시크릿 부재로 미수행. 본 변경은 결정적
  client-side 포맷이며 소스 로직 직접 실행 + lint/typecheck 로 동등 보장.
