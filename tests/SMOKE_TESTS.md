# WoodPantry — Smoke Test Guide

This directory contains end-to-end smoke tests that run against the full local Podman Compose stack. These tests verify HTTP contracts, cross-service integrations, and phase-level user journeys. They do not replace per-service unit or integration tests.

The current smoke scripts now cover the core Phase 1 flows plus a small set of contract-regression checks around Ingredient Dictionary, Recipe structured create, Pantry response shape, Matching, and staged ingest flows. This document defines the fuller target suite so new tests are added deliberately instead of ad hoc.

## Smoke Test Goals

- Catch broken service startup, wiring, or env config immediately.
- Catch HTTP contract drift between services.
- Catch staged-commit regressions across ingest flows.
- Catch cross-service invariants, especially Dictionary ownership and Matching dependencies.
- Keep tests idempotent so `make test-only` is safe against an already-running stack.
- Keep failures easy to localize by grouping tests by service or flow.

## Coverage Principles

- Smoke tests validate externally visible behavior only.
- Prefer one assertion with a clear failure over broad "didn't crash" checks.
- Cover both happy path and the smallest set of high-value guardrail failures.
- Favor deterministic fixtures over random test data, but namespace them so reruns are safe.
- Verify response shape as well as status code.
- Verify cross-service side effects when an endpoint is supposed to trigger them.

## Recommended Directory Structure

```bash
tests/
├── lib.sh
├── run_all.sh
├── smoke_health.sh
├── smoke_rabbitmq.sh
├── smoke_rabbitmq_restart.sh
├── smoke_ingredients.sh
├── smoke_recipes.sh
├── smoke_recipes_contracts.sh
├── smoke_recipes_ingest.sh
├── smoke_pantry.sh
├── smoke_pantry_ingest.sh
├── smoke_matching.sh
├── smoke_phase1_e2e.sh
├── smoke_ingestion_queue.sh          # Phase 2+
├── smoke_ingestion_twilio.sh         # Phase 2+
├── smoke_shopping_list.sh            # Phase 2+
├── smoke_phase2_e2e.sh               # Phase 2+
├── smoke_recipe_search.sh            # Phase 3+
├── smoke_receipt_ingest.sh           # Phase 3+
├── smoke_meal_plan.sh                # Phase 3+
├── smoke_phase3_e2e.sh               # Phase 3+
└── SMOKE_TESTS.md
```

If a phase is not implemented yet, the file should exist only when it has real assertions. Skip unsupported flows explicitly with `log_skip`.

## Test Data Strategy

Smoke tests must be rerunnable without a fresh database. Use stable names with a per-run suffix:

```bash
SMOKE_RUN_ID="${SMOKE_RUN_ID:-smoke-$(date +%s)}"
RECIPE_TITLE="Smoke Test Soup ${SMOKE_RUN_ID}"
INGREDIENT_NAME="yellow onion ${SMOKE_RUN_ID}"
```

Recommended patterns:

- Create fixtures through public APIs only.
- Capture returned IDs and reuse them within the file.
- Clean up when an API supports cleanup.
- When cleanup is unavailable, use unique names and assert on the created record only.
- Do not assume list endpoints return empty collections.

## Shared Helper Improvements

`lib.sh` is enough for basic checks, but the target suite should add these helpers:

| Helper | Purpose |
|--------|---------|
| `require_jq` | Fail fast if `jq` is unavailable |
| `api_put URL BODY [status]` | Needed for update-contract checks |
| `api_post_form URL BODY [status]` | Needed for Twilio webhook tests |
| `assert_json_expr BODY JQ_EXPR MESSAGE` | Reusable response-shape assertions |
| `assert_json_field BODY FIELD [MSG]` | Strict check for existence of lowercase field |
| `assert_no_json_field BODY FIELD [MSG]` | Strict check for absence of Go-style field |
| `extract_id_and_verify_contract BODY PREFIX` | Extract ID while alerting on case mismatch |
| `extract_json BODY JQ_EXPR` | Cleaner ID extraction |
| `wait_until CMD TIMEOUT_SECONDS` | Poll async jobs in Phase 2/3 |
| `unique_name PREFIX` | Safe rerun fixture naming |

