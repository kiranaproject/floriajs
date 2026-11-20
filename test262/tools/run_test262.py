#!/usr/bin/env python3
"""Execute synchronous Test262 scenarios and apply positive/negative verdicts."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from prepare_test262 import global_error, selection
from results import (
    build_report,
    compare_reports,
    engine_metadata,
    format_diff,
    host_metadata,
    load_report,
    platform_metadata,
    policy_metadata,
    write_jsonl,
    write_report,
)
from scenario import PlanningError, ScenarioPlanner, safe_relative, validate_checkout

TEST262 = Path(__file__).resolve().parent.parent


def partial_text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def execution_result(plan: dict, outcome: str, reason: str,
                     host_result: dict | None = None, host_exit_code: int | None = None) -> dict:
    result = dict(plan)
    result["preparationOnly"] = False
    result["executionPhase"] = "synchronous"
    result["outcome"] = outcome
    result["reason"] = reason
    result["hostExitCode"] = host_exit_code
    result["hostResult"] = host_result
    return result


NEGATIVE_DEFAULTS = {
    "acceptedParsePhases": ["parse", "compile"],
    "runtimePhase": "runtime",
    "resolutionReason": "negative resolution expectations are not classified by the host module loader",
    "dontEvaluateMarker": "Test262: This statement should not be evaluated.",
    "unsupportedParseErrorPatterns": ["not supported", "unsupported"],
}


def negative_policy(policy: dict) -> dict:
    configured = policy.get("negativeVerdicts")
    if not isinstance(configured, dict):
        return dict(NEGATIVE_DEFAULTS)
    result = dict(NEGATIVE_DEFAULTS)
    result.update(configured)
    return result


def apply_negative_verdict(plan: dict, result: dict, config: dict) -> dict:
    """Compare a completed host result with Test262 negative metadata.

    A negative test passes only when the required error occurs, in the test
    source itself, at the required phase, with the required constructor name.
    A parser limitation is not evidence for a specification early error, so a
    parse failure whose message identifies an unsupported construct is
    reported as `unsupported` rather than as an expected parse verdict.
    """
    expected = plan["metadata"]["negative"]
    if not expected:
        return result
    if result["outcome"] in {"harness-error", "crash", "timeout"}:
        return result

    host = result.get("hostResult")
    if not isinstance(host, dict):
        return execution_result(plan, "crash", "negative test produced no host result")

    expected_phase = expected["phase"]
    expected_type = expected["type"]
    actual_phase = host.get("phase", "")
    error = host.get("error") or {}
    actual_name = error.get("name", "")
    actual_message = error.get("message", "")
    exit_code = result.get("hostExitCode")

    if expected_phase == "resolution":
        # The specification's Link phase throws a SyntaxError for an unresolved,
        # missing, or ambiguous import. The engine reports that distinctly from a
        # parse error, so a resolution phase can be judged rather than skipped.
        if actual_phase == "resolution" and actual_name == expected_type:
            return execution_result(
                plan,
                "pass",
                f"negative expectation matched: {expected_phase} {expected_type}",
                host,
                exit_code,
            )
        if host.get("outcome") != "pass" and actual_phase in {"parse", "compile"}:
            return execution_result(
                plan,
                "unsupported",
                config["resolutionReason"],
                host,
                exit_code,
            )
        return execution_result(
            plan,
            "fail",
            "negative expectation mismatch: expected "
            f"{expected_phase} {expected_type}, got "
            f"{actual_phase} {actual_name or '<no error name>'}",
            host,
            exit_code,
        )

    marker = config.get("dontEvaluateMarker", "")
    if marker and marker in actual_message:
        return execution_result(
            plan,
            "fail",
            "$DONOTEVALUATE() was reached; the test must not be evaluated when "
            f"{expected_phase} {expected_type} is required",
            host,
            exit_code,
        )

    if host.get("outcome") == "pass":
        return execution_result(
            plan,
            "fail",
            f"negative test completed normally; expected {expected_phase} {expected_type}",
            host,
            exit_code,
        )

    accepted_parse_phases = set(config.get("acceptedParsePhases", ["parse", "compile"]))
    if expected_phase == "parse" and actual_phase in accepted_parse_phases:
        message = actual_message.casefold()
        for pattern in config.get("unsupportedParseErrorPatterns", []):
            if pattern and pattern.casefold() in message:
                return execution_result(
                    plan,
                    "unsupported",
                    "parse failed inside a parser feature that is not implemented: "
                    f"{actual_message}",
                    host,
                    exit_code,
                )

    if expected_phase == "parse":
        phase_matches = actual_phase in accepted_parse_phases
    elif expected_phase == "runtime":
        phase_matches = actual_phase == config.get("runtimePhase", "runtime")
    elif expected_phase == "resolution":
        phase_matches = actual_phase == "resolution"
    else:
        phase_matches = False

    type_matches = actual_name == expected_type
    if phase_matches and type_matches:
        return execution_result(
            plan,
            "pass",
            f"negative expectation matched: {expected_phase} {expected_type}",
            host,
            exit_code,
        )

    actual = f"{actual_phase} {actual_name or '<no error name>'}"
    return execution_result(
        plan,
        "fail",
        f"negative expectation mismatch: expected {expected_phase} {expected_type}, got {actual}",
        host,
        exit_code,
    )


def remaining_timeout(timeout: float, deadline: float | None) -> float:
    """Return the effective timeout, bounded by an optional global deadline."""
    if deadline is None:
        return timeout
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return 0.0
    return min(timeout, remaining)


def execute_plan(plan: dict, timeout: float,
                 deadline: float | None = None) -> dict:
    effective_timeout = remaining_timeout(timeout, deadline)
    if effective_timeout <= 0:
        return execution_result(
            plan,
            "timeout",
            "global run deadline was reached before the scenario started",
        )
    try:
        process = subprocess.run(
            plan["hostCommand"],
            cwd=TEST262,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=effective_timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        reason = f"scenario exceeded its {effective_timeout:g}-second deadline and was killed"
        if deadline is not None and effective_timeout < timeout:
            reason += " (bounded by the global run deadline)"
        return execution_result(
            plan,
            "timeout",
            reason,
            {
                "stdout": partial_text(error.stdout),
                "stderr": partial_text(error.stderr),
            },
        )
    except (OSError, subprocess.SubprocessError) as error:
        return execution_result(plan, "crash", f"host execution failed: {error}")

    stdout = process.stdout.strip()
    if not stdout:
        return execution_result(
            plan,
            "crash",
            f"host exited {process.returncode} without a JSON result; stderr: {process.stderr.strip()}",
            host_exit_code=process.returncode,
        )
    if len(stdout.splitlines()) != 1:
        return execution_result(plan, "crash", "host emitted multiple or malformed JSON records", host_exit_code=process.returncode)
    try:
        host_result = json.loads(stdout)
    except json.JSONDecodeError as error:
        return execution_result(plan, "crash", f"host emitted invalid JSON: {error}", host_exit_code=process.returncode)

    if not isinstance(host_result, dict) or host_result.get("outcome") not in {"pass", "fail", "harness-error"}:
        return execution_result(plan, "crash", "host returned an invalid result schema", host_exit_code=process.returncode)
    if process.stderr.strip():
        return execution_result(
            plan,
            "crash",
            f"host emitted unexpected stderr: {process.stderr.strip()}",
            host_result,
            process.returncode,
        )

    outcome = "harness-error" if host_result["outcome"] == "harness-error" else host_result["outcome"]
    return execution_result(plan, outcome, host_result.get("reason", ""), host_result, process.returncode)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", help="paths relative to the checkout's test/ directory")
    parser.add_argument("--root", type=Path, default=TEST262 / ".upstream")
    parser.add_argument("--host", type=Path, default=TEST262 / "target" / "floria-test262-host")
    parser.add_argument("--policy", type=Path, default=TEST262 / "config" / "feature-policy.json")
    parser.add_argument("--revision", type=Path, default=TEST262 / "config" / "test262-revision.txt")
    parser.add_argument("--list", type=Path, help="file containing test/relative paths")
    parser.add_argument("--timeout", type=float, default=5.0, help="per-scenario deadline in seconds")
    parser.add_argument(
        "--jobs",
        type=int,
        default=1,
        help="number of scenarios to execute concurrently (each in its own process)",
    )
    parser.add_argument(
        "--max-duration",
        type=float,
        default=0.0,
        help="optional global deadline in seconds for the whole run; 0 disables it",
    )
    parser.add_argument(
        "--allow-unpinned",
        action="store_true",
        help="allow a fixture root; never use this for official conformance results",
    )
    parser.add_argument("--output", type=Path, help="write the scenario records as JSONL")
    parser.add_argument("--report", type=Path, help="write the complete report as JSON")
    parser.add_argument("--baseline", type=Path, help="compare against a reviewed baseline report")
    parser.add_argument(
        "--fail-on-regression",
        action="store_true",
        help="exit 3 when the baseline comparison reports a regression",
    )
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    if args.max_duration < 0:
        parser.error("--max-duration must be zero or positive")
    deadline = time.monotonic() + args.max_duration if args.max_duration > 0 else None

    policy: dict | None = None
    policy_name = "unloaded-policy"
    upstream: dict = {}
    tests: list[str] = list(args.tests)
    baseline_data: dict | None = None
    try:
        if args.baseline:
            baseline_data = load_report(args.baseline)
        policy = json.loads(args.policy.read_text(encoding="utf-8"))
        if not isinstance(policy, dict) or "policyName" not in policy:
            raise PlanningError("invalid Test262 feature policy")
        policy_name = policy["policyName"]
        revision_lines = args.revision.read_text(encoding="utf-8").splitlines()
        if not revision_lines:
            raise PlanningError("empty Test262 revision pin")
        expected_revision = revision_lines[-1].strip()
        if len(expected_revision) != 40 or any(c not in "0123456789abcdef" for c in expected_revision):
            raise PlanningError("invalid Test262 revision pin")
        upstream = validate_checkout(args.root, expected_revision, args.allow_unpinned)

        if args.list:
            tests.extend(selection(args.list))
        if not tests:
            raise PlanningError("no test paths supplied")
        for test in tests:
            safe_relative(test)

        planner = ScenarioPlanner(upstream, policy, args.host.resolve())
        plans = [plan for test in tests for plan in planner.prepare(test)]
        if any(plan["outcome"] == "planned" for plan in plans):
            host = args.host.resolve()
            if not host.is_file() or not os.access(host, os.X_OK):
                raise PlanningError(f"host is not an executable file: {host}")
        negative_config = negative_policy(policy)

        def run_plan(plan: dict) -> dict:
            if plan["outcome"] != "planned":
                result = execution_result(plan, plan["outcome"], plan["reason"])
                result["hostCommand"] = []
                return result
            result = execute_plan(plan, args.timeout, deadline)
            return apply_negative_verdict(plan, result, negative_config)

        if args.jobs > 1 and len(plans) > 1:
            with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
                records = list(pool.map(run_plan, plans))
        else:
            records = [run_plan(plan) for plan in plans]
    except (PlanningError, OSError, ValueError) as error:
        records = [global_error(policy_name, error)]

    counts: dict[str, int] = {}
    for result in records:
        outcome = result["outcome"]
        counts[outcome] = counts.get(outcome, 0) + 1
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    print("Summary: " + ", ".join(f"{key}={counts[key]}" for key in sorted(counts)), file=sys.stderr)

    report = build_report(
        records,
        upstream=upstream,
        policy=policy_metadata(args.policy, policy),
        host=host_metadata(args.host.resolve()),
        engine=engine_metadata(TEST262.parent),
        platform_info=platform_metadata(),
        options={
            "timeoutSeconds": args.timeout,
            "jobs": args.jobs,
            "maxDurationSeconds": args.max_duration,
            "allowUnpinned": args.allow_unpinned,
            "selection": tests,
            "listFile": str(args.list) if args.list else None,
        },
    )
    if args.output:
        write_jsonl(args.output, records)
    if args.report:
        write_report(args.report, report)

    regression = False
    if baseline_data is not None:
        diff = compare_reports(baseline_data, report)
        print(format_diff(diff), file=sys.stderr)
        regression = diff["regression"]

    # Policy skips and genuine semantic failures are valid completed results;
    # setup, crash, and timeout failures make this invocation unsuccessful.
    # A reviewed baseline regression is distinct from infrastructure failure.
    if any(result["outcome"] in {"harness-error", "crash", "timeout"} for result in records):
        return 2
    if args.fail_on_regression and regression:
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
