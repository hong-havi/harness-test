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

RESPONSE="$(orca agent launch \
  --agent claude \
  --worktree "path:$WORKTREE_PATH" \
  --prompt "$PROMPT" \
  --focus \
  --json 2>&1)"
echo "$RESPONSE"

# spawn된 터미널 handle 을 기록 (advance 시 이전 역할 터미널 자동 close 용)
HANDLE="$(echo "$RESPONSE" | awk -F'"' '/"handle":/{print $4; exit}')"
if [[ -n "$HANDLE" ]]; then
  GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
  if [[ "$GIT_COMMON_DIR" = /* || "$GIT_COMMON_DIR" =~ ^[A-Z]:/ ]]; then
    REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
  else
    REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  fi
  mkdir -p "$REPO_ROOT/.harness/chat"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"role\":\"$ROLE\",\"agent\":\"claude\",\"handle\":\"$HANDLE\"}" \
    >> "$REPO_ROOT/.harness/chat/${TASK_ID}.handles"
fi
