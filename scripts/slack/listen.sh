#!/usr/bin/env bash
# slack/listen.sh — conversations.history 폴링. 봇 멘션 포함 메시지만 반환.
#
# 사용:
#   listen.sh --oldest <ts>     # ts 이후 메시지만 (최신에서 과거로 응답)
#   listen.sh --limit 20        # 기본
#   listen.sh --json            # 원 응답 그대로
#
# 출력 (기본): 각 라인에 "<ts>\t<user>\t<text(한줄로)>" (봇 멘션 필터링됨)
# 가장 오래된 것부터 (processing 순서)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "${SLACK_BOT_TOKEN:-}" && -n "${SLACK_CHANNEL_ID:-}" ]] || die "SLACK_BOT_TOKEN/SLACK_CHANNEL_ID 미설정"

OLDEST="0"
LIMIT="20"
EMIT_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --oldest) OLDEST="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --json) EMIT_JSON=1; shift ;;
    *) die "Unknown arg: $1" ;;
  esac
done

# 봇 자신 ID 조회 (한 번만, 캐시)
BOT_ID_CACHE="$REPO_ROOT/.harness/coord/bot_id.txt"
if [[ ! -f "$BOT_ID_CACHE" ]]; then
  mkdir -p "$(dirname "$BOT_ID_CACHE")"
  curl -sS -H "Authorization: Bearer $SLACK_BOT_TOKEN" https://slack.com/api/auth.test \
    | python -c "import json,sys; print(json.load(sys.stdin)['user_id'])" > "$BOT_ID_CACHE"
fi
BOT_ID="$(cat "$BOT_ID_CACHE")"

RESPONSE="$(curl -sS \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  "https://slack.com/api/conversations.history?channel=${SLACK_CHANNEL_ID}&oldest=${OLDEST}&limit=${LIMIT}")"

if [[ $EMIT_JSON -eq 1 ]]; then
  echo "$RESPONSE"
  exit 0
fi

# Slack 은 최신→과거 순서라서 역순 처리. 봇 멘션 포함 + 봇 자신이 아닌 메시지만.
echo "$RESPONSE" | BOT_ID="$BOT_ID" python -c "
import json, sys, os
bot_id = os.environ['BOT_ID']
data = json.load(sys.stdin)
if not data.get('ok'):
    print('ERROR:', data.get('error', 'unknown'), file=sys.stderr)
    sys.exit(1)
msgs = data.get('messages', [])
# 오래된 것부터
for m in reversed(msgs):
    # 봇 자신 skip
    if m.get('user') == bot_id or m.get('bot_id'):
        continue
    text = m.get('text', '').replace('\n', ' ')
    # 봇 멘션 포함 체크
    if f'<@{bot_id}>' not in text:
        continue
    ts = m.get('ts', '')
    user = m.get('user', 'unknown')
    print(f'{ts}\t{user}\t{text}')
"
