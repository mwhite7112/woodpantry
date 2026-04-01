#!/usr/bin/env bash
# Shared helpers for WoodPantry smoke tests.
# Source this file at the top of every smoke_*.sh script.

set -euo pipefail

# --- Service URLs (host-mapped ports) ---
export ING_URL="${ING_URL:-http://localhost:8081}"
export REC_URL="${REC_URL:-http://localhost:8082}"
export PAN_URL="${PAN_URL:-http://localhost:8083}"
export MAT_URL="${MAT_URL:-http://localhost:8084}"
export INGEST_URL="${INGEST_URL:-http://localhost:8085}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Counters ---
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# --- Logging ---
log_step()    { echo -e "${YELLOW}--- $1 ---${NC}"; }
log_success() { echo -e "${GREEN}PASS: $1${NC}"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_fail()    { echo -e "${RED}FAIL: $1${NC}"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
log_skip()    { echo -e "${YELLOW}SKIP: $1${NC}"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

# --- HTTP helpers ---
# Usage: api_get <url> [expected_status]
api_get() {
    local url="$1"
    local expected="${2:-200}"
    local status body
    body=$(curl -s -w '\n%{http_code}' "$url")
    status=$(echo "$body" | tail -n1)
    body=$(echo "$body" | sed '$d')
    if [[ "$status" != "$expected" ]]; then
        echo "$body"
        return 1
    fi
    echo "$body"
}

# Usage: api_post <url> <json_body> [expected_status]
api_post() {
    local url="$1"
    local data="$2"
    local expected="${3:-200}"
    local status body
    body=$(curl -s -w '\n%{http_code}' -X POST "$url" -H "Content-Type: application/json" -d "$data")
    status=$(echo "$body" | tail -n1)
    body=$(echo "$body" | sed '$d')
    if [[ "$status" != "$expected" ]]; then
        echo "$body"
        return 1
    fi
    echo "$body"
}

# Usage: api_delete <url> [expected_status]
api_delete() {
    local url="$1"
    local expected="${2:-200}"
    local status body
    body=$(curl -s -w '\n%{http_code}' -X DELETE "$url")
    status=$(echo "$body" | tail -n1)
    body=$(echo "$body" | sed '$d')
    if [[ "$status" != "$expected" ]]; then
        echo "$body"
        return 1
    fi
    echo "$body"
}

# --- Summary ---
smoke_summary() {
    echo ""
    echo -e "========================================="
    echo -e "  PASS: ${GREEN}${PASS_COUNT}${NC}  FAIL: ${RED}${FAIL_COUNT}${NC}  SKIP: ${YELLOW}${SKIP_COUNT}${NC}"
    echo -e "========================================="
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        return 1
    fi
}
