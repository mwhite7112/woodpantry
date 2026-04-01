#!/usr/bin/env bash
# Smoke tests: Pantry Service
# Tests item CRUD and verifies the response contract that downstream services depend on.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

log_step "Pantry — Add Item"

ADD_RESP=$(api_post "$PAN_URL/pantry/items" '{"name": "onion", "quantity": 2.0, "unit": "pcs"}') || {
    log_fail "POST /pantry/items returned non-200. Response: $ADD_RESP"
    smoke_summary; exit $?
}
log_success "Added pantry item"

# --- Contract check: GET /pantry response shape ---
log_step "Pantry — Response Contract"

PAN_RESP=$(api_get "$PAN_URL/pantry") || {
    log_fail "GET /pantry returned non-200. Response: $PAN_RESP"
    smoke_summary; exit $?
}

# The Matching service expects a raw JSON array from GET /pantry.
# If Pantry wraps it in an object (e.g. {"items": [...]}), Matching breaks.
# See BUGS.md for history on this contract mismatch.
IS_ARRAY=$(echo "$PAN_RESP" | jq 'if type == "array" then true else false end')

if [[ "$IS_ARRAY" == "true" ]]; then
    log_success "GET /pantry returns raw array (Matching contract satisfied)"
else
    log_fail "CONTRACT MISMATCH: GET /pantry returns object, Matching expects array. Response: $PAN_RESP"
fi

# --- Verify items have expected fields ---
log_step "Pantry — Item Shape"

FIRST_ITEM=$(echo "$PAN_RESP" | jq '.[0] // empty' 2>/dev/null || echo "$PAN_RESP" | jq '.items[0] // empty' 2>/dev/null)
if [[ -z "$FIRST_ITEM" || "$FIRST_ITEM" == "null" ]]; then
    log_skip "No items to validate shape"
else
    HAS_NAME=$(echo "$FIRST_ITEM" | jq 'has("name")')
    HAS_QTY=$(echo "$FIRST_ITEM" | jq 'has("quantity")')
    if [[ "$HAS_NAME" == "true" && "$HAS_QTY" == "true" ]]; then
        log_success "Pantry item has expected fields (name, quantity)"
    else
        log_fail "Pantry item missing expected fields. Item: $FIRST_ITEM"
    fi
fi

smoke_summary
