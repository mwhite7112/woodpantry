# RUN — Phase 3: AI Layer + Photo Ingestion + Frontend

**Phase Goal**: The full experience. Vibe-based recipe search, receipt photo ingestion, polished web UI, and meal planning. This is the phase where WoodPantry becomes something you use every day without thinking about it.

**Status (2026-03-31)**:
- [ ] No Phase 3 feature in this file is implemented end-to-end yet.
- [ ] `woodpantry-meal-plan`, `woodpantry-openapi`, and `woodpantry-ui` are still placeholder/docs-only directories.
- [ ] The current codebase has no `POST /recipes/search`, no semantic re-ranking in matching, no Twilio MMS receipt flow, and no deployed frontend.

**Notes**:
- Some groundwork exists for later work: the ingestion service already has OpenAI client code and a `VISION_MODEL` setting, and the recipe/matching docs already describe future semantic search.
- Those hooks are not wired into live Phase 3 behavior yet, so all RUN tickets remain open.

**Exit Criteria**:
- You can photograph a grocery receipt and have items land in your pantry after confirming
- `POST /matches/query` re-ranks results using semantic similarity against a natural language prompt
- The web frontend (Cook view + Grocery view) is deployed and usable
- Meal Plan Service is running

**Prerequisite**: All WALK tickets complete and Phase 2 stable in cluster.

---

## R-1 — pgvector Embeddings for Recipes

**Goal**: Generate and store vector embeddings for every recipe so semantic similarity search can re-rank match results by vibe.

**Service**: `woodpantry-recipes`

**Deliverables**:
- [ ] Add `pgvector` extension to `recipe_db`
- [ ] Add `embedding vector(1536)` column to `recipes` table (or appropriate dimension for chosen model)
- [ ] Background embedding job: subscribes to `recipe.imported` event, generates embedding via OpenAI API (`text-embedding-3-small`), stores in DB
- [ ] Backfill: one-time job to generate embeddings for all existing recipes
- [ ] `POST /recipes/search` endpoint: accept natural language prompt, generate query embedding, return recipes ranked by cosine similarity
- [ ] Embedding model configurable via env var (`EMBED_MODEL`, default `text-embedding-3-small`)
- [ ] Embedding generation happens asynchronously — recipe is usable before embedding is ready

**Acceptance Criteria**:
- [ ] Searching "something cozy and Italian" returns Italian recipes ranked above unrelated ones
- [ ] Embedding is generated within a few seconds of recipe import confirmation
- [ ] Backfill job completes without errors on 15–20 existing recipes

---

## R-2 — Matching Service: Semantic Re-ranking

**Goal**: `POST /matches/query` now actually uses the natural language prompt. Run deterministic pantry coverage scoring first to get the candidate set, then re-rank using semantic similarity.

**Service**: `woodpantry-matching`

**Deliverables**:
- [ ] Full `POST /matches/query` implementation:
  1. Fetch current pantry state from Pantry Service
  2. Run deterministic ingredient coverage scoring (existing logic from C-5)
  3. Filter candidates by `pantry_constrained` and `max_missing` params
  4. Generate embedding for the user's prompt
  5. Score each candidate recipe by cosine similarity against recipe embeddings
  6. Combine pantry coverage score and semantic score into a final ranking
  7. Return ranked list with recipe card, coverage %, missing ingredients, cook time
- [ ] Embedding generation via OpenAI API (same model as Recipe Service uses — `text-embedding-3-small`)
- [ ] Tunable weighting between coverage score and semantic score via env var (`SEMANTIC_WEIGHT`, default 0.4)

**Acceptance Criteria**:
- [ ] Prompt "something spicy and quick, maybe Asian" surfaces appropriate recipes above others with similar pantry coverage
- [ ] `pantry_constrained: true` never returns a recipe you cannot make (0 missing required ingredients) unless `max_missing` is set
- [ ] Response time remains acceptable (< 2s for 50 recipes)

---

## R-3 — Vision LLM: Receipt Photo OCR

**Goal**: Add MMS (photo message) handling to the Twilio webhook. User photographs a grocery receipt and the pipeline extracts items via a vision-capable LLM.

**Service**: `woodpantry-ingestion`

**Deliverables**:
- [ ] Detect inbound MMS in Twilio webhook handler (presence of `MediaUrl0` parameter)
- [ ] Download attached image from Twilio media URL
- [ ] Send image to OpenAI API (`gpt-5` with vision) with receipt OCR extraction prompt
- [ ] Parse extracted item list and continue through existing staged ingest flow
- [ ] Handle multiple media attachments (user sends multiple photos)
- [ ] Store raw image path in `IngestionJob.raw_input` for debugging
- [ ] Vision model configurable via env var (`VISION_MODEL`, default `gpt-5`)

