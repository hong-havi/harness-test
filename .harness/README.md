# Harness

멀티 task · 멀티 에이전트 · 역할 state machine 기반 하네스.

전체 설계와 Phase 분할은 [`WORKPLAN.md`](./WORKPLAN.md) 참조.

## 디렉토리

```
.harness/
├── README.md                 이 문서
├── WORKPLAN.md               전체 설계 + Phase 체크리스트
├── AGENTS.md                 에이전트별 특성 + 역할별 추천 (Phase 2 관찰 기반)
├── board.md                  활성 task 집계 (수동 또는 tasks.sh list 참고)
├── roles/                    8개 역할 지침 (불변)
├── templates/                task / pause-note / compose override
├── tasks/                    T###-<slug>.md (각 task 명세+이력)
├── chat/                     T###.jsonl (각 task 채팅 로그, gitignore)
└── archive/                  dropped/merged task 백업 (gitignore)
```

## 역할 흐름

```
Inbox (coordinator 수신)
   │
   ▼
planner ─▶ architect ─▶ [designer] ─▶ backend ─▶ frontend ─▶ qa ─▶ reviewer ─▶ merged
                            └── required_roles 에 선언된 역할만 ──┘

(각 역할은 "신규 세션"에서 실행. 완료 시 세션 종료, 다음 역할은 fresh context로 spawn)
```

### required_roles 는 planner가 지정

task 생성 시 planner가 **필요한 역할만 선택**해서 task.md에 선언합니다.
- UI 변경 없음 → `designer`, `frontend` 생략 가능
- DB 변경 없음 → 그래도 backend는 보통 포함 (API 라우트)
- 리뷰·QA는 **항상 포함** (품질 게이트)

## Task 상태 (frontmatter `status`)

| status | 의미 |
|--------|------|
| `planning` | planner가 명세 중 |
| `in-flight` | 역할 중 하나가 작업 중 |
| `paused` | pause-note 작성됨, 다른 task 때문에 중단 |
| `merged` | main에 반영 완료 |
| `dropped` | 폐기 |

세부 역할 커서는 frontmatter의 `current_role` 로 추적.

## Task ID 규칙

- 형식: `T001`, `T002`, ... (3자리 순차)
- 파일명: `T###-<kebab-slug>.md`
- 브랜치: `task/T###-<slug>`
- 워크트리: `.worktrees/T###-<slug>/`
- 커밋 메시지 접두어: `T### [agent]:` (예: `T001 [claude]: add signup endpoint`)

## 포트 할당

task 번호 N에 대해:
- `WEB_PORT = 3000 + (N % 100) * 10`
- `API_PORT = 4000 + (N % 100) * 10`
- `DB_PORT  = 3306 + (N % 100)`
- `COMPOSE_PROJECT_NAME = harness_t<zero-padded>`

예: T001 → 3010/4010/3307, T002 → 3020/4020/3308

`.worktrees/T###-<slug>/.env` 와 `docker-compose.override.yml` 로 스코프됨.

## 명령어

### 최초 1회 (Orca 환경)

```bash
./scripts/orca/setup.sh                    # external-worktree-visibility: show
```

### Task 라이프사이클

```bash
./scripts/tasks.sh new <slug>              # worktree + 브랜치 + task.md + planner 자동 spawn
./scripts/tasks.sh new <slug> --no-spawn   # agent spawn 없이
./scripts/tasks.sh list                    # 활성 task 테이블
./scripts/tasks.sh advance [task-id]       # 다음 역할 + 자동 spawn
./scripts/tasks.sh advance [task-id] --no-spawn  # 커서만 이동
./scripts/tasks.sh spawn [task-id] [role]  # 현재/지정 역할 재 spawn (디버깅)
./scripts/tasks.sh merge [task-id]         # rebase + ff-only → main + cleanup
./scripts/tasks.sh drop [task-id]          # 폐기 (archive)
```

worktree 내부에서 실행하면 `task-id`를 자동 감지합니다.

### 에이전트 매핑

task.md 의 `required_roles` 에서 역할별 agent 를 선언:

```yaml
required_roles:
  - { role: planner,    agent: claude }
  - { role: architect,  agent: claude }
  - { role: backend,    agent: codex }      # 반복 구현은 codex
  - { role: qa,         agent: kiro }       # QA 는 kiro IDE 로
  - { role: reviewer,   agent: claude }     # 리뷰는 claude 추천
```

지원:
- **claude** / **codex** → `orca agent launch` (Orca 탭/채팅에서 열림)
- **kiro** → `kiro chat --new-window --mode agent` (Kiro IDE 새 창)

### 역할 세션

```bash
./scripts/role.sh <role>                   # 역할 브리핑 + task 컨텍스트 + chat tail + PRD
./scripts/role.sh <role> <task-id>         # 명시적 task 지정
```

### Chat 로그

```bash
./scripts/chat.sh append <task-id> <from> <to> <type> <message>
./scripts/chat.sh view <task-id>           # 사람이 읽기 좋게
./scripts/chat.sh tail <task-id>           # tail -f
```

허용 `type`: `request` | `dispatch` | `question` | `answer` | `report` | `deliver` | `handoff` | `error` | `note`

## A → B 인터럽트 규칙

### 긴급하지 않음 (기본)
1. coordinator 또는 Slack `#harness-coord`에 요청 전달.
2. coordinator가 Inbox로 캡처 (현재 Phase 1 수동 모드에서는 `board.md`의 Inbox 섹션에 한 줄 추가).
3. A는 계속.

### 긴급 (핫픽스 등)
1. 현재 task 파일에 `templates/pause-note.md` 양식으로 **pause-note** 섹션 추가.
   - 마지막 커밋 SHA, 어디까지 했는지, 다음 스텝, 블로커, 재개 명령.
2. task frontmatter의 `status` 를 `paused` 로 변경.
3. `tasks.sh new <hotfix-slug>` 로 B 신규 task 시작.
4. B 완료 후 A 재개 시 pause-note 참조.

### 규칙
- "지금 바로 할 게 아니면 **반드시** Inbox 또는 신규 task" — 머릿속에 두지 않는다.
- 긴급 판단이 애매하면 Inbox로.

## 역할 전환 체크리스트

세션을 시작할 때:
1. 올바른 worktree 디렉토리인지 확인 (`pwd`)
2. `./scripts/role.sh <role>` 실행
3. 출력된 지침·task.md·chat tail을 읽는다
4. 담당 범위 밖 파일은 수정하지 않는다 (각 `roles/*.md` 상단에 명시)
5. 완료 시 task.md의 해당 섹션 작성 → `./scripts/tasks.sh advance` → 세션 종료

## 공유 상태 처리

| 자원 | 처리 |
|------|------|
| `.harness/board.md` | **main 브랜치의 파일만 진실**. 각 task worktree에서는 수정 금지 (스크립트가 집계) |
| `.harness/tasks/T###.md` | main과 task worktree 양쪽에 있음. **task worktree가 쓰기 권한**. merge 시 반영 |
| `.harness/chat/T###.jsonl` | main 브랜치에는 두지 않음(.gitignore). 로컬 single source |
| `PRD.md` | main에만 있음. 각 worktree는 **읽기 전용 참조** |
