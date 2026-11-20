#!/usr/bin/env python3
"""Phase 5 negative-verdict fixtures; no external Test262 checkout required."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import unittest

TEST262 = Path(__file__).resolve().parent.parent
ROOT = TEST262 / "fixtures" / "negative"
RUNNER = TEST262 / "tools" / "run_test262.py"

CASES = [
    "parse-syntax.js",
    "compile-early.js",
    "runtime-type.js",
    "raw-runtime.js",
    "wrong-phase.js",
    "wrong-type.js",
    "normal-completion.js",
    "parse-type.js",
    "dont-evaluate.js",
    "module.js",
    "async.js",
    "only-strict.js",
    "unsupported-feature.js",
    "unsupported-parse-feature.js",
    "include-error.js",
]


def without_duration(value):
    if isinstance(value, dict):
        return {key: without_duration(item) for key, item in value.items() if key != "durationMs"}
    if isinstance(value, list):
        return [without_duration(item) for item in value]
    return value


def run() -> tuple[list[dict], int, str]:
    process = subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--root",
            str(ROOT),
            "--allow-unpinned",
            "--timeout",
            "2",
            *CASES,
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    return [json.loads(line) for line in process.stdout.splitlines()], process.returncode, process.stderr


class NegativeVerdicts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.records, cls.status, cls.summary = run()
        cls.by_path = {}
        for record in cls.records:
            cls.by_path.setdefault(record["testPath"], []).append(record)

    def test_parse_and_compile_early_errors_pass(self) -> None:
        for name in ("parse-syntax.js", "compile-early.js"):
            record = self.by_path[name][0]
            self.assertEqual(record["outcome"], "pass", name)
            self.assertEqual(record["hostResult"]["outcome"], "fail")
            self.assertEqual(record["hostResult"]["phase"], "parse" if name == "parse-syntax.js" else "compile")
            self.assertEqual(record["hostResult"]["error"]["name"], "SyntaxError")
            self.assertEqual(record["metadata"]["negative"], {"phase": "parse", "type": "SyntaxError"})

    def test_runtime_and_raw_runtime_errors_pass(self) -> None:
        for name in ("runtime-type.js", "raw-runtime.js"):
            record = self.by_path[name][0]
            self.assertEqual(record["outcome"], "pass", name)
            self.assertEqual(record["hostResult"]["phase"], "runtime")
            self.assertEqual(record["hostResult"]["error"]["name"], "TypeError")
            self.assertEqual(record["hostResult"]["outcome"], "fail")

    def test_async_negative_test_runs_in_both_modes(self) -> None:
        normal, strict = self.by_path["async.js"]
        for record in (normal, strict):
            self.assertEqual(record["outcome"], "pass")
            self.assertEqual(record["metadata"]["negative"], {"phase": "runtime", "type": "TypeError"})
            self.assertEqual(
                [Path(item).name for item in record["harness"]],
                ["assert.js", "sta.js", "doneprintHandle.js"],
            )
            self.assertIn("--async", record["hostCommand"])
            self.assertEqual(record["hostResult"]["phase"], "runtime")
            self.assertEqual(record["hostResult"]["error"]["name"], "TypeError")
        self.assertIn("--strict", strict["hostCommand"])
        self.assertNotIn("--strict", normal["hostCommand"])

    def test_wrong_phase_wrong_type_and_normal_completion_fail(self) -> None:
        expected = {
            "wrong-phase.js": "negative expectation mismatch",
            "wrong-type.js": "negative expectation mismatch",
            "normal-completion.js": "negative test completed normally",
            "parse-type.js": "negative expectation mismatch",
        }
        for name, reason in expected.items():
            record = self.by_path[name][0]
            self.assertEqual(record["outcome"], "fail", name)
            self.assertIn(reason, record["reason"])

    def test_runtime_type_error_cannot_satisfy_parse_type_error(self) -> None:
        record = self.by_path["parse-type.js"][0]
        self.assertEqual(record["outcome"], "fail")
        self.assertEqual(record["hostResult"]["phase"], "runtime")
        self.assertEqual(record["hostResult"]["error"]["name"], "TypeError")
        self.assertIn("expected parse TypeError, got runtime TypeError", record["reason"])

    def test_dont_evaluate_does_not_satisfy_parse_expectation(self) -> None:
        record = self.by_path["dont-evaluate.js"][0]
        self.assertEqual(record["outcome"], "fail")
        self.assertIn("$DONOTEVALUATE() was reached", record["reason"])
        self.assertIn("must not be evaluated", record["reason"])
        self.assertEqual(record["hostResult"]["phase"], "runtime")
        self.assertIn(
            "Test262: This statement should not be evaluated.",
            record["hostResult"]["error"]["message"],
        )

    def test_skipped_and_unsupported_negative_tests_do_not_run(self) -> None:
        module = self.by_path["module.js"][0]
        self.assertEqual(module["variant"], "module")
        self.assertEqual(module["outcome"], "fail")
        self.assertIn("completed normally", module["reason"])

        only_strict = self.by_path["only-strict.js"][0]
        self.assertEqual(only_strict["variant"], "strict")
        self.assertEqual(only_strict["outcome"], "fail")
        self.assertIn("--strict", only_strict["hostCommand"])

        for record in self.by_path["unsupported-feature.js"]:
            self.assertEqual(record["outcome"], "unsupported")
            self.assertEqual(record["hostCommand"], [])
            self.assertIsNone(record["hostResult"])

    def test_parser_limitation_is_not_an_expected_early_error(self) -> None:
        record = self.by_path["unsupported-parse-feature.js"][0]
        self.assertEqual(record["outcome"], "unsupported")
        self.assertEqual(record["hostResult"]["phase"], "parse")
        self.assertEqual(record["hostResult"]["error"]["name"], "SyntaxError")
        self.assertIn("not implemented", record["reason"])
        self.assertIn("not supported", record["reason"])

    def test_harness_failure_is_not_a_negative_pass(self) -> None:
        record = self.by_path["include-error.js"][0]
        self.assertEqual(record["outcome"], "harness-error")
        self.assertEqual(record["hostResult"]["sourceRole"], "harness")
        self.assertEqual(record["hostResult"]["sourceIndex"], 2)

    def test_summary_and_repeatability(self) -> None:
        self.assertEqual(self.status, 2)  # include-error is an infrastructure failure
        self.assertIn("pass=9", self.summary)
        self.assertIn("fail=12", self.summary)
        self.assertNotIn("skipped=", self.summary)
        self.assertIn("unsupported=4", self.summary)
        self.assertIn("harness-error=2", self.summary)
        second, second_status, _ = run()
        self.assertEqual(second_status, self.status)
        self.assertEqual(without_duration(self.records), without_duration(second))


if __name__ == "__main__":
    unittest.main(verbosity=2)
