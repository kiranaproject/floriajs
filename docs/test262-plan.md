# Test262 metadata and scenario planning

`tools/prepare_test262.py` is the Phase 3 planning layer. It reads Test262 frontmatter and emits structured scenario plans; it **does not execute JavaScript, spawn the Pascal host, or assign Test262 pass/fail verdicts**.

## Requirements

- Python 3.10 or newer.
- PyYAML 6, installed from `test262/requirements.txt` if needed.
- A Test262 checkout whose content matches `config/test262-revision.txt`.
- The Phase 2 host only when constructing its future command lines; planning does not launch it.

Use an isolated Python environment when installing the dependency:

```sh
cd test262
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

The current validation environment already provides PyYAML 6.0.3.

## Checkout validation

For an ordinary planning run, provide `--root` pointing to the top level of a Test262 checkout. By default it is `test262/.upstream/`. The planner expects the checkout's `test/` and `harness/` directories, plus its `package.json`.

Unless `--allow-unpinned` is explicitly supplied, the planner uses read-only Git inspection to require:

- `HEAD^{commit}` equals the full pinned hash;
- the supplied root equals the repository's top-level directory;
- there are no changes to `test/`, `harness/`, or `package.json`;
- the package version is `5.0.0`.

It sets `GIT_OPTIONAL_LOCKS=0` and does **not** clone, fetch, pull, checkout, reset, clean, or modify the repository. A mismatch fails clearly rather than silently using stale or moving test material.

`--allow-unpinned` is for authored fixture roots only. Its output records `revisionVerified: false` and must never be used for official conformance claims.

## Commands

Plan selected upstream paths:

```sh
cd test262
python3 tools/prepare_test262.py \
  --root /path/to/test262 \
  --list config/smoke-tests.txt
```

Or supply paths relative to the checkout's `test/` directory:

```sh
python3 tools/prepare_test262.py \
  --root /path/to/test262 \
  language/expressions/addition/S11.6.1_A2.1_T1.js
```

The optional `--host` argument changes the executable path stored in each plan's argument list. It does not cause that executable to run.

Run the authored metadata tests:

```sh
python3 tools/run_metadata_smoke.py
```

## Output records

Output is one JSON object per scenario on standard output. `preparationOnly` is always `true`. A plan includes:

- upstream root, expected/actual revision, package version, and verification state;
- relative test path, stable scenario ID, and execution variant;
- `planned`, `skipped`, `unsupported`, or `harness-error` as the planning outcome and its reason;
- original byte count and SHA-256 of the unmodified source;
- parsed flags, metadata includes, features, locale, negative expectation, frontmatter presence, and non-deterministic marker;
- ordered absolute harness paths;
- an argument **list** for the future host, never an interpolated shell command.

The planner returns exit status `2` for metadata, checkout, or argument errors. Valid `planned`, `skipped`, and `unsupported` decisions return status `0`; these are not execution verdicts.

## Scenario rules

### `raw`

One `raw`/`planned` record. Its source remains byte-for-byte untouched and its host command has no `--harness`, even when metadata lists includes. Those includes must not be resolved or loaded into the testing realm.

### `noStrict`

One `non-strict`/`planned` record. It evaluates the standard harness in the future; no source rewriting occurs.

### Default

One `non-strict`/`planned` record and one separate `strict`/`skipped` record. Strict coverage is never manufactured by prepending a cosmetic `"use strict"` directive.

### `onlyStrict`

One `strict`/`skipped` record. There is no non-strict fallback or host command.

### `module`

One `module`/`skipped` record. No strict/non-strict expansion or host command is generated.

### `async`

The eligible non-strict variant executes with `doneprintHandle.js` added after `sta.js` and before declared includes; the host command also receives `--async`. The strict variant remains separately skipped as strict. `raw` + `async` is `unsupported` because a raw scenario cannot inject the done-print harness.

### `_FIXTURE`

Excluded as a standalone test before metadata or scenario expansion. Its validated relative path remains in the planning inventory for future module resolution.

### ECMA-402

`intl402/` and `staging/intl402/` are skipped. Other `staging/` tests follow their normal flags.

### Capabilities

Unsupported feature tags, harness includes, `CanBlock` requirements, malformed/contradictory flags, unsafe paths, and missing sources cannot produce executable commands. Unsupported feature/include scenarios remain distinct from strict-mode and intentional mode skips.

Negative metadata is preserved as `{phase, type}` and is not compared with errors by the planner itself; `$DONOTEVALUATE` is never invoked during planning. One exception is planning-visible: a `negative.phase: resolution` expectation is emitted as `unsupported`, because module resolution and linking cannot be exercised at all. All other negative verdicts are decided by `tools/run_test262.py` from actual host completion (Phase 5).

## Harness order

The current pinned Test262 documentation requires this order inside one realm:

1. `harness/assert.js`
2. `harness/sta.js`
3. Metadata includes in their declared order
4. Test source

The host command preserves that exact sequence using repeated `--harness` arguments. `raw` disables all of these injections. Async metadata places `doneprintHandle.js` after `sta.js` and before metadata includes, and adds `--async` to the host command.

## Safety and reproducibility

- Files are read as bytes; a separate strict UTF-8 copy is used only for metadata inspection.
- `yaml.safe_load` is combined with recursive duplicate-key checks, including nested `negative` keys.
- Field types and allowed flags are validated before planning.
- Tests/includes must be regular `.js` files beneath their canonical root. Absolute paths, `..`, backslashes, drive-qualified paths, empty components, and symlink escapes are rejected.
- Duplicate includes, features, flags, or YAML keys fail explicitly instead of being deduplicated or silently overwritten.
- Paths containing spaces or metacharacters remain single argument-list entries.
- Repeating the same pinned planning operation produces the same semantic JSON records; no timing or execution verdict is included.

`tools/frontmatter.py` owns source/YAML extraction. `tools/scenario.py` owns policy, path, and argument planning. `tools/prepare_test262.py` only coordinates checkout/policy loading, input selection, JSON output, and exit status.
