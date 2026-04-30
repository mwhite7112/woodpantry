#!/usr/bin/env bash
# Smoke tests: Shopping List Service
# Verifies persisted list creation plus cross-service aggregation and pantry subtraction.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_jq

INGREDIENT_NAME="$(unique_name "shopping flour")"
RECIPE_ONE_TITLE="$(unique_name "shopping list recipe one")"
RECIPE_TWO_TITLE="$(unique_name "shopping list recipe two")"

log_step "Shopping List — Seed Pantry Fixture"

PANTRY_RESP=$(api_post "$PAN_URL/pantry/items" "$(jq -nc \
    --arg name "$INGREDIENT_NAME" \
    '{name: $name, quantity: 1.0, unit: "cup"}')" '200,201') || {
    log_fail "POST /pantry/items failed for shopping-list fixture. Response: $PANTRY_RESP"
    smoke_summary; exit $?
}
log_success "Seeded pantry stock for shopping-list fixture"

log_step "Shopping List — Seed Recipe Fixtures"

CREATE_RECIPE_ONE_RESP=$(api_post "$REC_URL/recipes" "$(jq -nc \
    --arg title "$RECIPE_ONE_TITLE" \
    --arg ingredient "$INGREDIENT_NAME" \
    '{
        title: $title,
        ingredients: [
            {name: $ingredient, quantity: 2.0, unit: "cup"}
        ],
        instructions: "Mix fixture one."
    }')" '200,201') || {
    log_fail "POST /recipes failed for first shopping-list fixture recipe. Response: $CREATE_RECIPE_ONE_RESP"
    smoke_summary; exit $?
}
RECIPE_ONE_ID=$(extract_id_and_verify_contract "$CREATE_RECIPE_ONE_RESP" "CONTRACT MISMATCH: shopping fixture recipe one returned uppercase 'ID'")

CREATE_RECIPE_TWO_RESP=$(api_post "$REC_URL/recipes" "$(jq -nc \
    --arg title "$RECIPE_TWO_TITLE" \
    --arg ingredient "$INGREDIENT_NAME" \
    '{
        title: $title,
        ingredients: [
            {name: $ingredient, quantity: 1.5, unit: "cup"}
        ],
        instructions: "Mix fixture two."
    }')" '200,201') || {
    log_fail "POST /recipes failed for second shopping-list fixture recipe. Response: $CREATE_RECIPE_TWO_RESP"
    smoke_summary; exit $?
}
RECIPE_TWO_ID=$(extract_id_and_verify_contract "$CREATE_RECIPE_TWO_RESP" "CONTRACT MISMATCH: shopping fixture recipe two returned uppercase 'ID'")

if [[ -n "$RECIPE_ONE_ID" && -n "$RECIPE_TWO_ID" ]]; then
    log_success "Created recipe fixtures for shopping-list generation"
else
    log_fail "Failed to capture both recipe IDs for shopping-list fixture"
    smoke_summary; exit $?
fi

log_step "Shopping List — Create Persisted List"

CREATE_LIST_RESP=$(api_post "$SHOP_URL/shopping-list" "$(jq -nc \
    --arg recipe_one_id "$RECIPE_ONE_ID" \
    --arg recipe_two_id "$RECIPE_TWO_ID" \
    '{recipe_ids: [$recipe_one_id, $recipe_two_id]}')" '201') || {
    log_fail "POST /shopping-list failed. This usually means recipe, pantry, dictionary, or shopping-list contracts drifted. Response: $CREATE_LIST_RESP"
    smoke_summary; exit $?
}

LIST_ID=$(extract_id_and_verify_contract "$CREATE_LIST_RESP" "CONTRACT MISMATCH: POST /shopping-list returned uppercase 'ID'")
if [[ -n "$LIST_ID" ]]; then
    log_success "POST /shopping-list returned persisted list ID $LIST_ID"
else
    log_fail "POST /shopping-list returned no list ID. Response: $CREATE_LIST_RESP"
    smoke_summary; exit $?
fi

assert_json_field "$CREATE_LIST_RESP" "recipe_ids" "Shopping list response has recipe_ids"
assert_json_field "$CREATE_LIST_RESP" "items" "Shopping list response has items"
assert_json_field "$CREATE_LIST_RESP" "groups" "Shopping list response has category groups"

