# Phase 5 negative-verdict baseline

**Recorded:** 2026-11-14  
**FloriaJS source revision:** `d4b226d255e169b24e09d7635cdd6bd06e88eac4` plus diagnostics, host, planner, synchronous runner, and negative-verdict changes in the working tree  
**Pinned Test262 revision:** `2e58f87d8350ad51224617a041c6e041d52f8444` (`package.json` version `5.0.0`)  
**FPC:** 3.2.3  
**PasBuild:** 1.9.0  
**Metadata environment:** PyYAML 6.0.3

These are focused fixture and smoke results, not a full-suite Test262 conformance claim.

## Negative-verdict policy

`tools/run_test262.py` now compares a negative test's actual completion with its metadata:

- the error must originate in the test source, not a harness include;
- `negative.phase: parse` accepts the host's `parse` or `compile` phase;
- `negative.phase: runtime` requires a runtime JavaScript throw;
- `negative.phase: resolution` is `unsupported` because module linking is not implemented;
- `negative.type` must exactly equal the actual error constructor name;
- normal completion, a wrong phase, or a wrong type is `fail`;
- reaching the `$DONOTEVALUATE()` sentinel is `fail` with an explicit reason;
- a parse failure whose message matches a reviewed unsupported-parser-feature fragment is `unsupported`, not a false `pass`.

The fragments and accepted phases live in the `negativeVerdicts` section of `config/feature-policy.json`. The policy status is `phase-5-negative-verdicts`.

## Authored negative fixtures

Command:

```sh
cd test262
python3 tools/run_negative_smoke.py
```

Result: **9 test methods passed** over **15 fixtures**, producing **27 scenario records**:

```text
Summary: fail=5, harness-error=1, pass=4, skipped=15, unsupported=2
```

Outcome by fixture:

| Fixture | Outcome | Meaning |
| --- | --- | --- |
| `parse-syntax.js` | `pass` | Required parse `SyntaxError`; `$DONOTEVALUATE()` is never reached. |
| `compile-early.js` | `pass` | Required early `SyntaxError` reported in the compile phase. |
| `runtime-type.js` | `pass` | Required runtime `TypeError`. |
| `raw-runtime.js` | `pass` | Required runtime `TypeError` in a raw scenario without harness injection. |
| `wrong-phase.js` | `fail` | Parse expectation met by a runtime throw. |
| `wrong-type.js` | `fail` | Runtime `RangeError` where `TypeError` was required. |
| `normal-completion.js` | `fail` | Negative test completed normally. |
| `parse-type.js` | `fail` | Runtime `TypeError` does not satisfy a parse-phase `TypeError`. |
| `dont-evaluate.js` | `fail` | `$DONOTEVALUATE()` was reached instead of failing at parse time. |
| `module.js` | `skipped` | Modules are not implemented. |
| `async.js` | `skipped` | Async host contract is not implemented; strict variant separately skipped. |
| `only-strict.js` | `skipped` | Strict semantics are not implemented. |
| `unsupported-feature.js` | `unsupported` | Declared `Proxy` capability is absent; no host process runs. |
| `unsupported-parse-feature.js` | `unsupported` | Parser rejected a class field with an unimplemented-feature message; not treated as the expected early error. |
| `include-error.js` | `harness-error` | The include failed before the test; never a negative pass. |

Every default test also records its separate strict-scenario skip. The suite verifies repeatability after removing `durationMs` fields.

## Synchronous integration fixtures

Command:

```sh
cd test262
python3 tools/run_sync_smoke.py --root /tmp/opencode/floria-phase4-upstream
```

Result: **8 integration tests passed**. The reviewed upstream corpus remains at **8 `pass` and 7 strict `skipped`**, and the local negative fixture (`local/negative.js`) is now verified as a runtime `TypeError` pass instead of a Phase 4 `unsupported` deferral.

The metadata planner suite now has **22 passing tests** (21 from Phase 3 plus one negative-resolution fixture), and the host suite remains at **20 fixture checks plus one external-timeout check**.

## Existing suite and documentation claims

- FPCUnit: **231 tests run, 0 errors, 0 failures**.
- Documentation claims: **88 claims, 0 failed**.

No `Evaluate()` signature, existing public result record, or host protocol changed in Phase 5. The new policy fields are additive JSON configuration consumed only by the runner.

## Known limits

- A parser limitation that does not mention a reviewed unsupported-feature fragment can still produce a false parse-phase pass. The safeguard is conservative, not a proof of early-error correctness.
- Negative tests requiring strict or module scenarios remain skipped.
- Negative resolution expectations remain `unsupported` until module linking exists.
- The full Test262 negative corpus has not been executed; this baseline covers only authored fixtures and the reviewed synchronous smoke material.
