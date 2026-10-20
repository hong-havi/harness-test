# PRD: 간단한 게시판 시스템

## 1. 개요

- **목적**: 회원 가입/로그인 후 글을 작성할 수 있는 최소 기능 게시판
- **범위**: 회원 모듈, 게시판 모듈 2개
- **대상 사용자**: 비로그인 방문자(읽기), 로그인 회원(쓰기)

### 1.1 기술 스택

| 구분 | 선택 |
|------|------|
| Frontend | Next.js (App Router 가정) |
| Backend | NestJS |
| DB | MySQL 8.x |
| ORM | TypeORM |
| 인증 | JWT (Access Token, HttpOnly 쿠키 전달) |
| 비밀번호 해시 | bcrypt |
| 리포 구조 | 모노레포 (pnpm workspaces) |
| 로컬 실행 | Docker Compose (서비스별 컨테이너) |

### 1.2 아키텍처 개요

```
┌──────────── Docker network ────────────┐
│                                        │
│  [web]        [api]          [db]      │
│  Next.js  →   NestJS    →    MySQL     │
│  :3000        :4000          :3306     │
│                                        │
└────────────────────────────────────────┘
         ▲
         │  HTTP (브라우저)
       사용자
```

- 브라우저는 `/api/*` 요청을 **Next.js의 rewrites**를 통해 NestJS로 프록시 → 같은 origin에서 쿠키 전달
  - 대안: 브라우저가 NestJS를 직접 호출 (이 경우 CORS + `credentials: 'include'` + Set-Cookie `Domain` 정책 필요)
  - 기본은 **rewrites 방식** 채택 (쿠키/CORS 단순화)
- 서버 간 통신(SSR fetch 등)은 Docker 내부 DNS(`http://api:4000`) 사용
- 인증 보호 라우트는 서버에서 Guard로 재검증 (프런트 가드만으로는 불충분)

### 1.3 모노레포 구조

```
harness-test/
├── apps/
│   ├── web/           # Next.js
│   │   ├── Dockerfile
│   │   └── ...
│   └── api/           # NestJS
│       ├── Dockerfile
│       └── ...
├── packages/
│   └── shared/        # 공유 타입/DTO (선택, 과잉이면 생략)
├── docker-compose.yml
├── .env.example
├── pnpm-workspace.yaml
├── package.json
└── PRD.md
```

- **패키지 매니저**: pnpm (workspace 지원이 가벼움)
- `packages/shared`는 필요 시 추가. 초기엔 생략해도 무방.

## 2. 용어

| 용어 | 정의 |
|------|------|
| 회원 | 가입 절차를 완료한 사용자 |
| 방문자 | 비로그인 상태의 사용자 |
| 게시글 | 회원이 작성한 글 (제목 + 본문) |

## 3. 모듈 1 — 회원

### 3.1 데이터 모델

| 필드 | 타입 | 제약 | 비고 |
|------|------|------|------|
| id (PK) | BIGINT UNSIGNED | auto-increment | 내부 식별자 |
| user_id | VARCHAR(32) | UNIQUE, NOT NULL | 로그인 아이디 |
| password_hash | VARCHAR(255) | NOT NULL | bcrypt 해시 저장, 평문 금지 |
| nickname | VARCHAR(32) | UNIQUE, NOT NULL | 화면 표시명 |
| created_at | DATETIME | NOT NULL, DEFAULT CURRENT_TIMESTAMP | 가입일시 |
| created_ip | VARCHAR(45) | NOT NULL | 가입 IP (IPv6 대응 길이) |
| updated_at | DATETIME | NOT NULL, ON UPDATE CURRENT_TIMESTAMP | 최종 수정일시 |

- 문자셋: `utf8mb4` / collation: `utf8mb4_unicode_ci`
- 인덱스: `UNIQUE(user_id)`, `UNIQUE(nickname)`

### 3.2 기능

#### F-M1. 회원가입
- **입력**: user_id, password, nickname
- **검증**:
  - user_id: 4~32자, 영문/숫자, 중복 불가
  - password: 8자 이상, 영문+숫자 조합 (최소 요건)
  - nickname: 2~32자, 중복 불가
- **처리**:
  - password → 해시 변환 후 저장
  - 요청 IP를 created_ip에 기록
  - created_at = 현재 시각
- **응답**: 성공 시 로그인 화면으로 유도 (자동 로그인은 하지 않음)
- **에러**: 중복 아이디/닉네임, 유효성 실패

#### F-M2. 로그인
- **입력**: user_id, password
- **처리**:
  - user_id 조회 → bcrypt.compare로 password_hash 비교
  - 성공 시 JWT Access Token 발급
