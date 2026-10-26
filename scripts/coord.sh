#!/usr/bin/env bash
# coord.sh — Phase 4: Coordinator 세션
#
# 핵심 변경 (Phase 3 → 4):
#   - Slack 폴링만 하던 구조 → orca orchestration check --wait 루프
#   - worker_done 받으면 다음 역할 worker-start 호출 (자동 체인)
#   - question/escalation 은 Slack 포스트
#   - Slack 명령은 짧은 subcycle 로 처리
#
# 참조: .harness/COORDINATOR.md

set -uo pipefail
# set -e 는 의도적으로 제외 — orchestration 호출 중 non-fatal 에러에 전체 종료 방지

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

COORD_DIR="$REPO_ROOT/.harness/coord"
STATE_FILE="$COORD_DIR/state.json"
DECISIONS_FILE="$COORD_DIR/decisions.jsonl"
POLL_SLACK_EVERY="${COORD_SLACK_POLL_INTERVAL:-15}"   # seconds, check 사이에
CHECK_TIMEOUT_MS="${COORD_CHECK_TIMEOUT_MS:-30000}"   # 30s per cycle

mkdir -p "$COORD_DIR"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[coord] $*"; }
log_decision() {
  local event="$1" body="$2"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"$event\",\"body\":\"$body\"}" >> "$DECISIONS_FILE"
}

# ─────────────────────────────────────────────────────────────
# State 조작
# ─────────────────────────────────────────────────────────────
state_init() {
  if [[ ! -f "$STATE_FILE" ]]; then
    cat > "$STATE_FILE" <<EOF
{
  "schema": 2,
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "slack_cursor": "0",
  "active_tasks": [],
  "inbox": []
}
EOF
    info "fresh state.json 생성 (schema v2)"
  else
    info "state.json 로드"
  fi
}

state_get() {
  local pf="$STATE_FILE"
  command -v cygpath >/dev/null 2>&1 && pf="$(cygpath -m "$pf")"
  STATE="$pf" KEY="$1" PYTHONUTF8=1 PYTHONIOENCODING=utf-8 python -c "
import json, os
d = json.load(open(os.environ['STATE']))
v = d.get(os.environ['KEY'], '')
print(v if not isinstance(v, (list,dict)) else json.dumps(v, ensure_ascii=False))
"
}

