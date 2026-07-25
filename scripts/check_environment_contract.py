#!/usr/bin/env python3
"""Validate Relay's routed environment contract without network access."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from datetime import date
from pathlib import Path

PACKETS = (
    "architecture.md",
    "commands.md",
    "conventions.md",
    "security.md",
    "failure-modes.md",
    "examples.md",
    "done.md",
    "deployment.md",
)
REQUIRED_FILES = (
    "README.md",
    "AGENTS.md",
    "Package.swift",
    "scripts/pre-cr-test.sh",
    "scripts/release-check.sh",
)
REQUIRED_COMMANDS = (
    "swift test",
    "swift build -c release --product RelayApp",
    "swift build -c release --product RelayHelper",
    "./scripts/test-with-coverage.sh",
    "./scripts/pre-cr-test.sh",
    "./scripts/release-check.sh",
)
REQUIRED_QUALITY_COMMANDS = (
    "swift build",
    "swift test",
    "swift test --enable-code-coverage",
    "swift build -c release --product RelayApp",
    "swift build -c release --product RelayHelper",
    "python3 scripts/check_environment_contract.py",
)
REQUIRED_TARGETS = ("RelayCore", "RelayApp", "RelayHelper", "RelayCoreTests")
LINK_RE = re.compile(r"\[[^]]+\]\(([^)]+)\)")
REVIEW_RE = re.compile(r"last_reviewed:\s*(\d{4}-\d{2}-\d{2})")
SECRET_MARKERS = (".env", ".pem", ".key", ".p12", ".pfx", "id_rsa", "credentials")
SAFE_EXAMPLES = {".env.example", ".env.template"}


def _relative_links(text: str) -> list[str]:
    return [
        value
        for value in LINK_RE.findall(text)
        if not value.startswith(("http://", "https://", "#", "/"))
    ]


def _tracked_paths(root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=root,
        check=True,
        capture_output=True,
    )
    return [path for path in result.stdout.decode("utf-8").split("\0") if path]


def check_secret_paths(paths: list[str]) -> list[str]:
    findings: list[str] = []
    for path in paths:
        name = Path(path).name.lower()
        if name in SAFE_EXAMPLES:
            continue
        if any(marker in name for marker in SECRET_MARKERS):
            findings.append(path)
    return findings


def _check_metadata(root: Path) -> list[str]:
    errors: list[str] = []
    package_path = root / "Package.swift"
    try:
        package_text = package_path.read_text(encoding="utf-8")
    except OSError as exc:
        return [f"Package.swift unreadable: {exc}"]
    errors.extend(
        f"Package.swift is missing target or product marker: {target}"
        for target in REQUIRED_TARGETS
        if target not in package_text
    )
    pre_cr_path = root / ".pre-cr.json"
    try:
        pre_cr = json.loads(pre_cr_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"invalid .pre-cr.json: {exc}"]
    quality_commands = pre_cr.get("qualityCommands")
    if not isinstance(quality_commands, list):
        errors.append("required .pre-cr.json qualityCommands list is missing")
    else:
        missing_quality_commands = [
            command
            for command in REQUIRED_QUALITY_COMMANDS
            if command not in quality_commands
        ]
        errors.extend(
            f"required .pre-cr.json quality command is missing: {command}"
            for command in missing_quality_commands
        )
    adapters = pre_cr.get("qualityAdapters", [])
    environment_adapter = next(
        (adapter for adapter in adapters if adapter.get("name") == "environment-contract"),
        None,
    )
    if environment_adapter is None or environment_adapter.get("required") is not True:
        errors.append("required environment-contract pre-CR adapter is missing")
    if environment_adapter and environment_adapter.get("command") != (
        "python3 scripts/check_environment_contract.py"
    ):
        errors.append("environment-contract pre-CR adapter command is incorrect")
    return errors


def validate(
    root: Path,
    as_of: date,
    tracked_paths: list[str] | None = None,
) -> dict[str, object]:
    errors: list[str] = []
    errors.extend(f"missing required surface: {path}" for path in REQUIRED_FILES if not (root / path).is_file())
    index = root / ".agents" / "context" / "README.md"
    if not index.is_file():
        errors.append("missing .agents/context/README.md")
    else:
        index_text = index.read_text(encoding="utf-8")
        reviewed = REVIEW_RE.search(index_text)
        if reviewed is None:
            errors.append("context index is missing last_reviewed")
        else:
            reviewed_date = date.fromisoformat(reviewed.group(1))
            if (as_of - reviewed_date).days > 35:
                errors.append(f"context index is stale: {reviewed_date.isoformat()}")
        for link in _relative_links(index_text):
            target = (index.parent / link.split("#", 1)[0]).resolve()
            if not target.is_file() or root.resolve() not in target.parents:
                errors.append(f"broken context link: {link}")
    missing_packets = [packet for packet in PACKETS if not (index.parent / packet).is_file()]
    errors.extend(f"missing context packet: {packet}" for packet in missing_packets)
    errors.extend(_check_metadata(root))
    paths = tracked_paths if tracked_paths is not None else _tracked_paths(root)
    secret_paths = check_secret_paths(paths)
    errors.extend(f"secret-like tracked path: {path}" for path in secret_paths)
    commands_path = root / ".agents" / "context" / "commands.md"
    commands_text = commands_path.read_text(encoding="utf-8") if commands_path.is_file() else ""
    pre_cr_path = root / ".pre-cr.json"
    try:
        pre_cr = json.loads(pre_cr_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        quality_commands: list[object] = []
    else:
        raw_quality_commands = pre_cr.get("qualityCommands", [])
        quality_commands = (
            raw_quality_commands if isinstance(raw_quality_commands, list) else []
        )
    return {
        "schema_version": "environment-contract/v1",
        "as_of": as_of.isoformat(),
        "status": "pass" if not errors else "fail",
        "errors": errors,
        "checks": {
            "required_files": len(REQUIRED_FILES)
            - sum(not (root / path).is_file() for path in REQUIRED_FILES),
            "context_packets": len(PACKETS) - len(missing_packets),
            "context_packets_required": len(PACKETS),
            "declared_commands": sum(
                command in commands_text
                for command in REQUIRED_COMMANDS
            ),
            "declared_commands_required": len(REQUIRED_COMMANDS),
            "quality_commands": sum(
                command in quality_commands
                for command in REQUIRED_QUALITY_COMMANDS
            ),
            "quality_commands_required": len(REQUIRED_QUALITY_COMMANDS),
            "tracked_secret_paths": len(secret_paths),
            "required_pre_cr_adapter": not any(
                "environment-contract pre-CR" in error for error in errors
            ),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--as-of", type=date.fromisoformat, default=date.today())
    args = parser.parse_args()
    result = validate(args.root.expanduser().resolve(), args.as_of)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
