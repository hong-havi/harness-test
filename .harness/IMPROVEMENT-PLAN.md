# 하네스 개선 계획 (3-Tier)

작성일: 2026-10-29
근거: `.harness/WORKPLAN.md` Phase 4 S++ 상태 전수 감사 (리소스/토큰 비용 측면)

---

## 배경

task-per-worktree + 7-role + Orca orchestration 하네스를 **다른 프로젝트에 복제하기 전** 리소스/토큰 비용 측면에서 손봐야 할 지점 정리.

핵심 문제 요약:
1. **Coordinator 가 LLM(Opus) 세션으로 돌면서 `check --wait 60s` 블록킹 polling 을 LLM turn 단위로 반복** — 세션당 수십 Opus turn 소비
2. **role 전환마다 신규 agent 세션 cold-start** — role.md + bootstrap-prompt + task.md 가 매 role 재주입 → prompt caching 0
3. **작은 변경에도 full 7-role 체인 overkill** — 1-line 수정에 4+ 세션

---

## Tier 1 — 즉시 적용 (리스크 낮음, 토큰 ~50% 절감)

### 1. Agent/모델 기본값 외부 설정화

**현상**: `scripts/coord-launch.sh:46` 에 `--agent claude` 하드코딩. 모델 지정 없음 → Orca/claude-cli 기본값 (Opus) 사용.

**개선**:
- `.harness/agents.conf` (git-tracked) + `.harness/agents.local.conf` (gitignore, 사용자 override) 로 분리
- 역할별 `HARNESS_<ROLE>_AGENT` + `HARNESS_<ROLE>_MODEL` 변수
- `scripts/agents-conf.sh` 로더 helper 가 두 파일을 source + fallback 체인 제공
- 기본값:
  - `HARNESS_COORDINATOR_AGENT=claude`, `HARNESS_COORDINATOR_MODEL=claude-sonnet-4-5` (Opus → Sonnet)
  - `HARNESS_DEFAULT_AGENT=kiro`, `HARNESS_DEFAULT_MODEL=auto` (= `--model` 미전달, 각 agent 자체 설정 사용)
  - 역할별 변수는 비워두고 default 로 fallback

**트레이드오프**: Sonnet 으로 escalation/충돌 판단 품질 저하 가능. 복잡한 체인에서 재조정 필요할 수 있음.

### 2. `check --wait` timeout 60s → 600s

**현상**: `coord-launch.sh:91`, `.harness/roles/coordinator.md:45` 에 60000ms. 메시지가 없으면 60초마다 Coordinator LLM 턴이 "timeout" 응답으로 소비됨. 1 task 당 평균 수십 턴 낭비.

**개선**: 600000ms (10분) 로 상향. 메시지 즉시 수신 시 응답성 영향 없음.

**트레이드오프**: 없음. 순이득.

### 3. `required_roles` 기본값 축소 (planner 지침)

**현상**: `.harness/roles/planner.md:25` "거의 항상 포함: planner, architect, backend 또는 frontend 중 하나 이상, qa, reviewer" → 1-line fix 도 5+ 역할.

**개선**: planner.md 에 "trivial 변경 분류" 추가:
- **Trivial** (1 file / <20 lines / UI 텍스트/스타일 등): `[frontend 또는 backend, reviewer]` — qa/architect 생략
- **Standard**: 기존 full chain
- planner 가 판단해서 선택

**트레이드오프**: planner 가 trivial 오판 시 품질 저하. reviewer 가 catch 가능.

---

## Tier 2 — 2~3일 작업 (구조 변경, 추가 ~30% 절감)

### 4. Worker session 재사용 (role chain → single session + phase marker)

**현상**: `scripts/orca/worker-start.sh` 가 role 전환마다 신규 세션 → preamble/role.md/task.md 재주입.

**개선**: 하나의 worker 세션 안에서 `[PHASE: architect]` → `[PHASE: backend]` 마커로 역할 전환. Orca `send` 로 다음 phase 지시 주입. preamble 재주입 제거 + prompt caching 가능.

