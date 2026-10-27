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

### Phase 4 — Orca orchestration 전환 (현재 작업 중)

**배경**: Phase 3 end-to-end 반복 테스트에서 **"shell wrapper 로 self-advance"** 패턴이 fundamentally fragile 함을 확인. agent 세션 (특히 kiro-cli) 이 `/quit` 하면서 내부 bash tool 호출(`tasks.sh advance → spawn.sh`)이 중단되어 자동 체인 반복 깨짐. 수십 번 수정으로도 해결 안됨.

**방향 전환**: Orca orchestration primitives (run-create / worker-start / check / worker_done) 로 전환. Shell wrapper 가 아니라 Orca 가 본격 orchestration 책임.

#### 4.1 교체되는 것 vs 유지되는 것

| 구성 | Phase 3 | Phase 4 |
|------|---------|---------|
| worker spawn | `scripts/agents/*.sh` + `orca agent launch` | `orca orchestration worker-start --spec --agent` |
| preamble | 자체 `_bootstrap-prompt.sh` + argv 주입 | **Orca 가 자동 주입** (Task+Dispatch ID 포함) |
| 다음 역할 전환 | agent 가 self-호출 `tasks.sh advance` → spawn | agent 는 `worker_done` 만, Coordinator 가 다음 `worker-start` |
| Coordinator 역할 | Slack 폴링만, 자동 체인에 무관 | `check --wait` 로 메일박스 소비, 다음 worker 디스패치 |
| chat log | `chat.sh` JSONL + Slack 미러 | `orchestration send/reply` + Slack 미러 (JSONL 선택적 유지) |
| handles 파일 | 수동 관리 | Orca Run 이 state |
| self-advance 체인 | 매번 깨짐 | 없음 (agent 는 작업+worker_done 만) |

**유지되는 자산** (프로젝트 레이어):
- `.harness/roles/*.md` — 역할 지침 (worker spec 재료)
- `.harness/requests/*.md` — User Request 문서
- `.harness/tasks/<id>-<slug>.md` — task spec + 역할별 섹션 누적
- `.harness/templates/*` — task.md / user-request.md 템플릿
- git worktree 생성 (orchestration 과 독립)
- Slack 어댑터 (`send.sh` / `listen.sh`)

#### 4.2 Agent 지원 범위 (Orca 네이티브 리스트 기준)

**worker-start --agent 네이티브 지원**: `claude, codex, cursor, antigravity, muse, zcode, opencode, opencode2`

**비네이티브 (kiro 등)**:
- `orca terminal create --command "kiro-cli chat ..."` 로 터미널 띄움
- `worker-start --terminal <handle>` 로 등록 (preamble 주입은 agent 가 chat 안에서 받음)
- 안정성 떨어지므로 **experimental** 로 명시, **기본값은 claude**

#### 4.3 Coordinator 흐름 (B 재설계 — 2026-10-27)

**중요 재설계**: 초기 Phase 4 는 bash 데몬 `scripts/coord.sh` 가 Coordinator 역할을 담당하는 설계였으나, **end-to-end 테스트에서 치명적 공백**이 드러남 — Orca orchestration 의 `run-use` bind 는 **agent 세션(terminal) 단위**이고 bash 스크립트에서는 bind 유지 불가. 결과: `worker-start` 가 `consumer_fenced` 로 거부됨.

**B 재설계**: Coordinator = **전용 claude agent 세션** (Auto-mode).

```
tasks.sh new <slug>:
  1. worktree + 브랜치 + task.md 생성
  2. orca orchestration run-create → run_id (task.md frontmatter 에 기록)
  3. scripts/coord-launch.sh 호출
       ├─ orca agent launch --agent claude --worktree <main repo> --title "🎯 Coordinator T###"
       ├─ TUI 로드 대기
       └─ preamble 주입 (coordinator.md + 변수 TASK_ID/RUN_ID/WORKTREE/AGENT/FIRST_ROLE/USER_REQUEST)
  4. 사용자 셸 즉시 리턴

Coordinator claude 세션 (preamble 지시대로):
  1. orca orchestration run-use --run $RUN_ID       # Run bind 획득
  2. ./scripts/orca/worker-start.sh $TASK_ID planner "$WORKTREE" $AGENT $RUN_ID "$USER_REQUEST"
  3. loop:
       msg = $(orca orchestration check --wait \
                --types worker_done,question,escalation,heartbeat \
                --timeout-ms 60000 --json)
       ./scripts/coord-step.sh handle "$msg"    # ACTION: ... 지시 출력
       # ACTION 별 처리:
       #   spawned → 다시 check
       #   ask-user / question / escalation → orca orchestration ask → 답을 reply 로 worker 전달
       #   task-complete → 사용자 완료 리포트
```

