# Phase 3 validation baseline

**Recorded:** 2026-11-14  
**FloriaJS source revision:** `d4b226d255e169b24e09d7635cdd6bd06e88eac4` plus diagnostics, host, and metadata-planner changes in the working tree  
**FPC:** 3.2.3  
**PasBuild:** 1.9.0  
**Python metadata validation environment:** PyYAML 6.0.3  
**Pinned Test262 revision:** `2e58f87d8350ad51224617a041c6e041d52f8444` (upstream package version `5.0.0`)

This baseline records planner validation, not execution or a Test262 conformance result.

## Authored metadata fixtures

Command:

```sh
cd test262
python3 tools/run_metadata_smoke.py
```

Result: **21 tests passed**.

Coverage includes:

- raw/noStrict/default execution planning;
- separate strict skips for default scenarios;
- strict-only, module, async, and `_FIXTURE` exclusion;
- ECMA-402 directories versus other staging tests;
- unsupported feature tags, harness includes, and `CanBlock` requirements;
- official harness/include order;
- negative metadata preservation without verdict evaluation;
- duplicate YAML keys, invalid fields, unsafe YAML tags, invalid UTF-8, and contradictory flags;
- missing includes and path traversal rejection;
- raw source byte preservation and exact SHA-256 values;
- locale and non-deterministic metadata;
- paths containing spaces;
- read-only Git revision verification and mismatch rejection;
- deterministic repeated planning and source immutability.

No Pascal host or real Test262 harness is spawned by these fixture checks.

## Reviewed upstream smoke planning

Eight files in `config/smoke-tests.txt` were fetched from the pinned upstream revision into a temporary review root, then passed to:

```sh
python3 tools/prepare_test262.py \
  --root /tmp/opencode/floria-phase3-upstream \
  --allow-unpinned \
  --list config/smoke-tests.txt
```

Result: **15 planning records, all correct**:

- **8 `planned` non-strict scenarios** (one per reviewed file);
- **7 `skipped` strict scenarios**;
- no `unsupported` or `harness-error` outcomes;
- no negative expectations or unsupported feature/include requirements;
- no JavaScript execution or pass/fail assignment.

`S13.2.1_A6_T1.js` is `noStrict`, so it has one record; the other seven files have a non-strict record and an explicit strict skip. The temporary upstream review tree is not vendored into the repository.

## Policy correction

The pinned `INTERPRETING.md` specifies `harness/assert.js` followed by `harness/sta.js`. Policy and documentation were corrected during this phase so new plans use that exact official order, followed by metadata includes in declaration order.

## Compatibility

No Phase 1 diagnostics or Phase 2 host execution API was changed. Runtime regression checks remain at 231 passing FPCUnit tests and 88 passing documentation claims. The new phase adds only metadata/planning tools, authored fixtures, configuration status, and documentation.
