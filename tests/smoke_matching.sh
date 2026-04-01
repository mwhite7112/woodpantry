#!/usr/bin/env bash
# Smoke tests: Matching Service
# Tests the cross-service matching flow (depends on Pantry + Recipes being populated).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

log_step "Matching — Basic Query"

RESP=$(api_get "$MAT_URL/matches?max_missing=5") || {
    log_fail "GET /matches returned non-200. Response: $RESP"
    smoke_summary; exit $?
}

ERROR=$(echo "$RESP" | jq -r '.error // empty')
if [[ -n "$ERROR" ]]; then
    log_fail "Matching returned error: $ERROR"
else
    log_success "GET /matches returned valid response"
fi

# --- Verify response is an array of match objects ---
log_step "Matching — Response Shape"

IS_VALID=$(echo "$RESP" | jq 'if type == "array" then true elif type == "object" and has("matches") then true else false end')
if [[ "$IS_VALID" == "true" ]]; then
    log_success "Matching response has expected shape"
else
    log_fail "Unexpected matching response shape. Response: $RESP"
fi

smoke_summary
