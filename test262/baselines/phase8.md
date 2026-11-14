# Phase 8 context-owned timers baseline

**Recorded:** 2026-11-14  
**FloriaJS source revision:** `d4b226d255e169b24e09d7635cdd6bd06e88eac4` plus diagnostics, host, planner, runner, negative-verdict, reporting, async, and timer changes in the working tree  
**Pinned Test262 revision:** `2e58f87d8350ad51224617a041c6e041d52f8444` (`package.json` version `5.0.0`)  
**Runner version:** `0.6.0`  
**FPC:** 3.2.3  
**PasBuild:** 1.9.0  
**Metadata environment:** PyYAML 6.0.3

These are focused reviewed-corpus results, not a full-suite Test262 conformance claim.

## Timer ownership

`floria.js.timers` now provides `TFloriaJSTimerRegistry`, one instance per heap and therefore per context. Timer native functions are `of object` methods bound to that registry instead of free functions over global state.

- `TFloriaJSHeap.TimerRegistry` owns the registry reference.
- `TFloriaJSHeap.Clear`/destruction releases timer-held values while the heap is still alive.
- `FloriaJSRegisterTimers(AEnv, AHeap)` creates or reuses that heap's registry. The public signature is unchanged.
- `FloriaJSProcessTimers(AHeap)` delegates to the heap's registry. The public signature is unchanged.

Context helpers:

```text
DrainPromiseJobs()
PumpTimers()
HasPendingTimers()
PendingTimerCount()
NextTimerDelayMS()   // -1 none, 0 due, otherwise milliseconds
HasPendingWork()     // timers or queued Promise jobs
```

## Zero-delay and cancellation semantics

- A zero-delay `setTimeout` is queued only in the timer registry; Phase 7's additional Promise-job enqueue was removed.
- `ProcessDue` takes a snapshot of the current timer count. Timers scheduled by callbacks run in the next pump pass.
- Non-repeating timers are marked inactive before their callback runs, so a nested pump or `clearTimeout` cannot run them twice.
- `clearTimeout`/`clearInterval` release inactive work immediately. If the timer is already running, values are released after the callback returns, avoiding a use-after-release.
- Callback arguments are retained with the timer entry and passed unchanged to the callback.
- A repeating timer is rescheduled only while it is still active; clearing it from inside or outside the callback releases it.
- Inactive entries are compacted after each pump pass, keeping the registry bounded during long runs.
- NaN and negative delays are treated as zero.

## Host async pump

For `--async`, the host loop is:

1. `Context.PumpTimers()` (due timers, then all queued Promise jobs);
2. inspect done-print messages;
3. if no completion, sleep toward the nearest timer due time (capped at 5 ms) or 5 ms when no timer exists;
4. repeat until completion or the orchestrator's external deadline.

Pending timers are never treated as completion. A test that schedules only a far-future timer is killed by the deadline and reported as `timeout`. Cross-context callbacks cannot occur because the host pumps only its own context.

## FPCUnit coverage

Command:

```sh
pasbuild test
```

Result: **237 tests run, 0 errors, 0 failures** (six new timer tests):

| Test | Assertion |
| --- | --- |
| `TestZeroDelayExactlyOnceWithArguments` | A zero-delay timer does not run as a microtask, runs once when pumped, preserves `"x:y"`, and does not run again. |
| `TestClearTimeoutCancelsQueuedWork` | Cancellation before the pump and cancellation of an already-due timer both prevent execution. |
| `TestIntervalRunsUntilCleared` | A zero-delay interval runs exactly three times, clears itself, and leaves no pending timer. |
| `TestTimerRegistriesAreContextIsolated` | Pumping one context does not run another context's callback or mutate its globals. |
| `TestPendingTimersAreSafeAtEngineFree` | A long pending timer is visible through `HasPendingWork()` and is safely released at engine destruction. |
| `TestLegacyProcessTimersStillWorks` | `FloriaJSProcessTimers(Heap)` now pumps the context-owned queue. |

## Authored async timer fixtures

Command:

```sh
cd test262
python3 tools/run_async_smoke.py
```

Result: **9 test methods passed** over 9 fixtures, producing 18 records:

```text
Summary: fail=2, pass=5, skipped=9, timeout=2
```

| Fixture | Outcome | Check |
| --- | --- | --- |
| `timer-complete.js` | `pass` | Zero-delay callback prints its two arguments then completes. |
| `timer-cancel.js` | `pass` | A cancelled zero-delay callback never prints; the later timer completes. |
| `timer-interval.js` | `pass` | Interval fires exactly three times, clears itself, then completes. |
| `timer-order.js` | `pass` | Two zero-delay timers run in scheduling order (`1,2`). |
| `timer-pending.js` | `timeout` | A 60-second timer with no completion is not a pass. |
| `complete.js`, `failure.js`, `missing.js`, `repeated.js` | existing | Phase 7 async contract remains covered. |

The two deliberate timeouts are `missing.js` and `timer-pending.js`; the command therefore exits `2` while all fixture assertions pass.

The host fixture suite has **27 checks plus the external-timeout check**, including a non-async pending timer that must not run without a pump and an async timer completion pumped by the host.

## Reviewed upstream corpora

| Corpus | Records | Outcomes |
| --- | ---: | --- |
| Smoke | 15 | `pass=8, skipped=7` |
| Curated | 58 | `pass=25, fail=4, skipped=29` |

The timer changes do not alter the reviewed upstream outcomes. Current CI baselines are:

- `baselines/phase8-smoke.json`;
- `baselines/phase8-curated.json`.

## Upstream timer-dependent tests

The only tests in the pinned upstream tree that call `setTimeout` are `built-ins/Atomics/waitAsync/*` cases. They require `Atomics`, `SharedArrayBuffer`, and agent semantics, which the policy marks unsupported. No eligible timer-dependent upstream Test262 case exists in the reviewed directories, so none was enabled.

The authored timer fixtures are the gate for future cases: a timer-dependent Test262 test should be added only after the corresponding host and engine fixture passes.

## Adapter fixture suites

| Suite | Result |
| --- | --- |
| `run_host_smoke.py` | 27 checks plus one timeout check |
| `run_metadata_smoke.py` | 22 tests |
| `run_negative_smoke.py` | 10 test methods |
| `run_report_smoke.py` | 5 tests |
| `run_async_smoke.py` | 9 tests |
| `run_sync_smoke.py` | 8 tests |

## Limits

- Timers run only when the host or embedder pumps them. A non-async script's pending timers remain pending at process exit.
- The host pumps timers only for async scenarios; non-async Test262 scenarios deliberately do not gain an event loop.
- A zero-delay repeating interval can run until it clears itself or the external deadline ends the process.
- Timer callbacks currently receive the host `this` value used by the existing implementation; `this` binding is not part of this phase.
- The VM still has no general wall-clock event loop, and externally resolved promises/agents remain out of scope.

## Runtime compatibility

No existing public signature was removed. `FloriaJSRegisterTimers`, `FloriaJSProcessTimers`, and all `Evaluate*` methods keep their signatures. New context methods and `TFloriaJSTimerRegistry` are additive. Root documentation claims remain at **88 passing claims**.
