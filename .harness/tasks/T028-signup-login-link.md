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
current_role: reviewer
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

### 결론: 무변경 (요구사항 기 충족)

planner 분석대로, 요구 요소가 `apps/web/app/signup/page.tsx` 에 **이미 존재**한다.
YAGNI 원칙에 따라 신규 코드를 추가하지 않고, 현황이 요구/Acceptance 와 일치함을 재확인만 수행했다.

### 기존 구현 위치 (정적 검증)
- `apps/web/app/signup/page.tsx` — `</form>` 바로 다음, 제출 버튼보다 DOM 상 아래에 위치:
  ```tsx
  <p className="form-footer">
    이미 계정이 있으신가요? <Link href="/login">로그인</Link>
  </p>
  ```
- `Link` 는 `next/link` 에서 상단 import 되어 있음 (CSR 네비게이션, 전체 새로고침 없음).
- `.form-footer` 스타일은 `apps/web/app/globals.css:214` 에 정의되어 있어 스타일 누락 없음.
- 사용자 입력 렌더 아님 (고정 문자열) → XSS 벡터 없음. `dangerouslySetInnerHTML` 미사용.

### 추가 라우트/페이지
- 없음 (신규 라우트/페이지 추가 없음).

### 새 환경변수
- 없음.

### 변경 파일
- 코드 무변경. 본 task.md 의 Implementation (Frontend) 섹션 기록만 추가.

### 로컬 재현 (브라우저 시나리오 — qa 참고)
1. 워크트리에서 `docker compose up` (WEB=:3280 / API=:4280 / DB=:3334).
2. 브라우저로 `http://localhost:3280/signup` 접속.
3. 제출 버튼("가입하기") 아래에 "이미 계정이 있으신가요? 로그인" 노출 확인.
4. "로그인" 링크 클릭 → `/login` 으로 이동 (href="/login").
5. DOM 검사: `<p class="form-footer">` 가 `<form>` 바깥, form 다음 형제로 존재.

### 수용 기준 자가 검증
- [x] /signup 제출 버튼 아래 "이미 계정이 있으신가요?" 텍스트 노출 — page.tsx form-footer 로 충족.
- [x] "로그인" 링크가 `/login` 으로 이동 — `<Link href="/login">`.
- [x] 링크가 `<form>` 바깥, 제출 버튼보다 아래(DOM 순서상 form 다음) — `</form>` 다음 `<p className="form-footer">`.
- [x] 백엔드/API/DB 변경 없음 — `apps/api` 무변경, frontend-only.

### 비고 (의존성 미설치로 인한 한계)
- 이 워크트리에는 `node_modules` 가 설치되어 있지 않아 `next lint` / `tsc --noEmit` / `docker compose up` 런타임 검증은 수행하지 못했다.
- 대신 소스 정적 검증(import 경로·JSX 유효성·CSS 클래스 정의 확인)으로 코드 정합성을 확인했다. 실제 렌더 검증은 qa 역할에서 수행한다.

---

## QA report

### 결과
- 결정: **pass**
- 일자: 2026-10-28
- 환경: WEB=:3280 / API=:4280 / DB=:3334 (docker compose, harness_t028)
- 기동: `docker compose up -d` — db(healthy)/api/web 전부 running, HTTP 200.

### 수용 기준 검증 (런타임 렌더 기준)
- [x] /signup 렌더 시 제출 버튼 아래 "이미 계정이 있으신가요?" 텍스트 노출 — pass
      (렌더 HTML 에 `<p class="form-footer">이미 계정이 있으신가요? ...` 확인)
- [x] "로그인" 링크가 `/login` 으로 이동 — pass
      (렌더 HTML: `<a href="/login">로그인</a>`)
- [x] 링크가 `<form>` 바깥, 제출 버튼보다 아래(DOM 순서상 form 다음) — pass
      (바이트 인덱스 순서: 가입하기 버튼 2057 < `</form>` 2070 < `form-footer` 2087)
- [x] 백엔드/API/DB 변경 없음 — pass
      (`git diff --stat main...HEAD` → 변경 파일은 `.harness/tasks/T028-signup-login-link.md` 1건뿐. apps/api·apps/web 코드 무변경)

