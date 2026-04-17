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
