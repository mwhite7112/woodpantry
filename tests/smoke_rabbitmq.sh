#!/usr/bin/env bash
# Smoke tests: RabbitMQ broker and event wiring
# Verifies durable broker objects, direct publish/get, and pantry.updated routing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_jq

export RABBIT_HTTP_URL="${RABBIT_HTTP_URL:-http://localhost:15672/api}"
export RABBITMQ_USER="${RABBITMQ_USER:-woodpantry}"
export RABBITMQ_PASS="${RABBITMQ_PASS:-woodpantry}"

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

queue_has_messages() {
    local queue_name="$1"
    [[ "$(get_queue "$queue_name" | jq -r '.messages // 0')" -ge 1 ]]
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

QUEUE_DIRECT="smoke-rabbitmq-${SMOKE_RUN_ID}"
QUEUE_PANTRY="smoke-pantry-updated-${SMOKE_RUN_ID}"
ROUTING_DIRECT="smoke.rabbitmq.${SMOKE_RUN_ID}"
PROBE_PAYLOAD="smoke-rabbitmq-${SMOKE_RUN_ID}"
ITEM_NAME="rabbitmq-$(date +%s%N | cut -b10-19)-$(unique_token "pantry")"

cleanup() {
    delete_queue "$QUEUE_DIRECT"
    delete_queue "$QUEUE_PANTRY"
}

trap cleanup EXIT

log_step "RabbitMQ — Exchange Topology"

EXCHANGE_RESP=$(rabbit_api GET "/exchanges/%2F/woodpantry.topic")
assert_json_expr "$EXCHANGE_RESP" '.name == "woodpantry.topic"' "RabbitMQ exchange exists"
assert_json_expr "$EXCHANGE_RESP" '.type == "topic"' "RabbitMQ exchange uses topic routing"
assert_json_expr "$EXCHANGE_RESP" '.durable == true' "RabbitMQ exchange is durable"

for queue_name in ingestion.recipe-import-requested recipes.recipe-imported ingestion.pantry-ingest-requested; do
    QUEUE_RESP=$(get_queue "$queue_name")
    if [[ "$(echo "$QUEUE_RESP" | jq -r '.name')" == "$queue_name" ]]; then
        log_success "Queue ${queue_name} exists"
    else
        log_fail "Queue ${queue_name} missing. Response: $QUEUE_RESP"
    fi
    assert_json_expr "$QUEUE_RESP" '.durable == true' "Queue ${queue_name} is durable"
done

log_step "RabbitMQ — Direct Publish/Get Round Trip"

declare_queue "$QUEUE_DIRECT"
bind_queue "$QUEUE_DIRECT" "$ROUTING_DIRECT"

PUBLISH_DIRECT_RESP=$(rabbit_api POST "/exchanges/%2F/woodpantry.topic/publish" "$(jq -nc --arg key "$ROUTING_DIRECT" --arg payload "$PROBE_PAYLOAD" '{properties: {delivery_mode: 2, content_type: "application/json"}, routing_key: $key, payload: $payload, payload_encoding: "string"}')")
assert_json_expr "$PUBLISH_DIRECT_RESP" '.routed == true' "Direct broker publish was routed"

if wait_for_queue_message "$QUEUE_DIRECT" 10; then
    log_success "Direct broker round-trip queue received a message"
else
    log_fail "Direct broker round-trip queue never received a message"
    smoke_summary
    exit $?
fi

DIRECT_MSGS=$(get_messages "$QUEUE_DIRECT")
assert_json_expr "$DIRECT_MSGS" 'length == 1' "Direct broker get returned one message"
if [[ "$(echo "$DIRECT_MSGS" | jq -r '.[0].payload')" == "$PROBE_PAYLOAD" ]]; then
    log_success "Direct broker round-trip payload matches"
else
    log_fail "Direct broker round-trip payload mismatch. Response: $DIRECT_MSGS"
fi
assert_json_expr "$DIRECT_MSGS" '.[0].properties.delivery_mode == 2' "Direct broker round-trip message is persistent"

log_step "RabbitMQ — Pantry Event Routing"

declare_queue "$QUEUE_PANTRY"
bind_queue "$QUEUE_PANTRY" "pantry.updated"

ADD_RESP=$(api_post "$PAN_URL/pantry/items" "$(jq -nc --arg name "$ITEM_NAME" '{name: $name, quantity: 1.0, unit: "pcs"}')" '200,201') || {
    log_fail "POST /pantry/items failed while verifying pantry.updated routing. Response: $ADD_RESP"
    smoke_summary; exit $?
}
log_success "Pantry item add succeeded during RabbitMQ verification"

if wait_for_queue_message "$QUEUE_PANTRY" 10; then
    log_success "pantry.updated was routed into the verification queue"
else
    log_fail "pantry.updated did not reach the verification queue"
    smoke_summary
    exit $?
fi

PANTRY_MSGS=$(get_messages "$QUEUE_PANTRY")
assert_json_expr "$PANTRY_MSGS" 'length == 1' "Retrieved one pantry.updated event"
assert_json_expr "$PANTRY_MSGS" '.[0].routing_key == "pantry.updated"' "Retrieved event uses pantry.updated routing key"
assert_json_expr "$PANTRY_MSGS" '.[0].payload | fromjson | has("timestamp")' "pantry.updated payload includes timestamp"
assert_json_expr "$PANTRY_MSGS" '.[0].payload | fromjson | ((.changed_item_ids // []) | length) >= 1' "pantry.updated payload includes changed item IDs"
assert_json_expr "$PANTRY_MSGS" '.[0].properties.delivery_mode == 2' "pantry.updated event is persistent"

smoke_summary
