---
id: T027
title: 회원가입 페이지 이용약관 동의 체크박스
slug: signup-terms-check
branch: task/T027-signup-terms-check
worktree: .worktrees/T027-signup-terms-check
status: in-flight          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: kiro }
  - { role: architect,  agent: kiro }
  # - { role: designer,   agent: kiro, mcp: [figma] }  # 신규 비주얼 시스템 없음 — 기존 .field/.btn 스타일 재사용
  # - { role: backend,    agent: kiro }                # 프론트 전용 제출 게이트 — PRD §3.1 멤버 모델/§5.1 signup 계약 변경 없음 (YAGNI)
  - { role: frontend,   agent: kiro }
  - { role: qa,         agent: kiro }
  - { role: reviewer,   agent: kiro }
current_role: frontend
role_history: []
run_id: run_121330acb86b
ports:
  web: 3270
  api: 4270
  db: 3333
compose_project: harness_t027
figma_url: null
blocked_by: []
related_prd: ["3.2 F-M1 회원가입"]
priority: normal          # high | normal | low
created_at: 2026-10-27
updated_at: 2026-10-27
---

## User Request

> 회원가입 폼에 '이용약관 동의' 체크박스 추가. 미체크 상태로 제출 불가. UX / 검증 범위는 planner 재량.

---

