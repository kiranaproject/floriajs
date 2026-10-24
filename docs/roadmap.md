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
- Test suite: **176 tests pass** with `pasbuild test`.
- Gap scan: **109 probes OK / 11 ERR** with `bash scratch/run_gapscan.sh`.
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

### [x] P0-03 — Compile destructuring assignment (with iterable validation)

**Failure.**

```javascript
var a, b;
[a, b] = [1, 2];       // a and b are both undefined
var o = {};
({ a } = { a: 3 });    // a is undefined
[a] = 5;               // ECMAScript: TypeError
[a] = {0: 7, length: 1}; // ECMAScript: TypeError
```

Declaration destructuring works; **assignment** destructuring was silently
ignored by `CompileAssignExpr`, and array destructuring was previously treating
plain objects like array-likes instead of checking for iterable values.

**Files.**

- `src/main/pascal/floria.js.compiler.pas` (`CompileAssignExpr`,
  `CompileDestructuring`).
- `src/main/pascal/floria.js.bytecode.pas` (`opAssertIterable`).
- `src/main/pascal/floria.js.vm.pas` (`opAssertIterable` runtime check).
- `src/main/pascal/floria.js.env.pas` for const assignment errors.

**Implementation.**

1. Evaluate RHS once and duplicate on the stack for the expression result.
2. For array destructuring, emit `opAssertIterable` before unpacking elements.
   Reject non-array/string values (numbers, booleans, plain objects, Set without
   iterator support) with `TypeError`. Full iterator protocol (`Symbol.iterator`)
   for `Map`/`Set` destructuring is scheduled with P2-05.
3. For identifier targets in assignment destructuring, emit `opStoreEnv` (which
   throws `TypeError` on const bindings).
4. For member targets, evaluate target and property, and store through `opSetProp`/
   `opSetPropNamed`.
5. Support object/array patterns, defaults, rest, nested patterns, computed keys,
   and skipped array elements.
6. The expression result is the original RHS value.

**Tests.** Array/object, nested, defaults, rest, member targets, computed keys,
array holes, const-target rejection, non-iterable rejection (`[a]=5`,
`[a]={0:7, length:1}`, `[a]=new Set([1])`), string unpacking (`[a, b] = "xy"`),
and single evaluation of RHS.

---

### [x] P0-04 — Implement `var` hoisting and cross-scope declaration conflicts

**Failure.**

```javascript
function f() { return a; var a = 1; }     // ReferenceError; expected undefined
function f() { a = 5; var a; return a; }  // undefined; expected 5
function a() { return 1; }
var a;
a();                                      // TypeError; expected 1
function f() { let x = 1; { var x = 2; } } // accepted; expected SyntaxError
```

Function declarations were hoisted, but `var` declarations were not. A bare
`var a;` also overwrote a hoisted function with `undefined`. Furthermore,
`var` declarations inside nested blocks/switches/loops did not conflict with
enclosing lexical `let`/`const` declarations.

**Files.**

- `src/main/pascal/floria.js.compiler.pas` (`TFloriaJSDeclarationScope`,
  `ValidateScopeStmt`, `CompileProgram`, `CompileFunctionBody`, `CompileBlockStmt`,
  `CompileVarStmt`).
- `src/main/pascal/floria.js.bytecode.pas` (`opDeclareVar`).

**Implementation.**

- Implemented unified declaration-scope analyzer (`TFloriaJSDeclarationScope`)
  traversing statement trees for functions and programs prior to bytecode emission.
- Tracks `LexicalNames`, `AllSubtreeVars`, and `ParamNames`/`CatchParam`.
- Hoisted `var` declarations propagate up the scope tree; any ancestor lexical
  scope with a matching `let`/`const` triggers `SyntaxError`.
- Valid shadowing is preserved: `{ let x = 1; } var x = 2;` and
  `function f(){ var x=1; { let x=2; } return x; }` remain valid.
- Function parameters collide with lexical declarations in the function body,
  while `var` of the same name is allowed.
- Catch parameters collide with lexical declarations in the catch block, while
  `var` of the same name is allowed.