These helpers keep the smoke files short and make failures more readable.

## Execution Order

Run tests from lowest-level dependency to highest-level flow:

1. `smoke_health.sh`
2. `smoke_rabbitmq.sh`
3. `smoke_ingredients.sh`
4. `smoke_recipes.sh`
5. `smoke_recipes_contracts.sh`
6. `smoke_pantry.sh`
7. `smoke_pantry_ingest.sh`
8. `smoke_matching.sh`
9. `smoke_phase1_e2e.sh`
10. Phase 2 files
11. `smoke_phase2_e2e.sh`
12. Phase 3 files
13. `smoke_phase3_e2e.sh`

This keeps failures local. If Matching fails because Pantry changed its response shape, you should see Pantry fail first.

`smoke_rabbitmq_restart.sh` is intentionally not part of the default `run_all.sh` sequence because it restarts the local broker container. Run it explicitly after the normal suite when you want restart-level durability evidence.

## Comprehensive Test Matrix

### `smoke_health.sh`

Purpose: startup and reachability.

Assertions:

- `GET /healthz` returns 200 for every enabled service.
- Response body is valid JSON if the service promises JSON.
- Optional: `GET /metrics` returns 200 for every service that should expose Prometheus metrics.

Failure value:

- Broken container startup
- Wrong host port mapping
- Routing or env misconfiguration

### `smoke_ingredients.sh`

Purpose: protect the canonical shared dictionary contract.

Assertions:

- `POST /ingredients/resolve` creates a new ingredient for a novel normalized name.
- Re-resolving the same name returns the same canonical ingredient ID.
- Resolving a normalized variant such as case or extra whitespace still returns the same ID.
- `GET /ingredients/:id` returns the created ingredient.
- `GET /ingredients` contains the created ingredient.
- `POST /ingredients` can create a manual ingredient if the service supports direct create.
- `PUT /ingredients/:id` can add aliases if implemented.
- Resolving an alias returns the winner ingredient ID.
- `POST /ingredients/merge` preserves the winner and makes the loser resolvable as an alias if implemented.
- Concurrent duplicate creation is not required in shell smoke tests, but a rerun should not create obvious duplicates for the exact same normalized name.

High-value negative checks:

- Missing `name` returns a 4xx, not 200 with broken payload.
- Invalid JSON returns a 4xx.

### `smoke_recipes.sh`

Purpose: protect recipe storage and dictionary linkage on structured create.

Assertions:

- `POST /recipes` creates a recipe with multiple ingredients.
- Response returns a recipe ID.
- `GET /recipes/:id` returns the same title and ingredients.
- `GET /recipes` includes the created recipe.
- Ingredient rows in the returned recipe expose canonical ingredient linkage if the API promises it.
- `PUT /recipes/:id` updates title, instructions, or metadata if implemented.
- `DELETE /recipes/:id` removes the recipe if implemented.
- Deleted recipes return 404 on fetch if delete is implemented.

Cross-service assertions:

- Structured recipe creation triggers ingredient resolution rather than storing free-text duplicates.
- Creating a recipe with an already-known ingredient reuses the canonical ingredient ID.

High-value negative checks:

- Empty title returns a 4xx.
- Missing ingredient list or malformed ingredient shape returns a 4xx.

### `smoke_recipes_ingest.sh`

Purpose: protect the Phase 1 staged recipe ingest flow, and later the async Phase 2 flow.

Phase 1 assertions:

- `POST /recipes/ingest` accepts free text and returns a job ID.
- `GET /recipes/ingest/:job_id` returns a staged recipe with title, ingredients, and status.
- `POST /recipes/ingest/:job_id/confirm` commits the recipe.
- The committed recipe can be fetched via `GET /recipes/:id`.
- Confirmed ingredients are resolved against the Dictionary and linked canonically.

