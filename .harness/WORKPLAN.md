# Harness Build Plan

하네스 재구축 계획 문서. 중단되어도 이 문서만 읽으면 이어 짓도록 작성.

---

## 1. 결정된 설계 전제

| 영역 | 결정 |
|------|------|
| 프로젝트 | Next.js(apps/web) + NestJS(apps/api) + MySQL, pnpm 모노레포, Docker Compose (상세는 `PRD.md`) |
| 격리 단위 | **task-per-worktree** — `.worktrees/T###-<slug>/` (리포 내, gitignore) |
| 브랜치 | `task/T###-<slug>`, main으로 **rebase + ff-only** 병합 (reviewer 담당) |
| 역할 수 | 8개 — coordinator, planner, architect, designer, backend, frontend, qa, reviewer |
| 역할 흐름 | planner → architect → [designer?] → backend → frontend → qa → reviewer<br>required_roles는 task 생성 시 planner가 선언 |
| 세션 수명 | **역할당 신규 세션** — 세션 짧게/파일 길게. 모든 상태는 파일(task.md, chat log, 커밋)로 영속 |
| 멀티 에이전트 | 어댑터 패턴 — `scripts/agents/{claude,codex,kiro}.sh`. 역할-에이전트 매핑은 task.md에 선언 |
| 오케스트레이션 | **Orca 풀 통합** — worktree, agent spawn, 핸드오프, 터미널. 상위 인터페이스는 우리 스크립트 유지 |
| 코디네이터 | 전용 역할(별도 세션/창). user의 유일한 접점. agent 자동 dispatch. |
| 채팅 | **Slack + 로컬 JSONL 미러 어댑터**. 평상시 Slack, 로컬은 백업/네트워크 폴백 |
| 디자이너 | Figma MCP 호출로 Figma 디자인 + `apps/web` 코드 뼈대 함께 커밋 |

---

## 2. 역할 책임 요약

| 역할 | 할 수 있는 것 | 금지 |
|------|---------------|------|
| coordinator | user 입력 수신·dispatch·리포팅, task 상태 추적 | 코드/문서 직접 작성 |
| planner | task 명세, `required_roles` 지정, PRD 반영 | 코드 수정 |
| architect | 설계 문서, 엔티티/API 계약 초안 | 구현 코드 |
| designer | Figma 생성/업데이트, `apps/web` 컴포넌트 뼈대 + design tokens | 비즈니스 로직 |
| backend | `apps/api` 전체 + 마이그레이션 + DB | `apps/web`, 범위 외 리팩터 |
| frontend | `apps/web` 전체, 쿠키/CSRF/XSS 검증 | `apps/api`, DB 접근 |
| qa | docker up + UAT, 수용 기준 검증 | 코드 수정 |
| reviewer | 보안/성능/누수 리뷰, main과 rebase, ff-only 병합 | 범위 외 리팩터 |

---

## 3. 전체 아키텍처

```
User → Slack (#harness-coord)
         │
         ▼
      Coordinator (장기, Orca 관리)
         │  scripts/tasks.sh, scripts/coord.sh
         ▼
      Orca Layer
         │  worktree + spawn + 핸드오프
         ▼
      Per-task 작업 공간
         .worktrees/T###-<slug>/
         브랜치: task/T###-<slug>
         포트: WEB=3000+N*10, API=4000+N*10, DB=3306+N
         docker-compose project: harness_t###
         │
         ├─ spawn planner    (claude)          [세션 종료]
         ├─ spawn architect  (claude)          [세션 종료]
         ├─ spawn designer   (claude+figma)    [세션 종료]
         ├─ spawn backend    (claude|codex)    [세션 종료]
         ├─ spawn frontend   (claude)          [세션 종료]
         ├─ spawn qa         (claude|kiro)     [세션 종료]
         └─ spawn reviewer   (claude)          → rebase + ff-only → main → cleanup
         │
         ▼
      공유 상태 (파일)
         .harness/tasks/T###.md    역할별 섹션 누적
         .harness/chat/T###.jsonl  JSONL ⇄ Slack 미러
         .harness/board.md         main 브랜치 집계
         git branches, commits
```

### 핵심 흐름

1. **신규 task**: user → coordinator → `tasks.sh new <slug>` → worktree/브랜치/.env/compose override 생성 → planner spawn
2. **역할 전환**: 현재 역할 완료 → `tasks.sh advance` → task.md의 `required_roles` 다음 항목으로 커서 이동 → 해당 agent spawn (fresh context)
3. **최종 병합**: reviewer가 체크리스트 수행 → `git rebase main` → 충돌 시 coordinator에 에스컬레이션 → `git merge --ff-only` → worktree 정리

---

## 4. Phase 분할

### Phase 1 — 코어 뼈대 (standalone 수동 작동)