**트레이드오프**: role 간 agent 혼용 (planner=kiro, backend=codex) 포기. 다중 agent 가 실제로 가치가 있었는지 재검토.

### 5. Slack polling → Events webhook 또는 폐기

**현상**: `scripts/slack/relay.sh:45` `POLL_INTERVAL=5` 상시 데몬. 활성 task 3개 시 Tier 2 rate limit 초과 가능.

**개선**: Slack Events API webhook (Cloudflare tunnel) 전환 또는 **Slack 자체 포기**하고 CLI 전용 운영. 사용 빈도 평가 선행.

**트레이드오프**: 모바일 지시 포기 (webhook 전환이면 유지).

### 6. Archive rotation + orphan GC 자동화

**현상**: `.harness/archive/` move-only, 삭제·압축 없음. `harness-status.sh --kill-orphans` 수동.

**개선**:
- `tasks.sh merge/drop` 끝에 30일+ archive gzip
- Windows Task Scheduler / cron 1h 주기 `--kill-orphans` 호출
- `relay.log` logrotate

**트레이드오프**: 없음.

---

## Tier 3 — 재아키텍처 (고효과, 설계 재검토 필요)

### 7. Coordinator-as-bash 재도전

**현상**: `project_phase4_bind_gap.md` 메모에 "Orca run bind 는 agent 세션 단위라 bash daemon 불가" 결정. 이게 Coordinator LLM 비용의 근본 원인.

**재검토 지점**:
- Orca CLI 에 `--run <id>` 를 argv 로 직접 받는 모드가 있는지 (`worker-start --run` 처럼)
- bash 가 `claude -p "..."` 로 1-turn oneshot 호출하는 하이브리드 — Coordinator "지능" 이 정말 필요한 분기만 LLM 에 위임
- node daemon + Anthropic SDK direct call (Orca 우회)

**효과**: Coordinator LLM 비용 거의 0.

**트레이드오프**: Orca API 재조사 필요. Phase 4 B 전환의 "진짜 이유" 검증 필요.

### 8. 하네스 적용 criteria 명문화

**현상**: 모든 task 가 full 체인 통과. 1-line fix 도 포함.

**개선**: README 에 적용 가이드 명시:
- **하네스 사용 O**: PRD-impacting 변경 (새 엔티티, API 계약, 보안·성능 영향)
- **하네스 사용 X**: 1-line fix, 문구/스타일 변경, dependency bump → 수동 또는 single-agent `claude -p` 1회

**트레이드오프**: 사람이 매번 분류해야 함. 하지만 slug/변경 라인 수 기반 자동화 가능.

---

## 추천 실행 순서

1. **지금 (Tier 1)**: 1,2,3 을 1 PR 로 묶어 적용. 1~2 시간. 즉시 50% 토큰 절감 확인.
2. **1 task pilot**: 조정된 상태로 작은 task 1개 돌려 chat 로그에서 토큰 소비 측정.
3. **다음 주 (Tier 2)**: 6 → 4 순서. 5 는 Slack 사용 빈도 평가 후.
4. **복제 시점**: Tier 1 적용 상태 + Tier 3-8 criteria 를 복제 대상 프로젝트에 맞게 정립.

## 미해결 선결 과제 (복제 전 반드시)

`WORKPLAN.md:548-552` 미해결 Windows 전용 결함 3건은 **복제 대상이 Windows 가 아니면 재현 안 됨**. 하지만 macOS/Linux 는 **새로운 결함 세트** 등장 확률 높음:
- (1) kiro qa dev server 반복 멈춤
- (2) pnpm symlink Windows 자동 cleanup 불가
- (3) reviewer `tasks.sh merge` Windows shell output capture 멈춤

---

## 참고

- 감사 보고서 원본은 세션 로그 참조
- 관련 memory: `project_phase4_bind_gap.md`
