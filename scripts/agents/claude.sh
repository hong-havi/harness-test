#!/usr/bin/env bash
# agents/claude.sh — Claude agent 를 Orca 로 spawn
# 호출 규약: $0 <task-id> <role> <worktree-abs-path>

set -euo pipefail

TASK_ID="${1:?task-id required}"
ROLE="${2:?role required}"
WORKTREE_PATH="${3:?worktree path required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_NAME="claude"

# 부트스트랩 프롬프트 생성
PROMPT="$("$SCRIPT_DIR/_bootstrap-prompt.sh" "$TASK_ID" "$ROLE" "$AGENT_NAME")"

echo "→ orca agent launch: claude @ $WORKTREE_PATH (role=$ROLE)"

if [[ "${HARNESS_DRY_RUN:-0}" == "1" ]]; then
  echo "[DRY RUN] orca agent launch --agent claude --worktree path:$WORKTREE_PATH --prompt <...> --focus --json"
  echo "[DRY RUN] prompt length: ${#PROMPT} chars"
  exit 0
fi

orca agent launch \
  --agent claude \
  --worktree "path:$WORKTREE_PATH" \
  --prompt "$PROMPT" \
  --focus \
  --json
