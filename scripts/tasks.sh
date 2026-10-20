#!/usr/bin/env bash
# tasks.sh — task 라이프사이클 관리
#
# 서브커맨드:
#   new <slug>            새 task (worktree + 브랜치 + task.md + compose override)
#   list                  활성 task 테이블
#   advance [task-id]     current_role 커서를 다음 required_role로
#   merge [task-id]       rebase main + ff-only merge + cleanup
#   drop [task-id]        폐기 (archive)
#   show [task-id]        task 요약 출력
#
# worktree 내부에서 실행하면 task-id 자동 감지.
# Phase 1: Orca 미통합. git worktree 직접 사용.

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# task.md 는 LOCAL (worktree 또는 main) 에서 읽기/쓰기 — 역할 변경이 지역 브랜치에서 발생
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# worktrees/handles 경로는 MAIN 공유 — 모든 역할이 같은 위치 사용
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
if [[ "$GIT_COMMON_DIR" = /* || "$GIT_COMMON_DIR" =~ ^[A-Z]:/ ]]; then
  MAIN_REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  MAIN_REPO_ROOT="$REPO_ROOT"
fi

HARNESS_DIR="$REPO_ROOT/.harness"
TASKS_DIR="$HARNESS_DIR/tasks"
CHAT_DIR="$MAIN_REPO_ROOT/.harness/chat"      # handles 는 main 에 공유
ARCHIVE_DIR="$MAIN_REPO_ROOT/.harness/archive"
WORKTREES_DIR="$MAIN_REPO_ROOT/.worktrees"
TEMPLATE_TASK="$HARNESS_DIR/templates/task.md"
TEMPLATE_COMPOSE="$HARNESS_DIR/templates/docker-compose.override.yml.tmpl"
MAIN_BRANCH="main"

# ─────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────
die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "→ $*"; }

usage() {
  cat <<EOF
Usage: $0 <command> [args]

Commands:
  new <slug> [--no-spawn]       Create task + worktree + branch (planner 자동 spawn)
  list                          Show active tasks
  advance [task-id] [--no-spawn] Move current_role to next, auto-spawn 다음 agent
  merge [task-id]               Rebase + ff-only merge to main + cleanup
  drop [task-id]                Archive and remove worktree/branch
  show [task-id]                Print task summary
  spawn [task-id] [role]        현재 또는 지정 역할 agent 재spawn (디버깅)

worktree 내부에서 실행하면 task-id 자동 감지.
--no-spawn: 자동 agent spawn 비활성 (Phase 1 수동 모드와 동일).
EOF
}

# task-id (T001) 를 받아 task 파일 경로 반환
task_file() {
  local id="$1"
  local f
  f=$(find "$TASKS_DIR" -maxdepth 1 -name "${id}-*.md" | head -1)
  [[ -n "$f" ]] || die "task 파일을 찾을 수 없음: $id"
  echo "$f"
}

# 현재 디렉토리가 worktree 안이면 task-id 추출, 아니면 빈 문자열
detect_task_id() {
  local pwd_abs
  pwd_abs="$(pwd -P)"
  if [[ "$pwd_abs" == "$WORKTREES_DIR"/* ]]; then
    local rel="${pwd_abs#$WORKTREES_DIR/}"
    local wt_name="${rel%%/*}"
    # T001-signup-api → T001
    echo "${wt_name%%-*}"
  else
    echo ""
  fi
}

# task-id 를 인자로 받되, 없으면 자동 감지, 그래도 없으면 die
resolve_task_id() {
  local given="${1:-}"
  if [[ -n "$given" ]]; then
    echo "$given"
    return
  fi
  local detected
  detected="$(detect_task_id)"
  [[ -n "$detected" ]] || die "task-id 를 지정하거나 worktree 안에서 실행하세요."
  echo "$detected"
}

# 다음 번호 (max + 1), 3자리 0패딩
next_task_num() {
  local max=0
  if [[ -d "$TASKS_DIR" ]]; then
    while IFS= read -r f; do
      local base n
      base="$(basename "$f")"
      n="${base#T}"
      n="${n%%-*}"
      # strip leading zeros for arithmetic
      n=$((10#$n))
      (( n > max )) && max=$n
    done < <(find "$TASKS_DIR" -maxdepth 1 -name 'T[0-9][0-9][0-9]-*.md' 2>/dev/null || true)
  fi
  if [[ -d "$ARCHIVE_DIR" ]]; then
    while IFS= read -r f; do
      local base n
      base="$(basename "$f")"
      n="${base#T}"
      n="${n%%-*}"
      n=$((10#$n))
      (( n > max )) && max=$n
    done < <(find "$ARCHIVE_DIR" -maxdepth 1 -name 'T[0-9][0-9][0-9]-*.md' 2>/dev/null || true)
  fi
  printf 'T%03d' $((max + 1))
}

# task 번호 → 포트/프로젝트 이름
compute_ports() {
  local id="$1"              # T001
  local n="${id#T}"
  n=$((10#$n))
  local idx=$((n % 100))
  echo "WEB_PORT=$((3000 + idx * 10))"
  echo "API_PORT=$((4000 + idx * 10))"
  echo "DB_PORT=$((3306 + idx))"
  echo "COMPOSE_PROJECT_NAME=harness_$(echo "$id" | tr '[:upper:]' '[:lower:]')"
  echo "TASK_ID=$id"
}

# frontmatter 필드 값 추출 (단순 YAML, 1라인)
# 사용: get_fm <file> <key>
get_fm() {
  local file="$1"
  local key="$2"
  awk -v k="$key" '
    /^---/ { fm = !fm; next }
    fm && $0 ~ "^"k":" {
      sub("^"k": *", "", $0)
      sub(/ *#.*$/, "", $0)
      sub(/^"|"$/, "", $0)
      sub(/[[:space:]]+$/, "", $0)
      print
      exit
    }
  ' "$file"
}

# ─────────────────────────────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────────────────────────────

cmd_new() {
  local slug=""
  local no_spawn=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-spawn) no_spawn=1; shift ;;
      -*) die "Unknown flag: $1" ;;
      *) slug="$1"; shift ;;
    esac
  done
  [[ -n "$slug" ]] || die "slug 가 필요합니다. 예: $0 new signup-api"
  [[ "$slug" =~ ^[a-z0-9-]+$ ]] || die "slug 는 kebab-case 소문자+숫자+하이픈만 허용"

  local id
  id="$(next_task_num)"
  local branch="task/${id}-${slug}"
  local wt_rel=".worktrees/${id}-${slug}"
  local wt_abs="$REPO_ROOT/$wt_rel"
  local task_rel=".harness/tasks/${id}-${slug}.md"
  local task_abs="$REPO_ROOT/$task_rel"

  info "새 task 생성: $id ($slug)"
  info "  branch:    $branch"
  info "  worktree:  $wt_rel"
  info "  task file: $task_rel"

  # 1) worktree + 브랜치 (main 기반)
  cd "$REPO_ROOT"
  git worktree add -b "$branch" "$wt_abs" "$MAIN_BRANCH" >/dev/null
  info "  → git worktree 생성"

  # 2) task.md 생성 (template 복사 + 치환)
  mkdir -p "$TASKS_DIR"
  local today
  today="$(date +%Y-%m-%d)"
  local port_env
  port_env="$(compute_ports "$id")"
  local web_port api_port db_port compose_proj
  web_port=$(echo "$port_env" | awk -F= '/^WEB_PORT=/{print $2}')
  api_port=$(echo "$port_env" | awk -F= '/^API_PORT=/{print $2}')
  db_port=$(echo "$port_env" | awk -F= '/^DB_PORT=/{print $2}')
  compose_proj=$(echo "$port_env" | awk -F= '/^COMPOSE_PROJECT_NAME=/{print $2}')

  sed \
    -e "s|T###|${id}|g" \
    -e "s|<kebab-slug>|${slug}|g" \
    -e "s|<slug>|${slug}|g" \
    -e "s|<한 줄 요약>|${slug}|g" \
    -e "s|web: 3010|web: ${web_port}|" \
    -e "s|api: 4010|api: ${api_port}|" \
    -e "s|db: 3307|db: ${db_port}|" \
    -e "s|compose_project: harness_t###|compose_project: ${compose_proj}|" \
    -e "s|YYYY-MM-DD|${today}|g" \
    "$TEMPLATE_TASK" > "$task_abs"
  info "  → task.md 생성"

  # 3) task.md 를 worktree 쪽에도 복사해 두되 — 실제로는 main에서 git add 후
  #    worktree 가 보도록 커밋 전까지는 각자 영역. 간단히 main 쪽에만 두고
  #    각 역할은 main 트리의 파일을 참조하는 전략은 ff-only merge 와 충돌.
  #
  #    선택: main 에 task.md 커밋하고, worktree 는 main 기반이므로 자동 보임.
  cd "$REPO_ROOT"
  git add "$task_rel"
  git -c core.hooksPath=/dev/null commit -m "${id} [harness]: create task ${slug}" >/dev/null
  info "  → main 에 task.md 커밋"

  # 4) worktree 쪽에 compose override + .env 생성 (gitignore 됨)
  mkdir -p "$wt_abs"
  {
    echo "# task-scoped environment"
    echo "$port_env"
  } > "$wt_abs/.env"
  info "  → $wt_rel/.env 생성"

  # compose override 템플릿 변수 치환
  WEB_PORT="$web_port" API_PORT="$api_port" DB_PORT="$db_port" \
  TASK_ID="$id" COMPOSE_PROJECT_NAME="$compose_proj" \
    envsubst '${WEB_PORT} ${API_PORT} ${DB_PORT} ${TASK_ID}' < "$TEMPLATE_COMPOSE" \
    > "$wt_abs/docker-compose.override.yml"
  info "  → docker-compose.override.yml 생성"

  # 5) chat 로그 초기화
  mkdir -p "$CHAT_DIR"
  "$SCRIPT_DIR/chat.sh" append "$id" harness tasks note "task $id ($slug) created" >/dev/null

  info ""
  if [[ $no_spawn -eq 1 ]]; then
    info "완료 (--no-spawn). 다음 단계 수동:"
    info "  cd $wt_rel"
    info "  ./scripts/role.sh planner"
  else
    info "완료. planner agent 를 자동으로 spawn 합니다..."
    "$SCRIPT_DIR/orca/spawn.sh" "$id" planner || {
      info "⚠ spawn 실패. 수동으로 진행:"
      info "  cd $wt_rel && ./scripts/role.sh planner"
    }
  fi
}

cmd_list() {
  shopt -s nullglob
  local rows=0
  printf "%-6s %-24s %-14s %-10s %-18s %s\n" "ID" "SLUG" "STATUS" "CURRENT" "PORTS(web/api/db)" "BRANCH"
  echo "─────────────────────────────────────────────────────────────────────────────────────────"
  for f in "$TASKS_DIR"/T[0-9][0-9][0-9]-*.md; do
    [[ -f "$f" ]] || continue
    local id slug status current branch web api db
    id=$(get_fm "$f" "id")
    slug=$(get_fm "$f" "slug")
    status=$(get_fm "$f" "status")
    current=$(get_fm "$f" "current_role")
    branch=$(get_fm "$f" "branch")
    web=$(awk '/^  web:/{print $2; exit}' "$f")
    api=$(awk '/^  api:/{print $2; exit}' "$f")
    db=$(awk '/^  db:/{print $2; exit}' "$f")
    printf "%-6s %-24s %-14s %-10s %-18s %s\n" \
      "$id" "$slug" "$status" "$current" "${web}/${api}/${db}" "$branch"
    rows=$((rows+1))
  done
  if [[ $rows -eq 0 ]]; then
    echo "(no active tasks)"
  fi
}

# required_roles 리스트에서 current_role 다음 역할 찾기
# task.md 를 파싱 — "- { role: xxx, agent: yyy }" 패턴
cmd_advance() {
  local given_id=""
  local no_spawn=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-spawn) no_spawn=1; shift ;;
      -*) die "Unknown flag: $1" ;;
      *) given_id="$1"; shift ;;
    esac
  done
  local id
  id="$(resolve_task_id "$given_id")"
  local f
  f="$(task_file "$id")"

  local current
  current="$(get_fm "$f" "current_role")"
  [[ -n "$current" ]] || die "current_role 을 읽지 못함: $f"

  # required_roles 리스트에서 role 추출 (주석 라인은 스킵)
  local roles
  roles=$(awk '
    /^required_roles:/ { in_block=1; next }
    /^[a-zA-Z_]+:/ { in_block=0 }
    in_block && /^[[:space:]]*#/ { next }
    in_block && /role:/ {
      sub(/.*role: */, "")
      sub(/,.*/, "")
      sub(/[}].*/, "")
      gsub(/[[:space:]]/, "")
      print
    }
  ' "$f")

  [[ -n "$roles" ]] || die "required_roles 파싱 실패"

  local next=""
  local found=0
  while IFS= read -r r; do
    if [[ $found -eq 1 ]]; then
      next="$r"
      break
    fi
    [[ "$r" == "$current" ]] && found=1
  done <<< "$roles"

  if [[ -z "$next" ]]; then
    info "'$current' 이후 역할 없음. 모든 required_roles 소진. status 를 수동 확인하세요."
    return 0
  fi

  # frontmatter 의 current_role 교체
  sed -i.bak "s|^current_role: .*|current_role: $next|" "$f"
  rm -f "${f}.bak"
  info "$id: current_role $current → $next"

  "$SCRIPT_DIR/chat.sh" append "$id" "$current" "$next" handoff "advance: $current → $next" >/dev/null

  if [[ $no_spawn -eq 1 ]]; then
    info "(--no-spawn: 다음 agent 는 수동으로 spawn 하세요)"
  else
    # 이전 역할 터미널 자동 close (handles 파일에서 마지막 handle)
    local handles_file="$CHAT_DIR/${id}.handles"
    if [[ -f "$handles_file" ]]; then
      local prev_handle
      prev_handle=$(awk -F'"' '/"handle":/{h=$0} END{if(h) print h}' "$handles_file" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="handle:")print $(i+2); next}' | head -1)
      # 더 안정적: tail -1 로 마지막 라인 → handle 값 추출
      prev_handle=$(tail -1 "$handles_file" | awk -F'"handle":"' '{print $2}' | awk -F'"' '{print $1}')
      if [[ -n "$prev_handle" ]]; then
        info "이전 역할 ($current) 터미널 close: $prev_handle"
        orca terminal close --terminal "$prev_handle" --json >/dev/null 2>&1 || true
      fi
    fi
    info "다음 agent 를 자동으로 spawn 합니다..."
    "$SCRIPT_DIR/orca/spawn.sh" "$id" "$next" || {
      info "⚠ spawn 실패. 수동으로 진행:"
      info "  ./scripts/role.sh $next $id"
    }
  fi
}

