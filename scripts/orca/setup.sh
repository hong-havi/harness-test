#!/usr/bin/env bash
# orca/setup.sh — 1회성 Orca 환경 세팅
#
# 수행:
#   1. 현재 레포가 Orca에 등록되어 있는지 확인
#   2. external-worktree-visibility 를 "show" 로 설정 (git worktree를 Orca가 보도록)
#
# 재실행 안전.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "→ $*"; }

# orca CLI 존재 확인
command -v orca >/dev/null 2>&1 || die "orca CLI 를 찾을 수 없음. Orca 데스크톱 설치 확인."

# 현재 worktree가 Orca에 등록되어 있는지
RAW=$(orca worktree current --json 2>/dev/null || true)
if [[ -z "$RAW" ]] || ! echo "$RAW" | grep -q '"ok": true'; then
  die "현재 디렉토리($REPO_ROOT)가 Orca에 등록된 레포가 아닙니다. Orca 앱에서 레포 추가 후 재시도."
fi

# repoId 추출 (단순 파싱: "repoId": "..." 첫 매치)
REPO_ID=$(echo "$RAW" | awk -F'"' '/"repoId":/ {print $4; exit}')
[[ -n "$REPO_ID" ]] || die "repoId 파싱 실패."

info "레포 감지: $REPO_ID"

# external-worktree-visibility: show
orca repo set --repo "id:$REPO_ID" --external-worktree-visibility show --json >/dev/null \
  || die "external-worktree-visibility 설정 실패"
info "external-worktree-visibility: show (git worktree가 Orca에 노출됨)"

# 노출된 worktree 수 확인 (선택)
WT_COUNT=$(orca worktree list --repo "id:$REPO_ID" --json 2>/dev/null | awk -F'"' '/"totalCount":/{print $0; exit}' || echo "")
info "현재 등록된 worktree: ${WT_COUNT:-(unknown)}"

info ""
info "완료. 이제 ./scripts/tasks.sh new <slug> 로 task를 만들면 agent가 자동 spawn 됩니다."
