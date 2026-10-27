---
id: T026
title: login-forgot-link
slug: login-forgot-link
branch: task/T026-login-forgot-link
worktree: .worktrees/T026-login-forgot-link
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: kiro }
  # architect 제외: API/스키마 설계 없음 (단순 링크 추가)
  # designer 제외: 신규 UX/Figma 없음 (기존 .form-footer 패턴 재사용)
  # backend 제외: 백엔드/DB 변경 없음 (user 명시)
  - { role: frontend,   agent: kiro }
  - { role: qa,         agent: kiro }
  - { role: reviewer,   agent: kiro }
current_role: planner
role_history: []
run_id: run_a9d43c4e36f3
ports:
  web: 3260
  api: 4260
  db: 3332
compose_project: harness_t026
figma_url: null
blocked_by: []
related_prd: ["3.2 F-M2 로그인", "8 범위 밖(비밀번호 찾기)"]
priority: normal          # high | normal | low
created_at: 2026-10-27
updated_at: 2026-10-27
---

## User Request

> /login 페이지 하단에 '비밀번호 찾기' 링크 추가. 지금은 링크만 (href='/forgot-password', 실제 페이지는 추후 task). frontend-only, 백엔드/DB 변경 없음.

---

_(T026 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_


# T026 — login-forgot-link

## Plan

### Why
로그인 화면에서 비밀번호를 잊은 사용자가 복구 경로를 찾을 수 있는 진입점을 제공한다.
PRD §8 에서 "비밀번호 찾기" 기능 자체는 범위 밖이지만, 향후 task(실제 복구 페이지) 를 위한
UI 플레이스홀더 링크를 먼저 노출해 로그인 폼의 기대 동선을 완성한다.

### What
`/login` 페이지 하단(기존 회원가입 안내 영역)에 '비밀번호 찾기' 링크를 **추가**한다.
- 현재 로그인 페이지(`apps/web/app/login/page.tsx`)에는 `.form-footer` 안에
  `계정이 없으신가요? <Link href="/signup">회원가입</Link>` 만 존재한다.
- 여기에 동일한 `next/link` 패턴으로 `href="/forgot-password"` 링크를 한 줄 추가한다.
- 대상 페이지(`/forgot-password`)는 **이번 task 에서 만들지 않는다** (추후 별도 task).

### Scope
- 포함:
  - `apps/web/app/login/page.tsx` 에 '비밀번호 찾기' 링크(`href="/forgot-password"`) 추가.
  - 기존 `.form-footer` 영역 또는 그 바로 아래에, 기존 회원가입 링크 스타일과 일관되게 배치.
- 제외:
  - `/forgot-password` 라우트/페이지 구현 (추후 task). 링크 클릭 시 404(또는 Next 기본 미존재 처리)가 나는 것은 **의도된 상태**.
  - 백엔드 / DB / API 변경 일체 (user 명시: frontend-only).
  - 비밀번호 재설정 로직, 이메일 발송, 토큰 발급 등 (PRD §8 범위 밖).
  - 신규 디자인 토큰/컴포넌트 추가 (기존 `.form-footer` CSS 재사용).

### Acceptance
- [ ] `/login` 렌더 시 '비밀번호 찾기' 텍스트 링크가 화면에 보인다.
- [ ] 해당 링크의 `href` 가 정확히 `/forgot-password` 이다.
- [ ] 링크는 `next/link` 의 `<Link>` 로 구현되어 클라이언트 라우팅을 사용한다.
- [ ] 기존 '회원가입' 링크 및 로그인 폼 동작(제출/에러/성공 알림)이 회귀 없이 그대로 동작한다.
- [ ] 백엔드(`apps/api`)·DB·의존성에 어떤 변경도 없다 (frontend-only).
- [ ] `apps/web` 빌드/타입체크가 통과한다.

### Files touched (예상)
- `apps/web/app/login/page.tsx` — `.form-footer` 영역에 '비밀번호 찾기' `<Link href="/forgot-password">` 추가.
  (스타일 조정이 필요하면 해당 전역 CSS 의 `.form-footer` 규칙 재사용 — 신규 클래스는 지양.)

### 다음 역할 핸드오프 (frontend)
- 기존 코드가 이미 `import Link from 'next/link'` 를 포함하므로 추가 import 불필요.
- 기존 footer 마크업:
  `<p className="form-footer">계정이 없으신가요? <Link href="/signup">회원가입</Link></p>`
- 회원가입 링크와 비밀번호 찾기 링크를 한 영역에 자연스럽게 배치(예: 두 줄 또는 구분자).
  문구는 '비밀번호 찾기' 사용. `/forgot-password` 는 아직 미구현임을 코드 주석으로 남겨도 좋음(선택).

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
