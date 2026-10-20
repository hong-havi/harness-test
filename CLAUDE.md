# CLAUDE.md — 프로젝트 지침

## 프로젝트
간단한 게시판 (회원 + 게시판 모듈).
- 스펙: `PRD.md`
- 스택: Next.js(`apps/web`) + NestJS(`apps/api`) + MySQL 8, TypeORM, JWT(HttpOnly 쿠키), pnpm 모노레포, Docker Compose
- 로컬 전용 운영 (docker compose)

## 하네스 (중요)

이 리포는 **task-per-worktree + 8역할 하네스** 로 운영합니다.

- 전체 설계: `.harness/WORKPLAN.md`
- 사용법·흐름: `.harness/README.md`
- 활성 task 보드: `.harness/board.md`
- 각 역할의 상세 지침: `.harness/roles/<role>.md`

### 역할 (8개)

| 역할 | 요약 |
|------|------|
| coordinator | user의 유일한 접점. 역할 간 dispatch, 리포팅 |
| planner | task 명세 + `required_roles` 지정 |
| architect | 설계 (엔티티/API 계약) |
| designer | Figma MCP + `apps/web` 코드 뼈대 |
| backend | `apps/api` 전체 + DB |
| frontend | `apps/web` 전체 |
| qa | docker up + UAT |
| reviewer | 보안/누수/성능 리뷰 + rebase + ff-only merge |

### 어떤 작업이든 역할 설정부터

```bash
./scripts/role.sh <coordinator|planner|architect|designer|backend|frontend|qa|reviewer>
```

- 역할 설정 없이 코드/문서를 수정하지 않는다.
- 역할별 **경계**(수정 가능/금지 영역)는 `.harness/roles/<role>.md`에 명시.
- 각 역할은 **신규 세션**에서 수행. 긴 세션 재사용 금지 (컨텍스트 drift 방지).

### Task 생성 & 전환

```bash
./scripts/tasks.sh new <slug>          # task 생성 (worktree + 브랜치 + .env)
./scripts/tasks.sh list                # 활성 task 목록
./scripts/tasks.sh advance [task-id]   # 다음 required_role로 커서 이동
./scripts/tasks.sh merge [task-id]     # rebase + ff-only → main (reviewer가 호출)
```

### 채팅 로그

```bash
./scripts/chat.sh view <task-id>       # 사람이 읽기 좋게
./scripts/chat.sh append <task-id> <from> <to> <type> <message>
```

JSONL이 single source. Slack 미러는 Phase 3에서 추가.

## 작업 인터럽트 규칙 (A → B)

- B가 긴급하지 않음 → coordinator(또는 Slack `#harness-coord`)에 요청 전달 → coordinator가 Inbox에 캡처 → A 계속
- B가 긴급 → A의 task 파일에 **pause-note** 섹션 추가 (`.harness/templates/pause-note.md` 참조) → status `paused` → B 신규 task로 착수

상세는 `.harness/README.md`.

## 공통 작업 원칙

- **상태는 전부 파일**. `.harness/tasks/`, `.harness/chat/`, git 커밋이 single source of truth
- 커밋 메시지 접두어: `T### [agent]:` (예: `T001 [claude]: add signup endpoint`)
- PRD.md에 반하는 설계 변경은 planner 역할에서만, 사유를 커밋 메시지에 명시
- 운영 시크릿·`.env`·`.env.*` 커밋 금지
- 역할 경계를 넘지 않는다 (예: backend는 `apps/web` 수정 금지)
- 범위 밖 리팩터·"개선"은 하지 않는다 (YAGNI)

## 멀티 에이전트

역할-에이전트 매핑은 각 task의 `required_roles[].agent` 필드에 선언합니다 (claude / codex / kiro / gpt 등). Phase 1에서는 수동 세션으로 실행하며, Phase 2에서 Orca로 자동 spawn 통합 예정.
