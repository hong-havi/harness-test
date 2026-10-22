---
id: T009
title: add-email
slug: add-email
branch: task/T009-add-email
worktree: .worktrees/T009-add-email
status: planning          # planning | in-flight | paused | merged | dropped
required_roles:
  - { role: planner,    agent: claude }
  - { role: architect,  agent: claude }
  # - { role: designer,   agent: claude, mcp: [figma] }
  - { role: backend,    agent: claude }
  # - { role: frontend,   agent: claude }
  - { role: qa,         agent: claude }
  - { role: reviewer,   agent: claude }
current_role: backend
role_history: []
ports:
  web: 3090
  api: 4090
  db: 3315
compose_project: harness_t009
figma_url: null
blocked_by: []
related_prd: []
priority: normal          # high | normal | low
created_at: 2026-10-22
updated_at: 2026-10-22
---

## User Request

> 회원가입에 이메일 필드 추가

---

_(T009 생성 시 user 가 전달한 원 요구사항. planner 는 이 문맥을 기준으로 Plan 섹션을 작성한다.)_


# T009 — add-email

## Plan

### Why
PRD의 회원 데이터 모델은 식별자로 `user_id`/`nickname`만 보유하여 추후 공지·계정복구 등 이메일 기반 커뮤니케이션이 불가하다. 본 작업은 이메일을 **수집·수정**할 수 있는 기반만 추가한다. 메일 발송·인증·중복 체크는 범위 밖(사용자 확정).

> PRD 변경 사유: PRD §3.1 members 테이블에 `email` 컬럼 추가. 선택 입력, UNIQUE 없음, 254자 이하.

### What
- `members.email` 컬럼 신규 추가 (nullable, UNIQUE 아님)
- 회원가입 API/화면에서 이메일을 **선택 입력**으로 받음
- 내 정보 조회(GET /me) 응답에 `email` 포함
- 내 정보 수정(PATCH /me) 으로 이메일 수정/삭제 가능
- 이메일 **포맷 검증**만 서버에서 수행 (class-validator `@IsEmail`), 메일 발송·확인 링크 없음

### Scope
- 포함:
  - `member.entity.ts`, 신규 TypeORM 마이그레이션 (up/down)
  - `signup.dto.ts` (optional email 필드)
  - `auth.service.ts` signup 분기 (email 저장)
  - `update-me.dto.ts`, `members.service.ts`, `members.controller.ts` (GET/PATCH /me email)
  - `apps/web/app/signup/page.tsx` 폼 필드 1개 추가
  - `apps/web/app/me/page.tsx` 폼 필드 1개 추가 (수정 가능)
  - `apps/web/lib/api.ts` 요청/응답 타입에 email 반영
- 제외:
  - 메일 발송 / 인증 링크 / 이메일로 로그인 / 비밀번호 찾기
  - email 중복(UNIQUE) 체크
  - 자동 로그인/세션 변경
  - 로그인 폼 변경 (여전히 user_id 기반)

### Acceptance
- [ ] DB `members` 테이블에 `email VARCHAR(254) NULL` 컬럼이 존재한다 (UNIQUE 인덱스 없음, 왕복 마이그레이션 성공)
- [ ] `POST /auth/signup` 에서 `email` 생략 시 **201/200** 로 가입 성공, 저장된 레코드의 `email`은 `NULL`
- [ ] `POST /auth/signup` 에서 유효한 email 포함 시 가입 성공, DB에 그 값이 저장됨
- [ ] `POST /auth/signup` 에서 포맷 오류(e.g. `"not-an-email"`) 또는 254자 초과 → **400** 응답
- [ ] email이 서로 다른 두 회원이 **같은 email**로 가입 가능 (중복 허용 확인)
- [ ] `GET /me` 응답 바디에 `email` 필드가 포함되며, 저장값이 없으면 `null`
- [ ] `PATCH /me` 로 email 신규 설정 / 변경 / `""`(또는 `null`) 전송으로 **삭제** 가능
- [ ] 회원가입 화면 `/signup` 에 `이메일 (선택)` input 노출, 비워도 제출 가능하며 성공 시 `/login?signup=1` 로 이동
- [ ] 내 정보 화면 `/me` 에 email 필드가 저장값으로 프리필, 수정·저장 가능
- [ ] 기존 가입/로그인/글쓰기 플로우 회귀 없음 (QA가 UAT 로 확인)

