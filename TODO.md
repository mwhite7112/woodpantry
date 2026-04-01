# WoodPantry — Implementation TODO

Generated 2026-03-31. Organized by service for chunk-based delegation.

---

## Legend

- `[x]` — Done
- `[ ]` — Not started
- `[~]` — Partially done
- `DEP:` — Dependency (must be completed first)

---

## Infrastructure

### W-1 — RabbitMQ
- [x] RabbitMQ deployed to cluster
- [x] Persistent storage via Longhorn
- [x] Management UI exposed via Traefik
- [x] Exchange topology defined (`woodpantry.topic`, topic type, durable)
- [x] RabbitMQ credentials in cluster secrets
- [ ] Verify publish/consume round-trip from a local Go program
- [ ] Verify durable queues survive service restart

---

## woodpantry-ingredients

> Phase 1 service. ~95% complete.

### Bugs
- [x] Add HTTP handler: `GET /ingredients/{id}/substitutes` — sqlc query `ListSubstitutesByIngredient` exists but no handler exposes it
- [x] Add HTTP handler: `POST /ingredients/{id}/substitutes` — sqlc query `CreateSubstitute` exists but no handler exposes it
- [x] Add HTTP handler: `GET /ingredients/{id}/conversions` — sqlc query `ListUnitConversionsByIngredient` exists but no handler exposes it
- [x] Add HTTP handler: `POST /ingredients/{id}/conversions` — sqlc query `CreateUnitConversion` exists but no handler exposes it

### Notes
- These missing endpoints are consumed by the Matching Service (substitute lookups) and Shopping List Service (unit conversions). Both clients already handle 404/405 gracefully, but the data is inaccessible until handlers exist.
- `DEP: woodpantry-matching` substitute scoring relies on `GET /ingredients/{id}/substitutes` returning data.
- `DEP: woodpantry-shopping-list` unit normalization relies on `GET /ingredients/{id}/conversions` returning data.

---

## woodpantry-recipes

> Phase 1 service. ~95% complete. W-3 (async import) done.

### Bugs
- [x] Fix `ListRecipesByTag` SQL query — uses `WHERE $1 = ANY(tags)` (scalar comparison) instead of proper array-contains semantics (`WHERE tags @> $1`). Integration test `TestIntegration_ListByTag` is skipped with a TODO.
- [x] Regenerate sqlc after fixing the query
- [x] Unskip and verify the tag filter integration test

### W-3 — Async Import via Queue
- [x] RabbitMQ publisher: `recipe.import.requested` on `POST /recipes/ingest`
- [x] RabbitMQ subscriber: `recipe.imported` events update job status
- [x] Nop fallback when `RABBITMQ_URL` not set
- [x] Phase 1 direct OpenAI call removed (extraction moved to Ingestion Pipeline)

---

## woodpantry-pantry

> Phase 1 service. 100% complete. W-2 done.

### W-2 — Publish Events
- [x] RabbitMQ publisher for `pantry.updated`
- [x] Publishes after: item add, update, delete, ingest confirm, reset
- [x] Graceful handling if RabbitMQ unavailable
- [x] `RABBITMQ_URL` optional — skips publishing if not set

---

## woodpantry-matching

> Phase 1 service. 100% complete for Phase 1 scope.

### Phase 2 (future, not blocking)
- [ ] Subscribe to `pantry.updated` events for cache invalidation
- [ ] Add in-memory pantry cache with short TTL
- `DEP: W-2` (done) — Pantry Service must publish `pantry.updated` events.

### Phase 3 (deferred)
- [ ] Semantic re-ranking via embeddings
- [ ] `POST /matches/query` prompt processing (currently stubbed/ignored)

---

## woodpantry-ingestion

> Phase 2 Python service. Recipe extraction working. Pantry extraction and Twilio stubbed.

### W-4 — Core Service (~80% done)

#### Recipe import flow (done)
- [x] FastAPI + uvicorn scaffolding, `/healthz`
- [x] aio-pika RabbitMQ subscriber setup
- [x] Subscribe to `recipe.import.requested`
- [x] `extract_recipe()` LLM function with structured prompt
- [x] Dictionary client (`POST /ingredients/resolve`)
- [x] Publish `recipe.imported` with staged payload
- [x] Per-job error handling (publish `recipe.import.failed`)

