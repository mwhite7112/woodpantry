#!/usr/bin/env bash
# Run all smoke tests in sequence, collecting results.
# Usage: ./tests/run_all.sh [test_file ...]
#   No args = run all smoke_*.sh files.
#   Pass specific files to run a subset.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Collect test files
if [[ $# -gt 0 ]]; then
    TEST_FILES=("$@")
else
    TEST_FILES=(
        "$SCRIPT_DIR/smoke_health.sh"
        "$SCRIPT_DIR/smoke_ingredients.sh"
        "$SCRIPT_DIR/smoke_ingredients_contracts.sh"
        "$SCRIPT_DIR/smoke_recipes.sh"
        "$SCRIPT_DIR/smoke_recipes_contracts.sh"
        "$SCRIPT_DIR/smoke_recipes_ingest.sh"
        "$SCRIPT_DIR/smoke_pantry.sh"
        "$SCRIPT_DIR/smoke_pantry_ingest.sh"
        "$SCRIPT_DIR/smoke_matching.sh"
        "$SCRIPT_DIR/smoke_phase1_e2e.sh"
    )
fi

TOTAL=0
PASSED=0
FAILED=0
FAILED_NAMES=()

echo ""
echo "========================================"
echo "  WoodPantry Smoke Tests"
echo "========================================"
echo ""

for test_file in "${TEST_FILES[@]}"; do
    name=$(basename "$test_file" .sh)
    echo -e "${YELLOW}▶ Running: ${name}${NC}"
    echo ""

    if bash "$test_file"; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$name")
    fi

    TOTAL=$((TOTAL + 1))
    echo ""
done

echo "========================================"
echo -e "  Suites: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}, ${TOTAL} total"
if [[ ${#FAILED_NAMES[@]} -gt 0 ]]; then
    echo -e "  Failed: ${RED}${FAILED_NAMES[*]}${NC}"
fi
echo "========================================"

exit "$FAILED"