- **JWT payload**: `{ sub: member.id, user_id, nickname, iat, exp }`
- **응답**:
  - 바디: `{ id, user_id, nickname }` (토큰은 바디에 노출하지 않음)
  - 헤더: `Set-Cookie: access_token=<jwt>; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=3600`
- **에러**: 아이디/비번 불일치 시 동일한 메시지 반환 (계정 존재 여부 노출 금지)
- **보안**: 로그인 실패 횟수 제한은 **범위 밖** (추후 과제)

#### F-M3. 로그아웃
- **처리**: 서버가 `Set-Cookie: access_token=; Max-Age=0`로 쿠키 만료
- **참고**: JWT 자체는 stateless. 서버측 블랙리스트는 범위 밖 (만료까지 유효할 수 있음을 인지).

#### F-M4. 정보 수정
- **전제**: 로그인 상태
- **수정 가능 필드**: nickname, password
- **수정 불가 필드**: user_id, created_at, created_ip
- **검증**:
  - password 변경 시 현재 비밀번호 재확인 필수
  - nickname 변경 시 중복 체크
- **처리**: updated_at 갱신

### 3.3 JWT 정책

| 항목 | 값 |
|------|-----|
| 알고리즘 | HS256 |
| Access Token 만료 | 1시간 |
| Refresh Token | **범위 밖** (만료 시 재로그인) |
| 저장 위치 | **HttpOnly 쿠키** (`access_token`) — JS 접근 불가 |
| 쿠키 속성 | `HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=3600` (로컬 개발은 `Secure` 제외 가능) |
| 전송 방식 | 브라우저 자동 쿠키 전송 (fetch는 `credentials: 'include'` 또는 same-origin 프록시) |
| 서버 추출 | NestJS `cookie-parser` + `JwtStrategy`(cookieExtractor) |
| Secret 관리 | 환경변수 `JWT_SECRET`, 리포 커밋 금지 |

### 3.4 CSRF 대응

HttpOnly 쿠키 선택에 따라 CSRF 위험이 존재하므로 다음을 적용한다.

1. 쿠키 `SameSite=Lax`로 cross-site POST 자동 전송 차단 (1차 방어)
2. 상태 변경(POST/PUT/PATCH/DELETE) 요청에 **CSRF 토큰** 적용
   - 방식: Double Submit Cookie
     - 서버는 로그인 시 `csrf_token` 쿠키(HttpOnly 아님)도 함께 발급
     - 클라이언트는 `X-CSRF-Token` 헤더에 동일 값 복사 전송
     - 서버는 쿠키 값 ↔ 헤더 값 일치 여부 검증
3. CORS: `credentials: true` + 명시적 origin allowlist (와일드카드 금지)

> 참고: Next.js rewrites로 same-origin 운용 시 CSRF 리스크는 낮으나, 명시적 방어층을 유지한다.

### 3.5 비기능 요구사항 (회원)
- 비밀번호는 서버 로그/응답 어디에도 평문 노출 금지
- bcrypt saltRounds >= 10
- NestJS `AuthGuard('jwt')` + 쿠키 기반 `JwtStrategy`로 보호 라우트 처리

---

## 4. 모듈 2 — 게시판

### 4.1 데이터 모델

#### posts
| 필드 | 타입 | 제약 | 비고 |
|------|------|------|------|
| id (PK) | BIGINT UNSIGNED | auto-increment | |
| author_id (FK) | BIGINT UNSIGNED | NOT NULL, → members.id ON DELETE RESTRICT | 작성자 |
| title | VARCHAR(200) | NOT NULL | |
| content | TEXT | NOT NULL | |
| view_count | INT UNSIGNED | DEFAULT 0 | |
| created_at | DATETIME | NOT NULL, DEFAULT CURRENT_TIMESTAMP | |
| updated_at | DATETIME | NOT NULL, ON UPDATE CURRENT_TIMESTAMP | |
| deleted_at | DATETIME | NULL | soft delete |

- 인덱스: `INDEX(author_id)`, `INDEX(created_at)`, `INDEX(deleted_at)`
- 문자셋: `utf8mb4` / collation: `utf8mb4_unicode_ci`

### 4.2 권한 매트릭스

| 기능 | 방문자 | 로그인 회원 | 작성자 본인 |
|------|:------:|:-----------:|:-----------:|
| 목록 조회 | ✅ | ✅ | ✅ |
| 상세 조회 | ✅ | ✅ | ✅ |
| 작성 | ❌ | ✅ | - |
| 수정 | ❌ | ❌ | ✅ |
| 삭제 | ❌ | ❌ | ✅ |

