---
id: T027
title: signup-terms-check
slug: signup-terms-check
branch: task/T027-signup-terms-check
worktree: .worktrees/T027-signup-terms-check
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: kiro }
  - { role: architect,  agent: kiro }
  # - { role: designer,   agent: kiro, mcp: [figma] }  # 신규 비주얼 시스템 없음 — 기존 .field/.btn 스타일 재사용
  # - { role: backend,    agent: kiro }                # 프론트 전용 제출 게이트 — PRD §3.1 멤버 모델/§5.1 signup 계약 변경 없음 (YAGNI)
  - { role: frontend,   agent: kiro }
  - { role: qa,         agent: kiro }
  - { role: reviewer,   agent: kiro }
current_role: planner
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
