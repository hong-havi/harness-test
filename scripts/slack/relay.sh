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

# ─────────────────────────────────────────────────────────────
# 메타 명령 처리 (Coordinator 안 거침, relay 가 직접 Slack 에 답)
# 지원: status, help, list
# ─────────────────────────────────────────────────────────────
SENDER="$SCRIPT_DIR/send.sh"

post_slack() {
  local text="$1" thread="${2:-}"
  if [[ -n "$thread" ]]; then
    "$SENDER" --text "$text" --thread "$thread" >/dev/null 2>&1 || true
  else
    "$SENDER" --text "$text" >/dev/null 2>&1 || true
  fi
}

# body 가 메타 명령이면 처리하고 0 리턴, 아니면 1
handle_meta_command() {
  local body="$1" thread_ts="$2"
  local cmd
  cmd="$(echo "$body" | awk '{print tolower($1)}')"
  case "$cmd" in
    status|상태)
      log "META: status"
      local out
      out="$("$MAIN_REPO_ROOT/scripts/harness-status.sh" 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g')"
      post_slack "\`\`\`\n$out\n\`\`\`" "$thread_ts"
      return 0 ;;
    help|도움말|헬프)
      log "META: help"
      post_slack "*harness-bot 명령* _(모두 봇 멘션 필요)_
*조회*
• \`status\` — 활성 task + 세션 요약
• \`list\` — 활성 task 테이블
• \`help\` — 이 메시지

*task 라이프사이클*
• \`new <slug> <요구사항...>\` — 새 task 생성 + Coordinator 자동 띄움
   예: \`@bot new me-logout 회원 /me 페이지에 로그아웃 버튼\`
   긴 요구사항은 \`.harness/requests/<slug>.md\` 로 저장 후 \`new <slug>\` 만.
• \`drop T### --yes\` — task 폐기 (\`--yes\` 명시 필수)

*Coordinator 중계*
• \`T### <명령>\` — 그 task Coordinator 에 메시지 주입 (예: \`T020 merge\`)
• 활성 task 1개면 \`T###\` 생략 가능" "$thread_ts"
      return 0 ;;
    list|목록)
      log "META: list"
      local out
      out="$("$MAIN_REPO_ROOT/scripts/tasks.sh" list 2>&1)"
      post_slack "\`\`\`\n$out\n\`\`\`" "$thread_ts"
      return 0 ;;
    new)
      # 형식: new <slug> <요구사항...>
      local rest slug req
      rest="$(echo "$body" | sed -E 's/^[[:space:]]*(new|생성)[[:space:]]+//I')"
      slug="$(echo "$rest" | awk '{print $1}')"
      req="$(echo "$rest" | awk '{$1=""; sub(/^[[:space:]]+/,""); print}')"
      log "META: new slug=$slug req='${req:0:80}'"
      if [[ -z "$slug" || ! "$slug" =~ ^[a-z0-9-]+$ ]]; then
        post_slack "⚠️ \`new\` 사용법: \`@bot new <kebab-slug> <요구사항...>\`
slug 은 kebab-case 소문자+숫자+하이픈만 허용. 예:
    @bot new me-logout-button 회원 /me 페이지에 로그아웃 버튼 추가
요구사항이 길면 \`.harness/requests/<slug>.md\` 에 저장하고 \`@bot new <slug>\` 만 보내도 자동 매칭됨." "$thread_ts"
        return 0
      fi
      local out
      if [[ -n "$req" ]]; then
        out="$("$MAIN_REPO_ROOT/scripts/tasks.sh" new "$slug" "$req" 2>&1)"
      else
        out="$("$MAIN_REPO_ROOT/scripts/tasks.sh" new "$slug" 2>&1)"
      fi
      # 결과에서 task-id 추출
      local tid
      tid="$(echo "$out" | grep -oE 'T[0-9]{3}' | head -1)"
      # 요약만 보내기 — 전체 로그는 길고 Slack 가독성 낮음
      local tail_lines
      tail_lines="$(echo "$out" | tail -15)"
      if [[ -n "$tid" ]] && echo "$out" | grep -q "Coordinator 세션 띄움"; then
        post_slack "✅ *$tid* ($slug) 생성 + Coordinator 세션 뜸. 체인 진행 중.
\`\`\`
$tail_lines
\`\`\`" "$thread_ts"
      else
        post_slack "⚠️ task 생성 중 문제 가능. 로그 끝:
\`\`\`
$tail_lines
\`\`\`" "$thread_ts"
      fi
      return 0 ;;
    drop|폐기)
      # 형식: drop T### [--yes]
      local tid confirm
      tid="$(echo "$body" | grep -oE '\bT[0-9]{3}\b' | head -1)"
      confirm="$(echo "$body" | grep -oE '\-\-yes|yes|확인' | head -1)"
      log "META: drop tid=$tid confirm=$confirm"
      if [[ -z "$tid" ]]; then
        post_slack "⚠️ \`drop\` 사용법: \`@bot drop T### --yes\`" "$thread_ts"
        return 0
      fi
      if [[ -z "$confirm" ]]; then
        post_slack "⚠️ *$tid* drop 은 되돌릴 수 없습니다. 진짜 폐기하려면 \`@bot drop $tid --yes\` 로 다시 보내주세요." "$thread_ts"
        return 0
      fi
      local out
      out="$("$MAIN_REPO_ROOT/scripts/tasks.sh" drop "$tid" --yes 2>&1)"
      post_slack "🗑 *$tid* drop 완료.
\`\`\`
$(echo "$out" | tail -8)
\`\`\`" "$thread_ts"
      return 0 ;;
  esac
  return 1
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

    local body
    body="$(clean_text "$text")"
    [[ -z "$body" ]] && { log "SKIP (empty after clean): ts=$ts"; last_ts="$ts"; continue; }

    # 메타 명령 (status/help/list) 먼저 처리 — 활성 task 없어도 응답.
    if handle_meta_command "$body" "$ts"; then
      last_ts="$ts"; continue
    fi

    local task_id
    task_id="$(extract_task_id "$text")"
    if [[ -z "$task_id" ]]; then
      log "SKIP (no task-id, no meta): ts=$ts user=$user text='${text:0:80}'"
      post_slack "⚠️ task-id 없이 명령을 받았습니다. 활성 task 가 여러 개거나 없을 때는 \`T### <명령>\` 으로 명시해주세요. \`help\` 로 사용법 확인." "$ts"
      last_ts="$ts"; continue
    fi

    local handle
    handle="$(coord_handle_for "$task_id")" || handle=""
    if [[ -z "$handle" ]]; then
      log "SKIP (no coord handle for $task_id): ts=$ts user=$user"
      post_slack "⚠️ $task_id 의 Coordinator 세션을 찾지 못했습니다 (아직 안 떴거나 crash). \`coord-recover.sh $task_id\` 로 재시작하세요." "$ts"
      last_ts="$ts"; continue
    fi

    log "RELAY → $task_id (handle=${handle:0:20}…) user=$user body='${body:0:120}'"
    if ! orca terminal send --terminal "$handle" --text "$body" --enter --wait-submit 10 --json >/dev/null 2>&1; then
      log "  ⚠ orca terminal send 실패 (handle 죽었을 수 있음)"
      post_slack "⚠️ $task_id Coordinator 터미널에 메시지 주입 실패 (handle=${handle:0:20}…). crash 가능성." "$ts"
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
