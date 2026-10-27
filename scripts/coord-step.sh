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
# Orca 메시지 포맷이 변동 가능 — 여러 키 fallback (type / messageType / kind) +
# payload escaped 안쪽까지 체크.
extract_type() {
  local msg="$1" t
  # 1. top-level "type"
  t=$(echo "$msg" | grep -oE '"type"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
  # 2. "messageType"
  [[ -z "$t" ]] && t=$(echo "$msg" | grep -oE '"messageType"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
  # 3. "kind" (일부 orchestration 메시지)
  [[ -z "$t" ]] && t=$(echo "$msg" | grep -oE '"kind"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
  # 4. payload escaped 안의 type
  [[ -z "$t" ]] && t=$(echo "$msg" | grep -oE '\\\\"type\\\\":[[:space:]]*\\\\"[^\\\\]+\\\\"' | head -1 \
    | sed -E 's/.*\\"([^\\]+)\\".*/\1/')
  # 5. message.type (nested)
  [[ -z "$t" ]] && t=$(echo "$msg" | python -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    for path in [['type'], ['message','type'], ['result','type'], ['result','message','type']]:
        v = d
        for k in path:
            if isinstance(v, dict) and k in v: v = v[k]
            else: v = None; break
        if v: print(v); break
except Exception: pass
" 2>/dev/null)
  echo "$t"
}

# deliveryId 추출 — Coordinator 가 다음 check 호출에 --ack <id> 로 포함해야
# Orca 가 재배포를 멈춤. 추출 안 되면 빈 문자열.
extract_delivery_id() {
  echo "$1" | grep -oE '"deliveryId"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 \
    | sed -E 's/.*"([^"]+)"$/\1/'
}

# payload JSON 문자열 안에서 key 추출 (escaped quotes)
# payload 는 2단계 escape — "payload": "{\"key\":\"val\"}" 형태.
# 다중 fallback 로 다른 키명 시도 가능 (extract_body 가 호출).
extract_payload_field() {
  local msg="$1" key="$2"
  echo "$msg" | grep -oE "\\\\\"$key\\\\\":[[:space:]]*\\\\\"[^\\\\]+\\\\\"" | head -1 \
    | sed -E 's/.*\\"([^\\]+)\\".*/\1/'
}

# question/escalation 메시지의 "본문" 추출 — payload 키명이 orchestration
# 버전/명령에 따라 다를 수 있어 다중 fallback:
#   body, question, text, message, content
# 모두 실패하면 payload 통째 반환 (최소한 사용자가 뭔가 볼 수 있도록).
extract_body() {
  local msg="$1" v
  for k in body question text message content prompt; do
    v="$(extract_payload_field "$msg" "$k")"
    if [[ -n "$v" ]]; then echo "$v"; return 0; fi
  done
  # 최후: payload 전체 (escaped string). 디버그용.
  echo "$msg" | grep -oE '"payload"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 \
    | sed -E 's/.*"payload"[[:space:]]*:[[:space:]]*"(.+)"/\1/' | sed 's/\\n/\n/g; s/\\"/"/g' \
    | head -c 500
}

# 디버그 — 메시지 전체 JSON 을 /tmp 에 덤프 (--debug 환경변수)
dump_debug() {
  [[ -z "${HARNESS_COORD_DEBUG:-}" ]] && return 0
  local msg="$1" tag="${2:-msg}"
  local f="/tmp/coord-step-${tag}-$(date +%s%N).json"
  echo "$msg" > "$f"
  echo "DEBUG: dumped to $f" >&2
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

  # ─────────────────────────────────────────────────────────────
  # Idempotency 가드 — 같은 dispatch_id 를 두 번 처리하지 않는다.
  # Monitor dual-consumer 등으로 같은 worker_done 이 2회 이상 전달될 때,
  # worker-start 가 중복 호출되는 걸 막는다.
  # ─────────────────────────────────────────────────────────────
  local processed_file="$CHAT_DIR/$task_id.processed-dispatches"
  mkdir -p "$CHAT_DIR"
  if [[ -f "$processed_file" ]] && grep -qxF "$dispatch_id" "$processed_file"; then
    info "  ↩ dispatch $dispatch_id 이미 처리됨 → skip (중복 전달)"
    echo "ACTION: duplicate-skipped T=$task_id dispatch=$dispatch_id"
    return 0
  fi
  # 처리 시작 — dispatch_id 를 즉시 기록 (원자적 선점)
  echo "$dispatch_id" >> "$processed_file"

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

    # Phase 4 O: Slack 스레드에 명시적 완료 알림 포스트.
    # chat.sh deliver 가 자동 미러하지만, "✅ merged" 명확 메시지로 사용자 추적 쉽게.
    if [[ -n "${SLACK_BOT_TOKEN:-}" && -n "${SLACK_CHANNEL_ID:-}" && -f "$CHAT_DIR/$task_id.slack" ]]; then
      local merge_sha
      merge_sha="$(cd "$MAIN_REPO_ROOT" && git log --oneline -1 --grep="^${task_id} " 2>/dev/null | awk '{print $1}')"
      "$MAIN_REPO_ROOT/scripts/slack/send.sh" \
        --text "✅ *${task_id}* 완료 — merged${merge_sha:+ ($merge_sha)}. 모든 role 소진, Coordinator 종료." \
        --thread "$(cat "$CHAT_DIR/$task_id.slack")" >/dev/null 2>&1 || true
    fi

    # Phase 4 O: task 완료 자동 cleanup — task.md 가 archive 안 돼서 수동 cleanup 반복 결함.
    # reviewer 가 tasks.sh merge 호출했으면 main 쪽 task.md 가 archive 로 가야 함. 이중 체크:
    local main_task_md
    main_task_md="$(find "$TASKS_DIR" -maxdepth 1 -name "${task_id}-*.md" 2>/dev/null | head -1)"
    if [[ -f "$main_task_md" ]]; then
      info "  task.md archive 자동 이동: $main_task_md → .harness/archive/"
      mkdir -p "$MAIN_REPO_ROOT/.harness/archive"
      mv "$main_task_md" "$MAIN_REPO_ROOT/.harness/archive/"
      # chat 파일들 archive
      for suffix in jsonl slack role-history.jsonl; do
        [[ -f "$CHAT_DIR/${task_id}.${suffix}" ]] && mv "$CHAT_DIR/${task_id}.${suffix}" "$MAIN_REPO_ROOT/.harness/archive/"
      done
      rm -f "$CHAT_DIR/${task_id}.handles" "$CHAT_DIR/${task_id}.processed-dispatches"
      rm -f "$MAIN_REPO_ROOT/.harness/coord/relay-thread-${task_id}.cursor"
      # 자동 커밋 (hook 우회)
      (cd "$MAIN_REPO_ROOT" && git add -A && git -c core.hooksPath=/dev/null commit -m "${task_id} [harness]: auto-archive after task-complete" >/dev/null 2>&1) || true
    fi

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
# question / escalation — Slack 에 자동 포스트 (사용자 응답 받기 쉽게)
# ─────────────────────────────────────────────────────────────

# sender 의 dispatch_id 로 handles 에서 task-id 역매핑
# (worker 가 ask 호출하면 그 worker 의 dispatch_id 가 senderId 일 수 있음)
task_id_for_sender() {
  local sender="$1"
  [[ -z "$sender" ]] && return 1
  for h in "$CHAT_DIR"/*.handles; do
    [[ -f "$h" ]] || continue
    if grep -q "\"dispatch_id\":\"$sender\"" "$h"; then
      basename "$h" .handles; return 0
    fi
  done
  # 활성 task 1개 fallback
  local ids=()
  shopt -s nullglob
  for f in "$TASKS_DIR"/T[0-9][0-9][0-9]-*.md; do
    local st; st="$(awk '/^status:/{sub("^status: *",""); sub(/[[:space:]]+#.*/,""); print; exit}' "$f")"
    [[ "$st" == "merged" || "$st" == "dropped" ]] && continue
    local base; base="$(basename "$f" .md)"
    ids+=("${base%%-*}")
  done
  [[ ${#ids[@]} -eq 1 ]] && echo "${ids[0]}" || echo ""
}

post_slack_question() {
  local task_id="$1" body="$2" sender="$3" kind="${4:-question}"
  [[ -z "${SLACK_BOT_TOKEN:-}" || -z "${SLACK_CHANNEL_ID:-}" ]] && return 0
  local header="🔔 *응답 필요*"
  [[ "$kind" == "escalation" ]] && header="🚨 *긴급 — escalation*"
  local tid_hint=""
  [[ -n "$task_id" ]] && tid_hint=" — *$task_id*"
  # task 의 Slack 스레드로 reply (chat.sh 가 저장한 thread_ts 재사용)
  local thread_ts=""
  [[ -n "$task_id" && -f "$CHAT_DIR/$task_id.slack" ]] && thread_ts="$(cat "$CHAT_DIR/$task_id.slack")"
  local text="$header$tid_hint

$body

응답 방법:
• 스레드 reply 로 직접 답 (예: \`merge\`, \`no\`, \`rework\`) — 자동 인식
• 또는 \`@harness-bot ${task_id:-T###} <답>\`"
  if [[ -n "$thread_ts" ]]; then
    "$MAIN_REPO_ROOT/scripts/slack/send.sh" --text "$text" --thread "$thread_ts" >/dev/null 2>&1 || true
  else
    "$MAIN_REPO_ROOT/scripts/slack/send.sh" --text "$text" >/dev/null 2>&1 || true
  fi
}

handle_question() {
  local msg="$1"
  dump_debug "$msg" question
  local body sender task_id
  body="$(extract_body "$msg")"
  sender="$(extract_payload_field "$msg" senderId)"
  task_id="$(task_id_for_sender "$sender")" || task_id=""
  # body 가 비면 msg_json 통째를 raw dump 로 Slack 에 — 사용자가 raw 보고 응답 가능
  if [[ -z "$body" ]]; then
    body="(⚠️ 본문 추출 실패 — raw payload)
\`\`\`
$(echo "$msg" | head -c 1500)
\`\`\`"
  fi
  post_slack_question "$task_id" "$body" "$sender" question
  echo "ACTION: question T=${task_id:-?} sender=$sender body='${body:0:200}'"
}

handle_escalation() {
  local msg="$1"
  dump_debug "$msg" escalation
  local body sender task_id
  body="$(extract_body "$msg")"
  sender="$(extract_payload_field "$msg" senderId)"
  task_id="$(task_id_for_sender "$sender")" || task_id=""
  if [[ -z "$body" ]]; then
    body="(⚠️ 본문 추출 실패 — raw)
\`\`\`
$(echo "$msg" | head -c 1500)
\`\`\`"
  fi
  post_slack_question "$task_id" "$body" "$sender" escalation
  echo "ACTION: escalation T=${task_id:-?} body='${body:0:200}'"
}

# ─────────────────────────────────────────────────────────────
# Entry
# ─────────────────────────────────────────────────────────────
cmd="${1:-}"
case "$cmd" in
  handle)
    msg="${2:?msg JSON required}"
    type="$(extract_type "$msg")"
    delivery_id="$(extract_delivery_id "$msg")"
    case "$type" in
      worker_done) handle_worker_done "$msg" ;;
      question)    handle_question "$msg" ;;
      escalation)  handle_escalation "$msg" ;;
      heartbeat)   echo "ACTION: heartbeat" ;;
      *)
        # Unknown type — 메시지 포맷이 예상과 다름. Slack 에 raw 포스트해
        # 사용자가 수동 응답/판단 가능하도록. 활성 task 1개 fallback 적용.
        dump_debug "$msg" unknown
        task_id="$(single_active_task 2>/dev/null)" || task_id=""
        if [[ -n "${SLACK_BOT_TOKEN:-}" && -n "${SLACK_CHANNEL_ID:-}" ]]; then
          thread_ts=""
          [[ -n "$task_id" && -f "$CHAT_DIR/$task_id.slack" ]] && thread_ts="$(cat "$CHAT_DIR/$task_id.slack")"
          raw_dump="$(echo "$msg" | head -c 1500)"
          text="⚠️ *미인식 메시지 타입* $([ -n "$task_id" ] && echo "— *$task_id*")
coord-step.sh 가 type 추출 실패. raw 참고:
\`\`\`
$raw_dump
\`\`\`
사용자가 수동으로 Coordinator 세션에 응답하거나, 로그 확인 후 결정하세요."
          if [[ -n "$thread_ts" ]]; then
            "$MAIN_REPO_ROOT/scripts/slack/send.sh" --text "$text" --thread "$thread_ts" >/dev/null 2>&1 || true
          else
            "$MAIN_REPO_ROOT/scripts/slack/send.sh" --text "$text" >/dev/null 2>&1 || true
          fi
        fi
        echo "ACTION: unknown type=$type (Slack raw 포스트됨)"
        ;;
    esac
    # Coordinator 가 다음 check 에 --ack 로 포함해야 재배포 멈춤.
    # type 에 관계없이 (heartbeat 포함) delivery_id 가 있으면 ack 지시 출력.
    [[ -n "$delivery_id" ]] && echo "ACTION: ack delivery=$delivery_id"
    ;;
  *) echo "Usage: $0 handle <msg-json>" >&2; exit 1 ;;
esac
