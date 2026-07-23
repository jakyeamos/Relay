# Maintained implementation examples

- [`Sources/RelayCore/CodexAdapter.swift`](../../Sources/RelayCore/CodexAdapter.swift)
  is the canonical bounded local-session adapter. It limits initial work and
  preserves provider provenance.
- [`Sources/RelayCore/FileTransactions.swift`](../../Sources/RelayCore/FileTransactions.swift)
  is the canonical guarded-write path. It demonstrates preconditions, atomic
  replacement, audit records, and undo.
- [`Sources/RelayCore/SQLiteStore.swift`](../../Sources/RelayCore/SQLiteStore.swift)
  is the canonical persistence boundary and should be extended before adding
  another store.
- [`Sources/RelayApp/RelayWorkbenchViewController.swift`](../../Sources/RelayApp/RelayWorkbenchViewController.swift)
  is the canonical AppKit composition surface for the three user-facing modes.
- [`Tests/RelayCoreTests/RelayCoreTests.swift`](../../Tests/RelayCoreTests/RelayCoreTests.swift)
  is the canonical behavior-test surface for normalized data, queries, and
  guarded workflows.