### Files touched (예상)
- `apps/api/src/members/member.entity.ts`
- `apps/api/src/migrations/<timestamp>-add-member-email.ts` (신규)
- `apps/api/src/auth/dto/signup.dto.ts`
- `apps/api/src/auth/auth.service.ts`
- `apps/api/src/auth/auth.service.spec.ts`
- `apps/api/src/members/dto/update-me.dto.ts`
- `apps/api/src/members/members.service.ts`
- `apps/api/src/members/members.controller.ts`
- `apps/api/src/members/members.service.spec.ts`
- `apps/web/app/signup/page.tsx`
- `apps/web/app/me/page.tsx`
- `apps/web/lib/api.ts`

---

## Design

### 데이터 모델

`members` 테이블에 `email` 컬럼 추가.

| 컬럼 | 타입 | 제약 | 비고 |
|------|------|------|------|
| email | VARCHAR(254) | NULL (default NULL) | UNIQUE 인덱스 **없음**. RFC 5321 상한 254자 |

- 문자셋/collation: 테이블 기본값(`utf8mb4` / `utf8mb4_unicode_ci`) 상속
- 인덱스 추가 없음 (조회/정렬 요구 없음)
- `MemberEntity`에 매핑 추가:
  ```ts
  @Column({ name: 'email', type: 'varchar', length: 254, nullable: true })
  email!: string | null;
  ```
  - `select` 기본값 유지(true) — getMe 응답 즉시 사용.

### API 계약

| Method | Path | Auth | 요청 DTO (변경) | 응답 (변경) | 상태 코드 |
|--------|------|:----:|-----------------|-------------|-----------|
| POST | `/auth/signup` | - | `SignupDto`에 `email?: string` 추가 | 기존 `PublicMember` **그대로** (email 비노출) | 201 성공 / 400 포맷·길이 / 409 중복(기존) |
| GET | `/members/me` | JWT | - | `MeView`에 `email: string \| null` 추가 | 200 / 401 |
| PATCH | `/members/me` | JWT + CSRF | `UpdateMeDto`에 `email?: string \| null` 추가 | `MeView` (갱신 반영, email 포함) | 200 / 400 / 401 / 409(nickname) |

- `/auth/login`, `/auth/logout`, `/auth/join` 는 변경 없음.
- `/auth/join` 응답에도 email 미노출 (join은 범위 밖).
- `PublicMember`(signup/login 응답)는 **의도적으로 email 미포함** — 로그인 응답 바디 최소화 유지, email은 `/members/me`로만 노출.

#### DTO 세부

**SignupDto 추가 필드**
```ts
@IsOptional()
@IsString()
@IsEmail({}, { message: 'email 형식이 올바르지 않습니다.' })
@MaxLength(254, { message: 'email은 254자 이하여야 합니다.' })
email?: string;
```
- 생략 시 저장 레코드의 `email` = `NULL`.
- 빈 문자열(`""`) 전송은 `@IsEmail` 실패 → 400. (signup에서 "지우기" 의미 없음)

**UpdateMeDto 추가 필드**
```ts
@IsOptional()
@Transform(({ value }) => (value === '' ? null : value))  // 빈 문자열 → null 정규화
@ValidateIf((_, v) => v !== null)
@IsString()
@IsEmail({}, { message: 'email 형식이 올바르지 않습니다.' })
@MaxLength(254, { message: 'email은 254자 이하여야 합니다.' })
email?: string | null;
```
- `undefined` (키 생략): 변경 안 함
- `null` 또는 `""`: email **삭제** (DB `NULL`)
- 유효 포맷 문자열: email **설정/변경**
- "최소 1개 필드" 조건에 email 포함: `!hasNickname && !hasPassword && !hasEmail` → 400

