---
id: T025
title: 전역 Header 컴포넌트 — Nav.tsx 를 Header.tsx 로 리네임/정리
slug: header-login
branch: task/T025-header-login
worktree: .worktrees/T025-header-login
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,   agent: kiro }
  - { role: frontend,  agent: kiro }
  - { role: qa,        agent: kiro }
  - { role: reviewer,  agent: kiro }
current_role: qa
role_history: []
ports:
  web: 3250
  api: 4250
  db: 3331
compose_project: harness_t025
figma_url: null
blocked_by: []
related_prd: ["3.2 F-M2 로그인", "3.2 F-M3 로그아웃", "4.2 권한 매트릭스"]
priority: normal          # high | normal | low
created_at: 2026-10-27
updated_at: 2026-10-27
---

# T025 — 전역 Header 컴포넌트 (Nav.tsx → Header.tsx 리네임/정리)

## Plan

### Why
사용자는 "전역 Header 컴포넌트 추가 — 로그인 시 '{nickname}님' + 로그아웃 버튼,
비로그인 시 로그인/회원가입 링크" 를 요청했다.

조사 결과 요청 기능은 이미 `apps/web/app/components/Nav.tsx` 로 전역(`layout.tsx`)에
구현되어 있다 (로그인 분기, `{nickname}님`, 로그아웃 → `api.logout()` → `/login`,
비로그인 시 로그인/회원가입 링크). 즉 "신규 구현"이 아니라 **네이밍/구조 정리**가
실질 과제다.

Coordinator 경유 사용자 확인 결과 (orchestration ask, 2026-10-27):
> **A) Nav.tsx 를 Header.tsx 로 리네임/구조 정리하여 진행**

따라서 본 task 는 기존 `Nav` 를 의미에 맞는 `Header` 로 **리네임 리팩터** 한다.
중복 UI 를 만들지 않는다 (옵션 B 는 기각됨).

### What
기존 `Nav` 컴포넌트를 `Header` 로 이름/파일/CSS 클래스를 정리한다. **동작·마크업·분기
로직은 보존**한다 (기능 변경 없음, 순수 리네임 리팩터).

구체적으로:
- `apps/web/app/components/Nav.tsx` → `apps/web/app/components/Header.tsx`
  (파일 rename, export 함수명 `Nav` → `Header`)
- `apps/web/app/layout.tsx` 의 import 경로 및 `<Nav />` → `<Header />`
- `apps/web/app/globals.css` 의 BEM 블록 `.nav` / `.nav__brand` / `.nav__links`
  → `.header` / `.header__brand` / `.header__links` (컴포넌트의 className 도 동반 수정)
- `apps/web/app/logout/page.tsx` 주석의 "Nav 의 로그아웃 버튼" 문구 → "Header 의 로그아웃 버튼"

### Scope
- 포함:
  - `Nav.tsx` → `Header.tsx` 파일/컴포넌트 리네임
  - layout.tsx import·사용처 갱신
  - globals.css 의 `.nav*` 클래스 → `.header*` 로 리네임 (컴포넌트 className 동반)
  - logout/page.tsx 주석 문구 갱신
  - 기존 세미컴포넌트 주석("UX 편의일 뿐 보안 경계 아님") 보존
- 제외:
  - **백엔드 변경 없음** (`/auth/logout` API 이미 존재 가정 — PRD §5.1)
  - 신규 UI/스타일 디자인 변경 (색/레이아웃 재설계 금지 — YAGNI, designer 역할 불필요)
  - 로그인 분기 로직 변경, 새 링크/버튼 추가, `/join`(간편가입) 링크 제거/추가
  - 라우팅·middleware 변경
  - 테스트 프레임워크 신규 도입 (프로젝트에 없으면 QA 는 수동/빌드 검증으로 대체)

### Acceptance
- [ ] `apps/web/app/components/Header.tsx` 가 존재하고 `export default function Header()` 를 가진다. `Nav.tsx` 는 삭제된다.
- [ ] `apps/web/app/layout.tsx` 가 `./components/Header` 를 import 하고 `<Header />` 를 렌더한다. `Nav` 참조가 남아있지 않다.
- [ ] 리포 전체(`apps/web`)에 `components/Nav` 또는 `<Nav` 또는 `function Nav(` 참조가 0건이다 (grep 으로 확인). (`next/navigation` import 는 무관하므로 제외)
- [ ] `globals.css` 에 `.nav`/`.nav__brand`/`.nav__links` 가 없고 `.header`/`.header__brand`/`.header__links` 로 대체됐다. 컴포넌트의 className 과 일치한다.
- [ ] `pnpm --filter web build` (또는 프로젝트의 빌드 명령) 가 성공한다 (타입/린트 에러 0).
- [ ] 로그인 상태에서 상단 Header 에 `{nickname}님` + 로그아웃 버튼이 보이고, 로그아웃 클릭 시 `POST /auth/logout` 호출 후 `/login` 으로 이동한다 (기존 동작 유지).
- [ ] 비로그인 상태에서 상단 Header 에 "로그인" + "회원가입" 링크가 보인다 (기존 동작 유지).

