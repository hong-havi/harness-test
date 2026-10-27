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
# Coordinator 세션 띄우기
# ─────────────────────────────────────────────────────────────
info "Coordinator claude 세션 launch (main repo 위에서 상주)..."
LAUNCH="$(orca agent launch \
  --agent claude \
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
# Preamble 조립
# ─────────────────────────────────────────────────────────────
COORD_MD="$MAIN_REPO_ROOT/.harness/roles/coordinator.md"
COORD_BODY="$(cat "$COORD_MD" 2>/dev/null || echo "(coordinator.md 없음 — WARNING)")"

PREAMBLE="$(cat <<EOF
# Coordinator session — task $TASK_ID

당신은 **Coordinator** 입니다. 아래 지침 전수와 변수를 받습니다. 지침대로 수행하세요.

## 주입 변수

- TASK_ID=$TASK_ID
- RUN_ID=$RUN_ID
- WORKTREE=$WORKTREE_ORCA
- AGENT=$AGENT (worker 기본 agent)
- FIRST_ROLE=$FIRST_ROLE
- USER_REQUEST=${USER_REQUEST:-see .harness/tasks/$TASK_ID-*.md}

## 즉시 수행 (순서대로)

**1단계: Run bind**

    orca orchestration run-use --id $RUN_ID --json

**2단계: 첫 worker spawn**

    ./scripts/orca/worker-start.sh $TASK_ID $FIRST_ROLE "$WORKTREE_ORCA" $AGENT $RUN_ID "${USER_REQUEST//\"/\\\"}"

**3단계: 메인 루프 시작** — bash tool 로 아래 하나 호출 후 반환된 payload 를 \`scripts/coord-step.sh handle\` 에 넘기세요:

    msg_json=\$(orca orchestration check --wait \\
      --types worker_done,question,escalation,heartbeat \\
      --timeout-ms 60000 --json)
    ./scripts/coord-step.sh handle "\$msg_json"

coord-step.sh 가 stdout 에 \`ACTION: ...\` 라인으로 다음에 할 일을 지시합니다:
- \`ACTION: spawned T=... role=...\` → 그냥 다음 check 로 넘어가세요.
- \`ACTION: duplicate-skipped ...\` → 이미 처리된 메시지. 그냥 다음 check.
- \`ACTION: ask-user T=... msg='...'\` → \`orca orchestration ask --body "..."\` 로 사용자 결정 요청.
- \`ACTION: question sender=... body='...'\` → ask 로 사용자 중계 후 \`orca orchestration reply --to <sender> --body "..."\` 로 응답.
- \`ACTION: escalation ...\` → ask 로 사용자 긴급 알림.
- \`ACTION: task-complete T=...\` → 사용자에게 간단한 완료 리포트(한 줄 요약) 를 응답으로 출력하고 **메인 루프를 종료**. 더 이상 check-wait 호출 금지.
- \`ACTION: heartbeat\` 또는 응답 없음 → 그냥 다시 check.
- \`ACTION: ack delivery=<delivery_id>\` → **매우 중요**. 다음 check 호출에 반드시 \`--ack <delivery_id>\` 를 포함하세요. 안 하면 Orca 가 60초마다 같은 메시지를 재배포하고 큐가 막혀 다음 worker_done 을 받지 못합니다.

## ⚠️ ACK 패턴 (반드시 지킬 것)

coord-step.sh 는 각 메시지 처리 후 보통 **마지막 라인에 \`ACTION: ack delivery=<id>\`** 를 출력합니다. **다음 check 호출에 그 id 를 반드시 포함** 하세요:

    # 이번 턴 끝에 받은 delivery_id 를 변수에 저장
    LAST_ACK=\$(./scripts/coord-step.sh handle "\$msg_json" | tee /dev/stderr | awk -F'=' '/^ACTION: ack delivery=/{print \$2}')

    # 다음 check 호출에 --ack 포함
    msg_json=\$(orca orchestration check --wait --ack "\$LAST_ACK" \\
      --types worker_done,question,escalation,heartbeat \\
      --timeout-ms 60000 --json)

ack 하지 않으면 **planner succeeded 가 영원히 재배포되어 architect worker_done 이 큐에 밀려 처리 불가** 등의 교착 발생.

**이 루프를 모든 required_roles 완료까지 반복합니다. \`task-complete\` 받으면 루프 즉시 종료.**

## ⚠️ 매우 중요 — 단일 소비자 원칙 (중복 spawn 방지)

Orca orchestration 메시지 큐는 **단일 소비자** 모델을 전제합니다. 두 흐름이 동시에 check 호출하면 메시지가 **양쪽 모두에 전달되거나 재배포되어** worker-start 가 중복 호출됩니다 (실제로 발생함: architect/frontend kiro 세션이 2-3개씩 뜸).

**금지사항** (반드시 지킬 것):

1. **Monitor tool 사용 금지** — Claude Code 의 Monitor 로 \`orca orchestration check\` 를 백그라운드 polling 하지 마세요. 메인 흐름에서 하나의 \`check --wait\` 호출만 사용.
2. **\`run_in_background: true\` 로 check 호출 금지** — 메인 흐름 블록킹 호출만.
3. **같은 Run 에 대해 동시에 두 번 check 호출 금지** — 하나 끝나면 다음 하나.
4. **ack 는 매 check 호출에 포함** — \`check --ack <delivery_id>\` 로 즉시 ack 하거나, 다음 check 호출 시 \`--ack <prev_delivery_id>\` 로 처리. 지연 ack 하면 재배포됨.

**올바른 메인 루프 패턴 1건만**:

    while true:
      msg_json=\$(orca orchestration check --wait \\
        --types worker_done,question,escalation,heartbeat \\
        --timeout-ms 60000 --json)
      ./scripts/coord-step.sh handle "\$msg_json"
      # (ack 는 check --wait 가 자동으로 수행하거나 다음 호출에서 --ack 포함)

**중복 방지 가드도 코드에 있음**: coord-step.sh 가 dispatch_id 를 \`.harness/chat/<task>.processed-dispatches\` 에 기록해 같은 메시지가 재전달돼도 \`ACTION: duplicate-skipped\` 로 안전하게 skip. 하지만 **애초에 Monitor 를 안 띄우는 게 1차 방어선**.

## 전체 Coordinator 지침 (참고)

$COORD_BODY
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
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"role\":\"coordinator\",\"agent\":\"claude\",\"handle\":\"$HANDLE\",\"run_id\":\"$RUN_ID\",\"task_id\":\"\",\"dispatch_id\":\"\"}" \
  >> "$MAIN_REPO_ROOT/.harness/chat/$TASK_ID.handles"

info "✓ Coordinator 세션 띄움 (handle=$HANDLE). Auto-mode 로 루프 수행 중."
