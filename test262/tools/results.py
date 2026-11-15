"""Report schema, summaries, and reviewed baseline comparison for Test262 runs.

The runner writes one semantic record per scenario. This module adds the
surrounding report metadata, per-directory/per-feature summaries, and a
baseline diff that keeps infrastructure failures visible instead of folding
them into a generic expected-failure count.
"""

from __future__ import annotations

import argparse
from collections import Counter
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import subprocess
import sys
from typing import Any, Iterable

RUNNER_VERSION = "0.7.0"
REPORT_KIND = "floriajs-test262-report"
SCHEMA_VERSION = 1

OUTCOMES = ("pass", "fail", "unsupported", "skipped", "harness-error", "timeout", "crash")
INFRASTRUCTURE = ("harness-error", "timeout", "crash")
ATTEMPTED = ("pass", "fail")
REGRESSION_CATEGORIES = {
    "new-failure",
    "newly-attempted-failure",
    "new-harness-error",
    "new-timeout",
    "new-crash",
    "added-failure",
    "added-harness-error",
    "added-timeout",
    "added-crash",
}
COVERAGE_LOSS_CATEGORIES = {"supported-to-unsupported", "newly-skipped"}


class ReportError(ValueError):
    """A report or baseline cannot be interpreted deterministically."""


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path: Path) -> str | None:
    try:
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()
    except OSError:
        return None


def _git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str] | None:
    env = dict(os.environ)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    try:
        return subprocess.run(
            ["git", "--no-optional-locks", "-C", str(root), *arguments],
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=5,
            check=False,
            env=env,
        )
    except (OSError, subprocess.SubprocessError):
        return None


def engine_metadata(root: Path) -> dict[str, Any]:
    """Record the FloriaJS source revision without any clone/checkout action."""
    revision = None
    dirty = None
    commit = _git(root, "rev-parse", "--verify", "HEAD^{commit}")
    if commit is not None and commit.returncode == 0:
        revision = commit.stdout.strip() or None
        status = _git(root, "status", "--porcelain", "--", "src/main/pascal", "project.xml")
        if status is not None and status.returncode == 0:
            dirty = bool(status.stdout.strip())
    return {"revision": revision, "workingTreeDirty": dirty}


def host_metadata(path: Path) -> dict[str, Any]:
    info: dict[str, Any] = {"path": str(path), "sha256": sha256_file(path)}
    try:
        info["bytes"] = path.stat().st_size
    except OSError:
        info["bytes"] = None
    return info


def policy_metadata(path: Path, policy: dict[str, Any] | None) -> dict[str, Any]:
    info: dict[str, Any] = {
        "sha256": sha256_file(path),
        "name": (policy or {}).get("policyName"),
        "status": (policy or {}).get("status"),
    }
    return info


def platform_metadata() -> dict[str, Any]:
    return {
        "system": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "python": platform.python_version(),
    }


def outcome_counts(records: Iterable[dict[str, Any]]) -> dict[str, int]:
    counter: Counter[str] = Counter()
    for record in records:
        counter[record.get("outcome", "unknown")] += 1
    counts = {outcome: counter.get(outcome, 0) for outcome in OUTCOMES}
    for outcome, count in sorted(counter.items()):
        if outcome not in counts:
            counts[outcome] = count
    return counts


def bucket(records: list[dict[str, Any]]) -> dict[str, Any]:
    counts = outcome_counts(records)
    attempted = counts["pass"] + counts["fail"]
    return {
        "total": len(records),
        "outcomes": counts,
        "coverage": {
            "attempted": attempted,
            "pass": counts["pass"],
            "fail": counts["fail"],
            "skipped": counts["skipped"],
            "unsupported": counts["unsupported"],
            "infrastructure": sum(counts[outcome] for outcome in INFRASTRUCTURE),
        },
        "attemptedPassRate": round(counts["pass"] / attempted, 4) if attempted else None,
    }


def _directory_of(record: dict[str, Any]) -> str:
    path = record.get("testPath") or ""
    if not path:
        return "(unknown)"
    parent = PurePosixPath(path).parent.as_posix()
    return "." if parent in {"", "."} else parent


