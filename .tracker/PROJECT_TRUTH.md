# Relay Project Truth

summary: Dogfood-verified native macOS Relay with bounded Codex ingestion, normalized session titles, nested event normalization, crash-safe monitor notifications, responsive Observe and Resume surfaces, deterministic Playbook Intelligence, Unified Usage metrics, guarded file transactions, and login startup.
nextStep: Validate the Claude adapter against sanitized fixtures and live local data, then add the session detail/context inspector.
blockers: []
lastUpdated: 2026-07-21
sourceOfTruth: commit b11c1e1 plus live Today verification, native release build, coverage, and Pre-CR readback
healthScore: 90
statusLabel: dogfood verified

## Current State

- The project is a new Swift Package at `/Users/jakyeamos/projects/relay`.
- `RelayCore` contains normalized domain types, SQLite storage, provider adapters, status evidence, context discovery, Playbook analysis, usage metrics, monitoring, and guarded apply/undo transactions.
- `RelayApp` contains the native AppKit Today, Playbook, and Usage surfaces.
- `RelayHelper` reuses the monitoring coordinator for one-shot or resident background ingestion.
- Codex parsing is fixture- and live-validated. The first scan imports the 25 most recently modified sessions from the last 30 days, bounds each source file to a 2 MB prefix/tail sample, and later scans revisit only modified files. Claude Code detection is present but import remains deliberately deferred.
- Session titles are normalized at parse, storage, and read time so legacy rows also display readable sentence-case labels without changing the original transcript.
- The AppKit Today surface renders normalized live sessions without blocking the UI, keeps cards full-width, preserves the current scroll position during refresh, and refreshes from a utility queue. Search, Playbook, Usage, and resume actions were exercised against the local database; tmux fallback opened Terminal because tmux is not installed on this host.
- Today observes monitor changes through a main-queue notification token and removes that token on disappearance, preventing AppKit main-actor access from the background monitoring queue.
- Approved Playbook writes require an exact selected path, symlink resolution, precondition hashes, atomic writes, audit records, and guarded undo.
- The local readiness gate runs the built XCTest bundle and requires a refreshed coverage artifact; no source or transcript data is sent by the default workflow.
- `codes.relay.app` is registered as a user LaunchAgent and opens the current `Relay.app` bundle at macOS login; `scripts/uninstall-startup.sh` removes only that registration.

## Quality

| Check | Status | Evidence |
|---|---|---|
| Swift build | pass | `swift build -c release` compiled AppKit and helper products |
| Tests | pass | `swift test` and the commit gate passed 12 behavior tests |
| Coverage | pass | `coverage/lcov.info` loaded at 76% lines / 69% functions; changed-line coverage 97.3% |
| Pre-CR readiness | pass | Commit hook completed with exit code 0 |
| App bundle smoke | pass | `scripts/build-app.sh`, `plutil -lint`, and Mach-O inspection passed |
| Crash regression | pass | Translated report reproduced a background notification/main-actor race; rebuilt app stayed alive through a 12-second monitor interval |
| Helper smoke | pass | Isolated live import wrote 25 real Codex sessions and 5,489 events to temporary SQLite in 8 seconds |
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
- Dogfooded the native app across Today, search, resume, Playbook, and Usage; fixed main-thread startup/import blocking, real Codex nested payload mapping, session-card sizing/scroll behavior, and duplicate Git-root resolution in `077075c`.
- Fixed the `relayDataDidChange` observer race identified in the translated crash report by dispatching Today refreshes through a main-queue observer and committed the fix as `637d6c9`.
- Added deterministic title cleanup for Markdown headings, metadata tags, working-directory suffixes, boilerplate, and long prompt fragments; live Today now shows labels such as `Recommended plugins`, `Environment context`, and `AGENTS.md instructions` in `b11c1e1`.