#### 응답 타입

**MeView (추가)**
```ts
export interface MeView {
  id: string;
  userId: string;
  nickname: string;
  email: string | null;      // 추가
  createdAt: Date;
  updatedAt: Date;
}
```

**프런트 `apps/web/lib/types.ts`**
- `SignupInput`에 `email?: string` 추가
- `MemberProfile`에 `email: string | null` 추가
- `UpdateMeInput`에 `email?: string | null` 추가
- `PublicMember`는 변경 없음

### 흐름

**가입 (POST /auth/signup)**
1. `ValidationPipe` 가 `SignupDto` 검증 (email 포맷/길이 포함).
2. `AuthService.signup`:
   - 기존 user_id/nickname 중복 선검사 그대로.
   - `membersRepo.create()` 호출 시 `email: dto.email ?? null` 전달.
   - 저장 성공 → `PublicMember` 반환 (email 비노출).

**내 정보 조회 (GET /members/me)**
1. `JwtAuthGuard` 통과.
2. `MembersService.getMe` → `toView()`가 `email`을 그대로 매핑. 저장값 없으면 `null` 반환.

**내 정보 수정 (PATCH /members/me)**
1. `JwtAuthGuard` + `CsrfGuard`.
2. `UpdateMeDto` 검증 — email이 넘어오면 포맷/길이 또는 null 체크 통과.
3. `MembersService.updateMe`:
   - `hasEmail = dto.email !== undefined` 플래그 추가.
   - `hasNickname || hasPassword || hasEmail` 중 하나도 없으면 400.
   - email 변경은 **중복 체크 없음** (UNIQUE 아님).
   - `patch.email = dto.email` (null 포함) 그대로 할당.
   - update 후 `getMe` 재조회로 반환.

### 보안 / 에러

- **입력 검증 지점**:
  - 서버 1차: `ValidationPipe` + `class-validator` (`@IsEmail`, `@MaxLength(254)`).
  - 프런트는 보조만: `<input type="email" maxLength={254}>` (HTML5 검증은 서버 검증을 대체하지 않음).
  - `@Transform` 사용을 위해 `main.ts` ValidationPipe의 `transform: true` 활성화 여부를 backend가 선확인. 없으면 활성화하거나, DTO에서 `@Transform` 대신 서비스 레이어에서 `''→null` 정규화.
- **권한 체크**: 기존 그대로. signup은 비인증, me 계열은 `JwtAuthGuard`, PATCH는 `CsrfGuard`.
- **민감정보**: email은 PII로 간주 → 로그·에러 메시지에 **원본 email 값을 포함하지 않는다**. class-validator 메시지는 위처럼 값-less 문자열로 고정.
- **에러 응답**:
  - 400: email 포맷 오류 / 길이 초과 / PATCH 수정 항목 없음
  - 401: me 계열 인증 실패 (기존)
  - 403: PATCH /me CSRF 실패 (기존)
  - 409: email에는 적용 **안 됨** (중복 허용). user_id/nickname 중복은 기존 그대로.
- **CSRF**: PATCH /me는 기존 CsrfGuard 흐름 그대로. signup은 CSRF 미적용 (기존 정책 유지).
- **PRD 변경 사유**: PRD §3.1 members 테이블에 `email` 컬럼 신설. 커밋 메시지에 `PRD §3.1 members.email 추가` 사유 명시.

### 마이그레이션 (DB)

- 이름: `<timestamp>-add-member-email.ts` (예: `1729814400000-add-member-email.ts`)
  - timestamp는 기존 `1729468800000-create-members.ts` 이후 값이면 됨. backend가 `Date.now()` 또는 TypeORM CLI로 생성.
- **Up**:
  ```sql
  ALTER TABLE `members`
    ADD COLUMN `email` VARCHAR(254) NULL DEFAULT NULL AFTER `nickname`;
  ```
- **Down**:
  ```sql
  ALTER TABLE `members` DROP COLUMN `email`;
  ```
