# Build, test, and quality commands

Run commands from the repository root on macOS with the Swift toolchain.

## Normal development

```sh
swift test
swift build
python3 scripts/check_environment_contract.py --as-of 2026-07-25
```

`swift test` is the canonical fast behavioral gate. There is no separate
repository lint tool currently configured; keep Swift compiler diagnostics and
the contract checker green.

The disposable quality contract in `.pre-cr.json` declares these reproducible
quality commands:

```sh
swift build
swift test
swift test --enable-code-coverage
swift build -c release --product RelayApp
swift build -c release --product RelayHelper
python3 scripts/check_environment_contract.py
```

`./scripts/pre-cr-test.sh` remains the staged pre-CR bundle gate, and
`./scripts/release-check.sh` remains the release gate because its final result
requires fresh human-reviewed capture and accessibility evidence.

## Coverage and pre-CR

```sh
./scripts/test-with-coverage.sh
./scripts/pre-cr-test.sh
```

The pre-CR test expects a built test bundle, so run coverage first in a fresh
checkout. The pre-CR contract adapter runs the environment checker.

## Release validation

```sh
swift build -c release --product RelayApp
swift build -c release --product RelayHelper
./scripts/build-app.sh
./scripts/release-check.sh
```

`release-check.sh` exits `2` when fresh human-reviewed capture and accessibility
evidence is absent. That is an intentional evidence result, not a reason to
manufacture or bypass the gate.

## Local smoke commands

```sh
swift run RelayApp
swift run RelayHelper --once --database /tmp/relay-smoke.sqlite
```

Use temporary database paths for smoke tests. Do not point fixtures or tests at
the default personal database.
