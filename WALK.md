# WALK — Phase 2: Ingestion Pipeline + Queue

**Phase Goal**: Remove all friction from pantry updates. Make the SMS flow work end-to-end. Introduce RabbitMQ as the event backbone. Add shopping list generation.

**Status (2026-04-03)**:
- [x] W-1 is implemented in infra code: RabbitMQ, durable queues, persistence, and management ingress all exist in `../woodhouse-infra`.
- [x] W-2 through W-4 are partially to mostly implemented in application code.
- [x] `woodpantry-ingestion` now has a passing local Python test suite.
- [ ] W-5 and W-7 are not implemented beyond stubs/placeholders.
- [~] W-6 backend generation is implemented and locally verified by service integration tests plus root smoke coverage; category-grouped responses and release wiring still remain.

**Notes**:
- `woodpantry-recipes` already uses async queue-based ingest.
- `woodpantry-pantry` still also supports the older in-service OpenAI ingest path; the queue-based pantry path exists in `woodpantry-ingestion`, but the pantry service has not been fully refactored off the direct path.
- `woodpantry-pantry` now exposes `POST /pantry/ingest/{job_id}/stage` for queue-driven pantry staging.
- `woodpantry-ingestion` is now wired into `../woodhouse-infra/apps/woodpantry`, but deploy success still depends on a published image tag being available.
- The pantry cluster deployment now injects `RABBITMQ_URL`, so `pantry.updated` publishing is enabled by the cluster manifests when the secret contains `rabbitmq_url`.
- Local broker proof now exists in `tests/smoke_rabbitmq.sh`: it verifies exchange/queue durability flags, direct publish/get, and `pantry.updated` routing.
- Local broker-restart proof now also exists in `tests/smoke_rabbitmq_restart.sh`: it restarts the local `rabbitmq` container without removing volumes and verifies that a durable queue plus a persistent message survive the restart. This passed locally on 2026-04-03 via `make test-rabbitmq-restart`.
- Local consumer-redelivery proof now also exists in `tests/smoke_rabbitmq_redelivery.sh`: it publishes a persistent message to a temporary durable queue, crashes a probe consumer before `ack`, and verifies that a replacement consumer receives the same payload with `redelivered = true`. This is the narrow local proof for unacked-message survival across consumer loss.
- Application-specific consumer restart and replay handling are still an explicit follow-up; the current repo automation does not yet prove that a real WoodPantry service container or pod reconnects and safely reprocesses the replayed message after restart.

**Exit Criteria**:
- You can text a grocery list to a Twilio number and have it show up in your pantry after confirming
- RabbitMQ is deployed and all Phase 1 services publish/subscribe where specified
- Shopping list generation works given a set of recipe IDs
- OpenAPI spec is complete enough to hand to the frontend developer

**Prerequisite**: All CRAWL tickets complete and Phase 1 services stable in cluster.

---

## W-1 — Deploy RabbitMQ to Cluster

**Goal**: Stand up RabbitMQ as the event backbone. Establish exchange and queue topology before any services start using it.

**Service**: Infrastructure

**Deliverables**:
- [x] RabbitMQ deployed to cluster via Helm chart or k8s manifests
- [x] Persistent storage via Longhorn
- [x] Management UI exposed via Traefik (internal only)
- [x] Define exchange topology:
  - `woodpantry.topic` exchange (topic type)
  - Routing keys: `pantry.ingest.requested`, `pantry.updated`, `recipe.import.requested`, `recipe.imported`, `shopping_list.requested`
- [x] RabbitMQ credentials in cluster secrets
- [x] Document exchange + queue topology in this file and in `woodpantry-ingestion/CLAUDE.md`

### Exchange & Queue Topology

**Exchange**: `woodpantry.topic` (type: topic, durable)

| Queue | Routing Key | Publisher | Consumer |
|-------|-------------|-----------|----------|
| `pantry.ingest.queue` | `pantry.ingest.requested` | Ingestion Pipeline (SMS webhook) | Ingestion Pipeline (worker) |
| `pantry.updated.queue` | `pantry.updated` | Pantry Service | Matching Service, Shopping List |
| `recipe.import.queue` | `recipe.import.requested` | Recipe Service | Ingestion Pipeline (worker) |
| `recipe.imported.queue` | `recipe.imported` | Ingestion Pipeline (worker) | Recipe Service |
| `shopping_list.queue` | `shopping_list.requested` | API / Meal Plan | Shopping List Service |

