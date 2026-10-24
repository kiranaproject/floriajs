# floriajs — Engineering Roadmap

This is an execution plan for agents and maintainers. It is deliberately more
specific than a feature wishlist: each task lists the current failure, the
files involved, the intended approach, and the tests that make it “done”.

The roadmap is ordered by risk to the embedded runtime. **Correctness and
lifetime safety come first**, then ECMAScript parity, then missing features,
then performance.

## Current snapshot

At the time this roadmap was written:

- Runtime: bytecode VM only. The AST tree-walker is removed.
- Pipeline: lexer → parser → AST → compiler → `TFloriaJSBytecode` → `TFloriaJSVM`.
- Test suite: **168 tests pass** with `pasbuild test`.
- Gap scan: **108 probes OK / 12 ERR** with `bash scratch/run_gapscan.sh`.
  Some errors are expected (`throw`, unsupported `yield`); the probe harness is
  not an ECMAScript conformance suite.
- Unit count: 25 units.

Do not treat “tests pass” as “ECMAScript-compliant”. Several defects below are
currently untested because the existing tests assert only the happy path.

### Already landed (do not reimplement)

- Bytecode compiler, bytecode chunks, stack VM, frame/try handling, closures,
  async functions, and VM execution of FTML bindings/signals.
- Basic const rejection, duplicate `let`/`const` rejection in ordinary block
  lists, undeclared-read `ReferenceError` (with `typeof` exemption), and
  basic function declaration hoisting.
- `Array.prototype.toString`; array indices in `for…in`,
  `Object.keys/values/entries`; `hasOwnProperty`/`in` for present elements.
- Basic `Function.prototype.call`/`apply`/`bind`, lexical `arguments` in
  arrows, and `Foo.prototype.constructor === Foo`.
- `Number("0x10")`, `parseInt("010")`, and removal of the large-integer
  formatting overflow.
- Priority 3 library surface: Map, Set, Date, Symbol, RegExp, URI helpers,
  timers, and strict runtime type errors.

The tasks below are the **remaining gaps and edge cases**, not a request to
start over.

## How to work a task

1. Pick the first unchecked task that is not blocked.
2. Read the reproduction and the cited files before editing.
3. Add a failing test for the exact behaviour first.
4. Implement the smallest safe change.
5. Run the full suite, the gap scan, and `./build.sh examples`.
6. Check the lifetime rules below if the change creates or owns objects,
   environments, functions, or bytecode chunks.
7. Update the relevant docs and tick the task only then.

Use conventional commits (`fix(vm): …`, `feat(js): …`, `docs: …`). Keep one
logical change per commit. Do not push.

### Definition of done

A task is complete only when all of these hold:

- [ ] A unit test fails before the fix and passes after it.
- [ ] At least one JavaScript-level probe is added when the behaviour is
      observable from a script.
- [ ] `pasbuild compile` succeeds.
- [ ] `pasbuild test` reports 0 errors and 0 failures.
- [ ] `./build.sh examples` succeeds.
- [ ] No new heap/environment growth in lifetime tests for object-creating
      changes.
- [ ] The relevant docs are updated:
      `docs/language-support.md`, the API page, and this roadmap.
- [ ] The working tree is clean after committing.

### Lifetime rules

- Bytecode chunks are reference-counted. An owner that keeps a chunk calls
  `Retain` and releases it when done.
- `TFloriaJSFunction` owns its prototype object. The prototype’s owner backlink
  must never keep the function alive or point at a freed function.
- `TFloriaJSHeap.Clear` must invalidate **every** cached prototype pointer.
- Do not free AST nodes that are shared with functions; use `Retain`/`Release`.
- Prefer `JSMake*` factories over hand-built values.

### Unsupported-feature policy

When syntax is unsupported, **fail loudly** at lex/parse time. Do not let it
parse as unrelated identifiers or adjacent expressions. The current offenders
are listed in P0/P2 tasks (`void`, tagged templates, `class`, etc.).

---

## Priority 0 — Correctness and safety

These are blockers. They either produce wrong results silently or can lead to
invalid memory access.