**목표**: user가 수동으로 각 역할 세션을 열어 하네스를 돌릴 수 있다. Orca/Slack 미통합 상태에서도 전체 흐름이 완결된다.

파일/스크립트:
- [x] `.harness/WORKPLAN.md` (이 문서)
- [x] `CLAUDE.md` 재작성
- [x] `.harness/README.md` (전체 흐름/인터럽트 규칙/상태 전이)
- [x] `.harness/board.md` (멀티 task 집계)
- [x] `.harness/roles/*.md` 8개 (coordinator + 7)
- [x] `.harness/templates/task.md` (required_roles, agent 매핑, figma_url, role_history)
- [x] `.harness/templates/pause-note.md`
- [x] `.harness/templates/docker-compose.override.yml.tmpl`
- [x] `scripts/tasks.sh` (new/list/advance/merge/drop)
- [x] `scripts/role.sh` (현재 task 자동 감지 + 역할 브리핑)
- [x] `scripts/chat.sh` (JSONL append/view/tail)
- [x] `.gitignore` 갱신

**검증(완료 기준)**:
- `./scripts/tasks.sh new signup-api` 로 worktree/브랜치/task 파일/compose override가 모두 생성됨
- 생성된 worktree에서 `./scripts/role.sh planner` 가 역할 브리핑 + task 파일 + chat tail + PRD를 출력
- `./scripts/chat.sh append T001 user coordinator request "회원가입"` 후 `./scripts/chat.sh view T001` 가 정상 렌더
- `./scripts/tasks.sh list` 가 모든 활성 task를 테이블로 표시
- `./scripts/tasks.sh advance T001` 가 current_role 커서를 이동
- `./scripts/tasks.sh merge T001` 가 main에 rebase+ff-only로 반영하고 worktree를 정리

### Phase 2 — Orca 통합 + 에이전트 어댑터

**방침 (조정)**: 설계 조사 결과, `orca worktree create` 는 **경로 지정이 불가**해 `.worktrees/` 를 레포 내부에 유지하는 요건과 양립 불가. 따라서 **하이브리드**:
- worktree 생성/제거는 **git worktree** 유지 (Phase 1 그대로)
- `orca repo set --external-worktree-visibility show` 로 git worktree 를 Orca 가 보도록 노출
- agent spawn 은 `orca agent launch --worktree path:<abs>` 로 수행 (claude/codex)
- **kiro** 는 Orca native 가 아니므로 `kiro chat --new-window --mode agent "<prompt>"` 로 직접 호출 (Kiro IDE 창 열림)

파일:
- [x] `scripts/orca/setup.sh` — 1회성 external-worktree-visibility 설정
- [x] `scripts/orca/spawn.sh` — task.md 의 agent 매핑 읽어 어댑터 호출
- [x] `scripts/agents/_bootstrap-prompt.sh` — 공통 역할 부트스트랩 프롬프트 생성
- [x] `scripts/agents/claude.sh` — orca agent launch --agent claude
- [x] `scripts/agents/codex.sh` — orca agent launch --agent codex
- [x] `scripts/agents/kiro.sh` — kiro chat --new-window --mode agent

tasks.sh 변경:
- [x] `new <slug>` 끝에 planner 자동 spawn (`--no-spawn` 지원)
- [x] `advance` 끝에 다음 역할 자동 spawn (`--no-spawn` 지원)
- [x] `spawn [task-id] [role]` 서브커맨드 추가 (디버깅)

**검증**:
- [x] 스크립트 syntax OK (bash -n 통과)
- [x] `scripts/orca/setup.sh` 가 external-worktree-visibility 를 성공 설정
- [x] `tasks.sh new <slug>` → spawn 디스패처가 claude 어댑터 호출 명령을 올바르게 구성 (DRY_RUN 검증)
- [x] 역할 완료 후 `tasks.sh advance` → 다음 agent (configured per role) spawn 호출 체인 OK
- [x] agent 매핑 변경 시(backend→codex, qa→kiro) 올바른 어댑터가 선택됨 (DRY_RUN 검증)
- [ ] 실제 agent 세션에서 end-to-end 돌림 (user가 수행 예정)

### Phase 3 — Slack + Coordinator + orchestration 통합

**목표**: user가 Slack 채널에서만 상호작용. Coordinator 세션이 orca orchestration primitives 로 role worker 를 supervised 하게 운영.

#### 3.1 Coordinator 세션 모델

- **별도 Orca 터미널 1개** (user가 attach 하는 창). 장기 실행 claude 세션.
- 역할:
  - Slack `#harness-coord` listen (webhook 또는 polling)
  - user 메시지 분류 → 신규 task 생성 / 기존 task 메시지 라우팅
  - `orca orchestration run-create` 로 task 당 Run 생성
  - `worker-start --agent <id>` 로 각 role worker spawn (supervised)
  - `check --wait` 로 `worker_done`/`escalation`/`question` 소비
  - Slack 에 리포트 포스트

