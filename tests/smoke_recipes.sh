#!/usr/bin/env bash
# Smoke tests: Recipe Service
# Tests basic recipe CRUD and ingredient linking.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

log_step "Recipes — Create Recipe"

RECIPE_TITLE="Soup-$(date +%s%N | cut -b10-19)-$(unique_token "smoke")"

CREATE_RESP=$(api_post "$REC_URL/recipes" "$(jq -nc --arg title "$RECIPE_TITLE" '{
    title: $title,
    ingredients: [
        {"name": "onion", "quantity": 1.0, "unit": "pcs"},
        {"name": "garlic", "quantity": 3.0, "unit": "cloves"}
    ],
    instructions: "Combine and simmer."
}')" '200,201') || {
    log_fail "POST /recipes returned non-200. Response: $CREATE_RESP"
    smoke_summary; exit $?
}

RECIPE_ID=$(extract_id_and_verify_contract "$CREATE_RESP" "CONTRACT MISMATCH: POST /recipes returned uppercase 'ID'")

if [[ -z "$RECIPE_ID" ]]; then
    log_fail "No recipe ID in response. Response: $CREATE_RESP"
else
    log_success "Created recipe → ID $RECIPE_ID"
fi

# --- Fetch it back ---
log_step "Recipes — Fetch Recipe"

if [[ -n "$RECIPE_ID" ]]; then
    FETCH_RESP=$(api_get "$REC_URL/recipes/$RECIPE_ID") || {
        log_fail "GET /recipes/$RECIPE_ID returned non-200. Response: $FETCH_RESP"
        smoke_summary; exit $?
    }

    assert_json_field "$FETCH_RESP" "id" "Recipe detail has 'id' field"
    assert_no_json_field "$FETCH_RESP" "ID" "Recipe detail should NOT have 'ID' field"
    assert_json_field "$FETCH_RESP" "title" "Recipe detail has 'title' field"
    assert_no_json_field "$FETCH_RESP" "Title" "Recipe detail should NOT have 'Title' field"

    TITLE=$(echo "$FETCH_RESP" | jq -r '.title // empty')
    if [[ "$TITLE" == "$RECIPE_TITLE" ]]; then
        log_success "Fetched recipe matches (title='$TITLE')"
    elif [[ -z "$TITLE" ]]; then
         log_fail "Recipe title is missing or empty (contract mismatch). Response: $FETCH_RESP"
    else
        log_fail "Recipe title mismatch: expected '$RECIPE_TITLE', got '$TITLE'"
    fi
else
    log_skip "Skipping fetch — no recipe ID from create step"
fi
smoke_summary; exit $?
