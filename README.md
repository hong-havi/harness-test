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
│   ├── tasks.sh               task 라이프사이클 (new/list/advance/merge/drop)
│   ├── role.sh                역할 세션 진입점
│   └── chat.sh                task별 채팅 로그 (JSONL)
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

### Task 라이프사이클

```bash
./scripts/tasks.sh new <slug>              # 신규 task (worktree + 브랜치 + task.md 생성)
./scripts/tasks.sh list                    # 활성 task 테이블
./scripts/tasks.sh show [task-id]          # task 요약
./scripts/tasks.sh advance [task-id]       # current_role → 다음 required_role
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
| 2 | Orca 통합 + 에이전트 어댑터 (claude/codex/kiro) | 예정 |
| 3 | Slack + Coordinator 자동 dispatch 루프 | 예정 |
| 4 | (선택) tmux 관측 레이어 | 예정 |

상세는 [`.harness/WORKPLAN.md`](./.harness/WORKPLAN.md).

## 요구사항

- Git for Windows (Git Bash) 또는 bash 가능한 Unix 환경
- Docker Desktop (compose v2)
- pnpm (apps/ 작업 시 — Phase 2 이후)
- Node 20 (Phase 2 이후)
