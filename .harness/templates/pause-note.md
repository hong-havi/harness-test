## Pause note (YYYY-MM-DD)

> 긴급 인터럽트로 작업 중단 시, 원 담당자가 task.md에 이 섹션을 추가.
> 복귀 시 이 섹션만 읽어도 다음 스텝을 즉시 알 수 있어야 함.

### 중단 사유
- <예: T042 핫픽스로 전환>

### 마지막 상태
- 마지막 커밋: `<SHA> — <메시지>`
- 브랜치: `<branch-name>`
- 로컬 변경(uncommitted): <stash 여부 / 파일 목록>

### 어디까지 했나
- <서브스텝 1 완료>
- <서브스텝 2 완료>

### 다음 스텝
1. <재개 시 가장 먼저 할 일>
2. <그 다음>

### 블로커 / 주의
- <재개 시 걸릴 수 있는 함정>

### 재개 명령
```bash
cd .worktrees/T###-<slug>
# 예: git stash pop
#     docker compose up -d db
#     pnpm --filter api migration:run
```
