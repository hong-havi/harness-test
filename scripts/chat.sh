#!/usr/bin/env bash
# chat.sh — task별 채팅 로그(JSONL)
#
# 서브커맨드:
#   append <task-id> <from> <to> <type> <message>
#   view   <task-id>              사람이 읽기 좋게
#   tail   <task-id>              tail -f
#   raw    <task-id>              원문 JSONL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# worktree 안에서 호출돼도 메인 레포 chat 디렉토리 사용 (단일 진실 소스)
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
if [[ "$GIT_COMMON_DIR" = /* || "$GIT_COMMON_DIR" =~ ^[A-Z]:/ ]]; then
  REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
CHAT_DIR="$REPO_ROOT/.harness/chat"
VALID_TYPES=(request dispatch question answer report deliver handoff error note)

# .env 로드 (SLACK_* 를 위해)
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage:
  $0 append <task-id> <from> <to> <type> <message...>
  $0 append <task-id> <from> <to> <type> --from <file>    # 긴 메시지(argv quoting 이슈 회피)
  $0 view       <task-id>
  $0 tail       <task-id>
  $0 raw        <task-id>
  $0 send-coord <task-id> <message...>    # task 의 Coordinator 세션에 메시지 주입 (수동 응답 등)

Valid types: ${VALID_TYPES[*]}
EOF
}

chat_file() {
  local id="$1"
  mkdir -p "$CHAT_DIR"
  echo "$CHAT_DIR/${id}.jsonl"
}

# JSON 문자열 escape (쌍따옴표, 역슬래시, 개행)
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

cmd_append() {
  local id="${1:-}" from="${2:-}" to="${3:-}" type="${4:-}"
  [[ -n "$id" && -n "$from" && -n "$to" && -n "$type" ]] || { usage; exit 1; }
  shift 4 || true
  # 긴 message 는 argv quoting 이슈로 깨질 수 있어 --from <file> 지원.
  local msg=""
  if [[ "${1:-}" == "--from" ]]; then
    [[ -n "${2:-}" && -f "$2" ]] || die "--from 뒤에 유효한 파일 경로 필요"
    msg="$(cat "$2")"
    shift 2
  else
    msg="$*"
  fi
  [[ -n "$msg" ]] || die "message 가 비어있음"

  local valid=0
  for t in "${VALID_TYPES[@]}"; do [[ "$t" == "$type" ]] && valid=1 && break; done
  [[ $valid -eq 1 ]] || die "invalid type: $type (allowed: ${VALID_TYPES[*]})"

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local esc
  esc="$(json_escape "$msg")"

  local line
  line="{\"ts\":\"${ts}\",\"task\":\"${id}\",\"from\":\"${from}\",\"to\":\"${to}\",\"type\":\"${type}\",\"body\":\"${esc}\"}"

  local f
  f="$(chat_file "$id")"
  echo "$line" >> "$f"
  echo "appended → $f"

  # Slack 미러 (토큰 있으면)
  slack_mirror "$id" "$from" "$to" "$type" "$msg" || true
}

# agent 가 one-liner 로 보낸 긴 리포트를 섹션/bullet 앞에서 자동 줄바꿈.
# 안전: 이미 \n 이 있는 메시지는 유지 (중복 삽입 없음 — sed 가 이전 \n 유지).
auto_newline_markdown() {
  local m="$1"
  # 중간에 섹션 헤더가 나타나면 그 앞에 두 줄 띄움
  m="$(printf '%s' "$m" | sed -E 's| (## [^#])|\n\n\1|g')"
  # bullet 앞에 한 줄 띄움 (• 또는 - 앞)
  m="$(printf '%s' "$m" | sed -E 's| (• )|\n\1|g; s| (- )|\n\1|g')"
  # 숫자 리스트도 (예: " 1. ", " 2. ")
  m="$(printf '%s' "$m" | sed -E 's| ([0-9]+\. )|\n\1|g')"
  printf '%s' "$m"
}

# 메시지 포맷 — type 별로 user 친화적인 헤더 + body
# role 명(from)을 메인으로 노출, type 별 이모지
format_slack_body() {
  local from="$1" to="$2" type="$3" msg="$4"
  # 긴 리포트 (deliver/question) 는 자동 섹션 줄바꿈
  case "$type" in
    deliver|question|answer|report) msg="$(auto_newline_markdown "$msg")" ;;
  esac
  local header
  case "$type" in
    request)
      header="📄 *User request*"
      ;;
    dispatch)
      header="➡️ *Dispatch* → \`${to}\`"
      ;;
    deliver)
      # from role 을 capitalize 해서 완료 리포트로
      local rcap="$(echo "${from:0:1}" | tr '[:lower:]' '[:upper:]')${from:1}"
      case "$from" in
        planner)   header="📝 *${rcap}* 완료" ;;
        architect) header="🏗️ *${rcap}* 완료" ;;
        designer)  header="🎨 *${rcap}* 완료" ;;
        backend)   header="💻 *${rcap}* 완료" ;;
        frontend)  header="🖥️ *${rcap}* 완료" ;;
        qa)        header="🧪 *${rcap}* 완료" ;;
        reviewer)  header="🔎 *${rcap}* 리뷰 완료" ;;
        *)         header="✅ *${rcap}* 완료" ;;
      esac
      ;;
    handoff)
      header="🔄 \`${from}\` → \`${to}\`"
      ;;
    question)
      header="❓ *질문* — \`${from}\` → \`${to}\` (답을 이 스레드에 reply)"
      ;;
    answer)
      header="💬 *${from}* 답변"
      ;;
    report)
      header="📊 *리포트*"
      ;;
    error)
      header="⚠️ *에러* — \`${from}\`"
      ;;
    note)
      header="ℹ️ _${from}_"
      ;;
    *)
      header="\`${from}\` → \`${to}\` (${type})"
      ;;
  esac
  printf '%s\n%s\n' "$header" "$msg"
}

# task 당 1 Slack thread. thread_ts 를 .harness/chat/<id>.slack 에 저장.
# 첫 메시지는 채널 최상위에, 이후는 thread reply.
slack_mirror() {
  local id="$1" from="$2" to="$3" type="$4" msg="$5"
  [[ -n "${SLACK_BOT_TOKEN:-}" && -n "${SLACK_CHANNEL_ID:-}" ]] || return 0

  local thread_file="$CHAT_DIR/${id}.slack"
  local thread_ts=""
  [[ -f "$thread_file" ]] && thread_ts="$(cat "$thread_file")"

  local body
  body="$(format_slack_body "$from" "$to" "$type" "$msg")"

  local new_ts
  if [[ -z "$thread_ts" ]]; then
    # 첫 메시지 — 채널 최상위에 task 헤더 포스트
    local header="📋 *${id}* 시작

${body}"
    new_ts="$("$SCRIPT_DIR/slack/send.sh" --text "$header" 2>/dev/null)" || return 0
    [[ -n "$new_ts" ]] || return 0
    echo "$new_ts" > "$thread_file"
    echo "slack: new thread $new_ts → $thread_file"
  else
    "$SCRIPT_DIR/slack/send.sh" --text "$body" --thread "$thread_ts" >/dev/null 2>&1 || true
    echo "slack: appended to thread $thread_ts"
  fi
}

cmd_view() {
  local id="${1:-}"
  [[ -n "$id" ]] || { usage; exit 1; }
  local f
  f="$(chat_file "$id")"
  [[ -f "$f" ]] || { echo "(no chat log for $id)"; return; }

  awk '
    BEGIN { FS="" }
    {
      # 매우 단순한 JSON 추출. complex escapes 는 무시.
      ts=""; from=""; to=""; type=""; body=""
      match($0, /"ts":"[^"]*"/); if (RLENGTH>0) { s=substr($0,RSTART+6,RLENGTH-7); ts=s }
      match($0, /"from":"[^"]*"/); if (RLENGTH>0) { s=substr($0,RSTART+8,RLENGTH-9); from=s }
      match($0, /"to":"[^"]*"/); if (RLENGTH>0) { s=substr($0,RSTART+6,RLENGTH-7); to=s }
      match($0, /"type":"[^"]*"/); if (RLENGTH>0) { s=substr($0,RSTART+8,RLENGTH-9); type=s }
      # body 는 뒤쪽에 있고 escape 포함. 간단히 끝부분까지.
      p = index($0, "\"body\":\"")
      if (p>0) {
        rest = substr($0, p+8)
        # 마지막 "}" 제거
        gsub(/"}$/, "", rest)
        # 간단한 unescape
        gsub(/\\n/, "\n  ", rest)
        gsub(/\\"/, "\"", rest)
        gsub(/\\\\/, "\\", rest)
        body = rest
      }
      printf "[%s] %s → %s (%s)\n  %s\n", ts, from, to, type, body
    }
  ' "$f"
}

cmd_tail() {
  local id="${1:-}"
  [[ -n "$id" ]] || { usage; exit 1; }
  local f
  f="$(chat_file "$id")"
  [[ -f "$f" ]] || { echo "(no chat log for $id, waiting...)"; touch "$f"; }
  tail -F "$f"
}

cmd_raw() {
  local id="${1:-}"
  [[ -n "$id" ]] || { usage; exit 1; }
  local f
  f="$(chat_file "$id")"
  [[ -f "$f" ]] && cat "$f" || echo "(no chat log for $id)"
}

# cmd_send_coord — task 의 Coordinator 세션에 메시지 주입 (수동 복구 / 응답 전달용)
# 사용: chat.sh send-coord <task-id> <message...>
# handles 파일에서 coordinator handle 찾아 orca terminal send 호출.
cmd_send_coord() {
  local id="${1:-}"
  shift || true
  local msg="$*"
  [[ -n "$id" && -n "$msg" ]] || { echo "Usage: chat.sh send-coord <task-id> <message...>" >&2; exit 1; }
  local hf="$CHAT_DIR/${id}.handles"
  [[ -f "$hf" ]] || { echo "ERROR: handles 파일 없음: $hf" >&2; exit 1; }
  local handle
  handle="$(grep '"role":"coordinator"' "$hf" | tail -1 \
    | sed -nE 's/.*"handle"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
  [[ -n "$handle" ]] || { echo "ERROR: coordinator handle 없음 (handles 에 coordinator 라인 없음)" >&2; exit 1; }
  echo "→ send to $id Coordinator (handle=${handle:0:20}…): '${msg:0:120}'"
  orca terminal send --terminal "$handle" --text "$msg" --enter --wait-submit 10 --json >/dev/null 2>&1 \
    && echo "✓ 전달 완료" \
    || { echo "⚠ 전달 실패 (handle 죽었을 수 있음 — coord-recover.sh $id 로 재시작)"; exit 1; }
}

cmd="${1:-}"
shift || true
case "$cmd" in
  append)     cmd_append "$@" ;;
  view)       cmd_view "$@" ;;
  tail)       cmd_tail "$@" ;;
  raw)        cmd_raw "$@" ;;
  send-coord) cmd_send_coord "$@" ;;
  ""|-h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