### [x] P0-01 — Fix `Reset` invalidation and environment lifetime

**Failure.** After `TFloriaJSContext.Reset`:

```text
before Reset: (1.5).toString() -> 1.5
after Reset:  (1.5).toString() -> [object Object]
```

`try { const c = 1; c = 2; } catch (e) { ... }` after `Reset` also fails at
host level instead of being catchable by JavaScript.

**Cause.**

- `TFloriaJSHeap.Clear` resets all cached prototype pointers except
  `FNumberPrototype`.
- `TFloriaJSContext.Reset` creates the replacement global environment with
  `TFloriaJSEnvironment.Create(nil)` and does not pass `FHeap`.

**Files.**

- `src/main/pascal/floria.js.value.pas` — `TFloriaJSHeap.Clear`.
- `src/main/pascal/floria.js.core.pas` — `TFloriaJSContext.Reset`.

**Implementation.**

1. Reset `FNumberPrototype := nil` alongside the other prototype caches in
   `Clear`.
2. Create the new global environment with `TFloriaJSEnvironment.Create(nil, FHeap)`.
3. Re-point `VM.GlobalEnv` to the new environment through `InitContext`.
4. Add a regression test that calls `Reset` before number methods and
   catchable const assignment.

**Acceptance.**

```javascript
// after Reset
(1.5).toString() === "1.5";

try { const c = 1; c = 2; }
catch (e) { e.name === "TypeError"; }
```

**Tests.** Add to `TFloriaJSEngineTest` or a new reset/lifecycle test class.
Also check that repeated `Reset` does not crash and that heap counts return to
a stable baseline.

---

### [x] P0-02 — Compile compound assignments to member expressions

**Failure.**

```javascript
var o = { x: 1 };
o.x += 2;          // floriajs: 2   expected: 3
o["x"] *= 3;       // floriajs: 3   expected: 9 (after the previous step)
o.x **= 3;         // currently writes the RHS only
var a = [1];
a[0] += 2;         // floriajs: 2   expected: 3
```

`CompileAssignExpr` handles compound assignment only when the target is an
identifier. Named/computed member targets always compile as a plain property
store.

**Files.** `src/main/pascal/floria.js.compiler.pas` (`CompileAssignExpr`).

**Implementation.**

- For a named member: evaluate target once, duplicate it, load the old property,
  compile the RHS, emit the operator opcode, then store and leave the result.
- For a computed member: evaluate target and key once, preserve both for the
  final store, load old value, apply the operator, store, leave result.