### Files touched (예상)
- `apps/web/app/components/Header.tsx` — 신규 (Nav.tsx 에서 rename, 함수명·className 수정)
- `apps/web/app/components/Nav.tsx` — 삭제
- `apps/web/app/layout.tsx` — import 경로 + `<Nav />` → `<Header />`
- `apps/web/app/globals.css` — `.nav*` → `.header*`
- `apps/web/app/logout/page.tsx` — 주석 문구 1곳

### 다음 역할 참고 (handoff)
- `required_roles`: planner → frontend → qa → reviewer. **architect/designer/backend 불필요**
  (스키마·API·신규 UX 디자인 변경 없음, 순수 프런트 리네임).
- frontend: git mv 를 쓰면 히스토리 보존에 유리하나, 환경 제약 시 신규 생성 + 기존 삭제도 허용.
  className 과 CSS 클래스명을 **반드시 일치**시킬 것 (불일치 시 스타일 깨짐).
- qa: 테스트 프레임워크 부재 가능성 높음 → 빌드 성공 + grep 기반 잔여 참조 0 + 수동 2케이스
  (로그인/비로그인 Header 표시)로 수용 기준 검증. 가능하면 web 기동(포트 web:3250/api:4250/db:3331)
  후 브라우저 확인.
- reviewer: 순수 리네임이므로 동작 보존 여부(로그아웃 플로우, 분기)와 잔여 `Nav` 참조 0 을 집중 확인.



## Implementation (Frontend)

### 변경 요약 (순수 리네임 리팩터 — 동작·마크업 보존)
- `apps/web/app/components/Nav.tsx` → `apps/web/app/components/Header.tsx` (git mv, 히스토리 보존)
  - `export default function Nav()` → `export default function Header()`
  - 상단 주석 "상단 네비게이션" → "상단 Header" (세미컴포넌트 보안 경계 주석은 보존)
  - className BEM 블록: `nav` / `nav__brand` / `nav__links` → `header` / `header__brand` / `header__links`
  - 시맨틱 HTML5 `<nav>` 엘리먼트 태그는 유지 (접근성상 header 내 navigation 영역으로 올바름; 스펙상 `next/navigation` 과 함께 제외 대상)
- `apps/web/app/layout.tsx`: `import Nav from './components/Nav'` → `import Header from './components/Header'`, `<Nav />` → `<Header />`
- `apps/web/app/globals.css`: `.nav` / `.nav__brand` / `.nav__links` → `.header` / `.header__brand` / `.header__links` (선언 내용 불변, 컴포넌트 className 과 일치)
- `apps/web/app/logout/page.tsx`: 주석 "주 로그아웃 경로는 Nav 의 로그아웃 버튼" → "Header 의 로그아웃 버튼"

### 추가된 라우트/페이지
- 없음 (신규 라우트 없음, 기존 컴포넌트 리네임만)

### 새 환경변수
- 없음

### 수용 기준 자가 검증
- [x] `components/Header.tsx` 존재, `export default function Header()` 보유. `Nav.tsx` 삭제됨 (git mv R 상태 확인).
- [x] `layout.tsx` 가 `./components/Header` import + `<Header />` 렌더. `Nav` 참조 0.
- [x] `apps/web` 전체에 `components/Nav` / `<Nav` / `function Nav(` / `import Nav` 참조 0건 (grep 확인). 유일한 `nav` 매치는 `<nav className="header">` 시맨틱 태그 (스펙상 제외).
- [x] `globals.css` 에 `.nav*` 0건, `.header` / `.header__brand` / `.header__links` 로 대체됨. 컴포넌트 className 과 일치.
- [x] `pnpm --filter web run build` 성공 — "Compiled successfully", 타입체크/린트 통과, 9/9 static pages 생성, 타입 에러 0.
- [ ] (수동) 로그인 상태 Header 에 `{nickname}님` + 로그아웃 버튼 → 클릭 시 `POST /auth/logout` 후 `/login` 이동 — 로직 보존됨 (코드 diff 상 onLogout/api.logout 불변), 런타임 수동검증은 qa 담당.
- [ ] (수동) 비로그인 상태 Header 에 "로그인" + "회원가입" 링크 — 로직 보존됨 (anon 분기 불변), 런타임 수동검증은 qa 담당.

### 로컬 재현 명령 (qa 용 테스트 시나리오)
사전: 이 worktree 에는 처음에 `node_modules` 가 없어 `pnpm install` 을 1회 수행함 (863 packages). qa 환경에 없으면 동일하게 `pnpm install` 선행.

빌드 검증:
```
pnpm --filter web run build    # "Compiled successfully" + 타입/린트 통과 확인
```

