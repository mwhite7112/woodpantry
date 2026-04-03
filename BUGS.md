# WoodPantry — Integration Bug Tracker

## [2026-03-31] Matching service fails to unmarshal Pantry response

- **Symptom**: `GET /matches` returns `502 Bad Gateway`.
- **Error**: `scoring failed: fetch pantry: decode response: json: cannot unmarshal object into Go value of type []clients.PantryItem`
- **Root Cause**: `woodpantry-pantry` returns a JSON object with an `"items"` key (`{"items": [...]}`), but `woodpantry-matching`'s HTTP client expects a raw JSON array (`[...]`).
- **Required Fix**: Update `woodpantry-matching/internal/clients/pantry.go` to unmarshal into a wrapper struct `{ Items []PantryItem }`.
- **Smoke Test**: `tests/smoke_pantry.sh` — "Pantry — Response Contract" check.
- **Status**: CLOSED (reported fixed in `woodpantry-matching/internal/clients/pantry.go` with client test coverage)

## [2026-03-31] Recipe create rejects ingredient names without ingredient IDs

- **Symptom**: `POST /recipes` fails when given structured ingredients by `name`, which breaks direct recipe creation from the documented Phase 1 flow.
- **Error**: `{"error":"invalid ingredient_id: "}`
- **Root Cause**: `woodpantry-recipes` appears to require `ingredient_id` on structured create instead of resolving ingredient names through the Ingredient Dictionary before persistence.
- **Required Fix**: Update the recipe create flow in `woodpantry-recipes` to call `/ingredients/resolve` for each input ingredient when `ingredient_id` is absent, then persist the canonical IDs.
- **Smoke Test**: `tests/smoke_recipes.sh` — "Recipes — Create Recipe" check.
- **Status**: CLOSED (reported fixed in `woodpantry-recipes` create flow with unit/integration coverage)

## [2026-04-01] Ingestion pipeline pantry staging endpoint missing in Pantry Service

- **Symptom**: Queue-driven pantry ingest cannot stage extracted items in Pantry Service.
- **Error**: `woodpantry-ingestion` posts to `POST /pantry/ingest/{job_id}/stage`, but `woodpantry-pantry` does not expose that HTTP route.
- **Root Cause**: The pantry repo has staged-ingest internals, but the Phase 2 cross-service staging contract was not exposed as an API handler/router path.
- **Required Fix**: Add `POST /pantry/ingest/{job_id}/stage` to `woodpantry-pantry`, accepting extracted staged items from `woodpantry-ingestion` and returning stage counts.
- **Smoke Test**: No dedicated cross-service smoke test yet; add one once the endpoint exists.
- **Status**: CLOSED (endpoint added with handler/service tests; handler, service, and router wired)

## [2026-04-02] Recipe detail endpoint returns sqlc-style field names instead of documented JSON contract

- **Symptom**: `GET /recipes/{id}` returns fields like `ID` and `Title`, causing the smoke suite's fetch check to see an empty lowercase `title`.
- **Error**: Smoke test `smoke_recipes.sh` created a recipe successfully, then failed on fetch because the response did not expose the documented lowercase JSON field names.
- **Root Cause**: `woodpantry-recipes` was serializing embedded sqlc-generated structs directly in the recipe detail response.
- **Required Fix**: Update `woodpantry-recipes` `GET /recipes/{id}` response shaping to return explicit API DTOs with stable lowercase JSON fields.
- **Smoke Test**: `tests/smoke_recipes.sh` — "Recipes — Fetch Recipe" check.
- **Status**: CLOSED (fixed 2026-04-02; verified with hardened smoke suite)

## [2026-04-02] Pantry list endpoint omits documented `name` field and returns sqlc-style keys

- **Symptom**: `GET /pantry` returns items like `{"ID":"...","IngredientID":"..."}` without lowercase fields or `name`.
- **Error**: Smoke test `smoke_pantry.sh` failed to find added pantry item by name.
- **Root Cause**: `woodpantry-pantry` was serializing sqlc-generated `PantryItem` structs directly.
- **Required Fix**: Update `woodpantry-pantry` `GET /pantry` to return explicit API DTOs with stable lowercase JSON fields and the documented `name`.
- **Smoke Test**: `tests/smoke_pantry.sh` — "Pantry — Response Contract" check.
- **Status**: CLOSED (fixed 2026-04-02; verified with hardened smoke suite)

## [2026-04-02] Recipe Create and List endpoints return sqlc-style field names

- **Symptom**: `POST /recipes` and `GET /recipes` return Go-style uppercase fields (e.g., `ID`, `Title`), which breaks strict contract consumers.
- **Error**: Hardened smoke test `smoke_recipes.sh` logs `CONTRACT MISMATCH` when capturing the recipe ID from a `POST` response.
- **Root Cause**: `woodpantry-recipes` continues to return raw DB/sqlc structs in the list and create handlers.
- **Required Fix**: Update `handleCreateRecipe` and `handleListRecipes` in `woodpantry-recipes/internal/api/handlers.go` to return explicit lowercase API DTOs instead of raw DB/sqlc structs.
- **Smoke Test**: `tests/smoke_recipes.sh` — "Recipes — Create Recipe" check.
- **Status**: CLOSED (fixed 2026-04-02; verified by rerunning the hardened local smoke suite after recipe CRUD DTO normalization)
