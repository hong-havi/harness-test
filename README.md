# harness-test

멀티 task · 멀티 에이전트 · 역할 state machine 기반 하네스로 운영하는 게시판 프로젝트.

- 제품 스펙: [`PRD.md`](./PRD.md)
- 프로젝트 지침: [`CLAUDE.md`](./CLAUDE.md)
- 하네스 전체 설계: [`.harness/WORKPLAN.md`](./.harness/WORKPLAN.md)
- 하네스 사용법: [`.harness/README.md`](./.harness/README.md)

## 스택

- Frontend: Next.js (App Router)
- Backend: NestJS + TypeORM
- DB: MySQL 8
- 인증: JWT (HttpOnly 쿠키)
- 모노레포: pnpm workspaces
- 로컬 실행: Docker Compose

## 디렉토리 구조

```
harness-test/
├── CLAUDE.md                  프로젝트 지침
├── PRD.md                     제품 요구사항
├── README.md                  이 문서
├── .gitignore
│
├── apps/                      Next.js(web) + NestJS(api) 모노레포
│   ├── web/
│   └── api/
│
├── scripts/
│   ├── tasks.sh               task 라이프사이클 (new/list/show/merge/drop/rework/spawn)
│   ├── role.sh                worker 세션 시작 시 컨텍스트 로드
│   ├── chat.sh                task별 채팅 로그 (JSONL + Slack 미러)
│   ├── coord-launch.sh        전용 Coordinator claude agent 세션 spawn
│   ├── coord-step.sh          Coordinator 가 받은 메시지 1건 처리
│   ├── coord-recover.sh       Coordinator crash 복구
│   ├── harness-status.sh      전체 상태 1-shot
│   ├── orca/
│   │   ├── setup.sh             1회성 external-worktree-visibility 설정
│   │   └── worker-start.sh      worker spawn (네이티브/비네이티브 분기)
│   ├── agents/
│   │   └── _bootstrap-prompt.sh  worker preamble 재료
│   └── slack/
│       ├── relay.sh             Slack → Coordinator 중계 데몬 (polling)
│       ├── relay-start.bat      Windows Task Scheduler wrapper
│       ├── send.sh              chat.postMessage (chat.sh 미러링)
│       ├── listen.sh            conversations.history polling
│       └── thread-replies.sh    conversations.replies polling
│
├── .harness/
│   ├── WORKPLAN.md            설계 + Phase 1~5 기록
│   ├── COORDINATOR.md         Phase 4 B Coordinator 운영 규칙
│   ├── README.md              하네스 상세 (이 레포 상단은 요약)
│   ├── AGENTS.md              에이전트별 특성
│   ├── board.md               활성 task 집계
│   ├── roles/                 role 지침 (worker 7 + coordinator)
│   ├── templates/             task.md / pause-note / compose override
│   ├── tasks/                 T###-<slug>.md
│   ├── chat/                  T###.{jsonl, slack, handles, processed-dispatches, role-history.jsonl} (gitignore)
│   ├── coord/                 relay.pid / relay.cursor / relay.log / bot_id.txt (gitignore)
│   └── archive/               dropped/merged 백업 (gitignore)
│
└── .worktrees/                task별 worktree (gitignore)
    └── T###-<slug>/
        ├── .env                           포트 스코프 환경변수
        ├── docker-compose.override.yml    자동 생성
        └── (apps/, pnpm 설치 등)
```

## 하네스 — 핵심 흐름 (Phase 4 B)

```
사용자: tasks.sh new <slug> "요구사항"  (또는 Slack @bot new ...)
         │
         ├─ worktree + 브랜치 + task.md 생성
         ├─ orca orchestration run-create → run_id
         └─ 전용 Coordinator claude agent 세션 spawn (coord-launch.sh)
             │
             Coordinator (Auto-mode) 가 자율 수행:
             ├─ orca orchestration run-use → bind
             ├─ orca/worker-start.sh → 첫 worker (planner) spawn
             └─ loop: check --wait → coord-step.sh handle → 다음 worker-start
                       │
                       ├─ worker_done 받으면 다음 required_role spawn
                       ├─ question 받으면 Slack 포스트 (reviewer 승인 등)
                       └─ task-complete 받으면 메인 루프 종료

chain: planner → [architect] → [designer] → [backend] → [frontend] → qa → reviewer → merge
        (planner 가 required_roles 로 필요한 role 만 선언)

사용자 개입: reviewer 승인 1회 — Slack 스레드에 "merge" (또는 Orca Coordinator 터미널 직접)
```

