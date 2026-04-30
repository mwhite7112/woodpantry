# WoodPantry Status

Last updated: 2026-04-03

This file is the current-state dashboard for the project from a user-journey perspective.

Use it to answer:

- what a user can do right now
- what is partially working
- what is still missing
- what the current priorities are

Status meanings:

- `Green`: implemented and recently verified end-to-end
- `Yellow`: partially implemented, locally verified only in parts, or still missing important production-hardening work
- `Red`: not implemented, not usable, or intentionally deferred

## User Journeys

| Journey | Status | Current State | Evidence |
|---|---|---|---|
| Manually add pantry items | Green | Core pantry CRUD flow is working locally and contract-hardened | `tests/smoke_pantry.sh` |
| Free-text pantry ingest | Green | Staged ingest and confirm flow work through the Pantry Service | `tests/smoke_pantry_ingest.sh`, `CRAWL.md` |
| SMS pantry ingest | Yellow | Twilio webhook flow exists and deployment wiring/docs now cover local tunnel and cluster routing, but it still needs manual end-to-end verification with real credentials and DNS | `woodpantry-ingestion/README.md`, `WALK.md`, `TODO.md` |
| Structured recipe create | Green | Recipe CRUD contract has been normalized to lowercase API DTOs and smoke-tested | `tests/smoke_recipes.sh` |
| Recipe free-text ingest | Green | Async queue-based ingest is implemented; local queue publish/consume and staged job progression are smoke-covered, and separate broker-restart plus consumer-redelivery RabbitMQ proofs both passed locally on 2026-04-03 | `tests/smoke_recipes_ingest.sh`, `tests/smoke_rabbitmq.sh`, `tests/smoke_rabbitmq_restart.sh`, `tests/smoke_rabbitmq_redelivery.sh`, `WALK.md` |
| View recipe details | Green | `GET /recipes/{id}` contract regression was fixed and verified | `tests/smoke_recipes.sh`, `BUGS.md` |
| Match pantry to recipes | Green | Core deterministic matching works against pantry + recipe state | `tests/smoke_matching.sh`, `CRAWL.md` |
| Shopping list generation | Green | Shopping list create and fetch are smoke-verified against live recipe, pantry, and dictionary dependencies, including aggregation and pantry subtraction | `tests/smoke_shopping_list.sh`, `WALK.md` |
| Frontend cook flow | Red | No deployed or usable UI yet | `RUN.md` |
| Frontend grocery flow | Red | Depends on shopping list + UI work that is not complete | `RUN.md` |
| Receipt photo ingest | Red | Phase 3 feature; not implemented | `RUN.md` |
| Meal planning | Red | Phase 3 service is not implemented | `RUN.md` |

## Phase Status

| Phase | Status | Notes |
|---|---|---|
| Phase 1: Core Loop | Yellow | Core features are working locally, but cluster ingress/metrics/dashboard work is still incomplete |
| Phase 2: Queue + Ingestion + Shopping | Yellow | RabbitMQ wiring, broker-restart durability, and consumer redelivery after an unacked crash all passed locally on 2026-04-03; shopping-list generation is smoke-verified, while Twilio and real service restart/replay proof still remain open |
| Phase 3: AI Layer + Frontend | Red | Intentionally deferred; no end-to-end user-facing Phase 3 flow exists yet |

## Service Status

