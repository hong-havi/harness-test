## kiro-cli 세션 공통 지침

이 agent 는 **kiro-cli** 입니다. 모든 역할 (Coordinator / worker) 공통.

### ⚠️ Shell 명령 — `bash` 접두어 **절대 금지**

kiro-cli 에서 `bash <script>` 로 명시 호출 시 **WSL `/bin/bash`** 로 fallback → Windows path 를 못 찾아 실패:

    ❌  bash ./scripts/chat.sh append ...        # → "No such file or directory"
    ❌  bash scripts/orca/worker-start.sh ...
    ✅  ./scripts/chat.sh append ...             # shebang 가 git-bash 로 자동 라우팅
    ✅  orca orchestration send ...              # orca 자체는 bash 필요 없음

**반드시** 스크립트는 직접 호출. shebang `#!/usr/bin/env bash` 라우팅 신뢰. T022/T025 반복 결함.

### 파일 작업

kiro-cli 자체 editor 사용. shell 로 큰 heredoc 작성 지양. 작은 수정은 editor, 대량 생성은 Write 패턴.

### 장기 실행 명령 — Windows 결함 주의

**`WORKPLAN.md:548` 미해결**: kiro-cli 가 Windows 에서 `pnpm dev`, `docker compose up` (foreground) 같이 **종료 안 되는 명령**을 실행하면 세션이 멈춤.

- 반드시 `-d` / `--detach` 플래그 또는 백그라운드로. 포그라운드 blocking 명령 금지.
- 테스트는 1회 실행형 (`pnpm test` 1회, `--watch` 금지).

### 민감정보

API 토큰, 비밀번호 평문, 긴 스택트레이스 등은 응답/로그/커밋에 노출 금지. `.env`, `.env.*` 는 git 커밋 금지.