cmd_spawn() {
  local id
  id="$(resolve_task_id "${1:-}")"
  local role="${2:-}"
  "$SCRIPT_DIR/orca/spawn.sh" "$id" "$role"
}

cmd_merge() {
  local id
  id="$(resolve_task_id "${1:-}")"
  local f
  f="$(task_file "$id")"
  local branch slug wt_rel wt_abs
  branch=$(get_fm "$f" "branch")
  slug=$(get_fm "$f" "slug")
  wt_rel=".worktrees/${id}-${slug}"
  wt_abs="$REPO_ROOT/$wt_rel"

  info "merge $id (branch=$branch)"

  cd "$REPO_ROOT"
  git fetch --all --quiet || true

  # rebase onto main
  if [[ -d "$wt_abs" ]]; then
    (
      cd "$wt_abs"
      git fetch origin "$MAIN_BRANCH" --quiet || true
      info "  rebase $branch onto main"
      git rebase "$MAIN_BRANCH"
    ) || die "rebase 실패. 충돌 해결 후 재시도하거나 drop 하세요."
  fi

  # ff-only merge to main
  git checkout "$MAIN_BRANCH"
  info "  ff-only merge $branch → $MAIN_BRANCH"
  git merge --ff-only "$branch" || die "ff-only merge 실패. rebase 가 선행되지 않았거나 분기됨."

  # status 를 merged 로
  sed -i.bak "s|^status: .*|status: merged|" "$f"
  rm -f "${f}.bak"
  git add "$f"
  git -c core.hooksPath=/dev/null commit -m "${id} [harness]: mark merged" >/dev/null || true

  # 해당 worktree 의 모든 터미널 close
  if command -v orca >/dev/null 2>&1; then
    if command -v cygpath >/dev/null 2>&1; then
      WT_ORCA="$(cygpath -m "$wt_abs")"
    else
      WT_ORCA="$wt_abs"
    fi
    orca terminal close --worktree "path:$WT_ORCA" --all --json >/dev/null 2>&1 || true
    info "  worktree 터미널 close"
  fi

  # worktree + 브랜치 정리
  if [[ -d "$wt_abs" ]]; then
    git worktree remove --force "$wt_abs"
    info "  worktree removed"
  fi
  git branch -D "$branch" >/dev/null 2>&1 || true
  info "  branch deleted"

  # handles 파일 정리
  rm -f "$CHAT_DIR/${id}.handles"

  info "완료: $id merged."
}