#### Pantry ingest flow (done)
- [x] Implement `extract_pantry()` function in `app/llm/openai.py` — prompt already exists in `app/prompts/pantry.py`
- [x] Implement `handle_pantry_ingest()` worker in `app/workers/pantry_ingest.py`
- [x] Wire `pantry.ingest.requested` consumer in `app/main.py`
- [x] Implement pantry HTTP client in `app/clients/pantry.py` — calls Pantry Service staging endpoint
- [x] Add `PANTRY_URL` env var to `kubernetes/deployment.yaml`
- [x] `DEP: Pantry Service staging contract` — added `POST /pantry/ingest/{job_id}/stage` endpoint to Pantry Service

#### Tests (not done)
- [ ] Unit tests for `extract_recipe()` (mock OpenAI, verify Pydantic validation)
- [ ] Unit tests for `extract_pantry()` once implemented
- [ ] Unit tests for recipe_ingest worker (mock LLM + publisher)
- [ ] Unit tests for dictionary client
- [ ] Integration test for RabbitMQ publish/consume round-trip

### W-5 — Twilio SMS (~5% done)

- [x] `JobRegistry` class in `app/workers/job_registry.py` (in-memory phone-to-job map with TTL)
- [x] Twilio env vars defined in `app/config.py` (optional)
- [ ] Implement `POST /twilio/inbound` webhook handler in `app/api/twilio.py`
- [ ] Twilio signature validation (reject invalid with 403)
- [ ] Parse inbound SMS body and `From` number
- [ ] On text message: publish `pantry.ingest.requested` with raw text
- [ ] After staged items created: send reply SMS via Twilio REST API
- [ ] Handle `CONFIRM` reply: trigger confirm on most recent pending job for that phone number
- [ ] Add Twilio secrets to `kubernetes/deployment.yaml`
- [ ] Add Traefik IngressRoute for public webhook URL
- `DEP: W-4 pantry ingest flow` — the Twilio handler publishes `pantry.ingest.requested`, which the pantry ingest worker must consume.

---

## woodpantry-shopping-list

> Phase 2 service. 0% implemented. CLAUDE.md and README.md spec exist.

### W-6 — Full Service Build

#### Scaffolding
- [ ] `go.mod` + `go.sum` — module `github.com/mwhite7112/woodpantry-shopping-list`
- [ ] `cmd/shopping-list/main.go` — entrypoint with env var parsing
- [ ] `Makefile` — test, test-integration, sqlc, generate-mocks targets
- [ ] `Dockerfile` — multi-stage Go build, distroless base
- [ ] `.mockery.yaml`

#### Database
- [ ] Migration: `shopping_lists` table (id, created_at, recipe_ids)
- [ ] Migration: `shopping_list_items` table (id, list_id, ingredient_id, name, quantity, unit, category, in_pantry_qty, needed_qty)
- [ ] `sqlc.yaml` + queries for CRUD
- [ ] Generate sqlc code

#### HTTP Clients
- [ ] Recipe Service client — `GET /recipes/{id}` to fetch ingredient lists
- [ ] Pantry Service client — `GET /pantry` to fetch current stock
- [ ] Dictionary client — `GET /ingredients/{id}/conversions` for unit normalization
- `DEP: woodpantry-ingredients` must expose `GET /ingredients/{id}/conversions` endpoint (currently missing handler).

#### Service Logic
- [ ] Generation algorithm: fetch recipes -> aggregate ingredients -> normalize units -> diff against pantry -> group by category
- [ ] Quantity aggregation with unit conversion (e.g. 500g + 250g = 750g)
- [ ] Delta calculation: needed_qty = recipe_qty - pantry_qty (floor at 0)
- [ ] Category grouping (produce, dairy, protein, pantry, spice, liquid, other)

#### API Handlers
- [ ] `GET /healthz`
- [ ] `POST /shopping-list` — accept recipe IDs, generate and persist list
- [ ] `GET /shopping-list/{id}` — retrieve previously generated list

#### Kubernetes
- [ ] `kubernetes/deployment.yaml` with env vars (PORT, DB_URL, RECIPE_URL, PANTRY_URL, DICTIONARY_URL)
- [ ] `kubernetes/service.yaml`
- [ ] `kubernetes/kustomization.yaml`

