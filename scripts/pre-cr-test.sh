#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BINARY="$(rg --files --hidden "$PROJECT_ROOT/.build" -g 'RelayPackageTests' | rg '/RelayPackageTests\.xctest/Contents/MacOS/RelayPackageTests$' | head -1)"

if [[ -z "$TEST_BINARY" ]]; then
    echo "Relay test bundle is missing. Run ./scripts/test-with-coverage.sh before committing." >&2
    exit 1
fi

TEST_BUNDLE="${TEST_BINARY%/Contents/MacOS/RelayPackageTests}"
cd "$PROJECT_ROOT"
xcrun xctest "$TEST_BUNDLE"
