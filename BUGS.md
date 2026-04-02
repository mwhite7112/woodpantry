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
- **Root Cause**: `woodpantry-recipes` appears to serialize embedded sqlc-generated structs directly in the recipe detail response, so fields without JSON tags are emitted with Go-style names.
- **Required Fix**: Update `woodpantry-recipes` `GET /recipes/{id}` response shaping to return explicit API DTOs with stable lowercase JSON fields matching `README.md`.
- **Smoke Test**: `tests/smoke_recipes.sh` — "Recipes — Fetch Recipe" check.
- **Status**: OPEN

## [2026-04-02] Pantry list endpoint omits documented `name` field and returns sqlc-style keys

- **Symptom**: `GET /pantry` returns items like `{"ID":"...","IngredientID":"...","Quantity":2,"Unit":"pcs"}` without the documented lowercase field names or `name`.
- **Error**: Smoke test `smoke_pantry.sh` could confirm the wrapper shape and quantities, but could not find the added pantry item by name because the response omitted `name`.
- **Root Cause**: `woodpantry-pantry` appears to serialize sqlc-generated `PantryItem` structs directly from `GET /pantry`; those structs have no JSON tags and do not include a display name field.
- **Required Fix**: Update `woodpantry-pantry` `GET /pantry` to return explicit API DTOs with stable lowercase JSON fields and either include the documented ingredient `name` or correct the docs and dependent callers if `name` is intentionally unavailable.
- **Smoke Test**: `tests/smoke_pantry.sh` — "Pantry — Response Contract" and "Pantry — Added Item Visible" checks.
- **Status**: OPEN
