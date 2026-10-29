# Harness

멀티 task · 멀티 에이전트 하네스. **Phase 4 S++ 기준** — Orca orchestration + 전용 Coordinator claude agent 세션.

전체 설계와 Phase 분할은 [`WORKPLAN.md`](./WORKPLAN.md), 운영 규칙은 [`COORDINATOR.md`](./COORDINATOR.md) 참조.

## 디렉토리

```
.harness/
├── README.md                 이 문서
├── WORKPLAN.md               설계 + Phase 1~5 기록 (historical)
├── COORDINATOR.md            Phase 4 B Coordinator 운영 규칙
├── AGENTS.md                 에이전트별 특성 (Phase 2 관찰 기반)
├── board.md                  활성 task 집계 (수동)
├── roles/                    role 지침 (planner / architect / designer / backend / frontend / qa / reviewer / coordinator)
├── templates/                task / pause-note / compose override
├── tasks/                    T###-<slug>.md (각 task 명세 + 역할별 섹션)
├── chat/                     T###.{jsonl, slack, handles, processed-dispatches, role-history.jsonl} (gitignore)
├── coord/                    relay.pid, relay.cursor, relay.log, bot_id.txt (gitignore)
└── archive/                  dropped/merged task 백업 (gitignore)
```

## Task 흐름 (Phase 4 B)

```
사용자: tasks.sh new <slug> "요구사항"  (또는 Slack @bot new ...)
         │
         ├─ worktree + 브랜치 + task.md 생성
         ├─ orca orchestration run-create → run_id
         └─ coord-launch.sh — 전용 Coordinator claude agent 세션 띄움
             │
             Coordinator (Auto-mode) 가 자율 수행:
             ├─ run-use --id $RUN_ID        # bind
             ├─ worker-start planner        # 첫 worker
             └─ loop: check --wait → coord-step.sh handle → 다음 worker-start
                       │
                       └─ worker_done 받으면 다음 required_role spawn
                       └─ question 받으면 Slack 포스트 (reviewer 승인 등)
                       └─ task-complete 받으면 메인 루프 종료
                       
chain: planner → [architect] → [designer] → [backend] → [frontend] → qa → reviewer → merge
         (planner 가 required_roles 로 필요한 role 만 선언)

사용자 개입: reviewer 승인 1회 — Slack 스레드에 "merge" (또는 Orca Coordinator 터미널에서)
```

## required_roles 는 planner 가 지정

task 생성 시 planner 가 **필요한 역할만** 선언. 예:
- UI 변경 없음 → `designer`, `frontend` 생략
- DB 변경 없음 → backend 는 보통 포함 (API 라우트)
- qa + reviewer 는 **항상 포함** (품질 게이트)

task.md 의 `required_roles` 가 소진되면 Coordinator 가 `task-complete` 받고 세션 종료.

## Task 상태 (frontmatter `status`)

| status | 의미 |
|--------|------|
| `planning` | planner 가 명세 중 |
| `in-flight` | 역할 중 하나가 작업 중 |
| `paused` | pause-note 작성됨, 다른 task 때문에 중단 |
| `merged` | main 에 반영 완료 |
| `dropped` | 폐기 |

역할 커서는 `current_role` 로 추적 — Coordinator 가 전환마다 갱신.

## Task ID / 포트 규칙

- 형식: `T001`, `T002`, ... (3자리 순차)
- 파일명: `T###-<kebab-slug>.md`
- 브랜치: `task/T###-<slug>`
- 워크트리: `.worktrees/T###-<slug>/`
- 커밋 메시지 접두어: `T### [agent]:` (예: `T001 [kiro]: add signup endpoint`)
- 포트: `WEB_PORT=3000+(N%100)*10`, `API_PORT=4000+(N%100)*10`, `DB_PORT=3306+(N%100)` — `.env` 와 compose override 로 스코프

## 주요 명령

