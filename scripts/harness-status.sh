#!/usr/bin/env bash
# harness-status.sh — Phase 5: 전체 하네스 상태 1-shot 조회.
#
# 보여주는 것:
#   1. 활성 task 테이블 (tasks.sh list)
#   2. 각 task 의 Coordinator / worker 세션 handle + Orca terminal 생존 여부
#   3. 최근 chat 메시지 (각 task 당 마지막 3건)
#   4. idempotency 처리된 dispatch 수 (중복 skip 발생 여부)
#
# 옵션:
#   --json    JSON 출력
#   --kill-orphans   활성 task 가 아닌 harness 터미널 모두 close

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
if [[ "$GIT_COMMON_DIR" = /* || "$GIT_COMMON_DIR" =~ ^[A-Z]:/ ]]; then
  MAIN_REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  MAIN_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

TASKS_DIR="$MAIN_REPO_ROOT/.harness/tasks"
CHAT_DIR="$MAIN_REPO_ROOT/.harness/chat"

OPT_JSON=0
OPT_KILL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OPT_JSON=1; shift ;;
    --kill-orphans) OPT_KILL=1; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# *//'; exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

bold() { printf '\033[1m%s\033[0m' "$*"; }
dim() { printf '\033[2m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
red() { printf '\033[31m%s\033[0m' "$*"; }

# Orca 활성 터미널 handle 집합
alive_handles="$(orca terminal list --json 2>/dev/null \
  | grep -oE '"handle"[[:space:]]*:[[:space:]]*"[^"]+"' \
  | sed -nE 's/.*"handle"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
  | tr '\n' ' ')"

is_alive() {
  [[ " $alive_handles " == *" $1 "* ]]
}

bold "═══ Harness status ═══"
echo

# ─────────────────────────────────────────────────────────────
# 1. 활성 task
# ─────────────────────────────────────────────────────────────
bold "활성 task"; echo
"$SCRIPT_DIR/tasks.sh" list 2>&1 | sed 's/^/  /'
echo

# ─────────────────────────────────────────────────────────────
# 2. 각 task 세션 상태
# ─────────────────────────────────────────────────────────────
shopt -s nullglob
task_ids=()
for f in "$TASKS_DIR"/T[0-9][0-9][0-9]-*.md; do
  base="$(basename "$f" .md)"; task_ids+=("${base%%-*}")
done

if [[ ${#task_ids[@]} -eq 0 ]]; then
  dim "(활성 task 없음 — Coordinator / worker 세션 분석 생략)"
  echo
else
  bold "세션 상태 (handles vs Orca terminal 생존)"; echo
  for id in "${task_ids[@]}"; do
    hf="$CHAT_DIR/$id.handles"
    [[ -f "$hf" ]] || { echo "  $id: (handles 없음)"; continue; }
    printf "  %s\n" "$(bold "$id")"
    while IFS= read -r line; do
      role="$(echo "$line"   | sed -nE 's/.*"role"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
      agent="$(echo "$line"  | sed -nE 's/.*"agent"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
      handle="$(echo "$line" | sed -nE 's/.*"handle"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
      ts="$(echo "$line"     | sed -nE 's/.*"ts"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
      if is_alive "$handle"; then
        status="$(green alive)"
      else
        status="$(red dead)"
      fi
      printf "    %-12s %-8s %s %s %s\n" "$role" "$agent" "$status" "${handle:0:20}…" "$(dim "$ts")"
    done < "$hf"
    # processed-dispatches 개수
    pf="$CHAT_DIR/$id.processed-dispatches"
    if [[ -f "$pf" ]]; then
      c=$(wc -l < "$pf" | tr -d ' ')
      printf "    %s\n" "$(dim "processed dispatches: $c")"
    fi
  done
  echo
fi

# ─────────────────────────────────────────────────────────────
# 3. 최근 chat (각 task 당 last 3)
# ─────────────────────────────────────────────────────────────
if [[ ${#task_ids[@]} -gt 0 ]]; then
  bold "최근 chat (task 당 마지막 3건)"; echo
  for id in "${task_ids[@]}"; do
    jf="$CHAT_DIR/$id.jsonl"
    [[ -f "$jf" ]] || continue
    printf "  %s\n" "$(bold "$id")"
    tail -3 "$jf" | while IFS= read -r line; do
      ts="$(echo "$line"   | sed -nE 's/.*"ts"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
      from="$(echo "$line" | sed -nE 's/.*"from"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
      to="$(echo "$line"   | sed -nE 's/.*"to"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
      type="$(echo "$line" | sed -nE 's/.*"type"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
      msg="$(echo "$line"  | sed -nE 's/.*"message"[[:space:]]*:[[:space:]]*"(.*)",?[[:space:]]*}/\1/p' | head -c 80)"
      printf "    %s %s → %s (%s) %s\n" "$(dim "${ts:11:8}")" "$from" "$to" "$type" "$msg"
    done
  done
  echo
fi

# ─────────────────────────────────────────────────────────────
# 4. kill-orphans (옵션)
# ─────────────────────────────────────────────────────────────
if [[ $OPT_KILL -eq 1 ]]; then
  bold "orphan 세션 정리"; echo
  # 활성 task 들의 모든 handle 수집
  known_handles=""
  for id in "${task_ids[@]}"; do
    hf="$CHAT_DIR/$id.handles"
    [[ -f "$hf" ]] || continue
    while IFS= read -r h; do
      known_handles="$known_handles $h"
    done < <(sed -nE 's/.*"handle"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$hf")
  done
  # harness-test 소속이면서 known 에 없는 handle 수집
  orca terminal list --json 2>/dev/null \
    | python -c "
import sys, json, re
raw = sys.stdin.read()
# jq 대신 간단 파싱 — handle, worktreePath 추출
handles = re.findall(r'\"handle\"[[:space:]]*:[[:space:]]*\"([^\"]+)\"', raw) if False else []
" 2>/dev/null || true

  # 간단 쉘 파싱
  orca terminal list --json 2>/dev/null \
    | awk -v known="$known_handles" '
      /"handle"[[:space:]]*:/ {
        match($0, /"handle"[[:space:]]*:[[:space:]]*"[^"]+"/)
        h = substr($0, RSTART, RLENGTH); sub(/.*"/, "", h); gsub(/"/, "", h)
        last_handle = h
      }
      /"worktreePath"[[:space:]]*:/ {
        if ($0 ~ /harness-test/) {
          if (index(" " known " ", " " last_handle " ") == 0) {
            print last_handle
          }
        }
      }
    ' | while read -r orphan; do
    echo "  close orphan: $orphan"
    orca terminal close --terminal "$orphan" --json >/dev/null 2>&1 || true
  done
fi

bold "═══ end ═══"; echo
