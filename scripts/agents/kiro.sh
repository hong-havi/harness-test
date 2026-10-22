#!/usr/bin/env bash
# agents/kiro.sh — Kiro CLI agent 를 Orca 터미널에서 안정적으로 spawn
# 호출 규약: $0 <task-id> <role> <worktree-abs-path>
#
# 변경 이력:
# - 초기: `orca terminal create --command "kiro-cli chat ... $(cat ...)"` →
#   Windows cmd/PowerShell 쉘에서 $(cat) 치환 실패 → kiro-cli 가 literal
#   받고 즉시 exit → cmd prompt 로 fallback 후 handle 캡처 실패.
# - 현재: 임시 **bash wrapper 스크립트**를 생성해 그걸 bash.exe 절대경로로
#   호출. spawn 후 tui-idle 체크로 kiro-cli 가 실제 떴는지 검증, 실패 시 1회 재시도.

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

# bash.exe 절대경로 찾기 — orca terminal create 가 cmd/PowerShell 쉘에서 실행하므로
# `bash` 만으론 WSL 로 갈 수 있어 Git Bash 절대경로를 사용.
BASH_EXE=""
for candidate in \
  "C:/Program Files/Git/bin/bash.exe" \
  "C:/Program Files (x86)/Git/bin/bash.exe"; do
  [[ -x "$candidate" ]] && { BASH_EXE="$candidate"; break; }
done
if [[ -z "$BASH_EXE" ]]; then
  # Git Bash 밖(Unix 등) — 평범한 bash 로 폴백
  if command -v cygpath >/dev/null 2>&1; then
    BASH_EXE="$(cygpath -m "$(which bash)")"
  else
    BASH_EXE="$(which bash)"
  fi
fi

# WORKTREE_PATH 는 Orca 포맷(D:/...) 로 주어짐. bash 접근용 unix 경로로.
if [[ "$WORKTREE_PATH" =~ ^[A-Z]:/ ]] && command -v cygpath >/dev/null 2>&1; then
  WORKTREE_UNIX="$(cygpath -u "$WORKTREE_PATH")"
else
  WORKTREE_UNIX="$WORKTREE_PATH"
fi

# 프롬프트 + wrapper 스크립트 생성 (worktree 안)
PROMPT="$("$SCRIPT_DIR/_bootstrap-prompt.sh" "$TASK_ID" "$ROLE" "$AGENT_NAME")"
PROMPT_REL=".harness/.kiro-prompt-${TASK_ID}-${ROLE}.txt"
RUN_REL=".harness/.kiro-run-${TASK_ID}-${ROLE}.sh"
PROMPT_ABS="$WORKTREE_UNIX/$PROMPT_REL"
RUN_ABS="$WORKTREE_UNIX/$RUN_REL"

mkdir -p "$WORKTREE_UNIX/.harness"
printf '%s\n' "$PROMPT" > "$PROMPT_ABS"

# wrapper 스크립트: cd worktree + kiro-cli chat 실행
cat > "$RUN_ABS" <<EOF
#!/usr/bin/env bash
set -e
cd "\$(dirname "\$0")/../.."
exec kiro-cli chat --trust-all-tools "\$(cat "$PROMPT_REL")"
EOF
chmod +x "$RUN_ABS"

# cmd 쪽 명령: Git Bash 절대경로 + wrapper 스크립트 Windows 경로
RUN_WIN="$RUN_ABS"
if command -v cygpath >/dev/null 2>&1; then
  RUN_WIN="$(cygpath -m "$RUN_ABS")"
fi
CMD="\"$BASH_EXE\" -lc \"'$RUN_WIN'\""

echo "→ orca terminal create: kiro-cli chat @ $WORKTREE_PATH (role=$ROLE)"

if [[ "${HARNESS_DRY_RUN:-0}" == "1" ]]; then
  echo "[DRY RUN] orca terminal create --worktree path:$WORKTREE_PATH --command '$CMD'"
  echo "[DRY RUN] wrapper: $RUN_ABS"
  exit 0
fi

# spawn 시도 — 최대 2회 재시도 (사이 2초 대기, 각 시도 후 tui-idle 로 kiro 가 실제 떴는지 확인)
spawn_attempt=0
HANDLE=""
while [[ $spawn_attempt -lt 2 ]]; do
  spawn_attempt=$((spawn_attempt+1))
  echo "  attempt $spawn_attempt..."
  RESPONSE="$(orca terminal create \
    --worktree "path:$WORKTREE_PATH" \
    --title "Kiro ($ROLE) role for task $TASK_ID" \
    --command "$CMD" \
    --json 2>&1)"
  echo "$RESPONSE" | tail -5

  HANDLE="$(echo "$RESPONSE" | awk -F'"' '/"handle":/{print $4; exit}')"
  if [[ -z "$HANDLE" ]]; then
    echo "  ⚠ handle 추출 실패"
    sleep 2
    continue
  fi

  # tui-idle 체크 — kiro-cli TUI 가 초기화되고 idle 상태 도달하는지
  sleep 3
  WAIT_RESP="$(orca terminal wait --terminal "$HANDLE" --for tui-idle --timeout-ms 15000 --json 2>&1)"
  if echo "$WAIT_RESP" | grep -q '"satisfied":[[:space:]]*true'; then
    echo "  ✓ kiro-cli TUI 로드 확인"
    break
  else
    echo "  ⚠ kiro-cli TUI 로드 실패 (tui-idle timeout). 재시도..."
    # 실패한 터미널 close
    orca terminal close --terminal "$HANDLE" --json >/dev/null 2>&1 || true
    HANDLE=""
    sleep 2
  fi
done

if [[ -z "$HANDLE" ]]; then
  echo "⚠ kiro spawn 2회 모두 실패. 수동 복구 필요: ./scripts/tasks.sh spawn $TASK_ID $ROLE"
  exit 1
fi

# 성공: handle 기록
mkdir -p "$MAIN_REPO_ROOT/.harness/chat"
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"role\":\"$ROLE\",\"agent\":\"kiro\",\"handle\":\"$HANDLE\"}" \
  >> "$MAIN_REPO_ROOT/.harness/chat/${TASK_ID}.handles"
echo "✓ kiro-cli 세션 시작, handle=$HANDLE"
