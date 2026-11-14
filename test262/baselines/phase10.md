# Phase 10.1–10.10 TDZ, ASI, strict, coercion, descriptor, UTF-16, async, binary, module, and realm baseline

**Recorded:** 2026-11-14  
**FloriaJS source revision:** `d4b226d255e169b24e09d7635cdd6bd06e88eac4` plus all earlier phase work and the Phase 10.1 language changes in the working tree  
**Pinned Test262 revision:** `2e58f87d8350ad51224617a041c6e041d52f8444` (`package.json` version `5.0.0`)  
**Runner version:** `0.6.0`  
**FPC:** 3.2.3  
**PasBuild:** 1.9.0  
**Metadata environment:** PyYAML 6.0.3

This covers the TDZ/ASI, strict-mode, object-to-primitive coercion, property-descriptor, UTF-16 string, async suspension, binary/reflection, static-module, and realm milestones in Phase 10 (an umbrella of ten separate engine projects): TDZ/restricted-production ASI and strict-mode execution. It is not a full Test262 conformance claim.

## Language changes

### Temporal dead zone

- `TFloriaJSBinding` records whether it is initialized.
- New bytecode declarations `DECLARE_LET` / `DECLARE_CONST` create uninitialized bindings at scope entry.
- `TFloriaJSDeclarationScope` still rejects duplicate declarations during compilation.
- Program bodies, ordinary blocks, function bodies, `switch` bodies, and classic `for` initializers hoist their direct lexical declarations.
- Reading or assigning an uninitialized binding throws `ReferenceError` with `Cannot access 'name' before initialization`.
- `typeof` does not bypass the dead zone.
- `DEFINE_LET` / `DEFINE_CONST` initialize a predeclared binding (or create one in a fresh per-iteration environment); they no longer redefine a live lexical binding.
- `for…in`/`for…of` bindings and catch parameters are initialized when created; they do not expose a TDZ window.

### Restricted-production ASI

- `return`, `break`, and `continue` stop before a line break; `break`/`continue` labels must be on the same line.
- `throw` followed by a line break is a SyntaxError (`Illegal newline after throw`).
- Postfix `++`/`--` does not cross a line break.
- A line break, `}`, or end of input terminates a statement; two statements on the same source line still require a semicolon.
- `class` declarations remain semicolon-free; a following statement may start on the same line.

### Error constructor identity

The global `Error`, `TypeError`, `RangeError`, `ReferenceError`, and `SyntaxError` constructors now set `constructor` on their prototypes. `thrown.constructor === ReferenceError` and similar checks work, which lets Test262's `assert.throws` recognize thrown errors. This was a prerequisite for the TDZ tests.

## FPCUnit

Command:

```sh
pasbuild test
```

Result: **271 tests run, 0 errors, 0 failures** (22 new Phase 10 tests):

| Test | Check |
| --- | --- |
| `TestTemporalDeadZone` | Early read, self-referencing initializer, and `typeof` all throw `ReferenceError`. |
| `TestTemporalDeadZoneShadow` | An inner `let` is in TDZ even when an outer binding exists. |
| `TestTemporalDeadZoneInForInitializer` | `for (let i = i; ...)` throws before the loop body. |
| `TestReturnNewlineInsertsSemicolon` | `return` + newline returns `undefined`. |
| `TestThrowNewlineIsSyntaxError` | `throw` + newline is rejected. |
| `TestPostfixNewlineInsertsSemicolon` | `x` + newline + `--y` keeps `x` unchanged and prefixes `y`. |
| `TestSemicolonInsertionAtLineBreak` | Adjacent `var` declarations across lines work. |
| `TestMissingSemicolonOnOneLineIsRejected` | Same-line statements without a separator are rejected. |
| `TestAsyncEnvironmentSurvivesSuspension` | Block-scoped bindings remain reachable after one or more `await` suspensions. |

Documentation claims: **90 claims, 0 failed** (two new claims for TDZ and `return` ASI; the dynamic-import claim was updated to match the stricter parser).

## Focused Test262 report

Scope: every checked-out file under `test/language/statements/let` and `test/language/statements/const` (281 files) against the pinned revision:

```sh
find .upstream/test/language/statements/let \
     .upstream/test/language/statements/const \
     -name '*.js' | sed 's#^.upstream/test/##' | sort > /tmp/letconst.txt

python3 tools/run_test262.py \
  --root .upstream \
  --timeout 2 \
  --list /tmp/letconst.txt \
  --report results/letconst-report.json
```

