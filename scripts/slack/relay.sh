#!/usr/bin/env bash
# slack/relay.sh — Phase 4 C: Slack → Coordinator 세션 중계 데몬.
#
# 동작:
#   1. slack/listen.sh 를 N초마다 polling 해서 봇 멘션 메시지 수신.
#   2. 메시지에서 task-id 추출 (본문 "T### " 패턴 또는 활성 task 1개 fallback).
#   3. 그 task 의 handles 파일에서 coordinator handle 조회.
#   4. 'orca terminal send --terminal <handle> --text <msg> --enter' 로 주입.
#   5. 봇 멘션 토큰 (<@Uxxx>) 과 선행 "T###" 는 제거해서 자연스러운 명령만 주입.
#
# 사용:
#   relay.sh start      # setsid+nohup 백그라운드
#   relay.sh stop       # PID 파일 기반 종료
#   relay.sh status     # 돌고 있는지 확인
#   relay.sh once       # 1 사이클만 (디버깅)
#
# 상태 파일:
#   .harness/coord/relay.pid        — 데몬 PID
#   .harness/coord/relay.cursor     — 마지막으로 처리한 Slack ts
#   .harness/coord/relay.log        — 데몬 로그

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
if [[ "$GIT_COMMON_DIR" = /* || "$GIT_COMMON_DIR" =~ ^[A-Z]:/ ]]; then
  MAIN_REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  MAIN_REPO_ROOT="$REPO_ROOT"
fi

[[ -f "$MAIN_REPO_ROOT/.env" ]] && { set -a; source "$MAIN_REPO_ROOT/.env"; set +a; }

COORD_DIR="$MAIN_REPO_ROOT/.harness/coord"
CHAT_DIR="$MAIN_REPO_ROOT/.harness/chat"
TASKS_DIR="$MAIN_REPO_ROOT/.harness/tasks"
PID_FILE="$COORD_DIR/relay.pid"
CURSOR_FILE="$COORD_DIR/relay.cursor"
LOG_FILE="$COORD_DIR/relay.log"
POLL_INTERVAL="${SLACK_RELAY_POLL_INTERVAL:-5}"
LISTENER="$SCRIPT_DIR/listen.sh"
BOT_ID_CACHE="$COORD_DIR/bot_id.txt"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "→ $*"; }
log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" ; }

mkdir -p "$COORD_DIR"

# ─────────────────────────────────────────────────────────────
# task-id → coordinator handle (handles 파일 마지막 coordinator 라인)
# ─────────────────────────────────────────────────────────────
coord_handle_for() {
  local task_id="$1"
  local hf="$CHAT_DIR/${task_id}.handles"
  [[ -f "$hf" ]] || return 1
  grep '"role":"coordinator"' "$hf" | tail -1 \
    | sed -nE 's/.*"handle"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p'
}

# 활성 task 1개면 그 id, 아니면 빈 문자열 (여러 개면 명시 요구)
single_active_task() {
  local ids=()
  shopt -s nullglob
  for f in "$TASKS_DIR"/T[0-9][0-9][0-9]-*.md; do
    local st
    st="$(awk '/^status:/{sub("^status: *",""); sub(/[[:space:]]+#.*/,""); print; exit}' "$f")"
    [[ "$st" == "merged" || "$st" == "dropped" ]] && continue
    local base; base="$(basename "$f" .md)"
    ids+=("${base%%-*}")
  done
  [[ ${#ids[@]} -eq 1 ]] && echo "${ids[0]}" || echo ""
}

# 메시지 본문에서 task-id 추출 ("T### ..." 형태). 못 찾으면 fallback.
extract_task_id() {
  local text="$1"
  local maybe
  maybe=$(echo "$text" | grep -oE '\bT[0-9]{3}\b' | head -1)
  if [[ -n "$maybe" ]]; then
    echo "$maybe"
  else
    single_active_task
  fi
}

# 메시지에서 봇 멘션 토큰 (<@Uxxx>) 과 선행 T### 제거
clean_text() {
  local text="$1"
  local bot_id=""
  [[ -f "$BOT_ID_CACHE" ]] && bot_id="$(cat "$BOT_ID_CACHE")"
  if [[ -n "$bot_id" ]]; then
    text="$(echo "$text" | sed -E "s/<@${bot_id}>//g")"
  fi
  text="$(echo "$text" | sed -E 's/^[[:space:]]*T[0-9]{3}[[:space:]]+//')"
  text="$(echo "$text" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
  echo "$text"
}

# ─────────────────────────────────────────────────────────────
# 1 사이클 — 새 메시지 처리
# ─────────────────────────────────────────────────────────────
run_once() {
  local cursor
  cursor="$(cat "$CURSOR_FILE" 2>/dev/null || echo "0")"
  local msgs
  msgs="$("$LISTENER" --oldest "$cursor" --limit 20 2>/dev/null || true)"
  [[ -z "$msgs" ]] && return 0

  local last_ts="$cursor"
  while IFS=$'\t' read -r ts user text; do
    [[ -z "$ts" ]] && continue
    # cursor 와 같거나 더 오래된 메시지는 skip (안전망)
    if [[ "$ts" == "$cursor" ]]; then continue; fi

    local task_id
    task_id="$(extract_task_id "$text")"
    if [[ -z "$task_id" ]]; then
      log "SKIP (no task-id): ts=$ts user=$user text='${text:0:80}'"
      last_ts="$ts"; continue
    fi

    local handle
    handle="$(coord_handle_for "$task_id")" || handle=""
    if [[ -z "$handle" ]]; then
      log "SKIP (no coord handle for $task_id): ts=$ts user=$user"
      last_ts="$ts"; continue
    fi

    local body
    body="$(clean_text "$text")"
    [[ -z "$body" ]] && { log "SKIP (empty after clean): ts=$ts"; last_ts="$ts"; continue; }

    log "RELAY → $task_id (handle=${handle:0:20}…) user=$user body='${body:0:120}'"
    if ! orca terminal send --terminal "$handle" --text "$body" --enter --wait-submit 10 --json >/dev/null 2>&1; then
      log "  ⚠ orca terminal send 실패 (handle 죽었을 수 있음)"
    fi

    last_ts="$ts"
  done <<< "$msgs"

  if [[ "$last_ts" != "$cursor" ]]; then
    echo "$last_ts" > "$CURSOR_FILE"
    log "cursor → $last_ts"
  fi
}

# ─────────────────────────────────────────────────────────────
# 데몬 모드
# ─────────────────────────────────────────────────────────────
run_daemon() {
  log "slack-relay 시작 (poll=${POLL_INTERVAL}s)"
  while true; do
    run_once || log "run_once error (계속)"
    sleep "$POLL_INTERVAL"
  done
}

cmd_start() {
  if [[ -f "$PID_FILE" ]]; then
    local pid; pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      info "이미 실행 중 (pid=$pid). stop 먼저 하세요."
      return 1
    fi
    rm -f "$PID_FILE"
  fi

  [[ -n "${SLACK_BOT_TOKEN:-}" && -n "${SLACK_CHANNEL_ID:-}" ]] \
    || die "SLACK_BOT_TOKEN/SLACK_CHANNEL_ID 미설정 (.env)"

  info "slack-relay 백그라운드 시작..."
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup "$0" __daemon >> "$LOG_FILE" 2>&1 < /dev/null &
  else
    nohup "$0" __daemon >> "$LOG_FILE" 2>&1 < /dev/null &
  fi
  local pid=$!
  disown 2>/dev/null || true
  echo "$pid" > "$PID_FILE"
  info "pid=$pid, log=$LOG_FILE"
}

cmd_stop() {
  if [[ ! -f "$PID_FILE" ]]; then info "(실행 중 아님)"; return 0; fi
  local pid; pid=$(cat "$PID_FILE")
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    info "stopped (pid=$pid)"
  else
    info "(stale pid file)"
  fi
  rm -f "$PID_FILE"
}

cmd_status() {
  if [[ -f "$PID_FILE" ]]; then
    local pid; pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "running (pid=$pid)"
      echo "cursor: $(cat "$CURSOR_FILE" 2>/dev/null || echo '(none)')"
      echo "log tail:"
      tail -5 "$LOG_FILE" 2>/dev/null || true
      return 0
    fi
    rm -f "$PID_FILE"
  fi
  echo "not running"
}

cmd="${1:-}"
case "$cmd" in
  start)    cmd_start ;;
  stop)     cmd_stop ;;
  status)   cmd_status ;;
  once)     run_once ;;
  __daemon) run_daemon ;;
  ""|-h|--help)
    sed -n '2,/^$/p' "$0" | sed 's/^# *//' ;;
  *) echo "Unknown: $cmd" >&2; exit 1 ;;
esac