- Cover `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `**=`, `??=`.
- Preserve the JavaScript result value of the assignment expression.
- Do not evaluate the target/key twice: getters and side effects must run once.

**Acceptance.** All compound operators work for named and computed members,
and an assignment expression returns the assigned value.

**Tests.** Extend `TFloriaJSPriority1Test` with named, computed, array, and
getter/setter cases.

**Pitfall.** `o.x++` currently works; do not regress prefix/postfix updates
while refactoring the assignment path.

---

### [x] P0-03 — Compile destructuring assignment (or reject it explicitly)

**Failure.**

```javascript
var a, b;
[a, b] = [1, 2];       // a and b are both undefined
var o = {};
({ a } = { a: 3 });    // a is undefined
```

Declaration destructuring works; **assignment** destructuring is silently
ignored by `CompileAssignExpr`. Rendering it as a no-op is worse than a parse
error because scripts appear to run.

**Files.**

- `src/main/pascal/floria.js.compiler.pas` (`CompileAssignExpr`,
  `CompileDestructuring`).
- `src/main/pascal/floria.js.vm.pas` if a new stack pattern is needed.
- `src/main/pascal/floria.js.env.pas` for const assignment errors.

**Implementation.** Compile assignment patterns separately from declaration
patterns:

1. Evaluate the RHS once and keep it for the expression result.
2. For identifier targets, emit `STORE_ENV` (which must throw on a const
   binding).
3. For member targets, evaluate the reference and store through `SET_PROP`.
4. Support object/array patterns, defaults, rest, nested patterns, computed
   keys, and skipped array elements.
5. Return the RHS value, not the last assignment.

If a complete implementation cannot be done in one slice, reject destructuring
assignment at parse time with a clear “not supported” syntax error; do not
leave a silent no-op.

**Tests.** Array/object, nested, defaults, rest, member targets, computed keys,
array holes, and const-target rejection. Add a test that the expression result
is the RHS.

---

### [x] P0-04 — Implement `var` hoisting and fix function/`var` collisions

**Failure.**

```javascript
function f() { return a; var a = 1; }     // ReferenceError; expected undefined
function f() { a = 5; var a; return a; }  // undefined; expected 5
function a() { return 1; }
var a;
a();                                      // TypeError; expected 1
```

Function declarations are hoisted, but `var` declarations are not. A bare
`var a;` also overwrites a hoisted function with `undefined`.

**Files.**

- `src/main/pascal/floria.js.compiler.pas` (`CompileProgram`,
  `CompileFunctionBody`, `CompileBlockStmt`, `CompileVarStmt`).
- `src/main/pascal/floria.js.bytecode.pas` if a declaration-only opcode is
  warranted.

**Implementation.**

- Add a declaration pre-pass for each program and function body that collects
  all `var` names reachable through blocks, `if`, loops, `switch`, and `try`,
  but **not** through nested functions.
- Emit `undefined` bindings for those names at function/program entry.
- A declaration with no initializer must not reassign an existing binding.
  A declaration with an initializer assigns at its statement position.
- Hoist function declarations before entry declarations, and make a function
  declaration win over a bare `var` of the same name.
- Keep `let`/`const` block-scoped; do not hoist them.
- Apply the same logic inside function bodies; top-level `var` still goes to
  the global environment.

**Acceptance.**

```javascript
function f() { return a; var a = 1; }       // undefined
function f() { a = 5; var a; return a; }    // 5
function a() { return 1; } var a; a();      // 1
```

**Tests.** Both declaration orders, `typeof` before declaration, assignment
before declaration, nested blocks, loops, and nested functions (must not
hoist to the outer function).

---

### [x] P0-05 — Implement chain-wide optional chaining short-circuit

**Failure.**

```javascript
var a = null;
a?.b.c;          // TypeError; expected undefined
a?.b();          // TypeError; expected undefined
a?.b(sideEffect()); // TypeError; expected no argument evaluation
```

Only the immediate access/call is optional. Optional chaining must short-circuit
the **rest of the chain**, including calls, computed keys, and arguments.

**Files.**

- `src/main/pascal/floria.js.compiler.pas` (`CompileMemberExpr`,
  `CompileCallExpr`, optional-call paths).
- `src/main/pascal/floria.js.vm.pas` only if a sentinel/chain flag is preferred
  over compiler jumps.
- `src/main/pascal/floria.js.parser.pas` to reject optional-chain assignment
  (`a?.b = 1`) as a syntax error.

**Implementation options.**

- Preferred: compile the chain as guarded jumps. Evaluate the chain base once;
  if nullish, jump to an end label that pushes `undefined`; otherwise evaluate
  each link. Optional calls jump over the callee invocation and arguments.
- Alternative: maintain an “optional short-circuit” sentinel on the VM stack
  and teach access/call opcodes to propagate it. This is more invasive and
  must preserve normal `undefined` values.

**Tests.**

- `a?.b`, `a?.[k]`, `a?.()`, `a?.b()`, `a?.b.c`, `a?.b?.c`, nested chains.
- Nullish base skips computed-key evaluation.
- Nullish base skips call arguments (side-effect counter).
- Non-null base behaves normally.
- Optional-chain assignment is rejected by the parser.

---

### [ ] P0-06 — Make constructor back-references lifetime-safe

**Risk.** `TFloriaJSPrototypeObject` stores the owner function in a raw pointer.
`TFloriaJSFunction.Destroy` only clears the owner of the function’s **current**
`prototype` property. If the prototype is replaced or deleted first, an old
prototype held by user code can keep a dangling owner pointer:

```javascript
function F() {}
var p = F.prototype;
F.prototype = {};
F = null;
// p.constructor may now dereference a freed function
```

This did not crash in a small probe because the allocator did not reuse the
freed memory, but it is a real use-after-free risk.

**Files.** `src/main/pascal/floria.js.value.pas`
(`TFloriaJSFunction.Destroy`, `TFloriaJSPrototypeObject`,
`SetProperty`/`DeleteProperty` handling for `prototype`).

**Implementation.**

- Track every prototype object created for a function, or invalidate the old
  prototype’s owner whenever the `prototype` property is replaced or deleted.
- Clear the owner before the function is freed and when the prototype is
  detached.
- Never add a strong `function → prototype → constructor → function` cycle.
- A detached prototype may keep working as an ordinary object, but
  `p.constructor` must not return a stale pointer.

**Tests.** Replace/delete `prototype`, force `Collect`, read the old
prototype’s `constructor`, and extend the function-prototype leak test.

---

### [ ] P0-07 — Complete declaration validation and switch-case hoisting

**Failures.**

```javascript
function f(a) { let a = 1; return a; }       // should be SyntaxError
for (let i = 0, i = 1; i < 2; i++) {}        // should be SyntaxError
try { throw 1; } catch (e) { let e = 2; }    // should be SyntaxError
switch (1) { case 1: f(); function f(){} }   // f should be hoisted
```

`ValidateStatementsDeclarations` only scans statement lists in program/block
bodies. It does not visit function parameters, catch parameters, `for`
initializers, or switch case bodies.

**Files.**

- `src/main/pascal/floria.js.compiler.pas` (`ValidateStatementsDeclarations`,
  `CompileFunctionBody`, `CompileForStmt`, `CompileSwitchStmt`).
- `src/main/pascal/floria.js.parser.pas` if the parser should report earlier.

**Implementation.**

- Extend validation to:
  - function parameter lists (duplicate parameter/lexical collisions),
  - catch parameter against lexical declarations in the catch block,
  - `for` initializer declarations,
  - the whole switch body as one lexical scope (case clauses share it), while
    still hoisting function declarations from each clause.
- Hoist function declarations in switch bodies using the same helper as blocks.
- Keep `var` and function duplicate rules distinct from `let`/`const`.

**Tests.** Add the four repros above, plus duplicate `let` across case clauses,
valid shadowing cases that must continue to work, and a switch-case function
called before its textual declaration.

---

## Priority 1 — ECMAScript parity and remaining core semantics

These are not memory-safety blockers, but they still cause wrong results in
ordinary scripts.

### [ ] P1-01 — Classic `for` `let`/`const` scoping and per-iteration closures

**Failure.**

```javascript
var f = [];
for (let i = 0; i < 3; i++) f.push(() => i);
f[0]() + f[1]() + f[2]();   // 9 (3,3,3); expected 3 (0,1,2)
typeof i;                    // "number"; expected "undefined"
```

`CompileForStmt` does not create a loop scope for `let`/`const` and does not
copy the per-iteration environment. `for…of`/`for…in` already do per-iteration
environments.

**Files.** `src/main/pascal/floria.js.compiler.pas` (`CompileForStmt`),
`src/main/pascal/floria.js.vm.pas` (environment opcodes as needed).

**Implementation.**

- Push a loop environment for `let`/`const` initializers.
- Pop it on all exits, including `break`, `continue`, `return`, `throw`, and
  `finally`.
- Give each iteration its own binding for closure capture.
- Keep `var` loop variables in the enclosing function/program scope.

**Tests.** No leak after loop, closures see 0/1/2, nested labeled
break/continue, `return` from inside the loop body, and exception paths.

### [ ] P1-02 — Array holes, explicit `undefined`, and `length` mutation

**Failure.**

```javascript
var a = [undefined];
Object.keys(a);       // []      expected ["0"]
a.hasOwnProperty(0);  // false   expected true
0 in a;               // false   expected true

