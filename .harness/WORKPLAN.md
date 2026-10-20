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

**목표**: `tasks.sh new`가 내부적으로 Orca worktree + spawn을 호출. 역할 전환 시 Orca로 agent 세션을 spawn/종료. 초기엔 claude 하나만 사용.

파일:
- `scripts/orca/worktree.sh` — orca worktree 생성/삭제 래퍼
- `scripts/orca/spawn.sh` — orca spawn agent 래퍼 (role + task 컨텍스트 주입)
- `scripts/agents/claude.sh` — claude code CLI 어댑터
- `scripts/agents/codex.sh` — (스켈레톤)
- `scripts/agents/kiro.sh` — (스켈레톤)

**검증**:
- `tasks.sh new <slug>` 이 Orca를 통해 worktree 생성 후 planner를 자동 spawn
- 역할 완료 시 `tasks.sh advance` 가 Orca spawn 호출로 다음 역할 세션 시작
- 세션은 역할 완료 시 종료되고 다음 역할은 fresh context로 시작

### Phase 3 — Slack + Coordinator 자동화

**목표**: user가 Slack 채널에서만 상호작용. Coordinator가 자동으로 task 생성·역할 전환·리포팅.

파일:
- `scripts/slack/send.sh`, `scripts/slack/listen.sh`
- `scripts/chat.sh` 에 Slack 미러 어댑터 추가 (이미 작성된 JSONL에 abstract만 걸침)
- `scripts/coord.sh` — dispatch 자동 루프
- `.env.example` 에 `SLACK_BOT_TOKEN` 추가
- `.harness/roles/coordinator.md` 에 Slack 상호작용 섹션 보강

**사전 준비 (user)**:
- Slack 워크스페이스 + 봇 생성, 토큰 발급
- 채널: `#harness-coord` + 자동 생성될 `#task-T###`

**검증**:
- Slack `#harness-coord`에 "회원가입 만들어줘" 입력 → coordinator가 T001 생성 → `#task-T001-signup` 자동 생성 → 역할 전환마다 메시지 포스트
- Slack 메시지는 로컬 `.harness/chat/T###.jsonl` 과 동기

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