- **적용 방식**: 기존 워크플로와 동일 — `docker compose run --rm api pnpm migration:run`.
- **왕복 검증**: migration:run → migration:revert → migration:run 가 모두 성공해야 함 (QA가 확인).
- `synchronize: false` 유지 (PRD §7.4).

### 테스트 포인트 (QA 참조)

**백엔드 (단위/통합)**
- `auth.service.spec.ts`:
  - signup, email 생략 → 저장 레코드 `email === null`
  - signup, 유효 email → 저장 성공, 응답 바디에 email **없음** (PublicMember 그대로)
  - signup, 포맷 오류 → ValidationPipe가 400 (controller 레벨 e2e에서 확인)
  - 같은 email 로 두 유저 가입 성공 (중복 허용)
- `members.service.spec.ts`:
  - getMe → `email` 필드 포함 (저장값 없으면 null)
  - updateMe, email 신규 설정 / 변경 / `null` 로 삭제 / `""` → null 정규화 삭제
  - updateMe, email만 전송(다른 필드 없음) → 성공 (400 아님)
  - updateMe, 전체 필드 undefined → 400 (`수정할 항목이 없습니다.`)

**UAT (docker compose)**
1. `/signup`에서 이메일 **비우고** 가입 → 성공 → `/login?signup=1` 리다이렉트.
2. `/signup`에서 유효 이메일 입력 후 가입 → 성공.
3. `/signup`에서 `"not-an-email"` 입력 → 서버 400 메시지 노출.
4. 로그인 → `/me` → 저장된 email 표시 (없으면 공란/대시).
5. `/me`에서 email 변경 → 저장 → 재조회 시 반영.
6. `/me`에서 email 입력란 비우고 저장 → DB `NULL` 로 저장되고 재조회 시 공란.
7. 같은 email로 다른 user_id/nickname 두 번 가입 → 둘 다 성공.
8. 기존 플로우(로그인/글쓰기/로그아웃) 회귀 없음.

---

### Backend 핸드오프 요약
- 엔티티 1개 수정 (`member.entity.ts`) + 마이그레이션 1개 신규.
- DTO 2개 수정 (`signup.dto.ts`, `update-me.dto.ts`). `@Transform` 사용 전 `main.ts`의 `ValidationPipe({ transform: true })` 여부 확인.
- 서비스 2개 수정 (`auth.service.ts` signup 분기, `members.service.ts` updateMe + toView).
- `MeView` 인터페이스에 `email` 추가.
- `PublicMember` 응답은 변경하지 않는다 (의도).

### Frontend 핸드오프 요약 (frontend 역할 미할당 — backend/구현자가 함께 처리)
- `apps/web/lib/types.ts`: `SignupInput.email?`, `MemberProfile.email`, `UpdateMeInput.email?` 추가.
- `apps/web/app/signup/page.tsx`: `email` state + `<input type="email" maxLength={254}>` 필드 (선택, 라벨 "이메일 (선택)"). 비어 있으면 요청에 **키 자체를 포함하지 않음** (`undefined`).
- `apps/web/app/me/page.tsx`:
  - 프로필 표시 영역에 `이메일` 행 추가 (`load.member.email ?? '—'`).
  - 수정 폼에 email input 추가, 초기값은 `member.email ?? ''`.
  - 저장 로직: 입력값이 `load.member.email ?? ''`와 다를 때만 payload에 포함. 공란이면 `payload.email = null` 로 명시 전송(삭제 의도).

---

## Design (UX)
<designer 작성 — required면>

### Figma
- URL: <figma-url>

### 화면 목록
- `<Route>` — states: default | loading | error | empty

### 컴포넌트 트리
```
<PageName>
  └─ <HeaderBar>
  └─ <FormCard>
```

### Frontend 참고
- 디자인 토큰 import 경로
- 상태 분기 TODO 위치

---

## Implementation (Backend)

