#!/usr/bin/env bash
# setup.sh — 신규 PC 1-step 셋업 (Phase 4 L)
#
# 수행:
#   1. 필수 의존성 체크 (git, bash, python, curl, orca)
#   2. 선택 의존성 안내 (pnpm, docker, cygpath)
#   3. .env 가 없으면 .env.example 복사 + 토큰 입력 안내
#   4. Orca external-worktree-visibility 설정
#   5. (선택) pnpm install
#   6. (선택) Slack relay install (OS 자동 등록)
#
# 사용:
#   ./scripts/setup.sh              # interactive — 각 선택 사항 확인
#   ./scripts/setup.sh --yes        # 전부 자동 (CI/스크립트용)
#   ./scripts/setup.sh --check-only # 체크만, 설치/변경 안 함

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AUTO_YES=0
CHECK_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) AUTO_YES=1; shift ;;
    --check-only) CHECK_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# *//'; exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────────────────────
# 색상 + 유틸
# ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; D=$'\033[2m'; N=$'\033[0m'
else
  R=""; G=""; Y=""; B=""; D=""; N=""
fi

ok()   { echo "  ${G}✓${N} $*"; }
miss() { echo "  ${R}✗${N} $*"; }
warn() { echo "  ${Y}⚠${N} $*"; }
info() { echo "${B}$*${N}"; }

ask() {
  local prompt="$1" default="${2:-y}"
  if [[ $AUTO_YES -eq 1 ]]; then
    echo "  [--yes] $prompt → $default"
    [[ "$default" == "y" ]] && return 0 || return 1
  fi
  read -r -p "  $prompt [${default}/n] " ans
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[yY]$ ]]
}

# ─────────────────────────────────────────────────────────────
# 1. 필수 의존성 체크
# ─────────────────────────────────────────────────────────────
info "═══ 1. 필수 의존성 체크 ═══"
MISSING=0

check_cmd() {
  local cmd="$1" purpose="$2" required="${3:-1}"
  if command -v "$cmd" >/dev/null 2>&1; then
    local ver
    ver="$("$cmd" --version 2>&1 | head -1 || echo '?')"
    ok "$cmd — ${D}$ver${N}"
    return 0
  fi
  if [[ "$required" -eq 1 ]]; then
    miss "$cmd — ${D}$purpose${N} (필수)"
    MISSING=$((MISSING+1))
  else
    warn "$cmd — ${D}$purpose${N} (선택)"
  fi
  return 1
}

check_cmd git     "task worktree 관리"
check_cmd bash    "스크립트 실행"
check_cmd python  "Slack JSON 파싱"
check_cmd curl    "Slack API 호출"
check_cmd awk     "chat log 파싱"
check_cmd sed     "스크립트 처리"

# Orca CLI — 환경에 따라 orca / orca-ide / ORCA_CLI_COMMAND
ORCA_CMD=""
for c in "${ORCA_CLI_COMMAND:-}" orca orca-ide orca-dev; do
  [[ -z "$c" ]] && continue
  if command -v "$c" >/dev/null 2>&1; then
    ORCA_CMD="$c"
    ok "orca CLI — ${D}$c${N}"
    break
  fi
done
if [[ -z "$ORCA_CMD" ]]; then
  miss "orca CLI — ${D}Orca orchestration / terminal / agent 사용${N} (필수)"
  warn "  Orca 설치: https://orca.ai (또는 Orca 데스크톱 앱 설치 후 CLI 활성화)"
  MISSING=$((MISSING+1))
fi

echo
info "═══ 2. 선택 의존성 체크 ═══"
check_cmd pnpm    "apps/web apps/api 의존성" 0
check_cmd docker  "qa UAT (docker compose up)" 0

# Windows 전용
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -s)" == CYGWIN* ]]; then
  check_cmd cygpath "Windows ↔ Unix 경로 변환" 1
fi

if [[ $MISSING -gt 0 ]]; then
  echo
  echo "${R}✗ 필수 의존성 $MISSING 개 누락 — 설치 후 다시 실행하세요.${N}"
  exit 1
fi

