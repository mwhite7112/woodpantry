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
| SMS pantry ingest | Red | Twilio webhook, confirmation SMS, and `CONFIRM` flow are not implemented | `WALK.md`, `TODO.md` |
| Structured recipe create | Green | Recipe CRUD contract has been normalized to lowercase API DTOs and smoke-tested | `tests/smoke_recipes.sh` |
| Recipe free-text ingest | Green | Async queue-based ingest is implemented and locally verified | `WALK.md`, `TODO.md` |
| View recipe details | Green | `GET /recipes/{id}` contract regression was fixed and verified | `tests/smoke_recipes.sh`, `BUGS.md` |
| Match pantry to recipes | Green | Core deterministic matching works against pantry + recipe state | `tests/smoke_matching.sh`, `CRAWL.md` |
| Shopping list generation | Red | Service scaffold exists, but generation logic and endpoints are not complete | `WALK.md`, `TODO.md` |
| Frontend cook flow | Red | No deployed or usable UI yet | `RUN.md` |
| Frontend grocery flow | Red | Depends on shopping list + UI work that is not complete | `RUN.md` |
| Receipt photo ingest | Red | Phase 3 feature; not implemented | `RUN.md` |
| Meal planning | Red | Phase 3 service is not implemented | `RUN.md` |

## Phase Status

| Phase | Status | Notes |
|---|---|---|
| Phase 1: Core Loop | Yellow | Core features are working locally, but cluster ingress/metrics/dashboard work is still incomplete |
| Phase 2: Queue + Ingestion + Shopping | Yellow | RabbitMQ and ingestion core exist; Twilio and shopping list remain the major gaps |
| Phase 3: AI Layer + Frontend | Red | Intentionally deferred; no end-to-end user-facing Phase 3 flow exists yet |

## Service Status

| Service | Status | Notes |
|---|---|---|
| `woodpantry-ingredients` | Green | Core dictionary, resolve, merge, substitutes, and conversions are implemented |
| `woodpantry-recipes` | Green | Recipe CRUD and async ingest are working locally; ingest response contracts are not fully normalized yet |
| `woodpantry-pantry` | Green | Pantry CRUD and staged ingest are working locally; read-path name enrichment now depends on Dictionary availability |
| `woodpantry-matching` | Green | Phase 1 matching flow is working; Phase 2 cache invalidation and Phase 3 semantic ranking are still open |
| `woodpantry-ingestion` | Yellow | Core queue-based extraction works; Twilio path is still mostly stubbed |
| `woodpantry-shopping-list` | Red | Scaffold exists, but the service is not functionally complete |
| `woodpantry-openapi` | Red | Docs-only; spec not written |
| `woodpantry-meal-plan` | Red | Not started |
| `woodpantry-ui` | Red | Not started |

## Current Priorities

1. Finish Twilio SMS pantry ingest in `woodpantry-ingestion`
2. Build the actual shopping list generation flow in `woodpantry-shopping-list`
3. Verify and harden RabbitMQ publish/consume behavior and cluster event wiring
4. Write the OpenAPI spec once Phase 2 contracts are stable

## Recently Verified

- Recipe CRUD response contracts are now lowercase and smoke-test compatible
- Pantry list response contract now returns lowercase fields and `name`
- Root smoke suite has been hardened to catch JSON contract regressions explicitly
- `make dev-restart` and `make test-only` were run successfully on 2026-04-03

## Known Gaps

- Twilio webhook flow is still not implemented
- Shopping list service is still scaffold-only
- OpenAPI spec is still missing
- Cluster ingress, metrics scraping, and dashboard work are not fully complete for the whole system
- Some recipe ingest/job endpoints may still expose internal/sqlc-shaped payloads because CRUD endpoints were prioritized first

## Risks And Notes

- `GET /pantry` now enriches `name` using the Ingredient Dictionary. That keeps the API usable, but it adds read-path coupling that should be cached and documented.
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