After strict variants were enabled, the same 281 files produce **558 records — 344 pass, 182 fail, 32 unsupported**; attempted pass rate **344/526 = 65.40%**. The pass/fail rate is nearly identical in strict and non-strict modes, which is expected for TDZ/declaration tests.

| Directory | Pass | Fail | Unsupported | Attempted pass rate |
| --- | ---: | ---: | ---: | ---: |
| `language/statements/const` | 21 | 4 | 10 | 84.00% |
| `language/statements/const/dstr` | 102 | 78 | 6 | 56.67% |
| `language/statements/const/syntax` | 40 | 10 | 0 | 80.00% |
| `language/statements/let` | 26 | 5 | 10 | 83.87% |
| `language/statements/let/dstr` | 102 | 78 | 6 | 56.67% |
| `language/statements/let/syntax` | 53 | 7 | 0 | 88.33% |

The destination-structuring directories still account for most failures. That is expected: this milestone implements declarations, TDZ, and ASI, not the remaining destructuring semantics. No infrastructure failures occurred.

## Curated corpus

Seven passing upstream tests were added:

- `language/statements/let/block-local-use-before-initialization-in-prior-statement.js`
- `language/statements/let/block-local-use-before-initialization-in-declaration-statement.js`
- `language/statements/let/block-local-closure-get-before-initialization.js`
- `language/statements/let/block-local-closure-set-before-initialization.js`
- `language/statements/const/block-local-use-before-initialization-in-prior-statement.js`
- `language/statements/const/block-local-use-before-initialization-in-declaration-statement.js`
- `language/statements/return/12.9-1.js`

Result after text/JSON modules, exact async-generator ordering, complete Atomics range handling, the `with` statement, strict reserved words, Proxy invariants, import.meta/dynamic import/JSON attributes, BigInt atomics and waitAsync, strict escape sequences, cooperative agents, Proxy call/construct traps, SharedArrayBuffer/Atomics, live module bindings and star-export cycles, strict early errors, `Symbol.toPrimitive`, async generators, realms, cross-realm intrinsic selection, modules, binary APIs, async suspension, UTF-16, descriptors, coercion, live-global, and strict variants were enabled: **354 records — 338 pass, 16 fail, 0 skips**; attempted pass rate **338/354 = 95.48%**. The 16 failures are the known non-strict/strict gaps.

The smoke corpus is now **15 records, all pass** (8 non-strict, 7 strict).

Current baselines:

- `baselines/phase10-smoke.json`;
- `baselines/phase10-realms.json`;
- `baselines/phase10-async-generators.json`;
- `baselines/phase10-to-primitive.json`;
- `baselines/phase10-strict-early-errors.json`;
- `baselines/phase10-module-cycles.json`;
- `baselines/phase10-atomics.json`;
- `baselines/phase10-proxy.json`;
- `baselines/phase10-agents.json`;
- `baselines/phase10-strict-escapes.json`;
- `baselines/phase10-bigint-atomics.json`;
- `baselines/phase10-import-attributes.json`;
- `baselines/phase10-proxy-invariants.json`;
- `baselines/phase10-reserved-words.json`;
- `baselines/phase10-with.json`;
- `baselines/phase10-curated.json`.

## Adapter fixture suites

| Suite | Result |
| --- | --- |
| `run_host_smoke.py` | 34 checks plus one timeout check |
| `run_metadata_smoke.py` | 24 tests |
| `run_negative_smoke.py` | 10 test methods |
| `run_report_smoke.py` | 5 tests |
| `run_async_smoke.py` | 9 tests |
| `run_sync_smoke.py` | 8 tests |

## Strict mode (Phase 10.2)

- `"use strict"` directives are detected in program and function-body directive prologues. Class bodies are always strict.
- Each bytecode chunk carries an `IsStrict` flag; nested functions and arrows inherit the enclosing strictness.
- Strict assignment to an undeclared name throws `ReferenceError`; non-strict code still creates a global binding.
- Duplicate parameters and `eval`/`arguments` parameters are compiler early errors in strict functions.
- The Test262 host accepts `--strict`, validates it against `raw`, and prepends `"use strict";` only to the test source.
- The planner executes strict variants for default and `onlyStrict` tests. Strict skips are no longer produced for eligible tests.

