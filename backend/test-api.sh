#!/usr/bin/env bash
# Integration smoke test for the greppit backend.
# Requires: running server on port 8085, jq, curl.
set -u

BASE="http://localhost:8085"
EMAIL="test-$(date +%s)@example.com"
PW="hunter2"

say() { printf "\n=== %s ===\n" "$1"; }

say "Health"
curl -sS "$BASE/api/health" | jq .

say "Signup"
SIGNUP=$(curl -sS -X POST "$BASE/api/auth/signup" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}")
echo "$SIGNUP" | jq .
TOKEN=$(echo "$SIGNUP" | jq -r .token)

say "Login"
LOGIN=$(curl -sS -X POST "$BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}")
echo "$LOGIN" | jq .

say "Me"
curl -sS "$BASE/api/auth/me" \
  -H "Authorization: Bearer $TOKEN" | jq .

say "Login wrong password (expect 401)"
curl -sS -o /dev/null -w "status=%{http_code}\n" \
  -X POST "$BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"wrong\"}"

say "Create snippet A"
A=$(curl -sS -X POST "$BASE/api/snippets" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Elm howto","tags":"elm howto","markup":"markdown","body":"# Hello\n$e^{i\\pi}+1=0$"}')
echo "$A" | jq .
A_ID=$(echo "$A" | jq -r .id)

say "Create snippet B"
curl -sS -X POST "$BASE/api/snippets" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Postgres ilike tip","tags":"postgres","markup":"markdown","body":"Use ILIKE for case-insensitive."}' \
  | jq .

say "Create snippet C (scripta)"
curl -sS -X POST "$BASE/api/snippets" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Scripta demo","tags":"scripta","markup":"scripta","body":"[b bold]"}' \
  | jq .

say "List (no search) - expect 3 results, most recent first"
curl -sS "$BASE/api/snippets" \
  -H "Authorization: Bearer $TOKEN" | jq 'length'

say "Search 'elm' - expect 1"
curl -sS "$BASE/api/snippets?q=elm" \
  -H "Authorization: Bearer $TOKEN" | jq 'length'

say "Search 'elm howto' - expect 1 (conjunctive)"
curl -sS --get --data-urlencode "q=elm howto" \
  "$BASE/api/snippets" -H "Authorization: Bearer $TOKEN" | jq 'length'

say "Search 'elm postgres' - expect 0"
curl -sS --get --data-urlencode "q=elm postgres" \
  "$BASE/api/snippets" -H "Authorization: Bearer $TOKEN" | jq 'length'

say "Update A"
curl -sS -X PUT "$BASE/api/snippets/$A_ID" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Elm howto v2","tags":"elm howto","markup":"markdown","body":"updated"}' \
  | jq .

say "Get A (expect v2)"
curl -sS "$BASE/api/snippets/$A_ID" \
  -H "Authorization: Bearer $TOKEN" | jq .title

say "Delete A"
curl -sS -o /dev/null -w "status=%{http_code}\n" \
  -X DELETE "$BASE/api/snippets/$A_ID" \
  -H "Authorization: Bearer $TOKEN"

say "Get A (expect 404)"
curl -sS -o /dev/null -w "status=%{http_code}\n" \
  "$BASE/api/snippets/$A_ID" -H "Authorization: Bearer $TOKEN"

say "Unauthed list (expect 401)"
curl -sS -o /dev/null -w "status=%{http_code}\n" "$BASE/api/snippets"
