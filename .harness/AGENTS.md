# Agent 적합도 가이드

Phase 2 end-to-end 테스트에서 관찰된 agent별 특성과 역할 추천.

## 지원 에이전트

| Agent | 어댑터 | Orca 통합 | 특성 |
|-------|--------|-----------|------|
| **claude** | `scripts/agents/claude.sh` → `orca agent launch --agent claude` | 네이티브 | 긴 orchestration 안정적, 리뷰·설계 추론 강함 |
| **codex** | `scripts/agents/codex.sh` → `orca agent launch --agent codex` | 네이티브 | 반복적 코드 작성 효율 |
| **kiro** | `scripts/agents/kiro.sh` → `orca terminal create` + `kiro-cli chat` | 터미널 래핑 | 단일 산출물 작성 OK, 긴 orchestration 에서 dispatch failure 관찰 |

## 역할별 추천

| 역할 | 1st choice | Fallback | 비고 |
|------|:----------:|:--------:|------|
| planner | **claude** | codex | 설계·명세 긴 추론. 수용 기준 측정가능하게 작성 필요 |
| architect | **claude** | codex | 엔티티/API 계약, 보안 고려. 긴 설계 추론 |
| designer | **claude** (+ Figma MCP) | - | Figma MCP 는 claude에서만 안정. kiro/codex 는 MCP 지원 약함 |
| backend | **claude** | codex, kiro | 모듈 구현. 쓰기 많으면 kiro OK |
| frontend | **claude** | kiro, codex | UI 뼈대 작성은 kiro도 성공 관찰 (T002 frontend) |
| qa | **claude** | - | **kiro 비추천** — UAT 는 긴 docker + curl 체인, dispatch failure 반복 관찰 |
| reviewer | **claude** | - | **kiro 비추천** — rebase + merge + 리뷰 긴 orchestration, 안정성 중요 |
| coordinator | **claude** | - | 사용자 접점. 긴 세션 유지 필요 (Phase 3) |

## 관찰 기록 (T002 member-module end-to-end)

- **kiro frontend**: `apps/web/` 전체 스캐폴드 작성 **성공**, 커밋 전 UAT 단계에서 **dispatch failure** → 수동 커밋 후 다음 역할로 넘김
- **kiro qa**: API 백그라운드 띄우기 중 **dispatch failure** 반복 → claude 로 교체 후 31/31 UAT 통과
- **kiro reviewer**: .dockerignore 추가 + rebase + merge **성공** (단일 수정이라 짧은 세션)

## 역할별 agent 설정

task.md 의 `required_roles[].agent` 에 명시:

```yaml
required_roles:
  - { role: planner,    agent: claude }
  - { role: architect,  agent: claude }
  - { role: designer,   agent: claude, mcp: [figma] }  # Figma 필요시
  - { role: backend,    agent: claude }
  - { role: frontend,   agent: claude }
  - { role: qa,         agent: claude }                 # kiro 비추천
  - { role: reviewer,   agent: claude }                 # kiro 비추천
```

planner 가 task 생성 시 required_roles 선언. 기본값은 전부 claude. 특정 역할에 다른 agent 쓰려면 명시.

## 미지원 agent (`kiro.sh` 폴백 대상)

- gpt, custom: 어댑터 미작성. 추가하려면 `scripts/agents/<name>.sh` 작성 (claude.sh 참고) + `--agent <name>` 매핑.
