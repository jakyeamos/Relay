#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
USER_HOME="$HOME"
LAUNCH_AGENT_DIR="$USER_HOME/Library/LaunchAgents"
LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/codes.relay.app.plist"
LABEL="codes.relay.app"

cd "$PROJECT_ROOT"
./scripts/build-app.sh
APP_PATH="$PROJECT_ROOT/Relay.app"
mkdir -p "$LAUNCH_AGENT_DIR"

/usr/bin/sed "s|__APP_PATH__|$APP_PATH|g" \
    "$PROJECT_ROOT/Resources/codes.relay.app.plist" > "$LAUNCH_AGENT_PATH"

/bin/launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH"
echo "Installed $LAUNCH_AGENT_PATH"
echo "Relay will launch at the next macOS login."
