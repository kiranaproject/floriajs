#!/usr/bin/env python3
"""Phase 10.9 module bundling fixtures; no external checkout required."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import unittest

TEST262 = Path(__file__).resolve().parent.parent
ROOT = TEST262 / "fixtures" / "metadata"
RUNNER = TEST262 / "tools" / "run_test262.py"


def run(*tests: str) -> tuple[list[dict], int, str]:
    process = subprocess.run(
        [sys.executable, str(RUNNER), "--root", str(ROOT), "--allow-unpinned",
         "--timeout", "2", *tests],
        capture_output=True, text=True, encoding="utf-8", check=False,
    )
    return [json.loads(line) for line in process.stdout.splitlines()], process.returncode, process.stderr


class ModuleFixtures(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.records, cls.status, cls.summary = run("module-main.js")
        cls.record = cls.records[0]

    def test_relative_imports_exports_and_namespace(self) -> None:
        self.assertEqual(self.record["outcome"], "pass")
        self.assertEqual(self.record["variant"], "module")
        self.assertTrue(self.record["moduleBundle"])
        self.assertEqual(
            self.record["moduleGraph"],
            ["test/module-dep.js", "test/module-star.js", "test/module-main.js"],
        )
        self.assertIn("--strict", self.record["hostCommand"])
        self.assertEqual(self.record["hostResult"]["outcome"], "pass")

    def test_live_bindings_and_cycles(self) -> None:
        for name in ("module-live-main.js", "module-cycle-main.js", "module-meta-main.js", "module-json-main.js", "module-text-main.js"):
            records, status, _ = run(name)
            self.assertEqual(status, 0, name)
            self.assertEqual(records[0]["outcome"], "pass", name)
            self.assertTrue(records[0]["moduleBundle"], name)

    def test_missing_module_is_a_resolution_error(self) -> None:
        records, status, _ = run("module-missing.js")
        self.assertEqual(status, 2)
        self.assertEqual(records[0]["outcome"], "harness-error")
        self.assertIn("module graph", records[0]["reason"])
        self.assertIn("cannot resolve module", records[0]["reason"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
