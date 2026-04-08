#!/usr/bin/env bash
# Consumer-side RabbitMQ redelivery verification for local dev.
# Proves an unacked message is requeued and redelivered after a consumer
# process crashes, using a temporary controlled queue and probe consumer.

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
export PROBE_SERVICE="${PROBE_SERVICE:-ingestion}"
export PROBE_RABBITMQ_URL="${PROBE_RABBITMQ_URL:-amqp://${RABBITMQ_USER}:${RABBITMQ_PASS}@rabbitmq:5672/}"

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

publish_message() {
    local routing_key="$1"
    local payload="$2"
    rabbit_api POST "/exchanges/%2F/woodpantry.topic/publish" "$(jq -nc --arg key "$routing_key" --arg payload "$payload" '{properties: {delivery_mode: 2, content_type: "application/json"}, routing_key: $key, payload: $payload, payload_encoding: "string"}')"
}

queue_has_ready_messages() {
    local queue_name="$1"
    [[ "$(get_queue "$queue_name" | jq -r '.messages_ready // 0')" -ge 1 ]]
}

queue_is_empty() {
    local queue_name="$1"
    local state
    state="$(get_queue "$queue_name")"
    [[ "$(echo "$state" | jq -r '.messages // 0')" -eq 0 ]] && [[ "$(echo "$state" | jq -r '.messages_unacknowledged // 0')" -eq 0 ]]
}

rabbitmq_ready() {
    local overview
    overview="$(rabbit_api GET "/overview")" || return 1
    echo "$overview" | jq -e '.rabbitmq_version | length > 0' > /dev/null 2>&1
}

probe_consumer() {
    local mode="$1"
    local queue_name="$2"
    local output

    output="$(
        compose exec -T \
            -e PROBE_MODE="$mode" \
            -e PROBE_QUEUE_NAME="$queue_name" \
            -e PROBE_RABBITMQ_URL="$PROBE_RABBITMQ_URL" \
            "$PROBE_SERVICE" \
            python - <<'PY'
import asyncio
import json
import os
import sys

import aio_pika


async def main() -> int:
    connection = await aio_pika.connect(os.environ["PROBE_RABBITMQ_URL"])
    channel = await connection.channel()
    queue = await channel.declare_queue(os.environ["PROBE_QUEUE_NAME"], durable=True)

    try:
        message = await queue.get(timeout=15, fail=False)
        if message is None:
            print(json.dumps({"received": False}))
            return 2

        result = {
            "received": True,
            "payload": message.body.decode(),
            "redelivered": message.redelivered,
        }
        print(json.dumps(result))
        sys.stdout.flush()

        if os.environ["PROBE_MODE"] == "crash":
            os._exit(23)

        await message.ack()
        return 0
    finally:
        await connection.close()


raise SystemExit(asyncio.run(main()))
PY
    )"
    local rc=$?

    if [[ "$mode" == "crash" && "$rc" -eq 23 ]]; then
        printf '%s\n' "$output"
        return 0
    fi

    if [[ "$rc" -ne 0 ]]; then
        printf '%s\n' "$output"
        return "$rc"
    fi

    printf '%s\n' "$output"
}

QUEUE_REDELIVERY="smoke-rabbitmq-redelivery-${SMOKE_RUN_ID}"
ROUTING_REDELIVERY="smoke.rabbitmq.redelivery.${SMOKE_RUN_ID}"
PROBE_PAYLOAD="smoke-rabbitmq-redelivery-${SMOKE_RUN_ID}"

cleanup() {
    delete_queue "$QUEUE_REDELIVERY"
}

trap cleanup EXIT

log_step "RabbitMQ Consumer Redelivery — Setup"

if wait_until rabbitmq_ready 60 2; then
    log_success "RabbitMQ management API is reachable before redelivery probe"
else
    log_fail "RabbitMQ management API is not reachable before redelivery probe"
    smoke_summary
    exit $?
fi

declare_queue "$QUEUE_REDELIVERY"
bind_queue "$QUEUE_REDELIVERY" "$ROUTING_REDELIVERY"

QUEUE_RESP=$(get_queue "$QUEUE_REDELIVERY")
assert_json_expr "$QUEUE_RESP" '.name == "'"$QUEUE_REDELIVERY"'"' "Verification queue exists before consumer crash"
assert_json_expr "$QUEUE_RESP" '.durable == true' "Verification queue is durable before consumer crash"

PUBLISH_RESP=$(publish_message "$ROUTING_REDELIVERY" "$PROBE_PAYLOAD")
assert_json_expr "$PUBLISH_RESP" '.routed == true' "Persistent verification message was routed before consumer crash"

if wait_until "queue_has_ready_messages \"$QUEUE_REDELIVERY\"" 20 1; then
    log_success "Verification queue contains a ready message before first delivery"
else
    log_fail "Verification queue never received the persistent message before first delivery"
    smoke_summary
    exit $?
fi

log_step "RabbitMQ Consumer Redelivery — Crash Before Ack"

FIRST_DELIVERY="$(probe_consumer crash "$QUEUE_REDELIVERY")" || {
    log_fail "Crash probe consumer failed before receiving a message. Output: $FIRST_DELIVERY"
    smoke_summary
    exit 1
}

assert_json_expr "$FIRST_DELIVERY" '.received == true' "Crash probe consumer received the first delivery"
assert_json_expr "$FIRST_DELIVERY" '.payload == "'"$PROBE_PAYLOAD"'"' "Crash probe consumer received the expected payload"
assert_json_expr "$FIRST_DELIVERY" '.redelivered == false' "First delivery was not marked as redelivered"

if wait_until "queue_has_ready_messages \"$QUEUE_REDELIVERY\"" 20 1; then
    log_success "Unacked message returned to the queue after consumer crash"
else
    log_fail "Unacked message did not return to the queue after consumer crash"
    smoke_summary
    exit $?
fi

SECOND_DELIVERY="$(probe_consumer ack "$QUEUE_REDELIVERY")" || {
    log_fail "Replacement probe consumer failed to receive the redelivery. Output: $SECOND_DELIVERY"
    smoke_summary
    exit 1
}

assert_json_expr "$SECOND_DELIVERY" '.received == true' "Replacement probe consumer received a delivery"
assert_json_expr "$SECOND_DELIVERY" '.payload == "'"$PROBE_PAYLOAD"'"' "Replacement probe consumer received the same payload"
assert_json_expr "$SECOND_DELIVERY" '.redelivered == true' "Replacement probe consumer observed the message as redelivered"

if wait_until "queue_is_empty \"$QUEUE_REDELIVERY\"" 20 1; then
    log_success "Queue is empty after replacement consumer acked the redelivery"
else
    log_fail "Queue did not drain after replacement consumer acked the redelivery"
fi

smoke_summary