### Strict-mode validation

- FPCUnit: **250 tests** (three new strict tests).
- Host fixtures: **34 checks plus the timeout check**.
- Smoke corpus: **15 records, all pass** (8 non-strict, 7 strict).
- Curated corpus: **75 records — 67 pass, 8 fail, 0 skipped**; attempted pass rate **67/75 = 89.33%**. The eight failures are the four known gaps in both non-strict and strict variants.
- Negative fixtures: **27 records — pass=9, fail=11, skipped=1, unsupported=4, harness-error=2**. The `onlyStrict` negative fixture now runs strictly and correctly fails at `$DONOTEVALUATE()`.
- Focused `let`/`const` diagnostics now execute strict variants; the report records the strict results alongside non-strict.

Remaining strict-mode gaps: octal-literal rejection, `delete` of unqualified identifiers, `eval`/`arguments` binding restrictions, and the non-strict global-`this` rule.

## Live global object and `this` (Phase 10.3)

- Global `var`/function bindings are properties of a live global object; the root environment delegates to it.
- Writes through `globalThis` update bindings, and writes to bindings update the object.
- Global lexical `let`/`const` bindings stay in the environment and are not object properties.
- Top-level `this` is the global object.
- Plain calls of non-strict functions receive the global object; strict functions keep `undefined`.
- `$262.global` exposes the live object.
- FPCUnit: **253 tests**, including live-global synchronization and `this` receiver tests.
- Curated corpus: **79 records — 71 pass, 8 fail** (89.87%). One upstream `this` test was added.

## Coercion (Phase 10.4)

- `JSToPrimitive` consults `Symbol.toPrimitive` first, then `valueOf`/`toString` (reversed for the string hint), and rejects objects that produce no primitive.
- `+`, loose equality, relational operators, and object `ToNumber` use the primitive result.
- Exotic `Date` conversion ordering remains future work.
- FPCUnit: **260 tests** total (coercion, live-global, descriptor, UTF-16, async, binary, and Reflect tests).
- Curated corpus: **354 records — 338 pass, 16 fail** (95.48%). Four with-statement tests, six reserved-word tests, five Proxy-invariant tests, five import-attribute tests, six BigInt Atomics tests, four strict-escape tests, five Proxy apply/construct tests, three agent tests, seven Proxy property tests, six SharedArrayBuffer/Atomics tests, three module-cycle tests, fourteen strict early-error tests, five `Symbol.toPrimitive` tests, twelve async-generator tests, twelve cross-realm tests, seven initial realm tests, fifteen module tests, ten binary/Reflect/weak tests, twenty legacy string tests, seven `for await` tests, three property-helper tests, and one coercion test were added.
- Documentation claims were updated: `[1] == 1` is now `true`, and a custom `toString` is consulted by `+`.

## Property descriptors (Phase 10.5)

- Own properties now carry `writable`, `enumerable`, and `configurable` flags.
- `Object.defineProperty` and `Object.getOwnPropertyDescriptor` implement data and accessor descriptors, including array indices and `length`.
- `preventExtensions`, `freeze`, `seal`, `isExtensible`, `isFrozen`, and `isSealed` update real flags.
- `propertyIsEnumerable` is implemented.
- `propertyHelper.js` is no longer an unsupported include; three upstream property-helper tests pass in both modes.
- FPCUnit: **255 tests** (two new descriptor tests).
- Curated corpus: **85 records — 77 pass, 8 fail** (90.59%).
- Limits: strict writes to non-writable properties do not throw `TypeError` yet; `Object.getOwnPropertySymbols` is missing.

## UTF-16 string semantics (Phase 10.6)

- JS-visible `length`, indexing, `charAt`/`charCodeAt`, slicing, substring/substr, search, includes/starts/ends, padding, and `for…of` use UTF-16 code-unit positions.
- `String.fromCharCode` produces one code unit; `fromCodePoint` produces a surrogate pair for astral points.
- The legacy `language/types/string` corpus is part of the curated run: 20 tests / 40 records pass.
- FPCUnit: **256 tests** (one new UTF-16 test).
- Curated corpus: **133 records — 117 pass, 16 fail** (87.97%).
- Limits: regexp matching and lexer byte positions remain UTF-8-based; lone-surrogate literals and all astral regexp cases are not covered.

## Async suspension and iteration (Phase 10.7)

