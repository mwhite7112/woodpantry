# WoodPantry — Integration Bug Tracker

## [2026-03-31] Matching service fails to unmarshal Pantry response

- **Symptom**: `GET /matches` returns `502 Bad Gateway`.
- **Error**: `scoring failed: fetch pantry: decode response: json: cannot unmarshal object into Go value of type []clients.PantryItem`
- **Root Cause**: `woodpantry-pantry` returns a JSON object with an `"items"` key (`{"items": [...]}`), but `woodpantry-matching`'s HTTP client expects a raw JSON array (`[...]`).
- **Required Fix**: Update `woodpantry-matching/internal/clients/pantry.go` to unmarshal into a wrapper struct `{ Items []PantryItem }`.
- **Smoke Test**: `tests/smoke_pantry.sh` — "Pantry — Response Contract" check.
- **Status**: OPEN

## [2026-03-31] Recipe create rejects ingredient names without ingredient IDs

- **Symptom**: `POST /recipes` fails when given structured ingredients by `name`, which breaks direct recipe creation from the documented Phase 1 flow.
- **Error**: `{"error":"invalid ingredient_id: "}`
- **Root Cause**: `woodpantry-recipes` appears to require `ingredient_id` on structured create instead of resolving ingredient names through the Ingredient Dictionary before persistence.
- **Required Fix**: Update the recipe create flow in `woodpantry-recipes` to call `/ingredients/resolve` for each input ingredient when `ingredient_id` is absent, then persist the canonical IDs.
- **Smoke Test**: `tests/smoke_recipes.sh` — "Recipes — Create Recipe" check.
- **Status**: OPEN
