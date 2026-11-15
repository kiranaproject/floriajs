# Test262 single-scenario host

`floria-test262-host` is the Phase 2 low-level execution host. It evaluates one explicit scenario in a fresh process, using the additive Phase 1 diagnostics API. It is **not** the Test262 metadata runner and does not claim full ECMAScript conformance.

## Build

From the repository root:

```sh
cd test262
pasbuild compile
```

The executable is `test262/target/floria-test262-host`. Its PasBuild descriptor uses `src/main/pascal` before `../src/main/pascal`, so the host uses the checked-out runtime sources rather than silently selecting an older installed copy.

## Invocation

```text
floria-test262-host [options] --test <file.js>

  --scenario-id <id>   Stable identifier (defaults to the test filename)
  --variant <mode>     non-strict (default) or raw
  --harness <file.js>  Evaluate before the test; repeat in required order
  --test <file.js>     Evaluate exactly once after all harness files
  --strict             Evaluate the test source with a leading use-strict directive
  --async              Require exactly one Test262 done-print completion
  --help               Show usage
```

Every option value is a filename, never JavaScript source text. Arguments are fully validated before an engine is created. Unknown options, missing values, duplicate tests, unsupported variants, `raw` + async, `raw` + strict, and harness files in `raw` scenarios are rejected as structured `invalid-arguments` results.

Example:

```sh
test262/target/floria-test262-host \
  --scenario-id ordering \
  --variant non-strict \
  --harness test262/fixtures/host/harness-one.js \
  --harness test262/fixtures/host/harness-two.js \
  --test test262/fixtures/host/ordered-test.js
```

The same test, with paths relative to `test262/`, is used by the fixture checker below.

## Execution contract

One host invocation:

1. Creates one engine and one default context.
2. Registers a native `print` callback with a dedicated captured-output channel.
3. Installs `$262.global`, `$262.evalScript`, `$262.createRealm`, and the cooperative `$262.agent` surface. Unsupported members are not fabricated.
4. Reads and evaluates each `--harness` file once in argument order.
5. Stops immediately if a harness file fails.
6. Reads and evaluates `--test` once in that same context.
7. In `--strict` mode, prepends `"use strict";` to the test source (never to harness files).
8. In `--async` mode, pumps due timers, drains every queued Promise job, and waits for a completion print.
9. Emits exactly one compact JSON object to standard output.

Files are read as raw bytes through `TFileStream`; no BOM stripping, trimming, newline normalization, or concatenation occurs. A file is never warmed up, retried, sorted, deduplicated, or executed in another context. A directory, missing file, or read failure is a structured host I/O failure.

`console.log`/`warn`/`error` remain in the context's `consoleOutput` list. Calls to the host's `print` are recorded separately in `printOutput`. Both lists are copied before the engine is freed, and neither can inject extra JSON protocol lines.

The `$262` object exposes only capabilities that actually exist:

- `$262.global` is the live global object (the same object as `globalThis`). Global `var`/function bindings are its own properties; global lexical bindings are not.
- `$262.evalScript(source)` evaluates the source re-entrantly in the current global environment and returns its completion value. It deliberately skips heap collection and Promise-job draining while the caller's VM frame holds live values, and it does not pin the returned value. Runtime throws propagate to JavaScript; parse/compile errors become catchable `SyntaxError`s.
- `$262.createRealm()` creates a separate context with its own heap, global object, intrinsics, timer registry, and output list. The returned object exposes `global` and `evalScript`; the latter evaluates in the realm that owns the receiver.

`$262.detachArrayBuffer` and `$262.gc` remain absent. Collection from a native callback is unsafe while VM values are live, and detaching an array buffer needs semantics FloriaJS does not have. `$262.agent` is present but cooperative: agents run in separate contexts and switch only at explicit agent/Atomics calls, so there is no preemptive thread concurrency. The planner marks tests that reference missing members as `unsupported` rather than pretending success.

In `--async` mode, the host recognizes exactly these completion lines in the captured print channel:

- `Test262:AsyncTestComplete` → `pass` with reason `async-complete`;
- `Test262:AsyncTestFailure:<name>: <message>` → `fail` with reason `async-failure`;
- multiple completion lines → `fail` with reason `async-completion-repeated`;
- no completion line → the host remains pending and is killed by the external supervisor as `timeout`.

