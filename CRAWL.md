# CRAWL — Phase 1: The Core Loop

**Phase Goal**: One complete, useful vertical slice deployed to the cluster. Prove the core value prop — your own recipes, your pantry, real matches. No queue, no ingestion pipeline, no SMS. Just the four core services wired together over direct HTTP.

**Exit Criteria**:
- You can manually add pantry items via API
- You can enter your own recipes via free-text LLM ingest
- You can query what you can make right now
- All four services are deployed to the cluster and reachable via Traefik
- Metrics flowing to Grafana

---

## C-1 — Project Scaffolding

**Goal**: Establish the repo structure, Go module layout, and shared tooling conventions for the four Phase 1 services before writing any business logic.

**Services**: All Phase 1 services (ingredients, recipes, pantry, matching)

**Deliverables**:
- [ ] Initialize `go.mod` in each of the four service repos
- [ ] Create `cmd/<service>/main.go` entrypoint with a minimal chi router and health check (`GET /healthz`)
- [ ] Set up `sqlc.yaml` and `internal/db/` structure in ingredients, recipes, pantry
- [ ] Create `Dockerfile` for each service (multi-stage Go build)
- [ ] Create `kubernetes/` directory with skeleton Deployment + Service manifests for each
- [ ] Document shared environment variable conventions (DB_URL, PORT, LOG_LEVEL) in root CLAUDE.md

**Acceptance Criteria**:
- [ ] Each service builds cleanly with `go build ./...`
- [ ] Each service's Docker image builds and starts, returning 200 on `/healthz`
- [ ] `sqlc generate` runs without error on each service (even with no queries yet)

---

## C-2 — Ingredient Dictionary: Schema, CRUD, Resolve

**Goal**: Build the foundational ingredient dedup service. This is the critical dependency for all other ingest flows — nothing else can be built until resolve works.

**Service**: `woodpantry-ingredients`

**Deliverables**:
- [ ] DB schema: `ingredients`, `unit_conversions`, `ingredient_substitutes` tables
- [ ] Migrations using golang-migrate or raw SQL files
- [ ] sqlc queries for full CRUD on ingredients
- [ ] `POST /ingredients/resolve` — fuzzy match against existing names and aliases, return best match with confidence score. If below threshold, auto-create and return new entry.
- [ ] `GET /ingredients` — list all ingredients
- [ ] `POST /ingredients` — manually create
- [ ] `GET /ingredients/:id` — fetch by ID
- [ ] `PUT /ingredients/:id` — update (primary use: add aliases)
- [ ] `POST /ingredients/merge` — merge two entries, move references, add losing name as alias on winner
- [ ] Fuzzy matching implementation (e.g. trigram similarity or Levenshtein via a Go library)
- [ ] Configurable confidence threshold via env var (`RESOLVE_THRESHOLD`, default 0.8)

**Acceptance Criteria**:
- [ ] Resolving "garlic clove" when "garlic" exists returns the existing entry above threshold
- [ ] Resolving a completely novel ingredient auto-creates and returns the new entry
- [ ] Concurrent resolve calls for the same new ingredient do not create duplicates (upsert on normalized name)
- [ ] Merge correctly moves all alias references and does not orphan data

---

## C-3 — Recipe Service: Schema, CRUD, Free-Text Ingest

**Goal**: Build the recipe corpus. Support hand-crafted entry via free-text LLM extraction with staged commit. Each ingest seeds the Ingredient Dictionary organically.

**Service**: `woodpantry-recipes`

**Deliverables**:
- [ ] DB schema: `recipes`, `recipe_steps`, `recipe_ingredients` tables
- [ ] sqlc queries for full CRUD
- [ ] `GET /recipes` — list with filters (tags, cook_time_max, title search)
- [ ] `POST /recipes` — create a structured recipe directly (JSON body)
- [ ] `GET /recipes/:id` — full recipe detail
- [ ] `PUT /recipes/:id` — update
- [ ] `DELETE /recipes/:id` — delete
- [ ] `POST /recipes/ingest` — accept free-text body, call OpenAI API to extract structured recipe JSON, persist as staged `IngestionJob`, return job ID
- [ ] `GET /recipes/ingest/:job_id` — check status and retrieve staged recipe for review
- [ ] `POST /recipes/ingest/:job_id/confirm` — commit staged recipe; call `/ingredients/resolve` for each ingredient before committing
- [ ] OpenAI API client with structured extraction prompt (`gpt-5-mini` for cost efficiency)