**터미널**:
```bash
./scripts/tasks.sh new <slug> "요구사항"      # 신규 task + Coordinator 자동 띄움
./scripts/tasks.sh list                      # 활성 task
./scripts/tasks.sh show <id>                 # task.md 요약
./scripts/tasks.sh drop <id> --yes           # 폐기
./scripts/tasks.sh merge <id>                # reviewer 가 승인 받고 호출 (rebase + ff-only + cleanup)
./scripts/tasks.sh rework <id> <role>        # 지정 role 로 되돌림 + 재 spawn
./scripts/tasks.sh spawn <id> [role]         # 디버깅: role worker 수동 재시작

./scripts/harness-status.sh                  # 전체 상태 1-shot (handles alive/dead + 최근 chat)
./scripts/coord-recover.sh <id>              # Coordinator crash 복구
./scripts/chat.sh view <id> / tail <id>
./scripts/slack/relay.sh start / stop / status
./scripts/role.sh <role> [id]                # worker 세션 시작 시 컨텍스트 로드 (지침 + task.md + chat tail + PRD)
```

**Slack (`@harness-bot`)**:
```
help / status / list                         # 조회
new <slug> <요구사항...>                      # task 생성
drop T### --yes                              # 폐기
T### <명령>                                   # Coordinator 중계 (merge, no, rework, 자연어 지시)
                                             # 활성 task 1개면 T### 생략 OK
                                             # 스레드 reply 로 보내도 자동 인식
```

제거된 명령 (Phase 4 에서 제거):
- `tasks.sh advance` — Coordinator 가 자동 전환
- `scripts/coord.sh` — bash 데몬 (`.harness/archive/legacy/` 로 이동)

## Agent 매핑 (Phase 4 B)

task.md 의 `required_roles[].agent` 에서 role 별 agent 선언:

```yaml
required_roles:
  - { role: planner,   agent: kiro }
  - { role: backend,   agent: claude }
  - { role: frontend,  agent: kiro }
  - { role: qa,        agent: kiro }
  - { role: reviewer,  agent: claude }
```

지원:
- **네이티브** (`orca orchestration worker-start --agent <id>`): `claude, codex, cursor, antigravity, muse, zcode, opencode, opencode2`
- **비네이티브** (`orca agent launch` + preamble 주입): `kiro`

기본값: `.env` 의 `HARNESS_DEFAULT_AGENT` (예: `kiro`).

## A → B 인터럽트 규칙

**긴급하지 않음** → Slack 또는 coordinator 에 요청 → Inbox 캡처 (board.md 또는 자연스레 다음 task) → A 계속.

**긴급 (핫픽스 등)**:
1. 현재 task.md 에 `templates/pause-note.md` 양식으로 pause-note 섹션 추가 (마지막 SHA / 다음 스텝 / 블로커 / 재개 명령).
2. frontmatter `status: paused`.
3. `tasks.sh new <hotfix-slug>` 로 B 시작.
4. B 완료 후 A 재개 시 pause-note 참조.

## Chat 로그 타입

`request` | `dispatch` | `question` | `answer` | `report` | `deliver` | `handoff` | `error` | `note`

각 chat.sh append 는 jsonl 에 기록 + Slack 스레드에 자동 미러 (`.env` SLACK_* 설정 시).

## 공유 상태

| 자원 | 처리 |
|------|------|
| `.harness/board.md` | main 브랜치만 진실. task worktree 에서 수정 금지 |
| `.harness/tasks/T###.md` | task worktree 가 쓰기, Coordinator 가 current_role 갱신. merge 시 archive |
| `.harness/chat/T###.*` | main 에 없음 (.gitignore). drop/merge 시 jsonl/slack 은 archive, handles/cursor 는 삭제 |
| `PRD.md` | main 에만. 각 worktree 는 **읽기 전용 참조** |

## 재개 가능성

Coordinator 세션 crash 시:
```bash
./scripts/coord-recover.sh <task-id>
```
- task.md frontmatter 에서 `run_id` + `current_role` + `slug` 복구
- 기존 Coordinator 세션 close + `coord-launch.sh` 재호출
- `.harness/chat/<id>.processed-dispatches` 유지 → 재배포 메시지 idempotency 가드로 skip
