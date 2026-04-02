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
export SMOKE_RUN_ID="${SMOKE_RUN_ID:-smoke-$(date +%s)}"

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

require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        log_fail "jq is required for smoke tests"
        smoke_summary
        exit 1
    fi
}

wait_until() {
    local cmd="$1"
    local timeout="${2:-30}"
    local interval="${3:-2}"
    local elapsed=0

    while (( elapsed < timeout )); do
        if eval "$cmd" >/dev/null 2>&1; then
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    return 1
}

unique_name() {
    local prefix="$1"
    echo "${prefix} ${SMOKE_RUN_ID}"
}

unique_token() {
    local prefix="$1"
    echo "${prefix}-${SMOKE_RUN_ID}"
}

status_matches() {
    local actual="$1"
    local expected_csv="$2"
    local expected
    IFS=',' read -r -a expected <<< "$expected_csv"
    for code in "${expected[@]}"; do
        if [[ "$actual" == "$code" ]]; then
            return 0
        fi
    done
    return 1
}

# --- HTTP helpers ---
# Usage: api_get <url> [expected_status]
api_get() {
    local url="$1"
    local expected="${2:-200}"
    local status body
    body=$(curl -s -w '\n%{http_code}' "$url")
    status=$(echo "$body" | tail -n1)
    body=$(echo "$body" | sed '$d')
    if ! status_matches "$status" "$expected"; then
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
    if ! status_matches "$status" "$expected"; then
        echo "$body"
        return 1
    fi
    echo "$body"
}

# Usage: api_put <url> <json_body> [expected_status]
api_put() {
    local url="$1"
    local data="$2"
    local expected="${3:-200}"
    local status body
    body=$(curl -s -w '\n%{http_code}' -X PUT "$url" -H "Content-Type: application/json" -d "$data")
    status=$(echo "$body" | tail -n1)
    body=$(echo "$body" | sed '$d')
    if ! status_matches "$status" "$expected"; then
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
    if ! status_matches "$status" "$expected"; then
        echo "$body"
        return 1
    fi
    echo "$body"
}

extract_json() {
    local body="$1"
    local expr="$2"
    echo "$body" | jq -r "$expr // empty"
}

assert_json_expr() {
    local body="$1"
    local expr="$2"
    local message="$3"

    if echo "$body" | jq -e "$expr" > /dev/null 2>&1; then
        log_success "$message"
    else
        log_fail "$message. Response: $body"
    fi
}

has_json_path() {
    local body="$1"
    local expr="$2"
    echo "$body" | jq -e "$expr" > /dev/null 2>&1
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
