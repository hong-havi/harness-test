# AGENTS.md — 프로젝트 지침

## 프로젝트
- 간단한 게시판 (회원 + 게시판 모듈). 상세 스펙은 `PRD.md` 참조.
- 스택: Next.js (apps/web) + NestJS (apps/api) + MySQL, TypeORM, JWT(HttpOnly 쿠키), pnpm 모노레포, Docker Compose.

## 하네스 진입 규칙 (중요)

**어떤 작업이든 시작 전에 반드시 역할을 설정한다.**

```bash
./scripts/role.sh <planner|backend|frontend|reviewer|qa>
```

- 역할 설정 없이 코드/문서를 수정하지 않는다.
- 역할별 경계와 산출물은 `.harness/roles/<role>.md`에 정의.
- 작업 보드는 `.harness/board.md`.

## 작업 인터럽트 규칙 (A → B)

작업 A 중 B가 들어오면:

1. B가 **핫픽스/긴급**이 아니면 → `board.md`의 **Inbox**에 추가, A 계속.
2. 긴급이면 → 현재 태스크 파일에 **pause-note** 섹션 추가(`.harness/templates/pause-note.md` 참조) → A를 Paused로 이동 → B 착수.

규칙은 `.harness/README.md`에 상세.

## 공통 작업 원칙

- `.planning/`, `.harness/tasks/`는 작업 상태 저장소. 작업 중 반드시 갱신.
- 커밋은 작업 단위로 작게. 메시지에 태스크 ID(`T###`) 포함.
- PRD.md에 반하는 설계 변경은 planner 역할에서만 반영.
- 운영 시크릿·`.env`는 커밋 금지.
