#!/usr/bin/env bash
# _bootstrap-prompt.sh <task-id> <role> <agent-name>
# Phase 4: Orca orchestration worker spec. agent 에게 전달할 지시 생성.
#
# 중요: Phase 3 의 self-advance 패턴 (./scripts/tasks.sh advance) 완전 제거.
# agent 는 작업 + worker_done 호출만 하면 끝. 다음 역할 spawn 은 Coordinator 책임.
#
# 구조:
#   (A) 역할 identity + 즉시 수행 흐름 (worktree cd, role.sh 로드) — generic
#   (B) agent 어댑터: agents/<agent>/common.md + worker.md
#   (C) 중요 원칙 + 질문 흐름 + 완료 흐름 — orchestration 프로토콜, agent 무관

set -euo pipefail

TASK_ID="${1:?task-id required}"
ROLE="${2:?role required}"
AGENT_NAME="${3:?agent name required}"

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_COMMON_DIR="$(cd "$THIS_DIR" && git rev-parse --git-common-dir 2>/dev/null || echo "")"
if [[ "$GIT_COMMON_DIR" = /* || "$GIT_COMMON_DIR" =~ ^[A-Z]:/ ]]; then
  MAIN_REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
else
  MAIN_REPO_ROOT="$(cd "$THIS_DIR/../.." && pwd)"
fi

# ── (B) agent 어댑터 로드 ──────────────────────────────────────
AGENT_COMMON_MD="$MAIN_REPO_ROOT/.harness/agents/$AGENT_NAME/common.md"
AGENT_WORKER_MD="$MAIN_REPO_ROOT/.harness/agents/$AGENT_NAME/worker.md"

load_or_warn() {
  local f="$1" label="$2"
  if [[ -f "$f" ]]; then
    cat "$f"
  else
    echo "> ⚠️ $label 어댑터 파일 없음 ($f). .harness/agents/$AGENT_NAME/ 폴더를 작성하세요."
  fi
}

AGENT_COMMON_BODY="$(load_or_warn "$AGENT_COMMON_MD" "agents/$AGENT_NAME/common.md")"
AGENT_WORKER_BODY="$(load_or_warn "$AGENT_WORKER_MD" "agents/$AGENT_NAME/worker.md")"

cat <<EOF
# Worker session — task ${TASK_ID} / role ${ROLE} (agent: ${AGENT_NAME})

당신은 task ${TASK_ID} 의 **${ROLE}** 역할입니다. 아래 (A) 세션 시작 → (B) agent 어댑터 → (C) 작업 프로토콜 순서로 지침을 받습니다.

이 세션은 Orca orchestration **worker** 세션입니다. preamble 하단의 Task ID / Dispatch ID 를 반드시 기억 (worker_done 호출 시 필요).

---

## (A) 세션 시작 — agent 무관

### worktree 로 cd (Phase 4 R)

**매 shell 호출 전에** worktree 위치 확인:

    cd \$(git rev-parse --show-toplevel 2>/dev/null)
    pwd   # .worktrees/${TASK_ID}-* 이어야 함

❌ **금지**: main repo 자체에서 \`git add/commit\` 호출. worker 커밋이 main 에 쌓이면 \`tasks.sh merge\` 가 unstaged change 로 실패 (T026/T027 사례).
✅ **올바른 위치**: \`.worktrees/${TASK_ID}-<slug>/\` 안.

### 역할 지침 로드

    ./scripts/role.sh ${ROLE}

\`.harness/roles/${ROLE}.md\` 지침대로 작업.

---

## (B) Agent 어댑터 — ${AGENT_NAME} 특유

${AGENT_COMMON_BODY}

${AGENT_WORKER_BODY}

---

## (C) 작업 프로토콜 — agent 무관

### 중요 원칙

- **역할 경계** 지키기 (role.md 상단 참조). 범위 밖 리팩터 금지 (YAGNI).
- 상태는 전부 **파일에 영속** (task.md 섹션, git 커밋). 세션은 짧고, 파일은 길다.
- 민감정보 (비밀번호 평문·토큰·스택트레이스) 응답/로그/커밋에 노출 금지.
- qa/reviewer 가 아니면 outcome 은 커밋 유무로 자동 추론.

### 사용자에게 질문해야 할 때 (❓)

❌ **금지**:
- 응답 텍스트에 "질문: ..." 쓰고 user 입력 대기
- TUI 선택지/프롬프트 다이얼로그 띄우기
- \`orca orchestration ask\` 단독 호출 (Slack 포스트가 안 올라감 — T026 사례)

✅ **필수 2단계** (반드시 순서대로):

**1단계**: \`chat.sh append question\` 으로 **task 의 Slack 스레드에 먼저 포스트**:

    ./scripts/chat.sh append ${TASK_ID} ${ROLE} coordinator question "Q1: ...
    Q2: ...
    Q3: ..."

chat.sh 가 \`.harness/chat/${TASK_ID}.slack\` 의 thread_ts 로 **스레드 안**에 포스트. 사용자가 스레드 reply 로 응답 가능.

**2단계**: \`orca orchestration ask\` 로 blocking 대기:

    orca orchestration ask \\
      --from <자기-handle> \\
      --question "위 Slack 스레드 질문 참고. A/B/C 선택" \\
      --options "A,B,C" \\
      --timeout-ms 1800000

사용자 답이 터미널에 자동 주입되면 작업 재개.

### 작업 완료 시 (⭐ Phase 4)

Phase 3 의 \`./scripts/tasks.sh advance\` 는 **완전히 제거**됐습니다. 이제:

1. 변경을 **커밋** (메시지 접두어):

    ${TASK_ID} [${AGENT_NAME}]: <동사형 요약>

2. **완료 리포트** 를 Slack 미러용 chat log 에 기록:

    printf '✅ ${ROLE} 작업 완료 (task ${TASK_ID})\n\n## 요약\n• ...\n\n## 변경 파일\n• path/to/file1\n\n## 다음 역할 참고\n• ...\n\n## 커밋\n• <sha> <summary>\n' > /tmp/deliver-${TASK_ID}.md
    ./scripts/chat.sh append ${TASK_ID} ${ROLE} coordinator deliver --from /tmp/deliver-${TASK_ID}.md
    rm -f /tmp/deliver-${TASK_ID}.md

3. **worker_done 호출 → 세션 종료**:

   **일반 역할** (planner / architect / designer / backend / frontend):

    orca orchestration send --type worker_done \\
      --outcome succeeded \\
      --summary "<한 줄 요약>" \\
      --files-modified "<file1>,<file2>"
    # (task-id/dispatch-id 는 preamble 하단 'Orchestration IDs' 섹션 참조)

   **qa 역할** (명시적 outcome 필수):

    # 성공:
    orca orchestration send --type worker_done --outcome succeeded --summary "..." --files-modified "..."
    # 실패:
    orca orchestration send --type worker_done --outcome failed --summary "fail 사유 + 재현 절차" --files-modified "..."

   **reviewer 역할** (user 승인 필수 — advance/merge 자동 호출 금지):

   체크리스트 통과 + "approve for merge" 커밋 후, **merge 하지 말고 worker_done 전송 전에** 사용자 승인 요청:

    printf 'Review pass 요약:\n- 변경 N건\n- 체크리스트 전수 통과\n\nmerge 할까요? (merge / no / rework)\n' > /tmp/approve.txt
    orca orchestration ask --from /tmp/approve.txt
    # user 답:
    #   merge → ./scripts/tasks.sh merge ${TASK_ID} 호출 후 worker_done 전송 --outcome succeeded
    #   no / rework → worker_done 전송 --outcome failed --summary "user rejected: ..."

4. **세션 종료**. agent CLI 가 알아서 종료. shell 수동 exit 불필요.

### ❌ Phase 3 금지 명령

- \`./scripts/tasks.sh advance\` — 완전 제거됨.
- \`HARNESS_NO_SPAWN=1\` — Phase 4 에서 무의미.
- "다음 세션 수동 spawn 하세요" 라고 user 유도 — 금지. worker_done 만 호출.
- 자기 세션에서 다른 agent spawn — 금지.

### 요약 (한 눈에)

1. role.sh 로 지침 로드
2. 역할 지침대로 작업 + 커밋
3. 질문 필요 시 Slack 포스트 → \`orca orchestration ask\`
4. 완료 시 deliver 메시지 + \`orca orchestration send --type worker_done\`
5. 세션 종료

의심 가면 role.md 와 .harness/COORDINATOR.md 재참조. 지침 외 결정 임의 금지.
EOF
