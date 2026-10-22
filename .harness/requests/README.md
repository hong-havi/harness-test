# User Requests

User 가 작성하는 **상세한 요구사항 문서** 보관소. Slack 1-liner 로 끝낼 수 없는 복잡한 task 에 사용.

## 사용법

### 1. 요구사항 작성
```bash
cp .harness/templates/user-request.md .harness/requests/remember-me.md
# 편집기로 remember-me.md 작성
```

### 2. task 생성 (3가지 방법 중 택1)

**A. 자동 매칭** — slug 와 같은 이름의 파일이 있으면 자동 로드
```bash
./scripts/tasks.sh new remember-me
# → .harness/requests/remember-me.md 자동 사용
```

**B. 명시적 파일 지정**
```bash
./scripts/tasks.sh new remember-me --from .harness/requests/any-file.md
```

**C. Slack**
```
@harness-bot new remember-me
```
(자동 매칭 — 파일 있으면 사용, 없으면 slug 만 전달)

### 3. 인라인 (여전히 지원)
파일 없이 자연어로:
```bash
./scripts/tasks.sh new remember-me "로그인 체크박스 추가..."
```

## 우선순위
`--from <path>` > 인라인 자연어 > `.harness/requests/<slug>.md` 자동 매칭 > (아무것도 없으면 slug 만)

## 템플릿
`.harness/templates/user-request.md` 참조.

## 폴더 정책
- `.harness/requests/` 는 git tracked (리뷰·히스토리용)
- task merge/drop 시 archive 로 이동하지 않음 — 참조 자료로 영구 보관
- 파일명 = slug 와 일치 권장 (자동 매칭용)
