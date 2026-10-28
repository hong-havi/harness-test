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

# .env 로드 (HARNESS_DEFAULT_AGENT, SLACK_* 등). MAIN_REPO_ROOT 쪽을 우선.
for env_file in "$MAIN_REPO_ROOT/.env" "$REPO_ROOT/.env"; do
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
    break
  fi
done
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
  new <slug> [자연어 요구사항...] [--from <path>] [--agent <name>]
                                Create task + worktree + branch (planner 자동 spawn).
                                요구사항 전달 우선순위:
                                  --from <path>  명시 파일
                                  인라인 자연어   slug 뒤 토큰들
                                  자동 매칭      .harness/requests/<slug>.md 있으면 사용
                                --agent: 모든 역할의 기본 agent (default: HARNESS_DEFAULT_AGENT
                                         env 또는 claude). 지원: claude, codex, kiro.
  list                          Show active tasks
  advance   ⚠ 제거됨 (Phase 4) — agent 는 'orca orchestration worker-done' 호출 필요.
                                  자동 체인은 Coordinator (coord.sh) 가 담당.
  rework <task-id> <role>       current_role 을 지정 역할로 되돌리고 그 agent 재 spawn.
                                QA/reviewer fail 판정 후 담당 역할(backend/frontend)로.
  merge [task-id]               Rebase + ff-only merge to main + cleanup
  drop [task-id] [--yes]        Archive and remove worktree/branch (--yes 로 확인 스킵)
  show [task-id]                Print task summary
  spawn [task-id] [role]        현재 또는 지정 역할 agent 재spawn (디버깅)

worktree 내부에서 실행하면 task-id 자동 감지.
자동 spawn 끄려면 (사람 디버깅 전용): HARNESS_NO_SPAWN=1 ./scripts/tasks.sh ...
EOF
}

# task-id → main 쪽 task.md 경로 (존재 확인용). advance/merge 는 live(worktree) 경로를 쓸 것.
task_file() {
  local id="$1"
  local f
  f=$(find "$MAIN_REPO_ROOT/.harness/tasks" -maxdepth 1 -name "${id}-*.md" | head -1)
  [[ -n "$f" ]] || die "task 파일을 찾을 수 없음: $id"
  echo "$f"
}

