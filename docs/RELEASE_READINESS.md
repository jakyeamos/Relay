# Relay native release readiness

Relay is released as a signed macOS app bundle, not as a Python or registry
package. The version source is `Resources/Info.plist`:

- `CFBundleShortVersionString`: `0.1.0`
- `CFBundleVersion`: `1`
- bundle identifier: `codes.relay.app`

Run the native gate from the repository root:

```sh
./scripts/release-check.sh
```

The gate verifies Swift tests, optimized `RelayApp` and `RelayHelper` builds,
bundle assembly, and plist validity. It then requires a fresh, human-reviewed
live evidence artifact. The artifact is supplied with `RELAY_LIVE_EVIDENCE` and
must have this shape:

```json
{
  "schema_version": 1,
  "captured_at": "2026-07-22T20:00:00-04:00",
  "capture": {"status": "pass", "evidence_ref": "<reviewed capture reference>"},
  "accessibility": {"status": "pass", "evidence_ref": "<reviewed accessibility reference>"}
}
```

The timestamp must be within 24 hours of the gate run. The evidence must come
from a real desktop session; the script does not create screenshots,
accessibility receipts, or fixture substitutes. The reviewed desktop evidence
must show a non-zero Relay window frame and resolve the `relay.search.input`,
`relay.search.results`, and `relay.result.details` accessibility identifiers.
Until this artifact exists, Relay remains a native release candidate with local
build evidence but no public release claim.