### 설계 메모
- 엔드포인트: `POST /auth/signup` (요청에 `email?` 수용, 응답은 변화 없음), `GET /members/me` (응답에 `email` 포함), `PATCH /members/me` (요청에 `email?: string | null`, 응답에 `email` 포함).
- 엔티티 변경: `MemberEntity.email: string | null` 매핑 추가 (`VARCHAR(254) NULL`, UNIQUE 없음).
- 마이그레이션: `AddMemberEmail1729814400000` — `ALTER TABLE members ADD COLUMN email VARCHAR(254) NULL AFTER nickname` / down 은 `DROP COLUMN`.
- `main.ts` 의 ValidationPipe 가 이미 `transform: true` 이므로 `UpdateMeDto.email` 에 `@Transform(({value}) => value === '' ? null : value)` 를 그대로 적용.

### 변경 파일
- `apps/api/src/members/member.entity.ts` — `email` 컬럼 매핑 추가 (`VARCHAR(254) NULL`).
- `apps/api/src/migrations/1729814400000-add-member-email.ts` *(신규)* — email 컬럼 up/down.
- `apps/api/src/auth/dto/signup.dto.ts` — `@IsOptional @IsString @MaxLength(254) @IsEmail` 로 선택 `email` 필드 추가.
- `apps/api/src/auth/auth.service.ts` — signup 저장 시 `email: dto.email ?? null` 전달 (응답 `PublicMember` 는 변경 없음, email 미노출).
- `apps/api/src/members/dto/update-me.dto.ts` — 선택 `email?: string | null` 필드. `""→null` Transform, null 허용(이메일 삭제 의도), 유효 포맷 시 설정.
- `apps/api/src/members/members.service.ts`
  - `MeView.email: string | null` 추가.
  - `updateMe`: `hasEmail` 플래그 포함 — 세 필드 모두 undefined 면 400. email 변경은 중복체크 없이 patch 반영 (null 포함).
  - `toView` 가 `email` 포함.
- `apps/api/src/auth/auth.service.spec.ts` — signup email 생략/제공 시 저장 레코드 email 값과 응답 바디(email 미노출) 검증 테스트 2개 추가.
- `apps/api/src/members/members.service.spec.ts` — getMe email 노출, updateMe 로 email 설정/`null` 삭제/email-only patch 통과 테스트 추가.

### 새 환경변수
- 없음.

### 마이그레이션
- 파일명: `apps/api/src/migrations/1729814400000-add-member-email.ts` (클래스 `AddMemberEmail1729814400000`)
- Up: `ALTER TABLE members ADD COLUMN email VARCHAR(254) NULL DEFAULT NULL AFTER nickname;`
- Down: `ALTER TABLE members DROP COLUMN email;`

### 로컬 재현
```bash
# 1) 의존성/타입체크/단위 테스트 (현재 결과: 32/32 pass, tsc clean)
pnpm install
pnpm --filter api typecheck
pnpm --filter api test

# 2) DB & 마이그레이션 (QA/통합 검증용 — 현재 worktree 포트)
docker compose up -d db
pnpm --filter api migration:run

# 3) 왕복 검증
pnpm --filter api migration:revert
pnpm --filter api migration:run

# 4) API 수동 호출 (서버 기동 후)
#    - email 없이 가입
curl -X POST http://localhost:4090/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{"userId":"alice01","password":"password12","nickname":"alice"}'
#    - email 포함 가입
curl -X POST http://localhost:4090/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{"userId":"bob001","password":"password12","nickname":"bob","email":"bob@example.com"}'
#    - 포맷 오류 → 400
curl -X POST http://localhost:4090/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{"userId":"carol1","password":"password12","nickname":"carol","email":"not-an-email"}'
#    - 중복 email 허용 (서로 다른 user_id/nickname 로 같은 email)
#    - /members/me, PATCH /members/me 는 JWT·CSRF 쿠키 필요 — QA UAT 로 확인
```