### 4.3 기능

#### F-B1. 게시글 목록
- **접근**: 누구나
- **표시 항목**: 번호, 제목, 작성자 nickname, 작성일, 조회수
- **정렬**: 최신순 (created_at DESC)
- **페이징**: 페이지당 20건 (기본값)

#### F-B2. 게시글 상세
- **접근**: 누구나
- **표시 항목**: 제목, 작성자 nickname, 작성일, 본문, 조회수
- **처리**: 조회 시 view_count +1 (중복 방지는 범위 밖)
- **버튼 노출**:
  - 작성자 본인: 수정/삭제 버튼 노출
  - 그 외: 노출 안 함

#### F-B3. 게시글 작성
- **접근**: 로그인 회원만
- **입력**: title, content
- **검증**:
  - title: 1~200자
  - content: 1자 이상
- **처리**: author_id = 현재 로그인 회원 id

#### F-B4. 게시글 수정
- **접근**: 작성자 본인만
- **입력**: title, content
- **검증**:
  - 서버에서 author_id === 현재 세션 member.id 재확인 (프런트 숨김만으로 불충분)
- **처리**: updated_at 갱신

#### F-B5. 게시글 삭제
- **접근**: 작성자 본인만
- **처리**: soft delete (deleted_at 세팅)
- **목록/상세**: deleted_at IS NOT NULL인 글은 노출 제외

---

## 5. API 엔드포인트 (NestJS)

### 5.1 Auth / Member

| Method | Path | Auth | 설명 |
|--------|------|:----:|------|
| POST | `/auth/signup` | - | 회원가입 |
| POST | `/auth/login` | - | 로그인, `Set-Cookie: access_token`, `csrf_token` |
| POST | `/auth/logout` | JWT | 쿠키 만료 처리 |
| GET | `/members/me` | JWT | 내 정보 조회 |
| PATCH | `/members/me` | JWT + CSRF | 닉네임/비밀번호 수정 |

### 5.2 Posts

| Method | Path | Auth | 설명 |
|--------|------|:----:|------|
| GET | `/posts` | - | 목록 (page, size 쿼리) |
| GET | `/posts/:id` | - | 상세 (조회수 +1) |
| POST | `/posts` | JWT + CSRF | 작성 |
| PATCH | `/posts/:id` | JWT + CSRF + 작성자 | 수정 |
| DELETE | `/posts/:id` | JWT + CSRF + 작성자 | 삭제 (soft) |

### 5.3 공통 응답 규약

- 성공: 2xx + JSON 바디
- 에러 형식: `{ statusCode, message, error }` (NestJS 기본 HttpException 형태)
- 상태 코드:
  - 400: 유효성 실패 (`class-validator` 기반 DTO)
  - 401: 토큰 없음/만료/유효하지 않음
  - 403: 권한 없음 (타인의 글 수정/삭제 시도 등)
  - 404: 리소스 없음
  - 409: 중복 (user_id, nickname)

## 6. 공통 비기능 요구사항

- **입력 검증**: NestJS `ValidationPipe` + `class-validator`로 DTO 레벨에서 재검증
- **XSS 방지**: 게시글 본문은 Next.js에서 React 기본 escape 사용. `dangerouslySetInnerHTML` 금지
- **CSRF**: §3.4 참조 (Double Submit Cookie)
- **CORS**: NestJS에서 Next.js origin만 허용, `credentials: true`
- **에러 메시지**: 민감 정보(존재 여부, 스택트레이스) 노출 금지
- **환경 변수**: 하단 §7 참조

## 7. 로컬 실행 환경 (Docker)

### 7.1 Compose 서비스

| 서비스 | 이미지 (베이스) | 포트 (host:container) | 비고 |
|--------|----------------|-----------------------|------|
| `web` | `node:20-alpine` | `3000:3000` | Next.js, 개발 모드는 `pnpm dev`, 운영 모드는 `pnpm start` |
| `api` | `node:20-alpine` | `4000:4000` | NestJS, `cookie-parser` 포함 |
| `db` | `mysql:8` | `3306:3306` | 데이터 볼륨 영속화, 초기 DB `board` 생성 |

- `web`은 `api`에 의존 (`depends_on`), `api`는 `db` healthcheck 대기
- `db`에는 named volume (`mysql_data`) 마운트로 재기동 시 데이터 유지
- 핫리로드: 개발 시 소스 디렉토리 bind mount + `node_modules`는 익명 볼륨 유지

### 7.2 Dockerfile 전략

