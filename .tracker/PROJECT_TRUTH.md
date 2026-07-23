# Relay Project Truth

summary: Local-first native macOS Relay workbench with bounded Codex ingestion, normalized session titles, persistent repository workspaces, scoped session queries, deterministic Playbook Intelligence, Usage metrics, guarded file transactions, one-window AppKit navigation, and an explicit native release gate.
nextStep: Keep the routed environment contract current with the weekly audit; rerun `scripts/release-check.sh` with fresh human-reviewed capture and accessibility evidence when the desktop capture backend is available.
blockers: [Desktop screenshot/accessibility capture is unavailable in this environment because ScreenCaptureKit fails to start its stream; the native release gate remains blocked until a reviewed live evidence artifact is supplied.]
lastUpdated: 2026-07-22
sourceOfTruth: commit 47e4adb plus current Swift tests, coverage, release products, bundle validation, pre-CR output, and scripts/release-check.sh
healthScore: 95
statusLabel: implementation complete; capture-limited dogfood

## Current State

- The project is a new Swift Package at `/Users/jakyeamos/projects/relay`.
- `RelayCore` contains normalized domain types, SQLite storage, provider adapters, status evidence, context discovery, Playbook analysis, usage metrics, monitoring, and guarded apply/undo transactions.
- `RelayApp` contains a single nested AppKit split-view workbench for Today, Playbook, and Usage; the obsolete page-local controllers were removed after the replacement shell compiled and passed the core/app gates.
- The workbench persists workspace/session selection, pane widths, inspector visibility, density, mode, sort, filters, and usage range. It uses a virtualized `NSTableView` center list, a context inspector, native semantic surfaces, and an in-window `Cmd-K` command palette.
- Workspace resolution groups sessions by canonical repository, then worktree or working directory, with an explicit Unassigned bucket. Workspace records are additive, stable, renameable, pinnable, reorderable, hideable, and preserved across refreshes.
- SQLite now supports workspace-scoped, provider/status-filtered, tokenized session queries and scoped Usage activity/freshness metrics without rewriting imported session records.
- `RelayHelper` reuses the monitoring coordinator for one-shot or resident background ingestion.
- Codex parsing is fixture- and live-validated. The first scan imports the 25 most recently modified sessions from the last 30 days, bounds each source file to a 2 MB prefix/tail sample, and later scans revisit only modified files. Claude Code detection is present but import remains deliberately deferred.
- Session titles are normalized at parse, storage, and read time so legacy rows also display readable sentence-case labels without changing the original transcript.
- The AppKit Today surface renders normalized live sessions without blocking the UI, keeps cards full-width, preserves the current scroll position during refresh, and refreshes from a utility queue. Search, Playbook, Usage, and resume actions were exercised against the local database; tmux fallback opened Terminal because tmux is not installed on this host.
- Today observes monitor changes through a main-queue notification token and removes that token on disappearance, preventing AppKit main-actor access from the background monitoring queue.
- Approved Playbook writes require an exact selected path, symlink resolution, precondition hashes, atomic writes, audit records, and guarded undo.
- The local readiness gate runs the built XCTest bundle and requires a refreshed coverage artifact; no source or transcript data is sent by the default workflow.
- The routed environment contract covers eight context packets, six canonical commands, target metadata, and secret-path checks; `scripts/check_environment_contract.py` is required by pre-CR.
- `codes.relay.app` is registered as a user LaunchAgent and opens the current `Relay.app` bundle at macOS login; `scripts/uninstall-startup.sh` removes only that registration.

## Quality

| Check | Status | Evidence |
|---|---|---|
| Swift build | pass | Final `swift build -c release` compiled AppKit and helper products |
| Tests | pass | Final `swift test` passed 18 behavior tests with 0 failures |
| Coverage | pass | `coverage/lcov.info` refreshed by `scripts/test-with-coverage.sh`; changed-line coverage remains gated by the repository check |
| Environment contract | pass | 8 packets, 6 commands, 0 secret-like tracked paths; checker and pre-CR adapter passed |
| Pre-CR readiness | pass | Commit hook completed with exit code 0 |
| App bundle smoke | pass | Final `scripts/build-app.sh` completed; `Relay.app/Contents/Info.plist` linted successfully with macOS 13 minimum |
| Native release gate | blocked | `scripts/release-check.sh` passed tests/products/bundle checks and exited 2 because reviewed live capture/accessibility evidence is missing |
| Live launch smoke | pass | Fresh `Relay.app` launched as `RelayApp` and stayed running for process-level inspection; terminated after the check |
| Crash regression | pass | Translated report reproduced a background notification/main-actor race; rebuilt app stayed alive through a 12-second monitor interval |
| Helper smoke | pass | Isolated live import wrote 25 real Codex sessions and 5,489 events to temporary SQLite in 8 seconds |
| Login startup | pass | `launchctl print gui/$(id -u)/codes.relay.app`, plist lint, and last exit code 0 |
| Shellcheck | warning | `shellcheck` is unavailable on this host |
| Dead-code scan | unknown | No Swift dead-code tool configured yet |

## Recent Progress

- Added Codex JSONL parsing, status inference, Git context, and artifact discovery.
- Added SQLite persistence, local usage metrics, deterministic Playbook candidates, and transaction safety.
- Added AppKit navigation, Today session cards, Playbook preview/apply flow, Usage cards, helper executable, and launch-agent scaffolding.
- Added local JSON configuration for provider data roots and tmux/editor command templates.
- Added persistent repository workspaces, scoped/tokenized session queries, workspace-scoped Usage activity, and stable Playbook candidate lifecycle IDs in `1a3f1b1`.
- Replaced the page-swapping shell with the single-window Today/Playbook/Usage workbench, shared AppKit design tokens/components, contextual inspectors, keyboard routing, and guarded inline Playbook actions in `0e8274a`.
- Re-ran final `swift test`, release build, app-bundle build, `Info.plist` validation, and process-level launch smoke; all passed on the committed workbench.
- Verified an isolated one-shot helper import without touching the default Relay database.
- Verified the commit gate and committed the foundation as `768e278` on `feat/relay-foundation`.
- Registered the visible app for login startup in `9116e12`; helper startup remains independently opt-in.
- Dogfooded the native app across Today, search, resume, Playbook, and Usage; fixed main-thread startup/import blocking, real Codex nested payload mapping, session-card sizing/scroll behavior, and duplicate Git-root resolution in `077075c`.
- Fixed the `relayDataDidChange` observer race identified in the translated crash report by dispatching Today refreshes through a main-queue observer and committed the fix as `637d6c9`.
- Added deterministic title cleanup for Markdown headings, metadata tags, working-directory suffixes, boilerplate, and long prompt fragments; live Today now shows labels such as `Recommended plugins`, `Environment context`, and `AGENTS.md instructions` in `b11c1e1`.
- Added the minimal agent operating contract and context index in `b3ed825`; future work now has a bounded default context route and explicit safety invariants.
- Added the native release gate and readiness contract; current tests, release products, bundle assembly, and plist validation pass while live capture/accessibility evidence remains explicitly blocked.
- Added the complete routed environment contract, executable checker, regression tests, and required pre-CR adapter in `47e4adb`; all local quality gates pass.
