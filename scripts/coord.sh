#!/usr/bin/env bash
# coord.sh — Coordinator 세션 메인 루프
#
# Slack #harness-coord 를 polling 하며 봇 멘션 메시지를 분류·디스패치.
# 상태는 .harness/coord/state.json 에 영속 — 재시작 시 복구.
#
# 명령:
#   coord.sh start            # 메인 루프 (foreground, Ctrl+C 로 종료)
#   coord.sh step             # 1회 iteration (디버깅용)
#   coord.sh status           # state.json 요약
#
# 봇에게 전달하는 Slack 명령 포맷 (user 가 @harnessbot 멘션 후):
#   new <slug>                — 새 task 생성 + planner 자동 spawn
#   advance <task-id>          — 다음 역할로 전환
#   advance <task-id> succeeded|failed  — outcome 명시 (qa/reviewer)
#   status                     — 활성 task 목록
#   help                       — 이 안내

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

COORD_DIR="$REPO_ROOT/.harness/coord"
STATE_FILE="$COORD_DIR/state.json"
DECISIONS_FILE="$COORD_DIR/decisions.jsonl"
POLL_INTERVAL="${COORD_POLL_INTERVAL:-10}"   # seconds

mkdir -p "$COORD_DIR"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[coord] $*"; }
log_decision() {
  local event="$1" body="$2"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"$event\",\"body\":\"$body\"}" >> "$DECISIONS_FILE"
}

# ─────────────────────────────────────────────────────────────────────
# State 조작 (python 으로 atomic 쓰기)
# ─────────────────────────────────────────────────────────────────────
state_init() {
  if [[ ! -f "$STATE_FILE" ]]; then
    cat > "$STATE_FILE" <<EOF
{
  "schema": 1,
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "slack_cursor": "0",
  "active_tasks": [],
  "inbox": []
}
EOF
    info "fresh state.json 생성"
  else
    info "state.json 로드"
  fi
}

state_get() {
  # STATE 와 KEY 를 env 로 전달 (bash 가 msys /d/ 를 python 에 넘길 때 fail — cygpath 로 변환)
  local pf="$STATE_FILE"
  command -v cygpath >/dev/null 2>&1 && pf="$(cygpath -m "$pf")"
  STATE="$pf" KEY="$1" python -c "import json,os; print(json.load(open(os.environ['STATE'])).get(os.environ['KEY'], ''))"
}

state_set_cursor() {
  local new_cursor="$1"
  local pf="$STATE_FILE"
  command -v cygpath >/dev/null 2>&1 && pf="$(cygpath -m "$pf")"
  STATE="$pf" CURSOR="$new_cursor" python -c "
import json, os, time
p = os.environ['STATE']
with open(p) as f: s = json.load(f)
s['slack_cursor'] = os.environ['CURSOR']
s['updated_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
tmp = p + '.tmp'
with open(tmp, 'w') as f: json.dump(s, f, indent=2, ensure_ascii=False)
os.replace(tmp, p)
"
}

# ─────────────────────────────────────────────────────────────────────
# Slack 응답 유틸
# ─────────────────────────────────────────────────────────────────────
reply() {
  local body="$1"
  "$SCRIPT_DIR/slack/send.sh" --text "$body" >/dev/null 2>&1 || true
}

# ─────────────────────────────────────────────────────────────────────
# 명령 디스패치
# ─────────────────────────────────────────────────────────────────────
# 입력: user_text (봇 멘션 제거된 명령부)
# 수행 후 Slack 에 결과 응답
handle_command() {
  local user_text="$1"
  # 멘션 패턴 제거: <@U...> 공백
  local cmd
  cmd="$(echo "$user_text" | sed -E 's|<@[A-Z0-9]+>||g' | sed -E 's|^ +||;s| +$||')"

  info "명령 수신: $cmd"
  log_decision "command_received" "$cmd"

  case "$cmd" in
    "" )
      reply "💬 비어있는 명령. \`help\` 로 사용법 확인."
      ;;
    "help")
      reply "📘 *하네스 Coordinator 명령*
