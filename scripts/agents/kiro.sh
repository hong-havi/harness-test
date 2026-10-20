#!/usr/bin/env bash
# agents/kiro.sh — Kiro CLI agent 를 Orca 터미널에서 spawn
# 호출 규약: $0 <task-id> <role> <worktree-abs-path>
#
# Kiro 는 orca agent launch 네이티브가 아니라 "kiro-cli chat" 을
# orca terminal create --command 로 띄우는 방식으로 통합.
# claude/codex 와 동일하게 터미널 handle 을 .harness/chat/<id>.handles 에 기록.

set -euo pipefail

TASK_ID="${1:?task-id required}"
ROLE="${2:?role required}"
WORKTREE_PATH="${3:?worktree path required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_NAME="kiro"

command -v kiro-cli >/dev/null 2>&1 || { echo "ERROR: kiro-cli 를 찾을 수 없음" >&2; exit 1; }
command -v orca >/dev/null 2>&1 || { echo "ERROR: orca CLI 를 찾을 수 없음" >&2; exit 1; }

# MAIN_REPO_ROOT 찾기 (handles 파일 공유 위치)
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
if [[ "$GIT_COMMON_DIR" = /* || "$GIT_COMMON_DIR" =~ ^[A-Z]:/ ]]; then
  MAIN_REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  MAIN_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# 부트스트랩 프롬프트를 worktree 내 임시 파일에 저장 (kiro-cli chat 에 argv 로 전달하기엔 복잡해서)
# WORKTREE_PATH 는 이미 Orca 포맷(D:/...) 일 수 있음. kiro-cli 는 OS 네이티브 경로를 받을 수 있어 그대로 사용.
PROMPT="$("$SCRIPT_DIR/_bootstrap-prompt.sh" "$TASK_ID" "$ROLE" "$AGENT_NAME")"
# .harness/.kiro-prompt-T###-<role>.txt (gitignore 영역: .harness/chat 패턴은 cover 안 하지만 임시파일이라 수동 정리)
PROMPT_REL=".harness/.kiro-prompt-${TASK_ID}-${ROLE}.txt"

# WORKTREE_PATH 가 Orca 포맷(D:/...) 이면 네이티브 경로로 쓰고,
# bash 에서 접근하려면 cygpath -u 로 변환해야 함.
if [[ "$WORKTREE_PATH" =~ ^[A-Z]:/ ]] && command -v cygpath >/dev/null 2>&1; then
  WORKTREE_UNIX="$(cygpath -u "$WORKTREE_PATH")"
else
  WORKTREE_UNIX="$WORKTREE_PATH"
fi

mkdir -p "$WORKTREE_UNIX/.harness"
printf '%s\n' "$PROMPT" > "$WORKTREE_UNIX/$PROMPT_REL"

echo "→ orca terminal create: kiro-cli chat @ $WORKTREE_PATH (role=$ROLE)"

if [[ "${HARNESS_DRY_RUN:-0}" == "1" ]]; then
  echo "[DRY RUN] orca terminal create --worktree path:$WORKTREE_PATH --title '... ($ROLE)' --command 'kiro-cli chat --trust-all-tools \"\$(cat $PROMPT_REL)\"'"
  exit 0
fi

# Orca 터미널에서 kiro-cli chat 실행.
# command 는 쉘에서 평가되므로 $(cat ...) 가 터미널의 bash 에서 치환됨.
# --trust-all-tools 로 agent 가 셸/tool 호출 시 confirmation 없이 진행.
CMD="kiro-cli chat --trust-all-tools \"\$(cat $PROMPT_REL)\""

RESPONSE="$(orca terminal create \
  --worktree "path:$WORKTREE_PATH" \
  --title "Kiro ($ROLE) role for task $TASK_ID" \
  --command "$CMD" \
  --json 2>&1)"
echo "$RESPONSE"

# 터미널 handle 기록 (handle 은 "term_..." 패턴. 응답 포맷 상이할 수 있어 유연 추출)
HANDLE="$(echo "$RESPONSE" | awk -F'"' '/"handle":/{print $4; exit}')"
if [[ -n "$HANDLE" ]]; then
  mkdir -p "$MAIN_REPO_ROOT/.harness/chat"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"role\":\"$ROLE\",\"agent\":\"kiro\",\"handle\":\"$HANDLE\"}" \
    >> "$MAIN_REPO_ROOT/.harness/chat/${TASK_ID}.handles"
  echo "✓ kiro-cli 세션 시작, handle=$HANDLE"
else
  echo "⚠ terminal handle 추출 실패 — 수동 확인 필요"
fi
