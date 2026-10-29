## kiro — Worker 특유 지침

### 작업 흐름

1. preamble 하단의 **Orchestration IDs** 섹션을 반드시 기억 (Task ID / Dispatch ID / Run ID). `worker_done` 전송 시 필수.
2. `./scripts/role.sh <role>` 호출로 역할 지침 로드.
3. 역할 지침대로 작업 + 커밋.
4. 완료 시 `./scripts/chat.sh append ... deliver` 로 리포트 → `orca orchestration send --type worker_done ...` 호출.

### Windows 장기 명령 주의 (중요)

**`WORKPLAN.md:548` 미해결**: `pnpm dev` / `docker compose up` (foreground) 같은 종료 안 되는 명령은 kiro-cli 세션을 멈춤.

- qa 역할: `docker compose up` 대신 `docker compose up -d` 사용. 로그 확인은 `docker compose logs --tail=50`.
- 프론트/백 서버 띄울 때도 백그라운드.
- 테스트는 `pnpm test` 1회 실행만. `--watch` 금지.
- 긴 명령 결과를 봐야 하면 파일로 리다이렉트 후 `cat` (`pnpm build > /tmp/build.log 2>&1; cat /tmp/build.log`).

### 파일 수정

kiro editor 사용. shell heredoc 으로 전체 파일 overwrite 지양 — 특히 복잡한 escape (backtick, $) 가 섞이면 깨짐.

### Blocking user prompt (`orca orchestration ask`)

worker 가 사용자에게 질문해야 할 때는 **반드시 2단계**:

1. 먼저 Slack 스레드에 질문 포스트: `./scripts/chat.sh append $TASK_ID $ROLE coordinator question "Q1: ..."`
2. 그 다음 `orca orchestration ask --from <handle> --question "..."` 로 blocking 대기

Slack 포스트 없이 `ask` 만 호출하면 질문 내용이 사용자에게 안 보임 (T026 사례).
