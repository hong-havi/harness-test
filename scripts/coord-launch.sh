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
- \`ACTION: ask-user T=... msg='...'\` → \`orca orchestration ask --question "..."\` 로 사용자 결정 요청.
- \`ACTION: question sender=... body='...'\` → ask 로 사용자 중계 후 \`orca orchestration reply --to <sender> --body "..."\` 로 응답.
- \`ACTION: escalation ...\` → ask 로 사용자 긴급 알림.
- \`ACTION: task-complete T=...\` → **메인 루프 즉시 종료 (매우 중요)**:
    1. 사용자 응답으로 \`✅ T### 완료 — merged <sha>. Coordinator 종료.\` 한 줄만 출력
    2. **더 이상 \`orca orchestration check\` 호출 금지**. bash tool 호출 자체를 중단.
    3. 다음 사용자 지시 대기 (추가 작업 없이 세션 유휴 상태).
    4. 사용자가 명시적으로 추가 지시하기 전까지는 아무것도 하지 말 것.
    ⚠️ task-complete 는 "선택적 종료" 가 아니라 **반드시 종료** 신호입니다. 계속 check 돌리면 리소스 낭비 + 다음 task 와 혼선.
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

## ⚠️ Shell 명령에 \`bash\` 접두어 금지

하네스 스크립트 호출 시 **절대 \`bash\` 를 명시하지 마세요**:

- ❌ \`bash ./scripts/chat.sh append ...\`     → Windows 에서 WSL /bin/bash 로 fallback → \`No such file or directory\` 실패
- ❌ \`bash scripts/orca/worker-start.sh ...\`
- ✅ \`./scripts/chat.sh append ...\`          → shebang \`#!/usr/bin/env bash\` 가 자동으로 git-bash 로 라우팅
- ✅ \`./scripts/orca/worker-start.sh ...\`
- ✅ \`orca orchestration send ...\`           → orca 자체는 bash 필요 없음

이 패턴은 T022 planner, T025 qa 에서 반복 발생한 결함입니다. kiro-cli 환경에서 특히 자주 터지지만, 어떤 agent 든 shell 명령 호출 시 \`bash\` 접두어 쓰지 말 것.

## ⚠️ Coordinator 는 \`ask\` 호출 금지

\`orca orchestration ask\` 는 **supervised Dispatch 안의 worker 만** 호출 가능합니다. Coordinator (= Run owner) 는 Dispatch 가 아니므로 \`ask\` 호출 시 \`supervised Dispatch 필요\` 에러.

**worker question 수신 시 중계 흐름**:
1. coord-step.sh 가 자동으로 Slack 에 \`🔔 응답 필요 — T### <본문>\` 포스트 (handle_question 내장).
2. 사용자가 Slack 스레드에 응답 → relay.sh 가 받아 Coordinator 세션에 \`terminal send\` 로 주입.
3. Coordinator (= 당신) 는 그 응답을 worker 에 \`reply\` 로 전달:

       orca orchestration reply --to <sender_dispatch_id> --body "<사용자 응답>" --json

\`sender_dispatch_id\` 는 ACTION: question 라인의 \`sender=\` 값. 또는 msg_json 의 \`senderId\` 필드.

**사용자에게 질문해야 하는 경우 (worker 가 아니라 Coordinator 가)**: \`ask\` 대신 **slack/send.sh 직접 호출**:

    "$MAIN_REPO_ROOT/scripts/slack/send.sh" --text "T### 질문: ..." --thread "$(cat .harness/chat/T###.slack)"

그리고 사용자 응답 대기 — relay 가 받아 당신 세션에 주입.

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
