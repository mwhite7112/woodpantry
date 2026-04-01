# WoodPantry — Smoke Test Guide

This directory contains end-to-end smoke tests that run against the full local Podman Compose stack. These tests verify cross-service contracts, not internal service logic (that's what each service's own unit/integration tests cover).

## Directory Structure

```
tests/
├── lib.sh                 ← Shared helpers (source this in every test file)
├── run_all.sh             ← Orchestrator — runs all smoke_*.sh files
├── smoke_health.sh        ← Health checks for all services
├── smoke_ingredients.sh   ← Ingredient Dictionary resolution
├── smoke_recipes.sh       ← Recipe CRUD and ingredient linking
├── smoke_pantry.sh        ← Pantry CRUD + response contract checks
├── smoke_matching.sh      ← Cross-service matching flow
└── SMOKE_TESTS.md         ← This file
```

## Running Tests

From the repo root:

```bash
make test          # Bring up stack → run all tests → tear down
make test-only     # Run tests against an already-running stack
make dev           # Just bring up the stack (for manual testing)
make dev-down      # Tear down the stack
```

## Writing a New Smoke Test

### 1. Create the file

Name it `smoke_<domain>.sh` where `<domain>` matches the service or cross-cutting concern:

| Domain | File | What it tests |
|--------|------|---------------|
| health | `smoke_health.sh` | `/healthz` on all services |
| ingredients | `smoke_ingredients.sh` | Ingredient Dictionary resolution |
| recipes | `smoke_recipes.sh` | Recipe CRUD |
| pantry | `smoke_pantry.sh` | Pantry CRUD + response contracts |
| matching | `smoke_matching.sh` | Cross-service matching flow |
| ingestion | `smoke_ingestion.sh` | Ingestion pipeline (Phase 2+) |
| e2e | `smoke_e2e.sh` | Full user journey across all services |

### 2. Use the template

```bash
#!/usr/bin/env bash
# Smoke tests: <Domain Name>
# One-line description of what this file covers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

log_step "Test Group Name"

# Use api_get, api_post, api_delete from lib.sh
RESP=$(api_post "$ING_URL/ingredients/resolve" '{"name": "test"}') || {
    log_fail "Description of what failed. Response: $RESP"
    smoke_summary; exit $?
}

# Validate with jq
VALUE=$(echo "$RESP" | jq -r '.some_field // empty')
if [[ -n "$VALUE" ]]; then
    log_success "Got expected value: $VALUE"
else
    log_fail "Missing expected field. Response: $RESP"
fi

smoke_summary
```

### 3. Key rules

- **Always source `lib.sh`** — it provides `log_step`, `log_success`, `log_fail`, `log_skip`, `api_get`, `api_post`, `api_delete`, and `smoke_summary`.
- **Always end with `smoke_summary`** — it prints pass/fail counts and returns a nonzero exit code on failure.
- **Use `api_*` helpers** — they handle status code checking. On non-200, they print the body and return 1.
- **Available service URLs**: `$ING_URL`, `$REC_URL`, `$PAN_URL`, `$MAT_URL`, `$INGEST_URL` (all from lib.sh).
- **One file per service/domain** — don't mix pantry tests into the matching file.
- **Test contracts, not internals** — smoke tests verify the HTTP API shape and cross-service behavior. Internal logic is tested by each service's own test suite.
- **Idempotency** — tests should be safe to run repeatedly. Don't assume a clean database (the compose stack resets volumes on `make dev`, but `make test-only` doesn't).

### 4. Automatic discovery

`run_all.sh` automatically picks up any file matching `tests/smoke_*.sh`. No registration needed — just create the file and it runs.

## Tracking Bugs in BUGS.md

When a smoke test reveals a cross-service bug:

1. **Add an entry to `BUGS.md`** at the repo root with:
   - Date (YYYY-MM-DD)
   - Symptom (what the test observed)
   - Error (exact error message if available)
   - Root Cause (which service and why)
   - Required Fix (specific file/function to change)
   - Status: `OPEN` or `FIXED (date)`

2. **Add a comment in the smoke test** linking to the BUGS.md entry so future readers know why the check exists.

3. **Do not delete the test when the bug is fixed** — the test becomes a regression guard. Update the comment to note it was fixed.

### BUGS.md format

```markdown
## [YYYY-MM-DD] Short description

- **Symptom**: What the user/test sees.
- **Error**: `exact error message`
- **Root Cause**: Which service, which file, why.
- **Required Fix**: `service/path/to/file.go` — description of change.
- **Smoke Test**: `tests/smoke_<domain>.sh` — which test catches this.
- **Status**: OPEN | FIXED (YYYY-MM-DD)
```

## lib.sh API Reference

| Function | Usage | Description |
|----------|-------|-------------|
| `log_step "msg"` | Section header | Prints a yellow `--- msg ---` divider |
| `log_success "msg"` | Test passed | Prints green, increments pass counter |
| `log_fail "msg"` | Test failed | Prints red, increments fail counter |
| `log_skip "msg"` | Test skipped | Prints yellow, increments skip counter |
| `api_get URL [status]` | HTTP GET | Returns body; returns 1 if status != expected (default 200) |
| `api_post URL BODY [status]` | HTTP POST | JSON POST; returns body; returns 1 on mismatch |
| `api_delete URL [status]` | HTTP DELETE | Returns body; returns 1 on mismatch |
| `smoke_summary` | End of file | Prints totals; exits nonzero if any failures |
