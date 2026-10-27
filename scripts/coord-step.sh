#!/usr/bin/env bash
# coord-step.sh — Phase 4: Coordinator 세션이 받은 orchestration 메시지 1건을 처리.
#
# 사용: $0 handle <msg-json>
#   <msg-json> 은 orca orchestration check --wait --json 응답에서 받은 단일 메시지의 JSON 문자열.
#
# worker_done:
#   payload 의 taskId/dispatchId/outcome/summary 로 handles 역매핑 → 역할 전환.
# question / escalation / heartbeat:
#   stdout 에 요약 출력 후 Coordinator (claude 세션) 가 다음 액션 결정하도록 넘김.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
if [[ "$GIT_COMMON_DIR" = /* || "$GIT_COMMON_DIR" =~ ^[A-Z]:/ ]]; then
  MAIN_REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  MAIN_REPO_ROOT="$REPO_ROOT"
fi

CHAT_DIR="$MAIN_REPO_ROOT/.harness/chat"
TASKS_DIR="$MAIN_REPO_ROOT/.harness/tasks"
WORKTREES_DIR="$MAIN_REPO_ROOT/.worktrees"

# .env 로드 (HARNESS_DEFAULT_AGENT 등)
if [[ -f "$MAIN_REPO_ROOT/.env" ]]; then
  set -a; source "$MAIN_REPO_ROOT/.env"; set +a
fi

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "→ $*"; }

# ─────────────────────────────────────────────────────────────
# JSON 파싱 (grep + sed) — 작은 의존성
# ─────────────────────────────────────────────────────────────

# payload 는 JSON 안에 escaped string 으로 들어있음. 두 번째 레벨에서 파싱.
extract_type() {
  echo "$1" | grep -oE '"type"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/'
}

# payload JSON 문자열 안에서 key 추출 (escaped quotes)
extract_payload_field() {
  local msg="$1" key="$2"
  echo "$msg" | grep -oE "\\\\\"$key\\\\\":[[:space:]]*\\\\\"[^\\\\]+\\\\\"" | head -1 \
    | sed -E 's/.*\\"([^\\]+)\\".*/\1/'
}

# ─────────────────────────────────────────────────────────────
# handles 역매핑: dispatch_id → task_id (harness) / handle / role
# ─────────────────────────────────────────────────────────────
find_task_by_dispatch() {
  local dispatch_id="$1"
  [[ -z "$dispatch_id" ]] && return 1
  for h in "$CHAT_DIR"/*.handles; do
    [[ -f "$h" ]] || continue
    if grep -q "\"dispatch_id\":\"$dispatch_id\"" "$h"; then
      basename "$h" .handles
      return 0
    fi
  done
  return 1
}

# task.md frontmatter 필드 추출
get_fm() {
  local file="$1" key="$2"
  awk -v k="$key" '
    /^---/ { fm = !fm; next }
    fm && $0 ~ "^"k":" {
      sub("^"k": *", "", $0)
      sub(/[[:space:]]+#.*$/, "", $0)
      sub(/^"|"$/, "", $0)
      sub(/[[:space:]]+$/, "", $0)
      print
      exit
    }
  ' "$file"
}

# task-id → task.md 경로 (main)
task_file_main() {
  local id="$1"
  find "$TASKS_DIR" -maxdepth 1 -name "${id}-*.md" | head -1
}

# task-id → live task.md (worktree 우선)
live_task_file() {
  local id="$1"
  local main_f; main_f="$(task_file_main "$id")"
  [[ -z "$main_f" ]] && return 1
  local slug; slug="$(basename "$main_f" .md)"; slug="${slug#*-}"
  local live="$WORKTREES_DIR/${id}-${slug}/.harness/tasks/${id}-${slug}.md"
  [[ -f "$live" ]] && echo "$live" || echo "$main_f"
}

# required_roles 파싱
list_roles() {
  local f="$1"
  awk '
    /^required_roles:/ { b=1; next }
    /^[a-zA-Z_]+:/ { b=0 }
    b && /^[[:space:]]*#/ { next }
    b && /role:/ {
      sub(/.*role: */, "")
      sub(/,.*/, "")
      sub(/[}].*/, "")
      gsub(/[[:space:]]/, "")
      print
    }
  ' "$f"
}

# required_roles 에서 current 뒤에 오는 role
next_role() {
  local f="$1" current="$2"
  local roles found=0
  roles="$(list_roles "$f")"
  while IFS= read -r r; do
    if [[ $found -eq 1 ]]; then echo "$r"; return 0; fi
    [[ "$r" == "$current" ]] && found=1
  done <<< "$roles"
  return 1
}

