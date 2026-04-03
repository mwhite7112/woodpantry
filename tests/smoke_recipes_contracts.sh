#!/usr/bin/env bash
# Smoke tests: Recipe structured-create contracts
# Verifies name-based ingredient resolution and explicit ingredient_id passthrough.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_jq

RESOLVED_INGREDIENT_NAME="$(unique_name "contract flour")"
ID_ONLY_INGREDIENT_NAME="$(unique_name "contract milk")"
NAME_RECIPE_TITLE="Recipe-Name-Resolve-$(date +%s%N | cut -b10-19)-$(unique_token "smoke")"
ID_RECIPE_TITLE="Recipe-Explicit-ID-$(date +%s%N | cut -b10-19)-$(unique_token "smoke")"

log_step "Recipes Contracts — Seed Dictionary"

RESOLVE_ONE_RESP=$(api_post "$ING_URL/ingredients/resolve" "$(jq -nc --arg name "$RESOLVED_INGREDIENT_NAME" '{name: $name}')" '200,201') || {
    log_fail "Failed to resolve seed ingredient '$RESOLVED_INGREDIENT_NAME'. Response: $RESOLVE_ONE_RESP"
    smoke_summary; exit $?
}
RESOLVED_INGREDIENT_ID=$(extract_json "$RESOLVE_ONE_RESP" '.ingredient.id // .ingredient.ID // .id // .ID')

RESOLVE_TWO_RESP=$(api_post "$ING_URL/ingredients/resolve" "$(jq -nc --arg name "$ID_ONLY_INGREDIENT_NAME" '{name: $name}')" '200,201') || {
    log_fail "Failed to resolve seed ingredient '$ID_ONLY_INGREDIENT_NAME'. Response: $RESOLVE_TWO_RESP"
    smoke_summary; exit $?
}
ID_ONLY_INGREDIENT_ID=$(extract_json "$RESOLVE_TWO_RESP" '.ingredient.id // .ingredient.ID // .id // .ID')

if [[ -n "$RESOLVED_INGREDIENT_ID" && -n "$ID_ONLY_INGREDIENT_ID" ]]; then
    log_success "Seeded dictionary ingredients for recipe contract checks"
else
    log_fail "Failed to capture dictionary ingredient IDs"
    smoke_summary; exit $?
fi

log_step "Recipes Contracts — Structured Create Resolves Name"

CREATE_BY_NAME_RESP=$(api_post "$REC_URL/recipes" "$(jq -nc \
    --arg title "$NAME_RECIPE_TITLE" \
    --arg ingredient_name "$RESOLVED_INGREDIENT_NAME" \
    '{
        title: $title,
        ingredients: [
            {name: $ingredient_name, quantity: 2, unit: "cup"}
        ],
        instructions: "Mix and cook."
    }')" '200,201') || {
    log_fail "POST /recipes with ingredient name failed. Response: $CREATE_BY_NAME_RESP"
    smoke_summary; exit $?
}

NAME_RECIPE_ID=$(extract_id_and_verify_contract "$CREATE_BY_NAME_RESP" "CONTRACT MISMATCH: POST /recipes (by name) returned uppercase 'ID'")
if [[ -n "$NAME_RECIPE_ID" ]]; then
    log_success "Structured recipe create by ingredient name succeeded"
else
    log_fail "Structured recipe create by name returned no recipe ID. Response: $CREATE_BY_NAME_RESP"
    smoke_summary; exit $?
fi

NAME_FETCH_RESP=$(api_get "$REC_URL/recipes/$NAME_RECIPE_ID") || {
    log_fail "GET /recipes/$NAME_RECIPE_ID failed. Response: $NAME_FETCH_RESP"
    smoke_summary; exit $?
}

NAME_LINKED_ID=$(extract_json "$NAME_FETCH_RESP" '.ingredients[0].ingredient_id')
if [[ "$NAME_LINKED_ID" == "$RESOLVED_INGREDIENT_ID" ]]; then
    log_success "Recipe create by name persisted the canonical ingredient ID"
else
    if echo "$NAME_FETCH_RESP" | jq -e '.ingredients[0] | has("IngredientID")' > /dev/null 2>&1; then
        log_fail "CONTRACT MISMATCH: Ingredient has uppercase 'IngredientID' instead of 'ingredient_id'"
    else
        log_fail "Recipe create by name did not persist resolved ingredient ID. Expected '$RESOLVED_INGREDIENT_ID', got '$NAME_LINKED_ID'. Response: $NAME_FETCH_RESP"
    fi
fi

log_step "Recipes Contracts — Explicit Ingredient ID Persists"

CREATE_BY_ID_RESP=$(api_post "$REC_URL/recipes" "$(jq -nc \
    --arg title "$ID_RECIPE_TITLE" \
    --arg ingredient_id "$ID_ONLY_INGREDIENT_ID" \
    '{
        title: $title,
        ingredients: [
            {ingredient_id: $ingredient_id, quantity: 1.5, unit: "cup"}
        ],
        instructions: "Whisk and serve."
    }')" '200,201') || {
    log_fail "POST /recipes with explicit ingredient_id failed. Response: $CREATE_BY_ID_RESP"
    smoke_summary; exit $?
}

ID_RECIPE_ID=$(extract_id_and_verify_contract "$CREATE_BY_ID_RESP" "CONTRACT MISMATCH: POST /recipes (by ID) returned uppercase 'ID'")
if [[ -n "$ID_RECIPE_ID" ]]; then
    log_success "Structured recipe create with explicit ingredient_id succeeded"
else
    log_fail "Structured recipe create with explicit ingredient_id returned no recipe ID. Response: $CREATE_BY_ID_RESP"
    smoke_summary; exit $?
fi

ID_FETCH_RESP=$(api_get "$REC_URL/recipes/$ID_RECIPE_ID") || {
    log_fail "GET /recipes/$ID_RECIPE_ID failed. Response: $ID_FETCH_RESP"
    smoke_summary; exit $?
}

EXPLICIT_LINKED_ID=$(extract_json "$ID_FETCH_RESP" '.ingredients[0].ingredient_id')
if [[ "$EXPLICIT_LINKED_ID" == "$ID_ONLY_INGREDIENT_ID" ]]; then
    log_success "Recipe create preserved the explicit ingredient_id"
else
    if echo "$ID_FETCH_RESP" | jq -e '.ingredients[0] | has("IngredientID")' > /dev/null 2>&1; then
        log_fail "CONTRACT MISMATCH: Ingredient has uppercase 'IngredientID' instead of 'ingredient_id'"
    else
        log_fail "Recipe create did not preserve explicit ingredient_id. Expected '$ID_ONLY_INGREDIENT_ID', got '$EXPLICIT_LINKED_ID'. Response: $ID_FETCH_RESP"
    fi
fi

log_step "Recipes Contracts — Validation"

if api_post "$REC_URL/recipes" '{"ingredients":[{"name":"salt","quantity":1,"unit":"tsp"}]}' '400,422' > /dev/null 2>&1; then
    log_success "Recipe create rejects missing title with a 4xx validation error"
else
    log_fail "Recipe create did not reject missing title with a validation error"
fi

smoke_summary; exit $?
