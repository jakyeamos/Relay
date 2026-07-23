# Coding conventions

- Use Swift 6 language mode and keep the declared macOS 13 deployment target.
- Prefer value types and explicit domain models for normalized records.
- Keep exported APIs narrow and name types after the domain concept they own.
- Use AppKit for visible UI and keep UI-only state in `RelayApp`.
- Mark UI and main-queue interactions with the appropriate actor/queue boundary;
  do not touch AppKit from background ingestion callbacks.
- Keep SQLite access centralized in `SQLiteStore`; do not create ad hoc stores
  in view controllers or executables.
- Keep provider-specific behavior in adapter types and preserve raw-source
  provenance when normalizing records.
- Use guarded file transactions for writes: exact path selection, symlink
  resolution, precondition hashes, atomic replacement, audit record, and undo.
- Prefer small deterministic helpers over hidden global state. Extend existing
  domain services before adding a parallel implementation.
- Tests should protect behavior and safety boundaries, not merely line count.
