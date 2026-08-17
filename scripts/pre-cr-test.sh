#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

find_test_binary() {
    if [[ ! -d "$PROJECT_ROOT/.build" ]]; then
        return 0
    fi
    rg --files --hidden "$PROJECT_ROOT/.build" -g 'RelayPackageTests' \
        | rg '/RelayPackageTests\.xctest/Contents/MacOS/RelayPackageTests$' \
        | head -1 \
        || true
}

TEST_BINARY="$(find_test_binary)"

if [[ -z "$TEST_BINARY" ]]; then
    echo "Relay test bundle is missing; building the documented coverage test bundle." >&2
    "$PROJECT_ROOT/scripts/test-with-coverage.sh"
    TEST_BINARY="$(find_test_binary)"
fi

if [[ -z "$TEST_BINARY" ]]; then
    echo "Could not locate Relay test bundle after the coverage build." >&2
    exit 1
fi

TEST_BUNDLE="${TEST_BINARY%/Contents/MacOS/RelayPackageTests}"
cd "$PROJECT_ROOT"
python3 scripts/test_environment_contract.py
xcrun xctest "$TEST_BUNDLE"
