#!/usr/bin/env bash
# coord-recover.sh — Phase 4 B: Coordinator 세션 crash 복구.
#
# 사용: $0 <task-id>
#
# 동작:
#   1. task.md frontmatter 에서 run_id, current_role, slug 복구
#   2. .worktrees/<id>-<slug> 경로 확인
#   3. .harness/chat/<id>.handles 마지막 non-coordinator 라인에서 agent 복구
#   4. coord-launch.sh 재호출 (current_role 을 FIRST_ROLE 로)
#
# 중복 가드:
#   - 기존 Coordinator 세션이 떠있으면 close 요청.
#   - processed-dispatches 파일은 유지 — 이미 처리한 dispatch 가 재배포돼도 skip.

set -euo pipefail

TASK_ID="${1:?task-id required (e.g., T019)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
if [[ "$GIT_COMMON_DIR" = /* || "$GIT_COMMON_DIR" =~ ^[A-Z]:/ ]]; then
  MAIN_REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  MAIN_REPO_ROOT="$REPO_ROOT"
fi

TASKS_DIR="$MAIN_REPO_ROOT/.harness/tasks"
CHAT_DIR="$MAIN_REPO_ROOT/.harness/chat"
WORKTREES_DIR="$MAIN_REPO_ROOT/.worktrees"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "→ $*"; }

task_file="$(find "$TASKS_DIR" -maxdepth 1 -name "${TASK_ID}-*.md" | head -1)"
[[ -n "$task_file" ]] || die "task.md 없음: $TASK_ID (완료/drop 됐을 수 있음)"

get_fm() {
  local key="$1"
  awk -v k="$key" '
    /^---/ { fm = !fm; next }
    fm && $0 ~ "^"k":" {
      sub("^"k": *", "", $0); sub(/[[:space:]]+#.*$/, "", $0)
      sub(/^"|"$/, "", $0); sub(/[[:space:]]+$/, "", $0)
      print; exit
    }
  ' "$task_file"
}

RUN_ID="$(get_fm run_id)"
CURRENT_ROLE="$(get_fm current_role)"
SLUG="$(get_fm slug)"
STATUS="$(get_fm status)"

[[ -n "$RUN_ID" ]]        || die "task.md 에 run_id 없음. recovery 불가 (tasks.sh new 가 기록해야 함)."
[[ -n "$CURRENT_ROLE" ]]  || die "task.md 에 current_role 없음."
[[ -n "$SLUG" ]]          || die "task.md 에 slug 없음."
[[ "$STATUS" != "merged" && "$STATUS" != "dropped" ]] \
  || die "task 상태가 $STATUS — recovery 불필요."

WORKTREE="$WORKTREES_DIR/${TASK_ID}-${SLUG}"
[[ -d "$WORKTREE" ]] || die "worktree 없음: $WORKTREE"

# agent 복구 — handles 마지막 worker (non-coordinator) 라인에서
handles_file="$CHAT_DIR/${TASK_ID}.handles"
AGENT=""
if [[ -f "$handles_file" ]]; then
  AGENT="$(grep -v '"role":"coordinator"' "$handles_file" | tail -1 \
    | sed -nE 's/.*"agent"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
fi
[[ -n "$AGENT" ]] || AGENT="${HARNESS_DEFAULT_AGENT:-claude}"

info "Recovery 정보"
info "  TASK_ID       = $TASK_ID"
info "  RUN_ID        = $RUN_ID"
info "  CURRENT_ROLE  = $CURRENT_ROLE"
info "  WORKTREE      = $WORKTREE"
info "  AGENT (worker) = $AGENT"

# 기존 Coordinator 세션이 있으면 close
if [[ -f "$handles_file" ]]; then
  while IFS= read -r line; do
    coord_handle="$(echo "$line" | sed -nE 's/.*"handle"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
    [[ -n "$coord_handle" ]] && orca terminal close --terminal "$coord_handle" --json >/dev/null 2>&1 || true
  done < <(grep '"role":"coordinator"' "$handles_file")
  info "  기존 Coordinator 세션 close 완료"
fi

info "Coordinator 재시작 (current_role=$CURRENT_ROLE 로 재진입)..."
"$SCRIPT_DIR/coord-launch.sh" "$TASK_ID" "$RUN_ID" "$WORKTREE" "$AGENT" "$CURRENT_ROLE" "(recovery) task.md 참조"