#### 3.2 Role worker 모델 (orchestration 통합)

**claude/codex 역할**:
- `worker-start --spec "<bootstrap prompt>" --worktree path:<wt> --agent claude`
- preamble 에 Task+Dispatch ID 자동 주입 → worker 가 `worker_done` 호출 가능
- `_bootstrap-prompt.sh` 를 "orchestration-aware" 로 업데이트 (`advance` 대신 `worker_done` 호출 지시)

**kiro 역할** (orca native agent 아님):
- `orca terminal create --command "kiro-cli chat ..."` 로 터미널 생성
- `worker-start --terminal <handle>` 로 Task+Dispatch 등록 (supervised)
- kiro-cli 는 orchestration IDs 를 모르므로 `tasks.sh advance` 가 `worker_done` 을 **대신 호출** (wrapper 역할)

**Agent 간 선택 제약** (Phase 2 learning):
- QA/reviewer 는 긴 orchestration 이라 **claude 권장** (`.harness/AGENTS.md`)
- kiro 는 "코드 작성" 역할에만 (frontend scaffold OK, UAT NG)

#### 3.3 Chat 로그 2-way sync

- Local: `.harness/chat/T###.jsonl` (현재 그대로)
- Slack: `#task-T###` 채널의 스레드
- 어댑터: `scripts/chat.sh append` 가 Slack 토큰 있으면 slack API 로 미러
- 네트워크 실패 시 로컬만 쌓고 재시도 큐 (`.harness/chat/T###.pending`)

#### 3.4 파일 계획

