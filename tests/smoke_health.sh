#!/usr/bin/env bash
# Smoke tests: Service health checks
# Verifies all services are reachable and responding to /healthz.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

log_step "Health Checks"

for pair in "ingredients:$ING_URL" "recipes:$REC_URL" "pantry:$PAN_URL" "matching:$MAT_URL" "ingestion:$INGEST_URL" "shopping-list:$SHOP_URL"; do
    name="${pair%%:*}"
    url="${pair#*:}"
    if api_get "$url/healthz" > /dev/null 2>&1; then
        log_success "$name is healthy ($url/healthz)"
    else
        log_fail "$name is unreachable ($url/healthz)"
    fi
done

smoke_summary