cmd_drop() {
  local id
  id="$(resolve_task_id "${1:-}")"
  local f
  f="$(task_file "$id")"
  local branch slug wt_abs
  branch=$(get_fm "$f" "branch")
  slug=$(get_fm "$f" "slug")
  wt_abs="$REPO_ROOT/.worktrees/${id}-${slug}"

  info "drop $id — 폐기합니다."
  read -r -p "정말로? 되돌릴 수 없습니다 [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { info "취소됨"; return; }

  cd "$REPO_ROOT"
  # 해당 worktree 의 모든 터미널 close
  if command -v orca >/dev/null 2>&1; then
    if command -v cygpath >/dev/null 2>&1; then
      WT_ORCA="$(cygpath -m "$wt_abs")"
    else
      WT_ORCA="$wt_abs"
    fi
    orca terminal close --worktree "path:$WT_ORCA" --all --json >/dev/null 2>&1 || true
  fi
  if [[ -d "$wt_abs" ]]; then
    git worktree remove --force "$wt_abs"
  fi
  git branch -D "$branch" >/dev/null 2>&1 || true

  # task.md → archive
  mkdir -p "$ARCHIVE_DIR"
  mv "$f" "$ARCHIVE_DIR/"
  info "  → archive 로 이동"

  # chat log 도 archive
  if [[ -f "$CHAT_DIR/${id}.jsonl" ]]; then
    mv "$CHAT_DIR/${id}.jsonl" "$ARCHIVE_DIR/"
  fi
  rm -f "$CHAT_DIR/${id}.handles"

  git add -A
  git -c core.hooksPath=/dev/null commit -m "${id} [harness]: drop task" >/dev/null || true
  info "완료."
}

cmd_show() {
  local id
  id="$(resolve_task_id "${1:-}")"
  local f
  f="$(task_file "$id")"
  echo "─── $(basename "$f") ───"
  awk '/^---$/{c++; if(c==2){exit} next} c==1 {print}' "$f"
}

# ─────────────────────────────────────────────────────────────────────
# Entry
# ─────────────────────────────────────────────────────────────────────
cmd="${1:-}"
shift || true

case "$cmd" in
  new)      cmd_new "$@" ;;
  list)     cmd_list "$@" ;;
  advance)  cmd_advance "$@" ;;
  merge)    cmd_merge "$@" ;;
  drop)     cmd_drop "$@" ;;
  show)     cmd_show "$@" ;;
  spawn)    cmd_spawn "$@" ;;
  ""|-h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