- Async function bodies are resumable state machines driven by promise settlement.
- `await` suspends and resumes; thenables are adopted; rejections throw at the await point.
- Try handlers are snapshotted across suspension, so try/catch/finally around `await` works.
- `for await (... of ...)` supports `Symbol.asyncIterator` iterators and sync iterables.
- `Symbol.asyncIterator` is defined.
- FPCUnit: **258 tests** (two new async tests).
- Curated corpus: **147 records — 131 pass, 16 fail** (89.12%). Seven upstream `for await` tests were added.
- Limits: `async function*` is not implemented; the `async-iteration` feature tag still skips async generator tests while ordinary `for await` tests run.

## Binary, reflection, and weak collections (Phase 10.8)

- `ArrayBuffer`, nine typed-array constructors, and `DataView` with numeric indexing and byte-level accessors.
- `Reflect` exposes the core object operations, including `apply` and `construct`.
- `WeakMap`/`WeakSet` expose the Map/Set API but are not truly weak and accept primitive keys.
- FPCUnit: **260 tests** (two new binary/Reflect tests).
- Curated corpus: **167 records — 151 pass, 16 fail** (90.42%). Ten upstream binary/Reflect/weak tests were added.
- Limits: BigInt typed arrays, true weak semantics, TypedArray prototype methods, and species corners remain unsupported. `SharedArrayBuffer`, core `Atomics`, and the core `Proxy` property traps were added later in Phase 10.10.

## Modules (Phase 10.9)

- Relative `import`/`export` graphs are resolved recursively, including `_FIXTURE` files.
- The graph is lowered into one script with module-scoped function bodies and a `__require` registry.
- Supported: default/named/namespace/bare imports; default/named exports; export lists; re-exports; `export *`.
- Module plans run with strict host execution and record `moduleBundle` plus a relative `moduleGraph`.
- Resolution failures and cycles are harness errors before any host execution.
- Adapter fixtures: **2 tests**.
- Curated corpus: **182 records — 166 pass, 16 fail** (91.21%). Fifteen upstream module tests were added.
- Limits at that phase: snapshot bindings, no cycles, and no `import.meta`, dynamic import, or import attributes. Later Phase 10.10 work added these.

## Realms (Phase 10.10)

- `$262.createRealm()` creates a separate `TFloriaJSContext` with its own heap, global object, intrinsics, timer registry, and output list.
- The realm object exposes `global` and `evalScript`; `evalScript` evaluates re-entrantly in the realm that owns the receiver.
- Realm bindings and global properties do not leak into the caller realm, and caller bindings do not leak into the realm.
- `$262.agent` remains absent; there is no agent or concurrency support and no stub.
- Adapter fixtures: **35 host checks plus the timeout check**; three new FPCUnit realm tests.
- Focused realm corpus: **50 records — 50 pass** (100%).
- Curated corpus: **220 records — 204 pass, 16 fail** (92.73%). Twelve cross-realm tests were added.
- `GetPrototypeFromConstructor` now follows the newTarget realm for Array, ArrayBuffer, DataView, Promise, String, typed arrays, and array species.
- Limits: general object-to-string coercion is still incomplete outside `String.prototype.concat`. Agents remain unsupported; `SharedArrayBuffer` and core `Atomics` were added later in Phase 10.10.

## Async generators (Phase 10.10 follow-up)

- `async function*` parses and compiles as an async generator.
- `yield`, `await`, `for await`, and `yield*` work; `next()` returns a promise for `{value, done}`. Yielded promises are awaited and sent values are forwarded to the inner iterator.
- Async generator objects expose `Symbol.asyncIterator` and inherit from the realm's `AsyncGeneratorPrototype`.
- Explicit `return value` awaits the value before completing.
- Function `name`/`length` descriptors are non-writable and configurable.
- Focused corpus: **36 records — 36 pass** (100%).
- Curated corpus: **244 records — 228 pass, 16 fail** (93.44%). Twelve async-generator tests were added.
- Limits: none in the focused async-generator corpus.

## Symbol.toPrimitive (Phase 10.10 follow-up)

- `Symbol.toPrimitive` is consulted before `valueOf`/`toString` for `+`, loose equality, relational operators, and numeric conversion.
- The hint (`default`, `string`, `number`) is passed to the method; an object result throws `TypeError`.
- Property keys, `String()`, and `String.prototype.concat` use the full ToString path.
- Focused corpus: **10 records — 10 pass** (100%).
- Curated corpus: **254 records — 238 pass, 16 fail** (93.70%). Five `Symbol.toPrimitive` tests were added.
- Limits: some built-ins still use the simpler object-to-string conversion.

