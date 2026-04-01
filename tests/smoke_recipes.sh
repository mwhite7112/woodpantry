#!/usr/bin/env bash
# Smoke tests: Recipe Service
# Tests basic recipe CRUD and ingredient linking.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

log_step "Recipes — Create Recipe"

CREATE_RESP=$(api_post "$REC_URL/recipes" '{
    "title": "Smoke Test Soup",
    "ingredients": [
        {"name": "onion", "quantity": 1.0, "unit": "pcs"},
        {"name": "garlic", "quantity": 3.0, "unit": "cloves"}
    ],
    "instructions": "Combine and simmer."
}') || {
    log_fail "POST /recipes returned non-200. Response: $CREATE_RESP"
    smoke_summary; exit $?
}

RECIPE_ID=$(echo "$CREATE_RESP" | jq -r '.id // .ID // empty')
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

    TITLE=$(echo "$FETCH_RESP" | jq -r '.title // empty')
    if [[ "$TITLE" == "Smoke Test Soup" ]]; then
        log_success "Fetched recipe matches (title='$TITLE')"
    else
        log_fail "Recipe title mismatch: expected 'Smoke Test Soup', got '$TITLE'"
    fi
else
    log_skip "Skipping fetch — no recipe ID from create step"
fi

smoke_summary
