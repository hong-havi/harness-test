#!/usr/bin/env bash
# coord-launch.sh — Phase 4: 전용 Coordinator claude agent 세션 spawn.
#
# 사용: $0 <task-id> <run-id> <worktree-abs> <worker-agent> <first-role> [user-request]
#
# 동작:
#   1. orca agent launch --agent claude --worktree <main repo>  (coord 는 main 에서 돈다)
#   2. tui-idle 대기
#   3. preamble 주입 — Coordinator preamble + 변수 치환
#   coord 세션은 자율 (Auto mode) 로 돌면서 run-use → worker-start → check-wait 루프 수행.

set -euo pipefail

TASK_ID="${1:?task-id required}"
RUN_ID="${2:?run-id required}"
WORKTREE="${3:?worktree abs path required}"
AGENT="${4:?worker agent required}"
FIRST_ROLE="${5:?first role required}"
USER_REQUEST="${6:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
if [[ "$GIT_COMMON_DIR" = /* || "$GIT_COMMON_DIR" =~ ^[A-Z]:/ ]]; then
  MAIN_REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  MAIN_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "→ $*"; }

# Orca 포맷 경로
MAIN_ORCA="$MAIN_REPO_ROOT"
WORKTREE_ORCA="$WORKTREE"
if command -v cygpath >/dev/null 2>&1; then
  MAIN_ORCA="$(cygpath -m "$MAIN_REPO_ROOT")"
  WORKTREE_ORCA="$(cygpath -m "$WORKTREE")"
fi

# ─────────────────────────────────────────────────────────────
# agent/model config 로드 — .harness/agents.conf (+ .local.conf override)
# ─────────────────────────────────────────────────────────────
# shellcheck disable=SC1091
source "$MAIN_REPO_ROOT/scripts/agents-conf.sh"
COORD_AGENT="$(conf_coordinator_agent)"
COORD_MODEL="$(conf_coordinator_model)"

# ─────────────────────────────────────────────────────────────
# Coordinator 세션 띄우기
# ─────────────────────────────────────────────────────────────
info "Coordinator $COORD_AGENT 세션 launch (main repo 위에서 상주, model='${COORD_MODEL:-auto}')..."
LAUNCH="$(orca agent launch \
  --agent "$COORD_AGENT" \
  ${COORD_MODEL:+--model "$COORD_MODEL"} \
  --worktree "path:$MAIN_ORCA" \
  --focus \
  --json 2>&1)"
HANDLE="$(echo "$LAUNCH" | sed -nE 's/.*"handle"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)"
[[ -n "$HANDLE" ]] || die "Coordinator agent launch 실패: $LAUNCH"

info "  handle=$HANDLE — TUI 로드 대기..."
orca terminal wait --terminal "$HANDLE" --for tui-idle --timeout-ms 20000 --json >/dev/null 2>&1 \
  || info "  (tui-idle timeout — 계속)"
sleep 2

# ─────────────────────────────────────────────────────────────
# Preamble 조립 — 3 블록 합성:
#   (A) generic header: 변수, 즉시 수행, ACTION 라인 매뉴얼, ACK 패턴, Slack 중계 등
#   (B) agent-specific adapter: agents/<COORD_AGENT>/common.md + coordinator.md
#   (C) role spec: roles/coordinator.md
# ─────────────────────────────────────────────────────────────
COORD_ROLE_MD="$MAIN_REPO_ROOT/.harness/roles/coordinator.md"
AGENT_COMMON_MD="$MAIN_REPO_ROOT/.harness/agents/$COORD_AGENT/common.md"
AGENT_COORD_MD="$MAIN_REPO_ROOT/.harness/agents/$COORD_AGENT/coordinator.md"

load_or_warn() {
  local f="$1" label="$2"
  if [[ -f "$f" ]]; then
    cat "$f"
  else
    echo "> ⚠️ $label 어댑터 파일 없음 ($f). agents.conf 의 HARNESS_COORDINATOR_AGENT='$COORD_AGENT' 와 매칭되는 .harness/agents/$COORD_AGENT/ 폴더를 작성하세요."
  fi
}

AGENT_COMMON_BODY="$(load_or_warn "$AGENT_COMMON_MD" "agents/$COORD_AGENT/common.md")"
AGENT_COORD_BODY="$(load_or_warn "$AGENT_COORD_MD" "agents/$COORD_AGENT/coordinator.md")"
COORD_ROLE_BODY="$(cat "$COORD_ROLE_MD" 2>/dev/null || echo "(coordinator.md 없음 — WARNING)")"

PREAMBLE="$(cat <<EOF
# Coordinator session — task $TASK_ID (agent: $COORD_AGENT, model: ${COORD_MODEL:-auto})

당신은 **Coordinator** 입니다. 아래 (A) orchestration 프로토콜 → (B) agent 어댑터 → (C) 역할 지침 순서로 지침을 받습니다. 지침대로 수행하세요.

---

## (A) Orchestration 프로토콜 — agent 무관

### 주입 변수

- TASK_ID=$TASK_ID
- RUN_ID=$RUN_ID
- WORKTREE=$WORKTREE_ORCA
- AGENT=$AGENT (worker 기본 agent)
- FIRST_ROLE=$FIRST_ROLE
- USER_REQUEST=${USER_REQUEST:-see .harness/tasks/$TASK_ID-*.md}

### 즉시 수행 (순서대로)

**1단계: Run bind**

    orca orchestration run-use --id $RUN_ID --json

**2단계: 첫 worker spawn**

    ./scripts/orca/worker-start.sh $TASK_ID $FIRST_ROLE "$WORKTREE_ORCA" $AGENT $RUN_ID "${USER_REQUEST//\"/\\\"}"

**3단계: 메인 루프** — 아래 호출 후 반환된 payload 를 \`scripts/coord-step.sh handle\` 에 넘기세요:

    msg_json=\$(orca orchestration check --wait \\
      --types worker_done,question,escalation,heartbeat \\
      --timeout-ms 600000 --json)
    ./scripts/coord-step.sh handle "\$msg_json"

> timeout 600000ms (10분) 은 빈 timeout 턴 비용을 줄이기 위함. 메시지 즉시 수신 시 바로 반환.

### ACTION 라인 매뉴얼

coord-step.sh 가 stdout 에 \`ACTION: ...\` 로 다음 할 일을 지시:
- \`ACTION: spawned T=... role=...\` → 그냥 다음 check.
- \`ACTION: duplicate-skipped ...\` → 이미 처리된 메시지. 다음 check.
- \`ACTION: ask-user T=... msg='...'\` → Slack 포스트로 사용자 중계 (아래 Slack 중계 참조).
- \`ACTION: question sender=... body='...'\` → Slack 포스트 후 사용자 응답을 \`orca orchestration reply --to <sender> --body "..."\` 로 worker 에 전달.
- \`ACTION: escalation ...\` → Slack 포스트로 긴급 알림.
- \`ACTION: task-complete T=...\` → **메인 루프 즉시 종료**:
    1. "✅ T### 완료 — merged <sha>. Coordinator 종료." 한 줄 출력
    2. **더 이상 \`orca orchestration check\` 호출 금지**. shell 호출 자체 중단.
    3. 다음 사용자 지시 대기 (추가 작업 없이 유휴).
    ⚠️ task-complete 는 반드시 종료 신호. 계속 check 돌리면 리소스 낭비 + 다음 task 와 혼선.
- \`ACTION: heartbeat\` 또는 응답 없음 → 다시 check.
- \`ACTION: ack delivery=<delivery_id>\` → **다음 check 호출에 반드시 \`--ack <delivery_id>\` 포함**. 안 하면 Orca 가 같은 메시지 재배포, 큐 교착.

### ACK 패턴

각 메시지 처리 후 coord-step.sh 가 보통 마지막 라인에 \`ACTION: ack delivery=<id>\` 출력. **다음 check 호출에 그 id 포함**:

    LAST_ACK=\$(./scripts/coord-step.sh handle "\$msg_json" | tee /dev/stderr | awk -F'=' '/^ACTION: ack delivery=/{print \$2}')

    msg_json=\$(orca orchestration check --wait --ack "\$LAST_ACK" \\
      --types worker_done,question,escalation,heartbeat \\
      --timeout-ms 600000 --json)

ack 생략 시 planner succeeded 가 영원히 재배포되어 architect worker_done 이 큐에 밀려 처리 불가.

### Coordinator 는 \`ask\` 호출 금지

\`orca orchestration ask\` 는 supervised Dispatch 전용. Coordinator (= Run owner) 는 Dispatch 가 아니므로 \`supervised Dispatch 필요\` 에러.

**worker question 중계 흐름**:
1. coord-step.sh 가 자동으로 Slack 에 \`🔔 응답 필요 — T### <본문>\` 포스트.
2. 사용자 Slack 스레드 응답 → relay.sh 가 Coordinator 세션에 주입.
3. 당신이 그 응답을 worker 에 reply:

       orca orchestration reply --to <sender_dispatch_id> --body "<사용자 응답>" --json

### Slack 중계 (사용자에게 질문 / task 완료 알림)

Coordinator 가 사용자에게 직접 질문하거나 task 완료를 알릴 때 **반드시 task 스레드 안에**:

    "$MAIN_REPO_ROOT/scripts/slack/send.sh" \\
      --text "..." \\
      --thread "\$(cat $MAIN_REPO_ROOT/.harness/chat/$TASK_ID.slack)"

❌ \`--thread\` 생략 금지 — task 식별 불가.

task-complete 수신 시 메인 루프 종료 **전** 아래 포스트:

    "$MAIN_REPO_ROOT/scripts/slack/send.sh" \\
      --text "✅ *$TASK_ID* 완료 — merged. 모든 role 소진, Coordinator 종료." \\
      --thread "\$(cat $MAIN_REPO_ROOT/.harness/chat/$TASK_ID.slack)"

### 단일 소비자 원칙 (중복 spawn 방지)

Orca orchestration 메시지 큐는 **단일 소비자** 모델. 두 흐름이 동시에 check 호출하면 메시지 양쪽 전달 → worker-start 중복 (실측: architect 2개, frontend 3개).

**원칙** (agent 무관):
- 메인 흐름 1개의 \`check --wait\` 블록킹 호출만.
- 같은 Run 에 동시 두 번 check 금지.
- 메인 루프 밖 추가 check 금지 (ack 확인용 포함).
- ack 는 다음 \`check\` 에 \`--ack\` 로 포함.

**구체 금지 수단은 agent 마다 다름 → 아래 (B) agent 어댑터 참조**.

coord-step.sh 가 dispatch_id idempotency 로 2차 방어하지만, 동시 호출 자체를 피하는 게 1차 방어.

---

## (B) Agent 어댑터 — $COORD_AGENT 특유

$AGENT_COMMON_BODY

$AGENT_COORD_BODY

---

## (C) 역할 지침 — Coordinator

$COORD_ROLE_BODY
EOF
)"

# ─────────────────────────────────────────────────────────────
# Preamble 주입 (terminal send)
# ─────────────────────────────────────────────────────────────
info "  preamble 주입 (${#PREAMBLE} chars)..."
orca terminal send --terminal "$HANDLE" --text "$PREAMBLE" --enter --wait-submit 10 --json >/dev/null 2>&1 \
  || die "preamble 주입 실패"

# ─────────────────────────────────────────────────────────────
# handles 에 coord 세션 기록
# ─────────────────────────────────────────────────────────────
mkdir -p "$MAIN_REPO_ROOT/.harness/chat"
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"role\":\"coordinator\",\"agent\":\"$COORD_AGENT\",\"model\":\"${COORD_MODEL:-auto}\",\"handle\":\"$HANDLE\",\"run_id\":\"$RUN_ID\",\"task_id\":\"\",\"dispatch_id\":\"\"}" \
  >> "$MAIN_REPO_ROOT/.harness/chat/$TASK_ID.handles"

info "✓ Coordinator 세션 띄움 (handle=$HANDLE). Auto-mode 로 루프 수행 중."
