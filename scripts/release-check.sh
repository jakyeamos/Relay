#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$PROJECT_ROOT/Relay.app"

cd "$PROJECT_ROOT"
swift test
swift build -c release --product RelayApp
swift build -c release --product RelayHelper
./scripts/build-app.sh
/usr/bin/plutil -lint "$APP_ROOT/Contents/Info.plist" >/dev/null

bundle_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP_ROOT/Contents/Info.plist")"
evidence_path="${RELAY_LIVE_EVIDENCE:-}"

python3 - "$bundle_version" "$evidence_path" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


version, evidence_value = sys.argv[1:]
blockers: list[str] = []
evidence_path = Path(evidence_value).expanduser() if evidence_value else None

if evidence_path is None:
    blockers.append("live_capture_accessibility_evidence_missing")
else:
    try:
        payload: Any = json.loads(evidence_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        blockers.append("live_capture_accessibility_evidence_unreadable")
    else:
        if not isinstance(payload, dict) or payload.get("schema_version") != 1:
            blockers.append("live_capture_accessibility_evidence_schema_invalid")
        else:
            captured_at = payload.get("captured_at")
            if not isinstance(captured_at, str) or not captured_at:
                blockers.append("live_capture_accessibility_evidence_timestamp_missing")
            else:
                try:
                    captured_time = datetime.fromisoformat(captured_at.replace("Z", "+00:00"))
                    if captured_time.tzinfo is None:
                        raise ValueError("timestamp must include a timezone")
                    age = datetime.now(timezone.utc) - captured_time.astimezone(timezone.utc)
                    if age > timedelta(hours=24):
                        blockers.append("live_capture_accessibility_evidence_stale")
                    elif age < timedelta(minutes=-5):
                        blockers.append("live_capture_accessibility_evidence_from_future")
                except ValueError:
                    blockers.append("live_capture_accessibility_evidence_timestamp_invalid")
            for field in ("capture", "accessibility"):
                check = payload.get(field)
                if (
                    not isinstance(check, dict)
                    or check.get("status") != "pass"
                    or not isinstance(check.get("evidence_ref"), str)
                    or not check["evidence_ref"]
                ):
                    blockers.append(f"live_{field}_evidence_missing")

status = "passed" if not blockers else "blocked"
print(
    json.dumps(
        {
            "status": status,
            "version": version,
            "checks": {
                "swift_tests": "passed",
                "release_products": "passed",
                "app_bundle": "passed",
                "live_capture_accessibility": "passed" if not blockers else "blocked",
            },
            "evidence": str(evidence_path) if evidence_path else None,
            "blockers": blockers,
        },
        sort_keys=True,
    )
)
raise SystemExit(0 if status == "passed" else 2)
PY
