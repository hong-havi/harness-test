# Coordinator 운영 규칙 (Phase 4 — B 재설계)

## 개념

**Coordinator** 는 **전용 claude agent 세션** (Auto-mode) 이다. 하나의 task 에 1 Coordinator 1 Run 바인딩. bash 데몬 모델 (`scripts/coord.sh`) 은 폐기 — Orca orchestration 의 `run-use` bind 는 agent 세션 단위라 bash 스크립트에서 유지 불가.

### Coordinator 는 **하지 않는다**
- 코드/문서 직접 작성
- Worker 가 할 일을 대신 (plan / design / implement / commit)
- `apps/` worktree 수정 (main repo 위에서만 돈다)
- `orca orchestration ask` 없이 응답 텍스트로 사용자에 질문 (전달 안 됨)

### Coordinator 는 **한다**
- `orca orchestration run-use --id $RUN_ID` 로 Run 바인딩 획득
- `orca orchestration check --wait` 로 메시지 수신
- `scripts/coord-step.sh handle <msg>` 로 메시지별 처리 (worker-start / 역할 전환 / handles)
- `question` 수신 → `ask` 로 사용자 중계 → `reply` 로 worker 에 답
- `escalation` 수신 → 사용자에 긴급 중계
- 모든 required_roles 소진 시 사용자에 완료 리포트

---

## 운영 흐름

### 1. 사용자: 새 task

    ./scripts/tasks.sh new <slug> [자연어 요구사항]

내부:
1. worktree + 브랜치 + task.md 생성
2. `orca orchestration run-create` → `run_id`
3. `scripts/coord-launch.sh` 호출 → **전용 Coordinator claude 세션** 띄움
4. Coordinator 세션에 preamble 주입 (TASK_ID, RUN_ID, WORKTREE, AGENT, FIRST_ROLE, USER_REQUEST)
5. 사용자 셸은 즉시 리턴. 이후 체인은 Coordinator 세션이 담당.

### 2. Coordinator 세션 (자율 Auto-mode)

preamble 지시대로:
1. `orca orchestration run-use --id $RUN_ID` (bind)
2. `./scripts/orca/worker-start.sh $TASK_ID planner "$WORKTREE" $AGENT $RUN_ID "$USER_REQUEST"`
3. 메인 루프:

       msg=$(orca orchestration check --wait \
         --types worker_done,question,escalation,heartbeat \
         --timeout-ms 60000 --json)
       ./scripts/coord-step.sh handle "$msg"

   `coord-step.sh` 가 stdout 에 `ACTION: ...` 지시를 돌려주면 Coordinator 가 그에 맞춰 다음 액션 수행.

### 3. Worker 세션

Worker 는 Phase 4 와 동일 — 작업 끝나면:

    orca orchestration send --type worker_done \
      --task-id <preamble 에서> \
      --dispatch-id <preamble 에서> \
      --outcome succeeded \
      --summary "..." \
      --files-modified "..."

### 4. 사용자 질문 중계

Worker 가 `orca orchestration ask` 호출 → Coordinator 가 `check --wait` 로 question 수신 → Coordinator 가 **다시 `ask` 를 호출** 해 사용자에게 중계 → 사용자 답이 Coordinator 세션에 자동 주입 → Coordinator 가 `orca orchestration reply --to <worker-sender>` 로 worker 에 전달.

### 5. Reviewer merge 승인

Reviewer worker 가 체크리스트 통과 → `ask` 로 사용자에 "merge?" → 사용자 "merge" → Reviewer 가 `tasks.sh merge` 호출 → worker_done 전송.

---

## 재개 (recovery)

Coordinator 세션이 crash:
1. `./scripts/coord-launch.sh $TASK_ID $RUN_ID "$WORKTREE" $AGENT <current_role> ""` 재호출.
   - 변수는 task.md frontmatter 의 `run_id` + `current_role` + 포트에서 복구.
2. preamble 에 같은 RUN_ID 들어가므로 `run-use` 로 다시 bind.
3. 메인 루프 재진입. 중복 worker-start 는 Orca 가 거부 (활성 Dispatch 유지됨).

---

## State 영속

| 데이터 | 위치 | 쓰는 주체 |
|---|---|---|
| task.md (frontmatter + 섹션) | `.harness/tasks/T###-<slug>.md` + worktree live | tasks.sh / worker |
| run_id | task.md frontmatter | tasks.sh new |
| role_history | `.harness/chat/T###.role-history.jsonl` | coord-step.sh |
| handles (role / agent / handle / dispatch) | `.harness/chat/T###.handles` | worker-start.sh |
| chat log (role 간 메시지) | `.harness/chat/T###.jsonl` + Slack | chat.sh |

전부 **파일**. Coordinator 세션이 날아가도 전부 복구 가능.

---

## 금지 사항

- bash 백그라운드 데몬 (`scripts/coord.sh`) — 폐기됨. 쓰지 말 것.
- `tasks.sh advance` — Phase 4 에서 제거됨. worker 가 `worker_done` 보내면 Coordinator 가 자동 전환.
- 수동 `orca agent launch` 로 worker 띄우기 — `scripts/orca/worker-start.sh` 를 쓸 것 (Run 등록 포함).
- **Coordinator 세션 안에서 Monitor tool / 백그라운드 polling 으로 `check` 호출 금지** — Orca 메시지 큐가 단일 소비자 모델이라 dual consumer 가 되면 worker-start 가 **메시지당 2-3회 중복 호출**됨. 메인 흐름의 blocking `check --wait` 하나만. (coord-step.sh 가 `.harness/chat/<task>.processed-dispatches` 로 idempotency 2차 방어하지만 1차는 preamble 지침 준수.)

---

## 디버깅

- Coordinator 세션 터미널 확인: `orca terminal list` 에서 title `🎯 Coordinator T###`
- 체인 끊김 의심: handles 파일 마지막 라인 + task.md current_role + git log 교차 확인
- `consumer_fenced` 에러 → Coordinator 가 bind 안 됨. 세션 안에서 `orca orchestration run-current` 확인