# task-id → worktree 의 live task.md 경로 (각 역할이 섹션 작성, advance 가 조작)
live_task_file() {
  local id="$1"
  local main_f
  main_f=$(task_file "$id")
  local slug
  slug="$(basename "$main_f" .md)"          # T001-signup-api
  slug="${slug#*-}"                           # signup-api
  local wt="$WORKTREES_DIR/${id}-${slug}"
  local live="$wt/.harness/tasks/${id}-${slug}.md"
  if [[ -f "$live" ]]; then
    echo "$live"
  else
    # worktree 가 없거나 merge 완료된 상태면 main 폴백
    echo "$main_f"
  fi
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
  local no_spawn="${HARNESS_NO_SPAWN:-0}"
  if [[ "$no_spawn" == "1" ]]; then
    # 사람 interactive TTY 전용 — agent 세션(orca-spawned PTY, non-interactive shell)에서는 거부
    if [[ ! -t 0 || "${ORCA_AGENT_SESSION:-}" == "1" ]]; then
      die "HARNESS_NO_SPAWN=1 은 사람 interactive TTY 전용. agent 세션에선 금지됨. (자동 spawn 끄지 말고 그대로 체인 유지)"
    fi
    info "⚠ HARNESS_NO_SPAWN=1: 자동 spawn 생략 (디버깅 모드)"
  fi
  local description=""
  local from_file=""
  local agent="${HARNESS_DEFAULT_AGENT:-claude}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-spawn) die "--no-spawn 플래그는 제거됨. 디버깅용으로 자동 spawn 끄려면 'HARNESS_NO_SPAWN=1 ./scripts/tasks.sh ...' 로 환경변수 사용." ;;
      --from) from_file="$2"; shift 2 ;;
      --agent) agent="$2"; shift 2 ;;
      -*) die "Unknown flag: $1" ;;
      *)
        if [[ -z "$slug" ]]; then
          slug="$1"; shift
        else
          description="$*"
          break
        fi
        ;;
    esac
  done
  [[ -n "$slug" ]] || die "slug 가 필요합니다. 예: $0 new signup-api [자연어 요구사항] 또는 --from <path>"
  [[ "$slug" =~ ^[a-z0-9-]+$ ]] || die "slug 는 kebab-case 소문자+숫자+하이픈만 허용"
  # agent 유효성 — Phase 4 B 는 worker-start.sh 가 네이티브/비네이티브 분기 담당
  case "$agent" in
    claude|codex|cursor|antigravity|muse|zcode|opencode|opencode2|kiro) ;;
    *) die "지원하지 않는 agent: $agent (지원: claude, codex, kiro, cursor, antigravity, muse, zcode, opencode, opencode2)" ;;
  esac

  # description 결정: --from (명시) > 인라인 > .harness/requests/<slug>.md (자동 매칭)
  if [[ -n "$from_file" ]]; then
    [[ -f "$from_file" ]] || die "요구사항 파일을 찾을 수 없음: $from_file"
    description="$(cat "$from_file")"
    info "요구사항 파일 로드: $from_file ($(wc -l < "$from_file") lines)"
  elif [[ -z "$description" ]]; then
    local auto_req="$MAIN_REPO_ROOT/.harness/requests/${slug}.md"
    if [[ -f "$auto_req" ]]; then
      description="$(cat "$auto_req")"
      info "자동 매칭 요구사항 파일 로드: .harness/requests/${slug}.md ($(wc -l < "$auto_req") lines)"
    fi
  fi

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

  # Phase 4 R: 순서 교정 — task.md 를 main 에 **먼저** 커밋한 뒤 worktree 생성.
  # 기존 순서 (worktree 먼저 → main 에 task.md 커밋) 는 worktree HEAD 가 task.md
  # 커밋 1개 뒤로 밀려 worker 가 task.md 를 못 보던 결함 (T026/T027 발견).

  # 1) task.md 생성 (template 복사 + 치환)
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
    -e "s|<AGENT>|${agent}|g" \
    -e "s|web: 3010|web: ${web_port}|" \
    -e "s|api: 4010|api: ${api_port}|" \
    -e "s|db: 3307|db: ${db_port}|" \
    -e "s|compose_project: harness_t###|compose_project: ${compose_proj}|" \
    -e "s|YYYY-MM-DD|${today}|g" \
    "$TEMPLATE_TASK" > "$task_abs"
  info "  → task.md 생성 (agent: ${agent})"

  # 2) main 에 task.md 커밋 (worktree 생성 전!)
  cd "$REPO_ROOT"
  git add "$task_rel"
  git -c core.hooksPath=/dev/null commit -m "${id} [harness]: create task ${slug}" >/dev/null
  info "  → main 에 task.md 커밋"

  # 3) worktree + 브랜치 (방금 커밋한 main HEAD 기반 → task.md 포함)
  git worktree add -b "$branch" "$wt_abs" "$MAIN_BRANCH" >/dev/null
  info "  → git worktree 생성 (task.md 포함)"

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

  # 5) description 이 주어지면 task.md 에 "## User Request" 섹션 삽입 (frontmatter 바로 뒤)
  # 짧은 1줄은 blockquote, 긴 multi-line 은 fenced block 로 그대로 보존.
  if [[ -n "$description" ]]; then
    local tmpf="${task_abs}.tmp"
    local req_file="${task_abs}.req"
    printf '%s\n' "$description" > "$req_file"
    local lc
    lc=$(wc -l < "$req_file")
    awk -v tid="$id" -v reqf="$req_file" -v lc="$lc" '
      BEGIN { fm=0; done=0 }
      /^---$/ { fm++; print; if (fm==2 && !done) {
        print ""
        print "## User Request"
        print ""
        if (lc+0 <= 1) {
          # 짧은 한 줄 — blockquote
          while ((getline line < reqf) > 0) print "> " line
        } else {
          # 긴 multi-line — 원문 그대로 (markdown 형식 유지)
          while ((getline line < reqf) > 0) print line
        }
        close(reqf)
        print ""
        print "---"
        print ""
        print "_(" tid " 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_"
        print ""
        done=1
      }; next }
      { print }
    ' "$task_abs" > "$tmpf" && mv "$tmpf" "$task_abs"
    rm -f "$req_file"
    git add "$task_rel"
    git -c core.hooksPath=/dev/null commit --amend --no-edit >/dev/null 2>&1 || true
    info "  → task.md 에 User Request 섹션 추가"
  fi

  # 6) chat 로그 초기화 + user request 를 즉시 append (Slack 스레드 첫 메시지가 됨)
  mkdir -p "$CHAT_DIR"
  "$SCRIPT_DIR/chat.sh" append "$id" harness tasks note "task $id ($slug) created" >/dev/null
  if [[ -n "$description" ]]; then
    # 긴 문서는 Slack 에 요약 + 파일 경로 안내 (스레드 폭증 방지)
    local desc_lc
    desc_lc=$(printf '%s\n' "$description" | wc -l)
    if [[ $desc_lc -le 20 ]]; then
      "$SCRIPT_DIR/chat.sh" append "$id" user coordinator request "$description" >/dev/null
    else
      local first_line
      first_line="$(printf '%s\n' "$description" | head -1)"
      "$SCRIPT_DIR/chat.sh" append "$id" user coordinator request "📄 상세 요구사항 (${desc_lc}줄) — task.md 의 ## User Request 섹션 참조
