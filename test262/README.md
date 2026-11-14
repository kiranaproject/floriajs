# FloriaJS Test262 workspace

This directory holds the configuration and baselines for the proposed diagnostic Test262 adapter.

**Phase 0 status:** complete — baseline, pinned revision, policy, and reviewed smoke corpus established. No claim of full ECMAScript conformance is made.

**Phase 1 status:** complete — the additive phase-aware diagnostics API and its regression tests are implemented. See [detailed execution diagnostics](../docs/api/engine.md#detailed-execution-diagnostics).

**Phase 2 status:** complete — the single-scenario Pascal host and its authored fixture suite are implemented. See the [host guide](../docs/test262-host.md) for the CLI, JSON schema, exit statuses, and smoke commands.

**Phase 3 status:** complete — safe metadata parsing and scenario planning are implemented. See the [planner guide](../docs/test262-plan.md).

**Phase 4 status:** complete — the synchronous Test262 harness runner is implemented. All eight reviewed upstream smoke tests pass, with seven strict scenarios explicitly skipped. See the [runner guide](../docs/test262-runner.md) for commands, results, and integration validation.

**Phase 5 status:** complete — negative-test verdicts compare actual error phase and constructor name with `negative.phase`/`negative.type`, reject wrong-phase, wrong-type, and normal-completion results, and treat `$DONOTEVALUATE()` as a failure rather than an expected parse error. Parser limitations are reported as `unsupported`. See the [Phase 5 baseline](baselines/phase5.md) and the [runner guide](../docs/test262-runner.md#negative-verdicts).

**Phase 6 status:** complete — JSONL and JSON reports carry engine/upstream/host/platform/options metadata and per-directory/per-feature summaries. Reviewed Phase 6 baselines are compared with a regression-aware diff. See the [Phase 6 baseline](baselines/phase6.md) and the [reporting guide](../docs/test262-runner.md#reports-summaries-and-baselines).

**Phase 7 status:** complete — limited async tests load `doneprintHandle.js`, drain Promise jobs, require exactly one done-print completion, and map async failure/repeated completion/missing completion to distinct results. See the [Phase 7 baseline](baselines/phase7.md).

**Phase 8 status:** complete — timers are owned per context, zero-delay callbacks run exactly once, cancellation covers due work, and the host pumps timers plus microtasks through a controlled pending-work API. See the [Phase 8 baseline](baselines/phase8.md).

**Phase 9 status:** complete — `$262.global` exposes the global snapshot, `$262.evalScript` uses a safe re-entrant evaluation path, and unsupported `$262` members are absent and cause explicit feature skips. See the [Phase 9 baseline](baselines/phase9.md).

**Phase 10.1 status:** complete — `let`/`const`/`class` have a temporal dead zone, restricted-production ASI is implemented, and error constructors now identify correctly for `assert.throws`. Current CI baselines are `baselines/phase10-smoke.json` and `baselines/phase10-curated.json`.

**Phase 10.2 status:** complete — real strict-mode execution covers directives, class bodies, undeclared assignments, duplicate parameters, and strict Test262 variants. See the [Phase 10 baseline](baselines/phase10.md#strict-mode-phase-102).

**Phase 10.3 status:** complete — `globalThis` is the live global object, top-level `this` is the global object, and plain non-strict calls receive it. See the [live-global section](baselines/phase10.md#live-global-object-and-this-phase-103).

**Phase 10.4 status:** complete — object-to-primitive coercion uses `valueOf`/`toString` for `+`, loose equality, relational operators, and object numeric conversion. See the [coercion section](baselines/phase10.md#coercion-phase-104).

**Phase 10.5 status:** complete — full writable/enumerable/configurable descriptors, `Object.getOwnPropertyDescriptor`, `defineProperty`, freeze/seal/extensibility, and `propertyIsEnumerable`. See the [descriptor section](baselines/phase10.md#property-descriptors-phase-105).

**Phase 10.6 status:** complete — string length, indexing, slicing, char codes, padding, and iteration use UTF-16 code units at the JS boundary. See the [UTF-16 section](baselines/phase10.md#utf-16-string-semantics-phase-106).

**Phase 10.7 status:** complete — async bodies suspend at `await` and resume on settlement, including try/catch across awaits; `for await` supports async and sync iterables. See the [async section](baselines/phase10.md#async-suspension-and-iteration-phase-107).

**Phase 10.8 status:** complete — ArrayBuffer, typed arrays, DataView, Reflect, and WeakMap/WeakSet. See the [binary section](baselines/phase10.md#binary-reflection-and-weak-collections-phase-108).

**Phase 10.9 status:** complete — static relative modules are resolved, bundled, and evaluated with module-scoped bodies, exports, re-exports, and `moduleGraph` reporting. See the [module section](baselines/phase10.md#modules-phase-109).

**Phase 10.10 status:** complete — `$262.createRealm()` returns a genuinely separate context-owned realm, cross-realm intrinsic selection follows the newTarget realm for the supported constructors, async generators support basic `yield`/`await`/`for await`, `Symbol.toPrimitive` drives object coercion, strict mode rejects legacy octal literals and escape sequences, `delete` of identifiers, `eval`/`arguments` bindings, and strict future reserved words, modules use live export getters with star-export cycle support, `import.meta`, dynamic import, and JSON attributes and text modules, `SharedArrayBuffer`, BigInt typed arrays, and core `Atomics` are available, `Proxy` supports the core property and call/construct traps with the main invariants, and `$262.agent` provides cooperative agents. Current CI baselines are `baselines/phase10-smoke.json`, `baselines/phase10-realms.json`, `baselines/phase10-async-generators.json`, `baselines/phase10-to-primitive.json`, `baselines/phase10-strict-early-errors.json`, `baselines/phase10-module-cycles.json`, `baselines/phase10-atomics.json`, `baselines/phase10-proxy.json`, `baselines/phase10-agents.json`, `baselines/phase10-strict-escapes.json`, `baselines/phase10-bigint-atomics.json`, `baselines/phase10-import-attributes.json`, `baselines/phase10-proxy-invariants.json`, `baselines/phase10-reserved-words.json`, `baselines/phase10-with.json`, and `baselines/phase10-curated.json`. See the [realm section](baselines/phase10.md#realms-phase-1010), the [async-generator section](baselines/phase10.md#async-generators-phase-1010-follow-up), the [coercion section](baselines/phase10.md#symboltoprimitive-phase-1010-follow-up), the [strict section](baselines/phase10.md#strict-early-errors-phase-1010-follow-up), and the [module section](baselines/phase10.md#modules-live-bindings-and-cycles-phase-1010-follow-up).

**Phase 10.9 status:** complete — static relative modules are resolved, bundled, and evaluated with module-scoped bodies, exports, re-exports, and `moduleGraph` reporting. Current CI baselines remain `baselines/phase10-smoke.json` and `baselines/phase10-curated.json`. See the [module section](baselines/phase10.md#modules-phase-109).

## Build and validate the host

```sh
cd test262
pasbuild compile
python3 tools/run_host_smoke.py
```

The host binary is `target/floria-test262-host`. Example:

```sh
./target/floria-test262-host \
  --scenario-id example \
  --harness fixtures/host/harness-one.js \
  --test fixtures/host/pass.js
```

Every invocation evaluates each supplied source once in one context and emits one JSON result. External timeouts are demonstrated by the fixture checker.

See [the Test262 support guide](../docs/test262.md) for execution rules, result definitions, known limitations, and the next implementation step.

## Layout

- `config/test262-revision.txt` — exact upstream commit; change only with a reviewed baseline update.
- `config/feature-policy.json` — frozen scenario, skip, capability, and reporting policy.
- `config/smoke-tests.txt` — eight manually reviewed upstream smoke-test paths.
- `config/curated-tests.txt` — 23-test reviewed synchronous corpus for reporting and CI.
- `tools/prepare_test262.py` — metadata scenario planner (no execution).
- `tools/run_test262.py` — synchronous scenario runner with per-test timeout handling and report output.
- `tools/results.py` — report schema, summaries, baseline normalization, and diff CLI.
- `tools/run_sync_smoke.py` — upstream harness and synchronous integration checks.
- `tools/run_negative_smoke.py` — authored negative-verdict fixture checks.
- `tools/run_report_smoke.py` — report, summary, normalization, and baseline-diff fixtures.
- `tools/run_async_smoke.py` — limited-async completion, failure, missing, and repeated fixtures.
- `tools/run_metadata_smoke.py` — authored metadata/fixture validation.
- `tools/fetch_test262.sh` — pinned sparse checkout setup for the reviewed corpus.
- `tools/ci_smoke.sh` — deterministic CI entrypoint.
- `tools/frontmatter.py` — strict UTF-8/YAML frontmatter extraction.
- `tools/scenario.py` — policy, path, include, and argument-list planning.
- `baselines/` — reviewed validation and machine-readable report baselines.
- `THIRD_PARTY_NOTICES.md` — upstream material and licensing notes.
- `.upstream/` — local pinned Test262 checkout, ignored by Git.
- `results/` — generated JSONL/reports, ignored by Git.

Do not put generated upstream files or test results in the reviewed `baselines/` directory. A baseline records a specific engine revision, upstream revision, policy, and reproducible command set.
