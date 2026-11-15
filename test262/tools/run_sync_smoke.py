#!/usr/bin/env python3
"""Phase 4 integration checks against a supplied Test262 review checkout."""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess
import sys
import unittest

TEST262 = Path(__file__).resolve().parent.parent
RUNNER = TEST262 / "tools" / "run_test262.py"
SMOKE_LIST = TEST262 / "config" / "smoke-tests.txt"


def without_duration(value):
    if isinstance(value, dict):
        return {key: without_duration(item) for key, item in value.items() if key != "durationMs"}
    if isinstance(value, list):
        return [without_duration(item) for item in value]
    return value


class SynchronousSmoke(unittest.TestCase):
    root: Path

    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(cls.root).resolve()
        if not (cls.root / "test").is_dir() or not (cls.root / "harness").is_dir():
            raise unittest.SkipTest("an existing Test262 review checkout is required")

    def execute(self, *tests: str, extra: list[str] | None = None) -> tuple[list[dict], int, str]:
        command = [
            sys.executable,
            str(RUNNER),
            "--root",
            str(self.root),
            "--allow-unpinned",
            "--timeout",
            "2",
            *tests,
        ]
        if extra:
            command.extend(extra)
        process = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", check=False)
        records = [json.loads(line) for line in process.stdout.splitlines()]
        return records, process.returncode, process.stderr

    def execute_smoke_list(self) -> tuple[list[dict], int, str]:
        return self.execute(extra=["--list", str(SMOKE_LIST)])

    def test_reviewed_upstream_smoke_is_reproducible(self) -> None:
        first, status, summary = self.execute_smoke_list()
        second, second_status, _ = self.execute_smoke_list()
        self.assertEqual(status, 0)
        self.assertEqual(second_status, 0)
        self.assertEqual(len(first), 15)
        counts = Counter(result["outcome"] for result in first)
        self.assertEqual(counts, {"pass": 15})
        self.assertIn("Summary: pass=15", summary)
        self.assertEqual(without_duration(first), without_duration(second))
        for result in first:
            self.assertEqual(result["outcome"], "pass")
            self.assertEqual(result["hostExitCode"], 0)
            self.assertTrue(result["preparationOnly"] is False)
            self.assertEqual(result["hostResult"]["outcome"], "pass")
            if result["variant"] == "strict":
                self.assertIn("--strict", result["hostCommand"])
            else:
                self.assertNotIn("--strict", result["hostCommand"])

    def test_harness_order_and_metadata_comments(self) -> None:
        records, status, _ = self.execute("language/expressions/addition/S11.6.1_A2.1_T1.js")
        self.assertEqual(status, 0)
        self.assertEqual(records[0]["outcome"], "pass")
        self.assertEqual(
            [Path(path).name for path in records[0]["harness"]],
            ["assert.js", "sta.js"],
        )
        self.assertEqual(records[0]["hostResult"]["sourceName"], records[0]["source"]["name"])
        self.assertTrue(records[0]["metadata"]["hasFrontmatter"])

    def test_deliberate_assert_is_a_real_failure_not_a_harness_error(self) -> None:
        records, status, _ = self.execute("local/assert-failure.js")
        self.assertEqual(status, 0)
        self.assertEqual(records[0]["outcome"], "fail")
        self.assertEqual(records[0]["hostExitCode"], 1)
        self.assertEqual(records[0]["hostResult"]["sourceRole"], "test")
        self.assertEqual(records[1]["outcome"], "fail")
        self.assertEqual(records[1]["variant"], "strict")

    def test_include_failure_is_a_setup_error_with_source_location(self) -> None:
        records, status, _ = self.execute("local/include-throws.js")
        self.assertEqual(status, 2)
        self.assertEqual(records[0]["outcome"], "harness-error")
        self.assertEqual(records[0]["hostExitCode"], 3)
        self.assertEqual(records[0]["hostResult"]["sourceRole"], "harness")
        self.assertEqual(records[0]["hostResult"]["sourceIndex"], 2)
        self.assertEqual(records[0]["hostResult"]["printOutput"], [])

    def test_missing_include_is_a_planning_harness_error(self) -> None:
        records, status, _ = self.execute("local/missing-include.js")
        self.assertEqual(status, 2)
        self.assertEqual(records[0]["outcome"], "harness-error")
        self.assertIsNone(records[0]["hostExitCode"])
        self.assertEqual(records[0]["hostCommand"], [])

    def test_negative_expectation_is_verified(self) -> None:
        records, status, _ = self.execute("local/negative.js")
        self.assertEqual(status, 0)
        self.assertEqual(records[0]["outcome"], "pass")
        self.assertEqual(records[0]["hostResult"]["outcome"], "fail")
        self.assertEqual(records[0]["hostResult"]["phase"], "runtime")
        self.assertEqual(records[0]["hostResult"]["error"]["name"], "TypeError")
        self.assertEqual(records[0]["metadata"]["negative"], {"phase": "runtime", "type": "TypeError"})
        self.assertEqual(records[1]["outcome"], "pass")
        self.assertEqual(records[1]["variant"], "strict")
        self.assertIn("--strict", records[1]["hostCommand"])

    def test_parallel_execution_is_deterministic(self) -> None:
        sequential, status, _ = self.execute(extra=["--list", str(SMOKE_LIST)])
        parallel, parallel_status, _ = self.execute(
            extra=["--list", str(SMOKE_LIST), "--jobs", "4"]
        )
        self.assertEqual(status, 0)
        self.assertEqual(parallel_status, 0)
        self.assertEqual(len(sequential), 15)
        self.assertEqual(without_duration(sequential), without_duration(parallel))
        self.assertEqual(
            [record["scenarioId"] for record in sequential],
            [record["scenarioId"] for record in parallel],
        )

    def test_global_deadline_bounds_the_run(self) -> None:
        records, status, _ = self.execute(
            "local/infinite-loop.js",
            extra=["--timeout", "2", "--max-duration", "0.1"],
        )
        self.assertEqual(status, 2)
        self.assertEqual(records[0]["outcome"], "timeout")
        self.assertIn("global run deadline", records[0]["reason"])

    def test_external_timeout_is_classified_and_reaped(self) -> None:
        records, status, _ = self.execute("local/infinite-loop.js", extra=["--timeout", "0.1"])
        self.assertEqual(status, 2)
        self.assertEqual(records[0]["outcome"], "timeout")
        self.assertIn("deadline", records[0]["reason"])

    def test_missing_json_is_a_crash_not_a_language_failure(self) -> None:
        records, status, _ = self.execute(
            "language/expressions/addition/S11.6.1_A2.1_T1.js",
            extra=["--host", "/bin/false"],
        )
        self.assertEqual(status, 2)
        self.assertEqual(records[0]["outcome"], "crash")
        self.assertEqual(records[0]["hostExitCode"], 1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path, help="existing Test262 review checkout")
    arguments = parser.parse_args()
    SynchronousSmoke.root = arguments.root
    unittest.main(argv=[sys.argv[0]], verbosity=2)