- **멀티스테이지**: `deps` → `build` → `runtime`
- 운영 이미지는 `pnpm install --prod --frozen-lockfile` 결과만 포함
- Non-root user (`node`)로 실행

### 7.3 환경 변수 (`.env`)

| 변수 | 예시 | 용도 |
|------|------|------|
| `NODE_ENV` | `development` / `production` | 공통 |
| `JWT_SECRET` | (랜덤 32바이트) | api |
| `JWT_EXPIRES_IN` | `3600` | api |
| `DB_HOST` | `db` | api (Docker 내부 호스트명) |
| `DB_PORT` | `3306` | api |
| `DB_USER` | `board` | api |
| `DB_PASSWORD` | (랜덤) | api, db |
| `DB_NAME` | `board` | api, db |
| `MYSQL_ROOT_PASSWORD` | (랜덤) | db |
| `CORS_ORIGIN` | `http://localhost:3000` | api |
| `COOKIE_SECURE` | `false`(dev) / `true`(prod) | api |
| `NEXT_PUBLIC_API_BASE` | `/api` (rewrites 경유) | web |

- `.env.example`을 리포에 커밋, 실제 `.env`는 `.gitignore`
- 운영 비밀값은 Docker secrets 또는 외부 비밀관리로 승격 가능 (현재는 범위 밖)

### 7.4 Nest ↔ TypeORM ↔ MySQL 세부

- 접속: `TypeOrmModule.forRoot({ type: 'mysql', host: DB_HOST, ... })`
- **마이그레이션 전략**: `synchronize: false`, 명시적 **마이그레이션 파일** 사용
  - 개발 편의로 `synchronize: true`를 쓰지 않는다 (스키마 drift 위험)
- 엔티티: `MemberEntity`, `PostEntity` — snake_case 컬럼명 매핑
- 소프트삭제: TypeORM `@DeleteDateColumn()` 활용 또는 수동 `deleted_at`

### 7.5 개발 워크플로

```bash
cp .env.example .env
docker compose up -d db          # DB 먼저 기동
docker compose run --rm api pnpm migration:run
docker compose up                # web + api 기동
```

## 8. 범위 밖 (Out of Scope)

- 댓글/대댓글
- 이메일 인증, 비밀번호 찾기
- 파일/이미지 업로드
- 게시판 다중화(카테고리)
- 신고/차단, 관리자 기능
- 소셜 로그인
- 로그인 실패 횟수 제한, 2FA
- Refresh Token / 토큰 블랙리스트
- SSR 인증 (쿠키 기반 서버 컴포넌트 인증)
- 프로덕션 배포 파이프라인(CI/CD)
- 외부 비밀관리(Vault, AWS Secrets Manager 등)

## 9. 수용 기준 (Acceptance Criteria)

- [ ] 비회원이 가입 → 로그인 → 글 작성 → 로그아웃까지 완주 가능
- [ ] 비로그인 상태로 글 목록/상세 열람 가능
- [ ] 비로그인 상태로 작성 API 호출 시 401 반환
- [ ] 다른 회원의 글 수정/삭제 시도 시 403 반환
- [ ] 비밀번호가 DB에 평문으로 저장되지 않음
- [ ] 가입 IP가 올바르게 기록됨 (프록시 환경일 경우 X-Forwarded-For 처리 정책 명시 필요)
- [ ] 만료된 JWT로 보호된 API 호출 시 401 반환
- [ ] 로그인 시 `access_token` 쿠키가 `HttpOnly`로 설정됨 (브라우저에서 `document.cookie`로 접근 불가 확인)
- [ ] 상태 변경 요청에 CSRF 토큰 누락 시 403 반환
- [ ] `docker compose up`만으로 web/api/db 전체가 기동되고 UAT 통과

## 10. 결정 필요 항목 (Open Questions)

1. 프록시 뒤에 있을 경우 가입 IP 추출 정책 (`X-Forwarded-For` 신뢰 여부, Nest `trust proxy` 설정)
2. 닉네임 변경 주기 제한 여부 (예: 30일 1회)
3. 게시글 수정 시 "수정됨" 표시 노출 여부
4. 브라우저 → API 호출 경로: Next.js rewrites(same-origin) vs 직접 호출(CORS+credentials)
   - 기본은 rewrites 채택, 전환 시 CORS/Cookie Domain 정책 재검토
5. TypeORM 마이그레이션 실행 주체: 컨테이너 start-up hook vs 별도 one-off 명령 (`compose run --rm api pnpm migration:run`)
6. `packages/shared` 공유 패키지 도입 여부 (초기엔 생략 권장)
