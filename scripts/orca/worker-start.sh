#!/usr/bin/env bash
# orca/worker-start.sh — Phase 4: orchestration worker 시작 (agent 통합)
# 호출: $0 <task-id> <role> <worktree-abs-path> <agent> <run-id> [user-request]
#
# 수행:
#   1. role.md + user-request + bootstrap-prompt 를 결합한 spec 생성
#   2. agent 가 claude/codex/cursor/antigravity/muse/zcode/opencode(2) 중 하나면:
#        orca orchestration worker-start --agent <agent> --spec ... --run <run-id>
#   3. agent 가 kiro (비 네이티브) 면:
#        3-a. orca agent launch --agent kiro 로 터미널 생성 + TUI 대기
#        3-b. orca terminal send --text <preamble> 로 preamble 주입
#        3-c. (optional) worker-start --terminal <handle> --spec ... 로 Run 등록
#
# handles 기록 + 로그 표준화.

set -euo pipefail

TASK_ID="${1:?task-id required}"
ROLE="${2:?role required}"
WORKTREE_PATH="${3:?worktree path required}"
AGENT="${4:?agent required}"
RUN_ID="${5:?run id required}"
USER_REQUEST="${6:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
if [[ "$GIT_COMMON_DIR" = /* || "$GIT_COMMON_DIR" =~ ^[A-Z]:/ ]]; then
  MAIN_REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  MAIN_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "→ $*"; }

# ─────────────────────────────────────────────────────────────
# spec 작성 — role.md + user request + bootstrap-prompt 종합
# ─────────────────────────────────────────────────────────────
build_spec() {
  local role_md="$MAIN_REPO_ROOT/.harness/roles/${ROLE}.md"
  local bootstrap
  bootstrap="$("$SCRIPT_DIR/../agents/_bootstrap-prompt.sh" "$TASK_ID" "$ROLE" "$AGENT")"

  # spec 포맷: role 지침 + bootstrap + User Request (있으면)
  cat <<SPEC
# Task $TASK_ID — Role: $ROLE

$bootstrap

## Role 상세 지침

$(cat "$role_md" 2>/dev/null || echo "(role.md 없음)")

## User Request

${USER_REQUEST:-(요구사항 상세는 .harness/tasks/${TASK_ID}-*.md 의 User Request 섹션 참조)}
SPEC
}

# ─────────────────────────────────────────────────────────────
# Agent 분기
# ─────────────────────────────────────────────────────────────
NATIVE_AGENTS=(claude codex cursor antigravity muse zcode opencode opencode2)
is_native_agent() {
  local a="$1"
  for n in "${NATIVE_AGENTS[@]}"; do [[ "$a" == "$n" ]] && return 0; done
  return 1
}

# worktree path 를 Orca 포맷(D:/...) 로
WORKTREE_ORCA="$WORKTREE_PATH"
if command -v cygpath >/dev/null 2>&1; then
  WORKTREE_ORCA="$(cygpath -m "$WORKTREE_PATH")"
fi

HANDLE=""

if is_native_agent "$AGENT"; then
  info "worker-start --agent $AGENT ..."
  SPEC="$(build_spec)"
  # worker-start 는 Spec 을 argv 또는 stdin 으로 받음. 긴 spec 이므로 argv 는 Windows argv 제한 걸릴 수 있어
  # 임시 파일 경유 — orca 는 --spec <text> argv 받으므로 그대로 전달 (Linux/Windows 모두 가능).
  RESPONSE="$(orca orchestration worker-start \
    --run "$RUN_ID" \
    --spec "$SPEC" \
    --worktree "path:$WORKTREE_ORCA" \
    --agent "$AGENT" \
    --task-title "$TASK_ID: $ROLE" \
    --timeout-ms 60000 \
    --json 2>&1)"
  echo "$RESPONSE" | tail -10
  HANDLE="$(echo "$RESPONSE" | awk -F'"' '/"handle":/{print $4; exit}')"
else
  # kiro 등 비네이티브 — 터미널 띄우고 preamble 주입
  info "비네이티브 agent ($AGENT) — orca agent launch + preamble 주입"
  LAUNCH="$(orca agent launch \
    --agent "$AGENT" \
    --worktree "path:$WORKTREE_ORCA" \
    --focus \
    --json 2>&1)"
  echo "$LAUNCH" | tail -5
  HANDLE="$(echo "$LAUNCH" | awk -F'"' '/"handle":/{print $4; exit}')"
  [[ -n "$HANDLE" ]] || die "agent launch 결과 handle 추출 실패"

  info "  TUI 로드 대기 (최대 20초)..."
  orca terminal wait --terminal "$HANDLE" --for tui-idle --timeout-ms 20000 --json >/dev/null 2>&1 \
    || info "  (tui-idle timeout — 계속 진행)"
  sleep 2

  SPEC="$(build_spec)"
  info "  → preamble 주입 (${#SPEC} chars)..."
  orca terminal send --terminal "$HANDLE" --text "$SPEC" --enter --wait-submit 10 --json >/dev/null 2>&1 \
    || die "preamble 주입 실패"

  # worker-start --terminal 로 Run 에 등록 (orchestration 이 settled 관리)
  info "  worker-start --terminal $HANDLE (Run 에 등록)..."
  REG="$(orca orchestration worker-start \
    --run "$RUN_ID" \
    --spec "비네이티브 agent 세션 — preamble 은 terminal send 로 주입됨" \
    --terminal "$HANDLE" \
    --worktree "path:$WORKTREE_ORCA" \
    --task-title "$TASK_ID: $ROLE" \
    --json 2>&1)" || true
  echo "$REG" | tail -5
fi

[[ -n "$HANDLE" ]] || die "worker 시작 실패 — handle 없음"

# handles 기록
mkdir -p "$MAIN_REPO_ROOT/.harness/chat"
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"role\":\"$ROLE\",\"agent\":\"$AGENT\",\"handle\":\"$HANDLE\",\"run_id\":\"$RUN_ID\"}" \
  >> "$MAIN_REPO_ROOT/.harness/chat/${TASK_ID}.handles"
echo "✓ worker 시작 완료 ($ROLE / $AGENT), handle=$HANDLE"
