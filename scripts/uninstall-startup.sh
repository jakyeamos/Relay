#!/bin/zsh
set -euo pipefail

USER_HOME="$HOME"
LAUNCH_AGENT_PATH="$USER_HOME/Library/LaunchAgents/codes.relay.app.plist"
LABEL="codes.relay.app"

/bin/launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [[ -f "$LAUNCH_AGENT_PATH" ]]; then
    /bin/rm "$LAUNCH_AGENT_PATH"
fi
echo "Removed Relay startup registration."