- 각 worker 는 **신규 agent 세션** 에서 실행 (컨텍스트 drift 방지)
- 모든 상태는 **파일에 영속**: `.harness/tasks/T###.md`, `.harness/chat/T###.*`, git 커밋
- 역할-에이전트 매핑(claude/codex/kiro)은 task.md 의 `required_roles` 에 선언
- Coordinator = 전용 **claude agent 세션** (bash 데몬 아님). Orca Run bind 가 세션 단위라 필수.

## 다른 PC 로 배포 (1-step 셋업)

```bash
git clone <repo-url>
cd harness-test
./scripts/setup.sh              # 의존성 체크 + .env 복사 + Orca 세팅 + pnpm install (대화형)
# 또는 전부 자동으로:
./scripts/setup.sh --yes

# 체크만 (설치 안 함):
./scripts/setup.sh --check-only
```

`setup.sh` 가 수행:
1. 필수 의존성 체크 (`git`, `bash`, `python`, `curl`, `orca` CLI, Windows 는 `cygpath`)
2. 선택 의존성 체크 (`pnpm`, `docker`)
3. `.env` 없으면 `.env.example` 복사 + 토큰 입력 안내 (`SLACK_BOT_TOKEN`, `SLACK_CHANNEL_ID`, `HARNESS_DEFAULT_AGENT`)
4. Orca external-worktree visibility 설정 (1회성)
5. `pnpm install` (apps 의존성)
6. (선택) Slack relay 자동 시작 등록

**Slack relay 데몬은 수동 등록 불필요** — `./scripts/tasks.sh new` 가 **자동 start** (이미 돌고 있으면 skip). Orca 꺼져있으면 Slack 응답 받아도 전달 불가하므로 상시 상주할 가치 없음. task 시작 시 보장되는 모델.

**상시 자동 시작 원하면 (선택)**:
```bash
./scripts/slack/relay.sh install    # Windows=Task Scheduler, macOS=launchd, Linux=systemd user
./scripts/slack/relay.sh uninstall  # 제거
```

**수동 제어**:
```bash
./scripts/slack/relay.sh start / stop / status
```

---

## 명령어 레퍼런스

### 최초 1회 (Orca 환경 세팅)

```bash
./scripts/orca/setup.sh                    # external worktree visibility: show
```

### Task 라이프사이클

```bash
./scripts/tasks.sh new <slug> "요구사항"   # worktree + 브랜치 + task.md + Coordinator 자동 띄움
./scripts/tasks.sh new <slug> --from <path>   # 긴 요구사항을 파일에서
./scripts/tasks.sh new <slug> --agent claude  # agent override (기본: .env HARNESS_DEFAULT_AGENT)
./scripts/tasks.sh list                       # 활성 task 테이블
./scripts/tasks.sh show [task-id]             # task 요약
./scripts/tasks.sh rework <id> <role>         # 지정 role 로 되돌림 + 재 spawn
./scripts/tasks.sh spawn [id] [role]          # 디버깅: worker 수동 재 spawn
./scripts/tasks.sh merge [id]                 # rebase + ff-only merge + cleanup (reviewer 호출)
./scripts/tasks.sh drop [id] --yes            # 폐기 (archive)
```

worktree 내부에서 실행하면 `task-id` 자동 감지.

**❌ Phase 4 에서 제거된 명령**:
- `tasks.sh advance` — Coordinator 가 worker_done 받으면 자동 전환하므로 불필요

### 상태 조회 / 복구

```bash
./scripts/harness-status.sh                # 전체 1-shot (handles alive/dead + 최근 chat + processed-dispatches)
./scripts/harness-status.sh --kill-orphans # handles 에 없는 harness 터미널 정리
./scripts/coord-recover.sh <id>            # Coordinator crash 복구 (run_id/current_role 재진입)
```

### Slack (`@harness-bot`)