**Acceptance Criteria**:
- [ ] Pasting a recipe written in natural note-taking style produces a parseable staged result
- [ ] Each ingredient in the staged recipe is resolved against the Dictionary before commit
- [ ] Confirming a staged recipe persists it with correct `ingredient_id` foreign keys
- [ ] Enter 15–20 personal recipes via this flow to seed the corpus

---

## C-4 — Pantry Service: Schema, CRUD, Manual Ingest

**Goal**: Track current pantry state. Support manual item entry and a one-shot text blob ingest to backfill what's already in the fridge and pantry. This simultaneously seeds the Ingredient Dictionary with pantry vocabulary.

**Service**: `woodpantry-pantry`

**Deliverables**:
- [ ] DB schema: `pantry_items`, `ingestion_jobs`, `staged_items` tables
- [ ] sqlc queries for CRUD
- [ ] `GET /pantry` — current pantry state, all items with quantities
- [ ] `POST /pantry/items` — manually add or update a single pantry item; calls `/ingredients/resolve`
- [ ] `DELETE /pantry/items/:id` — remove item
- [ ] `POST /pantry/ingest` — accept free text blob, call OpenAI API for structured extraction, persist staged job
- [ ] `GET /pantry/ingest/:job_id` — status check and staged item list
- [ ] `POST /pantry/ingest/:job_id/confirm` — commit staged items to pantry, calling `/ingredients/resolve` for each
- [ ] `DELETE /pantry/reset` — clear all pantry items
- [ ] Quantity tracking with unit stored per item

**Acceptance Criteria**:
- [ ] Submitting a free-text grocery list ("2 lbs chicken breast, 1 head garlic, heavy cream") produces correctly staged items
- [ ] Confirming a staged job resolves all ingredients and persists with canonical IDs
- [ ] Manual item add works correctly for single items
- [ ] Initial pantry backfill via single text blob ingest succeeds end-to-end

---

## C-5 — Matching Service: Deterministic Coverage Scoring

**Goal**: Answer "what can I make right now?" by scoring recipes against current pantry state. Stateless — no DB, reads live from Pantry and Recipe services.

**Service**: `woodpantry-matching`

**Deliverables**:
- [ ] `GET /matches` — fetch pantry state from Pantry Service, fetch all recipes from Recipe Service, score each recipe by ingredient coverage, return ranked list
- [ ] Coverage score = (matched required ingredients) / (total required ingredients)
- [ ] Query params: `allow_subs=true` (use substitutes from Dictionary), `max_missing=N` (include recipes missing at most N ingredients)
- [ ] Response includes: recipe card, coverage %, list of missing ingredients if any, prep + cook time
- [ ] HTTP clients for Pantry Service, Recipe Service, Ingredient Dictionary (for substitutes)
- [ ] `POST /matches/query` stub — accept body with `prompt` and `pantry_constrained` flag; Phase 1 implementation ignores the prompt and runs deterministic scoring only. Semantic re-ranking added in Phase 3.

**Acceptance Criteria**:
- [ ] A recipe where you have all ingredients scores 100% and appears first
- [ ] `max_missing=2` correctly includes recipes where you are short 1 or 2 ingredients
- [ ] `allow_subs=true` correctly uses substitute ingredient data from the Dictionary
- [ ] Response time is acceptable with 20–50 recipes (no caching needed yet)

---

## C-6 — Deploy Phase 1 Services to Cluster

**Goal**: All four Phase 1 services running on the k8s homelab, reachable via Traefik, with metrics flowing to Grafana.

**Services**: ingredients, recipes, pantry, matching

**Deliverables**:
- [ ] PostgreSQL instance(s) provisioned on cluster (one DB per service, or one PG instance with separate databases)
- [ ] Kubernetes Deployments, Services, and ConfigMaps for each service
- [ ] Traefik IngressRoutes for each service (subdomain or path-based)
- [ ] Secrets management for DB credentials and LLM API keys
- [ ] ServiceMonitor or scrape config for Victoria Metrics
- [ ] Grafana dashboard with at minimum: request rate, error rate, latency per service
- [ ] `OPENAI_API_KEY` available as a cluster secret, injected into Recipe and Pantry service deployments
- [ ] Smoke test: end-to-end flow works against cluster (add pantry item → ingest recipe → query matches)

**Acceptance Criteria**:
- [ ] All four services pass `/healthz` checks in cluster
- [ ] Matching Service returns real results using live pantry and recipe data
- [ ] Metrics visible in Grafana for all four services
- [ ] No hardcoded secrets in k8s manifests or committed to git

---

## Phase 1 Complete

When all C-1 through C-6 tickets are done, WoodPantry is in daily use as a functional tool. Proceed to **WALK.md** to introduce the ingestion pipeline and remove friction from pantry updates.
