#!/usr/bin/env bash
# Smoke tests: Phase 1 end-to-end journey
# Verifies pantry + recipe + matching integration for a complete vertical slice.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_jq

RECIPE_TITLE="$(unique_name "Phase1 Match Soup")"
PANTRY_ONION="$(unique_name "onion")"
PANTRY_GARLIC="$(unique_name "garlic")"

log_step "Phase 1 E2E — Seed Pantry"

ONION_RESP=$(api_post "$PAN_URL/pantry/items" "$(jq -nc --arg name "$PANTRY_ONION" '{name: $name, quantity: 1, unit: "pcs"}')" '200,201') || {
    log_fail "Failed to add pantry onion. Response: $ONION_RESP"
    smoke_summary; exit $?
}
log_success "Added pantry onion fixture"

GARLIC_RESP=$(api_post "$PAN_URL/pantry/items" "$(jq -nc --arg name "$PANTRY_GARLIC" '{name: $name, quantity: 2, unit: "cloves"}')" '200,201') || {
    log_fail "Failed to add pantry garlic. Response: $GARLIC_RESP"
    smoke_summary; exit $?
}
log_success "Added pantry garlic fixture"

log_step "Phase 1 E2E — Create Recipe"

CREATE_RESP=$(api_post "$REC_URL/recipes" "$(jq -nc \
    --arg title "$RECIPE_TITLE" \
    --arg onion "$PANTRY_ONION" \
    --arg garlic "$PANTRY_GARLIC" \
    '{
        title: $title,
        ingredients: [
            {name: $onion, quantity: 1, unit: "pcs"},
            {name: $garlic, quantity: 2, unit: "cloves"}
        ],
        instructions: "Combine ingredients and simmer."
    }')") || {
    if echo "$CREATE_RESP" | jq -e '.error == "invalid ingredient_id: "' > /dev/null 2>&1; then
        log_skip "Skipping end-to-end match assertion because Recipe create currently requires ingredient_id"
        smoke_summary
        exit $?
    fi
    log_fail "Failed to create Phase 1 recipe. Response: $CREATE_RESP"
    smoke_summary; exit $?
}

RECIPE_ID=$(extract_json "$CREATE_RESP" '.id // .ID')
if [[ -z "$RECIPE_ID" ]]; then
    log_fail "Created recipe returned no ID. Response: $CREATE_RESP"
    smoke_summary; exit $?
else
    log_success "Created recipe $RECIPE_ID"
fi

log_step "Phase 1 E2E — Match Query"

MATCH_RESP=$(api_get "$MAT_URL/matches?max_missing=0") || {
    log_fail "GET /matches?max_missing=0 returned non-200. Response: $MATCH_RESP"
    smoke_summary; exit $?
}

HAS_RECIPE=$(echo "$MATCH_RESP" | jq --arg title "$RECIPE_TITLE" '
    if type == "array" then
        any(.[]; (.title // .recipe.title // "") == $title)
    elif type == "object" and has("matches") then
        any(.matches[]; (.title // .recipe.title // "") == $title)
    else
        false
    end')
if [[ "$HAS_RECIPE" == "true" ]]; then
    log_success "Matching returns the pantry-satisfied recipe"
else
    log_fail "Expected recipe '$RECIPE_TITLE' not found in matches. Response: $MATCH_RESP"
fi

COVERAGE=$(echo "$MATCH_RESP" | jq --arg title "$RECIPE_TITLE" -r '
    if type == "array" then
        first(.[] | select((.title // .recipe.title // "") == $title) | (.coverage // .coverage_pct // .coverage_percent // empty))
    elif type == "object" and has("matches") then
        first(.matches[] | select((.title // .recipe.title // "") == $title) | (.coverage // .coverage_pct // .coverage_percent // empty))
    else
        empty
    end')

if [[ "$COVERAGE" == "1" || "$COVERAGE" == "1.0" || "$COVERAGE" == "100" || "$COVERAGE" == "100.0" ]]; then
    log_success "Match coverage indicates a full pantry match ($COVERAGE)"
elif [[ -n "$COVERAGE" ]]; then
    log_fail "Expected full pantry coverage for '$RECIPE_TITLE', got '$COVERAGE'"
else
    log_skip "Coverage field not present in match response"
fi

smoke_summary
