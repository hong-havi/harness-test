---
id: T021
title: 회원 로그아웃 버튼
slug: me-logout
branch: task/T021-me-logout
worktree: .worktrees/T021-me-logout
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: kiro }
  - { role: architect,  agent: kiro }
  - { role: backend,    agent: kiro }
  - { role: frontend,   agent: kiro }
  - { role: qa,         agent: kiro }
  - { role: reviewer,   agent: kiro }
current_role: planner
role_history: []
ports:
  web: 3210
  api: 4210
  db: 3327
compose_project: harness_t021
figma_url: null
blocked_by: []
related_prd: ["§3.2 F-M3 로그아웃", "§5.1 POST /auth/logout", "§3.3 JWT 정책", "§3.4 CSRF 대응"]
priority: normal          # high | normal | low
created_at: 2026-10-27
updated_at: 2026-10-27
---

## User Request

# 회원 로그아웃 버튼

로그인한 회원이 자신의 세션을 종료할 수 있는 로그아웃 버튼이 필요하다.

---

_(T021 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_


# T021 — 회원 로그아웃 버튼

## Plan

### Why
현재 시스템은 회원가입·로그인은 구현되어 있으나(F-M1/F-M2) 로그인한 회원이 능동적으로 세션을 끝낼 수단이 없다. 공용·공유 기기에서 자리를 뜰 때 다음 사용자가 그대로 로그인 상태를 물려받는 보안 위험이 있고, PRD §9 수용 기준의 "비회원이 가입 → 로그인 → 글 작성 → **로그아웃**까지 완주 가능" 플로우가 아직 미완결이다. 로그아웃 버튼은 이 플로우를 닫는 최소 기능이다.

### What
PRD §3.2 F-M3 와 §5.1 에 정의된 로그아웃을 UI + API 양쪽으로 완성한다.

1. **Backend** — `POST /auth/logout` 엔드포인트 구현:
   - 인증된 요청(JWT 쿠키 보유)에 대해 `access_token` 쿠키를 즉시 만료(`Set-Cookie: access_token=; Max-Age=0; Path=/; HttpOnly; SameSite=Lax` + 운영 시 `Secure`).
   - 로그인 시 함께 발급되는 `csrf_token` 쿠키도 동일하게 만료시켜 잔여 쿠키를 남기지 않는다.
   - 성공 시 2xx + 간단한 JSON 바디(`{ ok: true }` 수준) 반환. JWT 는 stateless 이므로 서버측 토큰 폐기/블랙리스트는 하지 않는다(범위 밖, 쿠키 제거만으로 브라우저 세션 종료).
2. **Frontend** — 로그인 상태에서 보이는 "로그아웃" 버튼:
   - 로그인한 회원에게만 노출(로그인 여부 판단은 기존 패턴 재사용).
   - 클릭 시 `POST /auth/logout` 호출(same-origin rewrites 경유, `credentials: 'include'`). 상태 변경 요청이므로 CSRF 토큰 정책(§3.4 Double Submit Cookie: `X-CSRF-Token` 헤더) 준수.
   - 성공 응답 후 클라이언트 로그인 상태를 비우고 로그인 또는 홈 화면으로 이동.

### Scope
- **포함**:
  - `apps/api` — `POST /auth/logout` 컨트롤러/서비스, `access_token`·`csrf_token` 쿠키 만료 로직, `AuthGuard('jwt')` 보호.
  - `apps/api` — unit test: 로그아웃 응답이 두 쿠키를 `Max-Age=0`(만료)로 설정하는지 검증.
  - `apps/web` — 로그아웃 버튼 컴포넌트/배치(로그인 시 노출), 클릭 핸들러(API 호출 + CSRF 헤더 + 상태 초기화 + 리다이렉트).
- **제외**:
  - 서버측 토큰 블랙리스트 / Refresh Token 폐기 (PRD §8, §3.3 — 범위 밖).
  - "모든 기기에서 로그아웃" 같은 멀티세션 종료.
  - 자동 유휴(idle) 타임아웃 로그아웃.
  - 로그아웃 확인 모달 등 UX 고도화 (단순 버튼 1개로 한정).
  - 로그아웃 버튼의 시각 디자인 고도화 — 기존 헤더/네비 스타일 재사용으로 충분(별도 designer 역할 불필요).

### Acceptance
- [ ] 로그인 상태에서 "로그아웃" 버튼이 화면에 노출된다. 비로그인 상태에서는 노출되지 않는다.
- [ ] 버튼 클릭 시 `POST /auth/logout` 이 호출되고 2xx 응답을 받는다.
- [ ] 응답의 `Set-Cookie` 로 `access_token` 쿠키가 만료된다(`Max-Age=0`). DevTools Application 탭에서 로그아웃 후 `access_token` 쿠키가 사라진 것을 확인.
- [ ] 로그아웃 시 `csrf_token` 쿠키도 함께 만료되어 남지 않는다.
- [ ] 로그아웃 후 보호 API(`GET /members/me`) 호출 시 401 이 반환된다(쿠키 제거로 더 이상 인증되지 않음).
- [ ] 로그아웃 후 클라이언트는 로그인(또는 홈) 화면으로 이동하고, 로그아웃 버튼 대신 로그인 진입점이 보인다.
- [ ] 쿠키 없이(비로그인) `POST /auth/logout` 호출 시 401 이 반환된다(JWT 보호 라우트).
- [ ] CSRF 토큰 누락 상태에서 로그아웃 요청 시 서버 정책(§3.4)에 따라 처리된다(토큰 요구 시 403, 또는 로그아웃은 멱등하므로 CSRF 예외로 둘지 architect 가 §3.4 범위에서 결정).
- [ ] 기존 로그인/회원정보 플로우에 회귀가 없다(관련 unit test 통과).

### Files touched (예상)
- `apps/api/src/auth/auth.controller.ts` — `POST /auth/logout` 핸들러 추가
- `apps/api/src/auth/auth.service.ts` — 쿠키 만료(clear) 헬퍼 (login 의 쿠키 설정 로직과 대칭)
- `apps/api/src/auth/*.spec.ts` — 로그아웃 쿠키 만료 unit test
- `apps/web/app/...` — 헤더/네비게이션 등 로그인 상태 영역에 로그아웃 버튼 추가
- `apps/web/...` — 로그아웃 호출 클라이언트 유틸(API 호출 + CSRF 헤더) 및 상태/리다이렉트 처리

### 다음 역할로의 핸드오프 (제약 / 참고)
- **architect**: §3.4 CSRF 정책과 로그아웃의 상호작용(CSRF 토큰 요구 여부)을 명시 결정하고 API 계약에 반영할 것. 쿠키 만료 속성은 login 시 설정한 속성과 **정확히 대칭**(동일 Path/SameSite/HttpOnly, Max-Age=0)이어야 브라우저가 쿠키를 지운다 — 불일치 시 쿠키가 남는 흔한 버그에 주의.
- **backend**: JWT stateless 특성상 "로그아웃 후에도 이미 발급된 토큰은 만료까지 유효"하다는 점은 PRD §3.2 F-M3 참고 범위 내이며, 추가 폐기 로직을 구현하지 말 것(YAGNI, 범위 밖).
- **frontend**: 로그인 여부 판단 및 상태 초기화는 기존 로그인/멤버 상태 관리 패턴을 재사용. 신규 전역 상태 라이브러리 도입 금지(YAGNI).
- **related_prd**: §3.2 F-M3(로그아웃), §5.1(`POST /auth/logout` JWT), §3.3(JWT 정책), §3.4(CSRF).

### Open questions (architect 가 설계 시 확정)
- Q1: 로그아웃은 멱등(idempotent)한 세션 종료이므로 CSRF 토큰을 **요구**할지, 예외로 둘지? (§3.4 는 상태변경 요청 전반에 CSRF 적용을 명시 → 기본은 요구 쪽이 일관적)
- Q2: 로그아웃 성공 후 리다이렉트 목적지는 `/login` 과 홈(`/`) 중 어디로? (기본값 제안: `/login`)

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
- 일자: YYYY-MM-DD
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
- 일자: YYYY-MM-DD
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
