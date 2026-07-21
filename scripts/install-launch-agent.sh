#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
USER_HOME="${HOME}"
LAUNCH_AGENT_DIR="$USER_HOME/Library/LaunchAgents"
LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/codes.relay.helper.plist"

cd "$PROJECT_ROOT"
swift build -c release --product RelayHelper
HELPER_PATH="$PROJECT_ROOT/.build/release/RelayHelper"
mkdir -p "$LAUNCH_AGENT_DIR"

/usr/bin/sed "s|__HELPER_PATH__|$HELPER_PATH|g" \
    "$PROJECT_ROOT/Resources/com.relay.helper.plist" > "$LAUNCH_AGENT_PATH"

/bin/launchctl bootout "gui/$(id -u)/codes.relay.helper" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH"
echo "Installed $LAUNCH_AGENT_PATH"
