## Claude Code — Worker 특유 지침

### 코드 수정

- 작은 변경: **Edit tool** (`replace_all` 활용). diff 가 명확하고 안전.
- 신규 파일: **Write tool**. 반드시 Read 로 선행 조회 후 작성 (덮어쓰기 사고 방지).
- bash heredoc 으로 파일 전체 overwrite 지양.

### 장기 실행 명령

- `pnpm dev`, `docker compose up` (foreground), `pnpm test --watch` 등은 **`run_in_background: true`** 로 띄우고 **Monitor tool** 로 완료 대기.
- 짧은 명령 (`git status`, `pnpm lint`) 은 포그라운드.

### Blocking user prompt

`orca orchestration ask` 는 **포그라운드** bash 호출로 (user 응답 터미널 주입 대기). background 로 띄우면 응답 수신 불가.
