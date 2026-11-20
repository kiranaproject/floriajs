# Test262 diagnostic support

FloriaJS implements a practical JavaScript subset for embedded scripts and FTML handlers; it is **not currently a conforming ECMAScript implementation**. The work in `test262/` is intended to measure compatibility, not to claim full Test262 support.

## Current status: Phase 13, P3, and the post-P3 conformance closures complete

Phases 0–10.10 establish the baseline, pinned upstream material, support policy, reviewed smoke and curated corpora, additive diagnostics, single-scenario host, metadata planner, synchronous and asynchronous runner, negative-test verdicts, durable reports, reviewed baseline diffs, context-owned timers, a capability-honest `$262` host API, the language-coverage milestones (temporal dead zone, restricted-production ASI, strict-mode execution, live global object/`this`), general object-to-primitive coercion, full property descriptors, UTF-16 code-unit string semantics at the JavaScript boundary, resumable async execution with `for await` iteration, binary/reflection data APIs, static module linking/evaluation, isolated realms, and async generators. Phase 11 adds bounded process-level parallelism, a global run deadline, Markdown coverage reports, a separate extended diagnostic job, and a reviewed upstream-update workflow. Phase 12 closes the recorded curated gaps for boxed String objects, Promise.all microtask ordering, Proxy `has` fallback, and large array indices. Phase 13 adds direct and indirect `eval`, Unicode whitespace handling, and CR line-terminator tracking; the curated corpus now passes completely. This is still a diagnostic adapter, not a conformance certification. In particular:

- no conformance percentage or official Test262 verdict is published;
- no upstream test suite is vendored in this repository;
- no execution-engine behaviour is changed by this phase.

The implementation proposal is in `scratch/roadmap-proposal.md`. The exact baseline and smoke-review scope are recorded in `test262/baselines/phase0.md`.

The per-phase result sections later in this document are historical records: they describe what was true when each phase landed. For current behaviour, use this status section, [language support](language-support.md), and the latest reviewed baselines. Statements in older phase sections such as “still unsupported” may have been resolved by a later phase.

## Pinned upstream material

The initial revision is:

