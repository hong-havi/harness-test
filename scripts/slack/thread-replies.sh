#!/usr/bin/env bash
# slack/thread-replies.sh — 특정 스레드의 새 reply 메시지 조회
#
# 사용:
#   thread-replies.sh --thread <ts> [--oldest <ts>] [--limit 20]
#
# 출력: "<ts>\t<user>\t<text>" 라인 (가장 오래된 것부터, 봇 메시지·parent 제외)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

die() { echo "ERROR: $*" >&2; exit 1; }

THREAD_TS=""
OLDEST="0"
LIMIT="20"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --thread) THREAD_TS="$2"; shift 2 ;;
    --oldest) OLDEST="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ -n "$THREAD_TS" ]] || die "--thread 필요"
[[ -n "${SLACK_BOT_TOKEN:-}" && -n "${SLACK_CHANNEL_ID:-}" ]] || die "SLACK token/channel 미설정"

# 봇 ID 캐시
BOT_ID_CACHE="$REPO_ROOT/.harness/coord/bot_id.txt"
if [[ ! -f "$BOT_ID_CACHE" ]]; then
  mkdir -p "$(dirname "$BOT_ID_CACHE")"
  curl -sS -H "Authorization: Bearer $SLACK_BOT_TOKEN" https://slack.com/api/auth.test \
    | PYTHONUTF8=1 PYTHONIOENCODING=utf-8 python -c "import json,sys; print(json.load(sys.stdin)['user_id'])" > "$BOT_ID_CACHE"
fi
BOT_ID="$(cat "$BOT_ID_CACHE")"

RESPONSE="$(curl -sS \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  "https://slack.com/api/conversations.replies?channel=${SLACK_CHANNEL_ID}&ts=${THREAD_TS}&oldest=${OLDEST}&limit=${LIMIT}")"

echo "$RESPONSE" | THREAD="$THREAD_TS" OLDEST="$OLDEST" BOT_ID="$BOT_ID" PYTHONUTF8=1 PYTHONIOENCODING=utf-8 python -c "
import json, sys, os
bot_id = os.environ['BOT_ID']
thread_ts = os.environ['THREAD']
oldest = os.environ['OLDEST']
data = json.load(sys.stdin)
if not data.get('ok'):
    print('ERROR:', data.get('error', 'unknown'), file=sys.stderr)
    sys.exit(1)
msgs = data.get('messages', [])
# parent 메시지(thread_ts == ts) 는 제외. oldest 이후, 봇 메시지 제외.
for m in msgs:
    ts = m.get('ts', '')
    if ts == thread_ts:
        continue
    # oldest 비교 (float)
    try:
        if float(ts) <= float(oldest):
            continue
    except Exception:
        pass
    if m.get('user') == bot_id or m.get('bot_id'):
        continue
    text = m.get('text', '').replace('\n', ' ')
    user = m.get('user', 'unknown')
    print(f'{ts}\t{user}\t{text}')
"
