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
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHAT_DIR="$REPO_ROOT/.harness/chat"
VALID_TYPES=(request dispatch question answer report deliver handoff error note)

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage:
  $0 append <task-id> <from> <to> <type> <message...>
  $0 view   <task-id>
  $0 tail   <task-id>
  $0 raw    <task-id>

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
  local msg="$*"
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

cmd="${1:-}"
shift || true
case "$cmd" in
  append) cmd_append "$@" ;;
  view)   cmd_view "$@" ;;
  tail)   cmd_tail "$@" ;;
  raw)    cmd_raw "$@" ;;
  ""|-h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
