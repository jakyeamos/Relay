# Security and data boundaries

- Relay is local-first. The default monitor reads local Codex/Claude paths and
  writes only to the configured local SQLite store.
- No credentials, tokens, transcripts, prompts, source files, or diffs may be
  sent to a provider by the default workflow.
- Optional provider-assisted analysis is out of the background monitor. Any
  future adapter must redact, disclose, and require review before data leaves
  the device.
- Never commit personal session data, local databases, API keys, certificates,
  private keys, or generated app bundles. `.env.example`-style documentation is
  acceptable; real secret-like paths are not.
- Playbook writes require an exact selected path, symlink resolution,
  precondition hashes, atomic writes, an audit record, and guarded undo.
- Startup installation and helper launch-agent installation are explicit local
  user actions. They must not be added to tests or release automation.
- Do not deploy, publish, merge, push, or change login/startup state as part of
  a normal test run without explicit approval.