## Strict early errors (Phase 10.10 follow-up)

- Legacy octal literals are rejected in strict mode; sloppy mode keeps their octal value.
- Non-octal decimal literals such as `08` remain decimal in sloppy mode and are rejected in strict mode.
- `delete` of an unqualified identifier is a strict-mode `SyntaxError`.
- `eval`/`arguments` bindings are rejected in strict variable, function, class, catch, assignment, and update positions.
- Focused corpus: **14 records — 14 pass** (100%).
- Curated corpus: **268 records — 252 pass, 16 fail** (94.03%). Fourteen strict early-error tests were added.
- Limits: the `with` statement remains unsupported.

## Modules: live bindings and cycles (Phase 10.10 follow-up)

- Exports are defined as live getters, so mutations are visible through the namespace object.
- Named imports are rewritten to live property reads on the exporting module.
- Non-star module cycles are supported through the `__require` cache.
- Exported `let`/`const` keep their TDZ; the compiler now captures function-body lexical bindings correctly.
- Adapter fixtures: **3 module tests** (including live-binding and cycle fixtures).
- Focused cycle corpus: **7 records — 7 pass** (100%).
- Curated corpus: **271 records — 253 pass, 18 fail** (93.36%). Three module-cycle tests were added.
- Limits at that phase: `import.meta`, dynamic `import()`, and import attributes were unsupported. Later Phase 10.10 work added them.

## SharedArrayBuffer and Atomics (Phase 10.10 follow-up)

- `SharedArrayBuffer` supports `byteLength` and `slice`; slices preserve the shared flag.
- `Atomics` implements `load`, `store`, `add`, `sub`, `and`, `or`, `xor`, `exchange`, `compareExchange`, `isLockFree`, `wait`, and `notify`.
- Atomics operations work on integer typed arrays backed by shared or ordinary buffers.
- `Atomics.wait` is single-threaded: it returns `not-equal` on a value mismatch and `timed-out` otherwise.
- Focused corpus: **30 records — 30 pass** (100%).
- Curated corpus: **283 records — 261 pass, 22 fail** (92.23%). Six SharedArrayBuffer/Atomics tests were added.
- Limits: `$262.agent` and real concurrency remain unsupported; BigInt atomics and some range tests are incomplete.

## Proxy (Phase 10.10 follow-up)

- `new Proxy(target, handler)` and `Proxy.revocable` are implemented.
- Supported traps: `get`, `set`, `has`, `deleteProperty`, `ownKeys`, and `getOwnPropertyDescriptor`.
- Missing or non-callable traps follow the expected fallback/TypeError behavior.
- Revoked proxies throw `TypeError`.
- Focused corpus: **46 records — 44 pass, 2 fail** (attempted pass rate 44/46 = 95.65%).
- Curated corpus: **297 records — 275 pass, 22 fail** (92.59%). Seven Proxy tests were added.
- Limits: full proxy invariants remain incomplete.

## Cooperative agents (Phase 10.10 follow-up)

- `$262.agent` supports `start`, `report`, `getReport`, `broadcast`, `receiveBroadcast`, `sleep`, `monotonicNow`, `leave`/`leaving`, and `getSharedArrayBuffer`.
- Agents run cooperatively in separate contexts; the host switches at explicit agent calls and Atomics operations.
- `Atomics.load` yields to ready agents so busy-wait loops can make progress.
- Host fixtures: **36 checks plus the timeout check**.
- Focused agent corpus: **14 records — 14 pass** (100%).
- Curated corpus: **303 records — 281 pass, 22 fail** (92.74%). Three agent tests were added.
- Limits: agents are not preemptive; real thread concurrency is not implemented.

## Strict escape sequences (Phase 10.10 follow-up)

- Legacy octal escape sequences are rejected in strict mode.
- Sloppy mode decodes legacy octal escapes to their character values.
- Octal escapes in template literals are always rejected.
- `\0` remains valid in strict mode when not followed by a decimal digit.
- Fixed hex/unicode escape digit ordering in the lexer.
- Focused corpus: **18 records — 18 pass** (100%).
- Curated corpus: **317 records — 297 pass, 20 fail** (93.69%). Four strict-escape tests were added.
- Limits: the `with` statement remains unsupported.