# ─────────────────────────────────────────────────────────────
# worker_done 처리
# ─────────────────────────────────────────────────────────────
handle_worker_done() {
  local msg="$1"
  local dispatch_id outcome summary task_id

  dispatch_id="$(extract_payload_field "$msg" dispatchId)"
  outcome="$(extract_payload_field "$msg" outcome)"
  summary="$(extract_payload_field "$msg" summary)"

  info "worker_done: dispatch=$dispatch_id outcome=$outcome"

  task_id="$(find_task_by_dispatch "$dispatch_id")" || {
    info "⚠ dispatch_id=$dispatch_id → task 역매핑 실패. handles 파일 확인."
    return 1
  }
  info "  task=$task_id"

  # handles 에서 해당 라인 찾아 handle + role 추출 + settled 마킹
  local handles_file="$CHAT_DIR/$task_id.handles"
  local line handle role agent
  line="$(grep "\"dispatch_id\":\"$dispatch_id\"" "$handles_file" | tail -1)"
  handle="$(echo "$line"  | sed -nE 's/.*"handle":"([^"]+)".*/\1/p')"
  role="$(echo "$line"    | sed -nE 's/.*"role":"([^"]+)".*/\1/p')"
  agent="$(echo "$line"   | sed -nE 's/.*"agent":"([^"]+)".*/\1/p')"

  # 터미널 close (worker 세션 정리)
  if [[ -n "$handle" ]]; then
    orca terminal close --terminal "$handle" --json >/dev/null 2>&1 || true
    info "  worker 터미널 close: $handle"
  fi

  # role_history append
  local hist="$CHAT_DIR/$task_id.role-history.jsonl"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"role\":\"$role\",\"outcome\":\"$outcome\",\"dispatch\":\"$dispatch_id\",\"summary\":\"${summary//\"/\\\"}\"}" >> "$hist"

  # failed → 사용자 결정 필요. ask 로 중계.
  if [[ "$outcome" == "failed" ]]; then
    info "  outcome=failed. 사용자 결정 필요 (rework / drop)."
    "$SCRIPT_DIR/chat.sh" append "$task_id" "$role" coordinator handoff "FAILED: $summary" >/dev/null 2>&1 || true
    # ask 는 Coordinator agent 세션이 담당 — stdout 으로 지시만 출력.
    echo "ACTION: ask-user T=$task_id msg='$role 실패: $summary'"
    return 0
  fi

  # 다음 role 찾기
  local f next
  f="$(live_task_file "$task_id")" || die "live task.md 없음: $task_id"
  next="$(next_role "$f" "$role")" || true

  if [[ -z "$next" ]]; then
    info "  모든 required_roles 소진. task 완료."
    "$SCRIPT_DIR/chat.sh" append "$task_id" "$role" coordinator deliver "task $task_id 완료 (최종 role: $role)" >/dev/null 2>&1 || true
    echo "ACTION: task-complete T=$task_id"
    return 0
  fi

  # current_role 갱신
  sed -i.bak "s|^current_role: .*|current_role: $next|" "$f"
  rm -f "$f.bak"
  info "  current_role: $role → $next"

  "$SCRIPT_DIR/chat.sh" append "$task_id" "$role" "$next" handoff "advance: $role → $next" >/dev/null 2>&1 || true

  # 다음 worker spawn
  local slug wt_abs run_id
  slug="$(get_fm "$f" slug)"
  wt_abs="$WORKTREES_DIR/${task_id}-${slug}"
  run_id="$(get_fm "$f" run_id)"
  [[ -z "$run_id" ]] && run_id="$(sed -nE 's/.*"run_id":"([^"]+)".*/\1/p' "$handles_file" | tail -1)"

  local wt_orca="$wt_abs"
  if command -v cygpath >/dev/null 2>&1; then
    wt_orca="$(cygpath -m "$wt_abs")"
  fi

  info "  worker-start: $next (agent=$agent)"
  if "$SCRIPT_DIR/orca/worker-start.sh" "$task_id" "$next" "$wt_orca" "$agent" "$run_id" ""; then
    echo "ACTION: spawned T=$task_id role=$next"
  else
    echo "ACTION: spawn-failed T=$task_id role=$next"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────
# question / escalation — stdout 요약만. Coordinator 가 처리.
# ─────────────────────────────────────────────────────────────
handle_question() {
  local msg="$1"
  local body sender
  body="$(extract_payload_field "$msg" body)"
  sender="$(extract_payload_field "$msg" senderId)"
  echo "ACTION: question sender=$sender body='$body'"
}

handle_escalation() {
  local msg="$1"
  local body
  body="$(extract_payload_field "$msg" body)"
  echo "ACTION: escalation body='$body'"
}

# ─────────────────────────────────────────────────────────────
# Entry
# ─────────────────────────────────────────────────────────────
cmd="${1:-}"
case "$cmd" in
  handle)
    msg="${2:?msg JSON required}"
    type="$(extract_type "$msg")"
    case "$type" in
      worker_done) handle_worker_done "$msg" ;;
      question)    handle_question "$msg" ;;
      escalation)  handle_escalation "$msg" ;;
      heartbeat)   echo "ACTION: heartbeat" ;;
      *)           echo "ACTION: unknown type=$type" ;;
    esac
    ;;
  *) echo "Usage: $0 handle <msg-json>" >&2; exit 1 ;;
esac
