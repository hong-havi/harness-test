#!/usr/bin/env bash
# T002 backend 수용 기준 로컬 재현 스크립트
set -u
API=http://localhost:4020
CJ=/tmp/t002.cjar
rm -f "$CJ"
fail=0
pass=0
pass() { pass=$((pass+1)); echo "  OK  $1"; }
fail() { fail=$((fail+1)); echo "  FAIL $1"; }

code() { curl -s -o /tmp/t002.out -w "%{http_code}" -c "$CJ" -b "$CJ" "$@"; }
body() { cat /tmp/t002.out; }

echo "─ signup 400 (user_id 형식)"
c=$(code -X POST "$API/auth/signup" -H "Content-Type: application/json" -d '{"userId":"ab","password":"password12","nickname":"alice"}')
[ "$c" = "400" ] && pass "signup 400 on short user_id" || fail "expected 400 got $c $(body)"

echo "─ signup 400 (password 영문/숫자 미조합)"
c=$(code -X POST "$API/auth/signup" -H "Content-Type: application/json" -d '{"userId":"alice01","password":"onlylower","nickname":"alice"}')
[ "$c" = "400" ] && pass "signup 400 on password missing digit" || fail "expected 400 got $c $(body)"

echo "─ signup 400 (nickname 길이)"
c=$(code -X POST "$API/auth/signup" -H "Content-Type: application/json" -d '{"userId":"alice01","password":"password12","nickname":"a"}')
[ "$c" = "400" ] && pass "signup 400 on nickname too short" || fail "expected 400 got $c $(body)"

echo "─ signup 201 (정상)"
c=$(code -X POST "$API/auth/signup" -H "Content-Type: application/json" -H "X-Forwarded-For: 10.1.2.3" -d '{"userId":"alice01","password":"password12","nickname":"alice"}')
[ "$c" = "201" ] && pass "signup 201" || fail "expected 201 got $c $(body)"
echo "  body: $(body)"

echo "─ signup 409 (user_id 중복)"
c=$(code -X POST "$API/auth/signup" -H "Content-Type: application/json" -d '{"userId":"alice01","password":"password12","nickname":"other"}')
[ "$c" = "409" ] && pass "signup 409 user_id dup" || fail "expected 409 got $c $(body)"

echo "─ signup 409 (nickname 중복)"
c=$(code -X POST "$API/auth/signup" -H "Content-Type: application/json" -d '{"userId":"other01","password":"password12","nickname":"alice"}')
[ "$c" = "409" ] && pass "signup 409 nickname dup" || fail "expected 409 got $c $(body)"

echo "─ login 401 (없는 user_id)"
c=$(code -X POST "$API/auth/login" -H "Content-Type: application/json" -d '{"userId":"nobody","password":"password12"}')
msg_a=$(body)
[ "$c" = "401" ] && pass "login 401 unknown user" || fail "expected 401 got $c"

echo "─ login 401 (비번 불일치)"
c=$(code -X POST "$API/auth/login" -H "Content-Type: application/json" -d '{"userId":"alice01","password":"wrong-pass9"}')
msg_b=$(body)
[ "$c" = "401" ] && pass "login 401 wrong password" || fail "expected 401 got $c"

echo "─ login 401 메시지 통일"
[ "$msg_a" = "$msg_b" ] && pass "generic error message identical" || fail "messages differ: '$msg_a' vs '$msg_b'"

echo "─ login 200 + 쿠키"
rm -f "$CJ"
c=$(code -i -X POST "$API/auth/login" -H "Content-Type: application/json" -d '{"userId":"alice01","password":"password12"}')
[ "$c" = "200" ] && pass "login 200" || fail "expected 200 got $c $(body)"
# body 는 header+body 혼재 (because -i). 쿠키 jar 로 확인
grep -q access_token "$CJ" && grep -q csrf_token "$CJ" && pass "both cookies set" || fail "cookies missing"
# HttpOnly flag — cookie jar 는 '#HttpOnly_' 접두사
grep -E "^#HttpOnly_" "$CJ" | grep -q access_token && pass "access_token is HttpOnly" || fail "access_token not HttpOnly"
grep -E "^#HttpOnly_" "$CJ" | grep -q csrf_token && fail "csrf_token should NOT be HttpOnly" || pass "csrf_token is NOT HttpOnly"
# body: 토큰 미포함
rm -f "$CJ"
curl -s -c "$CJ" -X POST "$API/auth/login" -H "Content-Type: application/json" -d '{"userId":"alice01","password":"password12"}' -o /tmp/t002.body >/dev/null
if grep -q "access_token" /tmp/t002.body || grep -q "jwt" /tmp/t002.body; then
  fail "token exposed in body: $(cat /tmp/t002.body)"
else
  pass "token not in body: $(cat /tmp/t002.body)"
fi

echo "─ /members/me 200"
c=$(code -X GET "$API/members/me")
[ "$c" = "200" ] && pass "me 200" || fail "expected 200 got $c $(body)"
# password_hash, created_ip 비노출
grep -q password_hash /tmp/t002.out && fail "password_hash exposed" || pass "no password_hash in me"
grep -q created_ip /tmp/t002.out && fail "created_ip exposed" || pass "no created_ip in me"

echo "─ /members/me 401 (쿠키 없음)"
c=$(curl -s -o /tmp/t002.out -w "%{http_code}" -X GET "$API/members/me")
[ "$c" = "401" ] && pass "me 401 no cookie" || fail "expected 401 got $c"

echo "─ /members/me 401 (조작된 토큰)"
c=$(curl -s -o /tmp/t002.out -w "%{http_code}" -X GET "$API/members/me" -H "Cookie: access_token=invalid.token.here")
[ "$c" = "401" ] && pass "me 401 bad token" || fail "expected 401 got $c"

