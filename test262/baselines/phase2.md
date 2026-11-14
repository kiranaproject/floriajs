# Phase 2 validation baseline

**Recorded:** 2026-11-14  
**FloriaJS source revision:** `d4b226d255e169b24e09d7635cdd6bd06e88eac4` plus the Phase 1 diagnostic and Phase 2 host changes in the working tree  
**FPC:** 3.2.3  
**PasBuild:** 1.9.0  
**Pinned upstream Test262 revision:** `2e58f87d8350ad51224617a041c6e041d52f8444`

This records the host application's validation, not an official Test262 conformance run.

## Existing regression checks

The Phase 1 public `TFloriaJSResult`, diagnostics layout, evaluation signatures, and legacy messages remain unchanged.

```text
pasbuild test:                  231 tests, 0 errors, 0 failures
scratch/run_docclaims.sh:        88 claims, 0 failed
scratch/run_gapscan.sh:          194 probes, 186 OK / 8 diagnostic ERR
```

The eight gap-scan `ERR` rows remain the same diagnostic observations recorded in `baselines/phase0.md`.

## Host build

```sh
cd test262
pasbuild compile
```

Result: **PASS**. The application builds against the checked-out `src/main/pascal` sources, not an older installed `floriajs` package.

## Authored host fixtures

Command:

```sh
python3 tools/run_host_smoke.py
```

Result: **20 host fixture checks and 1 external timeout check passed**.

The checks cover:

- successful result projection;
- exact `print` and console arrays, Unicode, empty arguments, and escaped output;
- JavaScript error objects and primitive throws;
- parse and compiler error classification and available locations;
- ordered harness execution and global state in one context;
- stopping on harness failure before test execution;
- missing files and directory I/O errors;
- exactly-once evaluation;
- raw/non-strict and invalid argument handling;
- deliberately minimal `$262` capabilities;
- external termination of an infinite loop.

The Phase 0 upstream smoke paths are not rerun or labelled as Test262 outcomes in this baseline. Metadata parsing and scenario orchestration remain the next phase.
