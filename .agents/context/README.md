# Relay context index

last_reviewed: 2026-07-25
owner: repository-owner
freshness: review this index when Package.swift, scripts, Sources, or release policy changes

Load this index first, then follow only the packet needed for the task. The
repository is a local-first macOS control plane; do not dump the whole tree
into context.

- [`AGENTS.md`](../../AGENTS.md) — always-loaded operating invariants.
- [`README.md`](../../README.md) — user-facing entry points and local setup.
- [`architecture.md`](architecture.md) — target boundaries and data flow.
- [`commands.md`](commands.md) — build, test, coverage, and release commands.
- [`conventions.md`](conventions.md) — Swift/AppKit and persistence conventions.
- [`security.md`](security.md) — local-data, credential, and approval boundaries.
- [`failure-modes.md`](failure-modes.md) — known failures and recovery paths.
- [`examples.md`](examples.md) — maintained implementation examples.
- [`done.md`](done.md) — acceptance and evidence contract.
- [`deployment.md`](deployment.md) — bundle, startup, rollback, and release procedure.

Use the narrowest packet that answers the question. If a packet conflicts with
live code or the project truth snapshot, live code and verified command output
win; update the packet in the same change that changes the behavior.