- repository: <https://github.com/tc39/test262>
- commit: [`2e58f87d8350ad51224617a041c6e041d52f8444`](https://github.com/tc39/test262/commit/2e58f87d8350ad51224617a041c6e041d52f8444)
- upstream package version: `5.0.0`
- committer timestamp: 2026-11-11

The full hash lives in `test262/config/test262-revision.txt`. The runner fails clearly if its checkout does not match that hash; silently running a moving upstream branch would make baselines incomparable. Change the pin only together with a reviewed baseline update.

To review a candidate upstream update without editing the pin:

```sh
cd test262
bash tools/review_upstream_update.sh <candidate-sha>          # dry run
bash tools/review_upstream_update.sh <candidate-sha> --apply  # write the pin
```

The review script requires the candidate to exist locally, prints the commit and the `test/`/`harness/`/`package.json` diff, and refuses to write the pin unless the checkout `HEAD` already equals the candidate. After applying, rerun `ci_extended.sh`, regenerate every affected baseline, and update this page and [language support](language-support.md) for any new gaps. CI never fetches a moving branch on its own.

The default checkout location is `test262/.upstream/`; generated reports belong in `test262/results/`. Both are ignored by Git.

## Execution policy

The execution policy in `test262/config/feature-policy.json` covers these diagnostic scenarios:

| Test metadata | Treatment |
| --- | --- |
| `raw` | Execute once in non-strict mode, unmodified and without injected harness files. |
| `noStrict` | Execute once in non-strict mode with the standard harness. |
| Default test | Execute non-strict and strict scenarios. The strict variant prepends a leading `"use strict";` to the test source. |
| `onlyStrict` | Execute the strict scenario. |
| `module` | Resolve relative imports into a diagnostic bundle and execute the module graph. |
| `async` | Execute the non-strict scenario with `doneprintHandle.js`; require exactly one `Test262:AsyncTestComplete` done-print message. |
| Tests using `setTimeout`/`setInterval` | Run only through async scenarios; the host pumps the owner context until completion or the external deadline. |
| `negative` with `parse`/`runtime` | Execute and compare the actual phase and constructor with the metadata; the `$DONOTEVALUATE()` sentinel is a failure. |
| `negative` with `resolution` | `unsupported`: resolution failures are not modelled as module-link errors. |
| `intl402` / `staging/intl402` | Skip: ECMA-402 is not implemented. |
| Filename containing `_FIXTURE` | Never execute as a standalone test; it is module-test input. |
| `detachArrayBuffer.js` include | Unsupported until ArrayBuffer detachment exists. `propertyHelper.js` is now supported. |
| `$262.global` | The live global object (the same object as `globalThis`). |
| `$262.evalScript` | Re-entrant evaluation with no nested heap collection or microtask drain; runtime throws propagate, parse errors become `SyntaxError`. |
| `$262.createRealm` | Returns a separate context-owned realm with its own heap, global object, intrinsics, timers, and output. |
| `$262.agent` | Cooperative single-threaded agents that switch only at explicit agent/Atomics calls; waiters are resolved by `Atomics.notify`. |
| `$262.detachArrayBuffer`, `$262.gc` | Unsupported; no fake stubs or success results. Tests referencing them are `unsupported`. |

For eligible non-raw tests, the planned evaluation order in one fresh host process is:

1. Create a new engine/context.
2. Evaluate `harness/assert.js`.
3. Evaluate `harness/sta.js`.
4. Evaluate metadata includes in their declared order.
5. Evaluate the test source once in that same context.

`async` tests additionally evaluate `harness/doneprintHandle.js` after `sta.js` and before metadata includes. The host then drains queued Promise jobs and requires exactly one done-print message. A test without a completion message remains pending until the orchestrator's external deadline, producing `timeout` rather than a false pass.

A default test normally has both strict and non-strict scenarios upstream. Both now run: the strict scenario evaluates the test source with a leading `"use strict";` directive while the harness keeps its own source unchanged.

## Known semantic limitations

The policy must not disguise the following existing differences as passes:

- strict mode covers directives, undeclared-assignment errors, duplicate parameters, class bodies, legacy octal literals, `delete` of identifiers, and `eval`/`arguments` bindings, but not every strict-only early error;
- ASI covers restricted productions and statement boundaries, not every ECMAScript corner case;
- TDZ is implemented for program/block/function/switch/classic-for scopes, but not for `for…in`/`for…of` bindings or catch parameters;
- `$262.global`/`globalThis` are live, but global lexical bindings are still not object properties (as designed);
- `Symbol.toPrimitive` is consulted first; some built-ins still use the simpler object-to-string conversion;
- agents are cooperative rather than preemptive; `WeakMap`/`WeakSet` are not truly weak; module linking uses live getters and supports star-export cycles; `Atomics.waitAsync` waiters are resolved by `Atomics.notify`, including across cooperative agents;
- realms are isolated and cross-realm intrinsic selection works for the supported constructors; `String.prototype.concat` calls a user-supplied `toString`, but general object-to-string coercion is still incomplete.

The complete feature list and intentional embedded trade-offs are documented in [language support](language-support.md). A missing prerequisite should be classified as unsupported rather than automatically treated as a specification-mandated early error.

## Outcome vocabulary

Every future attempted scenario will have exactly one of these outcomes:

| Outcome | Meaning |
| --- | --- |
| `pass` | The scenario completed according to its metadata and the available ECMAScript capabilities. |
| `fail` | A supported scenario produced an incorrect assertion, completion, error phase, or error type. |
| `unsupported` | Execution requires an explicitly unavailable language, library, harness, or host capability. |
| `skipped` | The scenario was intentionally excluded by the frozen policy. |
| `harness-error` | The adapter, harness, metadata, or setup failed independently of the test's semantic assertion. |
| `timeout` | The host did not complete within its external deadline. |
| `crash` | The process terminated abnormally or did not return a valid structured result. |

Unsupported and skipped scenarios are neither passes nor failed assertions. Reports must show coverage separately from the attempted pass rate:

```text
attempted pass rate = pass / (pass + fail)
```

Harness errors, timeouts, and crashes remain visible as infrastructure or robustness defects and must never disappear inside an expected-failure baseline.

## Reviewed smoke corpus

`test262/config/smoke-tests.txt` contains eight paths, relative to the upstream `test/` directory:

| Area | Test |
| --- | --- |
| Arithmetic | `language/expressions/addition/S11.6.1_A2.1_T1.js` |
| Functions | `language/statements/function/S13.2.1_A6_T1.js` |
| Closures | `language/statements/function/S13_A18.js` |
| Exceptions | `language/statements/try/S12.14_A1.js` |
| Arrays | `built-ins/Array/S15.4_A1.1_T4.js` |
| Objects | `built-ins/Object/keys/15.2.3.14-2-1.js` |
| Promise | `built-ins/Promise/all/S25.4.4.1_A1.1_T1.js` |
| Promise | `built-ins/Promise/resolve/S25.4.4.5_A1.1_T1.js` |

The files were read and checked with the current `sta.js` and `assert.js` through the existing one-shot `evalone` probe as a **readiness review only**. That is not a Test262-compliant execution path and these outcomes must not be represented as official conformance results. The future adapter will evaluate each case using the frozen scenario rules and structured verdicts.

## Phase 1 result

The additive diagnostics API is now implemented and documented in [Engine and context API](api/engine.md#detailed-execution-diagnostics). It preserves `TFloriaJSResult` and existing evaluation signatures while classifying parse errors, compiler early errors, JavaScript throws, and Pascal host failures. Parser line/column data, JavaScript error names/messages, source filenames, and host exception classes are available as managed diagnostic fields.

The complete suite passes **231 tests**, including eight diagnostics tests. The API is tooling support only: no Test262 host or orchestration runner exists yet, and no conformance verdict has been produced.

## Phase 2 result

The dedicated single-scenario Pascal host is now implemented in `test262/`. It validates explicit `--harness`/`--test` arguments, reads raw source files in order, evaluates each source once in one context, captures native `print` separately from console output, and emits one compact JSON result. It installs an empty `$262` object without pretending to support unavailable host capabilities.

Build and validate it with:

```sh
cd test262
pasbuild compile
python3 tools/run_host_smoke.py
```

**All 20 host fixture checks and the external infinite-loop timeout check pass.** See the [host guide](test262-host.md) for the command-line protocol, result schema, exit statuses, and fixture coverage. FPCUnit remains at 231 passing tests; no existing runtime API or result layout was changed.

This is deliberately not the metadata orchestrator: there is no YAML frontmatter parsing, scenario expansion, revision checkout management, Test262 verdict aggregation, or asynchronous conformance harness yet.

## Phase 3 result

The pure metadata planner is implemented in `tools/frontmatter.py`, `tools/scenario.py`, and `tools/prepare_test262.py`. It parses `flags`, `includes`, `negative`, `features`, and `locale` with `yaml.safe_load` and duplicate-key checks. It preserves raw source bytes and emits ordered argument lists without executing the host or inventing conformance verdicts.

All **21 Phase 3 metadata fixture tests pass**, and the eight reviewed upstream smoke inputs produce **15 correct records: eight planned non-strict scenarios and seven strict skips**. Phase 5 adds one more metadata fixture (22 total) covering `negative.phase: resolution` deferral. See the [planner guide](test262-plan.md) for commands, result schemas, checkout verification, and safety rules.

The current pinned Test262 documentation requires `assert.js` **before** `sta.js`; the earlier policy text was corrected accordingly. Raw tests inject no harness, default tests retain a separate strict skip, and `_FIXTURE`, modules, `onlyStrict`, async, `intl402`, and unavailable host capabilities never become ordinary execution scenarios.

## Phase 4 result

The synchronous orchestrator now runs supported scenarios using the real Test262 harness: `assert.js`, then `sta.js`, then ordered includes, then the original test source. Each scenario executes in a separate host process with an external timeout. Positive test completion produces `pass`; actual assertion failures produce `fail`; harness/setup issues remain `harness-error`.

The complete reviewed upstream smoke corpus now returns **8 passing scenarios and 7 strict skips**. Another **8 integration tests** verify reproducibility, deliberate assertion versus harness failures, missing includes, negative-test deferral, real timeout handling, and missing-JSON crashes. See the [runner guide](test262-runner.md) for the exact invocation and result model.

At the end of Phase 4, negative expectations were explicitly `unsupported` and deferred to Phase 5. Strict, module, and async scenarios were not evaluated.

## Phase 5 result

The runner now applies Test262 negative verdicts instead of deferring every negative test. A negative scenario passes only when the test source itself produces the declared error constructor at the declared phase:

- `negative.phase: parse` accepts the host's `parse` or `compile` phase, both of which represent early errors.
- `negative.phase: runtime` requires a runtime JavaScript throw.
- `negative.phase: resolution` is `unsupported` because module linking is not implemented.
- Normal completion, the wrong phase, or the wrong constructor name is a `fail`.
- Harness failures remain `harness-error`; they can never satisfy a negative expectation.
- `$DONOTEVALUATE()` is recognized by its Test262 message. Reaching it is a `fail` with an explicit reason; it is never treated as the required parse error.
- A parse failure whose message identifies an unimplemented parser feature is reported as `unsupported`, not as evidence for the expected specification early error.

The authored negative suite now contains **15 fixtures** checked by **9 test methods**. It covers early `SyntaxError` parse/compile errors, runtime and raw `TypeError`, wrong phase, wrong type, a runtime `TypeError` that must not satisfy a parse-phase `TypeError`, normal completion, `$DONOTEVALUATE`, unsupported feature and parser limitations, module/async/strict skips, and harness failure. The fixture run produces 4 `pass`, 5 `fail`, 15 `skipped`, 2 `unsupported`, and 1 `harness-error` records. See the [Phase 5 baseline](../test262/baselines/phase5.md).

Existing `Evaluate()` callers and the Phase 1 diagnostic API remain unchanged.

## Phase 6 result

`tools/results.py` now builds durable reports around the scenario records. The runner can write:

- `--output PATH`: scenario records as JSONL, one object per line;
- `--report PATH`: a complete JSON report with report metadata, summary, and records;
- `--baseline PATH`: a comparison against a reviewed baseline report.

`--fail-on-regression` makes the runner exit `3` when a reviewed baseline reports a new failure, a new crash, a new timeout, or a new harness error. Infrastructure failure still exits `2` and is never folded into an expected-failure count.

Each report records the FloriaJS engine revision and working-tree state, the pinned upstream revision/package version, the policy name/status/hash, the host executable hash, platform and Python information, and execution options. The summary contains outcome counts, an attempted pass rate, and per-directory and per-feature buckets. Coverage counts `skipped`, `unsupported`, and `infrastructure` separately from `pass` and `fail`.

Reports are normalized before check-in: durations, the generation timestamp, absolute root paths, and the host executable path are removed. The remaining record order is stable, so two runs over the same sources produce byte-identical baselines. Baseline comparison is keyed by `scenarioId` and classifies new failures, fixes, crashes, timeouts, harness errors, and unsupported-to-supported transitions explicitly.

The reviewed **curated corpus** in `config/curated-tests.txt` contains 23 tests across arithmetic, assignment, logical operators, `if`, `for`, `try`, arrays, objects, and three negative parse tests. It produces **46 scenario records: 20 pass, 3 fail, and 23 strict skips**, for an attempted pass rate of **20/23 (86.96%)**:

| Directory | Pass | Fail | Skipped | Attempted pass rate |
| --- | ---: | ---: | ---: | ---: |
| `built-ins/Array` | 3 | 1 | 4 | 75% |
| `built-ins/Object/keys` | 2 | 0 | 2 | 100% |
| `language/expressions/addition` | 3 | 1 | 4 | 75% |
| `language/expressions/assignment` | 5 | 0 | 5 | 100% |
| `language/expressions/logical-and` | 2 | 0 | 2 | 100% |
| `language/statements/for` | 1 | 0 | 1 | 100% |
| `language/statements/if` | 1 | 1 | 2 | 50% |
| `language/statements/try` | 3 | 0 | 3 | 100% |

No curated scenario produced `unsupported`, `harness-error`, `timeout`, or `crash`. The three failures are genuine gaps, not infrastructure: two tests call the unimplemented `eval`, and one array-length boundary test does not extend `length` for an index at `2^31` (the harness then reports a thrown object as `[object Object]`). Every skip is the policy's explicit strict-variant skip. See the [Phase 6 baseline](../test262/baselines/phase6.md) for the fixture-level explanation.

The Phase 6 reviewed baselines were `baselines/phase6-smoke.json` and `baselines/phase6-curated.json`; Phase 7 added `phase7-*`, Phase 8 added `phase8-*`, Phase 9 added `phase9-*`, and Phase 10.1 now supplies the current CI pair `baselines/phase10-smoke.json` and `baselines/phase10-curated.json`. Earlier files remain as milestone records. `tools/ci_smoke.sh` runs the adapter suites and both corpora against the current baselines. A GitHub Actions workflow (`.github/workflows/test262-smoke.yml`) invokes that script with a pinned sparse checkout. The workflow has not yet been exercised on hosted CI, so it should be treated as the first CI trial rather than a guaranteed green gate.

## Phase 7 result

Limited asynchronous scenarios now execute instead of being skipped. The planner loads `harness/doneprintHandle.js` after `assert.js` and `sta.js` and before metadata includes, and passes `--async` to the host. The non-strict variant runs; the strict variant remains an explicit skip.

The host drains all queued Promise jobs and inspects the captured `print` channel for exactly one completion message:

- one `Test262:AsyncTestComplete` and no failure marker → `pass`;
- any `Test262:AsyncTestFailure:...` marker → `fail`, preserving the reported constructor and message;
- more than one completion marker → `fail` with `async-completion-repeated`;
- no completion marker → the host remains pending, so the orchestrator's external deadline produces `timeout`;
- a synchronous test throw still produces its normal `fail`/`harness-error` result.

The authored async suite has **4 fixtures and 5 test methods**: chained promise completion, async failure, missing completion (external timeout), repeated completion, and done-harness ordering. The host fixture suite now has **25 checks plus the timeout check**.

The reviewed curated corpus grew to **29 tests**: the previous 23 plus six already-resolved Promise tests. It now produces **58 records: 25 pass, 4 fail, 29 strict skips**, for an attempted pass rate of **25/29 (86.21%)**. The fourth failure is `built-ins/Promise/all/S25.4.4.1_A7.2_T1.js`, which reports completion twice — a real promise-continuation defect recorded by the new repeated-completion check. See the [Phase 7 baseline](../test262/baselines/phase7.md).

The host's Promise draining does not make `await` fully conformant. Synchronous async-function bodies still run to completion before their promise settles, and externally resolved promises/agents are out of scope. Async iteration, `for await`, and async feature tags remain unsupported.

## Phase 8 result

Timer ownership moved from process-global state to a registry owned by each context's heap. The standard-library timer functions are now native methods bound to that registry, so independent contexts cannot execute each other's callbacks. `FloriaJSProcessTimers(Heap)` remains as a compatibility wrapper over the same heap-owned queue.

The zero-delay duplication bug is fixed: `setTimeout(callback, 0, ...)` is queued only in the timer queue, never additionally as a Promise job. A pumped zero-delay callback runs exactly once with its original arguments. Cancellation clears inactive work and can cancel a timer that is already due but has not started; a running callback is released only after it returns.

The host now pumps the owner context before checking async completion:

1. execute due timers;
2. drain all Promise jobs, including jobs queued by callbacks;
3. check the done-print messages;
4. sleep toward the next due timer or the external deadline.

Pending timers are never treated as completion. A test that leaves only a long timer pending reaches the orchestrator deadline and becomes `timeout`.

The context exposes the controlled pump and pending-work API: `PumpTimers`, `DrainPromiseJobs`, `HasPendingTimers`, `PendingTimerCount`, `NextTimerDelayMS`, and `HasPendingWork`.

Validation now includes **6 new FPCUnit tests** (237 total) and **9 authored async fixtures** covering timer completion, ordering, cancellation, intervals, exactly-once zero-delay execution, pending timers, and process-exit cleanup. The host fixture suite has **27 checks plus the timeout check**. The reviewed curated corpus is unchanged at **58 records: 25 pass, 4 fail, 29 strict skips**.

Upstream `Atomics.waitAsync` cases now have the required `Atomics`/`SharedArrayBuffer` surface; timer-dependent agent tests remain limited by the cooperative scheduler. The authored timer fixtures are the gate for enabling such tests when the required host features exist. See the [Phase 8 baseline](../test262/baselines/phase8.md).

## Phase 9 result

The host now exposes only `$262` capabilities that actually work:

- `$262.global` exposes the live global object. Phase 10.3 replaced the Phase 9 snapshot; global `var`/function bindings and object properties are now synchronized.
- `$262.evalScript(source)` uses a new `TFloriaJSContext.EvaluateReentrant` path. It skips heap collection and Promise-job draining while the caller's VM frame is live, returns the completion value without pinning, throws runtime errors unchanged, and converts parse/compile errors into catchable `SyntaxError` objects.
- `$262.gc` remains absent because collection from a native callback is unsafe while VM values are live.
- `$262.detachArrayBuffer` remains absent until ArrayBuffer detachment exists.
- `$262.createRealm` was absent in Phase 9; Phase 10.10 later added isolated realms with separate heap, global, timer, and output ownership.
- `$262.agent` remains absent; there is no agent or concurrency support.

The planner marks tests that reference unsupported host members as `unsupported` before execution. It skipped the `cross-realm` feature tag until Phase 10.10 added realms; `host-gc-required` and `agent` remain unsupported.

Validation covers nested evaluation returning values, global snapshot identity, catchable nested runtime and syntax errors, re-entrancy under live objects, and the absence of premature microtask draining. The host fixture suite is now **30 checks plus the timeout check**, metadata planning is **24 tests**, and FPCUnit is **239 tests**.

Two upstream `$262.evalScript` tests were added to the curated corpus and pass, bringing it to **31 tests / 61 records: 27 pass, 4 fail, 30 strict skips** (attempted pass rate 27/31 = 87.10%). See the [Phase 9 baseline](../test262/baselines/phase9.md).

At that point no realm test could run accidentally. Phase 10.10 later enabled `$262.createRealm` and a focused realm corpus while keeping agents unsupported.

## Phase 10.1 result

The first language-coverage milestone implements the temporal dead zone for `let`/`const`/`class` bindings and restricted-production automatic semicolon insertion.

- Block, program, function-body, `switch`, and classic-`for` initializer scopes now predeclare lexical bindings as uninitialized. Reading or assigning one before its declaration throws `ReferenceError`; `typeof` does not bypass the dead zone.
- A declaration initializes the predeclared binding instead of creating it at the statement point. Shadowing is correct: an inner `let` is in TDZ even when an outer binding of the same name exists.
- `return`, `break`, and `continue` stop at a line break; a `throw` followed by a line break is a SyntaxError; postfix `++`/`--` does not cross a line break.
- A line break, `}`, or end of input terminates a statement; two statements on the same line still require a semicolon.
- Error prototype `constructor` back-references now identify the global error constructors, allowing `assert.throws`-style Test262 checks to recognize thrown `ReferenceError`/`SyntaxError` objects.

Validation: **247 FPCUnit tests** (8 new), **90 documentation claims** (2 new TDZ/ASI claims), and a focused `language/statements/{let,const}` diagnostic run over **281 files → 558 records: 172 pass, 92 fail, 278 strict skips, 16 unsupported** (attempted pass rate 172/264 = 65.15%). The remaining failures are concentrated in destructuring and syntax cases outside this slice.

Seven upstream tests were added to the curated corpus (six TDZ cases and the `return` line-terminator case). The corpus is now **38 tests / 75 records: 34 pass, 4 fail, 37 strict skips** (attempted pass rate 34/38 = 89.47%). See the [Phase 10.1 baseline](../test262/baselines/phase10.md).

## Phase 10.2 result

Strict-mode execution is now real for the covered subset:

- `"use strict"` directives at program and function-body level are detected by the compiler; class bodies are always strict.
- Each bytecode chunk records whether it is strict, and nested functions inherit strictness.
- Assigning an undeclared name in strict code throws `ReferenceError`; non-strict code keeps the existing global-assignment behavior.
- Duplicate parameter names, and `eval`/`arguments` parameters, are early errors in strict functions.
- The Test262 host accepts `--strict` and prepends `"use strict";` to the test source only.
- The planner now produces executable strict variants for default and `onlyStrict` tests; the previous strict skips are gone from the reviewed corpora.
- `raw` + strict remains rejected.

Validation:

- **250 FPCUnit tests** (3 new strict tests).
- Host fixtures: **34 checks plus the timeout check**.
- The focused `let`/`const` report now executes strict variants as well.
- Curated corpus: **75 records — 67 pass, 8 fail, 0 skipped**; attempted pass rate 67/75 = 89.33%. The eight failures are the four known non-strict gaps plus their strict variants.
- Smoke corpus: **15 records, all pass** (eight non-strict and seven strict).
- Negative fixtures: 27 records — pass=9, fail=11, skipped=1, unsupported=4, harness-error=2. The `onlyStrict` negative fixture now runs strictly and fails because its source reaches `$DONOTEVALUATE()`, as required.

Strict mode is not complete: octal literals, `delete` of identifiers, and `eval`/`arguments` binding restrictions remain future work. See the [Phase 10.2 baseline](../test262/baselines/phase10.md#strict-mode-phase-102).

## Phase 10.3 result

- `globalThis` is now the live global object. Global `var` and function bindings are its own properties; writes through `globalThis` update the bindings, and writes to those bindings update the object.
- Global lexical `let`/`const` bindings remain environment bindings and are intentionally not properties of the global object.
- Top-level `this` is the global object.
- A plain call of a non-strict function receives the global object as `this`; strict functions keep `undefined`; methods and `new` keep their explicit receiver.
- `$262.global` now exposes this live object.
- Existing global-object consumers (FTML item publication, timers, console) continue to work through the root environment.

Validation: **253 FPCUnit tests** (two new live-global/`this` tests), **90 documentation claims**, curated corpus **79 records — 71 pass, 8 fail** (attempted pass rate 71/79 = 89.87%). One upstream `this` test was added and passes in both modes. The eight failures remain the four known gaps in both modes.

## Phase 10.4 result

Object-to-primitive coercion now uses the object's `valueOf` and `toString` methods:

- `+` converts both operands with the default hint before deciding between string concatenation and numeric addition.
- Loose equality converts an object against a primitive operand and then retries the comparison.
- Relational operators convert with the numeric hint, preserving string/string lexicographic comparison.
- `ToNumber` on an object or function goes through `ToPrimitive`, so subtraction, multiplication, unary `+`, and similar operators see the primitive result.

`Symbol.toPrimitive` is consulted first. Conversion of exotic built-ins such as `Date` still uses the ordinary `valueOf`/`toString` order.

## Phase 10.5 result

Property descriptors are now enforced:

- Every own property carries `writable`, `enumerable`, and `configurable` flags in addition to value/accessor data.
- `Object.defineProperty` honors all descriptor fields and preserves absent fields on existing properties.
- `Object.getOwnPropertyDescriptor` returns data/accessor descriptors for ordinary objects and array indices/`length`.
- `Object.preventExtensions`, `Object.isExtensible`, `Object.freeze`, `Object.seal`, `Object.isFrozen`, and `Object.isSealed` update and report real extensibility and property flags.
- Writes to non-writable/frozen properties are ignored in non-strict code; deletes require `configurable`.
- `Object.prototype.propertyIsEnumerable` is implemented.
- `propertyHelper.js` is no longer an unsupported include; three upstream property-helper tests pass in both modes.

Validation: **255 FPCUnit tests** (two new descriptor tests), **90 documentation claims**, curated corpus **85 records — 77 pass, 8 fail** (attempted pass rate 77/85 = 90.59%). The eight failures remain the four known gaps in both modes.

Known descriptor limits: strict-mode writes to non-writable properties do not yet throw `TypeError`; arrays do not expose every descriptor corner case; and `Object.getOwnPropertySymbols` is not implemented.

## Phase 10.6 result

JavaScript-visible string operations now use UTF-16 code units while the runtime keeps UTF-8 storage internally:

- `length`, numeric indexing, `charAt`, `charCodeAt`, `slice`, `substring`, `substr`, `indexOf`, `lastIndexOf`, `includes`, `startsWith`, `endsWith`, `padStart`, and `padEnd` use code-unit positions.
- `String.fromCharCode` treats each argument as one code unit; `String.fromCodePoint` produces a surrogate pair for astral code points.
- `for…of`, spread, and `Array.from` over a string yield code points, keeping an astral character as one element.
- `\uXXXX` BMP escapes expose their actual code unit (`\u00e9` has length 1 and code 233).
- The legacy `language/types/string` corpus was added to the curated run: **20 tests / 40 records pass**.

Validation: **256 FPCUnit tests** (one new UTF-16 test), **90 documentation claims**, curated corpus **133 records — 117 pass, 16 fail** (attempted pass rate 117/133 = 87.97%). The 16 failures are the eight known gaps in both non-strict and strict variants.

Known limits: regular-expression matching and lexer byte positions still operate on the UTF-8 representation; lone-surrogate literals and every astral regexp corner case are not covered; `toUpperCase`/`toLowerCase` still use host Unicode case mapping via UTF-8.

## Phase 10.7 result

Async function bodies are now true resumable state machines rather than synchronous bodies:

- `await` suspends the async task and resumes it when the awaited promise settles.
- The task is driven by `Promise.resolve` semantics, so thenables are adopted.
- Rejections resume the task by throwing at the await point, making `try`/`catch` around `await` work.
- Suspended try handlers are saved and rebased on resume, so catch/finally across awaits function.
- Async bodies with no `await` still settle through microtasks.
- `for await (... of ...)` parses and executes over `Symbol.asyncIterator` iterators and sync iterables; each iteration awaits the step result and the produced value.
- `Symbol.asyncIterator` is defined.

Validation: **258 FPCUnit tests** (two new async tests), **90 documentation claims**, curated corpus **147 records — 131 pass, 16 fail** (attempted pass rate 131/147 = 89.12%). Seven upstream `for await` tests were added and pass. Async generator functions (`async function*`) were not yet supported at this point; a later phase added them.

## Phase 10.8 result

The binary and reflection layer is implemented:

- `ArrayBuffer` with `byteLength`, `slice`, `isView`, and zero-initialized bytes.
- `Uint8Array`, `Int8Array`, `Uint8ClampedArray`, `Uint16Array`, `Int16Array`, `Uint32Array`, `Int32Array`, `Float32Array`, and `Float64Array` over array buffers or array-likes; numeric indexing, `length`, `byteLength`, `byteOffset`, `buffer`, `set`, `subarray`, `slice`, and `fill` work.
- `DataView` with `getInt8`/`getUint8`/`getInt16`/`getUint16`/`getInt32`/`getUint32`/`getFloat32`/`getFloat64` and matching setters, including big-endian flags.
- `Reflect` with `get`, `set`, `has`, `deleteProperty`, `ownKeys`, `getPrototypeOf`, `setPrototypeOf`, `apply`, `construct`, `defineProperty`, `getOwnPropertyDescriptor`, `isExtensible`, and `preventExtensions`.
- `WeakMap`/`WeakSet` expose the Map/Set API. They are not truly weak yet and accept primitive keys; that is documented as a limitation.

Validation: **260 FPCUnit tests** (two new binary/reflection tests), **90 documentation claims**, curated corpus **167 records — 151 pass, 16 fail** (attempted pass rate 151/167 = 90.42%). Ten upstream binary/Reflect/weak-collection tests were added.

Still unsupported: `BigInt64Array`/`BigUint64Array`, true weak-reference semantics, and real agent concurrency. `SharedArrayBuffer`, core `Atomics`, and the core `Proxy` property traps are now available. Many TypedArray prototype methods (map/filter/reduce/iteration helpers) and species/constructor corner cases remain future work.

## Phase 10.9 result

Static ES modules were executed by a diagnostic adapter. This phase has since
been superseded by engine-level module records (see "ECMAScript module
records" below); the historical bundler, `test262/tools/modules.py`, has been
removed.

- The bundler resolved relative imports recursively, read `_FIXTURE` modules, detected cycles, and lowered the graph into one script with module-scoped function bodies.
- `import` forms: default, namespace, named aliases, bare side-effect imports.
- `export` forms: default expressions/functions/classes, named variable/function/class declarations, export lists, re-exports, and `export *`.
- The runner writes a temporary bundle, evaluates it in the normal fresh host process, then records `moduleBundle` and a stable relative `moduleGraph`.
- Module plans use strict host execution, as modules are strict code.
- Missing modules, unsupported specifiers, and escaping paths are reported as harness errors before execution.

Validation: **260 FPCUnit tests**, **90 documentation claims**, module adapter fixtures **2 tests**, curated corpus **182 records — 166 pass, 16 fail** (attempted pass rate 166/182 = 91.21%). Fifteen upstream module tests were added.

Limitations at that phase: bindings were snapshots, cycles were rejected, and `import.meta`, dynamic `import()`, and import attributes were not implemented. Later Phase 10.10 work added live bindings, cycles, `import.meta`, dynamic import, and JSON attributes.

## Phase 10.10 result

Realms are now exposed through the diagnostic host:

- `$262.createRealm()` creates a genuinely separate `TFloriaJSContext`: its own heap, global object, intrinsics, timer registry, and output list.
- The returned realm object exposes `global` and `evalScript`; `evalScript` evaluates re-entrantly in the realm that owns the receiver.
- Realm bindings and global properties do not leak into the caller realm, and caller bindings do not leak into the realm.
- `$262.agent` provides cooperative single-threaded agents; it is not a preemptive thread implementation.

Validation: **271 FPCUnit tests** (eleven new realm/async-generator/coercion/strict/binary/proxy tests), **90 documentation claims**, host fixtures **36 checks + 1 timeout**, focused realm corpus **50 records — 50 pass** (100%), focused async-generator corpus **36 records — 36 pass** (100%), focused `Symbol.toPrimitive` corpus **10 records — 10 pass** (100%), focused strict early-error corpus **14 records — 14 pass** (100%), focused strict-escape corpus **18 records — 18 pass** (100%), focused module-cycle corpus **7 records — 7 pass** (100%), focused SharedArrayBuffer/Atomics corpus **30 records — 30 pass** (100%), focused BigInt Atomics corpus **18 records — 18 pass** (100%), focused import-attributes corpus **10 records — 10 pass** (100%), focused Proxy corpus **46 records — 44 pass, 2 fail** (attempted pass rate 44/46 = 95.65%), focused Proxy-invariant corpus **21 records — 21 pass** (100%), focused reserved-word corpus **85 records — 85 pass** (100%), focused with-statement corpus **14 records — 14 pass** (100%), focused agent corpus **14 records — 14 pass** (100%), curated corpus **354 records — 338 pass, 16 fail** (attempted pass rate 338/354 = 95.48%). Twelve cross-realm, twelve async-generator, five `Symbol.toPrimitive`, fourteen strict early-error, four strict-escape, three module-cycle, six SharedArrayBuffer/Atomics, six BigInt Atomics, five import-attribute, twelve Proxy, five Proxy-invariant, six reserved-word, four with-statement, and three agent tests were added to the curated corpus.

Limitations: module exports are live getters, named imports are rewritten to live property reads, and star-export cycles are supported. Exported `let`/`const` keep their TDZ. `import.meta`, dynamic `import()` for relative specifiers, JSON import attributes, and text modules are supported. JSON module objects/arrays are stable and extensible. Cross-realm intrinsic selection is implemented for Array, ArrayBuffer, DataView, Promise, String, typed arrays, and array species. `Symbol.toPrimitive` is consulted before `valueOf`/`toString`, and property keys, `String()`, and `String.prototype.concat` use the full ToString path. Some built-ins still use the simpler conversion. Strict mode now rejects legacy octal literals, legacy octal escape sequences, `delete` of identifiers, `eval`/`arguments` bindings, and the strict future reserved words (`implements`, `interface`, `package`, `private`, `protected`, `public`, `static`, `yield`, `let`). Async generators support `yield`, `await`, `for await`, and `yield*`; yielded promises are awaited, sent values are forwarded to the inner iterator, and the async-generator prototype chain is present. `yield*` forwards `return`/`throw`, adopts thenables, and passes the exact ordering tests. `SharedArrayBuffer`, BigInt typed arrays, and the core `Atomics` operations are implemented; `Atomics.wait` is single-threaded and returns `timed-out` when no other agent can notify. `Atomics.waitAsync` returns the expected result shape and resolves registered waiters when `Atomics.notify` is called, including across cooperative agents. `Proxy` supports the core property traps, `apply`/`construct`, `Proxy.revocable`, and the main property invariants; the `with` statement is supported in sloppy mode and rejected in strict mode. `$262.agent` uses a cooperative single-threaded scheduler; real preemptive concurrency remains unsupported.

## Phase 11 result — scale reporting and CI

The diagnostic runner now scales without sharing runtime state:

- `--jobs N` executes up to `N` scenarios concurrently, each in a separate host process. Records remain in plan order, so sequential and parallel reports are identical after elapsed-time fields are removed.
- `--max-duration SECONDS` adds a global deadline. Scenarios that would cross it are bounded and reported as `timeout`; already-running hosts are killed by their per-scenario timeout.
- `tools/results.py markdown` renders deterministic Markdown with overall, per-directory, and per-feature coverage plus a non-passing scenario list.
- `tools/ci_smoke.sh` remains the short pull-request gate. `TEST262_JOBS` enables bounded parallelism; the curated Markdown summary is written to `results/ci/`.
- `tools/ci_extended.sh` is the longer scheduled/manual diagnostic with a larger timeout, a global deadline, separate `results/extended/` output, and a combined Markdown summary.
- `.github/workflows/test262-extended.yml` runs the extended job weekly or on manual dispatch and uploads its reports.
- `tools/review_upstream_update.sh` prints the upstream diff and a review checklist; `--apply` writes the pin only when the checkout is already at the candidate revision.
- Reports record `jobs` and `maxDurationSeconds` alongside the pinned revisions, policy hash, and host hash.

Validation: adapter fixtures pass (including Markdown rendering and sequential/parallel equivalence); `ci_smoke.sh` passes with no regressions; `ci_extended.sh` completes all 16 reviewed corpora under a 600-second global budget with **742 records — 724 pass, 18 known fail**. Markdown summaries are diagnostic views, not conformance certificates.

## Phase 12 result — curated conformance gaps

The recorded curated failures are now closed except for `eval`:

- `new String(value)` returns a real boxed String object with `String.prototype` as its prototype. `String.prototype.toString`/`valueOf` unwrap it, loose equality sees its primitive value, `typeof` is `"object"`, and `String.prototype.constructor` is `String`.
- `Array.prototype` now has a non-enumerable `length` and `constructor`, so `new Proxy(Object.create(Array.prototype), {})` and `"length" in target` follow the prototype chain.
- `Promise.all` settles its result through the microtask queue instead of synchronously. Reactions registered on input promises earlier now run in the specification order.
- Array indices in `[0, 2^32 - 2]` extend `length`. Indices at or above the dense threshold are stored in an overflow list rather than forcing a multi-gigabyte allocation; `length` accepts the full `2^32 - 1` boundary.
- `eval` remains absent and is the only remaining curated failure: four records (two tests in both variants). It is not approximated with global-only semantics.

Validation: **275 FPCUnit tests**, **90 documentation claims**, focused Proxy corpus **46 records — 46 pass**, curated corpus **354 records — 350 pass, 4 fail** (attempted pass rate 98.87%), extended diagnostic **742 records — 738 pass, 4 fail**. The four remaining failures are `eval`.

## Phase 13 result — eval and lexical whitespace

The last curated gap is closed:

- `eval` is a real intrinsic function. A syntactic call to the identifier `eval` runs in the caller's environment and returns the evaluated completion value. A shadowed `eval` binding falls back to a normal call.
- Indirect eval (`var e = eval; e(source)`) and `Reflect`-style calls run in the global environment.
- Non-string arguments are returned unchanged; parse and compile errors become catchable `SyntaxError` objects.
- Strict eval gets its own variable environment, so its `var` declarations do not leak into the caller. Non-strict direct eval shares the caller's environment, including `var` declarations.
- Evaluation is re-entrant: it skips heap collection and microtask draining while the caller's VM frame still holds live values.
- The lexer now treats U+00A0 as whitespace and U+2028/U+2029 as line terminators, and tracks CR (including CRLF) as a line terminator so ASI works in evaluated source.
- `if` statements reset the top-level completion value to `undefined` when neither branch produces one, matching eval completion semantics.
- Non-strict eval `var` declarations reach the caller's variable environment, while `let`/`const` declarations are scoped to the eval and disappear afterwards.

Validation: **276 FPCUnit tests**, **90 documentation claims**, curated corpus **354 records — 354 pass** (100%), extended diagnostic **742 records — 742 pass** (100%).

## Performance phase (P3)

The P3 performance work is complete and did not change Test262 outcomes:

- function parameters and `var` bindings resolve to frame slots in leaf functions;
- ordinary objects carry shape tokens with per-site inline property caches;
- the dispatch exception frame is entered once per run;
- numeric array keys take a direct index path;
- `TFloriaJSValue` is 32 bytes;
- simple FTML bindings compile to AOT snippets.

Validation at the end of P3: **281 FPCUnit tests**, **90 documentation claims**,
curated corpus **354 records — 354 pass**, extended diagnostic **742 records —
742 pass**.

## Library and iteration gap closure

The following previously documented gaps are closed:

- `Array.prototype.keys` and `entries` return iterator objects over the
  receiver's indices and `[index, value]` pairs.
- `Object.fromEntries` accepts any iterable of entry objects, including `Map`.
- `for…in` accepts a destructuring target and enumerates string indices.
- Object spread from an array copies its present element indices.
- `String.prototype.normalize` supports NFC, NFD, NFKC, and NFKD using generated
  Unicode tables.
- `String.prototype.localeCompare` compares canonically equivalent strings as
  equal, using deterministic code-point order rather than locale collation.

Along the way, iterator teardown, `\xNN` and legacy-octal escapes above 0x7F,
and native-method constructability and `length` metadata were corrected.

Focused corpus: `config/library-gaps-tests.txt` — **90 records, all pass**.
Validation at that point: **282 FPCUnit tests**, **90 documentation claims**,
curated corpus **354 records — 354 pass**, extended diagnostic **832 records —
832 pass**.

## Coercion completeness closure

The following coercion gaps are closed:

- `Array.prototype.join`/`toString` convert each element with the full ToString
  path, and `join` works on any array-like receiver (including strings and
  plain objects), reading holes through the prototype chain.
- `parseInt` and `parseFloat` convert their argument with ToString, honour the
  ECMAScript whitespace set, and `parseInt` accumulates past 2^63 as a Number.
- The URI helpers convert with ToString and implement UTF-8 percent encoding
  and validation: overlong forms, surrogate halves, truncated sequences, and
  out-of-range code points raise `URIError`. `decodeURI` preserves the source
  spelling of reserved characters.
- `Error` and its subclasses convert the message with ToString, define
  `message` as an own non-enumerable property only when supplied, install
  `options.cause`, and reject a Symbol message with `TypeError`.
- The Proxy `has` invariant also throws for a non-extensible target, which
  completes the `with`-statement cases.

Along the way, boxed Number and Boolean objects, `Object.prototype.isPrototypeOf`,
`Error`/`URIError` prototype chains, `Function.prototype.length`, and the sign of
`1 / -0` were corrected, and the bitwise/shift compound assignments (`&=`, `|=`,
`^=`, `<<=`, `>>=`, `>>>=`) were added to the lexer, parser, and compiler.

Focused corpus: `config/coercion-tests.txt` — **608 records, all pass**. The
corpus excludes lone-surrogate/noncharacter tests (UTF-8 storage cannot
represent them), resizable-buffer tests, cross-realm `Error` prototype
derivation, and two four-nested-loop URI tests that exceed the diagnostic
timeout. `S15.1.3.4_A2.3_T1.js` walks 51 000 code points and takes about 26 s
in a single host process, so the coercion corpus runs with a 180 s
per-scenario budget; the cost is the interpreter's loop throughput, identical
before and after the module work.

Validation: **283 FPCUnit tests**, **106 documentation claims**, curated corpus
**354 records — 354 pass**, extended diagnostic **1440 records — 1440 pass**.

## Modern built-in library closure

The following standard-library additions are implemented:

- `Object.hasOwn`, `Object.groupBy`, `Object.getOwnPropertyDescriptors`,
  `Object.defineProperties`, and `Object.getOwnPropertySymbols`.
- `Array.prototype.findLast`, `findLastIndex`, `toSorted`, `toReversed`,
  `toSpliced`, and `with`.
- `String.prototype.at` and `matchAll`.
- `Promise.allSettled` and `Promise.any`.
- `Number.isSafeInteger`.
- `Math.fround`, `expm1`, `log1p`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`,
  and `atanh`.
- `AggregateError`, `Map.groupBy`, `queueMicrotask`, and `structuredClone`.
- The well-known symbols `Symbol.match`, `matchAll`, `replace`, `search`, and
  `split`, plus `RegExp.prototype[Symbol.matchAll]`.

Along the way, the host report now sanitises invalid UTF-8 (a lone surrogate
would otherwise break the JSON stream), empty regular expressions compile as
`(?:)`, and `Object.prototype.isPrototypeOf` was added.

Focused corpus: `config/modern-builtins-tests.txt` — **1494 records, all pass**.
The corpus is the passing subset of the upstream directories. Tests that depend
on documented gaps are excluded: Promise subclassing/species, descriptor
edge cases in `Object.defineProperties`, generic array-like boxing, the full
`@@matchAll` protocol, resizable buffers, and lone surrogates.

Validation: **284 FPCUnit tests**, **150 documentation claims**, curated corpus
**354 records — 354 pass**, extended diagnostic **3446 records — 3446 pass**.

## Function.prototype.toString source retention

`Function.prototype.toString` now returns the function's original source text,
including comments and whitespace:

- Declarations, expressions, arrows, generators, async functions, methods, and
  accessors report their exact spelling from the source.
- A class constructor reports the whole `class ... { ... }` definition.
- A built-in, a bound function, or a callable proxy reports the native
  placeholder `function name() { [native code] }`.
- A non-callable receiver throws `TypeError`, and the method has the standard
  `length`/`name`/descriptor metadata and no `prototype` property.

Supporting fixes: the `Function(...)` constructor now formats its synthesized
source with newlines before the closing punctuation, the host report sanitises
invalid UTF-8, and the regex engine translates `\uXXXX` escapes to TRegExpr's
`\x{...}` form where it can.

Focused corpus: `config/function-tostring-tests.txt` — **72 records, all pass**.
The corpus is the passing subset. Excluded tests need computed class members,
class fields, private methods, async/generator methods, the `AsyncFunction` and
`GeneratorFunction` constructors, Unicode escapes in identifiers, the
`@@match` protocol on `RegExp`, or the Unicode regexes in
`nativeFunctionMatcher.js`.

Validation: **285 FPCUnit tests**, **150 documentation claims**, curated corpus
**354 records — 354 pass**, extended diagnostic **3446 records — 3446 pass**.

## Prototype constructor back-references

Every prototype now has a real own `constructor` data property:

- It is writable, non-enumerable, and configurable, and
  `Object.getOwnPropertyNames` reports it.
- Replacing `Foo.prototype` leaves the old prototype's `constructor` pointing at
  `Foo`; a fresh plain prototype inherits `Object.prototype.constructor`.
- Classes get the same back-reference from the generated prototype.
- The property stores the function without retaining it, and the function
  clears it on destruction, so a function and its prototype are still
  reclaimed together.

Every built-in prototype received its `constructor` as well (`Array`, `Object`,
`Function`, `Map`, `Set`, `RegExp`, `Date`, `Number`, `String`, `Boolean`,
`Symbol`, `Promise`, the error types, `ArrayBuffer`, `SharedArrayBuffer`,
`DataView`, the typed arrays, and `URIError`).

Supporting fix: `Object.prototype.valueOf` was missing and is now present.

Focused corpus: `config/prototype-constructor-tests.txt` — **22 records, all
pass**.

Validation: **286 FPCUnit tests**, **150 documentation claims**, curated corpus
**354 records — 354 pass**, extended diagnostic **3446 records — 3446 pass**.

## WeakMap and WeakSet weakness

`WeakMap` and `WeakSet` are now genuinely weak:

- They are separate classes from `Map`/`Set`, so the internal-slot brand check
  works (`WeakMap.prototype.set.call(new Map(), …)` throws `TypeError`).
- A key or value is stored without taking a reference. The heap keeps a list of
  weak collections and prunes an entry whose key has become unreachable, before
  and after each sweep.
- The constructors reject primitive keys and are not callable without `new`.
- `WeakMap` gains `getOrInsert` and `getOrInsertComputed`.
- Neither collection is iterable and neither has a `size`.

Supporting fixes: `Object.prototype.toString` now honours `Symbol.toStringTag`
(including inherited tags), symbol-keyed descriptor lookups resolve a
well-known symbol spelled by description, and `Map`/`Set`'s error paths build
real `TypeError` objects.

Focused corpus: `config/weak-collections-tests.txt` — **418 records, all pass**.
The corpus is the passing subset of the upstream `WeakMap`/`WeakSet`
directories; excluded tests depend on iterator-protocol abrupt-completion
ordering (a general limitation) and the `WeakMap`/`WeakSet` `undefined`
new-target case.

Validation: **287 FPCUnit tests**, **150 documentation claims**, curated corpus
**354 records — 354 pass**, extended diagnostic **3446 records — 3446 pass**.

## ECMAScript module records

Modules are no longer lowered by a Python bundler; the engine implements them:

- The lexer, parser, and AST cover `import`/`export` in every form, and module
  declarations are rejected outside a module and outside the top level.
- A module record holds `[[ImportEntries]]`, `[[LocalExportEntries]]`,
  `[[IndirectExportEntries]]`, `[[StarExportEntries]]`, and
  `[[RequestedModules]]`, with the lifecycle status of the specification.
- `ResolveExport` implements local precedence, indirect forwarding, star-export
  search with ambiguity detection, and a resolve-set cycle guard.
- Linking validates that every import resolves and that export names are unique
  and declared; evaluation is depth-first and cycle-safe, each module body runs
  in its own scope, and imports are live.
- `import.meta`, dynamic `import()`, `export *`, `export * as ns`, re-exports,
  string export names, and import attributes are supported.
- Link failures are reported as a distinct `resolution` phase: a missing or
  ambiguous export, an unresolved specifier, an unknown import-attribute key,
  and a dependency that does not parse all satisfy a `phase: resolution`
  negative test.
- Module early errors are enforced: top-level `return`/`yield`/`await`/`super`,
  reserved words in strict module code, `eval`/`arguments` bindings, duplicate
  labels, duplicate top-level lexical bindings, and functions that clash with a
  `var`.
- A namespace is a real exotic object: null prototype, non-extensible, data
  descriptors with `[[Writable]]` true and `[[Configurable]]` false,
  `Symbol.toStringTag` `"Module"`, and a [[Set]] that refuses every write.
- The diagnostic host supplies a loader for relative paths plus JSON and text
  modules.

Focused corpus: `config/module-record-tests.txt` — **548 records, all pass**.
The corpus is the passing subset of `language/module-code` (599 records). The
51 remaining failures depend on class fields, private names, source-phase
imports, or top-level-await tick ordering rather than on the module machinery.
Module-native work is complete: linking, resolution-phase errors, module early
errors, live bindings, and the namespace exotic object all behave as the
specification requires.

Validation: **288 FPCUnit tests**, **155 documentation claims**, curated corpus
**354 records — 354 pass**, extended diagnostic **3446 records — 3446 pass**.

## Next phase

Phase 10, Phase 11, Phase 12, and Phase 13 are complete, as is the P3 performance
work, the library/iteration gap closure, the coercion-completeness closure, the
modern built-in library closure, `Function.prototype.toString` source retention,
the prototype constructor back-reference work, and true weak collections. Further conformance work should start from the recorded gaps rather than adding superficial host stubs.
