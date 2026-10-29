## Claude Code 세션 공통 지침

이 agent 는 **Claude Code CLI** 입니다. 모든 역할 (Coordinator / worker) 공통.

### Shell 실행 수단

- Shell 명령은 **bash tool** 로 호출. shebang `#!/usr/bin/env bash` 가 자동으로 git-bash 로 라우팅하므로 `bash` 접두어 명시 불필요:

      ✅  ./scripts/chat.sh append ...
      ❌  bash ./scripts/chat.sh append ...   # Windows 에서 WSL 로 fallback

- `run_in_background: true` 는 **장기 실행 명령에만** (예: `pnpm dev`, `docker compose up`). 짧은 명령에 쓰지 말 것. 백그라운드 띄우면 **Monitor tool** 로 출력 스트림.

### 파일 작업

- 수정: **Edit tool** (`old_string` / `new_string`). bash 로 sed/awk 지양.
- 신규 작성: **Write tool**.
- 읽기: **Read tool**. bash 로 cat/head/tail 지양.
- 검색: **Grep / Glob tool**. bash 로 grep/rg/find 지양.

### 민감정보

API 토큰, 비밀번호 평문, 긴 스택트레이스 등은 응답/로그/커밋에 노출 금지. `.env`, `.env.*` 는 git 커밋 금지.