Phase 2 assertions:

- Submission returns immediately with a pending job state.
- Polling eventually transitions to staged or ready-for-review.
- Confirm commits only after staging is complete.
- Failed jobs expose an error state without crashing the service.

High-value negative checks:

- Confirming a nonexistent job returns 404.
- Confirming a failed or incomplete job returns a 4xx.

### `smoke_recipes_contracts.sh`

Purpose: protect the structured recipe-create contracts that recently regressed.

Assertions:

- `POST /recipes` accepts ingredients specified only by `name`.
- Ingredients provided by `name` are resolved through the Dictionary and persisted with canonical `ingredient_id` values.
- `POST /recipes` still accepts explicit canonical `ingredient_id` values.
- Fetching the created recipe returns the expected canonical ingredient IDs.

High-value negative checks:

- Missing `title` returns a 4xx.

### `smoke_pantry.sh`

Purpose: protect pantry state and the response contract Matching depends on.

Assertions:

- `POST /pantry/items` adds a pantry item.
- Adding the same canonical ingredient again either updates quantity or creates the service-defined behavior consistently.
- `GET /pantry` returns the documented top-level shape.
- Every returned item has the required fields downstream services rely on.
- `DELETE /pantry/items/:id` removes the item if implemented.
- `DELETE /pantry/reset` clears pantry state if implemented.

Cross-service assertions:

- Pantry item creation resolves through Ingredient Dictionary.
- Canonical ingredient IDs are stable across pantry and recipe payloads if the APIs expose them.

Contract checks worth keeping permanently:

- `GET /pantry` returns the current wrapped collection shape Matching expects: `{ "items": [...] }`.
- Quantity and unit fields remain named consistently.

High-value negative checks:

- Missing `name` or invalid quantity returns 4xx.
- Deleting an unknown item returns 404 or the documented no-op status.

### `smoke_pantry_ingest.sh`

Purpose: protect staged pantry ingest.

Assertions:

- `POST /pantry/ingest` accepts a free-text pantry blob and returns a job ID.
- `GET /pantry/ingest/:job_id` returns staged items and status.
- `POST /pantry/ingest/:job_id/confirm` commits items into `GET /pantry`.
- Confirmed items resolve through Ingredient Dictionary.
- `DELETE /pantry/reset` can clean up after the file when available.

High-value negative checks:

- Confirming an unknown job returns 404.
- Reconfirming the same job is either idempotent or rejected with a clear 4xx.

### `smoke_matching.sh`

Purpose: protect the stateless cross-service recipe matching contract.

Fixture setup:

- Seed pantry with a small deterministic set.
- Seed recipes covering:
  - one exact match
  - one recipe missing one ingredient
  - one recipe missing several ingredients

Assertions:

- `GET /matches` returns 200 and a valid collection.
- Exact-match recipe appears in results.
- Exact-match recipe ranks above recipes with missing ingredients.
- `max_missing=0` excludes incomplete recipes.
- `max_missing=1` includes the single-missing recipe.
- Missing ingredient names are returned when a recipe is incomplete.
- `allow_subs=true` changes results only when substitute data exists.
- `POST /matches/query` returns deterministic results in Phase 1 if the endpoint exists as a stub.

High-value negative checks:

- If Pantry or Recipes return invalid shape, Matching should return a controlled error, not malformed output.

### `smoke_phase1_e2e.sh`

Purpose: protect the core daily-use loop from `CRAWL.md`.

Flow:

1. Add pantry items.
2. Create or ingest a recipe.
3. Fetch matches.
4. Verify the created recipe appears with the expected coverage.

Assertions:

- One complete vertical slice works across Ingredients, Pantry, Recipes, and Matching.
- IDs and names stay consistent across services.

This is the highest-value regression test in Phase 1 and should stay fast.

### `smoke_ingestion_queue.sh`

Purpose: protect async ingest once RabbitMQ is introduced.

