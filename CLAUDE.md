# CLAUDE.md — 프로젝트 지침

## 프로젝트
간단한 게시판 (회원 + 게시판 모듈).
- 스펙: `PRD.md`
- 스택: Next.js(`apps/web`) + NestJS(`apps/api`) + MySQL 8, TypeORM, JWT(HttpOnly 쿠키), pnpm 모노레포, Docker Compose
- 로컬 전용 운영 (docker compose)

## 하네스 (Phase 4 L 기준)

이 리포는 **task-per-worktree + 7-role 하네스 + Orca orchestration** 으로 운영합니다.

- 전체 설계·운영 규칙: `.harness/WORKPLAN.md`, `.harness/COORDINATOR.md`
- 사용법·흐름: `.harness/README.md` + 이 문서 §Task 흐름
- 활성 상태 1-shot: `./scripts/harness-status.sh`
- 각 역할의 상세 지침: `.harness/roles/<role>.md`

### 역할 (worker 7 + coordinator 1)

| 역할 | 요약 |
|------|------|
| coordinator | Orca Run 바인딩 + worker 순차 spawn + check-wait 루프. 전용 claude agent 세션. 코드 안 씀. |
| planner | task 명세 + `required_roles` + agent 매핑 |
| architect | 설계 (엔티티/API 계약) |
| designer | Figma MCP + `apps/web` 코드 뼈대 (optional) |
| backend | `apps/api` 전체 + DB |
| frontend | `apps/web` 전체 |
| qa | docker up + UAT + 수용 기준 검증 |
| reviewer | 보안/누수/성능 리뷰 + user 승인 받고 rebase + ff-only merge |

### Task 흐름 (Phase 4 B)

```bash
./scripts/tasks.sh new <slug> "자연어 요구사항"
# → worktree + 브랜치 + task.md
# → orca orchestration run-create → run_id
# → coord-launch.sh 가 전용 Coordinator claude 세션 띄움
# → Coordinator 가 run-use + 첫 worker (planner) 자동 spawn
# → 체인 자동 진행 (planner → ... → reviewer → merge)
```

worker 는 `orca orchestration send --type worker_done` 호출로 완료 신호. Coordinator 가 받아 다음 role spawn. `tasks.sh advance` 는 **Phase 4 에서 제거됨** — Coordinator 가 자동 전환.

### 다른 명령

```bash
./scripts/tasks.sh list                 # 활성 task
./scripts/tasks.sh show <id>            # task.md 요약
./scripts/tasks.sh drop <id> --yes      # 폐기
./scripts/tasks.sh merge <id>           # reviewer 가 승인 받고 호출
./scripts/tasks.sh rework <id> <role>   # 지정 role 로 되돌림
./scripts/harness-status.sh             # 전체 1-shot (handles alive/dead + chat 등)
./scripts/coord-recover.sh <id>         # Coordinator crash 복구
./scripts/chat.sh view / tail <id>
./scripts/slack/relay.sh start / stop / status / install
```

### Slack (`@harness-bot`)

```
help / status / list                    # 조회
new <slug> <요구사항...>                 # task 생성 (tasks.sh new 와 동일)
drop T### --yes                         # 폐기
T### <명령>                              # Coordinator 세션에 주입 (merge, no, rework ...)
                                        # 활성 task 1개면 T### 생략 가능. 스레드 reply 로도 OK.
```

## 작업 인터럽트 규칙 (A → B)

- B가 긴급하지 않음 → Slack 또는 coord 에 요청 전달 → Inbox 캡처 → A 계속
- B가 긴급 → A의 task 파일에 **pause-note** 섹션 추가 → status `paused` → B 신규 task

상세는 `.harness/README.md`.

## 공통 작업 원칙

- **상태는 전부 파일**. `.harness/tasks/`, `.harness/chat/`, git 커밋이 single source of truth
- 커밋 메시지 접두어: `T### [agent]:` (예: `T001 [kiro]: add signup endpoint`)
- PRD.md 에 반하는 설계 변경은 planner 역할에서만, 사유를 커밋 메시지에 명시
- 운영 시크릿·`.env`·`.env.*` 커밋 금지
- 역할 경계를 넘지 않는다 (예: backend 는 `apps/web` 수정 금지)
- 범위 밖 리팩터·"개선"은 하지 않는다 (YAGNI)

## 멀티 에이전트 (Phase 4 B)

- 네이티브 (`orca orchestration worker-start --agent <id>` 지원): `claude, codex, cursor, antigravity, muse, zcode, opencode, opencode2`
- 비네이티브 (`orca agent launch` + preamble 주입): `kiro`
- 기본값: `.env` 의 `HARNESS_DEFAULT_AGENT` (예: `kiro`)
- task 생성 시 `--agent <name>` 로 override 가능
- 역할-에이전트 매핑은 planner 가 task.md 의 `required_roles[].agent` 로 결정
