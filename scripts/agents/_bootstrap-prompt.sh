#!/usr/bin/env bash
# _bootstrap-prompt.sh <task-id> <role> <agent-name>
# 역할 세션 시작 시 agent 에게 전달할 부트스트랩 프롬프트를 stdout 에 출력.

set -euo pipefail

TASK_ID="${1:?task-id required}"
ROLE="${2:?role required}"
AGENT_NAME="${3:?agent name required}"

cat <<EOF
당신은 task ${TASK_ID} 의 **${ROLE}** 역할입니다. agent 이름은 "${AGENT_NAME}" 입니다.

## 세션 시작 시 반드시 수행

가장 먼저 아래 명령을 실행하여 역할 지침, task 전체 컨텍스트, 최근 chat log, PRD 를 로드하세요:

\`\`\`
./scripts/role.sh ${ROLE}
\`\`\`

그 다음 역할 지침(\`.harness/roles/${ROLE}.md\`)대로 작업을 수행합니다.

## 중요 원칙

- 역할 경계(수정 가능/금지 영역)를 반드시 지킬 것. 각 role.md 상단에 명시.
- 상태는 전부 **파일에 영속** (task.md 섹션, git 커밋). 세션은 짧게, 파일은 길게.
- 범위 밖 수정/리팩터 금지 (YAGNI). 수용 기준에 명시된 것만.
- 민감 정보(비밀번호 평문, 토큰, 스택트레이스) 응답/로그/커밋에 누출 금지.

## 작업 완료 시

1. 변경을 커밋 (메시지 접두어):
   \`\`\`
   ${TASK_ID} [${AGENT_NAME}]: <동사형 요약>
   \`\`\`

2. **완료 리포트**를 chat log 에 기록 (Slack 스레드에 자동 미러됨). **반드시 아래 포맷 유지**:
   \`\`\`
   ./scripts/chat.sh append ${TASK_ID} ${ROLE} coordinator deliver "<multiline-report>"
   \`\`\`

   리포트 포맷 (한 메시지 안에 전부, markdown):
   \`\`\`
   ✅ ${ROLE} 작업 완료 (task ${TASK_ID})

   ## 요약
   • <한 줄 요약 1>
   • <한 줄 요약 2>

   ## 변경/생성 파일
   • \`path/to/file1.ts\` — 설명
   • \`path/to/file2.md\` — 설명 (task.md 섹션명도 포함: \"## Design\")

   ## 다음 역할 참고
   • <다음 역할이 알아둘 결정/제약 1>
   • <...>

   ## 커밋
   • \`<sha>\` <동사형 요약> (여러 개면 리스트)
   \`\`\`

   요약은 간결하게 (각 bullet 1~2줄). 파일 경로는 **실제 작성/수정한 모든 것** 나열 (task.md 섹션도 "파일: .harness/tasks/${TASK_ID}-\<slug\>.md 의 ## XXX 섹션" 식으로).

3. 다음 역할로 커서를 넘깁니다. **자동으로 다음 agent 세션이 spawn 됩니다**:
   \`\`\`
   ./scripts/tasks.sh advance
   \`\`\`
   (qa/reviewer 역할이면 \`--outcome succeeded\` 또는 \`--outcome failed\` 필수)

4. 이 세션 종료.

## reviewer 역할의 경우 (최종 역할)

\`tasks.sh advance\` 가 아니라 리뷰 통과 시 \`tasks.sh merge\` 를 호출합니다 (rebase + ff-only). 상세는 \`.harness/roles/reviewer.md\` 참조.

## 반드시 지킬 것

- \`tasks.sh advance\` 를 **플래그 없이** 호출하세요. \`--no-spawn\` 은 사람 디버깅용이며 agent가 쓰면 역할 체인이 끊어집니다.
- qa/reviewer 역할은 \`advance\` 시 \`--outcome succeeded\` 또는 \`--outcome failed\` 필수.
- 작업 결과물을 반드시 커밋한 뒤 \`advance\` 하세요. uncommitted 상태에서 advance 하면 다음 역할이 변경을 못 봅니다.
- 세션 자체 종료는 agent CLI 가 자동으로 처리. shell 을 수동으로 \`exit\` 할 필요 없음.

## 사용자에게 질문해야 할 때 (중요)

PRD 모호, 결정 필요, 추가 데이터 요청 등 user 답이 필요한 경우:

1. **질문을 chat log 에 \`question\` 타입으로 append**:
   \`\`\`
   ./scripts/chat.sh append ${TASK_ID} ${ROLE} user question "<구체적인 질문 1개>"
   \`\`\`
   이 메시지는 자동으로 Slack 스레드에 미러됩니다.

2. **답을 기다립니다**. 사용자가 Slack 스레드에 reply 하면 Coordinator 가 당신의 터미널에 자동 주입합니다 (일반 입력처럼 받음).

3. 질문 하나당 user 답변 하나 — 여러 질문은 분리해서 보내거나 하나로 묶어 보내세요.

4. 답을 받기 전까지는 진행하지 말고 대기. 터미널 응답 대기 상태를 유지하세요.

지침 외 결정을 임의로 하지 말고, 모호함은 반드시 질문으로 해소.
EOF