\`new <slug> [자연어 설명...]\` — 새 task 생성. 설명 생략 시 \`.harness/requests/<slug>.md\` 자동 로드
\`advance <task-id>\` — 다음 역할로 (커밋 유무로 추론)
\`advance <task-id> succeeded|failed\` — qa/reviewer outcome 명시
\`rework <task-id> <role>\` — 지정 역할로 되돌리고 재 spawn (fail 복구용)
\`spawn <task-id> [role]\` — 현재 또는 지정 역할 agent 재 spawn (복구용)
\`merge <task-id>\` — reviewer 수동 호출 (reviewer agent 가 못했을 때)
\`status\` — 활성 task 목록
\`help\` — 이 안내

👥 *역할 (8개)* — task 당 planner 가 \`required_roles\` 로 선언
• \`coordinator\` — user 유일 접점. dispatch·리포팅 (저 입니다)
• \`planner\` — 요구를 명세로 분해 + required_roles 지정
• \`architect\` — 엔티티/API 계약·보안 설계
• \`designer\` — Figma MCP + apps/web 코드 뼈대 (UI 필요 시)
• \`backend\` — apps/api 구현 + DB 핸들
• \`frontend\` — apps/web 구현
• \`qa\` — docker up + 수용 기준 전수 UAT (fail → rework)
• \`reviewer\` — 보안/누수/성능 리뷰 + rebase + ff-only merge

🔄 *진행 흐름* (자동 체인)
\`planner → architect → [designer?] → backend → frontend → qa → reviewer → merged\`

ℹ️ 각 역할의 상세 지침은 \`.harness/roles/<role>.md\`"
      ;;
    "status")
      local out
      out="$(./scripts/tasks.sh list 2>&1)"
      reply "📊 *Status*
\`\`\`
$out
\`\`\`"
      ;;
    "new "*)
      local rest="${cmd#new }"
      local slug description
      slug="$(echo "$rest" | awk '{print $1}')"
      # slug 뒤 모든 토큰 = description (자연어)
      description="$(echo "$rest" | awk '{for(i=2;i<=NF;i++) printf "%s%s", (i>2?" ":""), $i; print ""}')"
      [[ -n "$slug" ]] || { reply "⚠ slug 없음. 예: \`new remember-me 로그인에 remember me 체크박스 추가\`"; return; }
      local out
      if [[ -n "$description" ]]; then
        out="$("$SCRIPT_DIR/tasks.sh" new "$slug" "$description" 2>&1)" && ok=1 || ok=0
      else
        out="$("$SCRIPT_DIR/tasks.sh" new "$slug" 2>&1)" && ok=1 || ok=0
      fi
      if [[ $ok -eq 1 ]]; then
        reply "✅ *task 생성 완료* (\`$slug\`)${description:+
> $description}
\`\`\`
$(echo "$out" | tail -12)
\`\`\`"
        log_decision "task_created" "$slug${description:+ — $description}"
      else
        reply "❌ task 생성 실패:
\`\`\`
$out
\`\`\`"
      fi
      ;;
    "advance "*)
      local args="${cmd#advance }"
      # args: "<task-id>" 또는 "<task-id> succeeded|failed"
      local tid outcome=""
      tid="$(echo "$args" | awk '{print $1}')"
      outcome="$(echo "$args" | awk '{print $2}')"
      [[ -n "$tid" ]] || { reply "⚠ task-id 없음. 예: \`advance T001\`"; return; }
      local out
      local flags=()
      [[ -n "$outcome" ]] && flags+=(--outcome "$outcome")
      if out="$("$SCRIPT_DIR/tasks.sh" advance "$tid" "${flags[@]}" 2>&1)"; then
        reply "✅ *advance $tid* ${outcome:+(outcome=$outcome)}
\`\`\`
$(echo "$out" | tail -15)
\`\`\`"
        log_decision "task_advanced" "$tid ${outcome:-auto}"
      else
        reply "❌ advance 실패:
\`\`\`
$out
\`\`\`"
      fi
      ;;
    "rework "*)
      local args="${cmd#rework }"
      local tid trole
      tid="$(echo "$args" | awk '{print $1}')"
      trole="$(echo "$args" | awk '{print $2}')"
      [[ -n "$tid" && -n "$trole" ]] || { reply "⚠ 사용법: \`rework <task-id> <role>\` (예: \`rework T003 frontend\`)"; return; }
      local out
      if out="$("$SCRIPT_DIR/tasks.sh" rework "$tid" "$trole" 2>&1)"; then
        reply "🔄 *rework $tid → $trole*
\`\`\`
$(echo "$out" | tail -15)
\`\`\`"
        log_decision "task_rework" "$tid → $trole"
      else
        reply "❌ rework 실패:
\`\`\`
$out
\`\`\`"
      fi
      ;;
    "spawn "*)
      local args="${cmd#spawn }"
      local tid trole
      tid="$(echo "$args" | awk '{print $1}')"
      trole="$(echo "$args" | awk '{print $2}')"
      [[ -n "$tid" ]] || { reply "⚠ 사용법: \`spawn <task-id> [role]\` (role 생략시 현재 current_role 사용)"; return; }
      local out
      if out="$("$SCRIPT_DIR/tasks.sh" spawn "$tid" "$trole" 2>&1)"; then
        reply "🚀 *spawn $tid${trole:+ $trole}*
\`\`\`
$(echo "$out" | tail -8)
\`\`\`"
        log_decision "task_spawn" "$tid ${trole:-current}"
      else
        reply "❌ spawn 실패:
\`\`\`
$out
\`\`\`"
      fi
      ;;
    "merge "*)
      local tid="${cmd#merge }"
      tid="$(echo "$tid" | awk '{print $1}')"
      [[ -n "$tid" ]] || { reply "⚠ 사용법: \`merge <task-id>\`"; return; }
      local out
      if out="$("$SCRIPT_DIR/tasks.sh" merge "$tid" 2>&1)"; then
        reply "🎉 *merged $tid*
\`\`\`
$(echo "$out" | tail -20)
\`\`\`"
        log_decision "task_merged" "$tid"
      else
        reply "❌ merge 실패:
\`\`\`
$out
\`\`\`"
      fi
      ;;
    *)
      reply "⚠ 알 수 없는 명령: \`$cmd\`
\`help\` 로 사용법 확인."
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────
# task 의 활성(마지막) agent 터미널 handle 조회 — .harness/chat/<id>.handles 마지막 줄
# ─────────────────────────────────────────────────────────────────────
active_terminal_for_task() {
  local id="$1"
  local hf="$REPO_ROOT/.harness/chat/${id}.handles"
  [[ -f "$hf" ]] || return 1
  tail -1 "$hf" | awk -F'"handle":"' '{print $2}' | awk -F'"' '{print $1}'
}

# ─────────────────────────────────────────────────────────────────────
# 활성 task 들의 Slack 스레드 reply 를 폴링 → 해당 agent 터미널에 주입
# ─────────────────────────────────────────────────────────────────────
poll_task_threads() {
  shopt -s nullglob
  for slack_file in "$REPO_ROOT"/.harness/chat/T[0-9][0-9][0-9].slack; do
    local id thread_ts cursor_file cursor
    id="$(basename "$slack_file" .slack)"
    thread_ts="$(cat "$slack_file")"
    cursor_file="$COORD_DIR/thread-cursor-${id}.txt"
    cursor="$thread_ts"
    [[ -f "$cursor_file" ]] && cursor="$(cat "$cursor_file")"

    local last_processed="$cursor"
    while IFS=$'\t' read -r ts user text; do
      [[ -z "$ts" ]] && continue
      info "[$id] user reply @ $ts: $(echo "$text" | cut -c1-80)"
      # 1) chat log 에 answer 로 기록
      "$SCRIPT_DIR/chat.sh" append "$id" user "coord" answer "$text" >/dev/null 2>&1 || true
      # 2) 현재 활성 agent 터미널에 주입
      local handle
      if handle="$(active_terminal_for_task "$id")" && [[ -n "$handle" ]]; then
        info "[$id] → agent 터미널 ($handle) 에 주입"
        orca terminal send --terminal "$handle" --text "$text" --enter --json >/dev/null 2>&1 \
          || info "[$id] ⚠ terminal send 실패 (handle 만료 가능)"
      else
        info "[$id] ⚠ 활성 터미널 없음 — chat log 에만 기록"
      fi
      log_decision "thread_reply_relayed" "$id ts=$ts user=$user"
      last_processed="$ts"
    done < <("$SCRIPT_DIR/slack/thread-replies.sh" --thread "$thread_ts" --oldest "$cursor" --limit 20)

    if [[ "$last_processed" != "$cursor" ]]; then
      echo "$last_processed" > "$cursor_file"
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────
# 1 iteration: top-level 명령 + 스레드 reply 모두 처리
# ─────────────────────────────────────────────────────────────────────
run_once() {
  local cursor
  cursor="$(state_get slack_cursor)"
  [[ -z "$cursor" || "$cursor" == "None" ]] && cursor="0"

  # 1) 채널 top-level 메시지 (봇 명령)
  local last_ts="$cursor"
  while IFS=$'\t' read -r ts user text; do
    [[ -z "$ts" ]] && continue
    info "msg from $user @ $ts: $(echo "$text" | cut -c1-80)"
    handle_command "$text"
    last_ts="$ts"
  done < <("$SCRIPT_DIR/slack/listen.sh" --oldest "$cursor" --limit 20)

  if [[ "$last_ts" != "$cursor" ]]; then
    state_set_cursor "$last_ts"
  fi

  # 2) 활성 task 들의 스레드 reply → agent 로 전달
  poll_task_threads
}

cmd_start() {
  # PID lock — 중복 실행 방지 (여러 coord 가 돌면 Slack 응답 중복됨)
  local lockfile="$COORD_DIR/coord.pid"
  if [[ -f "$lockfile" ]]; then
    local old_pid
    old_pid="$(cat "$lockfile" 2>/dev/null || echo 0)"
    if [[ -n "$old_pid" && "$old_pid" -gt 0 ]] && kill -0 "$old_pid" 2>/dev/null; then
      die "coord 이미 실행 중 (PID $old_pid). 'kill $old_pid' 로 종료 후 재시작하거나, coord.sh stop 사용."
    fi
    info "stale lock 발견 (PID $old_pid 안 돌음) → 제거"
    rm -f "$lockfile"
  fi
  echo "$$" > "$lockfile"
  trap 'rm -f "$lockfile"; exit 0' INT TERM EXIT

  state_init
  info "listen 루프 시작 (PID $$, interval=${POLL_INTERVAL}s). Ctrl+C 로 종료."
  reply "🤖 coordinator 세션 시작 (PID $$) — \`help\` 로 명령 확인"
  log_decision "coord_started" "pid=$$"

  while true; do
    run_once || info "⚠ iteration 실패 (계속)"
    sleep "$POLL_INTERVAL"
  done
}

cmd_stop() {
  local lockfile="$COORD_DIR/coord.pid"
  [[ -f "$lockfile" ]] || { echo "실행 중인 coord 없음 (lock 파일 없음)"; return; }
  local pid
  pid="$(cat "$lockfile")"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" && echo "coord PID $pid 종료 요청"
    sleep 1
  else
    echo "lock 파일의 PID $pid 가 안 돌고 있음 (stale)"
  fi
  rm -f "$lockfile"
}

cmd_step() {
  state_init
  info "단일 iteration 실행"
  run_once
}

cmd_status() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "state.json 없음 — coord 가 아직 시작 안 됨"
    return
  fi
  echo "=== state.json ==="
  cat "$STATE_FILE"
  echo ""
  echo "=== 최근 결정 (last 10) ==="
  [[ -f "$DECISIONS_FILE" ]] && tail -10 "$DECISIONS_FILE" || echo "(없음)"
}

sub="${1:-}"
shift || true
case "$sub" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  step)   cmd_step ;;
  status) cmd_status ;;
  ""|-h|--help|help)
    cat <<EOF
Usage: $0 <start|stop|step|status>

start   메인 루프 (foreground). PID lock 으로 중복 실행 방지.
stop    실행 중인 coord 종료 (lock 파일의 PID kill)
step    1회 iteration (디버깅)
status  state.json + decisions.jsonl 요약

Slack 봇 멘션으로 명령 전송 — @harness-bot <command>
명령: new <slug>, advance <task-id> [succeeded|failed], rework <task-id> <role>, status, help
EOF
    ;;
  *) echo "Unknown: $sub" >&2; exit 1 ;;
esac