**Connection string**: `amqp://woodpantry:<password>@rabbitmq.rabbitmq.svc.cluster.local:5672/`

**Management UI**: `https://rabbitmq.woodlab.work`

**Acceptance Criteria**:
- [x] RabbitMQ management UI accessible
- [x] Local publish/consume round-trip works via `tests/smoke_rabbitmq.sh`
- [x] Durable queue plus persistent message survive a targeted local broker restart via `tests/smoke_rabbitmq_restart.sh`
- [x] Unacked-message redelivery after a consumer crash is re-verified via `tests/smoke_rabbitmq_redelivery.sh`
- [ ] Durable behavior across a real WoodPantry consumer container or pod restart is directly re-verified

---

## W-2 — Refactor Pantry Service: Publish Events

**Goal**: Pantry Service publishes `pantry.updated` after any stock change so downstream consumers (Matching Service cache, future notification service) can react.

**Service**: `woodpantry-pantry`

**Deliverables**:
- [x] Add RabbitMQ publisher to Pantry Service (`internal/events/publisher.go`)
- [x] Publish `pantry.updated` event after: item add, item update, item delete, ingest confirm, reset
- [x] Event payload: `{ "timestamp": "...", "changed_item_ids": [...] }` (keep it minimal)
- [x] Graceful handling if RabbitMQ is unavailable (log error, do not fail the HTTP request)
- [x] `RABBITMQ_URL` env var, optional — if not set, skip publishing (preserves Phase 1 behaviour)

**Acceptance Criteria**:
- [x] A pantry item update publishes a `pantry.updated` message observable from a temporary verification queue (`tests/smoke_rabbitmq.sh`)
- [x] Service continues operating normally if RabbitMQ is down

---

## W-3 — Refactor Recipe Service: Async Import via Queue

**Goal**: Recipe import (ingest) flow becomes async. Submission publishes a `recipe.import.requested` event; the Ingestion Pipeline picks it up and publishes `recipe.imported` when done; Recipe Service subscribes and commits.

**Service**: `woodpantry-recipes`

**Deliverables**:
- [x] Add RabbitMQ publisher: publish `recipe.import.requested` on `POST /recipes/ingest` instead of calling OpenAI API directly
- [x] Add RabbitMQ subscriber: listen for `recipe.imported` events, commit the structured recipe payload to DB
- [x] `POST /recipes/ingest/:job_id/confirm` flow updated to work with async job status
- [x] Phase 1 direct OpenAI API call removed from Recipe Service (moved to Ingestion Pipeline)
- [x] Job status polling still works via `GET /recipes/ingest/:job_id`

**Acceptance Criteria**:
- [x] Submitting a recipe for import returns a job ID immediately
- [x] Ingestion Pipeline processes the job asynchronously and Recipe Service commits on `recipe.imported`
- [x] Staged review flow still works — user can still review and confirm before commit

---

## W-4 — Build Ingestion Pipeline: Core Service

**Goal**: Build the Ingestion Pipeline service. Phase 2 scope: SMS text list ingestion and free-text recipe import. No photo/OCR yet (Phase 3).

**Service**: `woodpantry-ingestion`

**Deliverables**:
- [x] Service scaffolding: FastAPI app + uvicorn, health check, aio-pika RabbitMQ subscriber setup
- [x] Subscribe to `pantry.ingest.requested`:
  - Extract structured ingredient list from free-text using OpenAI API
  - Call `/ingredients/resolve` for each item
  - POST staged items to Pantry Service
  - Publish result back or update job status
- [x] Subscribe to `recipe.import.requested`:
  - Extract structured recipe JSON from free-text using OpenAI API
  - Publish `recipe.imported` with structured payload
- [x] OpenAI API client with structured extraction prompts for both pantry and recipe contexts (`gpt-5-mini` for cost efficiency)
- [x] Per-job error handling: mark job as failed (Recipe flow and Pantry flow publish failure events)
- [x] `OPENAI_API_KEY`, `RABBITMQ_URL` env vars
  The recipe worker publishes `recipe.imported`; it does not currently resolve ingredients itself because recipe confirm still resolves in `woodpantry-recipes`.

**Acceptance Criteria**:
 - [x] Free-text pantry ingest via queue stages items in Pantry Service via `POST /pantry/ingest/{job_id}/stage`
