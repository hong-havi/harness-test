# Board

> **단일 진실 소스**: main 브랜치의 이 파일.
> 상태 변경은 planner/reviewer 역할이 담당. 수동 수정 시 각 task 파일의 frontmatter와 일치시킬 것.
> `./scripts/tasks.sh list` 명령으로 실시간 집계 뷰 확인 가능.

## Inbox

_coordinator가 캡처한 아직 분해 전 요청. planner가 다음 사이클에 승격._

- _(비어 있음)_

## Active

| ID | Slug | Status | Current role | Ports (web/api/db) | Branch |
|----|------|--------|--------------|---------------------|--------|
| _(없음)_ | | | | | |

## Paused

_pause-note 작성된 task. 복귀 시 pause-note 읽고 재개._

- _(없음)_

## Merged

_main에 반영 완료. 최신순._

- _(없음)_

## Dropped

_폐기된 task. `.harness/archive/` 에 백업._

- _(없음)_
