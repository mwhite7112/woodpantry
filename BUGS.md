# WoodPantry — Integration Bug Tracker

## [2026-03-31] Matching service fails to unmarshal Pantry response

- **Symptom**: `GET /matches` returns `502 Bad Gateway`.
- **Error**: `scoring failed: fetch pantry: decode response: json: cannot unmarshal object into Go value of type []clients.PantryItem`
- **Root Cause**: `woodpantry-pantry` returns a JSON object with an `"items"` key (`{"items": [...]}`), but `woodpantry-matching`'s HTTP client expects a raw JSON array (`[...]`).
- **Required Fix**: Update `woodpantry-matching/internal/clients/pantry.go` to unmarshal into a wrapper struct `{ Items []PantryItem }`.
- **Smoke Test**: `tests/smoke_pantry.sh` — "Pantry — Response Contract" check.
- **Status**: OPEN