The host does not have an internal async deadline. This is intentional: a script that merely returns from `EvaluateDetailed()` cannot pass without printing completion. The async pump runs this context's due timers and then drains Promise jobs, including jobs queued by timer callbacks and cooperative agents. Pending timers are never treated as completion; a far-future timer therefore ends as `timeout`. Async iteration and `for await` are supported; agents remain cooperative and single-threaded.

## Result object

The top-level fields are:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Currently `1`. |
| `scenarioId` | Explicit ID or test basename without extension. |
| `variant` | `non-strict` or `raw`. |
| `outcome` | `pass`, `fail`, or `harness-error` in Phase 2. |
| `phase` | `success`, `parse`, `compile`, `runtime`, or `host`. |
| `reason` | Empty for success; otherwise a stable reason such as `evaluation-failed`, `source-io`, or `invalid-arguments`. |
| `sourceRole` | `test`, `harness`, or `host`. |
| `sourceIndex` | Zero-based index within that role; test source index is `0`, argument/setup host failures use `-1`. |
| `sourceName` | Original supplied filename. |
| `durationMs` | Nonnegative integer elapsed host time. |
| `error` | `name`, `message`, `hostExceptionClass`, `line`, and `column`. |
| `legacyResult` | `success`, `resultType`, `stringValue`, and `errorMessage` projections. |
| `consoleOutput` | Captured console entries in execution order. |
| `printOutput` | Captured native `print` entries in execution order. |

A normal test-source parse/compile/JavaScript failure is `fail`; a genuine assertion failure is not an internal host crash. Harness/setup/I/O and Pascal host exceptions are `harness-error`. Error names/messages and source locations come from Phase 1 managed diagnostics, with no fabricated runtime locations.

Example pass:

```json
{"schemaVersion":1,"scenarioId":"pass","variant":"non-strict","outcome":"pass","phase":"success","reason":"","sourceRole":"test","sourceIndex":0,"sourceName":"fixtures/host/pass.js","durationMs":7,"error":{"name":"","message":"","hostExceptionClass":"","line":0,"column":0},"legacyResult":{"success":true,"resultType":"number","stringValue":"42","errorMessage":""},"consoleOutput":[],"printOutput":[]}
```

Elapsed time is illustrative and must not be compared as part of a semantic baseline.

## Exit statuses

| Status | Meaning |
| ---: | --- |
| `0` | Valid JSON result; scenario passed. |
| `1` | Valid JSON result; test evaluation failed. |
| `2` | Valid JSON result; command-line/scenario arguments were invalid. |
| `3` | Valid JSON result; source I/O, harness, or host setup failed. |
| `4` | Best-effort valid JSON result for an unexpected internal host failure. |

The JSON `outcome` is authoritative; a nonzero process exit does not automatically mean a crash. Missing, truncated, malformed, or multiple JSON records is an infrastructure failure.

Timeouts are enforced **outside** the host by its supervisor. A killed process might not produce JSON; the supervisor supplies the `timeout` outcome itself. An async scenario without a completion message deliberately remains pending until that external deadline.

## Fixture validation

From `test262/`:

```sh
python3 tools/run_host_smoke.py
```

The fixture checker uses only Python's standard library and authored files in `fixtures/host/`. It verifies:

- positive arithmetic and exact console/print channels, including Unicode and escapes;
- JavaScript error objects, primitive throws, parse errors, and compiler errors;
- ordered harness evaluation in one context and exactly-once source execution;
- harness failure short-circuiting, missing files, and directory I/O failures;
- raw-mode rules and invalid argument/status handling;
- `$262.global` equality with the existing global snapshot, `evalScript` return/error propagation, and `createRealm` isolation;
- `evalScript` re-entrancy and absence of premature microtask draining;
- cooperative `$262.agent` start/report/broadcast/leave behavior;
- strict-mode undeclared assignment, duplicate parameters, and class-body strictness;
- `$262`'s deliberately limited surface, with unsupported members absent;
- async chained completion, failure, repeated completion, and missing completion;
- timer completion, ordering, cancellation, intervals, and pending-timer timeouts;
- non-async pending timers that must not run without a host pump;
- external timeout enforcement for an infinite loop and for pending async work.

Passing these fixtures validates the host protocol and failure handling, not Test262 language conformance.
