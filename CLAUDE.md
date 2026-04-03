# WoodPantry — Monorepo Root

WoodPantry is a self-hosted, microservices-based pantry and recipe tracking application with AI-assisted grocery ingestion. Deployed on a GitOps Kubernetes homelab cluster.

## Project Layout

```
woodpantry/                    ← you are here (documentation + phase planning root)
├── local/                     ← Docker Compose stack + env config
├── tests/                     ← Cross-service smoke tests (see tests/SMOKE_TESTS.md)
woodpantry-ingredients/        ← Ingredient Dictionary Service
woodpantry-recipes/            ← Recipe Service
woodpantry-pantry/             ← Pantry Service
woodpantry-ingestion/          ← Ingestion Pipeline (Phase 2+)
woodpantry-matching/           ← Matching Service
woodpantry-shopping-list/      ← Shopping List Service (Phase 2+)
woodpantry-meal-plan/          ← Meal Plan Service (Phase 3+)
woodpantry-openapi/            ← Central OpenAPI 3.x specification
woodpantry-ui/                 ← Web frontend (Phase 3, roommate-owned)
```

## Universal Conventions (apply to all Go services)

- Language: **Go** — all backend services except Ingestion Pipeline (see exception below)
- HTTP router: **chi**
- DB access: **sqlc** — write raw SQL, generate type-safe Go. Never use an ORM.
- Database: **PostgreSQL** — one database per service, no cross-service DB queries
- Events: **RabbitMQ** with `amqp091-go` (Go) / `aio-pika` (Python) — async flows only
- LLM: **OpenAI API** for all LLM tasks — `gpt-5-mini` for text extraction, `gpt-5` for vision/OCR (Phase 3), `text-embedding-3-small` for embeddings (Phase 3). One API key covers everything.
- Deployment: **Kubernetes** via GitOps — each service has a `Dockerfile` at the root and a `kubernetes/` directory with k8s manifests
- Observability: **Victoria Metrics + Grafana** — expose `/metrics` on all services
- Ingress: **Traefik**
- Storage: **Longhorn**

## Exception: Ingestion Pipeline

`woodpantry-ingestion` is written in **Python**, not Go. It is purely I/O bound (LLM API calls, HTTP calls to other services, RabbitMQ) with no CPU-intensive work, and the Python ecosystem (OpenAI SDK, Twilio helper library, aio-pika) makes this the natural fit. See `woodpantry-ingestion/CLAUDE.md` for its specific conventions.

## Architecture Rules

1. Each service owns exactly one Postgres database. No service reads another service's DB.
2. Services communicate via **HTTP** for synchronous query flows and **RabbitMQ** for async flows.
3. The Ingredient Dictionary is the **canonical shared layer** — all services that handle ingredients call `/ingredients/resolve` before creating or linking any ingredient. They do not replicate Dictionary data.
4. The Ingestion Pipeline is the **only** service that handles raw/dirty input (OCR, free text, receipt photos). All other services receive clean, normalized data.
5. All ingest flows use a **staged commit pattern**: raw input → LLM extraction → staged result (for review) → confirm → commit.

## Go Module Naming

Each Go service lives in its own directory and is its own Go module:
`module github.com/<owner>/woodpantry-<service>`

## Directory Layout (Go services)

```
woodpantry-<service>/
├── cmd/<service>/main.go      ← entrypoint
├── internal/
│   ├── api/                   ← HTTP handlers
│   ├── db/                    ← sqlc-generated code + migrations
│   │   ├── migrations/
│   │   ├── queries/           ← .sql query files (sqlc input)
│   │   └── sqlc.yaml
│   ├── mocks/                 ← mockery-generated mocks
│   ├── service/               ← business logic
│   ├── testutil/              ← test helpers (integration tests)
│   └── events/                ← RabbitMQ publisher/subscriber (if applicable)
├── kubernetes/                ← k8s manifests
├── .mockery.yaml              ← mockery config
├── Makefile
├── Dockerfile
├── go.mod
├── go.sum
├── README.md
└── CLAUDE.md
```

