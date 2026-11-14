#!/usr/bin/env python3
"""Phase 7 limited-async fixtures; no external Test262 checkout required."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import unittest

TEST262 = Path(__file__).resolve().parent.parent
ROOT = TEST262 / "fixtures" / "async"
RUNNER = TEST262 / "tools" / "run_test262.py"

CASES = [
    "complete.js",
    "failure.js",
    "missing.js",
    "repeated.js",
    "timer-complete.js",
    "timer-cancel.js",
    "timer-interval.js",
    "timer-order.js",
    "timer-pending.js",
]


def run(timeout: str = "1.0") -> tuple[list[dict], int, str]:
    process = subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--root",
            str(ROOT),
            "--allow-unpinned",
            "--timeout",
            timeout,
            *CASES,
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    return [json.loads(line) for line in process.stdout.splitlines()], process.returncode, process.stderr


class AsyncFixtures(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.records, cls.status, cls.summary = run()
        cls.by_path: dict[str, list[dict]] = {}
        for record in cls.records:
            cls.by_path.setdefault(record["testPath"], []).append(record)

    def test_completion_uses_done_harness_and_passes(self) -> None:
        normal, strict = self.by_path["complete.js"]
        self.assertEqual(normal["outcome"], "pass")
        self.assertEqual(normal["reason"], "async-complete")
        self.assertEqual(
            [Path(item).name for item in normal["harness"]],
            ["assert.js", "sta.js", "doneprintHandle.js"],
        )
        self.assertIn("--async", normal["hostCommand"])
        self.assertEqual(
            normal["hostResult"]["printOutput"],
            ["1,2", "Test262:AsyncTestComplete"],
        )
        self.assertEqual(strict["outcome"], "pass")
        self.assertIn("--strict", strict["hostCommand"])
        self.assertEqual(
            [Path(item).name for item in strict["harness"]],
            ["assert.js", "sta.js", "doneprintHandle.js"],
        )

    def test_async_failure_keeps_the_reported_error(self) -> None:
        record = self.by_path["failure.js"][0]
        self.assertEqual(record["outcome"], "fail")
        self.assertEqual(record["reason"], "async-failure")
        self.assertEqual(record["hostResult"]["reason"], "async-failure")
        self.assertEqual(record["hostResult"]["error"]["name"], "TypeError")
        self.assertEqual(record["hostResult"]["error"]["message"], "expected async failure")

    def test_repeated_completion_fails(self) -> None:
        record = self.by_path["repeated.js"][0]
        self.assertEqual(record["outcome"], "fail")
        self.assertEqual(record["hostResult"]["reason"], "async-completion-repeated")
        self.assertIn("reported 2 times", record["hostResult"]["error"]["message"])

    def test_missing_completion_times_out_rather_than_passing(self) -> None:
        record = self.by_path["missing.js"][0]
        self.assertEqual(record["outcome"], "timeout")
        self.assertIn("deadline", record["reason"])
        self.assertEqual(record["hostResult"], {"stdout": "", "stderr": ""})

    def test_timer_completion_and_cancellation(self) -> None:
        complete = self.by_path["timer-complete.js"][0]
        self.assertEqual(complete["outcome"], "pass")
        self.assertEqual(
            complete["hostResult"]["printOutput"],
            ["x,y", "Test262:AsyncTestComplete"],
        )

        cancelled = self.by_path["timer-cancel.js"][0]
        self.assertEqual(cancelled["outcome"], "pass")
        self.assertEqual(
            cancelled["hostResult"]["printOutput"],
            ["cancelled-blocked", "Test262:AsyncTestComplete"],
        )

    def test_timers_run_in_scheduling_order(self) -> None:
        record = self.by_path["timer-order.js"][0]
        self.assertEqual(record["outcome"], "pass")
        self.assertEqual(
            record["hostResult"]["printOutput"],
            ["1,2", "Test262:AsyncTestComplete"],
        )

    def test_interval_runs_until_cleared(self) -> None:
        record = self.by_path["timer-interval.js"][0]
        self.assertEqual(record["outcome"], "pass")
        self.assertEqual(
            record["hostResult"]["printOutput"],
            ["count=3", "Test262:AsyncTestComplete"],
        )

    def test_pending_timer_is_not_completion(self) -> None:
        record = self.by_path["timer-pending.js"][0]
        self.assertEqual(record["outcome"], "timeout")
        self.assertIn("deadline", record["reason"])

    def test_summary_keeps_async_outcomes_visible(self) -> None:
        self.assertEqual(self.status, 2)  # deliberate missing completions timed out
        self.assertIn("pass=10", self.summary)
        self.assertIn("fail=4", self.summary)
        self.assertNotIn("skipped=", self.summary)
        self.assertIn("timeout=4", self.summary)


if __name__ == "__main__":
    unittest.main(verbosity=2)
