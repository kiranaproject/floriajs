#!/usr/bin/env python3
"""Prepare Test262 scenarios without executing JavaScript or assigning verdicts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from scenario import PlanningError, ScenarioPlanner, safe_relative, validate_checkout

TEST262 = Path(__file__).resolve().parent.parent


def global_error(policy_name: str, error: Exception) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "preparationOnly": True,
        "policyName": policy_name,
        "testPath": "",
        "variant": "",
        "scenarioId": "",
        "outcome": "harness-error",
        "reason": str(error),
        "hostCommand": [],
    }


def selection(path: Path) -> list[str]:
    """Read path-list comments/blank lines, preserving the declared order."""
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "tests",
        nargs="*",
        help="paths relative to the root's test/ directory (comments are not paths)",
    )
    parser.add_argument("--root", type=Path, default=TEST262 / ".upstream")
    parser.add_argument("--host", type=Path, default=TEST262 / "target" / "floria-test262-host")
    parser.add_argument("--policy", type=Path, default=TEST262 / "config" / "feature-policy.json")
    parser.add_argument("--revision", type=Path, default=TEST262 / "config" / "test262-revision.txt")
    parser.add_argument("--list", type=Path, help="file containing test/relative paths, one per line")
    parser.add_argument(
        "--allow-unpinned",
        action="store_true",
        help="permit a non-Git fixture root; never use this for official conformance results",
    )
    args = parser.parse_args()

    policy_name = "unloaded-policy"
    try:
        policy = json.loads(args.policy.read_text(encoding="utf-8"))
        if not isinstance(policy, dict) or "policyName" not in policy:
            raise PlanningError("invalid Test262 feature policy")
        policy_name = policy["policyName"]
        revision_lines = args.revision.read_text(encoding="utf-8").splitlines()
        if not revision_lines:
            raise PlanningError("empty Test262 revision pin")
        expected_revision = revision_lines[-1].strip()
        if len(expected_revision) != 40 or any(char not in "0123456789abcdef" for char in expected_revision):
            raise PlanningError("invalid Test262 revision pin")

        upstream = validate_checkout(args.root, expected_revision, args.allow_unpinned)
        tests = list(args.tests)
        if args.list:
            tests.extend(selection(args.list))
        if not tests:
            raise PlanningError("no test paths supplied")

        # Validate every supplied path before producing any plans. This also
        # prevents accidental absolute-path inputs or metacharacter-based paths.
        for test in tests:
            safe_relative(test)

        planner = ScenarioPlanner(upstream, policy, args.host.resolve())
        outcomes: list[dict[str, object]] = []
        for test in tests:
            outcomes.extend(planner.prepare(test))
    except (PlanningError, OSError, ValueError) as error:
        outcomes = [global_error(policy_name, error)]

    for outcome in outcomes:
        print(json.dumps(outcome, ensure_ascii=False, separators=(",", ":")))

    return 2 if any(item["outcome"] == "harness-error" for item in outcomes) else 0


if __name__ == "__main__":
    raise SystemExit(main())
