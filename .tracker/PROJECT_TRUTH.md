# Relay Project Truth

summary: Native macOS Relay foundation created with AppKit, a shared Swift core, SQLite persistence, Codex-first ingestion, deterministic Playbook Intelligence, Unified Usage metrics, and guarded file transactions.
nextStep: Validate the Codex adapter against a live local session, then complete the Claude adapter contract.
blockers: []
lastUpdated: 2026-07-21
sourceOfTruth: mixed
healthScore: 78
statusLabel: early foundation

## Current State

- The project is a new Swift Package at `/Users/jakyeamos/projects/relay`.
- `RelayCore` contains normalized domain types, SQLite storage, provider adapters, status evidence, context discovery, Playbook analysis, usage metrics, monitoring, and guarded apply/undo transactions.
- `RelayApp` contains the native AppKit Today, Playbook, and Usage surfaces.
- `RelayHelper` reuses the monitoring coordinator for one-shot or resident background ingestion.
- Codex parsing is implemented; Claude Code detection is present but import is deliberately deferred until Codex validation is complete.

## Quality

| Check | Status | Evidence |
|---|---|---|
| Swift build | pass | `swift build -c release` compiled AppKit and helper products |
| Tests | pass | `swift test` passed 9 behavior tests |
| App bundle smoke | pass | `scripts/build-app.sh`, `plutil -lint`, and Mach-O inspection passed |
| Helper smoke | pass | Isolated fixture import wrote 1 session to temporary SQLite |
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