## Directory Layout (woodpantry-ingestion — Python)

```
woodpantry-ingestion/
├── app/
│   ├── main.py                ← FastAPI app + worker entrypoint
│   ├── api/                   ← HTTP handlers (Twilio webhook)
│   ├── workers/               ← RabbitMQ consumers
│   ├── llm/                   ← OpenAI client
│   ├── clients/               ← httpx clients for other services
│   ├── events/                ← RabbitMQ publisher/subscriber
│   └── prompts/               ← extraction prompt templates
├── kubernetes/
├── Dockerfile
├── pyproject.toml
├── README.md
└── CLAUDE.md
```

## Phase Reference

- **CRAWL.md** — Phase 1: Core loop. Four services, direct HTTP, no queue.
- **WALK.md** — Phase 2: Ingestion pipeline + RabbitMQ + Shopping List.
- **RUN.md** — Phase 3: AI layer, receipt photos, pgvector, frontend.

## Shared Environment Variables (all Go services)

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | HTTP listen port |
| `DB_URL` | required | PostgreSQL connection string (`postgres://user:pass@host/dbname?sslmode=disable`) |
| `LOG_LEVEL` | `info` | Logging verbosity (`debug`, `info`, `warn`, `error`) |

Each service may define additional env vars. See the service's own `CLAUDE.md` for extras (e.g. `RESOLVE_THRESHOLD` on ingredients, `OPENAI_API_KEY` on recipes and pantry).

## Testing Conventions

- **Assertions**: `testify` (`assert` for soft checks, `require` for fatal checks)
- **Mocks**: `mockery` v2 for auto-generated mocks from interfaces. Each service has a `.mockery.yaml` config.
- **Integration tests**: `testcontainers-go` for real Postgres containers. Build-tagged with `//go:build integration`. Require Docker.
- **Build tags**: Integration tests use `//go:build integration`. Unit tests have no build tag.
- **Test pattern**: Table-driven tests with `t.Parallel()` where safe.
- **sqlc interfaces**: All DB services use `emit_interface: true` in sqlc.yaml, generating a `Querier` interface for mockable DB layers.
- **Service interfaces**: External dependencies (LLM, HTTP clients, dictionary) are abstracted behind interfaces for dependency injection in tests.
- **Coverage targets**: Pure functions 95%+, service logic 80%+, handlers 75%+, overall per service 75%+.

### Running Tests

Each service has its own Makefile. Run from the service directory:

```bash
cd woodpantry-<service>
make test                # Unit tests
make test-integration    # Integration tests (requires Docker/Podman)
make test-all            # Unit + integration tests
make test-coverage       # Coverage report
make test-coverage-html  # HTML coverage report
make generate-mocks      # Regenerate mocks
make sqlc                # Regenerate sqlc (DB services only)
```

## Smoke Tests (Cross-Service)

Smoke tests live in `tests/` and run against the full local Podman Compose stack. They test HTTP contracts and cross-service flows, not internal logic.

See `tests/SMOKE_TESTS.md` for the full guide on writing and organizing tests.

### Quick Reference

```bash
make dev           # Start local stack (rebuilds images)
make dev-down      # Tear down stack
make test          # Start stack → run all smoke tests → tear down
make test-only     # Run smoke tests against already-running stack
make test-rabbitmq-restart  # Opt-in broker restart durability verification
```

### Bug Tracking

When a smoke test reveals a cross-service bug, document it in `BUGS.md` with symptom, root cause, required fix, and a link back to the smoke test that catches it. See `tests/SMOKE_TESTS.md` for the exact format.

## What to Avoid

- Do not add ORM dependencies (gorm, ent, etc.) — use sqlc.
- Do not query another service's database directly.
- Do not pre-seed the Ingredient Dictionary from any external dataset.
- Do not add RabbitMQ in Phase 1 — services use direct HTTP until Phase 2.
- Do not build Ingestion Pipeline features into core services — keep dirty I/O isolated.
