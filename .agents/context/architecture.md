# Architecture and boundaries

Relay is a private, local-first macOS workbench for inspecting and resuming
personal AI coding workflows. It has no Relay-operated backend and no required
account.

## Targets

- `RelayCore` owns domain models, provider adapters, bounded session ingestion,
  SQLite persistence, status inference, deterministic Playbook analysis, Usage
  metrics, and guarded file transactions.
- `RelayApp` owns the AppKit window, Today/Playbook/Usage navigation, command
  palette, and user-facing interaction. It calls `RelayCore`; it does not own
  persistence or provider parsing.
- `RelayHelper` reuses the monitoring coordinator for one-shot or resident
  background ingestion. It must remain safe to run without the visible app.
- `CSQLite` is the narrow system-library bridge used by `RelayCore`.
- `RelayCoreTests` protects parsing, persistence, inference, transaction, and
  workflow behavior with fixtures and isolated temporary stores.

## Data flow

Local session/config sources -> bounded provider adapters -> normalized domain
records -> SQLite store -> AppKit projections and Usage/Playbook projections.
Playbook writes are a separate guarded transaction path requiring explicit user
selection and confirmation.

## Boundary rules

- Keep provider-specific parsing behind adapters and normalized models.
- Keep UI state and AppKit concerns out of `RelayCore`.
- Keep file writes behind `FileTransactions` and its precondition/audit path.
- Keep background ingestion bounded, cancellable, and independent of UI launch.
- Optional provider-assisted analysis is never part of the default monitor.