_(T027 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_


# T027 — signup-terms-check

## Plan

### Why
- 회원가입 시 이용약관 동의는 서비스 운영의 기본 전제(법적·정책적)이다. 현재 `signup` 폼에는 동의 절차가 전혀 없어 사용자가 약관을 인지·동의한 기록 없이 가입된다.
- 요구: "미체크 상태로 제출 불가" — 즉 **명시적 동의 게이트**를 제출 흐름에 삽입한다.

### What
- 메인 회원가입 폼(`apps/web/app/signup/page.tsx`)에 **'이용약관 동의' 체크박스** 1개를 추가한다.
- 체크박스가 **미체크면 '가입하기' 버튼을 비활성화**(disabled)하여 제출 자체를 막는다. (1차 방어)
- 사용자가 버튼 활성화 전에도 상황을 알 수 있도록, 미동의 상태에 대한 **인라인 안내 문구**(예: "가입하려면 이용약관에 동의해야 합니다.")를 제공한다. (2차 — 접근성/명확성)
- 약관 '내용' 자체(전문 페이지/모달)는 범위 밖. 체크박스 라벨에 "이용약관에 동의합니다" 수준의 문구만 둔다. (약관 전문 페이지가 없으므로 링크는 걸지 않거나 비활성 placeholder — 아래 Open Questions 참조)

### Scope
- **포함**:
  - `signup` 페이지 폼에 체크박스 상태(`agreedToTerms: boolean`) 추가.
  - 미체크 시 submit 버튼 `disabled` + (시도 시) 인라인 에러 노출.
  - 체크박스 접근성: `<label htmlFor>` 연결, 키보드 포커스 가능, `aria-*` 적절히.
  - 기존 폼 레이아웃/스타일(`.field`, `.btn`, `.alert`) 재사용.
- **제외 (YAGNI)**:
  - 백엔드 변경 **없음**. `SignupDto`·`/auth/signup` 계약·멤버 DB 스키마(PRD §3.1)는 **불변**. 동의 여부를 서버에 전송/영속하지 않는다. (요구는 "제출 불가"까지이며, 동의 기록 영속은 별도 과제)
  - `join` 페이지(간편 가입, userId/password only)는 "회원가입 폼"의 대상이 아니므로 변경하지 않는다. (요구 원문은 nickname 포함 메인 signup 폼을 지칭)
  - 약관 전문 콘텐츠/별도 라우트/모달 미구현.
  - 동의 일시(consented_at) 기록, 약관 버전 관리 등 — 범위 밖.

### Acceptance
- [ ] `/signup` 진입 직후, '이용약관 동의' 체크박스가 폼에 렌더링되고 **기본 미체크** 상태다.
- [ ] 체크박스가 미체크인 동안 '가입하기' 제출 버튼이 `disabled` 이며 클릭/엔터로 제출(`api.signup` 호출)이 발생하지 않는다.
- [ ] 체크박스를 체크하면 제출 버튼이 활성화되고, 기존대로 가입이 진행되어 성공 시 `/login?signup=1` 로 이동한다.
- [ ] 체크했다가 다시 해제하면 제출 버튼이 다시 `disabled` 로 돌아간다.
- [ ] 체크박스에는 `<label>` 이 연결되어 있고, 라벨 텍스트 클릭으로도 토글되며, Tab 키로 포커스가 이동한다.
- [ ] 미동의 상태를 사용자에게 알리는 안내 문구가 표시된다(버튼 비활성 사유 명확).
- [ ] 백엔드 코드/DTO/스키마가 변경되지 않는다(이 task diff 에 `apps/api/` 변경 없음).
- [ ] 기존 기능 회귀 없음: userId/password/nickname 입력 및 가입 성공·실패(에러 alert) 흐름이 그대로 동작한다.

### Files touched (예상)
- `apps/web/app/signup/page.tsx` — 체크박스 상태/렌더/제출 게이트 추가 (프론트 전용).
- (선택) `apps/web/app/globals.css` 류 — 체크박스 전용 스타일이 필요하면 소폭 추가. 기본은 기존 `.field` 재사용으로 무변경 지향.

### Open Questions (architect/frontend 참고 — 차단 아님, 기본값 제시)
1. 약관 전문 링크: 전문 페이지가 없으므로 **링크 미노출**(단순 라벨)로 진행을 기본값으로 한다. 추후 약관 페이지 생기면 링크 연결.
2. 게이트 방식: 기본은 **버튼 disabled(1차) + 인라인 안내(2차)**. 추가로 submit 시도 시 에러 메시지까지 띄울지는 frontend 재량(접근성상 권장).

### required_roles 결정 근거
- 이 변경은 **프론트엔드 제출 게이트 1건**으로, DB/API 변경이 없다 → `backend`·`designer` 제외.
- `planner → architect(경량 상태/흐름 확인) → frontend → qa → reviewer` 체인으로 충분.

---

## Design

> **설계 범위**: 프론트엔드 전용 제출 게이트 1건. Plan 의 Scope 를 그대로 수용한다.
> 백엔드/DB/API 계약 **변경 없음** — 따라서 데이터 모델·API 계약·마이그레이션 섹션은 **해당 없음(N/A)**.
> 대상 파일: `apps/web/app/signup/page.tsx` (단일 컴포넌트), 필요 시 `apps/web/app/globals.css` 소폭.

### 데이터 모델
- **N/A** — 멤버 스키마(PRD §3.1) 불변. 동의 여부를 서버에 전송/영속하지 않는다.

### API 계약
- **N/A** — `/auth/signup` 계약(PRD §5.1) 불변. `api.signup({ userId, password, nickname })` 호출 페이로드는 기존 그대로. `agreedToTerms` 는 **클라이언트 로컬 상태로만** 존재하며 요청에 포함하지 않는다.

### 컴포넌트 상태 설계 (client component)
`SignupPage` 에 상태 1개 추가:

| 상태 | 타입 | 초기값 | 의미 |
|------|------|--------|------|
| `agreedToTerms` | `boolean` | `false` | 이용약관 동의 체크 여부 (기본 미체크) |

- 기존 상태(`userId`, `password`, `nickname`, `submitting`, `error`)는 변경 없음.
- **파생 값**(새 상태 아님): `canSubmit = agreedToTerms && !submitting`.
  - 제출 버튼 `disabled={!canSubmit}` → 미동의 또는 처리 중이면 비활성.
  - (frontend 재량) 추가로 입력값 공란 검사까지 묶어도 무방하나, Plan 수용 기준은 "동의 게이트"가 핵심이므로 **필수는 `agreedToTerms` 게이트**다.

### 마크업 / 접근성 계약
제출 버튼 바로 위, 마지막 `.field`(nickname) 다음에 체크박스 블록 삽입:

```
<div className="field field--checkbox">
  <input id="agreeTerms" type="checkbox"
         checked={agreedToTerms}
         onChange={(e) => setAgreedToTerms(e.target.checked)}
         disabled={submitting} />
  <label htmlFor="agreeTerms">이용약관에 동의합니다</label>
</div>
```

접근성/동작 계약 (QA 검증 대상):
- `<input id="agreeTerms">` ↔ `<label htmlFor="agreeTerms">` 연결 → **라벨 클릭으로 토글** 가능.
- 체크박스는 네이티브 `<input type="checkbox">` 사용 → **Tab 포커스·Space 토글** 기본 보장. 커스텀 div 토글 금지.
- 제출 버튼이 `disabled` 일 때 비활성 사유를 알리는 **인라인 안내 문구** 표시.
  - 기본: 미동의 시 체크박스 아래 `.field__hint` 로 "가입하려면 이용약관에 동의해야 합니다." 상시 노출(동의하면 숨김) — 가장 단순·명확.
  - (frontend 재량 2차) submit 시도 자체는 버튼 disabled 로 막히므로 `onSubmit` 진입 전 차단된다. 혹시 Enter 등으로 핸들러 진입 시를 대비해 `onSubmit` 최상단에 `if (!agreedToTerms) { setError('이용약관에 동의해주세요.'); return; }` 가드를 둘 수 있음(방어적, 선택).

### 흐름 (제출 게이트)
1. `/signup` 진입 → `agreedToTerms=false` → 버튼 `disabled`, 안내 문구 노출.
2. 사용자가 체크박스/라벨 클릭 or Space → `agreedToTerms=true` → 버튼 활성, 안내 문구 숨김.
3. '가입하기' 클릭 → 기존 `onSubmit` 그대로: `api.signup(...)` → 성공 시 `router.push('/login?signup=1')`, 실패 시 `.alert--error`.
4. 체크 해제 → `agreedToTerms=false` → 버튼 다시 `disabled`.

### 보안 / 에러
- **입력 검증 지점**: 클라이언트 제출 게이트(UX). 서버측 실질 검증은 기존 `/auth/signup` DTO(PRD §3.2 F-M1)가 담당 — 이번 변경과 무관.
- **민감정보 흐름**: 없음. 동의 플래그는 UI 로컬 상태일 뿐 서버/로그로 나가지 않음.
- **권한 체크**: N/A (비인증 공개 페이지).
- **주의**: 클라이언트 disabled 는 UX 게이트일 뿐 보안 경계가 아님. 그러나 "동의 기록 영속"은 Plan 에서 명시적 범위 밖이므로, 서버 강제 없음이 **의도된 설계**다. (향후 영속 필요 시 별도 task 로 `SignupDto.agreedToTerms` + 멤버 스키마 확장.)

### 마이그레이션
- **N/A** — DB 변경 없음.

### 테스트 포인트 (QA 참조)
- [ ] `/signup` 초기 렌더: 체크박스 존재 + **미체크** + 제출 버튼 `disabled`.
- [ ] 미동의 상태: 안내 문구("…동의해야 합니다") 노출, 버튼 클릭/Enter 로 `api.signup` 미호출(네트워크 요청 0건).
- [ ] 체크 → 버튼 활성 → 정상 가입 → `/login?signup=1` 이동.
- [ ] 체크 후 해제 → 버튼 다시 `disabled`.
- [ ] 라벨 텍스트 클릭으로 토글, Tab 포커스 이동, Space 토글.
- [ ] diff 에 `apps/api/` 변경 **없음** (백엔드 불변 회귀 확인).
- [ ] 기존 회귀: userId/password/nickname 입력 + 성공/실패(에러 alert) 흐름 유지.

### 다음 역할 핸드오프 (frontend)
- 수정 파일: `apps/web/app/signup/page.tsx` (단일). `api.signup` 페이로드 **건드리지 말 것**.
- 상태 1개 추가(`agreedToTerms`), 버튼 `disabled` 조건에 `!agreedToTerms` 결합, 네이티브 `<input type="checkbox">` + 연결 `<label>` 사용.
- CSS: 기존 `.field`/`.field__hint` 재사용. 체크박스+라벨 가로 정렬이 어색하면 `globals.css` 에 `.field--checkbox { display:flex; align-items:center; gap:8px; }` + `.field--checkbox label { margin-bottom:0; }` 정도만 소폭 추가(선택). 범위 밖 스타일 리팩터 금지.
- 약관 전문 링크: **미노출**(단순 라벨) — Plan Open Question 1 기본값 확정.

---

## Implementation (Frontend)

### 추가 라우트/페이지
- 신규 라우트 없음. 기존 `/signup` 페이지에 약관 동의 체크박스 추가.

### 변경 파일
- `apps/web/app/signup/page.tsx`
  - `agreedToTerms` state 추가 (기본 `false`).
  - 닉네임 필드와 제출 버튼 사이에 체크박스 필드 삽입 (`id=agreeTerms`).
  - 제출 버튼 `disabled={submitting || !agreedToTerms}` 로 게이트.
  - `onSubmit` 진입 시 `!agreedToTerms` 면 에러 세팅 후 early return (버튼 disabled 와 이중 방어).
- `apps/web/app/globals.css`
  - `.field--check`, `.checkbox`, `.checkbox input[type='checkbox']` 스타일 추가 (기존 디자인 토큰 사용).

### 새 환경변수
- 없음.

### 보안 자가 점검
- 사용자 입력은 React 기본 escape. `dangerouslySetInnerHTML` 미사용.
- 상태 변경 요청(POST /auth/signup)은 기존 `lib/api.ts` 가 `credentials: 'include'` + `X-CSRF-Token` 자동 처리(변경 없음).
- 약관 동의는 프런트 consent 게이트 (서버 계약 변경 없음).

### 로컬 재현 (브라우저 시나리오)
```bash
docker compose up        # 현재 worktree 포트 (web=3270)
```
1. `http://localhost:3270/signup` 접속.
2. 아이디/비밀번호/닉네임 입력 → "가입하기" 버튼이 **비활성화** 상태인지 확인(약관 미동의).
3. "이용약관에 동의합니다 (필수)" 체크박스 체크 → 버튼이 **활성화**되는지 확인.
4. 체크 해제 → 버튼 다시 비활성화 확인.
5. 체크 후 정상 값으로 "가입하기" → 기존대로 `/login?signup=1` 이동.
6. (이중 방어 확인) 체크박스를 끈 채로 Enter/제출 시도 시 "이용약관에 동의해야 가입할 수 있습니다." 에러 노출.

정적 검증(의존성 설치 후):
```bash
pnpm --filter web typecheck   # 통과
pnpm --filter web lint        # No ESLint warnings or errors
pnpm --filter web build       # /signup 컴파일 성공
```

### 수용 기준 자가 검증
- [x] 약관 체크박스 표시 — `/signup` 빌드 성공, 코드상 확인.
- [x] 미체크 시 버튼 비활성화 — `disabled={submitting || !agreedToTerms}`.
- [x] 체크 시 활성화 + 기존 플로우 유지.
- [x] 미동의 제출 차단 — `onSubmit` early return + 에러 메시지.
- [x] typecheck / lint / build 통과.

---

## QA report
<qa 작성>

---

## Review notes
<reviewer 작성>
