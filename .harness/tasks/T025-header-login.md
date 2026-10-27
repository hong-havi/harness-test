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
current_role: planner
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