```
help / status / list                       # 조회
new <slug> <요구사항...>                    # task 생성
drop T### --yes                            # 폐기
T### <명령>                                 # Coordinator 중계 (merge / no / rework / 자연어)
                                           # 활성 task 1개면 T### 생략 가능. 스레드 reply 로도 OK.
```

### Slack relay 데몬

```bash
./scripts/slack/relay.sh start / stop / status
./scripts/slack/relay.sh install           # (선택) OS 자동 시작 등록 — 보통 불필요, tasks.sh new 가 자동 start
```

### 역할 세션

```bash
./scripts/role.sh <role>                   # 역할 브리핑 + task + chat tail + PRD 로드
./scripts/role.sh <role> <task-id>         # 명시적 task 지정
```

유효 역할: `coordinator | planner | architect | designer | backend | frontend | qa | reviewer`

### 채팅 로그

```bash
./scripts/chat.sh append <task-id> <from> <to> <type> <message>
./scripts/chat.sh view <task-id>           # 사람이 읽기 좋게
./scripts/chat.sh tail <task-id>           # tail -f
./scripts/chat.sh raw  <task-id>           # 원본 JSONL
```

허용 `type`: `request` | `dispatch` | `question` | `answer` | `report` | `deliver` | `handoff` | `error` | `note`

## 사용 흐름 예시 (Phase 4 B — 자동 체인)

```bash
# 1) 신규 task 생성 (어디서든)
./scripts/tasks.sh new signup-api "회원가입 API: POST /auth/signup, DTO 검증, 비밀번호 해시"
#  → .worktrees/T001-signup-api/
#  → .harness/tasks/T001-signup-api.md
#  → orca orchestration run-create
#  → Orca UI 에 Coordinator claude 세션 뜸 (title: 🎯 Coordinator T001)
#  → relay 데몬 자동 start (nohup, 아직 안 돌면)
#  → Coordinator 가 자율 수행: run-use + planner(kiro) spawn + check-wait 루프

# 2) 체인 자동 진행 — 사용자 개입 불필요
# planner → architect → backend → qa → reviewer 가 Orca UI 에 순차적으로 뜸.
# 각 worker 는 role 지침대로 작업 + 커밋 + chat deliver + worker_done 호출.
# Coordinator 가 받고 다음 role spawn.

# 3) reviewer 승인 요청 — Slack 스레드에 "🔔 응답 필요" 자동 포스트
# 사용자가 Slack T001 스레드에서 "merge" 응답 → relay 가 받아 Coordinator 중계
# → reviewer kiro 가 tasks.sh merge 수행 → ff-only merge + archive.
# → Coordinator 가 task-complete 받고 세션 자동 종료.

# 중간 상태 조회
./scripts/harness-status.sh
# 또는 Slack: @bot status
```

## 작업 인터럽트 (A → B)

- 긴급하지 않음 → coordinator(또는 Slack `#harness-coord`)에 요청 전달. 다음 planner 사이클에서 승격.
- 긴급(핫픽스) → 현재 task.md 에 pause-note 섹션 추가 → `status: paused` → `tasks.sh new <hotfix-slug>` 로 B 착수.