런타임 수동 검증 (포트 web:3250 / api:4250 / db:3331):
```
docker compose up              # web+api+db 기동 (현재 worktree 포트)
```
1. 비로그인 케이스: 브라우저 `http://localhost:3250/` 접속 → 상단 Header 에 "로그인" / "회원가입" / "간편 가입" 링크 표시 확인.
2. 로그인 케이스: `/login` 에서 로그인 → `/` 로 복귀 시 Header 에 `{nickname}님` / "내 정보" / "로그아웃" 버튼 표시 확인.
3. 로그아웃 플로우: 로그아웃 버튼 클릭 → `POST /auth/logout` 네트워크 요청 발생 + `/login` 으로 이동 확인.
4. HttpOnly 검증: DevTools Console 에서 `document.cookie` 에 `access_token` 이 노출되지 않음 확인.
5. (스타일) Header 레이아웃이 기존 Nav 와 동일하게 렌더(상단 바, brand 좌측 / links 우측) — `.header*` 클래스 적용 확인.

### 체크리스트
- [x] 수용 기준 (빌드/정적) 전부 통과, 런타임 2케이스는 qa 핸드오프
- [x] 린트/타입체크 통과 (next build 내 type check 통과)
- [x] HttpOnly 쿠키 로직 불변 (`api.logout` 경로 보존)
- [x] 상태 변경 요청(logout)에 기존 api 래퍼 사용 — CSRF/credentials 처리는 `@/lib/api` 에 위임 (리네임으로 변경 없음)
- [x] `dangerouslySetInnerHTML` 미사용
- [x] 범위 밖 파일 변경 없음 (apps/web + task.md 만)
- [x] chat 에 `deliver` append (완료 시)



## QA report

### 결정: **PASS** → reviewer

순수 리네임 리팩터(Nav → Header). 정적 검증 + 전체 스택(Docker) 런타임 검증을 모두 수행했고
모든 수용 기준을 통과했다. 버그 수정은 없음(QA 는 보고만).

### 환경
- `pnpm install` (lockfile up to date) → `pnpm --filter web run build` 성공.
- `docker compose up -d` (web:3250 / api:4250 / db:3331, COMPOSE_PROJECT_NAME=harness_t025) 전체 기동.
- DB 스키마: 런타임 이미지가 prod(ts-node 부재)라 `migration:run`(ts) 실패 → 컴파일된
  `dist/migrations/*.js` 를 datasource 로 직접 실행하여 마이그레이션 적용
  (`CreateMembers1729468800000`, `AddMemberEmail1729814400000`). **앱 코드/스키마 변경 아님**, QA 환경 기동용.
- 브라우저(Playwright)로 실제 UI 확인.

### 수용 기준 검증 결과 (전수)
- [PASS] `components/Header.tsx` 존재 + `export default function Header()`. `Nav.tsx` 삭제(git mv R).
- [PASS] `layout.tsx` 가 `./components/Header` import + `<Header />` 렌더. `Nav` 참조 0.
- [PASS] `apps/web` 전체 `components/Nav`/`<Nav`/`function Nav(`/`import Nav` 0건
  (grep). 유일 매치는 `<nav className="header">` 시맨틱 태그(스펙상 제외) + `next/navigation`(무관).
- [PASS] `globals.css` 에 `.nav*` 0건, `.header`/`.header__brand`/`.header__links` 로 대체.
  런타임 computed style 확인: `nav.header { display:flex }`, `.header__brand`/`.header__links` 존재 → 스타일 정상 적용.
- [PASS] `pnpm --filter web run build` 성공 — "✓ Compiled successfully", 타입/린트 통과, 9/9 static pages, 에러 0.
  (Docker 내 web 빌드도 동일하게 "Compiled successfully".)
- [PASS] **로그인 상태 Header** — `http://localhost:3250/` 에서 `QA테스터님` + "내 정보" + "로그아웃" 버튼 표시.
  로그아웃 클릭 → `POST /api/auth/logout` **200 OK** → `/login` 이동 확인. 로그아웃 후 Header 가 anon 으로 복귀.
- [PASS] **비로그인 상태 Header** — "로그인" / "회원가입" / "간편 가입" 링크 표시(기존 동작 유지).

### 비기능 교차 검증 (PRD §9 / 권한)
- [PASS] HttpOnly 쿠키: 로그인 후 `document.cookie` = `csrf_token=...` 만 노출, `access_token` **미노출**(hasAccessToken=false). 로그아웃 후 쿠키 전부 제거.
- [PASS] 비로그인에서 보호 API `GET /api/members/me` → **401**(Header 가 anon 분기로 전환). 콘솔 에러는 의도된 401.
- [NOTE] 콘솔의 `favicon.ico 404` 는 리네임과 무관한 기존/범위 밖 cosmetic 이슈(수용 기준 아님).

### 회귀 샘플링
- [PASS] 핵심 플로우 가입 → 로그인 → (내 정보 리다이렉트) → 로그아웃 전 구간 정상.
- [PASS] Header 렌더/분기 로직 동작 보존(anon ↔ authed 전환 정상).

### 발견된 FAIL
- 없음.

### reviewer 참고
- 순수 리네임이므로 동작 보존(로그아웃 플로우·분기)과 잔여 `Nav` 참조 0 을 집중 확인 → 모두 PASS.
- 커밋 변경 파일은 `apps/web` + task.md 뿐. 범위 밖 변경 없음.
