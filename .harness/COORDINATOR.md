# Coordinator 운영 규칙

Phase 4 orchestration 전환 기준.

## 개념

**Coordinator** 는 **Orca orchestration Run 의 메일박스 소비자** 이다. 아래 하지 않는다/한다를 지킨다.

### Coordinator 는 **하지 않는다**
- 코드/문서 직접 작성
- 역할 agent 세션 안에서 작업
- Worker 가 할 일을 대신 (예: 커밋, task.md 섹션 작성)

### Coordinator 는 **한다**
- Slack 에서 user 명령 수신 → task 분해 또는 inbox 보관
- `tasks.sh new <slug>` 로 Run + 첫 worker 생성
- `orca orchestration check --wait` 로 메일박스 소비
- `worker_done` 받으면 다음 역할의 worker-start
- `question` 받으면 Slack 포스트 + user 답 터미널 주입
- `escalation` 받으면 user 알림 + 결정 중계
- Reviewer 가 user 승인 요청 → merge 승인 → `tasks.sh merge`

---

## 전역 루프

```
coord_start:
  resolve_cli (ORCA_CLI_COMMAND or 'orca')
  load_state (.harness/coord/state.json)
  for each task in state.active_tasks:
    if task.status == pending_resume:
      heartbeat_check(task.current_dispatch_id)
      resume_or_abandon(task)
  slack_post("coordinator up, resumed N tasks")
  main_loop

main_loop:
  while true:
    msg = ORCA orchestration check \
          --wait --types "worker_done,question,escalation,heartbeat" \
          --timeout-ms 900000 --json
    if msg is None:
      sleep 1; continue
    handle_message(msg)
    ORCA orchestration check --ack <delivery_id>
    state_save
    poll_slack_commands()   # 짧은 subcycle

poll_slack_commands:
  since last_cursor pull @harness-bot mentions
  for cmd in cmds:
    dispatch_slack_command(cmd)   # new/status/drop/merge/rework/help
```

---

## 상태 파일: `.harness/coord/state.json`

```json
{
  "schema": 2,
  "updated_at": "2026-10-26T07:00:00Z",
  "slack_cursor": "1792...",
  "coordinator_pid": 12345,
  "active_tasks": [
    {
      "id": "T014",
      "slug": "example",
      "run_id": "run_abc",
      "current_role": "backend",
      "current_task_id": "task_xyz",
      "current_dispatch_id": "disp_123",
      "worker_handle": "term_456",
      "slack_thread_ts": "1792...",
      "last_worker_done_at": "...",
      "pending_questions": [
        { "msg_id": "msg_1", "body": "...", "posted_at": "..." }
      ]
    }
  ],
  "inbox": [
    { "ts": "...", "user": "havi", "body": "..." }
  ]
}
```

**원자적 쓰기**: `state.json.tmp` → `mv`. 매 큰 결정마다 + 매 iteration 끝에.

---

## 메시지 처리

### `worker_done`
```
match task = active_tasks[where current_dispatch_id == msg.dispatch_id]
chat.sh append task.id, role, coordinator, deliver, msg.summary
if msg.outcome == succeeded:
  next_role = next_in_required_roles(task.current_role)
  if next_role is None:
    # 모든 역할 소진. reviewer 가 merge 호출했을 테니 완료 처리
    task.status = merged  # 또는 pending user approval
    cleanup_task(task)
  else:
    launch_worker(task, next_role)
if msg.outcome == failed:
  slack_post(task.thread, "⚠ <role> 작업 실패 — user 결정 필요")
  task.status = awaiting_decision
```

### `question`
```
chat.sh append task.id, role, user, question, msg.body
# Slack 미러는 chat.sh 가 자동으로 함
state.pending_questions.append({msg_id, body})
```

### User 답 (Slack thread reply 폴링)
```
for reply in slack_thread_replies_since(last_cursor):
  active_q = state.pending_questions[0]
  ORCA orchestration reply --id active_q.msg_id --body reply.text
  # 또는 터미널 주입: terminal send --terminal task.worker_handle --text reply --enter
  pop(state.pending_questions)
```

### `escalation`
```
slack_post_urgent(task.thread, msg)
# 추가 결정 로직은 user 에게 중계
```

---

## 재시작 복구 프로토콜

Coordinator crash → 재시작 시:
1. `.harness/coord/state.json` 존재 확인
2. 각 `active_tasks` 에 대해:
   - `ORCA orchestration worker-show --dispatch <current_dispatch_id>` 로 상태 조회
   - `live` → 그대로 체인 재진입 (main_loop)
   - `exited` with worker_done → 메일박스에서 `check --peek` 로 confirm → 다음 역할 launch
   - `unverifiable` → **사용자 결정 중계** (abandon vs retry)
3. Slack `#harness-coord` 에 `"coordinator 재시작, N active task 복구"` 리포트
4. `slack_cursor` 기점 이후 메시지 폴링 재개

---

## pause-point 자동화 (scripts/orca-review.sh 와 매핑)

Reviewer 역할은 특별 처리:
- Reviewer worker 가 작업 완료 후 `worker_done` 대신 **`ask`** 로 user 승인 요청
- user 답 (merge / rework / no) 받고 Coordinator 가:
  - merge → `tasks.sh merge <id>` → worker_done 수동 호출 또는 reply
  - rework → `tasks.sh rework <id> <role>` → 새 worker-start
  - no → 추가 질문

---

## Slack ↔ Orchestration 매핑

| Slack 명령 | Coordinator 행동 |
|-----------|------------------|
| `new <slug> [description...]` | `tasks.sh new` → `run-create` + 첫 `worker-start` (planner) |
| `status` | `active_tasks` 요약 + `worker-list --run <run_id>` |
| `advance <task-id>` | **금지** — 체인은 자동. 수동 override 는 `spawn` |
| `spawn <task-id> [role]` | 지정 역할의 worker 수동 재시작 (`worker-start --retry-of` 또는 신규) |
| `rework <task-id> <role>` | 현재 worker abandon + 지정 역할 신규 worker-start |
| `merge <task-id>` | reviewer 승인 후 호출. `tasks.sh merge` 실행 + Run cleanup |
| `drop <task-id>` | 전체 cleanup — `worker-abandon` + git worktree remove |
| `help` | 명령 안내 + 역할 소개 |

---

## 체크리스트 (coord 종료 전)

- [ ] 메일박스 비었는가 (`check --peek` 로 unread 0)
- [ ] 각 `active_task.current_dispatch_id` 가 live 또는 settled
- [ ] `state.json` 최신
- [ ] Slack 에 "coordinator sleeping" 알림 (user 가 알도록)
