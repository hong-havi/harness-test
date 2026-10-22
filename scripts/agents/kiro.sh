#!/usr/bin/env bash
# agents/kiro.sh — Kiro agent 를 Orca native 로 spawn
# 호출 규약: $0 <task-id> <role> <worktree-abs-path>
#
# Kiro 는 orca agent 로 등록되어 있어 'orca agent launch --agent kiro' 로
# 네이티브 spawn 가능. 다만 --prompt 는 kiro-cli 가 initial prompt 로
# 받지 않으므로(prompt.outcome=not-delivered), spawn 후 TUI 가 뜨면
# 'orca terminal send' 로 프롬프트 주입.

set -euo pipefail

TASK_ID="${1:?task-id required}"
ROLE="${2:?role required}"
WORKTREE_PATH="${3:?worktree path required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_NAME="kiro"

command -v orca >/dev/null 2>&1 || { echo "ERROR: orca CLI 를 찾을 수 없음" >&2; exit 1; }

GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
if [[ "$GIT_COMMON_DIR" = /* || "$GIT_COMMON_DIR" =~ ^[A-Z]:/ ]]; then
  MAIN_REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  MAIN_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

PROMPT="$("$SCRIPT_DIR/_bootstrap-prompt.sh" "$TASK_ID" "$ROLE" "$AGENT_NAME")"

echo "→ orca agent launch: kiro @ $WORKTREE_PATH (role=$ROLE)"

if [[ "${HARNESS_DRY_RUN:-0}" == "1" ]]; then
  echo "[DRY RUN] orca agent launch --agent kiro --worktree path:$WORKTREE_PATH --focus --json"
  echo "[DRY RUN] + orca terminal send --terminal <handle> --text <prompt>"
  echo "[DRY RUN] prompt length: ${#PROMPT} chars"
  exit 0
fi

# spawn 재시도 (최대 2회): launch → tui-idle wait → prompt 주입
HANDLE=""
attempt=0
while [[ $attempt -lt 2 ]]; do
  attempt=$((attempt+1))
  echo "  attempt $attempt..."
  RESPONSE="$(orca agent launch \
    --agent kiro \
    --worktree "path:$WORKTREE_PATH" \
    --focus \
    --json 2>&1)"
  echo "$RESPONSE" | tail -5

  HANDLE="$(echo "$RESPONSE" | awk -F'"' '/"handle":/{print $4; exit}')"
  if [[ -z "$HANDLE" ]]; then
    echo "  ⚠ handle 추출 실패"
    sleep 2
    continue
  fi

  # kiro-cli TUI 가 로드될 때까지 대기 (초기 splash + v3 recommend 등 포함)
  echo "  TUI 로드 대기 (최대 20초)..."
  WAIT_RESP="$(orca terminal wait --terminal "$HANDLE" --for tui-idle --timeout-ms 20000 --json 2>&1)"
  if echo "$WAIT_RESP" | grep -q '"satisfied":[[:space:]]*true'; then
    echo "  ✓ kiro-cli TUI 로드 확인"
    break
  else
    echo "  ⚠ TUI 로드 timeout"
    orca terminal close --terminal "$HANDLE" --json >/dev/null 2>&1 || true
    HANDLE=""
    sleep 2
  fi
done

if [[ -z "$HANDLE" ]]; then
  echo "⚠ kiro spawn 2회 모두 실패. 수동 복구: ./scripts/tasks.sh spawn $TASK_ID $ROLE"
  exit 1
fi

# TUI 안정화 추가 대기 (initial input prompt 가 준비될 때까지)
sleep 2

# 프롬프트 주입 — kiro-cli 는 initial text input 창에 그대로 들어감
echo "  → 프롬프트 주입 (${#PROMPT} chars)..."
SEND_RESP="$(orca terminal send \
  --terminal "$HANDLE" \
  --text "$PROMPT" \
  --enter \
  --wait-submit 10 \
  --json 2>&1)"
if echo "$SEND_RESP" | grep -q '"accepted":[[:space:]]*true'; then
  echo "  ✓ 프롬프트 전달 완료"
else
  echo "  ⚠ 프롬프트 주입 응답 이상 — kiro 창에서 수동 확인 필요"
  echo "$SEND_RESP" | tail -5
fi

# handle 기록
mkdir -p "$MAIN_REPO_ROOT/.harness/chat"
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"role\":\"$ROLE\",\"agent\":\"kiro\",\"handle\":\"$HANDLE\"}" \
  >> "$MAIN_REPO_ROOT/.harness/chat/${TASK_ID}.handles"
echo "✓ kiro 세션 시작, handle=$HANDLE"
