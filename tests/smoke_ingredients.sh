#!/usr/bin/env bash
# Smoke tests: Ingredient Dictionary Service
# Tests ingredient resolution — the shared foundation all services depend on.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

log_step "Ingredient Resolution"

# Test: resolve a new ingredient
RESP=$(api_post "$ING_URL/ingredients/resolve" '{"name": "yellow onion"}' '200,201') || {
    log_fail "POST /ingredients/resolve returned non-200. Response: $RESP"
    smoke_summary; exit $?
}

ING_ID=$(echo "$RESP" | jq -r '.ingredient.ID // .ingredient.id // empty')
if [[ -z "$ING_ID" ]]; then
    log_fail "Resolve returned no ingredient ID. Response: $RESP"
else
    log_success "Resolved 'yellow onion' → ID $ING_ID"
fi

# Test: resolving the same name again should return the same ID (idempotent)
RESP2=$(api_post "$ING_URL/ingredients/resolve" '{"name": "yellow onion"}' '200,201') || {
    log_fail "Second resolve call failed. Response: $RESP2"
    smoke_summary; exit $?
}

ING_ID2=$(echo "$RESP2" | jq -r '.ingredient.ID // .ingredient.id // empty')
if [[ "$ING_ID" == "$ING_ID2" ]]; then
    log_success "Resolve is idempotent (same ID on repeat call)"
else
    log_fail "Resolve not idempotent: first=$ING_ID second=$ING_ID2"
fi

smoke_summary
