#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0
MODE="${1:-all}"

run_test() {
    local test_file="$1"
    local test_name
    test_name="$(basename "$test_file" .sh)"

    if bash "$test_file" > /dev/null 2>&1; then
        echo -e "  ${GREEN}PASS${NC} ${test_name}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}FAIL${NC} ${test_name}"
        FAILED=$((FAILED + 1))
    fi
}

run_suite() {
    local suite_dir="$1"
    local suite_name
    suite_name="$(basename "$suite_dir")"

    echo -e "\n${BOLD}=== ${suite_name} ===${NC}"

    if [[ ! -d "$suite_dir" ]]; then
        echo -e "  ${YELLOW}SKIP${NC} directory not found"
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    for test_file in "$suite_dir"/*.sh; do
        [[ -f "$test_file" ]] || continue
        run_test "$test_file"
    done
}

echo -e "${BOLD}Kent Overlay — Test Runner${NC}"
echo -e "Mode: ${MODE}\n"

if [[ "$MODE" == "all" || "$MODE" == "static" ]]; then
    run_suite "tests/static"
fi

if [[ "$MODE" == "all" || "$MODE" == "deploy" ]]; then
    run_suite "tests/deploy"
fi

if [[ "$MODE" == "smoke" ]]; then
    run_suite "tests/smoke"
fi

echo -e "\n${BOLD}Results:${NC} ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}, ${YELLOW}${SKIPPED} skipped${NC}"

exit "$FAILED"
