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
  --title "🎯 Coordinator T$TASK_ID" \
  --focus \
  --json 2>&1)"
HANDLE="$(echo "$LAUNCH" | sed -nE 's/.*"handle":"([^"]+)".*/\1/p' | head -1)"
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

    orca orchestration run-use --run $RUN_ID --json

**2단계: 첫 worker spawn**

    ./scripts/orca/worker-start.sh $TASK_ID $FIRST_ROLE "$WORKTREE_ORCA" $AGENT $RUN_ID "${USER_REQUEST//\"/\\\"}"

**3단계: 메인 루프 시작** — bash tool 로 아래 하나 호출 후 반환된 payload 를 \`scripts/coord-step.sh handle\` 에 넘기세요:

    msg_json=\$(orca orchestration check --wait \\
      --types worker_done,question,escalation,heartbeat \\
      --timeout-ms 60000 --json)
    echo "\$msg_json" | ./scripts/coord-step.sh handle "\$msg_json"

coord-step.sh 가 stdout 에 \`ACTION: ...\` 라인으로 다음에 할 일을 지시합니다:
- \`ACTION: spawned T=... role=...\` → 그냥 다음 check 로 넘어가세요.
- \`ACTION: ask-user T=... msg='...'\` → \`orca orchestration ask --body "..."\` 로 사용자 결정 요청.
- \`ACTION: question sender=... body='...'\` → ask 로 사용자 중계 후 \`orca orchestration reply --to <sender> --body "..."\` 로 응답.
- \`ACTION: escalation ...\` → ask 로 사용자 긴급 알림.
- \`ACTION: task-complete T=...\` → 사용자에게 완료 리포트, 세션 종료 가능.
- \`ACTION: heartbeat\` 또는 응답 없음 → 그냥 다시 check.

**이 루프를 모든 required_roles 완료까지 반복합니다.**

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