ITEM_COUNT=$(extract_json "$CREATE_LIST_RESP" '.items | length')
if [[ "$ITEM_COUNT" == "1" ]]; then
    log_success "Shopping list aggregated duplicate recipe ingredients into one item"
else
    log_fail "Expected exactly 1 aggregated shopping-list item, got '$ITEM_COUNT'. Response: $CREATE_LIST_RESP"
fi

FIRST_ITEM=$(echo "$CREATE_LIST_RESP" | jq '.items[0] // empty')
if [[ -z "$FIRST_ITEM" || "$FIRST_ITEM" == "null" ]]; then
    log_fail "Shopping list returned no first item despite successful create. Response: $CREATE_LIST_RESP"
    smoke_summary; exit $?
fi

assert_json_field "$FIRST_ITEM" "ingredient_id" "Shopping item has ingredient_id"
assert_json_field "$FIRST_ITEM" "quantity_needed" "Shopping item has quantity_needed"
assert_json_field "$FIRST_ITEM" "quantity_in_pantry" "Shopping item has quantity_in_pantry"
assert_json_field "$FIRST_ITEM" "quantity_to_buy" "Shopping item has quantity_to_buy"
assert_json_field "$FIRST_ITEM" "unit" "Shopping item has unit"

if echo "$FIRST_ITEM" | jq -e '
    (.name == "'"$INGREDIENT_NAME"'") and
    (.unit == "cup") and
    ((.quantity_needed - 3.5) | fabs < 0.0001) and
    ((.quantity_in_pantry - 1.0) | fabs < 0.0001) and
    ((.quantity_to_buy - 2.5) | fabs < 0.0001)
' > /dev/null 2>&1; then
    log_success "Shopping list correctly aggregated recipe demand and subtracted pantry stock"
else
    log_fail "Shopping list quantities were incorrect. Expected name='$INGREDIENT_NAME', needed=3.5, pantry=1.0, to_buy=2.5, unit='cup'. Response: $FIRST_ITEM"
fi

if echo "$CREATE_LIST_RESP" | jq -e '
    (.groups | length == 1) and
    (.groups[0].category == .items[0].category) and
    (.groups[0].items | length == 1) and
    (.groups[0].items[0].id == .items[0].id) and
    (.groups[0].items[0].name == "'"$INGREDIENT_NAME"'")
' > /dev/null 2>&1; then
    log_success "Shopping list response includes additive category groups without changing flat items"
else
    log_fail "Shopping list category groups did not mirror the flat item. Response: $CREATE_LIST_RESP"
fi

log_step "Shopping List — Fetch Persisted List"

GET_LIST_RESP=$(api_get "$SHOP_URL/shopping-list/$LIST_ID") || {
    log_fail "GET /shopping-list/$LIST_ID failed. Response: $GET_LIST_RESP"
    smoke_summary; exit $?
}

FETCHED_ID=$(extract_json "$GET_LIST_RESP" '.id')
if [[ "$FETCHED_ID" == "$LIST_ID" ]]; then
    log_success "GET /shopping-list/{id} returned the same persisted list"
else
    log_fail "GET /shopping-list/{id} returned the wrong list ID. Expected '$LIST_ID', got '$FETCHED_ID'. Response: $GET_LIST_RESP"
fi

if echo "$GET_LIST_RESP" | jq -e '
    (.items | length == 1) and
    (.items[0].name == "'"$INGREDIENT_NAME"'") and
    ((.items[0].quantity_needed - 3.5) | fabs < 0.0001) and
    ((.items[0].quantity_in_pantry - 1.0) | fabs < 0.0001) and
    ((.items[0].quantity_to_buy - 2.5) | fabs < 0.0001)
' > /dev/null 2>&1; then
    log_success "GET /shopping-list/{id} preserved the created aggregate and pantry delta"
else
    log_fail "Fetched shopping list did not preserve the created aggregate quantities. Response: $GET_LIST_RESP"
fi

if echo "$GET_LIST_RESP" | jq -e '
    (.groups | length == 1) and
    (.groups[0].category == .items[0].category) and
    (.groups[0].items | length == 1) and
    (.groups[0].items[0].id == .items[0].id)
' > /dev/null 2>&1; then
    log_success "GET /shopping-list/{id} preserved category groups"
else
    log_fail "Fetched shopping list did not preserve category groups. Response: $GET_LIST_RESP"
fi

smoke_summary; exit $?
