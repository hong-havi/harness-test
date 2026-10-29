# AGENTS.md — 프로젝트 지침

## 프로젝트
- 간단한 게시판 (회원 + 게시판 모듈). 상세 스펙은 `PRD.md`.
- 스택: Next.js (apps/web) + NestJS (apps/api) + MySQL, TypeORM, JWT(HttpOnly 쿠키), pnpm 모노레포, Docker Compose.

## 하네스 (Phase 4 S++ 기준)

**이 리포는 Orca orchestration 기반 멀티-에이전트 하네스로 운영됩니다.** 자세한 운영 규칙·명령어·역할 지침은 다음 문서를 참조하세요:

- `CLAUDE.md` — 역할 / Task 흐름 / 명령어 / Slack 명령 (가장 간결)
- `.harness/WORKPLAN.md` — 전체 설계 + Phase 1~5 기록
- `.harness/COORDINATOR.md` — Coordinator 운영 규칙 (Phase 4 B)
- `.harness/roles/<role>.md` — 각 role 상세 지침
- `./scripts/harness-status.sh` — 상태 1-shot

## 핵심 원칙

- Task 시작은 `./scripts/tasks.sh new <slug> "요구사항"` 또는 Slack `@harness-bot new <slug> <요구사항>`
- Coordinator (전용 claude agent) 가 자동으로 planner → ... → reviewer → merge 체인 수행
- 사용자 개입은 reviewer 승인 시점 1회가 전부 (Slack 스레드에서 `merge` 응답)
- 모든 상태는 파일 (`.harness/tasks/`, `.harness/chat/`, git 커밋)
- 커밋 메시지 접두어: `T### [agent]:` (예: `T001 [kiro]: add signup endpoint`)
- 역할 경계 지키기 — role.md 상단 참조
- 범위 밖 리팩터·"개선" 금지 (YAGNI)
- 운영 시크릿·`.env`·`.env.*` 커밋 금지
