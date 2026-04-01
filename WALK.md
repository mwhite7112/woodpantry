# WALK — Phase 2: Ingestion Pipeline + Queue

**Phase Goal**: Remove all friction from pantry updates. Make the SMS flow work end-to-end. Introduce RabbitMQ as the event backbone. Add shopping list generation.

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
- [ ] RabbitMQ deployed to cluster via Helm chart or k8s manifests
- [ ] Persistent storage via Longhorn
- [ ] Management UI exposed via Traefik (internal only)
- [ ] Define exchange topology:
  - `woodpantry.topic` exchange (topic type)
  - Routing keys: `pantry.ingest.requested`, `pantry.updated`, `recipe.import.requested`, `recipe.imported`, `shopping_list.requested`
- [ ] RabbitMQ credentials in cluster secrets
- [ ] Document exchange + queue topology in this file and in `woodpantry-ingestion/CLAUDE.md`

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
- [ ] RabbitMQ management UI accessible
- [ ] Test publish/consume round-trip works from a local Go program
- [ ] No messages lost on service restart (durable queues)

---

## W-2 — Refactor Pantry Service: Publish Events

**Goal**: Pantry Service publishes `pantry.updated` after any stock change so downstream consumers (Matching Service cache, future notification service) can react.

**Service**: `woodpantry-pantry`

**Deliverables**:
- [ ] Add RabbitMQ publisher to Pantry Service (`internal/events/publisher.go`)
- [ ] Publish `pantry.updated` event after: item add, item update, item delete, ingest confirm, reset
- [ ] Event payload: `{ "timestamp": "...", "changed_item_ids": [...] }` (keep it minimal)
- [ ] Graceful handling if RabbitMQ is unavailable (log error, do not fail the HTTP request)
- [ ] `RABBITMQ_URL` env var, optional — if not set, skip publishing (preserves Phase 1 behaviour)

**Acceptance Criteria**:
- [ ] A pantry item update publishes a `pantry.updated` message observable in the management UI
- [ ] Service continues operating normally if RabbitMQ is down

---

## W-3 — Refactor Recipe Service: Async Import via Queue

**Goal**: Recipe import (ingest) flow becomes async. Submission publishes a `recipe.import.requested` event; the Ingestion Pipeline picks it up and publishes `recipe.imported` when done; Recipe Service subscribes and commits.

**Service**: `woodpantry-recipes`

**Deliverables**:
- [ ] Add RabbitMQ publisher: publish `recipe.import.requested` on `POST /recipes/ingest` instead of calling OpenAI API directly
- [ ] Add RabbitMQ subscriber: listen for `recipe.imported` events, commit the structured recipe payload to DB
- [ ] `POST /recipes/ingest/:job_id/confirm` flow updated to work with async job status
- [ ] Phase 1 direct OpenAI API call removed from Recipe Service (moved to Ingestion Pipeline)
- [ ] Job status polling still works via `GET /recipes/ingest/:job_id`

**Acceptance Criteria**:
- [ ] Submitting a recipe for import returns a job ID immediately
- [ ] Ingestion Pipeline processes the job asynchronously and Recipe Service commits on `recipe.imported`
- [ ] Staged review flow still works — user can still review and confirm before commit

---

## W-4 — Build Ingestion Pipeline: Core Service

**Goal**: Build the Ingestion Pipeline service. Phase 2 scope: SMS text list ingestion and free-text recipe import. No photo/OCR yet (Phase 3).

**Service**: `woodpantry-ingestion`

**Deliverables**:
- [ ] Service scaffolding: FastAPI app + uvicorn, health check, aio-pika RabbitMQ subscriber setup
- [ ] Subscribe to `pantry.ingest.requested`:
  - Extract structured ingredient list from free-text using OpenAI API
  - Call `/ingredients/resolve` for each item
  - POST staged items to Pantry Service
  - Publish result back or update job status
- [ ] Subscribe to `recipe.import.requested`:
  - Extract structured recipe JSON from free-text using OpenAI API
  - Call `/ingredients/resolve` for each recipe ingredient
  - Publish `recipe.imported` with structured payload
- [ ] OpenAI API client with structured extraction prompts for both pantry and recipe contexts (`gpt-5-mini` for cost efficiency)
- [ ] Per-job error handling: mark job as failed, preserve raw input for debugging
- [ ] `OPENAI_API_KEY`, `RABBITMQ_URL` env vars

**Acceptance Criteria**:
- [ ] Free-text pantry ingest via queue produces correct staged items in Pantry Service
- [ ] Free-text recipe import via queue produces a confirmed recipe in Recipe Service
- [ ] LLM failures mark the job as failed without crashing the service

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
- [ ] DB schema: `shopping_lists`, `shopping_list_items` tables (for persisting generated lists)
- [ ] `POST /shopping-list` — accept array of recipe IDs; fetch each recipe's ingredients from Recipe Service; aggregate quantities per ingredient; diff against Pantry Service current state; persist and return list
- [ ] `GET /shopping-list/:id` — retrieve a previously generated list
- [ ] Items grouped by ingredient category in response
- [ ] Quantity aggregation handles unit normalization (e.g. 500g + 250g = 750g) using unit conversion data from Dictionary
- [ ] HTTP clients for Recipe Service, Pantry Service, Ingredient Dictionary

**Acceptance Criteria**:
- [ ] Shopping list for 3 recipes correctly aggregates quantities across all recipes
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

**Acceptance Criteria**:
- [ ] Spec validates without errors against an OpenAPI 3.x linter
- [ ] Roommate can run Swagger UI against the spec and see all endpoints with examples
- [ ] All fields from the data models in the PRD are represented

---

## Phase 2 Complete

SMS pantry ingestion is live. Shopping lists work. The frontend developer has a spec to build against. Proceed to **RUN.md** to add the AI layer, receipt photo support, and the web UI.
