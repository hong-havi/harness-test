#!/usr/bin/env bash
# role.sh — 역할 세션 진입점
#
# 사용법:
#   ./scripts/role.sh <role> [task-id]
#
# 역할 브리핑 + task.md 전체 + chat log tail + PRD 를 출력.
# worktree 내부에서 실행하면 task-id 자동 감지.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_DIR="$REPO_ROOT/.harness"
ROLES_DIR="$HARNESS_DIR/roles"
TASKS_DIR="$HARNESS_DIR/tasks"
CHAT_DIR="$HARNESS_DIR/chat"
PRD_FILE="$REPO_ROOT/PRD.md"
BOARD_FILE="$HARNESS_DIR/board.md"
WORKTREES_DIR="$REPO_ROOT/.worktrees"
CHAT_TAIL_LINES="${CHAT_TAIL_LINES:-20}"

VALID_ROLES=(coordinator planner architect designer backend frontend qa reviewer)

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  echo "Usage: $0 <role> [task-id]"
  echo "Roles: ${VALID_ROLES[*]}"
  echo ""
  echo "worktree 내부에서 실행하면 task-id 자동 감지."
  echo "coordinator 역할은 task-id 불필요 (전역 역할)."
}

ROLE="${1:-}"
TASK_ID="${2:-}"

[[ -n "$ROLE" ]] || { usage; exit 1; }

MATCHED=0
for r in "${VALID_ROLES[@]}"; do
  [[ "$r" == "$ROLE" ]] && MATCHED=1 && break
done
[[ $MATCHED -eq 1 ]] || { echo "Unknown role: $ROLE" >&2; usage >&2; exit 1; }

ROLE_FILE="$ROLES_DIR/$ROLE.md"
[[ -f "$ROLE_FILE" ]] || die "role 파일 없음: $ROLE_FILE"

# ── task-id 자동 감지 (coordinator 제외)
detect_task_id() {
  local pwd_abs
  pwd_abs="$(pwd -P)"
  if [[ "$pwd_abs" == "$WORKTREES_DIR"/* ]]; then
    local rel="${pwd_abs#$WORKTREES_DIR/}"
    local wt_name="${rel%%/*}"
    echo "${wt_name%%-*}"
  fi
}

if [[ "$ROLE" != "coordinator" && -z "$TASK_ID" ]]; then
  TASK_ID="$(detect_task_id)"
  [[ -n "$TASK_ID" ]] || die "task-id 를 지정하거나 worktree 안에서 실행하세요."
fi

TASK_FILE=""
if [[ -n "$TASK_ID" ]]; then
  TASK_FILE="$(find "$TASKS_DIR" -maxdepth 1 -name "${TASK_ID}-*.md" 2>/dev/null | head -1)"
  [[ -n "$TASK_FILE" ]] || die "task 파일 없음: $TASK_ID"
fi

CHAT_FILE=""
[[ -n "$TASK_ID" ]] && CHAT_FILE="$CHAT_DIR/${TASK_ID}.jsonl"

# ─────────────────────────────────────────────────────────────────────
sep() { printf '%*s\n' 72 '' | tr ' ' '='; }

sep
echo " ROLE: $ROLE"
[[ -n "$TASK_ID" ]] && echo " TASK: $TASK_ID"
[[ -n "$TASK_FILE" ]] && echo " FILE: $TASK_FILE"
sep
echo
cat "$ROLE_FILE"
echo

if [[ -n "$TASK_FILE" ]]; then
  sep
  echo " TASK CONTEXT ($TASK_ID)"
  sep
  echo
  cat "$TASK_FILE"
  echo
fi

if [[ -n "$CHAT_FILE" && -f "$CHAT_FILE" ]]; then
  sep
  echo " RECENT CHAT (last $CHAT_TAIL_LINES)"
  sep
  echo
  "$SCRIPT_DIR/chat.sh" view "$TASK_ID" | tail -n "$CHAT_TAIL_LINES"
  echo
fi

if [[ "$ROLE" == "coordinator" ]]; then
  sep
  echo " BOARD"
  sep
  echo
  [[ -f "$BOARD_FILE" ]] && cat "$BOARD_FILE"
  echo
fi

sep
echo " PRD (reference)"
sep
echo
echo "See: $PRD_FILE"
echo "(역할 세션 시작 시 PRD.md 를 직접 읽어 관련 섹션을 확인하세요.)"
echo