### 수용 기준 자가 검증 (백엔드 범위)
- [x] DB `members.email VARCHAR(254) NULL` 컬럼 추가, UNIQUE 없음 (마이그레이션 up/down 작성 — 왕복은 QA 환경에서 실행).
- [x] `POST /auth/signup`: email 생략 시 저장 레코드 `email === null`, 응답에 email 미노출 (단위 테스트 확인).
- [x] `POST /auth/signup`: 유효 email 포함 시 저장 성공, 응답 바디는 기존 `PublicMember` 그대로 (단위 테스트 확인).
- [x] `POST /auth/signup`: 포맷 오류/254자 초과 → `ValidationPipe` 가 400 (`@IsEmail` + `@MaxLength(254)`). DTO 레벨 검증, e2e/수동 확인은 QA.
- [x] email 중복 허용: 엔티티·DB·DTO 모두 UNIQUE 없음.
- [x] `GET /members/me`: `MeView`에 `email` 필드 포함, 저장값 없으면 null (단위 테스트 확인).
- [x] `PATCH /members/me`: email 신규 설정 / 변경 / `""` → null 정규화 / `null` 삭제 지원 (단위 테스트 확인). email-only patch 는 400 아님.
- [ ] *(frontend 범위)* `/signup`, `/me` 화면 변경 — **백엔드 역할 경계 외**, 아래 Handoff 참조.
- [ ] *(QA 범위)* 회귀(가입/로그인/글쓰기) UAT.

### Frontend 핸드오프 (중요)
- 본 task 의 `required_roles` 에는 frontend 가 포함되어 있지 않습니다. Plan 섹션은 "frontend 역할 미할당 — backend/구현자가 함께 처리" 로 명시했지만, **`.harness/roles/backend.md` 는 `apps/web/**` 수정을 금지**하므로 백엔드 역할 세션에서는 손대지 않았습니다.
- 미처리 변경 항목 (Design 섹션 참조):
  - `apps/web/lib/types.ts` — `SignupInput.email?`, `MemberProfile.email`, `UpdateMeInput.email?`
  - `apps/web/app/signup/page.tsx` — "이메일 (선택)" input, 공란 시 요청 key 생략
  - `apps/web/app/me/page.tsx` — 프로필 표시 + 수정 폼 email 필드, 공란 저장 시 `email: null`
- coordinator 가 결정 필요: (a) task 에 frontend 역할 추가 후 재분배, (b) 범위를 백엔드 변경만으로 축소하고 frontend 는 별도 task 로 분리.

### API 응답 형태 (frontend/QA 참조)
```jsonc
// GET /members/me (200)
{
  "id": "1",
  "userId": "alice01",
  "nickname": "alice",
  "email": "alice@example.com",   // 또는 null
  "createdAt": "2026-10-22T...",
  "updatedAt": "2026-10-22T..."
}

// PATCH /members/me (200) — 요청: { "email": "a@b.com" } | { "email": null } | { "email": "" }
// → 응답은 위 MeView 와 동일 형태로 반영.

// POST /auth/signup (201) — 요청에 email 포함 가능, 응답은 변화 없음
{ "id": "1", "userId": "alice01", "nickname": "alice" }
```

---

## Implementation (Frontend)
<frontend 작성>

### 추가 라우트/페이지
- `/path` — 설명

### 새 환경변수
- `NEXT_PUBLIC_...`

### 로컬 재현 (브라우저 시나리오)
1. ...

### 수용 기준 자가 검증
- [x] ...

---

## QA report
<qa 작성>

### 결과
- 결정: pass | fail
- 일자: 2026-10-22
- 환경: WEB=:<port>/API=:<port>/DB=:<port>

### 수용 기준 검증
- [x] <기준> — pass
- [ ] <기준> — fail → 아래 참조

### 발견 사항
- 없음 또는
- **[FAIL]** <요약>
  - 재현:
    1. ...
  - 기대: ...
  - 실제: ...

---

## Review notes
<reviewer 작성>

### 결과
- 결정: pass | rework
- 일자: 2026-10-22
- 병합 SHA: <sha> (pass 시)

### Blocker
- 없음 또는
- `file.ts:42` — <문제>, <수정 가이드>

### Suggest
- `file.ts:88` — <개선 아이디어>

### 체크리스트 요약
- PRD 정합성: ✅
- 보안: ✅
- 리소스/누수: ✅
- 성능/데이터: ✅
- 코드 품질: ✅
- 테스트: ✅
- 범위: ✅