- Hoist function declarations before entry declarations, and make a function
  declaration win over a bare `var` of the same name.

**Acceptance.**

```javascript
function f() { return a; var a = 1; }       // undefined
function f() { a = 5; var a; return a; }    // 5
function a() { return 1; } var a; a();      // 1
function f() { let x = 1; { var x = 2; } }  // SyntaxError
let x = 1; switch (1) { case 1: var x = 2; } // SyntaxError
for (let i = 0; i < 1; i++) { var i; }      // SyntaxError
```

**Tests.** Declaration order, assignment before declaration, nested blocks,
cross-scope var/let conflicts in functions, scripts, switches, and loops, plus
valid shadowing cases.

---

### [x] P0-05 — Implement chain-wide optional chaining short-circuit and grouping boundaries

**Failure.**

```javascript
var a = null;
a?.b.c;          // TypeError; expected undefined
a?.b();          // TypeError; expected undefined
a?.b(sideEffect()); // TypeError; expected no argument evaluation
(a?.b).c;        // undefined; ECMAScript: TypeError
new a?.b();      // TypeError; ECMAScript: SyntaxError
```

Previously, only immediate access was optional, and parenthesized chains
leaked short-circuiting across grouping boundaries.

**Files.**

- `src/main/pascal/floria.js.ast.pas` (`TFloriaJSGroupExpr`,
  `ContainsOptionalChain`).
- `src/main/pascal/floria.js.parser.pas` (`ParsePrimary`, `ParseNewExpression`,
  `ParseMemberTail`, `ExtractParameters`, `IsOptionalChainTarget`).
- `src/main/pascal/floria.js.compiler.pas` (`CompileOptionalChain`,
  `CompileMemberExpr`, `CompileCallExpr`, `CompileAssignExpr`,
  `CompileUnaryExpr`).

**Implementation.**

- Added `TFloriaJSGroupExpr` AST node for parenthesized expressions `(expr)`.
- `ContainsOptionalChain` returns `False` for `TFloriaJSGroupExpr`, terminating
  the optional chain so subsequent access (`(a?.b).c`) evaluates normally on
  `undefined` and raises `TypeError`.
- `CompileOptionalChain` emits guarded short-circuit jumps (`opJumpNullish`)
  over chained member access, calls, and argument expressions.
- `ParseNewExpression` rejects `?.` while parsing the callee, so
  `new a?.b()` fails in the parser instead of constructing `a` first.
- Invalid assignment and update targets with optional chains (`a?.b = 1`,
  `(a?.b) = 1`, `a?.b++`, `(a?.b)++`, `++(a?.b)`) are rejected as syntax
  errors. Grouping is unwrapped only for this target check; it still terminates
  optional-chain short-circuiting during evaluation.
- Valid parenthesized references stay transparent: `(a)++`, `(a.b)++`, and
  `delete (a.b)` target the same binding/property as their unparenthesized
  forms.

**Tests.**

- `a?.b`, `a?.[k]`, `a?.()`, `a?.b()`, `a?.b.c`, `a?.b?.c`.
- Nullish base skips computed-key evaluation and call arguments.
- Non-null base behaves normally (`(a?.b).c === 10`).
- Grouping boundaries terminate short-circuiting: `(a?.b).c` and `(a?.b)()` throw
  `TypeError` on null base.
- `(a?.b)?.c` starts a new optional chain and returns `undefined`.
- `new a?.b()`, `new a?.b`, `new a?.[0]()`, and `new a?.()` are rejected with a
  parser error; `new (a?.b)()` remains valid.
- Optional-chain assignment and update expressions are rejected, including
  grouped forms; the assertions check the parser error text.
- Valid grouped updates and deletes still mutate their targets.

---

### [x] P0-06 — Make constructor back-references lifetime-safe

**Risk.** `TFloriaJSPrototypeObject` stores the owner function in a raw pointer.
`TFloriaJSFunction.Destroy` only cleared the owner of the function’s **current**
`prototype` property. If the prototype was replaced or deleted first, an old
prototype held by user code kept a dangling owner pointer:

