#!/usr/bin/env bash
# agents/kiro.sh — Kiro IDE 를 agent 모드로 spawn
# 호출 규약: $0 <task-id> <role> <worktree-abs-path>
#
# Kiro는 Orca native 가 아니라서 kiro CLI 를 직접 호출합니다.
# `kiro chat --new-window --mode agent "<prompt>"` 는 Kiro IDE 를 열고
# 지정된 작업 디렉토리에서 agent 모드 채팅을 시작합니다.

set -euo pipefail

TASK_ID="${1:?task-id required}"
ROLE="${2:?role required}"
WORKTREE_PATH="${3:?worktree path required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_NAME="kiro"

command -v kiro >/dev/null 2>&1 || { echo "ERROR: kiro CLI 를 찾을 수 없음" >&2; exit 1; }

PROMPT="$("$SCRIPT_DIR/_bootstrap-prompt.sh" "$TASK_ID" "$ROLE" "$AGENT_NAME")"

echo "→ kiro chat (agent mode) @ $WORKTREE_PATH (role=$ROLE)"

if [[ "${HARNESS_DRY_RUN:-0}" == "1" ]]; then
  echo "[DRY RUN] (cd $WORKTREE_PATH && kiro chat --new-window --mode agent <prompt...>)"
  exit 0
fi

# kiro chat 은 cwd 기준으로 열림 → 먼저 cd
cd "$WORKTREE_PATH"

# --new-window: 각 역할마다 새 창 (fresh context)
# --mode agent: 도구/셸 사용 가능한 agent 모드 (기본값이지만 명시)
kiro chat --new-window --mode agent "$PROMPT" &

# kiro 는 GUI 를 열고 즉시 반환. 백그라운드로 띄워 shell 흐름 방해 안 함.
# Orca 상태로는 추적되지 않음 — chat log 에 spawn 기록.
"$SCRIPT_DIR/../chat.sh" append "$TASK_ID" "harness" "$ROLE" note "kiro agent spawned (external window, not tracked by Orca)" >/dev/null
echo "✓ Kiro IDE 창이 열렸습니다. 해당 창에서 작업하세요."