#### Tests
- [ ] Unit tests for generation algorithm (mock clients)
- [ ] Unit tests for unit normalization logic
- [ ] Integration tests with testcontainers-go
- [ ] Handler tests with httptest

#### Dependencies
- `DEP: woodpantry-recipes` must be deployed (fetches recipe ingredients)
- `DEP: woodpantry-pantry` must be deployed (fetches current stock)
- `DEP: woodpantry-ingredients` unit conversion endpoint must exist for proper normalization

---

## woodpantry-openapi

> Phase 2 deliverable. 0% implemented. CLAUDE.md and README.md outline exist.

### W-7 — OpenAPI Specification

- [ ] Create `openapi.yaml` root file (OpenAPI 3.1, info, servers, security schemes)
- [ ] Auth scheme: `X-API-Key` header
- [ ] Error response schema (code, message, request_id)

#### Per-Service Path Definitions
- [ ] Ingredient Dictionary: `/ingredients`, `/ingredients/{id}`, `/ingredients/resolve`, `/ingredients/merge`, `/ingredients/{id}/substitutes`, `/ingredients/{id}/conversions`
- [ ] Recipe Service: `/recipes`, `/recipes/{id}`, `/recipes/ingest`, `/recipes/ingest/{job_id}`, `/recipes/ingest/{job_id}/confirm`
- [ ] Pantry Service: `/pantry`, `/pantry/items`, `/pantry/items/{id}`, `/pantry/ingest`, `/pantry/ingest/{job_id}`, `/pantry/ingest/{job_id}/confirm`, `/pantry/reset`
- [ ] Matching Service: `/matches`, `/matches/query`
- [ ] Shopping List Service: `/shopping-list`, `/shopping-list/{id}`

#### Component Schemas
- [ ] Ingredient, ResolveRequest, ResolveResponse, MergeRequest
- [ ] Recipe, RecipeStep, RecipeIngredient, IngestRequest, IngestJob
- [ ] PantryItem, IngestRequest, StagedItem
- [ ] MatchResult, MatchQuery
- [ ] ShoppingList, ShoppingListItem
- [ ] ErrorResponse

#### Validation & Docs
- [ ] Validate against OpenAPI 3.x linter (no errors)
- [ ] Add request/response examples for all endpoints
- [ ] README with instructions for Swagger UI / code generation
- `DEP: All Phase 1 + Phase 2 service APIs must be finalized` — spec should reflect actual implemented endpoints. Best done last or iteratively.

---

## Phase 3 (Not Started — Correctly Deferred)

### woodpantry-meal-plan
- [ ] Entire service (spec exists in CLAUDE.md)

### woodpantry-ui
- [ ] Entire frontend (spec exists in CLAUDE.md, tech stack TBD by frontend developer)

### woodpantry-recipes — Semantic Search
- [ ] pgvector extension + embedding column migration
- [ ] Embedding generation via OpenAI `text-embedding-3-small`
- [ ] `POST /recipes/search` endpoint

### woodpantry-matching — Semantic Re-ranking
- [ ] OpenAI embedding integration
- [ ] Cosine similarity scoring
- [ ] `POST /matches/query` prompt processing (currently stubbed)

---

## Suggested Execution Order

Respects dependency chains. Items at the same level can run in parallel.

```
1. [x] Bug fixes (parallel, no deps)
   ├── woodpantry-ingredients: add substitute + conversion HTTP handlers
   └── woodpantry-recipes: fix ListRecipesByTag SQL query

2. W-4 pantry ingest (depends on #1 for full flow, but can start immediately)
   └── woodpantry-ingestion: extract_pantry(), pantry worker, wire consumer

3. W-5 Twilio SMS (depends on W-4)
   └── woodpantry-ingestion: webhook handler, signature validation, SMS reply, CONFIRM flow

4. W-6 Shopping List Service (depends on #1 for unit conversions)
   └── woodpantry-shopping-list: full greenfield build

5. W-7 OpenAPI Spec (best done last, reflects final API surface)
   └── woodpantry-openapi: openapi.yaml + schemas + examples + validation
```