| Service | Status | Notes |
|---|---|---|
| `woodpantry-ingredients` | Green | Core dictionary, resolve, merge, substitutes, and conversions are implemented |
| `woodpantry-recipes` | Green | Recipe CRUD and async ingest are working locally; ingest response contracts are not fully normalized yet |
| `woodpantry-pantry` | Green | Pantry CRUD and staged ingest are working locally; read-path name enrichment now depends on Dictionary availability |
| `woodpantry-matching` | Green | Phase 1 matching flow is working; Phase 2 cache invalidation and Phase 3 semantic ranking are still open |
| `woodpantry-ingestion` | Yellow | Core queue-based extraction works and Twilio env/ingress wiring is in place; public DNS, secrets, and manual live verification still remain |
| `woodpantry-shopping-list` | Green | `POST /shopping-list` and `GET /shopping-list/{id}` are implemented and smoke-verified for aggregation plus pantry subtraction |
| `woodpantry-openapi` | Red | Docs-only; spec not written |
| `woodpantry-meal-plan` | Red | Not started |
| `woodpantry-ui` | Red | Not started |

## Current Priorities

1. Finish Twilio SMS pantry ingest in `woodpantry-ingestion`
2. Keep using the RabbitMQ restart/redelivery checks, then close the remaining real-consumer restart and downstream-consumer gaps
3. Finish shopping-list release wiring
4. Write the OpenAPI spec once Phase 2 contracts are stable

## Recently Verified

- Recipe CRUD response contracts are now lowercase and smoke-test compatible
- Pantry list response contract now returns lowercase fields and `name`
- Root smoke suite has been hardened to catch JSON contract regressions explicitly
- `make dev-restart` and `make wait-healthy` were run successfully on 2026-04-03
- `tests/smoke_rabbitmq.sh` passed on 2026-04-03, proving local broker publish/get and `pantry.updated` routing
- `make test-rabbitmq-restart` passed on 2026-04-03, proving that a durable queue plus a persistent message survived a targeted local RabbitMQ restart without resetting volumes
- `make test-rabbitmq-redelivery` passed on 2026-04-03, proving that an unacked message was requeued and redelivered with `redelivered = true` after a probe consumer process crashed before `ack`
- Recipe ingest queue flow was rechecked on 2026-04-03: `POST /recipes/ingest` produced a staged job and both RabbitMQ recipe queues showed matching publish/ack activity
- Shopping list generation is now root-smoke-covered via `tests/smoke_shopping_list.sh`, verifying persisted create/fetch plus a deterministic aggregation and pantry-delta fixture

## Known Gaps

- Twilio flow still needs a real-world manual verification pass against a tunnel and the cluster hostname
- Cluster Twilio ingress depends on real DNS and TLS for the public SMS host
- OpenAPI spec is still missing
- Cluster ingress, metrics scraping, and dashboard work are not fully complete for the whole system
- A real WoodPantry service container or pod restart has not yet been directly proven to reconnect, resume consuming, and safely replay in-flight messages
- Downstream service-specific replay behavior and handler idempotency are still not directly proven by a repo check
- Some recipe ingest/job endpoints may still expose internal/sqlc-shaped payloads because CRUD endpoints were prioritized first

## Risks And Notes

- `GET /pantry` now enriches `name` using the Ingredient Dictionary. That keeps the API usable, but it adds read-path coupling that should be cached and documented.
- Broker-restart durability has been verified for the local stack used on 2026-04-03 via `make test-rabbitmq-restart`; other environments still need the same check run locally.
- Consumer-side redelivery has been verified for the local stack used on 2026-04-03 via `make test-rabbitmq-redelivery`; this proof uses a temporary probe consumer rather than a real application worker.
- `BUGS.md` should remain limited to smoke-test-discovered regressions only.
- `TODO.md` is the backlog; this file is the current-state dashboard.

## Source Of Truth

Use these docs together:

- [`STATUS.md`](./STATUS.md): current product and journey status
- [`TODO.md`](./TODO.md): backlog and implementation work
- [`BUGS.md`](./BUGS.md): smoke-test-discovered regressions
- [`CRAWL.md`](./CRAWL.md): Phase 1 plan
- [`WALK.md`](./WALK.md): Phase 2 plan
- [`RUN.md`](./RUN.md): Phase 3 plan
- [`tests/SMOKE_TESTS.md`](./tests/SMOKE_TESTS.md): smoke suite structure and intent
