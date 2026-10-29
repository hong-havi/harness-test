## kiro — Coordinator 특유 지침

### 메인 루프 — 명시적 반복

kiro-cli 는 Claude Code 의 Auto-mode / Monitor tool 개념이 없음. 아래 루프를 **당신 세션 내부에서 명시적으로 반복** 호출:

    while true; do
      msg_json=$(orca orchestration check --wait \
        --types worker_done,question,escalation,heartbeat \
        --timeout-ms 600000 --json)
      ./scripts/coord-step.sh handle "$msg_json"
      # coord-step.sh 가 'ACTION: task-complete' 를 출력하면 루프 종료
    done

### ⚠️ 단일 소비자 원칙 — 중복 check 금지

Orca orchestration 메시지 큐는 **단일 소비자** 모델. 두 흐름이 동시에 `check` 호출하면 메시지가 양쪽에 전달 → `worker-start` 중복.

**금지**:
- 어떤 수단으로도 두 번째 `check` 를 동시에 띄우지 말 것 (별도 터미널, 백그라운드 shell 등)
- 메인 루프 밖에서 ack 확인용 추가 `check` 금지 — ack 는 다음 `check` 호출에 `--ack <id>` 로 포함

`coord-step.sh` 가 dispatch_id idempotency 로 2차 방어하지만, 중복 호출 자체를 피하는 게 우선.

### 장기 실행 명령 — Coordinator 는 특히 민감

Coordinator 세션이 멈추면 **task 전체 사망**. 긴 명령 (서버 상주, docker up foreground) 은 Coordinator 안에서 **절대 호출 금지**. 모든 shell 호출은 즉시 반환되는 orca CLI 또는 짧은 스크립트만 (`coord-step.sh handle`, `slack/send.sh`, `tasks.sh merge` 등).

### Slack 중계

Coordinator 가 사용자에게 질문할 때 (`orca orchestration ask` 는 Dispatch 전용이라 Coordinator 는 호출 불가). 반드시 Slack 스레드로:

    ./scripts/slack/send.sh \
      --text "질문 ..." \
      --thread "$(cat .harness/chat/$TASK_ID.slack)"

`--thread` 생략 금지.
