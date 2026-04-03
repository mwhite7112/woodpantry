#!/usr/bin/env bash
# Smoke tests: Pantry Service
# Tests item CRUD and verifies the response contract that downstream services depend on.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_jq

log_step "Pantry — Add Item"

# Higher entropy to avoid fuzzy-match collisions with stale data
ITEM_NAME="pantry-$(date +%s%N | cut -b10-19)-$(unique_token "onion")"

ADD_RESP=$(api_post "$PAN_URL/pantry/items" "$(jq -nc --arg name "$ITEM_NAME" '{name: $name, quantity: 2.0, unit: "pcs"}')" '200,201') || {
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

# The Pantry service returns a wrapper object with a top-level "items" collection.
# Matching was updated to consume this shape.
HAS_ITEMS_WRAPPER=$(echo "$PAN_RESP" | jq 'if type == "object" and (.items | type == "array") then true else false end')

if [[ "$HAS_ITEMS_WRAPPER" == "true" ]]; then
    log_success "GET /pantry returns wrapper object with items array"
else
    log_fail "CONTRACT MISMATCH: GET /pantry does not return {items:[...]}. Response: $PAN_RESP"
fi

# --- Verify items have expected fields ---
log_step "Pantry — Item Shape"

FIRST_ITEM=$(echo "$PAN_RESP" | jq '.items[0] // empty')
if [[ -z "$FIRST_ITEM" || "$FIRST_ITEM" == "null" ]]; then
    log_skip "No items to validate shape"
else
    # Strict contract check: only lowercase fields allowed for these keys
    assert_json_field "$FIRST_ITEM" "ingredient_id" "Pantry item has 'ingredient_id'"
    assert_no_json_field "$FIRST_ITEM" "IngredientID" "Pantry item should NOT have 'IngredientID'"
    
    assert_json_field "$FIRST_ITEM" "name" "Pantry item has 'name'"
    assert_no_json_field "$FIRST_ITEM" "Name" "Pantry item should NOT have 'Name'"

    assert_json_field "$FIRST_ITEM" "quantity" "Pantry item has 'quantity'"
    assert_no_json_field "$FIRST_ITEM" "Quantity" "Pantry item should NOT have 'Quantity'"

    assert_json_field "$FIRST_ITEM" "unit" "Pantry item has 'unit'"
    assert_no_json_field "$FIRST_ITEM" "Unit" "Pantry item should NOT have 'Unit'"
fi

log_step "Pantry — Added Item Visible"

HAS_ADDED_ITEM=$(echo "$PAN_RESP" | jq --arg name "$ITEM_NAME" 'any(.items[]; .name == $name)')
if [[ "$HAS_ADDED_ITEM" == "true" ]]; then
    log_success "Added pantry item appears in GET /pantry"
else
    if echo "$PAN_RESP" | jq --arg name "$ITEM_NAME" 'any(.items[]; .Name == $name)' | grep -q "true"; then
        log_fail "CONTRACT MISMATCH: Added item found with uppercase 'Name' instead of 'name'"
    else
        log_fail "Added pantry item missing from GET /pantry. Response: $PAN_RESP"
    fi
fi

log_step "Pantry — Validation"

if api_post "$PAN_URL/pantry/items" '{"quantity": 1, "unit": "pcs"}' '400,422' > /dev/null 2>&1; then
    log_success "Pantry rejects missing name with a 4xx validation error"
else
    log_fail "Pantry did not reject missing name with a validation error"
fi

smoke_summary; exit $?