```javascript
function F() {}
var p = F.prototype;
F.prototype = {};
F = null;
// p.constructor may now dereference a freed function
```

**Files.** `src/main/pascal/floria.js.value.pas`
(`TFloriaJSFunction`, `TFloriaJSPrototypeObject`, `SetProperty`/`DeleteProperty`),
`src/main/pascal/floria.js.objects.pas` (`InitObjectBuiltin`).

**Implementation.**

- Track every prototype object created for a function in a weak registration list
  (`FRegisteredPrototypes`).
- On function destruction, detachment, or prototype replacement/deletion,
  clear the back-reference (`FOwnerFunction := nil`) on all registered prototypes.
- When `FOwnerFunction = nil`, prototype `.constructor` safely delegates to
  `Object.prototype.constructor === Object`.
- Cycle safety: `Object.prototype.constructor` back-reference is safely wired
  and reclaimed on `Clear`.

**Tests.** Replace/delete `prototype`, force `Collect`, read the old
prototype’s `constructor`, and verify prototype reclamation without leaks.

---

### [x] P0-07 — Complete declaration validation and switch-case hoisting

**Failures.**

```javascript
function f(a) { let a = 1; return a; }       // should be SyntaxError
for (let i = 0, i = 1; i < 2; i++) {}        // should be SyntaxError
try { throw 1; } catch (e) { let e = 2; }    // should be SyntaxError
switch (1) { case 1: f(); function f(){} }   // f should be hoisted
let x = 1; { var x = 2; }                    // should be SyntaxError
```

Unified with P0-04 under `TFloriaJSDeclarationScope`.

**Files.**

- `src/main/pascal/floria.js.compiler.pas` (`TFloriaJSDeclarationScope`,
  `ValidateScopeStmt`, `CompileSwitchStmt`).

**Implementation.**

- Pre-pass declaration validator processes functions, parameter lists, catch
  parameters, `for` headers, and switch bodies.
- Switch case clauses share a single lexical scope; duplicate lexical declarations
  and cross-scope `var`/`let` collisions are rejected at compile time.
- Switch function declarations hoist across all case clauses before execution.

**Tests.** Parameter redeclarations, catch parameter redeclarations, for-loop
header duplicates, switch duplicate let, switch function hoisting before textual
declaration, and cross-scope var/let conflicts.

---

## Priority 1 — ECMAScript parity and remaining core semantics

These are not memory-safety blockers, but they still cause wrong results in
ordinary scripts.

### [x] P1-01 — Classic `for` `let`/`const` scoping and per-iteration closures

**Failure.**

```javascript
var f = [];
for (let i = 0; i < 3; i++) f.push(() => i);
f[0]() + f[1]() + f[2]();   // 9 (3,3,3); expected 3 (0,1,2)
typeof i;                    // "number"; expected "undefined"
```

`CompileForStmt` used the surrounding environment for `let`/`const`
initializers and did not create per-iteration bindings, so all closures shared
the final loop value and the binding remained visible after the loop.
`for…of`/`for…in` already had per-iteration environments.

**Files.** `src/main/pascal/floria.js.compiler.pas` (`CompileForStmt`),
`src/test/pascal/TestRunner.pas`.

**Implementation.**

- Push an outer loop environment for `let`/`const` initializers and keep `var`
  initializers in the enclosing function/program environment.
- Before each body, push a fresh per-iteration environment and copy the current
  loop bindings into it, so closures capture that iteration's values.
- At `continue`, copy body-modified `let` values back to the outer loop
  environment before running the update expression, then start the next
  iteration with a new environment.
- `break` uses a cleanup path that pops the per-iteration and outer loop
  environments; the normal test-false path pops only the outer environment.
  `return` and `throw` unwind through the existing environment cleanup.
- `const` loop bindings are copied per iteration but not written back; an update
  expression still raises `TypeError` as before.

**Tests.** Closures capture 0/1/2, no binding leaks after the loop, multiple
loop declarators, labeled/nested `break`/`continue`, `return` from inside the
loop, exception paths, `const` without an update, shared `var` semantics, and a
5,000-iteration environment-growth check.

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