def summarize(records: list[dict[str, Any]]) -> dict[str, Any]:
    directories: dict[str, list[dict[str, Any]]] = {}
    features: dict[str, list[dict[str, Any]]] = {}
    for record in records:
        directories.setdefault(_directory_of(record), []).append(record)
        declared = (record.get("metadata") or {}).get("features") or []
        if not declared:
            declared = ["(none)"]
        for feature in declared:
            features.setdefault(feature, []).append(record)

    summary = bucket(records)
    summary["directories"] = {
        name: bucket(items) for name, items in sorted(directories.items())
    }
    summary["features"] = {
        name: bucket(items) for name, items in sorted(features.items())
    }
    return summary


def build_report(
    records: list[dict[str, Any]],
    *,
    upstream: dict[str, Any],
    policy: dict[str, Any],
    host: dict[str, Any],
    engine: dict[str, Any],
    platform_info: dict[str, Any],
    options: dict[str, Any],
    generated_at: str | None = None,
) -> dict[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": REPORT_KIND,
        "runnerVersion": RUNNER_VERSION,
        "generatedAt": generated_at or utc_timestamp(),
        "engine": engine,
        "upstream": upstream,
        "policy": policy,
        "host": host,
        "platform": platform_info,
        "options": options,
        "summary": summarize(records),
        "records": records,
    }