### 회귀 (Regression)
- [x] /login 페이지 대칭 링크 정상 — `GET /login` 200, 렌더 HTML 에 `href="/signup"` + `form-footer` 존재 (상호 링크 UX 일관성 확인).
- [x] /signup 페이지 `GET` 200.

### 비기능
- 본 변경은 frontend-only 정적 문자열 링크 노출. 인증/권한/CSRF/상태코드 경로에 영향 없음 (API 무변경).
- 고정 문자열 렌더 → XSS 벡터 없음, 민감정보 노출 없음.

### 발견 사항
- 없음 (전 항목 pass).

### 비고 (환경)
- 워크트리 `.env` 가 포트 스코프 변수만 있어 db/jwt 공통 변수가 누락 → db 컨테이너가 `MYSQL_ROOT_PASSWORD` 미설정으로 unhealthy. QA 검증을 위해 `.env` (gitignore) 에 `.env.example` 기준 공통 변수를 append 하여 기동. 이는 로컬 검증용 환경 보정이며 커밋 대상 코드에는 영향 없음.

---

## Review notes

### 결과
- 결정: **pass** (approve for merge — 사용자 승인 대기)
- 일자: 2026-10-28
- 병합 SHA: <merge 수행 후 기록>

### 리뷰 범위
- 변경 diff: `git diff main...HEAD` → `.harness/tasks/T028-signup-login-link.md` 1건뿐 (frontend/qa 기록). **코드 무변경** (apps/web·apps/api 손대지 않음).
- 요구 요소(`/signup` → `/login` 링크)는 이미 존재 → planner/frontend 가 YAGNI 로 무변경 결론. reviewer 는 현황 정합성 + 안전성만 검증.

### 체크리스트 (파일:라인 근거)
1. **PRD 정합성** ✅
   - `apps/web/app/signup/page.tsx` 끝부분(`</form>` 직후)에 `<p className="form-footer">이미 계정이 있으신가요? <Link href="/login">로그인</Link></p>` 존재 → Acceptance 4개 전부 충족.
   - §7 Out of Scope 혼입 없음(백엔드/API/DB 무변경). API 계약(§5) 변경 없음.
2. **보안** ✅
   - 고정 문자열 렌더, `dangerouslySetInnerHTML` 미사용 → XSS 벡터 없음.
   - diff 에 `.env`/`.env.*`/토큰/비밀값 없음 (task.md 1건만). JWT/쿠키/Guard/CSRF 경로 변경 없음(API 무변경).
   - QA 가 로컬 검증용으로 보정한 `.env` 는 gitignore → 커밋 diff 에 미포함 확인.
3. **리소스/누수** ✅
   - `next/link` 기반 CSR 네비게이션. 신규 useEffect/listener/timer/DB 리소스 추가 없음.
4. **성능/데이터** ✅
   - 쿼리/스키마/마이그레이션 변경 없음. N+1·인덱스 이슈 무관.
5. **코드 품질** ✅
   - 코드 무변경(YAGNI 준수). 커밋 메시지 전부 `T028 [kiro]:`/`T028 [harness]:` 접두어 준수. `console.log`/디버그 잔존 없음.
6. **테스트** ✅
   - QA report = **pass**. 런타임 렌더 HTML 기준 어서션(`<a href="/login">로그인</a>`, 바이트 순서로 form-footer 가 `</form>` 다음 확인), /login 대칭 링크 회귀까지 커버.
7. **범위** ✅
   - 태스크 범위 밖 리팩터/수정 없음.

### Blocker
- 없음 (0건).

### Suggest
- 없음.

### 병합 메모
- `git rev-list --left-right --count main...HEAD` = `1  4` (main 이 T028 create-task 1건 선행, 히스토리 분기). `tasks.sh merge` 가 rebase + ff-only 로 처리. 두 브랜치의 task.md add/add 는 rebase 시 우리 쪽(상위집합)으로 해소 필요 — merge 스크립트 rebase 단계에서 확인.

### 체크리스트 요약
- PRD 정합성: ✅
- 보안: ✅
- 리소스/누수: ✅
- 성능/데이터: ✅
- 코드 품질: ✅
- 테스트: ✅
- 범위: ✅
