#!/usr/bin/env bash
# orca/spawn.sh — 역할 agent 세션 spawn 디스패처
#
# 사용:
#   ./scripts/orca/spawn.sh <task-id> [role]
#
# role 생략 시 task.md 의 current_role 사용.
# task.md 의 required_roles[].agent 매핑을 읽어 적절한 어댑터 호출.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TASKS_DIR="$REPO_ROOT/.harness/tasks"
AGENTS_DIR="$REPO_ROOT/scripts/agents"
WORKTREES_DIR="$REPO_ROOT/.worktrees"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "→ $*"; }

TASK_ID="${1:?Usage: $0 <task-id> [role]}"
ROLE="${2:-}"

TASK_FILE=$(find "$TASKS_DIR" -maxdepth 1 -name "${TASK_ID}-*.md" 2>/dev/null | head -1)
[[ -n "$TASK_FILE" ]] || die "task 파일 없음: $TASK_ID"

# current_role 조회 (role 미지정 시)
if [[ -z "$ROLE" ]]; then
  ROLE=$(awk '
    /^---/ { fm = !fm; next }
    fm && /^current_role:/ {
      sub(/^current_role: */, "")
      sub(/ *#.*$/, "")
      gsub(/[[:space:]]+$/, "")
      print
      exit
    }
  ' "$TASK_FILE")
  [[ -n "$ROLE" ]] || die "current_role 을 task.md 에서 읽지 못함"
fi

# required_roles 에서 role 의 agent 추출
# 라인 예: "  - { role: planner,    agent: claude }"
# 주석(#) 라인은 스킵
AGENT=$(awk -v target="$ROLE" '
  /^required_roles:/ { in_block=1; next }
  /^[a-zA-Z_]+:/ { in_block=0 }
  in_block && /^[[:space:]]*#/ { next }
  in_block && /role:/ {
    # role 추출
    line = $0
    sub(/.*role: */, "", line)
    role_val = line
    sub(/,.*/, "", role_val)
    sub(/[}].*/, "", role_val)
    gsub(/[[:space:]]/, "", role_val)
    if (role_val == target) {
      # agent 추출
      ag = $0
      sub(/.*agent: */, "", ag)
      sub(/,.*/, "", ag)
      sub(/[}].*/, "", ag)
      gsub(/[[:space:]]/, "", ag)
      print ag
      exit
    }
  }
' "$TASK_FILE")

[[ -n "$AGENT" ]] || die "role '$ROLE' 의 agent 매핑을 task.md 에서 찾지 못함"

# 어댑터 존재 확인
ADAPTER="$AGENTS_DIR/${AGENT}.sh"
[[ -x "$ADAPTER" ]] || die "agent 어댑터 없음 또는 실행 불가: $ADAPTER"

# worktree 경로 (slug 포함)
SLUG=$(basename "$TASK_FILE" .md)        # T001-signup-api
SLUG="${SLUG#*-}"                         # signup-api
WORKTREE_PATH="$WORKTREES_DIR/${TASK_ID}-${SLUG}"
[[ -d "$WORKTREE_PATH" ]] || die "worktree 경로 없음: $WORKTREE_PATH"

# Orca 는 Windows 에서 "D:/path/..." 포맷(mixed, drive letter 대문자, forward slash)을 요구함.
# bash 의 /d/... 는 selector_not_found 로 실패. cygpath 로 변환.
if command -v cygpath >/dev/null 2>&1; then
  WORKTREE_PATH_ORCA="$(cygpath -m "$WORKTREE_PATH")"
else
  WORKTREE_PATH_ORCA="$WORKTREE_PATH"
fi

info "spawn: task=$TASK_ID role=$ROLE agent=$AGENT worktree=$WORKTREE_PATH_ORCA"

# 어댑터 호출 (Orca 호환 포맷 전달)
exec "$ADAPTER" "$TASK_ID" "$ROLE" "$WORKTREE_PATH_ORCA"