Assertions:

- Submitting pantry ingest creates a pending job and eventually staged items.
- Submitting recipe ingest creates a pending job and eventually staged recipe data.
- Async jobs can be confirmed after staging.
- A RabbitMQ outage degrades gracefully where the service contract says it should.

Implementation note:

- This file should use polling helpers rather than fixed sleeps.

### `smoke_rabbitmq.sh`

Purpose: prove the broker and current event wiring are alive before deeper ingest tests run.

Assertions:

- RabbitMQ management API is reachable.
- `woodpantry.topic` exists and is durable.
- Core queues currently expected in local Phase 2 work exist and are durable.
- A direct publish to `woodpantry.topic` can be routed to a temporary verification queue and read back.
- `POST /pantry/items` emits a persistent `pantry.updated` event that can be observed from a temporary verification queue.

Implementation note:

- This file is the low-cost local proof for broker wiring.
- It does not prove broker persistence across a RabbitMQ container restart by itself; that restart check remains an explicit ops follow-up.

### `smoke_rabbitmq_restart.sh`

Purpose: prove a restart-oriented local durability scenario without relying on application consumers: a durable queue and a persistent message survive a targeted RabbitMQ container restart without removing volumes.

Assertions:

- A temporary durable verification queue can be declared and bound before restart.
- A persistent message can be published to that queue before restart.
- The local `rabbitmq` container can be restarted through Compose.
- After broker recovery, the same queue still exists and remains durable.
- The queued message is still present after restart, with the same payload and `delivery_mode = 2`.

Runbook:

```bash
make dev
make wait-healthy
make test-rabbitmq-restart
```

Implementation note:

- This is an opt-in, disruptive check and is intentionally excluded from `run_all.sh`.
- It proves broker-level durable storage across restart.
- It does not prove consumer-restart behavior, redelivery of unacked in-flight messages, or application-specific replay semantics.

### `smoke_ingestion_twilio.sh`

Purpose: protect the SMS ingestion contract.

Assertions:

- `POST /twilio/inbound` with valid form payload returns success.
- Invalid Twilio signature returns 403.
- A normal SMS body creates or enqueues a pantry ingest job.
- A `CONFIRM` reply confirms the latest pending job for that phone number.

Keep this file isolated from real Twilio by using local signature fixtures and fake credentials.

### `smoke_shopping_list.sh`

Purpose: protect shopping list aggregation.

Fixture setup:

- Seed pantry with partial inventory.
- Seed two or three recipes with overlapping ingredients.

Assertions:

- `POST /shopping-list` returns a persisted list ID.
- The fixture creates two recipes with the same ingredient so the generated list deduplicates into one aggregated item.
- That aggregated item reports `quantity_needed = 3.5`, `quantity_in_pantry = 1.0`, and `quantity_to_buy = 2.5` for the deterministic `cup` fixture.
- `GET /shopping-list/:id` returns the same persisted item and quantities as `POST /shopping-list`.

### `smoke_phase2_e2e.sh`

Purpose: protect the user journey from `WALK.md`.

Flow:

1. Submit pantry text through ingestion.
2. Review staged result.
3. Confirm pantry commit.
4. Submit recipe import.
5. Review and confirm recipe.
6. Generate matches or shopping list from the resulting data.

This should prove the queue-backed staged-commit architecture actually works.

### `smoke_recipe_search.sh`

Purpose: protect semantic recipe search in Phase 3.

Assertions:

- `POST /recipes/search` returns ranked recipes for a natural-language query.
- Imported recipes remain searchable after embeddings are generated.
- Search degrades clearly when embeddings are missing or still pending.

Use broad assertions about inclusion and ordering, not brittle exact score checks.

### `smoke_receipt_ingest.sh`

Purpose: protect receipt photo ingestion.

Assertions:

- MMS-like input or receipt upload creates a staged pantry job.
- The staged items include obvious line items from the receipt fixture.
- Ambiguous items are surfaced for review instead of being silently dropped.

