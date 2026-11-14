# Phase 6 baseline and coverage report

**Recorded:** 2026-11-14  
**FloriaJS source revision:** `d4b226d255e169b24e09d7635cdd6bd06e88eac4` plus diagnostics, host, planner, synchronous runner, negative-verdict, and reporting changes in the working tree  
**Pinned Test262 revision:** `2e58f87d8350ad51224617a041c6e041d52f8444` (`package.json` version `5.0.0`)  
**Runner version:** `0.6.0`  
**FPC:** 3.2.3  
**PasBuild:** 1.9.0  
**Metadata environment:** PyYAML 6.0.3  
**Host SHA-256:** `fa5255b5dc6bd8e34995b6504fb859cbd1b29addedb25ae50910698384f08001`

These are focused reviewed-corpus results, not a full-suite Test262 conformance claim.

## Report format

`tools/results.py` defines `schemaVersion: 1` reports with the following top-level fields:

```text
schemaVersion, kind, runnerVersion, generatedAt,
engine { revision, workingTreeDirty },
upstream { root, expectedRevision, actualRevision, packageVersion, revisionVerified },
policy { name, status, sha256 },
host { path, sha256, bytes },
platform { system, release, machine, python },
options { timeoutSeconds, allowUnpinned, selection, listFile },
summary { total, outcomes, coverage, attemptedPassRate, directories, features },
records [ ... ]
```

`--output` writes the records alone as JSONL. `--report` writes the complete document. A report is produced even when the run ends with an infrastructure failure, so a crash or harness error is always preserved.

## Summary model

- `outcomes` always contains every vocabulary entry, including zeros.
- `coverage.attempted = pass + fail`.
- `coverage.infrastructure = harness-error + timeout + crash`.
- `coverage.skipped` and `coverage.unsupported` remain separate from attempts.
- `attemptedPassRate = pass / (pass + fail)`, `null` when nothing was attempted.
- `directories` groups by the test path's parent directory.
- `features` groups by metadata `features`; tests without declared features use `(none)`.

## Reviewed upstream smoke corpus

Command:

```sh
cd test262
python3 tools/run_test262.py \
  --root .upstream \
  --list config/smoke-tests.txt \
  --report results/smoke-report.json \
  --baseline baselines/phase6-smoke.json \
  --fail-on-regression
```

Result: **8 `pass`, 7 `skipped`**, no failures or infrastructure outcomes. Compared with the reviewed baseline: no regressions. Stored as `baselines/phase6-smoke.json` (15 records).

## Reviewed curated corpus

`config/curated-tests.txt` contains 23 reviewed tests. Command:

```sh
python3 tools/run_test262.py \
  --root .upstream \
  --list config/curated-tests.txt \
  --report results/curated-report.json \
  --baseline baselines/phase6-curated.json \
  --fail-on-regression
```

Result: **46 scenario records: 20 pass, 3 fail, 23 skipped**. Attempted pass rate: **20/23 = 86.96%**. No `unsupported`, `harness-error`, `timeout`, or `crash` outcomes. Stored as `baselines/phase6-curated.json`.

| Directory | Pass | Fail | Skipped | Attempted pass rate |
| --- | ---: | ---: | ---: | ---: |
| `built-ins/Array` | 3 | 1 | 4 | 75.00% |
| `built-ins/Object/keys` | 2 | 0 | 2 | 100.00% |
| `language/expressions/addition` | 3 | 1 | 4 | 75.00% |
| `language/expressions/assignment` | 5 | 0 | 5 | 100.00% |
| `language/expressions/logical-and` | 2 | 0 | 2 | 100.00% |
| `language/statements/for` | 1 | 0 | 1 | 100.00% |
| `language/statements/if` | 1 | 1 | 2 | 50.00% |
| `language/statements/try` | 3 | 0 | 3 | 100.00% |

The direct repository also produced 23 strict `skipped` records: one per default test. The three negative parse tests (`target-null.js`, `target-string.js`, `target-number.js`) pass through the Phase 5 early-error comparison.

### Explaining every failure and skip

Each curated file is a default or `noStrict` test with an explicitly reviewed outcome:

