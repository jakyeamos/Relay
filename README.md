# Relay

Relay is a private, keyboard-first macOS control plane for personal AI coding workflows.

The first native slice is built around three surfaces:

- **Today** — local Codex session discovery, status evidence, repository context, search, and tmux/Neovim resumption.
- **Playbook** — deterministic local friction analysis with evidence, confidence, latest-scan versus pending separation, and explicit file transactions.
- **Usage** — derived local workflow metrics with provider quota values clearly marked unavailable until a provider adapter can prove them.

Relay is local-first. The app does not require an account or Relay-operated backend. Optional provider-assisted analysis is not invoked by the background monitor and must be redacted and reviewed before it leaves the device.

## Run locally

```sh
swift test
swift run RelayApp
```

The helper can run one import cycle or stay resident:

```sh
swift run RelayHelper --once
swift run RelayHelper
```

The Codex adapter reads `~/.codex/sessions` by default. The Claude Code adapter is intentionally health-only until the Codex contract is validated against fixtures and live local data.

Optional configuration lives at `~/Library/Application Support/Relay/config.json`:

```json
{
  "codexSessionsPath": "/Users/you/.codex/sessions",
  "claudeProjectsPath": "/Users/you/.claude/projects",
  "tmuxCommandTemplate": "tmux new-session -Ad -s {session} -c {path}",
  "editorCommandTemplate": "cd {path} && nvim"
}
```

The helper also accepts `--database <path>` and `--sessions-root <path>` for fixture and isolated smoke runs.

## Build an app bundle

```sh
./scripts/build-app.sh
open Relay.app
```

The visible app can launch automatically at macOS login:

```sh
./scripts/install-startup.sh
```

This registers a user-level LaunchAgent for the current `Relay.app` bundle. If
the repository moves, run the script again to refresh the registered path.
Remove the startup registration with:

```sh
./scripts/uninstall-startup.sh
```

The headless helper remains separately opt-in:

```sh
./scripts/install-launch-agent.sh
```

The app never applies a Playbook suggestion without an explicit path selection, full preview, confirmation, precondition check, and transaction record.

## Project shape

`RelayCore` owns the provider contract, SQLite store, normalized session model, deterministic intelligence, usage metrics, and guarded file transactions. `RelayApp` owns the AppKit shell. `RelayHelper` reuses the same monitoring coordinator for background ingestion.
