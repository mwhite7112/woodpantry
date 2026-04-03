#!/usr/bin/env bash
# Restart-oriented RabbitMQ durability verification for local dev.
# Proves a durable queue and persistent message survive a broker restart
# without removing the RabbitMQ volume.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_jq

export RABBIT_HTTP_URL="${RABBIT_HTTP_URL:-http://localhost:15672/api}"
export RABBITMQ_USER="${RABBITMQ_USER:-woodpantry}"
export RABBITMQ_PASS="${RABBITMQ_PASS:-woodpantry}"
export COMPOSE_ENGINE="${COMPOSE_ENGINE:-podman}"
export COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/local/docker-compose.yaml}"
export COMPOSE_ENV_FILE="${COMPOSE_ENV_FILE:-$REPO_ROOT/local/.env}"

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

compose() {
    "$COMPOSE_ENGINE" compose -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV_FILE" "$@"
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

publish_message() {
    local routing_key="$1"
    local payload="$2"
    rabbit_api POST "/exchanges/%2F/woodpantry.topic/publish" "$(jq -nc --arg key "$routing_key" --arg payload "$payload" '{properties: {delivery_mode: 2, content_type: "application/json"}, routing_key: $key, payload: $payload, payload_encoding: "string"}')"
}

queue_has_messages() {
    local queue_name="$1"
    [[ "$(get_queue "$queue_name" | jq -r '.messages // 0')" -ge 1 ]]
}

rabbitmq_ready() {
    local overview
    overview="$(rabbit_api GET "/overview")" || return 1
    echo "$overview" | jq -e '.rabbitmq_version | length > 0' > /dev/null 2>&1
}

queue_exists() {
    local queue_name="$1"
    [[ "$(get_queue "$queue_name" | jq -r '.name // empty')" == "$queue_name" ]]
}

QUEUE_RESTART="smoke-rabbitmq-restart-${SMOKE_RUN_ID}"
ROUTING_RESTART="smoke.rabbitmq.restart.${SMOKE_RUN_ID}"
PROBE_PAYLOAD="smoke-rabbitmq-restart-${SMOKE_RUN_ID}"

cleanup() {
    delete_queue "$QUEUE_RESTART"
}

trap cleanup EXIT

log_step "RabbitMQ Restart Durability — Setup"

if wait_until rabbitmq_ready 60 2; then
    log_success "RabbitMQ management API is reachable before restart"
else
    log_fail "RabbitMQ management API is not reachable before restart"
    smoke_summary
    exit $?
fi

declare_queue "$QUEUE_RESTART"
bind_queue "$QUEUE_RESTART" "$ROUTING_RESTART"

QUEUE_RESP=$(get_queue "$QUEUE_RESTART")
assert_json_expr "$QUEUE_RESP" '.name == "'"$QUEUE_RESTART"'"' "Verification queue exists before restart"
assert_json_expr "$QUEUE_RESP" '.durable == true' "Verification queue is durable before restart"

PUBLISH_RESP=$(publish_message "$ROUTING_RESTART" "$PROBE_PAYLOAD")
assert_json_expr "$PUBLISH_RESP" '.routed == true' "Persistent verification message was routed before restart"

if wait_until "queue_has_messages \"$QUEUE_RESTART\"" 20 1; then
    log_success "Verification queue contains a message before restart"
else
    log_fail "Verification queue never received the persistent message before restart"
    smoke_summary
    exit $?
fi

log_step "RabbitMQ Restart Durability — Broker Restart"

if compose restart rabbitmq > /dev/null; then
    log_success "RabbitMQ container restart command completed"
else
    log_fail "RabbitMQ container restart command failed"
    smoke_summary
    exit $?
fi

if wait_until rabbitmq_ready 60 2; then
    log_success "RabbitMQ management API recovered after restart"
else
    log_fail "RabbitMQ management API did not recover after restart"
    smoke_summary
    exit $?
fi

if wait_until "queue_exists \"$QUEUE_RESTART\"" 30 2; then
    log_success "Verification queue still exists after restart"
else
    log_fail "Verification queue did not reappear after restart"
    smoke_summary
    exit $?
fi

POST_RESTART_QUEUE=$(get_queue "$QUEUE_RESTART")
assert_json_expr "$POST_RESTART_QUEUE" '.durable == true' "Verification queue is still durable after restart"

POST_RESTART_MSGS=$(get_messages "$QUEUE_RESTART")
assert_json_expr "$POST_RESTART_MSGS" 'length == 1' "Retrieved one persistent message after restart"
if [[ "$(echo "$POST_RESTART_MSGS" | jq -r '.[0].payload')" == "$PROBE_PAYLOAD" ]]; then
    log_success "Persistent message payload survived broker restart"
else
    log_fail "Persistent message payload mismatch after restart. Response: $POST_RESTART_MSGS"
fi
assert_json_expr "$POST_RESTART_MSGS" '.[0].properties.delivery_mode == 2' "Persistent message retained delivery mode after restart"

smoke_summary