| Test | Outcome | Explanation |
| --- | --- | --- |
| `language/expressions/addition/S11.6.1_A1.js` | `fail` | Uses the unimplemented global `eval`; runtime `ReferenceError: eval is not defined`. |
| `language/statements/if/cptn-else-false-nrml.js` | `fail` | Uses the unimplemented global `eval`; runtime `ReferenceError: eval is not defined`. |
| `built-ins/Array/S15.4.5.2_A1_T1.js` | `fail` | Assigning index `2147483648` does not extend `length`; the harness throws, and the host reports the non-Error object as `[object Object]`. |
| Every `::strict` record | `skipped` | Frozen policy: genuine strict-mode semantics are absent. |

No curated test was skipped for unrelated reasons, and no file was filtered out because it failed. The two `eval` failures and the large-index array failure are recorded as real language gaps for later engine work.

## Baseline normalization

`tools/results.py normalize` removes `generatedAt`, durations, absolute repository roots, the host executable path, absolute harness/source paths, and record ordering. Verified properties:

- two runs over the same sources normalize to identical JSON;
- no absolute workspace path appears in the checked-in baseline;
- no `durationMs` field appears anywhere;
- records are sorted by `scenarioId`.

## Baseline diff

`tools/results.py compare BASELINE CURRENT --fail-on-regression` displays added, removed, and changed scenarios. Categories include:

- `new-failure`, `new-crash`, `new-timeout`, `new-harness-error`;
- `failure-fixed`, `infrastructure-recovered`;
- `unsupported-to-supported`, `skipped-to-supported`;
- `supported-to-unsupported`, `newly-skipped`;
- `added-failure`, `added-crash`, `added-timeout`, `added-harness-error`, `added-pass`, `added-skipped`, `added-unsupported`.

Exit status is `3` when a regression is present and `--fail-on-regression` is set. A new failure that exists only because a test was newly added to the corpus is still surfaced, but it is listed separately from pass-to-fail changes so a reviewer can distinguish a regression from expanded coverage.

Verified during this phase:

- an unchanged rerun produces no diff and status `0`;
- flipping a `pass` record to `fail` produces one `new-failure` and status `3`;
- adding a `crash` record produces an `added-crash` regression;
- changing `unsupported` to `pass` produces `unsupported-to-supported`.

## Adapter fixture suites

| Suite | Result |
| --- | --- |
| `tools/run_host_smoke.py` | 20 fixture checks plus one external-timeout check |
| `tools/run_metadata_smoke.py` | 22 tests passed |
| `tools/run_negative_smoke.py` | 9 test methods passed |
| `tools/run_report_smoke.py` | 5 tests passed |
| `tools/run_sync_smoke.py` | 8 tests passed against the pinned review checkout |

`run_report_smoke.py` covers report metadata, JSONL equality with stdout, per-directory/per-feature summaries, portable normalization, regression/improvement/infrastructure classification, exit status `3`, and a missing checkout failing as `harness-error` without host execution.

## CI

`tools/ci_smoke.sh` builds the host, runs all four adapter suites, and executes both reviewed corpora against the checked-in baselines with `--fail-on-regression`. Generated reports land in `test262/results/ci/`, which is ignored by Git. `.github/workflows/test262-smoke.yml` invokes this script on pushes and pull requests that touch `test262/` or `src/main/pascal/`.

The workflow is authored and locally validated through `ci_smoke.sh`, but it has not run on hosted GitHub Actions yet. It is a limited, explicit-corpus job, not a full-suite diagnostic run.

## Reproducing a full diagnostic run

The curated corpus is intentionally small. For an optional broader diagnostic run, supply an explicit path list from a full pinned checkout; do not use an unpinned checkout for a report you intend to compare:

```sh
python3 tools/run_test262.py \
  --root /path/to/pinned/test262 \
  --list /path/to/explicit-paths.txt \
  --timeout 10 \
  --report results/full-report.json
```

This writes a report but does not update a reviewed baseline. Broad-corpus results remain diagnostic until they are reviewed file by file.

## Runtime compatibility

Phase 6 changed only the Python runner, reporting tools, configuration, fixtures, and documentation. No Pascal engine source, public `Evaluate()` API, or host protocol changed. Root FPCUnit remains at **231 passing tests**, and documentation claims remain at **88 passing claims**.