**신규**:
- `scripts/coord.sh` — coordinator 메인 루프 (listen + dispatch + check-wait)
- `scripts/slack/send.sh` — Slack bot message post
- `scripts/slack/listen.sh` — Slack events API polling 또는 webhook endpoint
- `scripts/orchestration/worker-start.sh` — orca orchestration 래퍼 (현재 agents/*.sh 통합)
- `scripts/orchestration/check-wait.sh` — coordinator 폴링 헬퍼

**수정**:
- `scripts/agents/_bootstrap-prompt.sh` — worker_done 호출 지시 추가
- `scripts/tasks.sh advance` — `worker_done` wrapper 호출 (kiro 폴백 포함)
- `scripts/tasks.sh new` — `run-create` + `task-create` + 초기 worker-start
- `scripts/chat.sh append` — Slack 미러 토큰 있을 때
- `.harness/roles/coordinator.md` — Slack 상호작용 섹션

#### 3.5 사전 준비 (user)

- Slack 워크스페이스 + Bot App 생성
- Scopes: `chat:write`, `channels:read`, `channels:history`, `channels:manage` (채널 자동 생성용), `groups:write` (private channel)
- Bot token (`xoxb-...`) → `.env` 의 `SLACK_BOT_TOKEN`
- 채널 전략:
  - `#harness-coord` 수동 생성 — user ↔ coordinator 대화
  - `#task-T###-<slug>` task 생성 시 자동 생성

#### 3.6 Phase 3 수용 기준

- [ ] Slack `#harness-coord` 에 "회원가입 만들어줘" → coordinator 세션이 즉시 응답 + T### 생성
- [ ] 각 role 세션이 **orca orchestration worker** 로 spawn (`worker-list` 에서 확인됨)
- [ ] role 완료 시 `worker_done` 호출로 coordinator 에 settle 보고 (claude/codex 네이티브, kiro 는 tasks.sh wrapper)
- [ ] coordinator 가 다음 role 자동 spawn + Slack 에 전환 메시지 포스트
- [ ] Slack 과 로컬 `.harness/chat/T###.jsonl` 양쪽에 메시지 기록됨
- [ ] 최종 merge 완료 시 coordinator 가 Slack 에 요약 리포트 (SHA + 변경 범위)

#### 3.7 Phase 3 진행 단계 (하위 서브태스크)

| 서브 | 내용 | 선행 |
|------|------|------|
| 3-A | Slack 어댑터 (`scripts/slack/*`) + 토큰 셋업 가이드 | - |
| 3-B | orchestration 래퍼 (`worker-start` 통합) + bootstrap 프롬프트 업데이트 | - |
| 3-C | `tasks.sh advance` 가 `worker_done` 호출 (kiro wrapper 포함) | 3-B |
| 3-D | Coordinator 세션 (`scripts/coord.sh`) — listen + dispatch + check-wait 루프 | 3-A, 3-B, 3-C |
| 3-E | `chat.sh` Slack 미러 어댑터 | 3-A |
| 3-F | End-to-end 검증 (실 Slack + 실 task 1건) | 전체 |

#### 3.8 결정 필요 항목 (3-A 전에)

1. **Slack 봇 승인/권한 범위**: user 가 봇을 설치할 워크스페이스 결정, scope 승인 준비
2. **채널 전략**: `#task-T###-<slug>` 자동 생성 (`channels:manage`) vs 사전 생성된 단일 `#tasks` 채널 + 스레드로 분리
3. **Coordinator 세션 수명**: Orca 자동 재시작 지원 여부 — 지금은 수동 유지 가정
4. **kiro worker_done**: `tasks.sh advance` 가 `worker_done` 호출 시 `--outcome` 결정 로직 — kiro 작업 커밋 유무로 판정 vs 명시적 "pass/fail" 수동 입력

### Phase 4 (선택) — 관측 레이어

- user용 tmux 모니터링 레이아웃 (chat tail + board watch + orca worker status)
- `.harness/dashboard.md` 자동 갱신 훅

---

## 5. 명령어 레퍼런스 (Phase 1 기준)

```bash
# 신규 task
./scripts/tasks.sh new <slug>
# → .harness/tasks/T###-<slug>.md 생성 (template 복사)
# → task/T###-<slug> 브랜치
# → .worktrees/T###-<slug>/ (git worktree add)
# → .env, docker-compose.override.yml 생성 (포트 스코프)

# task 목록
./scripts/tasks.sh list
# T001  signup-api    backend       3010/4010/3307  in-progress
# T002  post-list     planner       3020/4020/3308  planning

# 현재 역할 커서를 다음 required_roles로 이동
./scripts/tasks.sh advance [task-id]     # worktree 내부면 task-id 자동 감지

# 최종 병합 (reviewer가 호출)
./scripts/tasks.sh merge [task-id]
# → rebase main
# → ff-only merge to main
# → worktree + branch 정리

# task 폐기 (실수로 만든 경우)
./scripts/tasks.sh drop [task-id]
# → 확인 후 worktree + branch 삭제, task.md는 archive로 이동

# 역할 세션 진입
./scripts/role.sh <role>                 # worktree 내부에서 실행 → task 자동 감지
./scripts/role.sh <role> <task-id>       # 명시적

# chat log
./scripts/chat.sh append <task-id> <from> <to> <type> <message>
./scripts/chat.sh view <task-id>         # 사람이 읽기 좋게
./scripts/chat.sh tail <task-id>         # tail -f
```

---

## 6. 핵심 데이터 스키마

### task 파일 frontmatter

```yaml
---
id: T001
title: 회원가입 API
slug: signup-api
branch: task/T001-signup-api
worktree: .worktrees/T001-signup-api
status: in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: claude }
  - { role: architect,  agent: claude }
  - { role: designer,   agent: claude, mcp: [figma] }
  - { role: backend,    agent: claude }
  - { role: frontend,   agent: claude }
  - { role: qa,         agent: claude }
  - { role: reviewer,   agent: claude }
current_role: planner
role_history:
  - { role: planner,   agent: claude, started: 2026-10-20T10:00, finished: null, commits: [] }
ports:
  web: 3010
  api: 4010
  db: 3307
compose_project: harness_t001
figma_url: null
created_at: 2026-10-20
updated_at: 2026-10-20
---
```

### chat JSONL 1라인

```json
{"ts":"2026-10-20T10:00:00+09:00","task":"T001","from":"user","to":"coordinator","type":"request","body":"회원가입 만들어줘"}
```

허용 `type`: `request` | `dispatch` | `question` | `answer` | `report` | `deliver` | `handoff` | `error` | `note`

---

## 7. 포트 할당 공식

```
WEB_PORT = 3000 + (task_num % 100) * 10
API_PORT = 4000 + (task_num % 100) * 10
DB_PORT  = 3306 + (task_num % 100)
COMPOSE_PROJECT_NAME = harness_t<zero-padded 3자리>
```

task_num=1 → web 3010, api 4010, db 3307
task_num=2 → web 3020, api 4020, db 3308

100개까지 겹침 없이 운영. 넘어가면 재사용(완료된 task 번호 회수).

---

## 8. 인터럽트 규칙 (A → B)

- B가 긴급하지 않음 → **Slack 또는 coordinator에게 메시지** → coordinator가 Inbox로 캡처 → A 계속
- B가 긴급 → A의 task 파일에 pause-note 작성 → `tasks.sh pause T00A` → B를 새 task로 시작

> Phase 1에서는 `tasks.sh pause` 미구현. 수동으로 pause-note 섹션을 task 파일에 추가하고 status를 `paused`로 바꾸는 방식.

---

## 9. 재개 시 체크리스트

중단 후 다시 시작할 때:
1. `TaskList` 로 미완료 작업 확인
2. 이 문서(§4 Phase 체크박스)에서 다음 할 일 확인
3. `.harness/board.md` 로 현재 활성 task 상태 확인
