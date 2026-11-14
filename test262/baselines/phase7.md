# Phase 7 limited-async baseline

**Recorded:** 2026-11-14  
**FloriaJS source revision:** `d4b226d255e169b24e09d7635cdd6bd06e88eac4` plus diagnostics, host, planner, synchronous runner, negative-verdict, reporting, and limited-async changes in the working tree  
**Pinned Test262 revision:** `2e58f87d8350ad51224617a041c6e041d52f8444` (`package.json` version `5.0.0`)  
**Runner version:** `0.6.0`  
**FPC:** 3.2.3  
**PasBuild:** 1.9.0  
**Metadata environment:** PyYAML 6.0.3

These are focused reviewed-corpus results, not a full-suite Test262 conformance claim.

## Async contract

For metadata `flags: [async]`:

1. the planner injects `harness/assert.js`, `harness/sta.js`, then `harness/doneprintHandle.js`, then metadata includes;
2. the host receives `--async`;
3. the non-strict variant executes and the strict variant remains an explicit skip;
4. after the test source returns successfully, the host drains every queued Promise job;
5. the host requires exactly one done-print message in the captured `print` channel.

Verdicts:

| Host observation | Outcome | Host reason |
| --- | --- | --- |
| One `Test262:AsyncTestComplete`, no failure | `pass` | `async-complete` |
| Any `Test262:AsyncTestFailure:...` | `fail` | `async-failure` |
| More than one completion marker | `fail` | `async-completion-repeated` |
| No completion marker | external `timeout` | orchestrator deadline |
| Synchronous throw before completion | normal `fail` | `evaluation-failed` |

`raw` + `async` is planned as `unsupported` because a raw scenario cannot inject `doneprintHandle.js` and therefore cannot provide the completion contract.

The host has no internal async deadline. A pending test remains alive until the orchestrator kills it; this is deliberate, so a script that returns without scheduling completion cannot pass merely because `EvaluateDetailed()` returned successfully.

## Authored async fixtures

Command:

```sh
cd test262
python3 tools/run_async_smoke.py
```

Result: **5 test methods passed**.

| Fixture | Result |
| --- | --- |
| `complete.js` | Chained promise jobs run in order; `1,2` is printed, then `Test262:AsyncTestComplete`; scenario `pass`. |
| `failure.js` | `$DONE(new TypeError(...))` produces an `async-failure` with `TypeError` and the original message. |
| `missing.js` | No completion is scheduled; the orchestrator kills the host and records `timeout`. |
| `repeated.js` | Two completion prints produce `async-completion-repeated`. |

The fixture run yields 8 records: **1 pass, 2 fail, 4 strict skips, 1 timeout**. The deliberate missing-completion case makes the command exit `2`.

## Curated corpus

`config/curated-tests.txt` now contains **29 reviewed tests**, including six limited-async Promise tests. Command:

```sh
python3 tools/run_test262.py \
  --root .upstream \
  --list config/curated-tests.txt \
  --report results/curated-report.json \
  --baseline baselines/phase7-curated.json \
  --fail-on-regression
```

Result: **58 scenario records: 25 pass, 4 fail, 29 skipped**. Attempted pass rate: **25/29 = 86.21%**. No `unsupported`, `harness-error`, `timeout`, or `crash` outcomes in the stable curated run.

| Directory | Pass | Fail | Skipped | Attempted pass rate |
| --- | ---: | ---: | ---: | ---: |
| `built-ins/Array` | 3 | 1 | 4 | 75.00% |
| `built-ins/Object/keys` | 2 | 0 | 2 | 100.00% |
| `built-ins/Promise/all` | 1 | 1 | 2 | 50.00% |
| `built-ins/Promise/resolve` | 4 | 0 | 4 | 100.00% |
| `language/expressions/addition` | 3 | 1 | 4 | 75.00% |
| `language/expressions/assignment` | 5 | 0 | 5 | 100.00% |
| `language/expressions/logical-and` | 2 | 0 | 2 | 100.00% |
| `language/statements/for` | 1 | 0 | 1 | 100.00% |
| `language/statements/if` | 1 | 1 | 2 | 50.00% |
| `language/statements/try` | 3 | 0 | 3 | 100.00% |

### Async tests in the curated corpus

| Test | Outcome | Explanation |
| --- | --- | --- |
| `built-ins/Promise/all/S25.4.4.1_A2.3_T3.js` | `pass` | `Promise.all([])` completes through the done-print contract. |
| `built-ins/Promise/all/S25.4.4.1_A7.2_T1.js` | `fail` | Completion is reported twice (`async-completion-repeated`); microtask continuation is duplicated. |
| `built-ins/Promise/resolve/resolve-non-obj.js` | `pass` | `Promise.resolve(23)` fulfils and completes once. |
| `built-ins/Promise/resolve/S25.4.4.5_A2.2_T1.js` | `pass` | Pass-through of a later-resolved promise completes. |
| `built-ins/Promise/resolve/S25.4.4.5_A2.3_T1.js` | `pass` | Pass-through of a later-rejected promise completes through the rejection branch. |
| `built-ins/Promise/resolve/S25.4.4.5_A4.1_T1.js` | `pass` | Self-resolution rejects with `TypeError` and completes. |

The pre-existing failures remain: two tests use the unimplemented `eval`, and the array-length boundary at `2^31` does not extend `length`. Every skipped record is the explicit strict-variant skip.

## Smoke corpus

The Phase 0 smoke corpus remains **8 pass, 7 strict skips**, with no failure or infrastructure outcome. Stored as `baselines/phase7-smoke.json` (15 records).

## Adapter fixture suites

| Suite | Result |
| --- | --- |
| `tools/run_host_smoke.py` | 25 checks plus one external-timeout check |
| `tools/run_metadata_smoke.py` | 22 tests passed |
| `tools/run_negative_smoke.py` | 10 test methods passed; 27 records with `pass=5, fail=5, skipped=14, unsupported=2, harness-error=1` |
| `tools/run_report_smoke.py` | 5 tests passed |
| `tools/run_async_smoke.py` | 5 tests passed |
| `tools/run_sync_smoke.py` | 8 tests passed against the pinned review checkout |

The negative suite's async fixture now runs with the done harness and passes its runtime `TypeError` expectation. The host suite verifies chained completion, async failure, repeated completion, pending-without-completion, and raw+async rejection.

## Baseline diff and CI

`tools/ci_smoke.sh` now runs all five adapter suites and both current corpora against:

- `baselines/phase7-smoke.json`;
- `baselines/phase7-curated.json`.

The Phase 6 baseline files remain as the Phase 6 record. An unchanged rerun produces no diff; the current curated baseline has no regressions relative to itself.

## Limits

- Async functions still run their bodies synchronously and settle their promises after the body returns; there is no general suspension/resumption model.
- Only Promise microtasks are drained. Timers, agents, externally resolved promises, and async iteration are out of scope.
- A test that never prints completion is reported as `timeout`, not as a semantic assertion failure.
- The duplicate-completion failure in `S25.4.4.1_A7.2_T1.js` is a real engine gap, not a harness artefact.
- The full Test262 async corpus has not been run.

## Runtime compatibility

No public `Evaluate()` API or host protocol was removed. The host gained an additive `--async` option and the planner gained the matching command-line flag. Root FPCUnit remains at **231 passing tests**, and documentation claims remain at **88 passing claims**.
