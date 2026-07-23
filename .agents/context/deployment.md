# Deployment and rollback

## Local bundle

Build the app with `./scripts/build-app.sh`, inspect the generated
`Relay.app`, and launch it with `open Relay.app`. The bundle is local build
output and is ignored by Git.

## Startup installation

`./scripts/install-startup.sh` installs the visible app's user-level
`codes.relay.app` LaunchAgent. `./scripts/install-launch-agent.sh` is a
separate, explicit choice for the headless helper. Verify the resulting
registration with the commands documented in the script and project truth.

## Release gate

Run `./scripts/release-check.sh` before calling a build release-ready. Fresh,
human-reviewed capture and accessibility evidence must be supplied through
`RELAY_LIVE_EVIDENCE`. Publishing and deployment remain human-approved.

## Rollback

For a code regression, stop the app, revert the single atomic commit or deploy
the last known-good commit through the repository's normal review path; do not
rewrite history. For startup problems, run `./scripts/uninstall-startup.sh`.
For a Playbook write, use the recorded guarded undo transaction rather than
manually overwriting a file.
