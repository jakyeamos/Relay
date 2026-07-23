# Common failure modes and recovery

## Missing live release evidence

`scripts/release-check.sh` may pass tests, release products, bundle assembly,
and plist validation, then exit `2` because the reviewed capture/accessibility
JSON is absent or stale. Supply a fresh human-reviewed artifact through
`RELAY_LIVE_EVIDENCE`; never weaken the gate.

## Test bundle missing

`scripts/pre-cr-test.sh` requires the XCTest bundle produced by
`scripts/test-with-coverage.sh`. Run the coverage script first, then rerun
pre-CR from the same checkout.

## Background/main-thread race

AppKit must be reached on the main queue. Reproduce with `swift test` and a
bounded helper/app smoke run, then inspect observer lifetime and dispatch
boundaries before changing persistence or UI state.

## Large or changing session sources

Use the adapter's bounded first-scan and modified-file behavior. Do not replace
it with an unbounded recursive read or load the complete transcript history into
one context.

## Transaction precondition failure

Treat a changed target, symlink mismatch, or failed hash as a stop. Refresh the
preview and obtain a new explicit path selection; do not force the write or
rewrite the audit history.

## Startup path drift

If Relay moves, rerun `scripts/install-startup.sh` to refresh the user-level
LaunchAgent path. Use `scripts/uninstall-startup.sh` to remove only Relay's
registration.
