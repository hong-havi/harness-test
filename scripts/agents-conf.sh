#!/usr/bin/env bash
# scripts/agents-conf.sh — agents.conf 로더 + lookup helper.
#
# source 후 사용:
#   source "$MAIN_REPO_ROOT/scripts/agents-conf.sh"
#   agent="$(conf_agent_for planner)"       # kiro
#   model="$(conf_model_for planner)"       # (빈 문자열 = --model 미전달)
#   agent="$(conf_coordinator_agent)"       # claude
#   model="$(conf_coordinator_model)"       # claude-sonnet-4-5
#
# model 이 'auto' 또는 빈 값이면 함수가 **빈 문자열** 반환 → 호출측에서
# `${model:+--model "$model"}` 패턴으로 flag 조건부 전달.

set -u

_conf_this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_conf_git_common="$(cd "$_conf_this_dir" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
if [[ "$_conf_git_common" = /* || "$_conf_git_common" =~ ^[A-Z]:/ ]]; then
  _CONF_REPO_ROOT="$(dirname "$_conf_git_common")"
else
  _CONF_REPO_ROOT="$(cd "$_conf_this_dir/.." && pwd)"
fi

_CONF_FILE="$_CONF_REPO_ROOT/.harness/agents.conf"
_CONF_LOCAL="$_CONF_REPO_ROOT/.harness/agents.local.conf"

# 1차: committed defaults
if [[ -f "$_CONF_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$_CONF_FILE"
fi

# 2차: user override (gitignore)
if [[ -f "$_CONF_LOCAL" ]]; then
  # shellcheck disable=SC1090
  source "$_CONF_LOCAL"
fi

# 최종 안전망 — 둘 다 비어 있으면 claude 로 fallback
: "${HARNESS_DEFAULT_AGENT:=claude}"
: "${HARNESS_DEFAULT_MODEL:=auto}"
: "${HARNESS_COORDINATOR_AGENT:=claude}"
: "${HARNESS_COORDINATOR_MODEL:=auto}"

# role 이름을 대문자로 치환 ("planner" -> "PLANNER")
_conf_upper() {
  echo "$1" | tr '[:lower:]' '[:upper:]'
}

# model 값이 'auto' 또는 빈 값이면 "" 반환, 아니면 그대로.
_conf_resolve_model() {
  local v="${1:-}"
  if [[ -z "$v" || "$v" == "auto" ]]; then
    echo ""
  else
    echo "$v"
  fi
}

# conf_agent_for <role>
# 1) HARNESS_<ROLE>_AGENT 가 비어있지 않으면 그 값
# 2) 아니면 HARNESS_DEFAULT_AGENT
conf_agent_for() {
  local role="${1:?role required}"
  local upper
  upper="$(_conf_upper "$role")"
  local var_name="HARNESS_${upper}_AGENT"
  local val="${!var_name:-}"
  if [[ -n "$val" ]]; then
    echo "$val"
  else
    echo "${HARNESS_DEFAULT_AGENT}"
  fi
}

# conf_model_for <role>
# 1) HARNESS_<ROLE>_MODEL 이 비어있지 않으면 그 값 (단, 'auto' 는 "")
# 2) 아니면 HARNESS_DEFAULT_MODEL (단, 'auto' 는 "")
conf_model_for() {
  local role="${1:?role required}"
  local upper
  upper="$(_conf_upper "$role")"
  local var_name="HARNESS_${upper}_MODEL"
  local val="${!var_name:-}"
  if [[ -n "$val" ]]; then
    _conf_resolve_model "$val"
  else
    _conf_resolve_model "${HARNESS_DEFAULT_MODEL}"
  fi
}

conf_coordinator_agent() {
  echo "${HARNESS_COORDINATOR_AGENT}"
}

conf_coordinator_model() {
  _conf_resolve_model "${HARNESS_COORDINATOR_MODEL}"
}

# 간단한 자가 테스트: scripts/agents-conf.sh --dump 로 호출하면 전체 매핑 출력
if [[ "${1:-}" == "--dump" ]]; then
  echo "# Resolved agent/model config (from $_CONF_FILE${_CONF_LOCAL:+ + $_CONF_LOCAL})"
  echo "coordinator: agent=$(conf_coordinator_agent) model='$(conf_coordinator_model)'"
  for r in planner architect designer backend frontend qa reviewer; do
    echo "$r: agent=$(conf_agent_for "$r") model='$(conf_model_for "$r")'"
  done
fi