첫줄: ${first_line}" >/dev/null
    fi
  fi

  info ""
  if [[ $no_spawn -eq 1 ]]; then
    info "완료 (--no-spawn). 다음 단계 수동:"
    info "  cd $wt_rel"
    info "  ./scripts/role.sh planner"
    return 0
  fi

  # Slack relay 데몬 자동 보장 — Orca 가 켜지고 첫 task 생성 시점에 start.
  # 이미 돌고 있으면 skip. .env 에 SLACK_* 설정 있을 때만.
  # set -e 중단 방지: start 가 "이미 실행 중" exit 1 이어도 OK → || true.
  if [[ -n "${SLACK_BOT_TOKEN:-}" && -n "${SLACK_CHANNEL_ID:-}" ]]; then
    if "$SCRIPT_DIR/slack/relay.sh" status 2>&1 | head -1 | grep -q "^running"; then
      info "Slack relay 이미 실행 중 (skip)"
    else
      info "Slack relay 데몬 시작..."
      "$SCRIPT_DIR/slack/relay.sh" start 2>&1 | sed 's/^/  /' | tail -2 || true
    fi
  fi

  # Phase 4 (재설계): orca orchestration run-create → Coordinator claude 세션 launch.
  # Coordinator 세션이 run-use + 첫 worker spawn + check-wait 루프를 담당 (bash coord.sh 는 폐기).
  info "orchestration Run 생성..."
  local run_json run_id
  run_json="$(orca orchestration run-create \
    --objective "Task $id ($slug): $description" \
    --json 2>&1)"
  run_id="$(echo "$run_json" | grep -oE '"id":[[:space:]]*"run_[a-zA-Z0-9]+"' | head -1 | sed -E 's/.*"id":[[:space:]]*"([^"]+)".*/\1/')"
  [[ -n "$run_id" ]] || { info "⚠ run-create 실패:"; echo "$run_json" | tail -5; return 1; }
  info "  run_id=$run_id"

  # run_id 를 task.md frontmatter 에 기록 — Coordinator 재개 시 참조
  if grep -q "^role_history:" "$task_abs"; then
    awk -v rid="$run_id" '
      /^role_history:/ && !ins { print; print "run_id: " rid; ins=1; next }
      { print }
    ' "$task_abs" > "$task_abs.tmp" && mv "$task_abs.tmp" "$task_abs"
  else
    # frontmatter 끝 (두 번째 ---) 바로 앞에 삽입
    awk -v rid="$run_id" '
      /^---$/ { c++; if (c==2 && !ins) { print "run_id: " rid; ins=1 } }
      { print }
    ' "$task_abs" > "$task_abs.tmp" && mv "$task_abs.tmp" "$task_abs"
  fi

  info "Coordinator 세션 launch (전용 claude agent)..."
  "$SCRIPT_DIR/coord-launch.sh" "$id" "$run_id" "$wt_abs" "$agent" planner "$description" || {
    info "⚠ Coordinator launch 실패. 수동 복구 필요:"
    info "  ./scripts/coord-launch.sh $id $run_id $wt_abs $agent planner \"$description\""
    return 1
  }
  info "완료. Coordinator 세션이 체인 진행."
}

cmd_list() {
  shopt -s nullglob
  local rows=0
  printf "%-6s %-24s %-14s %-10s %-18s %s\n" "ID" "SLUG" "STATUS" "CURRENT" "PORTS(web/api/db)" "BRANCH"
  echo "─────────────────────────────────────────────────────────────────────────────────────────"
  # main 의 task.md 로 ID 발견 → live task.md (worktree) 에서 실제 상태 읽음
  for main_f in "$MAIN_REPO_ROOT/.harness/tasks"/T[0-9][0-9][0-9]-*.md; do
    [[ -f "$main_f" ]] || continue
    local id slug status current branch web api db f
    id=$(get_fm "$main_f" "id")
    f="$(live_task_file "$id")"      # 활성이면 worktree, 아니면 main 폴백
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

# cmd_advance 는 Phase 4 에서 완전 제거됨. entry case 가 stub 에러만 반환.
# 이 함수 자리에 있던 160+ 줄 로직은 archive 로 이동 (git history).

# cmd_spawn — 디버깅용: 지정 role 의 worker 를 수동으로 재 spawn.
# Phase 4 B: worker-start.sh 호출 (task.md 에서 run_id/agent/worktree 자동 추출).
cmd_spawn() {
  local id role
  id="$(resolve_task_id "${1:-}")"
  role="${2:-}"
  local f; f="$(live_task_file "$id")"
  [[ -z "$role" ]] && role="$(get_fm "$f" current_role)"
  [[ -n "$role" ]] || die "role 을 지정하거나 task.md 에 current_role 이 있어야 함"
  local slug run_id agent
  slug="$(get_fm "$f" slug)"
  run_id="$(get_fm "$f" run_id)"
  [[ -n "$run_id" ]] || die "task.md 에 run_id 없음 — Phase 4 orchestration Run 필요"
  # required_roles 에서 role 의 agent 매핑 추출
  agent="$(awk -v r="$role" '
    /^required_roles:/ { b=1; next }
    /^[a-zA-Z_]+:/ { b=0 }
    b && index($0, "role: " r) { if (match($0, /agent:[[:space:]]*[a-z0-9]+/)) { print substr($0, RSTART+6); exit } }
  ' "$f" | sed -E 's/[[:space:]]+//g; s/,.*//; s/}.*//')"
  [[ -n "$agent" ]] || agent="${HARNESS_DEFAULT_AGENT:-claude}"
  local wt_abs="$WORKTREES_DIR/${id}-${slug}" wt_orca
  wt_orca="$wt_abs"
  command -v cygpath >/dev/null 2>&1 && wt_orca="$(cygpath -m "$wt_abs")"
  info "worker-start: $id $role (agent=$agent, run=$run_id)"
  "$SCRIPT_DIR/orca/worker-start.sh" "$id" "$role" "$wt_orca" "$agent" "$run_id" "(manual spawn)"
}

# rework: current_role 을 지정 역할로 되돌리고 그 agent 를 재 spawn.
#   QA/reviewer 가 fail 판정했을 때 담당 역할(backend/frontend)로 돌리는 용도.
cmd_rework() {
  local given_id="" to_role=""
  local no_spawn="${HARNESS_NO_SPAWN:-0}"
  if [[ "$no_spawn" == "1" ]]; then
    # 사람 interactive TTY 전용 — agent 세션(orca-spawned PTY, non-interactive shell)에서는 거부
    if [[ ! -t 0 || "${ORCA_AGENT_SESSION:-}" == "1" ]]; then
      die "HARNESS_NO_SPAWN=1 은 사람 interactive TTY 전용. agent 세션에선 금지됨. (자동 spawn 끄지 말고 그대로 체인 유지)"
    fi
    info "⚠ HARNESS_NO_SPAWN=1: 자동 spawn 생략 (디버깅 모드)"
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-spawn) die "--no-spawn 플래그는 제거됨. 디버깅용으로 자동 spawn 끄려면 'HARNESS_NO_SPAWN=1 ./scripts/tasks.sh ...' 로 환경변수 사용." ;;
      *)
        if [[ -z "$given_id" ]]; then given_id="$1"
        elif [[ -z "$to_role" ]]; then to_role="$1"
        else die "unexpected arg: $1"; fi
        shift ;;
    esac
  done
  local id
  id="$(resolve_task_id "$given_id")"
  [[ -n "$to_role" ]] || die "rework 할 역할 지정 필요. 예: tasks.sh rework T003 frontend"
  local f
  f="$(live_task_file "$id")"
  if [[ "$f" == "$(task_file "$id")" ]]; then
    die "worktree 의 live task.md 를 찾지 못함: $id"
  fi
  local current
  current="$(get_fm "$f" "current_role")"

  # 이전 역할 터미널 close
  local handles_file="$CHAT_DIR/${id}.handles"
  if [[ -f "$handles_file" ]]; then
    local prev_handle
    prev_handle=$(tail -1 "$handles_file" | awk -F'"handle":"' '{print $2}' | awk -F'"' '{print $1}')
    if [[ -n "$prev_handle" ]]; then
      info "이전 역할 ($current) 터미널 close: $prev_handle"
      orca terminal close --terminal "$prev_handle" --json >/dev/null 2>&1 || true
    fi
  fi

  sed -i.bak "s|^current_role: .*|current_role: $to_role|" "$f"
  rm -f "${f}.bak"
  info "$id: rework — current_role $current → $to_role"
  "$SCRIPT_DIR/chat.sh" append "$id" "$current" "$to_role" handoff "rework: $current → $to_role (수정 작업 요청)" >/dev/null

  local hist_file="$CHAT_DIR/${id}.role-history.jsonl"
  mkdir -p "$CHAT_DIR"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"role\":\"$current\",\"outcome\":\"rework\",\"next\":\"$to_role\"}" >> "$hist_file"

  if [[ $no_spawn -eq 1 ]]; then
    info "(--no-spawn: $to_role agent 는 수동으로 spawn 하세요)"
  else
    info "$to_role agent 재 spawn (worker-start)..."
    cmd_spawn "$id" "$to_role"
  fi
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
    git worktree remove --force "$wt_abs" 2>/dev/null || rm -rf "$wt_abs" 2>/dev/null || info "  ⚠ worktree 디렉토리 완전 삭제 실패 (수동 cleanup 필요)"
    info "  worktree removed"
  fi
  git branch -D "$branch" >/dev/null 2>&1 || true
  info "  branch deleted"

  # artifacts → archive (chat log, handles, task.md 는 git tracked 라 커밋만 함)
  mkdir -p "$ARCHIVE_DIR"
  [[ -f "$CHAT_DIR/${id}.jsonl" ]] && mv "$CHAT_DIR/${id}.jsonl" "$ARCHIVE_DIR/" && info "  chat.jsonl → archive"
  [[ -f "$CHAT_DIR/${id}.handles" ]] && mv "$CHAT_DIR/${id}.handles" "$ARCHIVE_DIR/" && info "  handles → archive"
  # main의 task.md 는 history 보존을 위해 archive 로 이동(git mv)
  if [[ -f "$f" ]]; then
    local f_name
    f_name="$(basename "$f")"
    git mv "$f" ".harness/archive/$f_name" 2>/dev/null || mv "$f" "$ARCHIVE_DIR/"
    git -c core.hooksPath=/dev/null commit -m "${id} [harness]: archive task.md after merge" >/dev/null 2>&1 || true
    info "  task.md → archive"
  fi

  info "완료: $id merged."
}

