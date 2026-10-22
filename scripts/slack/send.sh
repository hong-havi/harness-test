#!/usr/bin/env bash
# slack/send.sh — Slack chat.postMessage 호출
#
# 사용:
#   send.sh --text "hello"                              # 채널 상위
#   send.sh --text "hi" --thread <thread_ts>            # 스레드 reply
#   send.sh --text "hi" --json                          # 응답 JSON 그대로
#
# 환경변수 (.env 로드 가능):
#   SLACK_BOT_TOKEN  (필수)
#   SLACK_CHANNEL_ID (필수)
#
# 성공 시 stdout 에 thread_ts (스레드 reply 가능한 ts) 출력.
# 네트워크/토큰 실패는 stderr + exit 1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# .env 로드 (있으면)
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

die() { echo "ERROR: $*" >&2; exit 1; }

TEXT=""
THREAD_TS=""
EMIT_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text) TEXT="$2"; shift 2 ;;
    --thread) THREAD_TS="$2"; shift 2 ;;
    --json) EMIT_JSON=1; shift ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ -n "$TEXT" ]] || die "--text 필요"
[[ -n "${SLACK_BOT_TOKEN:-}" ]] || die "SLACK_BOT_TOKEN 미설정 (.env 확인)"
[[ -n "${SLACK_CHANNEL_ID:-}" ]] || die "SLACK_CHANNEL_ID 미설정"

# JSON 바디 구성 (text 는 escape 필요)
# Windows 에서 python 이 환경변수를 CP949 로 디코드해 한글이 깨지므로 UTF-8 강제.
BODY="$(TEXT="$TEXT" CHANNEL="$SLACK_CHANNEL_ID" THREAD_TS="$THREAD_TS" \
  PYTHONUTF8=1 PYTHONIOENCODING=utf-8 python -c "
import json, os, sys
sys.stdout.reconfigure(encoding='utf-8')
payload = {'channel': os.environ['CHANNEL'], 'text': os.environ['TEXT']}
if os.environ.get('THREAD_TS'):
    payload['thread_ts'] = os.environ['THREAD_TS']
print(json.dumps(payload, ensure_ascii=False))
")"

RESPONSE="$(curl -sS -X POST \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data "$BODY" \
  https://slack.com/api/chat.postMessage)"

if [[ $EMIT_JSON -eq 1 ]]; then
  echo "$RESPONSE"
fi

# ok 체크
OK="$(echo "$RESPONSE" | PYTHONUTF8=1 PYTHONIOENCODING=utf-8 python -c "import json,sys; print(json.load(sys.stdin).get('ok', False))")"
if [[ "$OK" != "True" ]]; then
  echo "ERROR: Slack API 실패" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

# ts 추출 (성공 시 스레드 reply 가능한 핸들)
TS="$(echo "$RESPONSE" | PYTHONUTF8=1 PYTHONIOENCODING=utf-8 python -c "import json,sys; print(json.load(sys.stdin).get('ts',''))")"
echo "$TS"