state_set_cursor() {
  local new_cursor="$1"
  local pf="$STATE_FILE"
  command -v cygpath >/dev/null 2>&1 && pf="$(cygpath -m "$pf")"
  STATE="$pf" CURSOR="$new_cursor" PYTHONUTF8=1 PYTHONIOENCODING=utf-8 python -c "
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

reply() {
  local body="$1"
  "$SCRIPT_DIR/slack/send.sh" --text "$body" >/dev/null 2>&1 || true
}

# ─────────────────────────────────────────────────────────────
# 핵심: orchestration 메시지 처리
# ─────────────────────────────────────────────────────────────
# worker_done 처리: 다음 역할 worker-start
# question 처리: Slack 미러 (chat.sh 가 자동으로 함)
# escalation: Slack 긴급 알림
handle_orchestration_msg() {
  local msg_json="$1"
  local msg_type delivery_id task_id dispatch_id outcome summary

  msg_type="$(echo "$msg_json" | grep -oE '"type":[[:space:]]*"[a-z_]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
  delivery_id="$(echo "$msg_json" | grep -oE '"deliveryId":[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
  # task-id/dispatch-id 는 payload JSON string 안에 있음 ("payload":"{\"taskId\":\"...\",\"dispatchId\":\"...\"}")
  task_id="$(echo "$msg_json" | grep -oE '\\"taskId\\":[[:space:]]*\\"[^\\]+\\"' | head -1 | sed -E 's/.*\\"([^\\]+)\\".*/\1/')"
  dispatch_id="$(echo "$msg_json" | grep -oE '\\"dispatchId\\":[[:space:]]*\\"[^\\]+\\"' | head -1 | sed -E 's/.*\\"([^\\]+)\\".*/\1/')"

  info "message type=$msg_type task=$task_id dispatch=$dispatch_id delivery=$delivery_id"

  case "$msg_type" in
    worker_done)
      outcome="$(echo "$msg_json" | awk -F'"' '/"outcome":/{print $4; exit}')"
      summary="$(echo "$msg_json" | awk -F'"' '/"summary":/{print $4; exit}')"
      log_decision "worker_done" "task=$task_id outcome=$outcome summary=${summary:0:100}"

      # task 식별: dispatch_id 로 state 에서 조회 (여기선 간단화 — orca worker-list 로 상호 참조)
      # 다음 역할 결정 로직을 위해 task.md 를 참조
      local harness_task_id
      harness_task_id="$(find_harness_task_by_dispatch "$dispatch_id")"
      if [[ -z "$harness_task_id" ]]; then
        info "⚠ dispatch_id → harness task 매핑 실패 (state.json 확인 필요)"
        return
      fi

      if [[ "$outcome" == "succeeded" ]]; then
        advance_to_next_role "$harness_task_id"
      elif [[ "$outcome" == "failed" ]]; then
        reply "⚠️ *${harness_task_id}* — ${msg_type} *failed*: ${summary:-no summary}
사용자 결정 필요. \`rework\` 또는 \`spawn\` 명령으로."
      fi
      ;;
    question)
      local body
      body="$(echo "$msg_json" | awk -F'"' '/"body":/{print $4; exit}')"
      reply "❓ task 질문: ${body:-(empty)}
이 스레드에 답하면 터미널에 자동 주입됩니다."
      log_decision "question" "task=$task_id body=${body:0:100}"
      ;;
    escalation)
      reply "🚨 *escalation* task=$task_id: $(echo "$msg_json" | awk -F'"' '/"body":/{print $4; exit}')"
      log_decision "escalation" "task=$task_id"
      ;;
    heartbeat)
      # 기본은 noop. live 상태 확인에 활용.
      :
      ;;
    *)
      info "unknown msg type: $msg_type (payload 로그)"
      ;;
  esac
}

# dispatch_id 로 .harness/tasks/*.md 를 뒤져서 T### 찾기
# (state.json 에 확실한 매핑을 유지하면 더 빠르지만 fallback 구현)
find_harness_task_by_dispatch() {
  local disp="$1"
  grep -l "\"dispatch_id\":\"$disp\"" "$REPO_ROOT"/.harness/chat/T*.handles 2>/dev/null | head -1 | \
    sed -E 's|.*/T([0-9]+)\.handles|T\1|'
}

advance_to_next_role() {
  local tid="$1"
  info "advance 시도: $tid"

  # live task.md 에서 current_role 다음 역할 조회
  local live_f main_f slug f
  main_f="$(find "$REPO_ROOT/.harness/tasks" -maxdepth 1 -name "${tid}-*.md" | head -1)"
  if [[ -z "$main_f" ]]; then
    info "⚠ task.md 없음: $tid"
    return
  fi
  slug="$(basename "$main_f" .md)"; slug="${slug#*-}"
  live_f="$REPO_ROOT/.worktrees/${tid}-${slug}/.harness/tasks/${tid}-${slug}.md"
  [[ -f "$live_f" ]] || live_f="$main_f"
  f="$live_f"

  local current next
  current="$(awk -F': *' '/^current_role:/{print $2; exit}' "$f" | tr -d '"')"
  # 다음 역할 추출
  next="$(awk -v cur="$current" '
    /^required_roles:/ { in_block=1; next }
    /^[a-zA-Z_]+:/ { in_block=0 }
    in_block && /^[[:space:]]*#/ { next }
    in_block && /role:/ {
      sub(/.*role: */, ""); sub(/,.*/, ""); sub(/[}].*/, ""); gsub(/[[:space:]]/, "")
      if (found) { print; exit }
      if ($0 == cur) found=1
    }
  ' "$f")"

  if [[ -z "$next" ]]; then
    info "$tid: 모든 역할 소진. reviewer 가 merge 호출했으면 cleanup."
    reply "🎉 *${tid}* 모든 역할 완료"
    return
  fi

  # current_role 를 next 로 업데이트 + 커밋 (live 쪽)
  sed -i.bak "s|^current_role: .*|current_role: $next|" "$f" && rm -f "${f}.bak"
  info "  $tid: $current → $next"
  reply "🔄 *${tid}*: $current → $next 전환 중..."

  # 다음 role 의 agent 조회
  local agent
  agent="$(awk -v r="$next" '
    /^required_roles:/ { in_block=1; next }
    /^[a-zA-Z_]+:/ { in_block=0 }
    in_block && /^[[:space:]]*#/ { next }
    in_block && /role:/ {
      line=$0
      sub(/.*role: */, "", line); r_val=line
      sub(/,.*/, "", r_val); sub(/[}].*/, "", r_val); gsub(/[[:space:]]/, "", r_val)
      if (r_val == r) {
        ag=$0; sub(/.*agent: */, "", ag); sub(/,.*/, "", ag); sub(/[}].*/, "", ag); gsub(/[[:space:]]/, "", ag)
        print ag; exit
      }
    }
  ' "$f")"
  [[ -n "$agent" ]] || { info "⚠ next role 의 agent 매핑 없음"; return; }

  # run_id 조회
  local run_id
  run_id="$(awk -F': *' '/^run_id:/{print $2; exit}' "$f" | tr -d '"')"

  # worktree 경로
  local wt_abs="$REPO_ROOT/.worktrees/${tid}-${slug}"

  # worker-start 호출 (background)
  info "  worker-start $next ($agent)..."
  local log="/tmp/coord-worker-${tid}-${next}.log"
  (
    setsid nohup "$SCRIPT_DIR/orca/worker-start.sh" "$tid" "$next" "$wt_abs" "$agent" "${run_id:-unknown}" "" \
      > "$log" 2>&1 < /dev/null &
    disown
  ) || true
  info "  spawn 발사됨 (log=$log)"
  log_decision "next_worker_started" "task=$tid role=$next agent=$agent"
}

# ─────────────────────────────────────────────────────────────
# Slack 명령 처리 (Phase 3 와 동일, 부분적 유지)
# ─────────────────────────────────────────────────────────────
# (옛 coord.sh 의 handle_command 를 그대로 유지 — new/status/rework/spawn/merge/drop/help)
handle_command() {
  local user_text="$1"
  local cmd
  cmd="$(echo "$user_text" | sed -E 's|<@[A-Z0-9]+>||g' | sed -E 's|^ +||;s| +$||')"
  info "slack cmd: $cmd"

  case "$cmd" in
    "")       reply "💬 비어있는 명령. \`help\` 확인." ;;
    "help")
      reply "📘 *하네스 Phase 4 Coordinator 명령*
\`new <slug> [--agent kiro|claude|codex] [자연어 설명]\` — 새 task (orchestration Run 생성 + planner 시작)
\`status\` — 활성 task 목록
\`rework <task-id> <role>\` — 지정 역할로 되돌리고 새 worker 시작
\`spawn <task-id> [role]\` — 수동 재 spawn (복구)
\`merge <task-id>\` — reviewer 승인 후 user 가 직접 호출
\`drop <task-id>\` — task 폐기 (worker-abandon + cleanup)
\`help\` — 이 안내

👥 *역할*: planner → architect → [designer?] → backend → frontend → qa → reviewer → merged (자동 체인)

Phase 4 변경: agent 는 \`orca orchestration worker-done\` 호출. advance 명령 제거됨."
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
      local agent_opt=""
      if [[ "$rest" =~ --agent[[:space:]]+([a-zA-Z0-9_-]+) ]]; then
        agent_opt="${BASH_REMATCH[1]}"
        rest="$(echo "$rest" | sed -E 's/--agent[[:space:]]+[a-zA-Z0-9_-]+//')"
      fi
      local slug description
      slug="$(echo "$rest" | awk '{print $1}')"
      description="$(echo "$rest" | awk '{for(i=2;i<=NF;i++) printf "%s%s", (i>2?" ":""), $i}' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
      [[ -n "$slug" ]] || { reply "⚠ 사용법: \`new <slug> [--agent ...] [설명]\`"; return; }
      local extra=() out ok=0
      [[ -n "$agent_opt" ]] && extra+=(--agent "$agent_opt")
      if [[ -n "$description" ]]; then
        out="$("$SCRIPT_DIR/tasks.sh" new "$slug" "${extra[@]}" "$description" 2>&1)" && ok=1
      else
        out="$("$SCRIPT_DIR/tasks.sh" new "$slug" "${extra[@]}" 2>&1)" && ok=1
      fi
      if [[ $ok -eq 1 ]]; then
        reply "✅ *task 생성* \`$slug\`${agent_opt:+ (agent=$agent_opt)}
\`\`\`
$(echo "$out" | tail -8)
\`\`\`"
        log_decision "task_created" "$slug agent=${agent_opt:-default}"
      else
        reply "❌ 실패:
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
      [[ -n "$tid" && -n "$trole" ]] || { reply "⚠ 사용법: \`rework <task-id> <role>\`"; return; }
      local out
      if out="$("$SCRIPT_DIR/tasks.sh" rework "$tid" "$trole" 2>&1)"; then
        reply "🔄 rework $tid → $trole 완료"
      else
        reply "❌ rework 실패:
\`\`\`
$out
\`\`\`"
      fi
      ;;
    "spawn "*)
      local args="${cmd#spawn }" tid trole
      tid="$(echo "$args" | awk '{print $1}')"
      trole="$(echo "$args" | awk '{print $2}')"
      [[ -n "$tid" ]] || { reply "⚠ 사용법: \`spawn <task-id> [role]\`"; return; }
      "$SCRIPT_DIR/tasks.sh" spawn "$tid" "$trole" >/dev/null 2>&1 \
        && reply "🚀 spawn $tid${trole:+ $trole}" \
        || reply "❌ spawn 실패"
      ;;
    "merge "*)
      local tid="${cmd#merge }"; tid="$(echo "$tid" | awk '{print $1}')"
      local out
      if out="$("$SCRIPT_DIR/tasks.sh" merge "$tid" 2>&1)"; then
        reply "🎉 merged $tid"
      else
        reply "❌ merge 실패:
\`\`\`
$out
\`\`\`"
      fi
      ;;
    "drop "*)
      local tid="${cmd#drop }"; tid="$(echo "$tid" | awk '{print $1}')"
      if "$SCRIPT_DIR/tasks.sh" drop "$tid" --yes >/dev/null 2>&1; then
        reply "🗑️ dropped $tid"
      else
        reply "❌ drop 실패"
      fi
      ;;
    *) reply "⚠ 알 수 없는 명령: \`$cmd\` (\`help\`)" ;;
  esac
}

poll_slack() {
  local cursor
  cursor="$(state_get slack_cursor)"
  [[ -z "$cursor" || "$cursor" == "None" ]] && cursor="0"
  local last_ts="$cursor"
  while IFS=$'\t' read -r ts user text; do
    [[ -z "$ts" ]] && continue
    handle_command "$text"
    last_ts="$ts"
  done < <("$SCRIPT_DIR/slack/listen.sh" --oldest "$cursor" --limit 20)
  if [[ "$last_ts" != "$cursor" ]]; then
    state_set_cursor "$last_ts"
  fi
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
cmd_start() {
  # lockfile 을 전역으로 (trap 에서 참조하므로 함수 범위 벗어나도 유효해야)
  LOCKFILE="$COORD_DIR/coord.pid"
  if [[ -f "$LOCKFILE" ]]; then
    local old_pid
    old_pid="$(cat "$LOCKFILE" 2>/dev/null || echo 0)"
    if [[ -n "$old_pid" && "$old_pid" -gt 0 ]] && kill -0 "$old_pid" 2>/dev/null; then
      die "coord 이미 실행 중 (PID $old_pid). 'coord.sh stop' 후 재시작."
    fi
    info "stale lock 제거 (PID $old_pid)"
    rm -f "$LOCKFILE"
  fi
  echo "$$" > "$LOCKFILE"
  trap 'rm -f "${LOCKFILE:-}"; exit 0' INT TERM EXIT

  state_init
  info "Phase 4 Coordinator 시작 (PID $$, check_timeout=${CHECK_TIMEOUT_MS}ms)"
  reply "🤖 Phase 4 coordinator up (PID $$) — \`help\` 로 명령 확인"
  log_decision "coord_started" "pid=$$"

  local last_slack_poll=0
  while true; do
    # orchestration check (block 함수) — 30초 안에 메시지 또는 timeout
    local check_resp
    check_resp="$(orca orchestration check \
      --wait --types "worker_done,question,escalation,heartbeat" \
      --timeout-ms "$CHECK_TIMEOUT_MS" --json 2>&1 || true)"
    # 메시지 있으면 처리, timeout 이면 건너뜀
    if echo "$check_resp" | grep -q '"type":'; then
      handle_orchestration_msg "$check_resp"
      local delivery_id
      delivery_id="$(echo "$check_resp" | awk -F'"' '/"deliveryId":/{print $4; exit}')"
      [[ -n "$delivery_id" ]] && orca orchestration check --ack "$delivery_id" --json >/dev/null 2>&1 || true
    fi

    # Slack 폴링 (매 반복마다 check 이 긴 timeout 가지므로 자연스럽게 interval)
    local now
    now=$(date +%s)
    if (( now - last_slack_poll >= POLL_SLACK_EVERY )); then
      poll_slack
      last_slack_poll=$now
    fi
  done
}

cmd_stop() {
  LOCKFILE="$COORD_DIR/coord.pid"
  [[ -f "$LOCKFILE" ]] || { echo "lock 없음"; return; }
  local pid
  pid="$(cat "$LOCKFILE")"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" && echo "coord PID $pid 종료 요청"; sleep 1
  else
    echo "stale PID $pid"
  fi
  rm -f "$LOCKFILE"
}

cmd_status() {
  [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "state.json 없음"
  echo ""
  echo "=== 최근 결정 ==="
  [[ -f "$DECISIONS_FILE" ]] && tail -10 "$DECISIONS_FILE" || echo "(없음)"
}

sub="${1:-}"; shift || true
case "$sub" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  ""|-h|--help|help)
    cat <<EOF
Usage: $0 <start|stop|status>

Phase 4 — orchestration check-wait 루프 기반 Coordinator.
자세한 설계는 .harness/COORDINATOR.md 참조.
EOF
    ;;
  *) echo "Unknown: $sub"; exit 1 ;;
esac