**bash 데몬 `scripts/coord.sh` 는 폐기** (`.harness/archive/legacy/` 로 이동).
핵심 로직 분리:
- `scripts/coord-launch.sh` — Coordinator claude 세션 띄움 + preamble 주입
- `scripts/coord-step.sh handle <msg>` — 메시지 1건 처리 (handles 역매핑, 역할 전환, 다음 worker-start)
- `.harness/roles/coordinator.md` — Coordinator agent 세션용 지침 (preamble 재료)
- `.harness/COORDINATOR.md` — 운영 규칙

#### 4.4 Worker (agent 세션) 흐름 (preamble 지시대로)

```
# Orca 가 agent 세션에 자동 주입하는 preamble (요약):
#  - Task ID / Dispatch ID
#  - 사용 가능 명령: worker_done, ask, heartbeat, check (follow-up)
#  - 세션 종료 조건: worker_done 호출 후

agent 작업 흐름:
  1. role.sh 로 컨텍스트 로드 (지침, task.md, chat log, PRD)
  2. 역할 지침대로 작업 + 커밋
  3. User 질문 필요 시: orca orchestration ask --body "<Q>"
     → coordinator 가 answer 받아 전달
  4. 작업 완료 시:
     orca orchestration worker-done \
       --task <id> --dispatch <id> \
       --outcome succeeded|failed \
       --summary "..." --files-modified "..." --report-path <task.md>
  5. 세션 종료 (자동)

# 중요: self-advance 호출 없음. 다음 worker 는 coordinator 책임.
```

#### 4.5 신규 / 재작성 파일

**신규**:
- `.harness/COORDINATOR.md` — Coordinator 운영 규칙 (Phase 4 B)
- `scripts/coord-launch.sh` — Coordinator claude 세션 spawn + preamble 주입
- `scripts/coord-step.sh` — 메시지 1건 처리 로직
- `.harness/roles/coordinator.md` — Coordinator agent 세션 preamble 재료

**재작성 (완전 교체)**:
- `scripts/tasks.sh new` — run-create + coord-launch (Coordinator 세션 띄움)
- `scripts/agents/_bootstrap-prompt.sh` — worker_done 패턴
- `.harness/roles/*.md` 7개 (worker) — advance 지시 전부 → worker_done 지시로

**제거/비활성화**:
- `scripts/coord.sh` — bash 데몬 Coordinator. **`.harness/archive/legacy/coord.sh.phase3-bash-daemon` 로 이동**. 재사용 금지.
- `scripts/tasks.sh advance` — orchestration 이 대체 (완전 제거 — stub 에러만)
- `scripts/orca/spawn.sh` — orchestration worker-start 가 대체 (worker-start.sh 가 통합)

**유지 + 리팩터**:
- `scripts/tasks.sh merge` — reviewer 가 user 승인 받고 호출 (그대로)
- `scripts/tasks.sh rework` — orchestration 과 독립 (유지)
- `scripts/tasks.sh drop` — git/orca cleanup 추가 (worker-abandon 호출)
- `scripts/chat.sh` — Slack 미러 유지, orchestration send 와 병행

#### 4.6 Phase 4 서브태스크 (TaskCreate 로 추적)

| ID | 내용 | 상태 |
|----|------|------|
| 28 | T013 drop + cleanup | ✅ 완료 |
| 29 | Phase 4 설계 (이 문서) | 진행 중 |
| 30 | `.harness/COORDINATOR.md` 작성 | pending |
| 31 | `coord.sh` 재작성 (check-wait 루프) | pending |
| 32 | `tasks.sh new` orchestration 전환 | pending |
| 33 | `bootstrap-prompt` 재작성 (worker_done) | pending |
| 34 | role.md 8개 업데이트 | pending |
| 35 | end-to-end 검증 + README 갱신 | pending |

#### 4.7 사용자 결정 필요 (설계 마무리 전)

1. **Agent 기본값**: claude (안정) vs kiro (사용자 요청) — **추천: claude 기본, kiro experimental**
2. **chat.sh 유지 여부**: orchestration send/check 와 병행 vs 완전 교체 — **추천: 병행 (Slack 미러 가치 유지)**
3. **advance 명령**: deprecated wrapper (호환성) vs 완전 제거 — **추천: 완전 제거 (혼동 방지)**
4. **Coordinator 세션 수명**: 세션당 1 Run 유지 vs 매 task 당 1 Run — **추천: task 당 1 Run** (재시작 쉬움)

---

### Phase 5 (추후, 선택) — 관측 레이어

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