def write_jsonl(path: Path, records: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        for record in records:
            stream.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
            stream.write("\n")


def write_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def load_report(path: Path) -> dict[str, Any]:
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReportError(f"cannot read report {path}: {error}") from error
    if not isinstance(report, dict) or report.get("kind") != REPORT_KIND:
        raise ReportError(f"{path} is not a FloriaJS Test262 report")
    records = report.get("records")
    if not isinstance(records, list):
        raise ReportError(f"{path} has no record list")
    return report


def _stable_string(value: str) -> str:
    return Path(value).name if os.path.isabs(value) else value


def _baseline_record(record: dict[str, Any]) -> dict[str, Any]:
    stable = deepcopy(record)
    stable.pop("durationMs", None)
    record_upstream = stable.get("upstream")
    if isinstance(record_upstream, dict):
        record_upstream.pop("root", None)
    source = stable.get("source")
    if isinstance(source, dict):
        source.pop("name", None)
    stable["harness"] = [
        _stable_string(item) for item in stable.get("harness", []) if isinstance(item, str)
    ]
    stable["hostCommand"] = [
        _stable_string(item) for item in stable.get("hostCommand", []) if isinstance(item, str)
    ]
    host_result = stable.get("hostResult")
    if isinstance(host_result, dict):
        host_result.pop("durationMs", None)
        if isinstance(host_result.get("sourceName"), str):
            host_result["sourceName"] = _stable_string(host_result["sourceName"])
    return stable


def baseline_report(report: dict[str, Any]) -> dict[str, Any]:
    """Produce a portable, deterministic report suitable for review and check-in."""
    stable = deepcopy(report)
    stable.pop("generatedAt", None)
    stable["baseline"] = True
    upstream = stable.get("upstream")
    if isinstance(upstream, dict):
        upstream.pop("root", None)
    host = stable.get("host")
    if isinstance(host, dict):
        host.pop("path", None)
    options = stable.get("options")
    if isinstance(options, dict) and isinstance(options.get("listFile"), str):
        options["listFile"] = _stable_string(options["listFile"])
    records = [_baseline_record(record) for record in stable.get("records", [])]
    records.sort(key=lambda item: (item.get("scenarioId", ""), item.get("testPath", "")))
    stable["records"] = records
    stable["summary"] = summarize(records)
    return stable


def _record_map(report: dict[str, Any]) -> dict[str, dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    for record in report.get("records", []):
        scenario_id = record.get("scenarioId")
        if not scenario_id:
            raise ReportError("report contains a record without scenarioId")
        if scenario_id in records:
            raise ReportError(f"report contains duplicate scenarioId: {scenario_id}")
        records[scenario_id] = record
    return records


def _classify(from_outcome: str, to_outcome: str) -> str:
    if from_outcome == to_outcome:
        return "unchanged"
    if to_outcome == "pass":
        if from_outcome == "unsupported":
            return "unsupported-to-supported"
        if from_outcome == "skipped":
            return "skipped-to-supported"
        if from_outcome == "fail":
            return "failure-fixed"
        if from_outcome in INFRASTRUCTURE:
            return "infrastructure-recovered"
        return "new-pass"
    if to_outcome == "fail":
        if from_outcome == "pass":
            return "new-failure"
        if from_outcome in {"unsupported", "skipped"}:
            return "newly-attempted-failure"
        return "changed-failure"
    if to_outcome in INFRASTRUCTURE:
        return f"new-{to_outcome}"
    if to_outcome == "unsupported":
        return "supported-to-unsupported" if from_outcome in ATTEMPTED else "changed-to-unsupported"
    if to_outcome == "skipped":
        return "newly-skipped"
    return "changed"


def _added_category(outcome: str) -> str:
    if outcome == "fail":
        return "added-failure"
    return f"added-{outcome}"


def compare_reports(baseline: dict[str, Any], current: dict[str, Any]) -> dict[str, Any]:
    before = _record_map(baseline)
    after = _record_map(current)
    changes: list[dict[str, Any]] = []
    added: list[dict[str, Any]] = []
    removed: list[dict[str, Any]] = []
    regressions: list[dict[str, Any]] = []
    coverage_loss: list[dict[str, Any]] = []

    for scenario_id in sorted(set(before) | set(after)):
        if scenario_id not in before:
            record = after[scenario_id]
            entry = {
                "scenarioId": scenario_id,
                "testPath": record.get("testPath", ""),
                "outcome": record.get("outcome", ""),
                "reason": record.get("reason", ""),
                "category": _added_category(record.get("outcome", "")),
            }
            added.append(entry)
            if entry["category"] in REGRESSION_CATEGORIES:
                regressions.append(entry)
            continue
        if scenario_id not in after:
            record = before[scenario_id]
            removed.append({
                "scenarioId": scenario_id,
                "testPath": record.get("testPath", ""),
                "outcome": record.get("outcome", ""),
            })
            continue

        old = before[scenario_id]
        new = after[scenario_id]
        from_outcome = old.get("outcome", "")
        to_outcome = new.get("outcome", "")
        if from_outcome == to_outcome:
            continue
        category = _classify(from_outcome, to_outcome)
        entry = {
            "scenarioId": scenario_id,
            "testPath": new.get("testPath", ""),
            "from": from_outcome,
            "to": to_outcome,
            "category": category,
            "reason": new.get("reason", ""),
        }
        changes.append(entry)
        if category in REGRESSION_CATEGORIES:
            regressions.append(entry)
        if category in COVERAGE_LOSS_CATEGORIES:
            coverage_loss.append(entry)

    before_counts = outcome_counts(before.values())
    after_counts = outcome_counts(after.values())
    delta = {
        outcome: after_counts[outcome] - before_counts[outcome] for outcome in after_counts
    }

    def identity(report: dict[str, Any]) -> dict[str, Any]:
        upstream = report.get("upstream") or {}
        engine = report.get("engine") or {}
        return {
            "runnerVersion": report.get("runnerVersion"),
            "engineRevision": engine.get("revision"),
            "upstreamRevision": upstream.get("actualRevision") or upstream.get("expectedRevision"),
            "recordCount": len(report.get("records", [])),
        }

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "floriajs-test262-diff",
        "baseline": identity(baseline),
        "current": identity(current),
        "counts": {"baseline": before_counts, "current": after_counts, "delta": delta},
        "added": added,
        "removed": removed,
        "changes": changes,
        "regressions": regressions,
        "coverageLoss": coverage_loss,
        "regression": bool(regressions),
    }


def _format_outcomes(counts: dict[str, int]) -> str:
    return ", ".join(f"{outcome}={counts[outcome]}" for outcome in OUTCOMES if counts.get(outcome))


def format_diff(diff: dict[str, Any]) -> str:
    lines = ["Test262 baseline diff"]
    baseline = diff["baseline"]
    current = diff["current"]
    lines.append(
        f"  baseline: {baseline['recordCount']} records, engine {baseline['engineRevision'] or 'unknown'}, "
        f"upstream {baseline['upstreamRevision'] or 'unpinned'}"
    )
    lines.append(
        f"  current:  {current['recordCount']} records, engine {current['engineRevision'] or 'unknown'}, "
        f"upstream {current['upstreamRevision'] or 'unpinned'}"
    )
    lines.append(f"  baseline outcomes: {_format_outcomes(diff['counts']['baseline']) or 'none'}")
    lines.append(f"  current outcomes:  {_format_outcomes(diff['counts']['current']) or 'none'}")

    if diff["regressions"]:
        lines.append(f"  REGRESSIONS ({len(diff['regressions'])}):")
        for entry in diff["regressions"]:
            if "from" in entry:
                lines.append(
                    f"    [{entry['category']}] {entry['scenarioId']}: "
                    f"{entry['from']} -> {entry['to']}"
                )
            else:
                lines.append(f"    [{entry['category']}] {entry['scenarioId']}: {entry['outcome']}")
    else:
        lines.append("  Regressions: none")

    improvements = [
        entry for entry in diff["changes"]
        if entry["category"] in {
            "new-pass",
            "unsupported-to-supported",
            "skipped-to-supported",
            "failure-fixed",
            "infrastructure-recovered",
        }
    ]
    if improvements:
        lines.append(f"  Improvements ({len(improvements)}):")
        for entry in improvements:
            lines.append(
                f"    [{entry['category']}] {entry['scenarioId']}: "
                f"{entry['from']} -> {entry['to']}"
            )

    if diff["coverageLoss"]:
        lines.append(f"  Coverage loss ({len(diff['coverageLoss'])}):")
        for entry in diff["coverageLoss"]:
            lines.append(
                f"    [{entry['category']}] {entry['scenarioId']}: "
                f"{entry['from']} -> {entry['to']}"
            )

    if diff["added"]:
        lines.append(f"  Added ({len(diff['added'])}):")
        for entry in diff["added"]:
            lines.append(f"    {entry['scenarioId']}: {entry['outcome']}")
    if diff["removed"]:
        lines.append(f"  Removed ({len(diff['removed'])}):")
        for entry in diff["removed"]:
            lines.append(f"    {entry['scenarioId']}: {entry['outcome']}")

    other = [
        entry for entry in diff["changes"]
        if entry not in improvements
        and entry not in diff["coverageLoss"]
        and entry not in diff["regressions"]
    ]
    if other:
        lines.append(f"  Other changes ({len(other)}):")
        for entry in other:
            lines.append(
                f"    [{entry['category']}] {entry['scenarioId']}: "
                f"{entry['from']} -> {entry['to']}"
            )
    return "\n".join(lines)


def _md_cell(value: Any) -> str:
    text = "" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", " ")


def _md_rate(value: Any) -> str:
    if value is None:
        return "n/a"
    return f"{float(value) * 100:.2f}%"


def _md_bucket_row(name: str, bucket_info: dict[str, Any]) -> str:
    coverage = bucket_info["coverage"]
    return (
        f"| {_md_cell(name)} | {bucket_info['total']} | {coverage['attempted']} | "
        f"{coverage['pass']} | {coverage['fail']} | {coverage['skipped']} | "
        f"{coverage['unsupported']} | {coverage['infrastructure']} | "
        f"{_md_rate(bucket_info['attemptedPassRate'])} |"
    )


def render_markdown(report: dict[str, Any]) -> str:
    """Render a stable Markdown summary from a JSON report.

    This is a diagnostic view, not a conformance certificate. It deliberately
    keeps attempted, skipped, unsupported, and infrastructure outcomes in
    separate columns.
    """
    summary = report.get("summary")
    if not isinstance(summary, dict):
        summary = summarize(list(report.get("records") or []))
    coverage = summary["coverage"]
    options = report.get("options") or {}
    engine = report.get("engine") or {}
    upstream = report.get("upstream") or {}
    policy = report.get("policy") or {}
    host = report.get("host") or {}

    lines = [
        "# Test262 diagnostic report",
        "",
        "This report measures the reviewed FloriaJS corpus. It is not a full",
        "ECMAScript conformance result.",
        "",
        "## Run metadata",
        "",
        f"- Runner: `{_md_cell(report.get('runnerVersion'))}`",
        f"- Generated: `{_md_cell(report.get('generatedAt'))}`",
        f"- Engine revision: `{_md_cell(engine.get('revision') or 'unknown')}`"
        f" (working tree dirty: `{_md_cell(engine.get('workingTreeDirty'))}`)",
        f"- Upstream revision: `{_md_cell(upstream.get('actualRevision') or upstream.get('expectedRevision') or 'unpinned')}`",
        f"- Policy: `{_md_cell(policy.get('name'))}` / `{_md_cell(policy.get('status'))}`",
        f"- Host SHA-256: `{_md_cell((host.get('sha256') or 'unknown')[:16])}...`",
        f"- Selection: `{_md_cell(options.get('listFile') or 'explicit tests')}`",
        f"- Per-test timeout: `{_md_cell(options.get('timeoutSeconds'))}` s; "
        f"jobs: `{_md_cell(options.get('jobs', 1))}`; "
        f"global deadline: `{_md_cell(options.get('maxDurationSeconds', 0))}` s",
        "",
        "## Overall",
        "",
        "| Total | Attempted | Pass | Fail | Skipped | Unsupported | Infrastructure | Attempted pass rate |",
        "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        f"| {summary['total']} | {coverage['attempted']} | {coverage['pass']} | "
        f"{coverage['fail']} | {coverage['skipped']} | {coverage['unsupported']} | "
        f"{coverage['infrastructure']} | {_md_rate(summary['attemptedPassRate'])} |",
        "",
        "`Attempted pass rate` is `pass / (pass + fail)`. Infrastructure outcomes",
        "(harness errors, timeouts, crashes) are never folded into `fail`.",
        "",
        "## Per directory",
        "",
        "| Directory | Total | Attempted | Pass | Fail | Skipped | Unsupported | Infrastructure | Rate |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for name, info in sorted((summary.get("directories") or {}).items()):
        lines.append(_md_bucket_row(name, info))

    lines.extend([
        "",
        "## Per feature",
        "",
        "| Feature | Total | Attempted | Pass | Fail | Skipped | Unsupported | Infrastructure | Rate |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ])
    for name, info in sorted((summary.get("features") or {}).items()):
        lines.append(_md_bucket_row(name, info))

    problems = [
        record for record in report.get("records") or []
        if record.get("outcome") in {"fail", "harness-error", "timeout", "crash"}
    ]
    lines.extend(["", "## Non-passing scenarios", ""])
    if problems:
        lines.extend([
            "| Scenario | Variant | Outcome | Reason |",
            "| --- | --- | --- | --- |",
        ])
        for record in problems:
            lines.append(
                f"| {_md_cell(record.get('testPath') or record.get('scenarioId'))} | "
                f"{_md_cell(record.get('variant'))} | {_md_cell(record.get('outcome'))} | "
                f"{_md_cell(record.get('reason'))} |"
            )
    else:
        lines.append("None.")
    lines.append("")
    return "\n".join(lines)


def write_markdown(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_markdown(report), encoding="utf-8")


def _print_summary(report: dict[str, Any]) -> None:
    summary = report["summary"]
    print(json.dumps(summary, indent=2, sort_keys=True, ensure_ascii=False))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    summarize_parser = subparsers.add_parser("summarize", help="print a report's summary")
    summarize_parser.add_argument("report", type=Path)

    normalize_parser = subparsers.add_parser(
        "normalize", help="write a deterministic baseline form of a report"
    )
    normalize_parser.add_argument("input", type=Path)
    normalize_parser.add_argument("output", type=Path)

    markdown_parser = subparsers.add_parser(
        "markdown", help="render a deterministic Markdown summary of a report"
    )
    markdown_parser.add_argument("input", type=Path)
    markdown_parser.add_argument("output", type=Path)

    compare_parser = subparsers.add_parser("compare", help="compare a report with a baseline")
    compare_parser.add_argument("baseline", type=Path)
    compare_parser.add_argument("current", type=Path)
    compare_parser.add_argument("--fail-on-regression", action="store_true")
    compare_parser.add_argument("--json", action="store_true", help="also print the JSON diff")

    args = parser.parse_args(argv)

    try:
        if args.command == "summarize":
            _print_summary(load_report(args.report))
            return 0
        if args.command == "normalize":
            write_report(args.output, baseline_report(load_report(args.input)))
            return 0
        if args.command == "markdown":
            write_markdown(args.output, load_report(args.input))
            return 0
        baseline = load_report(args.baseline)
        current = load_report(args.current)
        diff = compare_reports(baseline, current)
        print(format_diff(diff))
        if args.json:
            print(json.dumps(diff, indent=2, sort_keys=True, ensure_ascii=False))
        if args.fail_on_regression and diff["regression"]:
            return 3
        return 0
    except ReportError as error:
        print(f"report error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