var b = [1, 2];
b.length = 5;
b.length;             // 2       expected 5
```

Explicit `undefined` elements and holes are indistinguishable because the array
stores only a dense value array. Numeric keys are not real object properties.

**Files.** `src/main/pascal/floria.js.value.pas` (`TFloriaJSArray`),
`src/main/pascal/floria.js.objects.pas` (keys/values/entries),
`src/main/pascal/floria.js.vm.pas` (`FOR_IN_INIT`, `IN`, property ops),
`src/main/pascal/floria.js.arrays.pas` (length behaviour).

**Implementation.**

- Add element-presence tracking (hole bitmap or equivalent) or store a hole
  sentinel distinct from `undefined`.
- Make `hasOwnProperty`, `in`, `Object.keys/values/entries`, and `for…in`
  distinguish holes from explicit `undefined`.
- Make `length = n` extend with holes and truncate correctly.
- Preserve JavaScript hole semantics in array methods: `map`/`forEach` skip
  holes, `join` renders holes as empty strings, array spread yields
  `undefined`, and `JSON.stringify` emits `null` for holes.
- Ensure array enumerations do not expose `length` as an index.

**Tests.** Explicit undefined, holes, mixed arrays, length grow/shrink,
enumeration, string/JSON conversion, and array methods over holes.

### [ ] P1-03 — Correct `new` on bound functions

**Failure.**

```javascript
function C(x) { this.x = x; }
var B = C.bind(null, 7);
(new B()).x;   // TypeError: Cannot set properties of null
```

**Files.** `src/main/pascal/floria.js.value.pas`
(`TFloriaJSBoundFunction`, `JSFunctionBind`), `src/main/pascal/floria.js.vm.pas`
(`ConstructObject`).

**Implementation.**

- Bound functions are constructable iff their target is constructable.
- `new Bound(...)` ignores the bound `this`, constructs the target with the
  combined bound + call arguments, and installs the target’s prototype.
- `instanceof` must traverse the target’s prototype chain.
- Bound functions must not expose an own `prototype` per ECMAScript.

**Tests.** Bound partial args, `new`, `instanceof`, arrow targets rejected,
non-constructor targets rejected, and `.call`/`.apply` on bound functions.

### [ ] P1-04 — Number formatting and conversion parity

**Failure.**

```javascript
String(1e20);              // "1E20"        expected "100000000000000000000"
String(1e-7);              // "1E-7"        expected "1e-7"
(0.1 + 0.2).toString();    // "0.3"         expected "0.30000000000000004"
```

`ToNumber` hex/binary/octal parsing is fixed, and the integer overflow path is
gone, but `ToString` uses host formatting (`FloatToStr`) and truncates
precision. The existing `1e20` test only checks the first character; that is
not enough.

**Files.** `src/main/pascal/floria.js.value.pas` (`ToString`,
`TFloriaJSValue.ToNumber`), `src/main/pascal/floria.js.stdlib.pas`
(`JSNumberToString`), `src/main/pascal/floria.js.value.pas` tests.

**Implementation.**

- Implement a shortest-round-trip decimal formatter (or a carefully tested
  approximation) for doubles.
- Match JavaScript exponent thresholds and `e+`/`e-` notation.
- Preserve integer display below the safe-integer range.
- Update `Number("...")` edge cases at the same time.

**Tests.** `0.1 + 0.2`, `1e20`, `1e21`, `1e-7`, `-0`, `NaN`, `Infinity`,
safe integers, and round trips through `Number(String(x))`.

### [ ] P1-05 — Fix `delete` and `debugger` semantics

**Failures.**

```javascript
delete undeclaredName;   // ReferenceError; ECMAScript non-strict: true
var x = 1; delete x;     // true, x remains; ECMAScript non-strict: false
debugger;                // ReferenceError; roadmap previously said no-op
```

**Files.** `src/main/pascal/floria.js.compiler.pas` (`tkDelete`),
`src/main/pascal/floria.js.lexer.pas`/`parser.pas` for `debugger`,
`src/main/pascal/floria.js.vm.pas` for delete opcode.

**Implementation.**

- `delete identifier` must not perform an undeclared read.
- Declared variables are non-deletable: return `false` and leave the binding.
- Unknown identifiers return `true` without creating a binding.
- Either recognize `debugger` as a no-op keyword or reject it at parse time;
  do not let undeclared-read strictness turn it into `ReferenceError`.
- Update the deferred-semantics section accordingly.

---

### [ ] P1-06 — Re-sync documentation with current runtime behaviour

Several docs still describe the pre-P1 runtime:

- `docs/language-support.md` says `const` reassignment is allowed, function
  declarations are not hoisted, `Function.prototype.call/apply/bind` are
  missing, and `debugger` is a no-op.
- `docs/README.md` still lists `Function.prototype` methods as unimplemented.
- `docs/api/values.md` needs the new `TFloriaJSPrototypeObject`,
  `TFloriaJSBoundFunction`, and number-prototype behaviour documented.
- `docs/getting-started.md` still mentions the old “prototype deliberately has
  no constructor back-reference” design.

Update these pages as the P0 fixes land. The language-support deviation table
must distinguish:

- currently incorrect behaviour that is scheduled (P0),
- deliberate embedded trade-offs,
- genuinely missing features (P2/P3).

Acceptance: no statement in `docs/` contradicts a passing test or a completed
roadmap item.

---

## Priority 2 — Missing language and library features

Implement these only after P0 is clean. Each needs syntax/feature tests and a
gap-scan probe.

### [ ] P2-01 — `void` operator

Add `tkVoid`, parse `void <expr>`, and emit the existing `OP_VOID` (or an
equivalent) so the operand is evaluated and discarded. Add `void 0` and
side-effect tests; currently `void` is an undeclared identifier.

### [ ] P2-02 — Logical assignment operators

Add `&&=` and `||=`, including short-circuiting (the RHS must not be evaluated
when the condition is not met) for identifiers and member targets. Add parse,
evaluation, and side-effect tests.

### [ ] P2-03 — Promise constructor

Implement `new Promise(executor)` with native `resolve`/`reject` callbacks,
settled-state transitions, and microtask integration. Keep `Promise.resolve`,
`reject`, `all`, and `race` working. Add unhandled-rejection and await tests.

### [ ] P2-04 — JSON parity

- Call `toJSON()` when present.
- Honour the `replacer` function and key array.
- Implement the `reviver` argument to `JSON.parse`.
- Invoke getters and `toJSON` according to ECMAScript property-access
  semantics, while keeping circular detection and indentation behaviour.
- Add hole/`undefined`/function serialization tests.

### [ ] P2-05 — Map/Set iteration and iterators

- Implement the iterator protocol (`next`, `done`, `value`).
- Make `for…of` iterate `Map` and `Set` directly.
- Make `keys`/`values`/`entries` return iterators, not arrays.
- Preserve the current array-returning helpers only if needed for compatibility;
  otherwise migrate tests and docs.
- Add destructuring `[key, value]` in `for…of`.

### [ ] P2-06 — Classes

Parse `class`, constructor/methods/static methods, `extends`, `super`, and
non-enumerable prototype methods. Lower to constructor functions and prototype
wiring. Add construction, inheritance, `instanceof`, and `super` tests.

### [ ] P2-07 — Generators and `for await`

Implement `function*`, `yield`, `yield*`, generator objects, and async
iteration. This requires VM suspension/resumption state; define the frame
snapshot format before coding.

### [ ] P2-08 — Tagged templates

Parse `tag`template`` as a call with the cooked/raw string array and
expressions. Do not silently treat it as adjacent expressions.

### [ ] P2-09 — BigInt

Add lexer literal support (`123n`), a `TFloriaJSBigInt` value, arithmetic and
comparison rules, and `BigInt()` conversion. Defer if host interop does not
need it.

### [ ] P2-10 — Function constructor and function metadata

`new Function(...)` is currently a native function with no implementation, and
`fn.length`/`fn.name` are unavailable. Decide whether to implement the
constructor (requires parsing/compiling generated source) and at minimum expose
stable `length`/`name` properties.

### [ ] P2-11 — Library completeness audit

Add or explicitly defer the remaining bits currently known to be missing:

- `Object.is`, `defineProperty`, `getOwnPropertyNames`, `freeze`/`seal`.
- `Array.prototype.flat`/`flatMap`/`fill`/`copyWithin`/`at`.
- `String.fromCharCode`/`fromCodePoint`.
- Date component setters and broader parse formats.
- RegExp flags/features beyond `gim` (named groups, lookbehind, etc.) only if
  the chosen Pascal engine supports them; otherwise document limits.
- Symbol-keyed properties (currently symbols are stringified).

---

## Priority 3 — Performance and FTML fast paths

The VM is a pure interpreter. These tasks are for later and must be measured
against a checked-in benchmark, not guessed.

### [ ] P3-01 — Reduce VM dispatch overhead

- Measure the per-instruction `try`/`except` cost.
- Investigate routing JavaScript throws without wrapping every dispatch, or
  reduce the wrapped region while preserving catch semantics.
- Benchmark loops, calls, property access, and FTML binding updates before and
  after.

### [ ] P3-02 — Resolve user variables to slots

Currently only parameters/temporaries use VM local slots; user identifiers still
walk string-keyed environments. Add a compiler scope analysis that resolves
function/block locals to frame slots and emits `LOAD_LOC`/`STORE_LOC`, with an
environment fallback for closures and FTML delegate-object environments.

### [ ] P3-03 — Value representation

- Evaluate 64-bit NaN-boxed values or a tagged union.
- Reduce `TFloriaJSValue` copying and stack footprint.
- Keep compatibility with existing host factory helpers.

### [ ] P3-04 — Object shapes and inline caches

- Add shape/hidden-class transitions for ordinary objects.
- Add monomorphic property caches at bytecode sites.
- Preserve prototype-chain and getter/setter semantics.
- Do not change observable key enumeration order.

### [ ] P3-05 — FTML reactive fast path

- Compile each binding into a small snippet.
- Add a subscription-aware property opcode so dependency recording happens
  during evaluation, not through proxy overhead.
- Use direct field offsets for common item geometry (`x`, `y`, `width`,
  `height`).
- Target thousands of reactive updates per frame without allocation churn.

### [ ] P3-06 — AOT/JIT (optional, platform-gated)

Ahead-of-time compile pure arithmetic/layout bindings to Pascal function
pointers. A baseline machine-code JIT is optional and must be gated by
platforms with writable/executable memory. Never make correctness depend on
JIT availability.

---

## Intentionally deferred

These are deliberate embedded-runtime trade-offs. Keep them documented rather
than “fixing” them accidentally:

1. **UTF-8 byte strings.** `String.length`, indexing, `charAt`, and string
   iteration operate on native UTF-8 bytes, not UTF-16 code units.
2. **`globalThis` snapshot.** It exposes standard globals but is not a live
   proxy for later variable declarations or assignments. This preserves
   sandboxing.
3. **No object-to-primitive coercion for loose equality.** Recommend `===`.
   `[1] == 1` remains `false`.
4. **No ES modules.** `import`/`export` are deferred until a host module/package
   specification exists.
5. **`with`** remains unsupported and should fail clearly.
6. **Full ECMAScript conformance** is not a goal; the target is a practical
   embedded UI runtime.

`debugger` is **not** in this list: it currently throws an undeclared-name
`ReferenceError`. P1-05 must either make it a real no-op keyword or reject it at
parse time.

---

## Verification and maintenance

- Refresh the baseline before planning:
  ```bash
  pasbuild test
  bash scratch/run_gapscan.sh
  ./build.sh examples
  ```
- Add a probe for every JavaScript-visible change. A probe that only prints
  `OK` without checking the value is not sufficient.
- Add a lifetime test when a change creates objects, functions, environments,
  prototypes, or bytecode chunks.
- Update `docs/language-support.md` as part of the same commit. Several
  current statements are stale: `const` reassignment, function hoisting,
  `Function.prototype` support, and `debugger` are already implemented
  differently from what that page still says.
- Update the API pages when public signatures/behaviour change.
- Tick a checkbox only after the tests and docs are in place.