Use a stable local fixture image committed to the relevant service repo once Phase 3 exists.

### `smoke_meal_plan.sh`

Purpose: protect meal-plan-backed shopping flows.

Assertions:

- `POST /meal-plans` creates a plan.
- Assigning recipes to days persists.
- Generating a shopping list from `meal_plan_id` returns the expected aggregate result.

### `smoke_phase3_e2e.sh`

Purpose: protect the full product loop from `RUN.md`.

Flow:

1. Ingest groceries from text or receipt.
2. Confirm pantry state.
3. Search or query for what to cook.
4. Build a meal plan.
5. Generate a shopping list delta.

Keep this file lean. It should prove the whole system works, not duplicate every lower-level assertion.

## Minimum Assertion Set by Service

If time is limited, these are the non-negotiable smoke checks:

| Service | Minimum smoke coverage |
|--------|-------------------------|
| Ingredients | resolve create, resolve idempotency, fetch by ID |
| Recipes | create structured recipe, fetch by ID, staged ingest confirm |
| Pantry | add item, list shape contract, staged ingest confirm |
| Matching | exact match ranking, `max_missing` filter |
| Ingestion | async job creation, staging, confirm path |
| Shopping List | aggregate and subtract pantry inventory |
| Meal Plan | create plan, attach recipes, shop from plan |

## Writing a New Smoke Test

### 1. Create the file

Name it `smoke_<domain>.sh`.

### 2. Use the template

```bash
#!/usr/bin/env bash
# Smoke tests: <Domain Name>
# One-line description of what this file covers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

log_step "Test Group Name"

RESP=$(api_post "$ING_URL/ingredients/resolve" '{"name": "test"}') || {
    log_fail "Description of what failed. Response: $RESP"
    smoke_summary; exit $?
}

VALUE=$(echo "$RESP" | jq -r '.some_field // empty')
if [[ -n "$VALUE" ]]; then
    log_success "Got expected value: $VALUE"
else
    log_fail "Missing expected field. Response: $RESP"
fi

smoke_summary
```

### 3. Key rules

- Always source `lib.sh`.
- Always end with `smoke_summary`.
- Use `api_*` helpers instead of raw `curl`.
- Test contracts, not internals.
- Keep one file focused on one service or one cross-service journey.
- Make the file safe to rerun.
- Add a `BUGS.md` link comment when the test guards a known regression.

## Tracking Bugs in `BUGS.md`

When a smoke test reveals a cross-service bug:

1. Add an entry to `BUGS.md` at the repo root with:
   - Date
   - Symptom
   - Error
   - Root Cause
   - Required Fix
   - Smoke Test
   - Status
2. Add a short comment in the smoke test pointing to that entry.
3. Keep the test after the bug is fixed.

### `BUGS.md` format

```markdown
## [YYYY-MM-DD] Short description

- **Symptom**: What the user or test sees.
- **Error**: `exact error message`
- **Root Cause**: Which service, which file, why.
- **Required Fix**: `service/path/to/file.go` - description of change.
- **Smoke Test**: `tests/smoke_<domain>.sh` - which test catches this.
- **Status**: OPEN | FIXED (YYYY-MM-DD)
```

## `lib.sh` API Reference

| Function | Usage | Description |
|----------|-------|-------------|
| `log_step "msg"` | Section header | Prints a yellow divider |
| `log_success "msg"` | Test passed | Prints green, increments pass counter |
| `log_fail "msg"` | Test failed | Prints red, increments fail counter |
| `log_skip "msg"` | Test skipped | Prints yellow, increments skip counter |
| `api_get URL [status]` | HTTP GET | Returns body; returns 1 on status mismatch |
| `api_post URL BODY [status]` | HTTP POST | JSON POST; returns body; returns 1 on mismatch |
| `api_delete URL [status]` | HTTP DELETE | Returns body; returns 1 on mismatch |
| `smoke_summary` | End of file | Prints totals; exits nonzero if any failures |
