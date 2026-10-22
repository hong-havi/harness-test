# 로그인 "로그인 상태 유지" 체크박스

## 배경 (Why)
현재 로그인은 쿠키 1시간 만료라 자주 재로그인해야 함. 체크박스로 **유지 기간 선택** 할 수 있게 하면 신뢰 기기에서는 편의성, 공용 기기에서는 보안이 모두 가능.

## 요구사항 (What)
`/login` 페이지 폼에 "로그인 상태 유지" 체크박스 추가:
- 체크 → 쿠키 7일 유지 (`Max-Age=604800`)
- 미체크 → 세션 쿠키 (`Max-Age` 생략, 브라우저 종료 시 만료)
- 기본 미체크

## 범위 (Scope)
- **포함**:
  - `apps/web/app/login/page.tsx` 체크박스 UI 추가
  - `apps/api` 로그인 DTO 에 `rememberMe: boolean` optional 필드
  - 로그인 성공 시 쿠키 `Max-Age` 를 조건부 설정
  - unit test: rememberMe=true/false 각각 쿠키 속성 검증
- **제외**:
  - "Remember my email" 같은 다른 저장 기능
  - 모바일 전용 처리
  - "자동 로그인" (biometric 등)

## 수용 기준 (예상)
- [ ] `/login` 체크박스가 보이고 기본 미체크
- [ ] 체크 후 로그인 → 쿠키 `Max-Age=604800` 로 설정됨 (DevTools 확인)
- [ ] 미체크 후 로그인 → `Max-Age` 없음 (session cookie)
- [ ] API 로그인 DTO 가 `rememberMe` 받고 class-validator 검증 통과
- [ ] 기존 로그인 플로우 회귀 없음 (unit test + e2e)

## 제약 / 참고
- PRD §3.3 (JWT 1시간 → 지금 유지 기간 변경 가능하다는 전제)
- 쿠키 속성: HttpOnly·Secure(운영)·SameSite=Lax 유지
- JWT 자체 만료는 그대로 (쿠키 Max-Age 만 조정 — 토큰은 1시간, 쿠키는 7일 보유 중일 수 있음)
  → 실제 세션 유효성은 서버 재발급 로직에 의존 (지금은 미구현. 명시 결정 필요)

## Open questions
- Q1: JWT 자체 만료를 7일로 늘릴지, 아니면 쿠키만 7일 유지하고 만료된 토큰은 재로그인 유도할지?
- Q2: 체크박스 default 값은 **미체크**로 OK?
- Q3: 체크했는데 쿠키가 하루 뒤에 토큰 만료 → 재로그인 시에도 자동 "체크" 유지?