## BigInt atomics and waitAsync (Phase 10.10 follow-up)

- `BigInt64Array` and `BigUint64Array` are implemented with 8-byte elements.
- `Atomics` operations work on BigInt typed arrays and return BigInt values.
- `Atomics.store` returns the converted BigInt value.
- `Atomics.compareExchange` and `wait` compare BigInt values with the correct signed/unsigned width.
- `Atomics.waitAsync` returns `{ async, value }` with `not-equal`, `timed-out`, or a promise.
- `Atomics.notify` resolves registered waiters and returns the number woken.
- A suspended async task keeps its activation environment alive across `await`, so block-scoped bindings remain reachable after resumption.
- Focused corpus: **18 records — 18 pass** (100%).
- Curated corpus: **329 records — 309 pass, 20 fail** (93.92%). Six BigInt Atomics tests were added.
- Limits: none in the focused BigInt Atomics corpus.

## import.meta, dynamic import, and attributes (Phase 10.10 follow-up)

- `import.meta.url` is available in bundled modules.
- Dynamic `import("./relative.js")` is lowered to a promise over the bundled module.
- JSON modules are supported through `with { type: "json" }` and export their parsed value as default.
- JSON modules are included in the module graph and cached like other modules.
- Adapter fixtures: **4 module tests** (including import.meta, JSON, and text modules).
- Focused corpus: **10 records — 10 pass** (100%).
- Curated corpus: **334 records — 314 pass, 20 fail** (94.01%). Five import-attribute tests were added.
- Limits: none in the focused import-attribute corpus.

## Proxy invariants (Phase 10.10 follow-up)

- `get` enforces non-configurable, non-writable data properties and accessor properties with no getter.
- `has` and `deleteProperty` enforce non-configurable target properties.
- `ownKeys` includes all non-configurable target keys and all keys of non-extensible targets.
- `getOwnPropertyDescriptor` enforces non-configurable descriptor compatibility.
- `setPrototypeOf` enforces the non-extensible target invariant.
- `Object.getOwnPropertyNames` and `Object.getOwnPropertyDescriptor` use the proxy traps.
- Focused corpus: **21 records — 21 pass** (100%).
- Curated corpus: **344 records — 324 pass, 20 fail** (94.19%). Five Proxy-invariant tests were added.
- Limits: the `with`-statement invariant test remains unsupported.

## Strict reserved words (Phase 10.10 follow-up)

- Strict mode rejects `implements`, `interface`, `package`, `private`, `protected`, `public`, `static`, `yield`, and `let` as identifiers.
- Sloppy mode still accepts them as identifiers.
- Unicode escapes in identifiers are decoded before keyword classification.
- `static` is accepted as a variable name in sloppy mode.
- Focused corpus: **85 records — 85 pass** (100%).
- Curated corpus: **350 records — 330 pass, 20 fail** (94.29%). Six reserved-word tests were added.
- Limits: the `with` statement remains unsupported.

## with statement (Phase 10.10 follow-up)

- `with (object) statement` is supported in sloppy mode.
- Strict mode rejects `with` as a `SyntaxError`.
- Primitive objects are boxed so `with (1)` and `with ("text")` work.
- The `with` environment delegates name lookup to the object.
- Focused corpus: **14 records — 14 pass** (100%).
- Curated corpus: **354 records — 338 pass, 16 fail** (95.48%). Four with-statement tests were added.
- Limits: none specific to `with`; remaining failures are the known Atomics/async-generator cases.

## Known limits from this slice

- `for…in`/`for…of` bindings and catch parameters do not expose TDZ windows.
- Destructuring declaration semantics remain incomplete; the focused report records those failures rather than hiding them.
- General ASI is implemented for restricted productions and statement ends; it does not claim every ECMAScript ASI corner case.
- Strict mode does not yet reject octal literals, `delete` of identifiers, or `eval`/`arguments` bindings.
- Global lexical `let`/`const` bindings are intentionally not properties of `globalThis`.
- The error-constructor fix does not implement full property-descriptor semantics.
- `Symbol.toPrimitive` is consulted first; `Date` still uses the ordinary coercion order.

## Runtime compatibility

No existing public API was removed. New bytecode opcodes and the environment initialization state are additive. Existing `Evaluate*`, timer, host, and reporting signatures are unchanged.