상세는 [`.harness/README.md`](./.harness/README.md#a--b-인터럽트-규칙).

## 포트 할당 (task별)

task 번호 N 에 대해:
- `WEB_PORT = 3000 + (N % 100) * 10`
- `API_PORT = 4000 + (N % 100) * 10`
- `DB_PORT  = 3306 + (N % 100)`
- `COMPOSE_PROJECT_NAME = harness_t<padded>`

예: T001 → 3010/4010/3307, T002 → 3020/4020/3308

## Phase 로드맵

| Phase | 내용 | 상태 |
|-------|------|------|
| 1 | 코어 뼈대 (수동 작동) — 역할 파일, tasks/role/chat 스크립트 | ✅ 완료 |
| 2 | Orca 통합 + 에이전트 어댑터 (claude/codex/kiro) | ✅ 완료 |
| 3 | Slack + Coordinator 자동 dispatch 루프 (shell-based) | ✅ 완료 (fragile 발견) |
| 4 | **Orca orchestration 전환** (worker-start/check-wait) | 🚧 진행 중 |
| 5 | (선택) tmux 관측 레이어 | 예정 |

## 기본 Agent 교체 위치

Default agent 는 **3군데** 에서 설정 가능 (적용 우선순위: 아래 ↓):

| 위치 | 범위 | 예시 |
|------|------|------|
| **`.env`** `HARNESS_DEFAULT_AGENT=<name>` | 전역 기본값 | `kiro` 또는 `claude` |
| **`tasks.sh new --agent <name>`** / Slack `new <slug> --agent <name>` | 특정 task 만 override | `tasks.sh new signup --agent claude` |
| **`.harness/tasks/<id>-<slug>.md`** 의 `required_roles[].agent` | 특정 역할만 override (수동) | task 생성 후 편집 |

**지원 agent** (Phase 4):
- 네이티브 (orca orchestration worker-start --agent): `claude`, `codex`, `cursor`, `antigravity`, `muse`, `zcode`, `opencode`, `opencode2`
- 비네이티브 (experimental): `kiro` — `agent launch` + `terminal send` + `worker-start --terminal` 우회

상세는 [`.harness/WORKPLAN.md`](./.harness/WORKPLAN.md).

## 다른 PC에서 처음 셋업하기

이 하네스를 새 머신에 클론해서 바로 쓸 수 있도록 하는 단계별 가이드.

### 1. 사전 설치

| 필수 | 버전 | 비고 |
|------|------|------|
| **Git** | 2.40+ | Windows 는 **Git for Windows** (Git Bash 포함) |
| **Docker Desktop** | compose v2 | api/web/db 로컬 기동 |
| **Node.js** | 20 LTS | pnpm 설치/스크립트 실행에 필요 |
| **pnpm** | 8+ | `npm i -g pnpm` |
| **Python** | 3.9+ | Slack 어댑터 (JSON 파싱, UTF-8). `PYTHONUTF8=1` 지원 필요 |
| **Orca Desktop** | 최신 | agent spawn/terminal/worktree 통합. [orca.so](https://orca.so) |

| 선택 (agent 별) | 비고 |
|------|------|
| **Claude Code CLI** | Orca 가 `--agent claude` 로 spawn — Orca 가 자동 처리 |
| **Codex CLI** | 역할 중 codex 쓸 때 |
| **kiro-cli** | 역할 중 kiro 쓸 때. [kiro.dev/docs/cli/](https://kiro.dev/docs/cli/) |

### 2. 리포 클론 + 권한 설정

```bash
git clone https://github.com/hong-havi/harness-test.git
cd harness-test

# bash 스크립트 실행 권한 (Git Bash 는 chmod 가 의미 있음)
chmod +x scripts/*.sh scripts/orca/*.sh scripts/agents/*.sh scripts/slack/*.sh
```

### 3. `.env` 로컬 생성

`.env.example` 복사해서 값 채움. **`.env` 는 gitignore 됨, 커밋 금지**.

```bash
cp .env.example .env
```

필수 값:
- `JWT_SECRET` — 32 bytes 랜덤 문자열 (openssl rand -base64 32)
- `DB_PASSWORD` — DB 비밀번호
- `SLACK_BOT_TOKEN` + `SLACK_CHANNEL_ID` — Phase 3 Slack 통합용 (아래 §5)

### 4. Orca 환경 셋업 (1회성)

Orca 데스크톱 앱에서:
1. **File → Add Repo** 로 이 레포 폴더 등록
2. 아래 스크립트 실행:
```bash
./scripts/orca/setup.sh
```
→ external worktree visibility 를 `show` 로 설정. `.worktrees/` 안의 task worktree 들을 Orca 가 추적 가능.

### 5. Slack 봇 셋업 (Phase 3 — 선택이지만 권장)

Coordinator + 역할 간 통신에 Slack 사용. 미설정 시 chat log 는 로컬 JSONL 에만 쌓임.

#### 5-1. Slack App 생성
1. [api.slack.com/apps](https://api.slack.com/apps) → **Create New App → From scratch**
2. App 이름 (예: `harness-bot`) + Workspace 선택
3. **OAuth & Permissions → Bot Token Scopes** 추가:
   - `chat:write`
   - `channels:history`
   - `channels:read`
4. **Install to Workspace** → Bot User OAuth Token (`xoxb-...`) 복사

#### 5-2. 채널 준비
- 전용 채널 1개 생성 (예: `#harness-coord`)
- Channel Settings → **Integrations → Add apps** 에서 봇 추가 (또는 채널에서 `/invite @harness-bot`)
- Channel ID 복사 (채널 설정 하단 또는 About 에)

#### 5-3. `.env` 에 값 입력
```
SLACK_BOT_TOKEN=xoxb-...
SLACK_CHANNEL_ID=C0XXXXXXX
```

#### 5-4. 연결 테스트
```bash
./scripts/slack/send.sh --text "📄 harness 연결 테스트"
# → ts 숫자 출력되면 성공. Slack 채널 확인.
```

### 6. 첫 테스트 (하네스 동작 확인)

```bash
# 활성 task 없는지 확인 (clean state)
./scripts/tasks.sh list
# → (no active tasks)

# help 확인
./scripts/tasks.sh --help
```

### 7. Coordinator 세션 시작

```bash
./scripts/coord.sh start
# → PID lock 생성, Slack 폴링 시작 (5초 간격)
# Ctrl+C 로 종료, 또는 다른 터미널에서 ./scripts/coord.sh stop
```

이제 Slack 에서 `@harness-bot help` 쳐보면 봇이 응답.

### 8. 첫 task 생성 (end-to-end 검증)

```bash
# CLI 로
./scripts/tasks.sh new my-first-task "회원가입에 환영 토스트 추가"

# 또는 Slack 에서
# @harness-bot new my-first-task 회원가입에 환영 토스트 추가
```

Orca 창에 planner (claude) 세션이 자동 열림 → 자동 체인 (planner → architect → backend → ... → reviewer merge).

### 같은 Slack 봇을 다른 PC/다중 PC에서 쓸 때

Slack 토큰·채널은 **Slack 서버 자원**이라 PC 와 무관하게 공유 가능. `.env` 만 복사하면 됨.

| 자원 | 공유 가능 | 메모 |
|------|:--------:|------|
| `SLACK_BOT_TOKEN` | ✅ | 워크스페이스/앱 레벨 자격증명 |
| `SLACK_CHANNEL_ID` | ✅ | Slack 서버 영구 ID |
| 봇의 채널 멤버십 | ✅ | 재초대 불필요 |
| `.env` 파일 | ❌ (gitignore) | 안전한 경로(비밀번호 매니저/암호 메신저)로 수동 전달 |

**⚠ coord 는 1인 1실행 원칙**:
- PID lock 은 **로컬 PC 안에서만** 중복 방지
- 서로 다른 PC 에서 같은 토큰으로 coord 를 **동시에** 돌리면 Slack 메시지 중복 응답 + task 번호/worktree 충돌
- 한 사람이 PC 교체 시: 이전 PC 에서 `./scripts/coord.sh stop` → 새 PC 에서 start
- 두 사람이 각자 테스트 시: **별도 채널 + 별도 봇** 분리 권장 (또는 한 명만 coord 돌리고 다른 쪽은 Slack 명령 전송만)

### 셋업 문제 해결

| 증상 | 원인 | 조치 |
|------|------|------|
| `orca: command not found` | Orca 미설치 | Orca 데스크톱 설치, Terminal 재시작 |
| `cygpath: command not found` | Git Bash 밖 (WSL/pure Linux) | 스크립트가 자동 폴백. Windows 라면 Git Bash 사용 |
| Slack `not_in_channel` | 봇이 채널에 없음 | `/invite @<bot>` |
| Slack 한글 깨짐 | Python 버전 또는 locale | Python 3.9+ 확인. `python -c "import sys; print(sys.version)"` |
| `.worktrees` 삭제 실패 | Windows file lock (node_modules) | `cmd //c "rmdir /S /Q .worktrees\\<name>"` |
| agent spawn 실패 | task 브랜치가 main 보다 뒤 | worktree 안에서 `git rebase main` |

### 요구사항 요약 (설치만 체크)

- [x] Git (Git Bash on Windows)
- [x] Docker Desktop
- [x] Node 20 + pnpm 8+
- [x] Python 3.9+
- [x] Orca Desktop
- [ ] (선택) Codex CLI
- [ ] (선택) kiro-cli
- [ ] (선택) Slack workspace + bot
