#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COVERAGE_DIR="$PROJECT_ROOT/coverage"
COVERAGE_PATH="$COVERAGE_DIR/lcov.info"

cd "$PROJECT_ROOT"
swift test --enable-code-coverage

PROFILE_PATH="$(rg --files --hidden .build -g 'default.profdata' | head -1)"
TEST_BINARY="$(rg --files --hidden .build -g 'RelayPackageTests' | rg '/RelayPackageTests\.xctest/Contents/MacOS/RelayPackageTests$' | head -1)"

if [[ -z "$PROFILE_PATH" || -z "$TEST_BINARY" ]]; then
    echo "Could not locate Swift coverage artifacts." >&2
    exit 1
fi

mkdir -p "$COVERAGE_DIR"
xcrun llvm-cov export -format=lcov -instr-profile "$PROFILE_PATH" "$TEST_BINARY" > "$COVERAGE_PATH"
echo "Wrote $COVERAGE_PATH"
