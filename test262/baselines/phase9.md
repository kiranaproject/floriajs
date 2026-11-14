# Phase 9 capability-honest `$262` baseline

**Recorded:** 2026-11-14  
**FloriaJS source revision:** `d4b226d255e169b24e09d7635cdd6bd06e88eac4` plus diagnostics, host, planner, runner, negative-verdict, reporting, async, timer, and `$262` changes in the working tree  
**Pinned Test262 revision:** `2e58f87d8350ad51224617a041c6e041d52f8444` (`package.json` version `5.0.0`)  
**Runner version:** `0.6.0`  
**FPC:** 3.2.3  
**PasBuild:** 1.9.0  
**Metadata environment:** PyYAML 6.0.3

These are focused reviewed-corpus results, not a full-suite Test262 conformance claim.

## Exposed host API

The host installs a `$262` object with only two members:

### `$262.global`

Set to the context's existing `globalThis` snapshot. It is intentionally not a live global object: assigning a property on `$262.global` does not create a live global binding. This limitation is part of the support matrix.

### `$262.evalScript(source)`

Calls the new additive `TFloriaJSContext.EvaluateReentrant` path. That path:

- parses and compiles source in the current global environment;
- does **not** call `Heap.Collect()` while a native callback and its caller frame hold live values;
- does **not** drain Promise jobs, so microtasks stay queued until the outer script finishes;
- returns the completion value without pinning it;
- lets runtime throws propagate unchanged;
- converts parser and compiler errors into catchable JavaScript `SyntaxError` objects.

## Deliberately absent members

| Member | Status | Reason |
| --- | --- | --- |
| `$262.gc` | absent | Collection from a native callback is unsafe while VM values are live; no pretend success. |
| `$262.detachArrayBuffer` | absent | ArrayBuffer detachment does not exist. |
| `$262.createRealm` | absent | No designed/tested cross-realm global, heap, console, or timer ownership. |
| `$262.agent` | absent | No agent/concurrency support. |

The policy's `unsupportedHostMembers` no longer includes `$262.evalScript`. It still includes `$262.createRealm`, `$262.agent`, `$262.detachArrayBuffer`, and `$262.gc`.

Planning now scans the test source for those unsupported members and emits `unsupported` with an explicit reason. Feature tags `host-gc-required`, `cross-realm`, and `agent` are also unsupported, so tagged tests never run.

## FPCUnit coverage

Command:

```sh
pasbuild test
```

Result: **239 tests run, 0 errors, 0 failures**. Two new tests cover the re-entrant path:

| Test | Assertion |
| --- | --- |
| `TestReturnsValueAndPropagatesErrors` | Returns `42` from nested source; runtime `RangeError` propagates; parse failure becomes a catchable `SyntaxError`. |
| `TestDoesNotDrainMicrotasks` | A Promise job scheduled by re-entrant source stays queued until the host explicitly drains it. |

## Host fixture coverage

Command:

```sh
cd test262
python3 tools/run_host_smoke.py
```

Result: **30 checks plus one timeout check**.

New checks:

- `$262.global` is an object and is identical to `globalThis`;
- `$262.evalScript` returns values, exposes `var` bindings to the global environment, propagates `TypeError`, and throws `SyntaxError` for invalid syntax;
- `$262.evalScript` does not drain microtasks early (`nested,after,microtask` order);
- 20 nested evaluations run while an outer object/value remains live, and nested `evalScript` recursion returns `3`;
- `typeof $262.gc`, `$262.detachArrayBuffer`, `$262.createRealm`, and `$262.agent` remain `undefined`.

## Metadata fixture coverage

Command:

```sh
python3 tools/run_metadata_smoke.py
```

Result: **24 tests passed**. New checks:

- a test using `$262.evalScript` remains `planned`;
- tests using `$262.createRealm` or `$262.agent` are `unsupported` with no host command;
- a `host-gc-required` test is `unsupported` before execution.

## Curated corpus

Two upstream `$262.evalScript` tests were added:

- `language/global-code/script-decl-func-dups.js` — passes;
- `language/global-code/script-decl-lex-deletion.js` — passes.

Command:

```sh
python3 tools/run_test262.py \
  --root .upstream \
  --list config/curated-tests.txt \
  --report results/curated-report.json \
  --baseline baselines/phase9-curated.json \
  --fail-on-regression
```

Result: **31 tests, 61 records: 27 pass, 4 fail, 30 strict skips**. Attempted pass rate: **27/31 = 87.10%**. The four failures remain the two `eval` gaps, the large-array-index `length` gap, and the duplicate Promise continuation in `Promise/all/S25.4.4.1_A7.2_T1.js`.

The smoke corpus remains **8 pass, 7 strict skips** (15 records).

Current baselines:

- `baselines/phase9-smoke.json`;
- `baselines/phase9-curated.json`.

## Realm safety

No realm tests can run accidentally:

- `$262.createRealm` is absent;
- `cross-realm` metadata is unsupported;
- the host still creates exactly one engine and one context per process;
- console/timer state remains per context, and the host never creates a second context.

## Adapter fixture suites

| Suite | Result |
| --- | --- |
| `run_host_smoke.py` | 30 checks plus one timeout check |
| `run_metadata_smoke.py` | 24 tests |
| `run_negative_smoke.py` | 10 test methods |
| `run_report_smoke.py` | 5 tests |
| `run_async_smoke.py` | 9 tests |
| `run_sync_smoke.py` | 8 tests |

## Limits

- `$262.global` is a snapshot, not a live global object.
- `$262.evalScript` uses the existing per-context compiler; separate calls do not add a new global lexical declaration scope beyond what the compiler already models.
- Nested evaluation deliberately skips collection. A host that repeatedly evaluates without an outer collection relies on normal context teardown to reclaim objects.
- `$262.gc`, `$262.detachArrayBuffer`, `$262.createRealm`, and `$262.agent` remain unsupported.
- Upstream tests using unsupported includes or feature tags remain skipped/unsupported before execution.

## Runtime compatibility

All existing `Evaluate*`, timer, and host signatures remain. `EvaluateReentrant` and the `$262` members are additive. Root documentation claims remain at **88 passing claims**.
