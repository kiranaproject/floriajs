# Phase 0 baseline

**Recorded:** 2026-11-13  
**Engine source revision:** `d4b226d255e169b24e09d7635cdd6bd06e88eac4`  
**Pinned Test262 revision:** `2e58f87d8350ad51224617a041c6e041d52f8444`  
**FPC:** 3.2.3  
**PasBuild:** 1.9.0  
**Runtime changes in Phase 0:** none

This is a baseline of the existing tests and diagnostic probes. It is not an official Test262 result and contains no conformance pass-rate claim.

## Existing FPCUnit suite

Command:

```sh
pasbuild test
```

Result: **PASS**

```text
N:223 E:0 F:0 I:0
Number of run tests: 223
Number of errors:    0
Number of failures:  0
```

The library compilation, test compilation, and all registered test suites completed successfully.

## Documentation claims

Command:

```sh
bash scratch/run_docclaims.sh
```

Result: **PASS**

```text
88 claims, 0 failed
```

These claims describe the current runtime, including intentional deviations from ECMAScript. They do not mean those deviations are standards-conformant.

## Gap scans

Command:

```sh
bash scratch/run_gapscan.sh
```

Result: **COMPLETED** (exit status 0)

| Program | Probes | `OK` rows | `ERR` rows |
| --- | ---: | ---: | ---: |
| `gapscan` | 81 | 79 | 2 |
| `gapscan2` | 113 | 107 | 6 |
| Total | 194 | 186 | 8 |

The gap-scan programs print outcomes rather than assert all expected results. Their `ERR` rows are existing JavaScript exceptions and parse failures, not failed FPCUnit tests. Examples include expected throws, `const` reassignment, unsupported `alert`, rejected `with`, calling a non-function, and an invalid assignment target. These rows are diagnostic observations, **not eight certified ECMAScript passes or failures**.

Some output is inherently variable (for example Date values), so raw gap-scan output is not treated as a golden text baseline. Re-run the same commands to review changes rather than diffing timestamps.

## Smoke-corpus review

Eight upstream files were selected from the pinned Test262 revision after reading their source and metadata. Their exact paths and rationale are in `test262/config/smoke-tests.txt`.

For readiness only, each selected file was evaluated in a fresh invocation of the existing `scratch/evalone` probe, with the current upstream `sta.js` and `assert.js` prepended to the source. All eight invocations returned an `OK` result for the selected cases at the engine revision above.

That review is deliberately **not** called an official Test262 run because:

- the probe is not a Test262 host;
- harness and test text were concatenated rather than executed by the future structured scenario host;
- there was no metadata-driven scenario expansion or negative verdict handling;
- there was no Test262-specific timeout, result schema, or coverage accounting;
- strict scenarios were not claimed.

The purpose was to avoid adding obviously unusable inputs to the initial smoke corpus. The future adapter must re-evaluate every selected test and produce its own structured verdicts.

## Frozen scope

The selected tests use only non-strict synchronous readiness paths. `raw`, default strict scenarios, `onlyStrict`, `module`, `async`, `intl402`, `_FIXTURE` files, and unsupported host capabilities are governed by `test262/config/feature-policy.json`.

See `docs/test262.md` for the complete policy and result vocabulary.
