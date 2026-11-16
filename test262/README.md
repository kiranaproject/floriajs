# FloriaJS Test262 workspace

This directory holds the configuration and baselines for the proposed diagnostic Test262 adapter.

**Current status:** Phases 0–13 are complete. The adapter covers the pinned metadata planner, single-scenario host, synchronous and asynchronous runner, negative verdicts, durable reports, reviewed baselines, timers, realms, modules, binary/Atomics data, Proxy, cooperative agents, and async generators. Phase 11 adds bounded process-level parallelism, a global run deadline, Markdown coverage summaries, a separate extended diagnostic job, and a reviewed upstream-update workflow. Phase 12 closes the curated boxed-String, Promise.all ordering, Proxy `has`, and large-array-index gaps. Phase 13 adds direct/indirect `eval`, Unicode whitespace and CR line handling, so the curated corpus is fully passing. This remains a diagnostic adapter, not a full ECMAScript conformance certificate.

See the [Test262 support guide](../docs/test262.md) for current capabilities and gaps, the [runner guide](../docs/test262-runner.md) for commands, and [the Phase 10 baseline](baselines/phase10.md) for milestone details.

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
- `config/*-tests.txt` — reviewed smoke, focused, and curated corpora.
- `tools/prepare_test262.py` — metadata scenario planner (no execution).
- `tools/run_test262.py` — scenario runner with per-test timeout, bounded `--jobs` parallelism, a global deadline, and report output.
- `tools/results.py` — report schema, summaries, baseline normalization, diff, and Markdown rendering.
- `tools/run_sync_smoke.py` — upstream harness and synchronous integration checks.
- `tools/run_negative_smoke.py` — authored negative-verdict fixture checks.
- `tools/run_report_smoke.py` — report, summary, normalization, and baseline-diff fixtures.
- `tools/run_async_smoke.py` — limited-async completion, failure, missing, and repeated fixtures.
- `tools/run_metadata_smoke.py` — authored metadata/fixture validation.
- `tools/fetch_test262.sh` — pinned sparse checkout setup for the reviewed corpus.
- `tools/ci_smoke.sh` — short deterministic CI entrypoint.
- `tools/ci_extended.sh` — longer scheduled/manual diagnostic with parallelism and a global deadline.
- `tools/review_upstream_update.sh` — deliberate upstream pin review helper.
- `tools/frontmatter.py` — strict UTF-8/YAML frontmatter extraction.
- `tools/scenario.py` — policy, path, include, and argument-list planning.
- `baselines/` — reviewed validation and machine-readable report baselines.
- `THIRD_PARTY_NOTICES.md` — upstream material and licensing notes.
- `.upstream/` — local pinned Test262 checkout, ignored by Git.
- `results/` — generated JSONL/reports, ignored by Git.

Do not put generated upstream files or test results in the reviewed `baselines/` directory. A baseline records a specific engine revision, upstream revision, policy, and reproducible command set.
