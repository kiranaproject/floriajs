#!/usr/bin/env python3
"""Run the Phase 2 one-scenario host against authored fixtures.

This is a fixture checker, not the Test262 metadata orchestrator. Every scenario
uses a new subprocess and a timeout. It never accepts host text as a verdict
without first parsing exactly one JSON result.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

TEST262 = Path(__file__).resolve().parent.parent
FIXTURES = TEST262 / "fixtures" / "host"


def path(name: str) -> str:
    return (FIXTURES / name).relative_to(TEST262).as_posix()


def options(*sources: tuple[str, str] | str) -> list[str]:
    args: list[str] = []
    for source in sources:
        if isinstance(source, tuple):
            role, filename = source
            args.extend((f"--{role}", filename))
        else:
            args.extend(("--test", source))
    return args


def subset(expected: Any, actual: Any, path_name: str = "result") -> None:
    """Require expected object members; arrays and scalar values must match."""
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            raise AssertionError(f"{path_name}: expected an object, got {actual!r}")
        for key, value in expected.items():
            if key not in actual:
                raise AssertionError(f"{path_name}: missing {key}")
            subset(value, actual[key], f"{path_name}.{key}")
    elif expected != actual:
        raise AssertionError(f"{path_name}: expected {expected!r}, got {actual!r}")


def invoke(host: Path, args: list[str], timeout: float) -> tuple[dict[str, Any], int]:
    process = subprocess.run(
        [str(host), *args],
        cwd=TEST262,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=timeout,
        check=False,
    )
    if process.stderr:
        raise AssertionError(f"unexpected stderr: {process.stderr.strip()}")

    output = process.stdout.strip()
    if not output:
        raise AssertionError(f"host emitted no JSON (exit {process.returncode})")
    if len(output.splitlines()) != 1:
        raise AssertionError("host emitted more than one JSON record")

    try:
        result = json.loads(output)
    except json.JSONDecodeError as error:
        raise AssertionError(f"invalid JSON output: {error}: {output!r}") from error

    if not isinstance(result, dict):
        raise AssertionError("host result is not a JSON object")
    if result.get("schemaVersion") != 1:
        raise AssertionError(f"unsupported result schema: {result.get('schemaVersion')}")
    if not isinstance(result.get("durationMs"), int) or result["durationMs"] < 0:
        raise AssertionError("durationMs must be a nonnegative integer")
    return result, process.returncode


def validate(host: Path, case: dict[str, Any], timeout: float) -> None:
    if "timeout" in case:
        try:
            subprocess.run(
                [str(host), *case["args"]],
                cwd=TEST262,
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=case["timeout"],
                check=False,
            )
        except subprocess.TimeoutExpired:
            return
        raise AssertionError("expected the host to remain pending until the external deadline")

    result, exit_code = invoke(host, case["args"], timeout)
    expected_exit = case["exit"]
    if exit_code != expected_exit:
        raise AssertionError(f"expected exit {expected_exit}, got {exit_code}")
    subset(case["result"], result)

    for key, value in case.get("assertions", {}).items():
        if key == "positiveColumn":
            if result["error"]["column"] <= 0:
                raise AssertionError("expected a positive parser column")
        elif key == "sourceIOWithoutClass":
            if result["error"]["hostExceptionClass"] != "":
                raise AssertionError("missing files should not have a synthetic exception class")
        else:
            raise AssertionError(f"unknown fixture assertion: {key}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--host",
        type=Path,
        default=TEST262 / "target" / "floria-test262-host",
        help="path to the host executable",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=3.0,
        help="per-scenario subprocess timeout in seconds (default: 3)",
    )
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")

    cases: list[dict[str, Any]] = [
        {
            "name": "positive completion",
            "args": options(path("pass.js")),
            "exit": 0,
            "result": {
                "scenarioId": "pass",
                "outcome": "pass",
                "phase": "success",
                "sourceRole": "test",
                "sourceName": path("pass.js"),
                "legacyResult": {"success": True, "stringValue": "42", "errorMessage": ""},
            },
        },
        {
            "name": "console and print preserve exact channels and Unicode",
            "args": options(path("console-output.js")),
            "exit": 0,
            "result": {
                "outcome": "pass",
                "consoleOutput": ["console message"],
                "printOutput": ['quotes " \\ \n\t', "", "héllo"],
            },
        },
        {
            "name": "JavaScript error object",
            "args": options(path("runtime-throw.js")),
            "exit": 1,
            "result": {
                "outcome": "fail",
                "phase": "runtime",
                "sourceRole": "test",
                "sourceIndex": 0,
                "error": {"name": "TypeError", "message": "boom"},
                "legacyResult": {"errorMessage": "TypeError: boom"},
            },
        },
        {
            "name": "primitive throw has no invented error constructor",
            "args": options(path("primitive-throw.js")),
            "exit": 1,
            "result": {
                "outcome": "fail",
                "phase": "runtime",
                "error": {"name": "", "message": "boom"},
            },
        },
        {
            "name": "parse phase and location",
            "args": options(path("parse-error.js")),
            "exit": 1,
            "result": {
                "outcome": "fail",
                "phase": "parse",
                "error": {"name": "SyntaxError", "line": 1},
            },
            "assertions": {"positiveColumn": True},
        },
        {
            "name": "compiler early-error phase",
            "args": options(path("compile-error.js")),
            "exit": 1,
            "result": {
                "outcome": "fail",
                "phase": "compile",
                "error": {"name": "SyntaxError", "line": 0, "column": 0},
            },
        },
        {
            "name": "ordered harness files and same-context globals",
            "args": ["--scenario-id", "ordering", *options(
                ("harness", path("harness-one.js")),
                ("harness", path("harness-two.js")),
                path("ordered-test.js"),
            )],
            "exit": 0,
            "result": {
                "scenarioId": "ordering",
                "outcome": "pass",
                "printOutput": ["h1", "h2", "test"],
                "legacyResult": {"stringValue": "h1,h2,test"},
            },
        },
        {
            "name": "harness failure stops test evaluation",
            "args": options(
                ("harness", path("harness-before-failure.js")),
                ("harness", path("harness-failure.js")),
                path("never-run.js"),
            ),
            "exit": 3,
            "result": {
                "outcome": "harness-error",
                "phase": "runtime",
                "sourceRole": "harness",
                "sourceIndex": 1,
                "error": {"name": "SyntaxError", "message": "harness boom"},
                "printOutput": ["before-harness"],
            },
        },
        {
            "name": "missing harness source",
            "args": options(
                ("harness", path("does-not-exist.js")),
                path("never-run.js"),
            ),
            "exit": 3,
            "result": {
                "outcome": "harness-error",
                "phase": "host",
                "reason": "source-io",
                "sourceRole": "harness",
                "sourceIndex": 0,
                "sourceName": path("does-not-exist.js"),
                "printOutput": [],
            },
            "assertions": {"sourceIOWithoutClass": True},
        },
        {
            "name": "missing test source",
            "args": options(path("does-not-exist.js")),
            "exit": 3,
            "result": {
                "outcome": "harness-error",
                "phase": "host",
                "sourceRole": "test",
                "sourceIndex": 0,
                "sourceName": path("does-not-exist.js"),
            },
        },
        {
            "name": "source directory is a host I/O failure, not a crash",
            "args": options("fixtures"),
            "exit": 3,
            "result": {
                "outcome": "harness-error",
                "phase": "host",
                "sourceRole": "test",
                "sourceName": "fixtures",
            },
        },
        {
            "name": "each source evaluates exactly once",
            "args": options(path("evaluate-once.js")),
            "exit": 0,
            "result": {
                "outcome": "pass",
                "printOutput": ["1"],
                "legacyResult": {"stringValue": "1"},
            },
        },
        {
            "name": "minimal host API does not expose fake capabilities",
            "args": options(path("capabilities.js")),
            "exit": 0,
            "result": {
                "outcome": "pass",
                "printOutput": [
                    "object",
                    "object",
                    "function",
                    "function",
                    "object",
                    "undefined",
                    "undefined",
                ],
            },
        },
        {
            "name": "$262.agent starts a cooperative agent and returns its report",
            "args": options(path("agent.js")),
            "exit": 0,
            "result": {
                "outcome": "pass",
                "printOutput": ["agent-ok"],
            },
        },
        {
            "name": "$262.createRealm returns an isolated realm with its own intrinsics",
            "args": options(path("realm.js")),
            "exit": 0,
            "result": {
                "outcome": "pass",
                "printOutput": ["true false"],
            },
        },
        {
            "name": "raw scenario without harness",
            "args": ["--variant", "raw", *options(path("pass.js"))],
            "exit": 0,
            "result": {"variant": "raw", "outcome": "pass"},
        },
        {
            "name": "raw scenario rejects harness",
            "args": ["--variant", "raw", *options(
                ("harness", path("harness-one.js")), path("pass.js")
            )],
            "exit": 2,
            "result": {"outcome": "harness-error", "reason": "invalid-arguments"},
        },
        {
            "name": "no arguments is a structured usage failure",
            "args": [],
            "exit": 2,
            "result": {
                "outcome": "harness-error",
                "phase": "host",
                "reason": "invalid-arguments",
                "sourceRole": "host",
            },
        },
        {
            "name": "unknown argument is rejected before evaluation",
            "args": ["--not-a-real-option", *options(path("pass.js"))],
            "exit": 2,
            "result": {"outcome": "harness-error", "reason": "invalid-arguments"},
        },
        {
            "name": "missing option value is rejected",
            "args": ["--test"],
            "exit": 2,
            "result": {"outcome": "harness-error", "reason": "invalid-arguments"},
        },
        {
            "name": "duplicate test is rejected",
            "args": [*options(path("pass.js")), *options(path("pass.js"))],
            "exit": 2,
            "result": {"outcome": "harness-error", "reason": "invalid-arguments"},
        },
        {
            "name": "strict mode rejects assignment to an undeclared name",
            "args": ["--strict", *options(path("strict-undeclared.js"))],
            "exit": 1,
            "result": {
                "outcome": "fail",
                "phase": "runtime",
                "error": {"name": "ReferenceError"},
            },
        },
        {
            "name": "non-strict mode keeps the existing global-assignment behavior",
            "args": options(path("strict-undeclared.js")),
            "exit": 0,
            "result": {"outcome": "pass"},
        },
        {
            "name": "a use-strict directive enables strict mode without --strict",
            "args": options(path("strict-directive.js")),
            "exit": 1,
            "result": {
                "outcome": "fail",
                "error": {"name": "ReferenceError"},
            },
        },
        {
            "name": "duplicate parameters are a strict-mode early error",
            "args": ["--strict", *options(path("strict-duplicate-param.js"))],
            "exit": 1,
            "result": {
                "outcome": "fail",
                "phase": "compile",
                "error": {"name": "SyntaxError"},
            },
        },
        {
            "name": "raw strict mode is rejected rather than simulated",
            "args": ["--variant", "raw", "--strict", *options(path("pass.js"))],
            "exit": 2,
            "result": {"outcome": "harness-error", "reason": "invalid-arguments"},
        },
        {
            "name": "async completion after chained promise jobs",
            "args": [
                "--async",
                *options(
                    ("harness", path("doneprintHandle.js")),
                    "fixtures/async/test/complete.js",
                ),
            ],
            "exit": 0,
            "result": {
                "outcome": "pass",
                "phase": "success",
                "reason": "async-complete",
                "printOutput": ["1,2", "Test262:AsyncTestComplete"],
            },
        },
        {
            "name": "async failure reports the done-print reason",
            "args": [
                "--async",
                *options(
                    ("harness", path("doneprintHandle.js")),
                    "fixtures/async/test/failure.js",
                ),
            ],
            "exit": 1,
            "result": {
                "outcome": "fail",
                "phase": "runtime",
                "reason": "async-failure",
                "error": {"name": "TypeError", "message": "expected async failure"},
                "printOutput": ["Test262:AsyncTestFailure:TypeError: expected async failure"],
            },
        },
        {
            "name": "async repeated completion is rejected",
            "args": [
                "--async",
                *options(
                    ("harness", path("doneprintHandle.js")),
                    "fixtures/async/test/repeated.js",
                ),
            ],
            "exit": 1,
            "result": {
                "outcome": "fail",
                "phase": "runtime",
                "reason": "async-completion-repeated",
                "error": {"message": "async completion was reported 2 times"},
            },
        },
        {
            "name": "$262.global exposes the global snapshot and evalScript returns values and errors",
            "args": options(path("eval-script.js")),
            "exit": 0,
            "result": {
                "outcome": "pass",
                "printOutput": ["object", "true", "42", "41", "TypeError:nested boom", "SyntaxError"],
            },
        },
        {
            "name": "evalScript does not drain microtasks prematurely",
            "args": options(path("eval-script-order.js")),
            "exit": 0,
            "result": {
                "outcome": "pass",
                "printOutput": ["nested,after,microtask"],
            },
        },
        {
            "name": "evalScript is re-entrant and returns unpinned values safely",
            "args": options(path("eval-script-reentrant.js")),
            "exit": 0,
            "result": {
                "outcome": "pass",
                "printOutput": ["197", "3"],
            },
        },
        {
            "name": "pending timers do not run unless the host pumps",
            "args": options(path("timer-pending.js")),
            "exit": 0,
            "result": {
                "outcome": "pass",
                "printOutput": [],
                "legacyResult": {"success": True},
            },
        },
        {
            "name": "async timer completion is pumped by the host",
            "args": [
                "--async",
                *options(
                    ("harness", path("doneprintHandle.js")),
                    "fixtures/async/test/timer-complete.js",
                ),
            ],
            "exit": 0,
            "result": {
                "outcome": "pass",
                "reason": "async-complete",
                "printOutput": ["x,y", "Test262:AsyncTestComplete"],
            },
        },
        {
            "name": "async missing completion waits for the external deadline",
            "args": [
                "--async",
                *options(
                    ("harness", path("doneprintHandle.js")),
                    "fixtures/async/test/missing.js",
                ),
            ],
            "timeout": 0.25,
        },
        {
            "name": "raw async scenario is rejected",
            "args": [
                "--variant", "raw",
                "--async",
                *options(path("pass.js")),
            ],
            "exit": 2,
            "result": {"outcome": "harness-error", "reason": "invalid-arguments"},
        },
    ]

    failures: list[str] = []
    for case in cases:
        try:
            validate(args.host, case, args.timeout)
        except (AssertionError, subprocess.SubprocessError, OSError) as error:
            failures.append(f"{case['name']}: {error}")
            print(f"FAIL {case['name']}")
        else:
            print(f"PASS {case['name']}")

    # This check deliberately has no host JSON verdict. The external supervisor
    # must kill/reap the child and classify the deadline itself.
    try:
        subprocess.run(
            [str(args.host), "--test", path("infinite-loop.js")],
            cwd=TEST262,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=min(args.timeout, 0.25),
            check=False,
        )
        failures.append("timeout enforcement: an infinite loop returned instead of timing out")
        print("FAIL timeout enforcement")
    except subprocess.TimeoutExpired:
        print("PASS timeout enforcement")
    except (subprocess.SubprocessError, OSError) as error:
        failures.append(f"timeout enforcement: {error}")
        print("FAIL timeout enforcement")

    if failures:
        print("\nFailures:\n  - " + "\n  - ".join(failures), file=sys.stderr)
        return 1

    print(f"\n{len(cases)} host fixture checks and 1 timeout check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
