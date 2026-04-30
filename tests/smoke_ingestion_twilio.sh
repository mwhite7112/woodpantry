#!/usr/bin/env bash
# Smoke tests: Ingestion Twilio webhook
# Verifies local Twilio signature handling and pantry.ingest.requested publishing without live Twilio.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_jq

export RABBIT_HTTP_URL="${RABBIT_HTTP_URL:-http://localhost:15672/api}"
export RABBITMQ_USER="${RABBITMQ_USER:-woodpantry}"
export RABBITMQ_PASS="${RABBITMQ_PASS:-woodpantry}"

LOCAL_ENV_FILE="${LOCAL_ENV_FILE:-$SCRIPT_DIR/../local/.env}"

load_env_value() {
    local name="$1"
    local current="${!name:-}"
    if [[ -n "$current" || ! -f "$LOCAL_ENV_FILE" ]]; then
        echo "$current"
        return
    fi

    awk -F= -v key="$name" '
        $0 !~ /^[[:space:]]*#/ && $1 == key {
            sub(/^[^=]*=/, "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            gsub(/^"|"$/, "")
            gsub(/^'"'"'|\047$/, "")
            print
            exit
        }
    ' "$LOCAL_ENV_FILE"
}

TWILIO_AUTH_TOKEN="$(load_env_value TWILIO_AUTH_TOKEN)"
INGEST_BASE_URL="${INGEST_URL%/}"

rabbit_api() {
    local method="$1"
    local path="$2"
    local body="${3:-}"

    if [[ -n "$body" ]]; then
        curl -s -u "${RABBITMQ_USER}:${RABBITMQ_PASS}" \
            -X "$method" \
            -H "Content-Type: application/json" \
            "$RABBIT_HTTP_URL$path" \
            -d "$body"
        return
    fi

    curl -s -u "${RABBITMQ_USER}:${RABBITMQ_PASS}" -X "$method" "$RABBIT_HTTP_URL$path"
}

declare_queue() {
    local queue_name="$1"
    rabbit_api PUT "/queues/%2F/${queue_name}" '{"durable":true,"auto_delete":false,"arguments":{}}' > /dev/null
}

bind_queue() {
    local queue_name="$1"
    local routing_key="$2"
    rabbit_api POST "/bindings/%2F/e/woodpantry.topic/q/${queue_name}" "$(jq -nc --arg key "$routing_key" '{routing_key: $key, arguments: {}}')" > /dev/null
}

unbind_queue() {
    local queue_name="$1"
    local routing_key="$2"
    rabbit_api DELETE "/bindings/%2F/e/woodpantry.topic/q/${queue_name}/${routing_key}" > /dev/null 2>&1 || true
}

delete_queue() {
    local queue_name="$1"
    rabbit_api DELETE "/queues/%2F/${queue_name}" > /dev/null 2>&1 || true
}

get_queue() {
    local queue_name="$1"
    rabbit_api GET "/queues/%2F/${queue_name}"
}

get_messages() {
    local queue_name="$1"
    rabbit_api POST "/queues/%2F/${queue_name}/get" '{"count":1,"ackmode":"ack_requeue_false","encoding":"auto","truncate":50000}'
}

queue_message_count() {
    local queue_name="$1"
    get_queue "$queue_name" | jq -r '.messages // 0'
}

queue_has_messages() {
    local queue_name="$1"
    [[ "$(queue_message_count "$queue_name")" -ge 1 ]]
}

wait_for_queue_message() {
    local queue_name="$1"
    local attempts="${2:-10}"

    local i
    for i in $(seq 1 "$attempts"); do
        if queue_has_messages "$queue_name"; then
            return 0
        fi
        sleep 1
    done

    return 1
}

post_twilio_form() {
    local signature="$1"
    local form_body="$2"
    local response_file="$3"
    local status_file="$4"

    local status_code
    status_code=$(curl -s -o "$response_file" -w '%{http_code}' \
        -X POST "$INGEST_BASE_URL/twilio/inbound" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "X-Twilio-Signature: ${signature}" \
        --data "$form_body")
    printf '%s' "$status_code" > "$status_file"
}

generate_twilio_signature() {
    local url="$1"
    local token="$2"
    local form_body="$3"

    python3 - "$url" "$token" "$form_body" <<'PY'
import base64
import hashlib
import hmac
import sys
from urllib.parse import parse_qsl

url, token, form_body = sys.argv[1:4]
params = parse_qsl(form_body, keep_blank_values=True)
signed = url + "".join(f"{key}{value}" for key, value in sorted(params))
digest = hmac.new(token.encode(), signed.encode(), hashlib.sha1).digest()
print(base64.b64encode(digest).decode())
PY
}

encode_form() {
    local from_number="$1"
    local body="$2"

    python3 - "$from_number" "$body" <<'PY'
import sys
from urllib.parse import urlencode

print(urlencode({"From": sys.argv[1], "Body": sys.argv[2]}))
PY
}

QUEUE_TWILIO="smoke-twilio-pantry-ingest-${SMOKE_RUN_ID}"
APP_PANTRY_QUEUE="ingestion.pantry-ingest-requested"
ROUTING_KEY="pantry.ingest.requested"
FROM_NUMBER="+15555550123"
SMS_BODY="milk, eggs ${SMOKE_RUN_ID}"
FORM_BODY="$(encode_form "$FROM_NUMBER" "$SMS_BODY")"
RESPONSE_FILE="$(mktemp)"
STATUS_FILE="$(mktemp)"
APP_QUEUE_WAS_BOUND=0

app_queue_has_binding() {
    rabbit_api GET "/bindings/%2F/e/woodpantry.topic/q/${APP_PANTRY_QUEUE}" | \
        jq -e --arg key "$ROUTING_KEY" '[.[] | select(.source == "woodpantry.topic" and .routing_key == $key)] | length > 0' > /dev/null 2>&1
}

cleanup() {
    rm -f "$RESPONSE_FILE" "$STATUS_FILE"
    delete_queue "$QUEUE_TWILIO"
    if [[ "$APP_QUEUE_WAS_BOUND" -eq 1 ]]; then
        bind_queue "$APP_PANTRY_QUEUE" "$ROUTING_KEY"
    fi
}

trap cleanup EXIT

log_step "Ingestion Twilio — Signature Configuration"

if [[ -z "$TWILIO_AUTH_TOKEN" ]]; then
    post_twilio_form "invalid-signature" "$FORM_BODY" "$RESPONSE_FILE" "$STATUS_FILE"
    PROBE_STATUS="$(cat "$STATUS_FILE")"
    if [[ "$PROBE_STATUS" == "503" ]]; then
        log_skip "Twilio signature validation is not configured on ingestion; skipping Twilio webhook smoke test"
        smoke_summary
        exit $?
    fi
    if [[ "$PROBE_STATUS" == "403" ]]; then
        log_success "Invalid Twilio signature is rejected"
        log_skip "TWILIO_AUTH_TOKEN is unavailable to the smoke runner; cannot generate a valid local signature"
        smoke_summary
        exit $?
    fi
    log_fail "Expected 503 or 403 when probing Twilio webhook without local auth token, got ${PROBE_STATUS}. Response: $(cat "$RESPONSE_FILE")"
    smoke_summary
    exit $?
fi

log_success "TWILIO_AUTH_TOKEN is available to generate local webhook signatures"

log_step "Ingestion Twilio — Event Probe Setup"

declare_queue "$QUEUE_TWILIO"
bind_queue "$QUEUE_TWILIO" "$ROUTING_KEY"
log_success "Temporary RabbitMQ probe queue is bound to ${ROUTING_KEY}"

log_step "Ingestion Twilio — Invalid Signature"

post_twilio_form "invalid-signature" "$FORM_BODY" "$RESPONSE_FILE" "$STATUS_FILE"
INVALID_STATUS="$(cat "$STATUS_FILE")"
if [[ "$INVALID_STATUS" == "503" ]]; then
    log_skip "Twilio signature validation is not configured on ingestion; skipping Twilio webhook smoke test"
    smoke_summary
    exit $?
elif [[ "$INVALID_STATUS" == "403" ]]; then
    log_success "Invalid Twilio signature returns 403"
else
    log_fail "Invalid Twilio signature should return 403, got ${INVALID_STATUS}. Response: $(cat "$RESPONSE_FILE")"
    smoke_summary
    exit $?
fi

if [[ "$(queue_message_count "$QUEUE_TWILIO")" == "0" ]]; then
    log_success "Invalid Twilio request did not publish pantry.ingest.requested"
else
    log_fail "Invalid Twilio request unexpectedly published pantry.ingest.requested"
fi

log_step "Ingestion Twilio — Worker Isolation"

if app_queue_has_binding; then
    APP_QUEUE_WAS_BOUND=1
    # Prevent the real ingestion pantry worker from consuming the smoke event and calling OpenAI/Twilio.
    unbind_queue "$APP_PANTRY_QUEUE" "$ROUTING_KEY"
    if app_queue_has_binding; then
        log_skip "Could not temporarily unbind ${APP_PANTRY_QUEUE}; skipping valid SMS publish to avoid OpenAI and live Twilio side effects"
        smoke_summary
        exit $?
    fi
    log_success "Real pantry ingest worker queue temporarily unbound"
else
    log_success "Real pantry ingest worker queue is not bound; no worker isolation needed"
fi

log_step "Ingestion Twilio — Valid SMS Publish"

VALID_SIGNATURE="$(generate_twilio_signature "$INGEST_BASE_URL/twilio/inbound" "$TWILIO_AUTH_TOKEN" "$FORM_BODY")"
post_twilio_form "$VALID_SIGNATURE" "$FORM_BODY" "$RESPONSE_FILE" "$STATUS_FILE"
VALID_STATUS="$(cat "$STATUS_FILE")"
if status_matches "$VALID_STATUS" "200,202"; then
    log_success "Valid Twilio SMS webhook accepted with status ${VALID_STATUS}"
else
    log_fail "Valid Twilio SMS webhook should return 200 or 202, got ${VALID_STATUS}. Response: $(cat "$RESPONSE_FILE")"
    smoke_summary
    exit $?
fi

if wait_for_queue_message "$QUEUE_TWILIO" 10; then
    log_success "pantry.ingest.requested was routed into the Twilio verification queue"
else
    log_fail "pantry.ingest.requested did not reach the Twilio verification queue"
    smoke_summary
    exit $?
fi

TWILIO_MSGS="$(get_messages "$QUEUE_TWILIO")"
assert_json_expr "$TWILIO_MSGS" 'length == 1' "Retrieved one Twilio pantry ingest event"
assert_json_expr "$TWILIO_MSGS" '.[0].routing_key == "pantry.ingest.requested"' "Retrieved event uses pantry.ingest.requested routing key"

EVENT_RAW_TEXT="$(echo "$TWILIO_MSGS" | jq -r '.[0].payload | fromjson | .raw_text // empty')"
if [[ "$EVENT_RAW_TEXT" == "$SMS_BODY" ]]; then
    log_success "Twilio event payload includes raw SMS body"
else
    log_fail "Twilio event payload raw_text mismatch. Response: $TWILIO_MSGS"
fi

EVENT_FROM_NUMBER="$(echo "$TWILIO_MSGS" | jq -r '.[0].payload | fromjson | .from_number // empty')"
if [[ "$EVENT_FROM_NUMBER" == "$FROM_NUMBER" ]]; then
    log_success "Twilio event payload includes source phone number"
else
    log_fail "Twilio event payload from_number mismatch. Response: $TWILIO_MSGS"
fi

assert_json_expr "$TWILIO_MSGS" '.[0].payload | fromjson | (.job_id | type == "string" and length > 0)' "Twilio event payload includes job ID"
assert_json_expr "$TWILIO_MSGS" '.[0].properties.delivery_mode == 2' "Twilio event is persistent"

smoke_summary
