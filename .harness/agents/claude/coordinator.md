## Claude Code — Coordinator 특유 지침

### ⚠️ 단일 소비자 — Monitor tool / 백그라운드 폴링 절대 금지

Orca orchestration 메시지 큐는 **단일 소비자** 모델. 두 흐름이 동시에 `check` 호출하면 메시지가 양쪽에 전달 → `worker-start` 가 중복 호출됨 (실측: architect 2개, frontend 3개 동시 spawn).

**절대 금지**:
- **Monitor tool 로 `orca orchestration check` 백그라운드 polling 금지**
- `run_in_background: true` 로 `check` 호출 금지
- 같은 Run 에 동시에 두 번 `check` 호출 금지 (ack 확인용 포함)
- 메인 루프 밖에서 추가 `check` 호출 금지

**허용**: 메인 흐름 1개의 블록킹 호출만:

    msg_json=$(orca orchestration check --wait \
      --types worker_done,question,escalation,heartbeat \
      --timeout-ms 600000 --json)

`coord-step.sh` 가 dispatch_id idempotency 로 2차 방어 (`.harness/chat/<task>.processed-dispatches`) 하지만, **Monitor 안 띄우는 게 1차 방어선**.

### Auto-mode 특성

Claude Code 는 Auto-mode 에서 사용자 확인 없이 bash tool 호출을 연속 수행 → Coordinator 메인 루프에 적합. `check --wait` 가 timeout 반환해도 즉시 다음 iteration.

### Slack 중계 호출

Coordinator 가 사용자에게 질문해야 할 때 (worker 가 아닌 Coordinator 본인) `orca orchestration ask` 는 **금지** (supervised Dispatch 요구 에러). 대신 bash tool 로 Slack 포스트:

    "$MAIN_REPO_ROOT/scripts/slack/send.sh" \
      --text "질문 ..." \
      --thread "$(cat $MAIN_REPO_ROOT/.harness/chat/$TASK_ID.slack)"

`--thread` 생략 금지 — task 식별 안 됨.
