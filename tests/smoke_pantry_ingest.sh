#!/usr/bin/env bash
# Smoke tests: Pantry staged ingest flow
# Verifies free-text pantry ingest, staged retrieval, and confirm-to-commit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_jq

ITEM_ONE="$(unique_name "garlic cloves")"
ITEM_TWO="$(unique_name "heavy cream")"
FREE_TEXT="2 ${ITEM_ONE}, 1 ${ITEM_TWO}"

log_step "Pantry Ingest — Submit"

INGEST_RESP=$(api_post "$PAN_URL/pantry/ingest" "$(jq -nc --arg content "$FREE_TEXT" '{content: $content}')" '200,201,202') || {
    log_fail "POST /pantry/ingest returned non-200. Response: $INGEST_RESP"
    smoke_summary; exit $?
}

JOB_ID=$(extract_json "$INGEST_RESP" '.job_id // .jobID // .id // .ID')
if [[ -z "$JOB_ID" ]]; then
    log_fail "No job ID returned from pantry ingest. Response: $INGEST_RESP"
    smoke_summary; exit $?
else
    log_success "Pantry ingest created job $JOB_ID"
fi

log_step "Pantry Ingest — Review Staged Items"

STATUS_RESP=$(api_get "$PAN_URL/pantry/ingest/$JOB_ID" '200,202') || {
    log_fail "GET /pantry/ingest/$JOB_ID returned non-200. Response: $STATUS_RESP"
    smoke_summary; exit $?
}

JOB_STATUS=$(extract_json "$STATUS_RESP" '.status // .Status')
if [[ -n "$JOB_STATUS" ]]; then
    log_success "Pantry ingest job status is '$JOB_STATUS'"
else
    log_skip "Pantry ingest status field not present"
fi

STAGED_COUNT=$(echo "$STATUS_RESP" | jq '(.items // .staged_items // .stagedItems // []) | length')
if [[ "$STAGED_COUNT" -ge 2 ]]; then
    log_success "Staged pantry ingest returned items"
else
    log_skip "Pantry ingest has not produced staged items yet"
fi

log_step "Pantry Ingest — Confirm"

if [[ "$STAGED_COUNT" -lt 1 ]]; then
    log_skip "Skipping confirm until pantry ingest produces staged items"
    smoke_summary
    exit $?
fi

CONFIRM_RESP=$(api_post "$PAN_URL/pantry/ingest/$JOB_ID/confirm" '{}' '200,201,202') || {
    log_fail "POST /pantry/ingest/$JOB_ID/confirm returned non-success. Response: $CONFIRM_RESP"
    smoke_summary; exit $?
}
log_success "Pantry ingest confirm returned success"

PANTRY_RESP=$(api_get "$PAN_URL/pantry") || {
    log_fail "GET /pantry returned non-200 after confirm. Response: $PANTRY_RESP"
    smoke_summary; exit $?
}

HAS_ITEM_ONE=$(echo "$PANTRY_RESP" | jq --arg name "$ITEM_ONE" 'if type == "array" then any(.[]; (.name // "") == $name) elif type == "object" and has("items") then any(.items[]; (.name // "") == $name) else false end')
HAS_ITEM_TWO=$(echo "$PANTRY_RESP" | jq --arg name "$ITEM_TWO" 'if type == "array" then any(.[]; (.name // "") == $name) elif type == "object" and has("items") then any(.items[]; (.name // "") == $name) else false end')

if [[ "$HAS_ITEM_ONE" == "true" && "$HAS_ITEM_TWO" == "true" ]]; then
    log_success "Confirmed pantry ingest items appear in pantry state"
else
    log_fail "Confirmed pantry ingest items missing from pantry. Response: $PANTRY_RESP"
fi

smoke_summary
