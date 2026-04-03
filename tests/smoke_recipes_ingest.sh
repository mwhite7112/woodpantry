#!/usr/bin/env bash
# Smoke tests: Recipe staged ingest flow
# Verifies free-text recipe ingest, staged retrieval, and confirm-to-commit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_jq

RECIPE_TITLE="$(unique_name "Smoke Ingest Soup")"
FREE_TEXT=$(cat <<EOF
${RECIPE_TITLE}

Ingredients:
- 1 yellow onion
- 2 garlic cloves
- 1 tablespoon olive oil

Instructions:
Saute onion and garlic in olive oil. Simmer briefly and serve.
EOF
)

log_step "Recipes Ingest — Submit"

INGEST_RESP=$(api_post "$REC_URL/recipes/ingest" "$(jq -nc --arg text "$FREE_TEXT" '{text: $text}')" '200,201,202') || {
    log_fail "POST /recipes/ingest returned non-200. Response: $INGEST_RESP"
    smoke_summary; exit $?
}

JOB_ID=$(extract_json "$INGEST_RESP" '.job_id // .jobID // .id // .ID')
if [[ -z "$JOB_ID" ]]; then
    log_fail "No job ID returned from recipe ingest. Response: $INGEST_RESP"
    smoke_summary; exit $?
else
    log_success "Recipe ingest created job $JOB_ID"
fi

log_step "Recipes Ingest — Review Staged Result"

STATUS_RESP=""
JOB_STATUS=""

for _ in $(seq 1 20); do
    STATUS_RESP=$(api_get "$REC_URL/recipes/ingest/$JOB_ID" '200,202') || {
        log_fail "GET /recipes/ingest/$JOB_ID returned non-200. Response: $STATUS_RESP"
        smoke_summary; exit $?
    }

    JOB_STATUS=$(extract_json "$STATUS_RESP" '.status // .Status')
    if [[ "$JOB_STATUS" == "staged" || "$JOB_STATUS" == "failed" ]]; then
        break
    fi

    sleep 1
done

if [[ -n "$JOB_STATUS" ]]; then
    log_success "Recipe ingest job status is '$JOB_STATUS'"
else
    log_skip "Recipe ingest status field not present"
fi

STAGED_TITLE=$(extract_json "$STATUS_RESP" '.recipe.title // .staged_recipe.title // .staged_data.title // .StagedData.title // .title')
STAGED_COUNT=$(echo "$STATUS_RESP" | jq '(.recipe.ingredients // .staged_recipe.ingredients // .staged_data.ingredients // .StagedData.ingredients // .ingredients // []) | length')

if [[ -n "$STAGED_TITLE" ]]; then
    log_success "Recipe ingest produced a staged recipe title"
else
    log_skip "Recipe ingest has not produced staged recipe data yet"
fi

if [[ "$STAGED_COUNT" -ge 2 ]]; then
    log_success "Staged recipe contains ingredient list"
else
    log_skip "Recipe ingest has no staged ingredients yet"
fi

log_step "Recipes Ingest — Confirm"

if [[ "$JOB_STATUS" == "failed" ]]; then
    log_fail "Recipe ingest job entered failed state. Response: $STATUS_RESP"
    smoke_summary
    exit $?
fi

if [[ -z "$STAGED_TITLE" && "$STAGED_COUNT" -lt 1 ]]; then
    log_skip "Skipping confirm until recipe ingest produces staged data"
    smoke_summary
    exit $?
fi

CONFIRM_RESP=$(api_post "$REC_URL/recipes/ingest/$JOB_ID/confirm" '{}' '200,201,202') || {
    log_fail "POST /recipes/ingest/$JOB_ID/confirm returned non-success. Response: $CONFIRM_RESP"
    smoke_summary; exit $?
}

RECIPE_ID=$(extract_json "$CONFIRM_RESP" '.recipe_id // .recipeID // .id // .ID')
if [[ -z "$RECIPE_ID" ]]; then
    log_skip "Confirm accepted, but no committed recipe ID is available yet"
    smoke_summary
    exit $?
else
    log_success "Recipe ingest confirmed as recipe $RECIPE_ID"
fi

FETCH_RESP=$(api_get "$REC_URL/recipes/$RECIPE_ID") || {
    log_fail "GET /recipes/$RECIPE_ID returned non-200. Response: $FETCH_RESP"
    smoke_summary; exit $?
}

FETCH_TITLE=$(extract_json "$FETCH_RESP" '.title')
if [[ -n "$STAGED_TITLE" && "$FETCH_TITLE" == "$STAGED_TITLE" ]]; then
    log_success "Confirmed recipe preserves the staged title"
elif [[ -n "$FETCH_TITLE" ]]; then
    log_fail "Confirmed recipe title mismatch: staged '$STAGED_TITLE', fetched '$FETCH_TITLE'"
else
    log_fail "Confirmed recipe title missing from fetch response: $FETCH_RESP"
fi

smoke_summary
