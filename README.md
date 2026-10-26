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
├── apps/                      (Phase 2 이후 생성 예정)
│   ├── web/                   Next.js
│   └── api/                   NestJS
│
├── scripts/
│   ├── tasks.sh               task 라이프사이클 (new/list/advance/merge/drop/spawn)
│   ├── role.sh                역할 세션 진입점
│   ├── chat.sh                task별 채팅 로그 (JSONL)
│   ├── orca/
│   │   ├── setup.sh             1회성 external-worktree-visibility 설정
│   │   └── spawn.sh             task.md agent 매핑 → 어댑터 호출
│   └── agents/
│       ├── _bootstrap-prompt.sh  공통 역할 부트스트랩 프롬프트
│       ├── claude.sh             orca agent launch --agent claude
│       ├── codex.sh              orca agent launch --agent codex
│       └── kiro.sh               kiro chat --new-window --mode agent
│
├── .harness/
│   ├── WORKPLAN.md            전체 설계 + Phase 체크리스트
│   ├── README.md              하네스 사용 가이드
│   ├── board.md               활성 task 집계
│   ├── roles/                 8개 역할 지침
│   │   ├── coordinator.md       user의 유일한 접점, dispatch
│   │   ├── planner.md           task 명세 + required_roles 지정
│   │   ├── architect.md         설계 (엔티티/API 계약)
│   │   ├── designer.md          Figma MCP + apps/web 코드 뼈대
│   │   ├── backend.md           apps/api 구현 (DB 포함)
│   │   ├── frontend.md          apps/web 구현
│   │   ├── qa.md                docker up + UAT
│   │   └── reviewer.md          보안/누수/성능 리뷰 + rebase + ff-only merge
│   ├── templates/
│   │   ├── task.md                            task 파일 템플릿
│   │   ├── pause-note.md                      긴급 인터럽트 핸드오프
│   │   └── docker-compose.override.yml.tmpl   task별 포트 스코프
│   ├── tasks/                 T###-<slug>.md (각 task 명세+이력)
│   ├── chat/                  T###.jsonl (각 task 채팅, gitignore)
│   └── archive/               폐기된 task 백업 (gitignore)
│
└── .worktrees/                task별 worktree (gitignore)
    └── T###-<slug>/
        ├── .env                           포트 스코프 환경변수
        ├── docker-compose.override.yml    자동 생성
        └── (apps/, pnpm 설치 등)
```

## 하네스 — 핵심 흐름

```
User
 │  (Slack #harness-coord — Phase 3 예정)
 ▼
Coordinator          user의 유일한 접점. dispatch, 리포팅.
 │
 ▼
Per-task worktree    task마다 .worktrees/T###-<slug>/ (브랜치: task/T###-<slug>)
 │                   포트 스코프: WEB=3000+N*10, API=4000+N*10, DB=3306+N
 │
 ├─ planner       →  task.md 명세 + required_roles 선언
 ├─ architect     →  설계 (엔티티/API)
 ├─ designer      →  Figma + apps/web 뼈대 (필요 시)
 ├─ backend       →  apps/api 구현
 ├─ frontend      →  apps/web 구현 (필요 시)
 ├─ qa            →  docker up + UAT
 └─ reviewer      →  rebase + ff-only merge → main
```

- 각 역할은 **신규 세션**에서 실행 (컨텍스트 drift 방지)
- 모든 상태는 **파일에 영속**: `.harness/tasks/T###.md`, `.harness/chat/T###.jsonl`, git 커밋
- 역할-에이전트 매핑(claude/codex/kiro 등)은 task.md에 선언. Phase 2에서 자동 spawn (Orca).

## 명령어 레퍼런스

### 최초 1회 (Orca 환경 세팅)

```bash
./scripts/orca/setup.sh                    # external worktree visibility: show
```

### Task 라이프사이클

```bash
./scripts/tasks.sh new <slug>              # worktree + 브랜치 + task.md 생성 + planner 자동 spawn
./scripts/tasks.sh new <slug> --no-spawn   # agent spawn 없이 (Phase 1 수동 모드)
./scripts/tasks.sh list                    # 활성 task 테이블
./scripts/tasks.sh show [task-id]          # task 요약
./scripts/tasks.sh advance [task-id]       # 다음 역할로 커서 이동 + 다음 agent spawn
./scripts/tasks.sh advance [task-id] --no-spawn  # 커서만 이동
./scripts/tasks.sh spawn [task-id] [role]  # 현재/지정 역할 agent 재 spawn (디버깅)
./scripts/tasks.sh merge [task-id]         # rebase main + ff-only merge + cleanup
./scripts/tasks.sh drop [task-id]          # 폐기 (archive 로)
```

worktree 내부에서 실행하면 `task-id` 자동 감지.

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

## 사용 흐름 예시

```bash
# 1) 신규 task 생성 (main 에서)
./scripts/tasks.sh new signup-api
#  → .worktrees/T001-signup-api/
#  → task/T001-signup-api 브랜치
#  → .harness/tasks/T001-signup-api.md
#  → .env (WEB_PORT=3010, API_PORT=4010, DB_PORT=3307)

# 2) worktree 로 이동 + planner 세션
cd .worktrees/T001-signup-api
../../scripts/role.sh planner
#   → 역할 지침 + task.md + PRD 로드
#   → planner 가 task.md 의 Plan 섹션 + required_roles 작성
#   → 커밋

# 3) 다음 역할로
../../scripts/tasks.sh advance
#  → current_role: planner → architect

../../scripts/role.sh architect
#  → architect 세션 (fresh context, task.md 전체 참조)

# 4) 각 역할 반복 ... → reviewer 가 최종 병합
../../scripts/tasks.sh merge
#  → git rebase main
#  → git merge --ff-only
#  → worktree + 브랜치 정리
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
