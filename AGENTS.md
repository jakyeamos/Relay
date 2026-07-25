# Agent operating contract

Read this router before repository work.

- Read `.agents/context/README.md` before searching broadly.
- Use documented commands and repository-local quality gates.
- Treat the `.pre-cr.json` `qualityCommands` list as the canonical set for
  disposable automated verification; keep live capture and release evidence
  gates separate.
- Preserve unrelated dirty work and use a disposable worktree for risky changes.
- Keep credentials, secrets, deployments, merges, and destructive operations behind explicit approval.
- Validate behavior and record the evidence needed for the task handoff.