**Acceptance Criteria**:
- [ ] Photographing a Trader Joe's or similar receipt produces a correctly staged item list
- [ ] Quantities and units are extracted correctly for clearly legible items
- [ ] Illegible or ambiguous items are flagged with low confidence for review
- [ ] Model version configurable via env var so it can be updated without a code change

---

## R-4 — Web Frontend: Cook View

**Goal**: The primary daily query surface. User types a vibe prompt, gets a ranked list of what they can cook tonight.

**Service**: `woodpantry-ui`

**Deliverables** (roommate-owned, frontend developer):
- [ ] Cook view: natural language prompt input + submit
- [ ] Calls `POST /matches/query` with `pantry_constrained: true`
- [ ] Displays ranked recipe cards: title, coverage %, cook time, missing ingredients chip list
- [ ] Toggle: "allow substitutions" → re-queries with `allow_subs=true`
- [ ] Toggle: "I can shop for a few things" → slider for `max_missing` (0–5)
- [ ] Recipe detail view: full ingredient list, steps, source
- [ ] Responsive, works on mobile browser (complement to SMS flow)

**Acceptance Criteria**:
- [ ] End-to-end: typing "something warming and filling" returns a useful ranked list
- [ ] Coverage % and missing ingredients are clearly communicated per recipe card
- [ ] Works without a prompt (empty prompt = pure pantry coverage ranking)

---

## R-5 — Web Frontend: Grocery View

**Goal**: Weekly planning flow. Select recipes, generate a shopping list, take it to the store.

**Service**: `woodpantry-ui`

**Deliverables** (roommate-owned, frontend developer):
- [ ] Recipe browser/search (calls `GET /recipes` with filters)
- [ ] Multi-select: add recipes to "this week's meals" basket
- [ ] Generate shopping list: calls `POST /shopping-list` with selected recipe IDs
- [ ] Display shopping list grouped by category (produce, dairy, protein, pantry, spice)
- [ ] Each item shows: ingredient name, quantity needed, unit
- [ ] Items already in pantry at sufficient quantity shown as greyed-out / "already have"
- [ ] Shareable list or printable view

**Acceptance Criteria**:
- [ ] Selecting 4 recipes and generating a list produces a correct, deduplicated, categorized list
- [ ] Items partially in pantry show the correct delta quantity
- [ ] List is usable on a phone screen at a grocery store

---

## R-6 — Meal Plan Service

**Goal**: Manage a weekly meal plan (recipe X on day Y). Acts as the structured input to Shopping List Service for the Grocery View's "plan the week" flow.

**Service**: `woodpantry-meal-plan`

**Deliverables**:
- [ ] DB schema: `meal_plans`, `meal_plan_entries` tables
- [ ] `POST /meal-plans` — create a meal plan (name + date range)
- [ ] `PUT /meal-plans/:id/entries` — assign recipes to days
- [ ] `GET /meal-plans/:id` — get full meal plan with recipes per day
- [ ] `DELETE /meal-plans/:id` — delete plan
- [ ] Integration with Shopping List Service: `POST /shopping-list` accepts a `meal_plan_id` in addition to explicit recipe IDs
- [ ] Frontend integration: Grocery View can load from an active meal plan instead of manual recipe selection

**Acceptance Criteria**:
- [ ] Creating a 5-day meal plan and generating a shopping list from it produces the correct aggregated list
- [ ] Recipe assignments to days persist correctly

---

## R-7 — Web Recipe URL Import

**Goal**: User pastes a URL to a recipe on any cooking site; the system fetches, extracts, and imports it.

**Service**: `woodpantry-ingestion` + `woodpantry-recipes`

**Deliverables**:
- [ ] URL ingest path in `POST /recipes/ingest`: detect if body is a URL
- [ ] Ingestion Pipeline fetches URL content (HTTP GET with browser-like headers)
- [ ] Send fetched HTML to LLM with structured extraction prompt (title, ingredients, steps)
- [ ] Continue through existing staged import flow (resolve ingredients, staged review, confirm)
- [ ] Handle common failure cases: paywalls, JS-rendered pages (log and fail gracefully)
- [ ] Respect `robots.txt` for fetched URLs

**Acceptance Criteria**:
- [ ] Pasting a URL to a recipe on a major cooking site (NYT Cooking, Serious Eats, etc.) produces a usable staged recipe
- [ ] Ingredient resolution against Dictionary works the same as free-text import
- [ ] Paywalled or inaccessible URLs fail gracefully with a clear error message

---

## Phase 3 Complete

WoodPantry is a real product used every week. The SMS → pantry → recipe → match → grocery loop is fully realized with AI at every ingest step and semantic search surfacing what you actually want to cook.
