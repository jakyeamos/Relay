from __future__ import annotations

import importlib.util
import tempfile
import unittest
from datetime import date
from pathlib import Path


def _load_checker():
    path = Path(__file__).with_name("check_environment_contract.py")
    spec = importlib.util.spec_from_file_location("relay_environment_contract", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load environment contract checker")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CHECKER = _load_checker()


class EnvironmentContractTests(unittest.TestCase):
    def test_repository_contract_passes(self) -> None:
        root = Path(__file__).parents[1]
        result = CHECKER.validate(root, date(2026, 7, 22), tracked_paths=[])
        self.assertEqual(result["status"], "pass")

    def test_missing_packet_and_broken_link_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            index = root / ".agents" / "context"
            index.mkdir(parents=True)
            (root / "AGENTS.md").write_text("# router\n", encoding="utf-8")
            (index / "README.md").write_text(
                "last_reviewed: 2026-07-22\n[missing](missing.md)\n",
                encoding="utf-8",
            )
            result = CHECKER.validate(root, date(2026, 7, 22), tracked_paths=[])
            self.assertEqual(result["status"], "fail")
            self.assertIn("broken context link: missing.md", result["errors"])
            self.assertIn("missing context packet: architecture.md", result["errors"])

    def test_stale_index_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            index = root / ".agents" / "context"
            index.mkdir(parents=True)
            (root / "AGENTS.md").write_text("# router\n", encoding="utf-8")
            (index / "README.md").write_text("last_reviewed: 2025-01-01\n", encoding="utf-8")
            for packet in CHECKER.PACKETS:
                (index / packet).write_text("# packet\n", encoding="utf-8")
            result = CHECKER.validate(root, date(2026, 7, 22), tracked_paths=[])
            self.assertEqual(result["status"], "fail")
            self.assertTrue(any("context index is stale" in item for item in result["errors"]))

    def test_metadata_requires_all_targets_and_adapter(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            for path in CHECKER.REQUIRED_FILES:
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("placeholder\n", encoding="utf-8")
            (root / "Package.swift").write_text("RelayCore RelayApp\n", encoding="utf-8")
            (root / ".pre-cr.json").write_text('{"qualityAdapters": []}\n', encoding="utf-8")
            context = root / ".agents" / "context"
            context.mkdir(parents=True)
            (context / "README.md").write_text("last_reviewed: 2026-07-22\n", encoding="utf-8")
            for packet in CHECKER.PACKETS:
                (context / packet).write_text("# packet\n", encoding="utf-8")
            result = CHECKER.validate(root, date(2026, 7, 22), tracked_paths=[])
            self.assertEqual(result["status"], "fail")
            self.assertIn("required environment-contract pre-CR adapter is missing", result["errors"])
            self.assertTrue(any("RelayHelper" in item for item in result["errors"]))

    def test_secret_path_guard_allows_examples(self) -> None:
        self.assertEqual(CHECKER.check_secret_paths([".env.example", ".env.template"]), [])
        self.assertEqual(
            CHECKER.check_secret_paths(["config/production.env", "keys/id_rsa"]),
            ["config/production.env", "keys/id_rsa"],
        )


if __name__ == "__main__":
    unittest.main()
