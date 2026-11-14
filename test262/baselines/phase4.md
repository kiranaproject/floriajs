# Phase 4 synchronous validation baseline

**Recorded:** 2026-11-14  
**FloriaJS source revision:** `d4b226d255e169b24e09d7635cdd6bd06e88eac4` plus diagnostics, host, metadata planner, and synchronous runner changes in the working tree  
**Pinned Test262 revision:** `2e58f87d8350ad51224617a041c6e041d52f8444` (`package.json` version `5.0.0`)  
**FPC:** 3.2.3  
**PasBuild:** 1.9.0  
**Metadata environment:** PyYAML 6.0.3

These are focused smoke results, not a full-suite Test262 conformance claim.

## Reviewed upstream smoke corpus

The pinned harness and eight reviewed smoke sources were fetched from the upstream revision into a temporary review checkout. The runner was invoked with:

```sh
python3 tools/run_test262.py \
  --root /tmp/opencode/floria-phase4-upstream \
  --allow-unpinned \
  --list config/smoke-tests.txt
```

Result: **8 `pass` results and 7 explicit strict `skipped` results**.

Each of these eight files returned host exit code `0` with host outcome `pass`:

- `language/expressions/addition/S11.6.1_A2.1_T1.js`
- `language/statements/function/S13.2.1_A6_T1.js`
- `language/statements/function/S13_A18.js`
- `language/statements/try/S12.14_A1.js`
- `built-ins/Array/S15.4_A1.1_T4.js`
- `built-ins/Object/keys/15.2.3.14-2-1.js`
- `built-ins/Promise/all/S25.4.4.1_A1.1_T1.js`
- `built-ins/Promise/resolve/S25.4.4.5_A1.1_T1.js`

Every applicable default test also produced its separate strict skip. `S13.2.1_A6_T1.js` is `noStrict`, so only the seven default tests have the extra strict skip.

The official `assert.js` → `sta.js` harness sequence was used, followed by any metadata includes. No source was rewritten, and Test262 frontmatter comments remained harmless JavaScript comments.

This validation is explicitly **not** a result for the complete Test262 suite or its strict scenarios.

## Integration fixture

Command:

```sh
python3 tools/run_sync_smoke.py --root /tmp/opencode/floria-phase4-upstream
```

Result: **8 integration tests passed**.

Verified outcomes:

- Repeating the reviewed smoke run yields identical semantic JSON after removing `durationMs`.
- A deliberately failing `assert` returns `fail` and host exit `1`, not `harness-error`.
- A failed include returns `harness-error`, identifying the harness role and index.
- A missing include returns a setup error before any host process executes.
- A negative runtime expectation returns `unsupported`, defers verdicts to Phase 5, and emits no host command/result.
- An infinite loop is killed by the external deadline and returns `timeout`.
- A host that returns no JSON returns `crash`, not a semantic failure.

## Runtime compatibility

The Phase 1/2 engine and host protocols remain unchanged. Root FPCUnit remains at **231 passing tests** and **88/88 documentation claims** after this phase. The new changes are confined to the synchronous orchestration tool, review fixtures, policy status, and documentation.
