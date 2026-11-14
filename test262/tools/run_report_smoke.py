#!/usr/bin/env python3
"""Phase 6 report, summary, and baseline-diff fixtures; no upstream checkout needed."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TEST262 = Path(__file__).resolve().parent.parent
ROOT = TEST262 / "fixtures" / "negative"
RUNNER = TEST262 / "tools" / "run_test262.py"
RESULTS = TEST262 / "tools" / "results.py"
sys.path.insert(0, str(TEST262 / "tools"))

from results import baseline_report, compare_reports, outcome_counts  # noqa: E402

CASES = [
    "parse-syntax.js",
    "runtime-type.js",
    "wrong-phase.js",
    "unsupported-feature.js",
    "include-error.js",
]


def run_runner(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(RUNNER), "--root", str(ROOT), "--allow-unpinned", "--timeout", "2", *arguments],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )


def records_of(stdout: str) -> list[dict]:
    return [json.loads(line) for line in stdout.splitlines() if line.strip()]


class ReportFixtures(unittest.TestCase):
    def test_report_metadata_jsonl_and_summary(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            report_path = base / "report.json"
            output_path = base / "records.jsonl"
            process = run_runner(
                [
                    "--report", str(report_path),
                    "--output", str(output_path),
                    *CASES,
                ]
            )

            self.assertEqual(process.returncode, 2)  # include-error is infrastructure
            records = records_of(process.stdout)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            written = records_of(output_path.read_text(encoding="utf-8"))

            self.assertEqual(written, records)
            self.assertEqual(report["kind"], "floriajs-test262-report")
            self.assertEqual(report["schemaVersion"], 1)
            self.assertEqual(report["runnerVersion"], "0.6.0")
            self.assertTrue(report["engine"]["revision"])
            self.assertIsInstance(report["engine"]["workingTreeDirty"], bool)
            self.assertFalse(report["upstream"]["revisionVerified"])
            self.assertEqual(report["policy"]["name"], "floriajs-diagnostic-subset")
            self.assertEqual(report["policy"]["status"], "phase-10.10-modules-text-json")
            self.assertTrue(report["policy"]["sha256"])
            self.assertTrue(report["host"]["sha256"])
            self.assertTrue(report["platform"]["system"])
            self.assertTrue(report["platform"]["python"])
            self.assertEqual(report["options"]["timeoutSeconds"], 2)
            self.assertTrue(report["options"]["allowUnpinned"])
            self.assertEqual(report["options"]["selection"], CASES)

            summary = report["summary"]
            self.assertEqual(summary["outcomes"], outcome_counts(records))
            self.assertEqual(summary["coverage"]["infrastructure"], 2)
            self.assertEqual(summary["outcomes"]["harness-error"], 2)
            self.assertEqual(summary["directories"]["."]["total"], len(records))
            self.assertIn("WeakRef", summary["features"])
            self.assertEqual(summary["features"]["WeakRef"]["outcomes"]["unsupported"], 2)
            self.assertIsNotNone(summary["attemptedPassRate"])

    def test_baseline_normalization_is_portable_and_repeatable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            first_path = base / "first.json"
            second_path = base / "second.json"
            for path in (first_path, second_path):
                process = run_runner(["--report", str(path), *CASES])
                self.assertEqual(process.returncode, 2)

            first = baseline_report(json.loads(first_path.read_text(encoding="utf-8")))
            second = baseline_report(json.loads(second_path.read_text(encoding="utf-8")))
            self.assertEqual(first, second)
            self.assertTrue(first["baseline"])
            self.assertNotIn("generatedAt", first)
            self.assertNotIn("root", first["upstream"])
            self.assertNotIn("path", first["host"])
            serialized = json.dumps(first)
            self.assertNotIn(str(ROOT), serialized)
            self.assertNotIn("durationMs", serialized)
            self.assertEqual(first["records"], sorted(first["records"], key=lambda r: r["scenarioId"]))

    def _report(self, directory: Path) -> dict:
        path = directory / "report.json"
        process = run_runner(["--report", str(path), *CASES])
        self.assertIn(process.returncode, {0, 2})
        return json.loads(path.read_text(encoding="utf-8"))

    def test_diff_detects_regressions_improvements_and_infrastructure(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            report = self._report(Path(temporary))
            baseline = baseline_report(report)
            current = json.loads(json.dumps(report))
            passed = next(record for record in current["records"] if record["outcome"] == "pass")
            failed = next(record for record in current["records"] if record["outcome"] == "fail")
            unsupported = next(
                record for record in current["records"] if record["outcome"] == "unsupported"
            )
            passed["outcome"] = "fail"
            failed["outcome"] = "pass"
            unsupported["outcome"] = "pass"
            crashed = json.loads(json.dumps(passed))
            crashed["scenarioId"] = "added-crash.js::non-strict"
            crashed["testPath"] = "added-crash.js"
            crashed["outcome"] = "crash"
            current["records"].append(crashed)

            diff = compare_reports(baseline, current)
            categories = {entry["category"] for entry in diff["changes"]}
            self.assertIn("new-failure", categories)
            self.assertIn("failure-fixed", categories)
            self.assertIn("unsupported-to-supported", categories)
            self.assertIn("added-crash", {entry["category"] for entry in diff["added"]})
            self.assertTrue(diff["regression"])
            self.assertEqual(len(diff["regressions"]), 2)
            self.assertEqual(diff["counts"]["current"]["crash"], 1)

    def test_compare_cli_exits_three_on_regression(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            report = self._report(base)
            baseline_path = base / "baseline.json"
            current_path = base / "current.json"
            baseline_path.write_text(json.dumps(baseline_report(report)), encoding="utf-8")
            current = json.loads(json.dumps(report))
            next(record for record in current["records"] if record["outcome"] == "pass")[
                "outcome"
            ] = "fail"
            current_path.write_text(json.dumps(current), encoding="utf-8")

            process = subprocess.run(
                [
                    sys.executable,
                    str(RESULTS),
                    "compare",
                    str(baseline_path),
                    str(current_path),
                    "--fail-on-regression",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
                check=False,
            )
            self.assertEqual(process.returncode, 3)
            self.assertIn("REGRESSIONS", process.stdout)

    def test_missing_checkout_fails_without_executing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            empty = Path(temporary)
            process = subprocess.run(
                [
                    sys.executable,
                    str(RUNNER),
                    "--root",
                    str(empty),
                    "--allow-unpinned",
                    "parse-syntax.js",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
                check=False,
            )
            self.assertEqual(process.returncode, 2)
            records = records_of(process.stdout)
            self.assertEqual(len(records), 1)
            self.assertEqual(records[0]["outcome"], "harness-error")
            self.assertIn("root must contain test/ and harness/", records[0]["reason"])
            self.assertFalse(records[0].get("hostCommand"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
