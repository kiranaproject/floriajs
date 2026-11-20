#!/usr/bin/env python3
"""Assertion-only fixtures for Phase 3 metadata and scenario preparation."""

from __future__ import annotations

from hashlib import sha256
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

TEST262 = Path(__file__).resolve().parent.parent
ROOT = TEST262 / "fixtures" / "metadata"
PREPARE = TEST262 / "tools" / "prepare_test262.py"
sys.path.insert(0, str(TEST262 / "tools"))

from frontmatter import FrontmatterError, parse_yaml_block  # noqa: E402
from scenario import PlanningError, validate_checkout  # noqa: E402


def plans(*tests: str, extra: list[str] | None = None) -> tuple[list[dict], int]:
    command = [
        sys.executable,
        str(PREPARE),
        "--root",
        str(ROOT),
        "--allow-unpinned",
        *tests,
    ]
    if extra:
        command.extend(extra)
    process = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", check=False)
    if process.stderr:
        raise AssertionError(process.stderr)
    return [json.loads(line) for line in process.stdout.splitlines()], process.returncode


class MetadataFixtures(unittest.TestCase):
    def test_default_expands_to_non_strict_and_strict_scenarios(self) -> None:
        records, status = plans("default.js")
        self.assertEqual(status, 0)
        self.assertEqual(len(records), 2)
        normal, strict = records
        self.assertEqual(normal["outcome"], "planned")
        self.assertEqual(normal["variant"], "non-strict")
        self.assertEqual(strict["outcome"], "planned")
        self.assertEqual(strict["variant"], "strict")
        expected = ["assert.js", "sta.js", "second.js", "first.js"]
        self.assertEqual([Path(p).name for p in normal["harness"]], expected)
        self.assertEqual([Path(p).name for p in strict["harness"]], expected)
        self.assertNotIn("--strict", normal["hostCommand"])
        self.assertIn("--strict", strict["hostCommand"])

    def test_no_strict_runs_once_with_standard_harness(self) -> None:
        records, _ = plans("no-strict.js")
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["variant"], "non-strict")
        self.assertEqual([Path(p).name for p in records[0]["harness"]], ["assert.js", "sta.js"])

    def test_raw_has_no_harness_even_when_includes_are_missing(self) -> None:
        records, _ = plans("raw.js")
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["variant"], "raw")
        self.assertEqual(records[0]["harness"], [])
        self.assertNotIn("--harness", records[0]["hostCommand"])
        self.assertEqual(records[0]["metadata"]["includes"], ["missing-but-ignored.js"])

    def test_only_strict_and_module_scenarios_are_executable(self) -> None:
        strict, _ = plans("only-strict.js")
        module, _ = plans("module.js")
        self.assertEqual(strict[0]["variant"], "strict")
        self.assertEqual(strict[0]["outcome"], "planned")
        self.assertIn("--strict", strict[0]["hostCommand"])
        self.assertEqual(module[0]["variant"], "module")
        self.assertEqual(module[0]["outcome"], "planned")
        self.assertIn("--module", module[0]["hostCommand"])
        self.assertIn("--strict", module[0]["hostCommand"])

    def test_default_async_runs_both_modes_with_done_harness(self) -> None:
        records, _ = plans("async.js")
        self.assertEqual([(r["variant"], r["outcome"]) for r in records], [
            ("non-strict", "planned"),
            ("strict", "planned"),
        ])
        normal, strict = records
        for record in records:
            self.assertEqual(
                [Path(item).name for item in record["harness"]],
                ["assert.js", "sta.js", "doneprintHandle.js"],
            )
            self.assertIn("--async", record["hostCommand"])
        self.assertNotIn("--strict", normal["hostCommand"])
        self.assertIn("--strict", strict["hostCommand"])

    def test_supported_262_members_remain_executable(self) -> None:
        records, _ = plans("eval-script.js")
        self.assertEqual(records[0]["outcome"], "planned")
        self.assertIn("--test", records[0]["hostCommand"])

        records, _ = plans("host-create-realm.js")
        self.assertEqual(records[0]["outcome"], "planned")
        self.assertIn("--test", records[0]["hostCommand"])

        records, _ = plans("host-agent.js")
        self.assertEqual(records[0]["outcome"], "planned")
        self.assertIn("--test", records[0]["hostCommand"])

    def test_unsupported_262_members_are_explicit(self) -> None:
        for name, reason_fragment in (
            ("host-gc.js", "host-gc-required"),
        ):
            records, _ = plans(name)
            self.assertEqual(records[0]["outcome"], "unsupported", name)
            self.assertIn(reason_fragment, records[0]["reason"])
            self.assertEqual(records[0]["hostCommand"], [])

    def test_fixture_is_excluded_before_metadata_or_variant_expansion(self) -> None:
        records, _ = plans("example_FIXTURE.js")
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["outcome"], "skipped")
        self.assertEqual(records[0]["variant"], "")
        self.assertEqual(records[0]["testPath"], "example_FIXTURE.js")

    def test_intl_directories_and_other_staging(self) -> None:
        for relative in ("intl402/example.js", "staging/intl402/example.js"):
            records, _ = plans(relative)
            self.assertTrue(all(r["outcome"] == "skipped" for r in records))
        ordinary, _ = plans("staging/ordinary.js")
        self.assertEqual(len(ordinary), 1)
        self.assertEqual(ordinary[0]["outcome"], "planned")

    def test_unsupported_features_and_includes_cover_both_modes(self) -> None:
        records, _ = plans("weakref-feature.js")
        self.assertTrue(all(record["outcome"] == "unsupported" for record in records))
        self.assertTrue(all(not record["hostCommand"] for record in records))

        helper, _ = plans("property-helper.js")
        self.assertTrue(all(record["outcome"] == "planned" for record in helper))
        self.assertTrue(all("propertyHelper.js" in [Path(item).name for item in record["harness"]] for record in helper))

    def test_can_block_requires_an_unsupported_agent(self) -> None:
        records, _ = plans("can-block.js")
        self.assertTrue(all(r["outcome"] == "skipped" for r in records))
        self.assertTrue(all(not r["hostCommand"] for r in records))

    def test_missing_include_is_a_harness_error(self) -> None:
        records, status = plans("missing-include.js")
        self.assertEqual(status, 2)
        self.assertEqual(records[0]["outcome"], "harness-error")
        self.assertEqual(records[0]["hostCommand"], [])

    def test_invalid_metadata_never_falls_back_to_default(self) -> None:
        tests = [
            "invalid-flags.js",
            "invalid-includes.js",
            "traversal.js",
            "duplicate-key.js",
            "invalid-negative.js",
            "conflicting.js",
            "unknown-flag.js",
            "multiple-frontmatter.js",
            "invalid-utf8.js",
            "unsafe-yaml.js",
        ]
        records, status = plans(*tests)
        self.assertEqual(status, 2)
        self.assertEqual(len(records), len(tests))
        self.assertTrue(all(r["outcome"] == "harness-error" for r in records))
        self.assertTrue(all(not r["hostCommand"] for r in records))

    def test_negative_metadata_is_preserved_not_evaluated(self) -> None:
        records, _ = plans("negative.js")
        self.assertEqual(records[0]["metadata"]["negative"], {"phase": "runtime", "type": "TypeError"})
        self.assertEqual(records[0]["outcome"], "planned")
        self.assertNotEqual(records[0]["outcome"], "pass")

    def test_negative_resolution_is_planned_and_run(self) -> None:
        # The engine reports a module link failure as a distinct resolution
        # phase, so a resolution negative is a real scenario rather than a
        # declared gap.
        records, _ = plans("negative-resolution.js")
        self.assertEqual(len(records), 2)
        normal, strict = records
        self.assertEqual(normal["outcome"], "planned")
        self.assertEqual(normal["metadata"]["negative"]["phase"], "resolution")
        self.assertNotEqual(normal["hostCommand"], [])
        self.assertEqual(strict["outcome"], "planned")
        self.assertEqual(strict["variant"], "strict")

    def test_crlf_and_raw_bytes_are_preserved(self) -> None:
        original = (ROOT / "test" / "raw-crlf.js").read_bytes()
        records, _ = plans("raw-crlf.js")
        self.assertEqual(records[0]["source"]["bytes"], len(original))
        self.assertEqual(records[0]["source"]["sha256"], sha256(original).hexdigest())
        self.assertEqual(records[0]["variant"], "raw")

    def test_locale_and_informational_flags_are_preserved(self) -> None:
        records, _ = plans("locale.js")
        self.assertEqual(records[0]["metadata"]["locale"], ["en-US", "ar"])
        self.assertTrue(records[0]["metadata"]["nonDeterministic"])

    def test_spaces_and_metacharacters_stay_in_one_argument(self) -> None:
        records, _ = plans("space name.js")
        command = records[0]["hostCommand"]
        self.assertIsInstance(command, list)
        self.assertEqual(command[-1], str(ROOT / "test" / "space name.js"))

    def test_duplicate_yaml_keys_are_rejected(self) -> None:
        with self.assertRaises(FrontmatterError):
            parse_yaml_block("negative:\n  phase: runtime\n  phase: parse\n  type: TypeError\n")

    def test_revision_is_required_without_explicit_fixture_permission(self) -> None:
        process = subprocess.run(
            [sys.executable, str(PREPARE), "--root", str(ROOT), "default.js"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )
        self.assertEqual(process.returncode, 2)
        result = json.loads(process.stdout)
        self.assertEqual(result["outcome"], "harness-error")
        self.assertIn("revision", result["reason"])

    def test_git_inspection_is_read_only(self) -> None:
        pin = "2e58f87d8350ad51224617a041c6e041d52f8444"
        root = str(ROOT.resolve())
        responses = [
            subprocess.CompletedProcess([], 0, pin + "\n", ""),
            subprocess.CompletedProcess([], 0, root + "\n", ""),
            subprocess.CompletedProcess([], 0, "", ""),
        ]
        with mock.patch("scenario.subprocess.run", side_effect=responses) as execute:
            result = validate_checkout(ROOT, pin, False)
        self.assertTrue(result["revisionVerified"])
        for call in execute.call_args_list:
            argv = call.args[0]
            self.assertIn("--no-optional-locks", argv)
            self.assertTrue(set(argv).isdisjoint({"clone", "fetch", "pull", "checkout", "reset", "clean", "config"}))

    def test_revision_mismatch_is_not_repaired(self) -> None:
        pin = "2e58f87d8350ad51224617a041c6e041d52f8444"
        response = subprocess.CompletedProcess([], 0, "0" * 40 + "\n", "")
        with mock.patch("scenario.subprocess.run", return_value=response):
            with self.assertRaises(PlanningError):
                validate_checkout(ROOT, pin, False)

    def test_list_files_and_repeated_plans_are_deterministic(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST262 / "target") as directory:
            list_file = Path(directory) / "selection.txt"
            list_file.write_text("# fixture selection\ndefault.js\nraw.js\n", encoding="utf-8")
            first, _ = plans(extra=["--list", str(list_file)])
            second, _ = plans(extra=["--list", str(list_file)])
        self.assertEqual(first, second)
        self.assertEqual(len(first), 3)

    def test_planning_does_not_modify_sources(self) -> None:
        names = ["default.js", "raw.js", "raw-crlf.js", "negative.js"]
        before = {name: sha256((ROOT / "test" / name).read_bytes()).hexdigest() for name in names}
        plans(*names)
        after = {name: sha256((ROOT / "test" / name).read_bytes()).hexdigest() for name in names}
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main(verbosity=2)