cmd_drop() {
  local given_id=""
  local force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|--force|-y) force=1; shift ;;
      *) given_id="$1"; shift ;;
    esac
  done
  local id
  id="$(resolve_task_id "$given_id")"
  local f
  f="$(task_file "$id")"
  local branch slug wt_abs
  branch=$(get_fm "$f" "branch")
  slug=$(get_fm "$f" "slug")
  wt_abs="$REPO_ROOT/.worktrees/${id}-${slug}"

  info "drop $id — 폐기합니다."
  if [[ $force -eq 0 ]]; then
    read -r -p "정말로? 되돌릴 수 없습니다 [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || { info "취소됨"; return; }
  else
    info "  (--yes: 확인 스킵)"
  fi

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

  # chat log 도 archive — jsonl / slack(thread_ts) 보존, handles/processed/cursor 는 삭제
  for suffix in jsonl slack role-history.jsonl; do
    [[ -f "$CHAT_DIR/${id}.${suffix}" ]] && mv "$CHAT_DIR/${id}.${suffix}" "$ARCHIVE_DIR/"
  done
  rm -f "$CHAT_DIR/${id}.handles" "$CHAT_DIR/${id}.processed-dispatches"
  rm -f "$MAIN_REPO_ROOT/.harness/coord/relay-thread-${id}.cursor"

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
  advance)  die "advance 명령은 Phase 4 에서 완전히 제거됐습니다. agent 는 orca orchestration worker-done 을 호출해야 합니다. 자세히는 .harness/COORDINATOR.md 와 bootstrap-prompt 참조." ;;
  rework)   cmd_rework "$@" ;;
  merge)    cmd_merge "$@" ;;
  drop)     cmd_drop "$@" ;;
  show)     cmd_show "$@" ;;
  spawn)    cmd_spawn "$@" ;;
  ""|-h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