[[ $CHECK_ONLY -eq 1 ]] && { echo; info "═══ --check-only 모드. 설치/변경 skip ═══"; exit 0; }

# ─────────────────────────────────────────────────────────────
# 3. .env 설정
# ─────────────────────────────────────────────────────────────
echo
info "═══ 3. .env 설정 ═══"
if [[ -f "$REPO_ROOT/.env" ]]; then
  ok ".env 존재"
  # SLACK_* 비어있으면 경고
  for k in SLACK_BOT_TOKEN SLACK_CHANNEL_ID; do
    v="$(grep -E "^$k=" "$REPO_ROOT/.env" | head -1 | cut -d= -f2-)"
    [[ -z "$v" ]] && warn "$k 비어있음 — Slack 통합 안 됨 (@bot 명령 못 받음)"
  done
else
  warn ".env 없음 → .env.example 복사"
  if ask ".env.example → .env 복사?"; then
    cp "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"
    ok "복사 완료. 아래 토큰 수동 입력:"
    echo "    ${B}SLACK_BOT_TOKEN${N}   = xoxb-... (Slack 봇 OAuth 토큰)"
    echo "    ${B}SLACK_CHANNEL_ID${N}  = C0XXXXXXXXX (하네스 운영 채널 ID)"
    echo "    ${B}HARNESS_DEFAULT_AGENT${N} = kiro | claude | codex (기본 agent)"
    echo "    편집: ${D}\$EDITOR $REPO_ROOT/.env${N}"
  fi
fi

# ─────────────────────────────────────────────────────────────
# 4. Orca external-worktree-visibility
# ─────────────────────────────────────────────────────────────
echo
info "═══ 4. Orca external-worktree-visibility ═══"
if [[ -x "$SCRIPT_DIR/orca/setup.sh" ]]; then
  if ask "Orca external-worktree visibility 설정 (1회성)?"; then
    "$SCRIPT_DIR/orca/setup.sh" || warn "orca/setup.sh 실패 (Orca 미실행 가능)"
  fi
else
  warn "scripts/orca/setup.sh 없음 — skip"
fi

# ─────────────────────────────────────────────────────────────
# 5. pnpm install (apps 의존성)
# ─────────────────────────────────────────────────────────────
echo
info "═══ 5. apps 의존성 ═══"
if command -v pnpm >/dev/null 2>&1 && [[ -f "$REPO_ROOT/package.json" ]]; then
  if ask "pnpm install 실행?"; then
    (cd "$REPO_ROOT" && pnpm install) || warn "pnpm install 실패"
  fi
else
  warn "pnpm 또는 package.json 없음 — skip (apps 생성 전 상태)"
fi

# ─────────────────────────────────────────────────────────────
# 6. Slack relay 자동 시작 (선택)
# ─────────────────────────────────────────────────────────────
echo
info "═══ 6. Slack relay 자동 시작 등록 (선택) ═══"
echo "  ${D}참고: tasks.sh new 가 relay 를 자동 start 하므로 일반적으로 불필요.${N}"
echo "  ${D}Slack 응답 상시 받고 싶을 때만 등록 (Windows=Task Scheduler, macOS=launchd, Linux=systemd).${N}"
if ask "Slack relay 자동 시작 등록?" "n"; then
  "$SCRIPT_DIR/slack/relay.sh" install || warn "relay install 실패 — nohup 모드 유지 가능"
fi

# ─────────────────────────────────────────────────────────────
# 마무리
# ─────────────────────────────────────────────────────────────
echo
info "═══ 셋업 완료 ═══"
echo "다음 단계:"
echo "  1. ${B}.env${N} 에 SLACK 토큰 채웠는지 확인"
echo "  2. 첫 task 시작: ${B}./scripts/tasks.sh new <slug> \"요구사항\"${N}"
echo "     또는 Slack: ${B}@harness-bot new <slug> <요구사항>${N}"
echo "  3. 상태 조회: ${B}./scripts/harness-status.sh${N} 또는 ${B}@bot status${N}"
echo "  4. 자세히: ${D}cat CLAUDE.md${N} 또는 ${D}cat .harness/README.md${N}"