- [x] Free-text recipe import via queue produces a confirmed recipe in Recipe Service
- [x] LLM failures mark the job as failed without crashing the service
  The current local Python test suite passes, including worker/client coverage around failure handling.

---

## W-5 — Twilio Webhook: SMS Text List Ingestion

**Goal**: Handle inbound SMS from Twilio. User texts a grocery list, the pipeline extracts it and stages it in the Pantry Service. A confirmation SMS is sent back.

**Service**: `woodpantry-ingestion`

**Deliverables**:
- [ ] `POST /twilio/inbound` — Twilio webhook handler, validates Twilio signature
- [ ] Parse inbound SMS body and `From` number
- [ ] If body is text: publish `pantry.ingest.requested` event with raw text
- [ ] After staged items created: send reply SMS via Twilio REST API — `"N items staged. M need review. Reply CONFIRM to commit."`
- [ ] Handle `CONFIRM` reply: trigger `POST /pantry/ingest/:job_id/confirm` for the most recent pending job for that phone number
- [ ] Map phone number → in-progress job ID (simple in-memory store or lightweight DB table)
- [ ] Twilio credentials via env vars (`TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`)
- [ ] Webhook URL exposed via Traefik with public DNS (or ngrok for dev)

**Acceptance Criteria**:
- [ ] Texting "2 lbs chicken, garlic, heavy cream" results in staged pantry items and a confirmation SMS reply
- [ ] Replying CONFIRM commits the staged items
- [ ] Invalid Twilio signatures are rejected with 403

---

## W-6 — Shopping List Service

**Goal**: Given a set of recipe IDs, produce a deduplicated aggregated shopping list diffed against current pantry state.

**Service**: `woodpantry-shopping-list`

**Deliverables**:
- [x] DB schema: `shopping_lists`, `shopping_list_items` tables (for persisting generated lists)
- [x] Runnable Go scaffold: entrypoint, env parsing, migrations, `/healthz`, Dockerfile, tests, and Kubernetes manifests
- [x] `POST /shopping-list` — accept array of recipe IDs; fetch each recipe's ingredients from Recipe Service; aggregate quantities per ingredient; diff against Pantry Service current state; persist and return list
- [x] `GET /shopping-list/:id` — retrieve a previously generated list
- [ ] Items grouped by ingredient category in response
- [x] Quantity aggregation handles unit normalization (e.g. 500g + 250g = 750g) using unit conversion data from Dictionary
- [x] HTTP clients for Recipe Service, Pantry Service, Ingredient Dictionary

  `woodpantry-shopping-list` now has runnable generation endpoints, upstream clients, migrations, and persisted list retrieval. Root smoke coverage verifies `POST /shopping-list` and `GET /shopping-list/{id}` against live recipe, pantry, and dictionary dependencies in the local stack.
  It also still needs to be created as a standalone GitHub repo and published to GHCR before GitOps can deploy it.

**Acceptance Criteria**:
- [x] Shopping list generation is smoke-verified for overlapping recipe ingredients with pantry subtraction
- [ ] Items already in pantry at sufficient quantity do not appear on the list
- [ ] Items partially in pantry show the delta quantity needed
- [ ] Response groups items by category (produce, dairy, protein, pantry, spice, etc.)

---

## W-7 — OpenAPI Specification

**Goal**: Complete the OpenAPI 3.x spec for all Phase 1 and Phase 2 services so the frontend developer has a stable contract to build against.

**Service**: `woodpantry-openapi`

**Deliverables**:
- [ ] `openapi.yaml` (or split per service) covering all endpoints for:
  - Ingredient Dictionary
  - Recipe Service
  - Pantry Service
  - Matching Service
  - Shopping List Service
- [ ] All request/response schemas defined with examples
- [ ] Error response schema standardized across all services
- [ ] Auth scheme documented (API key header)
- [ ] README with instructions for how to use the spec (e.g. Swagger UI, code generation)
  `woodpantry-openapi` currently contains docs only; no spec files exist yet.

**Acceptance Criteria**:
- [ ] Spec validates without errors against an OpenAPI 3.x linter
- [ ] Roommate can run Swagger UI against the spec and see all endpoints with examples
- [ ] All fields from the data models in the PRD are represented

---

## Phase 2 Complete

SMS pantry ingestion is live. Shopping lists work. The frontend developer has a spec to build against. Proceed to **RUN.md** to add the AI layer, receipt photo support, and the web UI.