echo "─ PATCH /members/me 403 (CSRF 누락)"
c=$(code -X PATCH "$API/members/me" -H "Content-Type: application/json" -d '{"nickname":"alice2"}')
[ "$c" = "403" ] && pass "patch me 403 no csrf" || fail "expected 403 got $c $(body)"

csrf=$(awk '$6=="csrf_token"{print $7}' "$CJ")
echo "─ PATCH /members/me 403 (CSRF 헤더 불일치)"
c=$(code -X PATCH "$API/members/me" -H "Content-Type: application/json" -H "X-CSRF-Token: wrong-value" -d '{"nickname":"alice2"}')
[ "$c" = "403" ] && pass "patch me 403 csrf mismatch" || fail "expected 403 got $c $(body)"

echo "─ PATCH /members/me 200 (nickname 변경)"
c=$(code -X PATCH "$API/members/me" -H "Content-Type: application/json" -H "X-CSRF-Token: $csrf" -d '{"nickname":"alice2"}')
[ "$c" = "200" ] && pass "patch me 200 nickname" || fail "expected 200 got $c $(body)"

echo "─ PATCH /members/me 400 (빈 바디)"
c=$(code -X PATCH "$API/members/me" -H "Content-Type: application/json" -H "X-CSRF-Token: $csrf" -d '{}')
[ "$c" = "400" ] && pass "patch me 400 empty" || fail "expected 400 got $c $(body)"

echo "─ PATCH /members/me 400 (currentPassword 불일치)"
c=$(code -X PATCH "$API/members/me" -H "Content-Type: application/json" -H "X-CSRF-Token: $csrf" -d '{"newPassword":"brand-new-9","currentPassword":"wrong-password-9"}')
[ "$c" = "400" ] && pass "patch me 400 wrong currentPassword" || fail "expected 400 got $c $(body)"

echo "─ PATCH /members/me 400 (user_id 포함 — forbidNonWhitelisted)"
c=$(code -X PATCH "$API/members/me" -H "Content-Type: application/json" -H "X-CSRF-Token: $csrf" -d '{"userId":"hack01"}')
[ "$c" = "400" ] && pass "patch me 400 forbidNonWhitelisted" || fail "expected 400 got $c $(body)"

echo "─ 다른 유저 생성 후 nickname 중복 409"
rm -f /tmp/t002.cjar2
curl -s -c /tmp/t002.cjar2 -X POST "$API/auth/signup" -H "Content-Type: application/json" -d '{"userId":"bob01","password":"password12","nickname":"bob"}' >/dev/null
curl -s -c /tmp/t002.cjar2 -b /tmp/t002.cjar2 -X POST "$API/auth/login" -H "Content-Type: application/json" -d '{"userId":"bob01","password":"password12"}' >/dev/null
csrf2=$(awk '$6=="csrf_token"{print $7}' /tmp/t002.cjar2)
c=$(curl -s -o /tmp/t002.out -w "%{http_code}" -b /tmp/t002.cjar2 -c /tmp/t002.cjar2 -X PATCH "$API/members/me" -H "Content-Type: application/json" -H "X-CSRF-Token: $csrf2" -d '{"nickname":"alice2"}')
[ "$c" = "409" ] && pass "patch me 409 nickname dup" || fail "expected 409 got $c $(body)"

echo "─ PATCH /members/me 200 (password 변경)"
c=$(code -X PATCH "$API/members/me" -H "Content-Type: application/json" -H "X-CSRF-Token: $csrf" -d '{"newPassword":"brand-new-9","currentPassword":"password12"}')
[ "$c" = "200" ] && pass "patch me 200 password change" || fail "expected 200 got $c $(body)"

echo "─ 새 비번으로 로그인 가능"
rm -f /tmp/t002.cjar3
c=$(curl -s -o /tmp/t002.out -w "%{http_code}" -c /tmp/t002.cjar3 -X POST "$API/auth/login" -H "Content-Type: application/json" -d '{"userId":"alice01","password":"brand-new-9"}')
[ "$c" = "200" ] && pass "login with new password" || fail "expected 200 got $c $(body)"

echo "─ 로그아웃 — access_token Max-Age=0"
csrfA=$(awk '$6=="csrf_token"{print $7}' /tmp/t002.cjar3)
headers=$(curl -s -i -b /tmp/t002.cjar3 -c /tmp/t002.cjar3 -X POST "$API/auth/logout")
echo "$headers" | grep -i "set-cookie:" | head -4
echo "$headers" | grep -iE "set-cookie: *access_token=.*max-age=0" >/dev/null && pass "logout clears access_token" || fail "logout cookie not cleared"

echo "─ 로그아웃 후 /members/me 401"
c=$(curl -s -o /tmp/t002.out -w "%{http_code}" -b /tmp/t002.cjar3 -X GET "$API/members/me")
[ "$c" = "401" ] && pass "me 401 after logout" || fail "expected 401 got $c"

echo "─ 가입 IP: X-Forwarded-For 반영 확인 (DB)"
ip=$(docker compose -f docker-compose.yml exec -T db mysql -uroot -proot_pw -N -B -D board -e "SELECT created_ip FROM members WHERE user_id='alice01'" 2>/dev/null)
echo "  created_ip=$ip"
[ "$ip" = "10.1.2.3" ] && pass "X-Forwarded-For honored" || fail "expected 10.1.2.3 got '$ip'"

echo
echo "═══════════════════════════════"
echo "PASS: $pass    FAIL: $fail"
echo "═══════════════════════════════"
exit $fail
