#!/usr/bin/env bash
# Smoke tests: Ingredient Dictionary contracts
# Verifies fetch/list behavior, normalization, and basic validation errors.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_jq

INGREDIENT_NAME="$(unique_token "zz-smoke-ingredient")"

log_step "Ingredients — Resolve and Fetch"

CREATE_RESP=$(api_post "$ING_URL/ingredients/resolve" "{\"name\": \"${INGREDIENT_NAME}\"}" '200,201') || {
    log_fail "Resolve failed for '${INGREDIENT_NAME}'. Response: $CREATE_RESP"
    smoke_summary; exit $?
}

INGREDIENT_ID=$(extract_json "$CREATE_RESP" '.ingredient.ID // .ingredient.id')
if [[ -z "$INGREDIENT_ID" ]]; then
    log_fail "Resolve returned no ingredient ID. Response: $CREATE_RESP"
    smoke_summary; exit $?
else
    log_success "Resolved ingredient ID $INGREDIENT_ID"
fi

FETCH_RESP=$(api_get "$ING_URL/ingredients/$INGREDIENT_ID") || {
    log_fail "GET /ingredients/$INGREDIENT_ID returned non-200. Response: $FETCH_RESP"
    smoke_summary; exit $?
}

FETCH_NAME=$(extract_json "$FETCH_RESP" '.name // .Name // .ingredient.name // .ingredient.Name')
if [[ "$FETCH_NAME" == "$INGREDIENT_NAME" ]]; then
    log_success "Fetched ingredient matches created name"
else
    log_fail "Fetched ingredient name mismatch: expected '$INGREDIENT_NAME', got '$FETCH_NAME'"
fi

log_step "Ingredients — List Endpoint"

LIST_RESP=$(api_get "$ING_URL/ingredients") || {
    log_fail "GET /ingredients returned non-200. Response: $LIST_RESP"
    smoke_summary; exit $?
}

LIST_HAS_ID=$(echo "$LIST_RESP" | jq --arg id "$INGREDIENT_ID" 'if type == "array" then any(.[]; ((.id // .ID | tostring) == $id)) elif type == "object" and has("ingredients") then any(.ingredients[]; ((.id // .ID | tostring) == $id)) else false end')
if [[ "$LIST_HAS_ID" == "true" ]]; then
    log_success "Ingredient appears in list endpoint"
else
    log_fail "Created ingredient missing from GET /ingredients. Response: $LIST_RESP"
fi

log_step "Ingredients — Normalization"

NORMALIZED_RESP=$(api_post "$ING_URL/ingredients/resolve" "{\"name\": \"  ${INGREDIENT_NAME^^}  \"}" '200,201') || {
    log_fail "Resolve failed for normalized variant. Response: $NORMALIZED_RESP"
    smoke_summary; exit $?
}

NORMALIZED_ID=$(extract_json "$NORMALIZED_RESP" '.ingredient.ID // .ingredient.id')
if [[ "$NORMALIZED_ID" == "$INGREDIENT_ID" ]]; then
    log_success "Resolve normalizes case and surrounding whitespace"
else
    log_fail "Normalization mismatch: expected ID $INGREDIENT_ID, got $NORMALIZED_ID"
fi

log_step "Ingredients — Validation"

if api_post "$ING_URL/ingredients/resolve" '{}' '400,422' > /dev/null 2>&1; then
    log_success "Resolve rejects missing name with a 4xx validation error"
else
    log_fail "Resolve did not reject missing name with a validation error"
fi

smoke_summary
