# Relay Project Truth

summary: Verified native macOS Relay foundation with AppKit, a shared Swift core, SQLite persistence, Codex-first ingestion, deterministic Playbook Intelligence, Unified Usage metrics, guarded file transactions, and login startup.
nextStep: Validate the Codex adapter against a live local session, then complete the Claude adapter contract.
blockers: []
lastUpdated: 2026-07-21
sourceOfTruth: commit 9116e12 plus local build, fixture smoke, and launchctl readback
healthScore: 84
statusLabel: verified foundation

## Current State

- The project is a new Swift Package at `/Users/jakyeamos/projects/relay`.
- `RelayCore` contains normalized domain types, SQLite storage, provider adapters, status evidence, context discovery, Playbook analysis, usage metrics, monitoring, and guarded apply/undo transactions.
- `RelayApp` contains the native AppKit Today, Playbook, and Usage surfaces.
- `RelayHelper` reuses the monitoring coordinator for one-shot or resident background ingestion.
- Codex parsing is implemented and fixture-validated; Claude Code detection is present but import is deliberately deferred until live Codex validation is complete.
- Approved Playbook writes require an exact selected path, symlink resolution, precondition hashes, atomic writes, audit records, and guarded undo.
- The local readiness gate runs the built XCTest bundle and requires a refreshed coverage artifact; no source or transcript data is sent by the default workflow.
- `codes.relay.app` is registered as a user LaunchAgent and opens the current `Relay.app` bundle at macOS login; `scripts/uninstall-startup.sh` removes only that registration.

## Quality

| Check | Status | Evidence |
|---|---|---|
| Swift build | pass | `swift build -c release` compiled AppKit and helper products |
| Tests | pass | `swift test --enable-code-coverage` passed 9 behavior tests |
| Coverage | pass | `coverage/lcov.info` loaded by Pre-CR at 71% lines / 63% functions |
| Pre-CR readiness | pass | Commit hook completed with exit code 0 |
| App bundle smoke | pass | `scripts/build-app.sh`, `plutil -lint`, and Mach-O inspection passed |
| Helper smoke | pass | Isolated fixture import wrote 1 session to temporary SQLite |
| Login startup | pass | `launchctl print gui/$(id -u)/codes.relay.app`, plist lint, and last exit code 0 |
| Shellcheck | warning | `shellcheck` is unavailable on this host |
| Dead-code scan | unknown | No Swift dead-code tool configured yet |

## Recent Progress

- Added the Swift Package and SQLite system module.
- Added the normalized Relay domain model and provider contract.
- Added Codex JSONL parsing, status inference, Git context, and artifact discovery.
- Added SQLite persistence, local usage metrics, deterministic Playbook candidates, and transaction safety.
- Added AppKit navigation, Today session cards, Playbook preview/apply flow, Usage cards, helper executable, and launch-agent scaffolding.
- Added local JSON configuration for provider data roots and tmux/editor command templates.
- Verified an isolated one-shot helper import without touching the default Relay database.
- Verified the commit gate and committed the foundation as `768e278` on `feat/relay-foundation`.
- Registered the visible app for login startup in `9116e12`; helper startup remains independently opt-in.
