# Test262 runner

`tools/run_test262.py` connects the Phase 3 metadata planner to the Phase 2 single-scenario host. It evaluates supported synchronous, asynchronous, and module Test262 scenarios. It does not claim that FloriaJS is a conforming ECMAScript implementation.

## Prerequisites

- Build `test262/target/floria-test262-host` with `pasbuild compile` from `test262/`.
- Python 3.10+ and PyYAML 6 from `test262/requirements.txt`.
- A Test262 checkout whose `HEAD`, consumed content, and package version match the pinned revision.

The default root is `test262/.upstream/`; revision validation is described in the [planner guide](test262-plan.md#checkout-validation). `--allow-unpinned` is for authored/review fixtures only and is never an authoritative conformance mode.

## Run the reviewed smoke corpus

From `test262/`:

```sh
python3 tools/run_test262.py \
  --root /path/to/test262 \
  --list config/smoke-tests.txt
```

Or supply individual paths relative to the checkout's `test/` directory:

```sh
python3 tools/run_test262.py \
  --root /path/to/test262 \
  --timeout 5 \
  language/expressions/addition/S11.6.1_A2.1_T1.js
```

Other options:

- `--host PATH` selects the host executable; it must exist and be executable.
- `--policy PATH` changes the frozen feature policy.
- `--revision PATH` changes the required pinned commit file.
- `--timeout SECONDS` sets an independent external deadline for each scenario.
- `--jobs N` executes up to `N` scenarios concurrently, each in its own host process. Records stay in plan order, so reports are deterministic.
- `--max-duration SECONDS` sets an optional global deadline for the whole run; `0` disables it. A scenario that would cross the deadline gets a bounded per-scenario timeout and is reported as `timeout`.
- `--output PATH` writes the scenario records as JSONL.
- `--report PATH` writes a complete report: metadata, summary, and records.
- `--baseline PATH` compares the run with a reviewed baseline report.
- `--fail-on-regression` exits `3` when that comparison reports a regression.

## What the runner evaluates

For a supported non-strict scenario, it runs the planner-produced argument list in a fresh host process. The same context evaluates:

1. `harness/assert.js`
2. `harness/sta.js`
3. Metadata includes in their declared order
4. The original test source

Every source is separate and evaluated once. No harness file is concatenated with a test file. A raw scenario is exact source input with no harness injection.

Strict scenarios pass `--strict` to the host, which prepends `"use strict";` to the test source only. Async metadata inserts `harness/doneprintHandle.js` after `sta.js` and before the declared includes, and passes `--async` to the host. The host drains every queued Promise job and requires exactly one completion message.

Test262 frontmatter comments stay comments; they are not transformed or stripped from source passed to the host.

## Results

One JSON record per scenario is written to standard output. A human-readable outcome count is written to standard error.

The top-level result preserves the plan's metadata and adds:

- `preparationOnly: false` and `executionPhase: synchronous`;
- final `outcome` and reason;
- `hostExitCode` when a host process actually ran, otherwise `null`;
- `hostResult`, the complete host JSON object, or `null` when no host ran.

Host duration remains diagnostic only and must be ignored for semantic baseline comparisons.

### Outcomes

- **`pass`:** the positive test completed normally, or a negative test produced the required error at the required phase with the required constructor name.
- **`fail`:** an actual test assertion or uncaught JavaScript exception failed a positive test, or a negative test completed normally, threw at the wrong phase, or threw the wrong constructor. A deliberately failing `assert` is a `fail`, not a harness failure.
- **`harness-error`:** harness evaluation, source I/O, missing include, Pascal host exception, or another setup problem occurred. Harness results include the failing harness role/index/filename.
- **`skipped`:** module, `_FIXTURE`, or policy-excluded variants.
- **`unsupported`:** a declared capability or harness prerequisite is absent, a negative resolution/module expectation cannot be evaluated, or a negative parse test failed inside an unimplemented parser feature.
- **`timeout`:** the external deadline expired and the child was killed/reaped.
- **`crash`:** the host failed to execute, returned no valid JSON object, returned malformed/multiple JSON records, or wrote unexpected stderr.

A positive `assert` failure is a test result. A harness/include failure is a setup result. Missing prerequisites such as `detachArrayBuffer.js` are marked unsupported by the frozen policy rather than misreported as ordinary assertion failures.

### Negative verdicts

When metadata contains `negative`, the runner compares the host's actual completion with the declared expectation:

- the error must come from the test source, not a harness file;
- `phase: parse` accepts an actual `parse` or `compile` phase, both of which represent early errors;
- `phase: runtime` requires an actual runtime throw;
- `phase: resolution` is reported as `unsupported` because a host loader failure and a module-link failure are reported as ordinary `fail` records rather than a distinct resolution phase;
- the constructor name must match `negative.type` exactly.

Normal completion, a wrong phase, or a wrong type is a `fail` with a reason that states both the expectation and the actual completion. Harness failures are never converted into negative passes.

The Test262 `$DONOTEVALUATE()` sentinel is recognized explicitly. If it is reached, the runner reports a `fail` explaining that the test was evaluated even though it required a `parse`-phase error; the throw is never accepted as the expected error.

A parse failure can also come from a syntax construct FloriaJS does not implement. The policy lists reviewed error-message fragments (`not supported`, `unsupported`) and, when a negative parse expectation fails for such a reason, the scenario is `unsupported` rather than a false `pass`. This is a conservative safeguard, not a complete semantic verification of every early error.

### Async verdicts

An async scenario passes only on exactly one done-print completion:

- `Test262:AsyncTestComplete` → `pass` with host reason `async-complete`;
- `Test262:AsyncTestFailure:...` → `fail` with host reason `async-failure`, preserving the reported error name/message;
- multiple completion messages → `fail` with `async-completion-repeated`;
- no completion message → the host stays alive and the external per-scenario deadline produces `timeout`.

Before checking completion, the host pumps the owner context: due timers run, then every queued Promise job is drained. Pending timers keep the host pumping but are never treated as completion. Timer state is per context, so a pump cannot execute another context's callbacks.

A synchronous throw still wins over any completion message and keeps its normal `fail`/`harness-error` classification. `raw` + `async` is planned as `unsupported` because a raw scenario injects no done-print harness.

This is still limited support: the host has no internal async deadline, so pending work is killed by the external per-scenario deadline. Async functions, timers, cooperative agents, and async iteration are supported; externally resolved promises and real preemptive threads are not.

## Reports, summaries, and baselines

A report is a single JSON document with `kind: "floriajs-test262-report"`:

- `runnerVersion`, `schemaVersion`, and `generatedAt`;
- `engine`: FloriaJS `HEAD` revision and whether the engine sources are dirty;
- `upstream`: root, expected and actual revision, package version, verification state;
- `policy`: name, status, and SHA-256 of `config/feature-policy.json`;
- `host`: executable path and SHA-256;
- `platform`: OS, release, machine, and Python version;
- `options`: timeout, pinned/unpinned mode, selection, and list file;
- `summary`: outcome counts, coverage, attempted pass rate, and per-directory/per-feature buckets;
- `records`: the same semantic records written by `--output`.

Coverage keeps `attempted = pass + fail`, `skipped`, `unsupported`, and `infrastructure = harness-error + timeout + crash` separate. The attempted pass rate is `pass / (pass + fail)` and is `null` when nothing was attempted. Every bucket includes all outcomes, so an infrastructure failure cannot disappear behind an expected-failure count.

### Reviewed baselines

Write a report, then normalize it for check-in:

```sh
python3 tools/run_test262.py \
  --root .upstream \
  --list config/curated-tests.txt \
  --report results/curated-report.json

python3 tools/results.py normalize \
  results/curated-report.json \
  baselines/phase10-curated.json
```

Normalization removes `generatedAt`, durations, absolute repository paths, the host executable path, and absolute harness/source paths. It sorts records by `scenarioId`, so repeated runs over the same sources produce identical baseline files.

Compare a current report with a reviewed baseline directly:

```sh
python3 tools/results.py compare \
  baselines/phase10-curated.json \
  results/curated-report.json \
  --fail-on-regression
```

The diff reports added, removed, and changed scenarios. Categories include `new-failure`, `new-crash`, `new-timeout`, `new-harness-error`, `failure-fixed`, `unsupported-to-supported`, `skipped-to-supported`, `supported-to-unsupported`, and `added-*`. Regressions are listed separately and set the `--fail-on-regression` exit status.

Inspect a report without re-running:

```sh
python3 tools/results.py summarize results/curated-report.json
```

### Smoke, curated, and broader diagnostic runs

The reviewed commands are deliberately separate:

```sh
# Small upstream smoke corpus.
python3 tools/run_test262.py --root .upstream --list config/smoke-tests.txt \
  --baseline baselines/phase10-smoke.json --fail-on-regression

# Reviewed curated corpus.
python3 tools/run_test262.py --root .upstream --list config/curated-tests.txt \
  --baseline baselines/phase10-curated.json --fail-on-regression

# Optional broader diagnostic run with bounded parallelism and a deadline.
python3 tools/run_test262.py --root /path/to/pinned/test262 \
  --list /path/to/explicit-paths.txt --timeout 10 --jobs 4 \
  --max-duration 3600 --report results/full-report.json
```

Each worker launches a separate host process; no VM context, heap, or runtime state is shared between scenarios. The report records `jobs` and `maxDurationSeconds` in its options.

The broader run writes a report but does not compare against a reviewed baseline automatically. Expanding the corpus requires reviewing the new results and updating a baseline deliberately.

Render a stable Markdown summary from any report:

```sh
python3 tools/results.py markdown results/full-report.json results/full-report.md
```

The summary keeps `pass`, `fail`, `skipped`, `unsupported`, and infrastructure outcomes in separate columns, includes per-directory and per-feature coverage, and lists non-passing scenarios. It is a diagnostic view, not a conformance certificate.

## Exit statuses and reproducibility

- `0`: results were produced without setup/crash/timeout failures. `pass`, semantic `fail`, `skipped`, and `unsupported` are all possible.
- `2`: a harness/setup error, process/protocol crash, or external timeout occurred.
- `3`: `--fail-on-regression` was requested and the reviewed baseline comparison found a regression.

A nonzero host exit with valid JSON is interpreted by its structured host outcome, not automatically treated as a crash. A missing or malformed result is a crash regardless of exit status.

The same pinned source, policy, and host build produces the same semantic result after `durationMs` fields are removed. Strict variants are executed with the `--strict` directive rewrite and are counted separately by scenario ID.

## Integration validation

With an existing review checkout:

```sh
python3 tools/run_sync_smoke.py --root /path/to/test262
```

The integration fixture verifies:

- all 15 reviewed smoke records pass, including both variants;
- repeatability after removing elapsed-time fields;
- parallel (`--jobs`) output matches sequential output;
- a bounded global deadline terminates pending work;
- exact `assert.js` → `sta.js` order and harmless metadata comments;
- a deliberately failing assertion versus an include/harness exception;
- a missing include as a setup error;
- a negative runtime expectation verified by phase and constructor;
- a real infinite-loop timeout;
- missing host JSON classified as a crash;
- done-print async completion, failure, repeated completion, and missing completion in the authored async suite.

The checked-in `run_host_smoke.py`, `run_metadata_smoke.py`, `run_negative_smoke.py`, `run_report_smoke.py`, and `run_async_smoke.py` still validate the lower-level host, planning, negative-verdict, reporting, and async layers independently.

## CI

`tools/ci_smoke.sh` is the deterministic, short pull-request entrypoint. It:

1. fetches the pinned revision into a sparse checkout if `.upstream/` is absent;
2. builds the host with `pasbuild`, falling back to `fpc`;
3. runs all adapter fixture suites;
4. runs every reviewed corpus against its baseline with `--fail-on-regression`;
5. writes generated reports and a Markdown summary to `test262/results/ci/`, which is ignored by Git.

`TEST262_JOBS` controls worker parallelism (default `1` locally; the GitHub workflow sets `4`). `TEST262_MAX_DURATION` optionally bounds the whole run.

The GitHub Actions workflow invokes exactly that script. A local run looks like:

```sh
bash test262/tools/ci_smoke.sh
```

`tools/ci_extended.sh` is the longer-running companion for scheduled or manually dispatched diagnostics. It uses a larger per-scenario timeout, the same bounded parallelism, a global deadline, separate `results/extended/` output, and a combined Markdown summary. It is intentionally not part of the pull-request gate:

```sh
bash test262/tools/ci_extended.sh
```
