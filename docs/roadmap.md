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
- Test suite: **209 tests pass** with `pasbuild test`.
- Gap scan: **162 probes OK / 7 ERR** with `bash scratch/run_gapscan.sh`.
  Some errors are expected (`throw`, unsupported `yield`); the probe harness is
  not an ECMAScript conformance suite.
- Unit count: 26 units.
- Documentation claims: **57 checked, 0 failing** with
  `bash scratch/run_docclaims.sh`.

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
- `Function.prototype.call`/`apply`/`bind` including construction and
  `instanceof` through a bound function, lexical `arguments` in arrows, and
  `Foo.prototype.constructor === Foo`.
- `Number("0x10")`, `parseInt("010")`, and ECMAScript-exact number formatting
  and parsing (`floria.js.number`), including `toString(radix)`.
- The `void` operator and the short-circuiting logical assignments `&&=` and
  `||=`, for identifiers and member targets.
- `new Promise(executor)` and a working microtask queue: `.then`/`.catch`/
  `.finally` and `await` all execute, and `JSON` honours `toJSON`, the
  replacer, getters, and the reviver.
- The iteration protocol: `Symbol.iterator`, iterator objects with `next()`,
  `for…of` over arrays/strings/`Map`/`Set`/iterators (including destructuring
  targets), and `Array.from`/spread over any iterable.
- Classes: declarations and expressions, constructors, methods, accessors,
  statics, `extends`, `super`, and non-enumerable prototype members.
- Tagged templates, with the cooked strings array, `raw`, and substitutions.
- Generators: `function*`, `yield`, `yield*`, suspension/resumption, and
  iteration over generator objects.
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
   Reject non-iterable values with `TypeError`. (P2-05 later widened this from
   array/string only to the full iteration protocol, so `Map`/`Set`/iterators
   destructure too.)
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

### [x] P1-02 — Array holes, explicit `undefined`, and `length` mutation

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

Explicit `undefined` elements and holes were indistinguishable because the
array stored only a dense value array. Numeric keys were not real object
properties.

**Files.**

- `src/main/pascal/floria.js.value.pas` (`TFloriaJSArray` presence bitmap,
  `length` setter, `delete` handling, `Array(n)`).
- `src/main/pascal/floria.js.arrays.pas` (hole-aware array methods).
- `src/main/pascal/floria.js.objects.pas` (keys/values/entries).
- `src/main/pascal/floria.js.vm.pas` (`FOR_IN_INIT`, new array opcodes).
- `src/main/pascal/floria.js.bytecode.pas` (`opArrayMarkHole`,
  `opArrayPushHole`, `opSpreadIterable`).
- `src/main/pascal/floria.js.compiler.pas` (array literal elisions and spread).

**Implementation.**

- Added a presence bitmap (`TFloriaJSArray.FPresent`) next to the element
  storage. A hole keeps its slot in the length but is not an own property, so
  an explicit `undefined` element stays distinguishable from an elision.
- Array literals compile elisions as `NEW_ARRAY` followed by one
  `ARRAY_MARK_HOLE` per elided index; the spread-built path appends holes with
  `ARRAY_PUSH_HOLE`. `NEW_ARRAY` still builds dense arrays.
- `new Array(n)` and `length = n` create holes. Assigning past the end fills the
  gap with holes, truncation releases the dropped elements, and `delete arr[i]`
  turns a present element into a hole without changing the length. Invalid
  lengths (fractional, negative, not representable) raise `RangeError`.
- `hasOwnProperty`, `in`, `Object.keys/values/entries`, and `for…in` consult the
  presence bitmap instead of testing for `undefined`.
- Array methods follow ECMAScript hole rules: `map`/`forEach`/`filter`/`some`/
  `every`/`reduce`/`reduceRight`/`indexOf`/`lastIndexOf` skip holes; `map`
  preserves them in its result; `join`/`toString` render them as empty text;
  `JSON.stringify` emits `null`; `concat`/`slice`/`splice`/`reverse`/`sort`
  preserve them (`sort` moves holes to the end).
- Spread uses the new `SPREAD_ITERABLE` opcode, which materialises an iterable
  into a dense array (holes become explicit `undefined`, strings expand to
  characters).
- `reduce`/`reduceRight` with no initial value throw `TypeError` when every
  index is a hole.
- Array enumeration still exposes only numeric indices and named properties,
  never `length`.

**Tests.** Explicit `undefined` vs holes, mixed arrays, `Object.keys/values/
entries`, `for…in`, `hasOwnProperty`, `new Array(n)`, index assignment past the
end, `delete`, length grow/shrink, invalid lengths, `join`/`JSON.stringify`,
spread densification, and the hole-skipping/preserving behaviour of every array
callback method. A Pascal-level test covers the presence API directly, and a
lifetime test checks that repeated length growth/truncation does not accumulate
objects and that truncation releases the dropped elements.

### [x] P1-03 — Correct `new` on bound functions

**Failure.**

```javascript
function C(x) { this.x = x; }
var B = C.bind(null, 7);
(new B()).x;   // TypeError: Cannot set properties of null
```

`bind` returned a *native* function whose only callback forwarded the call, so
`new` constructed that wrapper, not the target. The wrapper had its own empty
prototype, and the forwarded call ran the target with the bound `this` of
`null`.

**Files.** `src/main/pascal/floria.js.value.pas`
(`TFloriaJSBoundFunction`, `JSFunctionBind`, `JSInstanceOf`),
`src/main/pascal/floria.js.vm.pas` (`ConstructObject`, `CallFunction`,
`opCall`, `opNew`).

**Implementation.**

- `TFloriaJSBoundFunction` is now a `TFloriaJSFunction` subclass rather than a
  free-standing helper wrapped in a native method. It owns (and retains) the
  target, the bound `this`, and the bound arguments, and the heap frees it like
  any other tracked object.
- Bound functions are constructable iff their target is constructable.
  `new Bound(...)` ignores the bound `this`, constructs the target with the
  combined bound + call arguments, and installs the target’s prototype.
- `instanceof` traverses the target’s prototype chain: the heap resolves the
  constructor target through a chain of bound functions.
- Bound functions do not expose an own `prototype` (`SuppressPrototype`), while
  remaining ordinary function objects for `typeof`, enumeration, and
  `Function.prototype` methods.
- Calls of a bound function ignore the receiver in every dispatch path:
  `opCall`, `CallFunction` (used by `.call`/`.apply` and heap-side built-ins),
  and construction. A new `TFloriaJSConstructInvoker` callback lets the value
  unit construct the target without depending on the VM.

**Tests.** Bound partial args, `new`, `instanceof` for both the bound and the
target name, arrow targets rejected, non-constructor targets rejected,
`.call`/`.apply` on bound functions, chained binds, native constructors, and a
lifetime test that repeated bind/construct does not accumulate objects or
environments.

### [x] P1-04 — Number formatting and conversion parity

**Failure.**

```javascript
String(1e20);              // "1E20"        expected "100000000000000000000"
String(1e-7);              // "1E-7"        expected "1e-7"
(0.1 + 0.2).toString();    // "0.3"         expected "0.30000000000000004"
```

`ToString` used host formatting (`FloatToStr`), which both truncated precision
and used its own exponent style. The existing `1e20` test only checked the
first character, so it did not notice.

While fixing this it turned out the host *parser* is not correctly rounded
either: `StrToFloat("1e126")` returns a value one ulp above the true nearest
double. That affected `Number(...)`, numeric literals, and `parseFloat`, so
both directions were replaced.

**Files.** New `src/main/pascal/floria.js.number.pas`; wired into
`src/main/pascal/floria.js.value.pas` (`ToString`, `ToNumber`,
`JSNumberToString`), `src/main/pascal/floria.js.json.pas`,
`src/main/pascal/floria.js.lexer.pas`.

**Implementation.**

- Added `floria.js.number`, which does all conversion on **exact decimal digit
  strings** rather than through the host float routines:
  - Doubles are decomposed exactly (`m * 2^e`, expanded as `m * 5^k / 10^k`
    for negative exponents), so no precision is lost.
  - The rounding interval of a double is computed from the exact midpoints to
    its neighbours, with an inclusive endpoint only for an even mantissa
    (round-half-even). A decimal is accepted when it falls inside that
    interval.
  - `JSNumberToStr` searches digit counts from 1 upward and returns the first
    decimal that round-trips, so it is the shortest representation. It uses
    fixed notation for `1e-6 <= |x| < 1e21` and scientific notation outside,
    with `e+`/`e-` and no zero padding.
  - `JSTryStrToNumber` seeds from the host parser, then walks the double grid
    against the exact interval, which corrects the host's rounding. Overflow
    saturates to `Infinity`; underflow becomes `0`.
  - `JSNumberToRadixStr` implements `toString(radix)` for radix 2..36,
    including the fractional part.
- `ToString`, `ToNumber`, JSON number serialisation, and lexer literals now
  delegate to the new unit.
- `Number.prototype.toString(radix)` honours its argument (it previously
  ignored the radix and printed base 10) and throws a catchable `RangeError`
  outside 2..36.
- Negative zero prints as `"0"`, matching ECMAScript.

**Tests.** The three reported cases, exponent thresholds (`1e-6` fixed,
`1e-7` scientific, `1e20` fixed, `1e21` scientific), `e+` notation, exact
integers, `-0`/`NaN`/`Infinity`, both double extremes, a value needing all 17
digits, JSON number output, `Number(String(x))` round trips, correctly rounded
parsing (`1e126`, the smallest normal), subnormal and overflow boundaries, the
existing `Number` forms, and radix conversion including `RangeError`.

**Verification.** Beyond the unit tests, both directions were diffed against
Node.js over **41,626 bit patterns** (random doubles plus every decade
boundary and the extremes): zero differences. The same comparison over 8,037
decimal strings found no difference in the numeric core.

### [x] P1-05 — Fix `delete` and `debugger` semantics

**Failures.**

```javascript
delete undeclaredName;   // ReferenceError; ECMAScript non-strict: true
var x = 1; delete x;     // true, x remains; ECMAScript non-strict: false
debugger;                // ReferenceError; roadmap previously said no-op
```

`CompileAssignExpr`'s sibling unary path compiled `delete <identifier>` as an
ordinary expression read followed by `POP` and a literal `true`. Reading the
identifier is what produced the `ReferenceError`, and the unconditional `true`
ignored whether the binding is deletable. `debugger` was not a keyword at all,
so it fell through to an identifier read.

**Files.** `src/main/pascal/floria.js.lexer.pas` (`tkDebugger`, `tkWith`),
`src/main/pascal/floria.js.ast.pas` (`TFloriaJSDebuggerStmt`),
`src/main/pascal/floria.js.parser.pas` (`ParseDebuggerStatement`),
`src/main/pascal/floria.js.compiler.pas` (`tkDelete`, statement dispatch),
`src/main/pascal/floria.js.bytecode.pas` (`opDeleteEnv`),
`src/main/pascal/floria.js.vm.pas` (`opDeleteEnv`, `opDeleteProp`).

**Implementation.**

- Added `opDeleteEnv`: it answers `Has(name)` without reading the binding.
  A declared binding is non-deletable, so `delete x` is `false` and `x` keeps
  its value; an undeclared name is `true` and no binding is created.
- `delete <member>` keeps using `opDeleteProp`, which now throws `TypeError`
  when the base is `null`/`undefined`, matching the reference evaluation that
  ECMAScript performs first.
- `delete <non-reference>` still evaluates the operand and yields `true`.
- `debugger` is now a keyword, parsed into `TFloriaJSDebuggerStmt`, and
  compiled to nothing. Because it is a keyword it is also reserved, so
  `var debugger = 1` is a syntax error as in ECMAScript.
- `with` is now a keyword and is **rejected at parse time** with
  `'with' statements are not supported`, instead of surfacing later as an
  undeclared-name `ReferenceError`.
- The deferred-semantics section now separates `with` (unsupported, parse-time
  rejection) from `debugger` (supported no-op).

**Tests.** `delete` of an undeclared name (and that it creates no binding), of
`var`/`let`/`const`/parameter/function-local bindings, grouped targets,
non-reference operands, own properties, array holes, missing properties, and
`TypeError` for `delete null.x` / `delete undefined.x`; `debugger` at top
level, in a function, and in a block, plus its reserved-word status; and `with`
being a parse error rather than a `ReferenceError`.

---

### [x] P1-06 — Re-sync documentation with current runtime behaviour

**Failures.** The docs had drifted from the runtime in ways that a reader would
not notice, because nothing checked them:

- `docs/README.md` still said numeric formatting was non-standard, which P1-04
  had just fixed.
- `docs/architecture.md` did not list `floria.js.number` at all.
- `docs/development.md` referred to a `TFloriaJSEvaluatorTest` class that does
  not exist and omitted the whole Priority 1 suite.
- `docs/language-support.md` described `void 0` as yielding `0` (it always
  throws `ReferenceError`), said `class` was "sometimes silently ignored" (every
  form throws the same `ReferenceError`), and claimed `for…of` over a
  `Map`/`Set` "runs zero iterations" (it throws `TypeError`).
- `docs/api/values.md` never documented `TFloriaJSPrototypeObject`.
- The deviation table was a flat list mixing scheduled work, deliberate design
  decisions, and unexplained gaps, which is exactly the distinction the task
  asked for.

Two further deviations surfaced while verifying, and are now documented:
`this` at the top level of a script is unbound and throws, and a detached
`Foo.prototype` loses its `constructor` back-reference.

**Files.** `docs/README.md`, `docs/language-support.md`, `docs/architecture.md`,
`docs/development.md`, `docs/api/values.md`, `docs/roadmap.md`; new
`scratch/docclaims.pas` and `scratch/run_docclaims.sh`.

**Implementation.**

- Replaced the flat deviation table with the three required groups:
  **deliberate embedded trade-offs** (no scheduled change),
  **missing features (scheduled)** (each row names its roadmap task), and
  **known gaps** (unscheduled divergences).
- Collapsed the duplicate "Not implemented" list into a pointer at the
  scheduled table, so the two cannot drift apart.
- Corrected every statement listed under **Failures** above, and rewrote the
  tagged-template entries after finding that the tag is never called at all.
- Documented `TFloriaJSPrototypeObject`, including the weak-owner design that
  makes `constructor` work without a reference cycle.
- Added `floria.js.number` to the architecture unit table and the Priority 1
  suite to the test-suite list.

**Verification.** The acceptance criterion ("no statement in `docs/`
contradicts a passing test or a completed roadmap item") is only checkable by
executing the documented behaviour, so `scratch/docclaims.pas` encodes 36
statements from the page as assertions with their expected results. It reports
`36 claims, 0 failed`, and a deliberately wrong claim makes it fail, so it
detects drift rather than just passing.

## Priority 2 — Missing language and library features

Implement these only after P0 is clean. Each needs syntax/feature tests and a
gap-scan probe.

### [x] P2-01 — `void` operator

`opVoid` already existed in the bytecode set and the VM, but nothing emitted
it: `void` was not a keyword, so it lexed as an identifier and every use threw
`ReferenceError: void is not defined`.

**Files.** `src/main/pascal/floria.js.lexer.pas` (`tkVoid`),
`src/main/pascal/floria.js.parser.pas` (prefix set),
`src/main/pascal/floria.js.compiler.pas` (`tkVoid`).

**Implementation.** Added `tkVoid` inside the keyword block, included it in the
prefix-operator set, and compiled it to `opVoid`, which pops the operand and
pushes `undefined`. Precedence falls out of the existing unary path, so
`void 1 + 2` is `(void 1) + 2` = `NaN`, as in ECMAScript.

**Tests.** `void 0` and `typeof void 0`, operand side effects being kept, the
precedence against `+`, use in argument and property-value position, and a
missing operand being a syntax error.

### [x] P2-02 — Logical assignment operators

`&&=` and `||=` were parse errors.

**Files.** `src/main/pascal/floria.js.lexer.pas` (`tkAndAssign`, `tkOrAssign`),
`src/main/pascal/floria.js.parser.pas` (precedence and assignment dispatch),
`src/main/pascal/floria.js.compiler.pas` (`ShortCircuitAssignJump`).

**Implementation.** Added the two tokens, lexed by extending the existing `&&`
and `||` cases with an `=` check. The compiler already implemented `??=` as a
load / peek-test / conditional-assign / drop sequence, and the VM already had
the peeking jumps `opJumpIfFalseyPeek` and `opJumpIfTruthyPeek`, so the three
conditional assignments differ only in which jump performs the test. All four
`??=` sites (local, environment, computed member, named member) now accept the
three operators and pick the jump through `ShortCircuitAssignJump`. Because the
jump *peeks*, the skipped branch leaves the existing value on the stack, which
is what makes the expression value correct as well as avoiding the assignment.

**Tests.** Each operator assigning and skipping for identifiers and for named
and computed members, the expression value, truthiness following JavaScript
rules (`""`, `NaN`), no-space lexing, the member base being evaluated once,
`TypeError` on a null base, and — the important one — the right-hand side not
being evaluated when the assignment is skipped, proved with a side effect and
with a throwing function.

### Also fixed while working P2

- **Keyword property names were unreadable.** Five sites accepted a property
  name by comparing the token enum against a hard-coded keyword range. That
  broke for any keyword added after `tkUndefined`: `o.debugger` and `o.with`
  were syntax errors while `o.delete` worked. Replaced with an
  `IsKeywordToken` predicate that bounds the range by the last keyword, so new
  keywords are covered automatically.
- **BigInt literals silently evaluated to the wrong value.** `10n` lexed as the
  number `10` followed by the identifier `n`, so `var b = 10n;` threw
  `ReferenceError` only by luck: once any `n` existed in scope it silently
  became that variable's value. The lexer now rejects a BigInt suffix in every
  radix and in the decimal, fractional, and exponent forms. Found by the
  documentation-claims harness, not by the test suite.
- **Invalid assignment targets are accepted.** `1 += 2` and `f() &&= 1` should
  be `SyntaxError`; they currently evaluate to `undefined`. This affects every
  compound assignment and predates this work, so it is recorded under P2-11
  rather than fixed here.

### [x] P2-03 — Promise constructor

`Promise` was a plain object, so `new Promise(executor)` raised
`TypeError: Value is not a constructor`. Adding the constructor exposed a much
larger bug: **`SetJobRunner` was never called**, so the microtask queue was
never drained and no `.then`, `.catch`, or `.finally` callback had ever run —
`await` was broken in the same way. The existing tests only checked that the
promise *object* existed, never that a callback fired.

**Files.** `src/main/pascal/floria.js.value.pas`
(`TFloriaJSPromiseResolver`, `PromiseConstructor`, `NewPromise`,
`Attach` made public), `src/main/pascal/floria.js.vm.pas`
(`HeapJobRunner`), `src/main/pascal/floria.js.stdlib.pas` (registration).

**Implementation.**

- `TFloriaJSPromiseResolver` owns the per-promise `resolve`/`reject` pair and an
  already-settled flag, so the first call wins and later ones are ignored. A
  `of object` native method carries that state, which a bare function pointer
  could not.
- `PromiseConstructor` validates the executor, creates the promise, runs the
  executor synchronously, and rejects the promise if it throws. Resolving with
  the promise itself is a `TypeError` cycle.
- `Promise` is now a constructor function; the statics hang off the same
  object, so `Promise.resolve` still works.
- `TFloriaJSVM.HeapJobRunner` runs one reaction: it picks `finally`/reject/
  fulfill, passes the settlement through when no handler is supplied, calls the
  handler, rejects the child on a throw, adopts a returned promise, and lets
  `finally` forward the original settlement. The VM installs it through
  `SetJobRunner` and clears it on destruction, matching the existing
  invoker/constructor wiring.
- Promises now inherit from `Object.prototype` (`NewPromise` passed no
  prototype), so `p instanceof Object` holds.

**Tests.** Constructor identity and `typeof`, the executor running
synchronously with two function arguments, a non-callable executor being a
`TypeError`, statics still present, `then`/`catch`/`finally` actually running,
a throwing executor rejecting, first-settlement-wins, chaining, pass-through
for a missing handler, promise adoption, a throw inside a handler rejecting the
child, and `await` on resolve, on a constructed promise, and on a rejection.

### [x] P2-04 — JSON parity

`JSON.stringify` ignored the `replacer`, read stored property values instead of
running getters, and never called `toJSON`; `JSON.parse` had no reviver.

**Files.** `src/main/pascal/floria.js.json.pas`.

**Implementation.** `Serialize` now runs every value through `PrepareValue`
(`toJSON` first, then the replacer function) before type dispatch, and carries
the current property key so `toJSON(key)` and the replacer receive it. Object
members are read with `GetProperty`, so getters execute. A key-array replacer
filters object keys. `JSON.parse` walks the parsed tree depth-first through a
synthetic root holder, calling the reviver on every member and deleting
properties whose reviver returns `undefined`. Circular detection and
indentation are unchanged.

**Tests.** Getters invoked, `toJSON` on the root and receiving the key, `toJSON`
returning a structure or `undefined`, function replacer on objects and arrays,
a replacer dropping members, the key-array replacer, `undefined`/function
members omitted from objects but `null` in arrays, indentation with a replacer,
the reviver transforming numbers, deleting properties, handling arrays, walking
children before parents, and receiving the empty key for the root.

### [x] P2-05 — Map/Set iteration and iterators

`for…of` did not use the iteration protocol at all: `opForOfInit` copied arrays
and strings into a temporary array and threw for everything else, so `Map` and
`Set` were not iterable. `keys`/`values`/`entries` returned arrays, and
`Symbol.iterator` existed as a well-known symbol that nothing consumed.

**Files.** `src/main/pascal/floria.js.collections.pas`
(`TFloriaJSIterator`, `JSGetIterator`, `JSIteratorNext`, `JSIteratorToArray`,
`JSArrayValues`, `JSSet.GetItem`), `src/main/pascal/floria.js.vm.pas`
(`opForOfInit`, `opForOfNext`, `opSpreadIterable`),
`src/main/pascal/floria.js.bytecode.pas`, `src/main/pascal/floria.js.compiler.pas`
(`CompileForOfStmt`), `src/main/pascal/floria.js.ast.pas` /
`floria.js.parser.pas` (for-of patterns), `src/main/pascal/floria.js.arrays.pas`
(`Array.from`), `src/main/pascal/floria.js.stdlib.pas` (array iterator methods).

**Implementation.**

- `TFloriaJSIterator` is a native iterator object holding a source and a cursor.
  It implements `next()` returning `{value, done}` and `[Symbol.iterator]`
  returning itself, which is what makes an iterator usable directly in `for…of`
  and spread. It walks lazily instead of copying, so a large source costs
  nothing up front.
- `for…of` now wraps the iterable in an iterator (`opForOfInit`) and steps it
  each iteration (`opForOfNext`), which jumps past the loop when done. `for…in`
  keeps its existing array-of-keys shape, since it enumerates property names.
- `Map.prototype.keys/values/entries` and `Set.prototype.values/entries` return
  iterators. Set `entries` yields `[value, value]` as ECMAScript specifies.
- Arrays gained `values()` and `[Symbol.iterator]`.
- `Array.from` and spread consume any iterable, so `[...map.keys()]` and
  `Array.from(new Set(...))` work.
- `for (const [k, v] of map)` is supported: the loop target may be a
  destructuring pattern, compiled through the existing `CompileDestructuring`.
- Two tests that asserted the old array-returning behaviour were migrated to
  iterate instead, as the task anticipated.

**Tests.** `Symbol.iterator` and `values()` on arrays, `next()` producing
values then `done`, empty iterators, iterators being iterable, `for…of` over an
iterator, Map/Set helpers returning iterators (including Set `entries`
duplicating the value), `Array.from` and spread over iterators, `for…of` over
`Map`/`Set`/arrays/strings, `break`/`continue` in an iterator loop,
non-iterables still throwing, and destructuring in `for…of` for Map, arrays,
and a three-element pattern.

### [x] P2-06 — Classes

`class` was not a keyword, so every form parsed as an identifier and threw
`ReferenceError: class is not defined`. Nothing about classes existed: no
tokens, no AST node, no lowering, and properties had no enumerability concept,
so non-enumerable prototype methods were not even representable.

**Files.** `src/main/pascal/floria.js.lexer.pas` (`tkClass`, `tkExtends`,
`tkSuper`, `tkStatic`), `src/main/pascal/floria.js.ast.pas`
(`TFloriaJSClassNode`, `TFloriaJSClassMember`),
`src/main/pascal/floria.js.parser.pas` (`ParseClassExpr`,
`ParseClassDeclaration`, `super` as a primary),
`src/main/pascal/floria.js.compiler.pas` (`CompileClassExpr`),
`src/main/pascal/floria.js.bytecode.pas` / `floria.js.vm.pas` (`opSetProto`,
`opDefineHidden`, `opDefineGetterHidden`, `opDefineSetterHidden`),
`src/main/pascal/floria.js.value.pas` (property enumerability).

**Implementation.**

- Classes lower to a constructor function plus prototype wiring, which is what
  ECMAScript's class semantics are defined in terms of. A class declaration
  becomes a `let` declaration whose initializer is the class expression.
- `extends Base` creates a **fresh** prototype object whose prototype is
  `Base.prototype` (sharing the base object would overwrite its methods), and
  sets the class function's own prototype to `Base`, so static members are
  inherited.
- Properties gained an `Enumerable` flag with `SetPropertyNonEnumerable`,
  `SetEnumerable`, `GetEnumerablePropertyCount`, and
  `GetEnumerablePropertyKey`. `Object.keys`, `for…in`, and `JSON.stringify` now
  use the enumerable variants, so class methods stay out of reflection.
  Accessors created by `DefineGetter`/`DefineSetter` remain enumerable by
  default, matching object-literal syntax.
- `super` is bound as an ordinary name in a scope wrapped around each member's
  closure — to the base constructor inside a constructor, to the base prototype
  inside a method, and to the base class inside a static method. That makes
  `super(...)` and `super.m()` plain calls needing no special handling.
  `super(...)` passes the current `this`, so the base initialises the same
  object rather than a new one.
- `SetProperty` now walks the prototype chain looking for a setter before
  creating an own property, which is what makes an inherited class setter work.
- The class name is installed as `name`, so `A.name` works.
- Class fields (`class A { x = 1 }`) are rejected at parse time rather than
  silently ignored.

**Also fixed while working P2-06:** the declaration scope used
`TStringList`, which is **case-insensitive by default**, so `let A = 1; var a =
2;` was a spurious `SyntaxError: Identifier 'a' has already been declared`.
JavaScript identifiers are case-sensitive; the scope lists are now created with
`CaseSensitive := True`. This made any class whose name differed only in case
from another binding unusable.

**Tests.** Class identity (`typeof`, `name`), construction, implicit
constructors, methods on the prototype and shared, methods not being own
properties, statics and their absence on instances, class expressions,
getters, setters, chaining through `this`, field rejection, `instanceof` in
both directions, inherited and overridden methods, static inheritance,
`super()` with and without arguments, `super.method()`, an implicit derived
constructor, `super` being undefined in a base class, and non-enumerability
through `Object.keys`, `for…in`, and `JSON.stringify`.

### [x] P2-07 — Generators and `for await`

`function*` and `yield` were parse errors; there was no way to suspend and
resume bytecode.

**Frame snapshot format.** The task asked for this to be defined first. A
generator stores exactly the state `RunLoop` needs to resume:

- `Bytecode` and `IP` — where to continue, just past the `yield`.
- `Env` — the activation environment, so parameters and locals survive.
- `BaseBP` — the frame's stack base.
- The operand stack from `BaseBP` up to the yield point, retained.

Nothing else is live across a yield: try handlers belong to the enclosing call
and are not supported inside generators, and the frames above are unwound by
the suspension itself.

**Files.** `src/main/pascal/floria.js.lexer.pas` (`tkYield`),
`src/main/pascal/floria.js.ast.pas` (generator flags),
`src/main/pascal/floria.js.parser.pas` (`function*`, `yield`, `yield*`),
`src/main/pascal/floria.js.compiler.pas` (`opYield`, `CompileYieldStar`),
`src/main/pascal/floria.js.bytecode.pas` (`opYield`, `IsGenerator`),
`src/main/pascal/floria.js.value.pas` (`TFloriaJSGenerator`),
`src/main/pascal/floria.js.vm.pas` (`opYield`, `RunGenerator`, `MakeGenerator`).

**Implementation.**

- `TFloriaJSGenerator` holds the snapshot and implements `next()`, `return()`,
  and `Symbol.iterator`. It retains its bytecode, environment, arguments, and
  saved stack values, because a suspended generator outlives the call that
  created it.
- Calling a generator function builds an activation environment (binding
  parameters, `this`, and `arguments` exactly as a normal call does) and
  returns a suspended generator instead of running the body.
  `MakeGenerator` is shared by all three call paths so they cannot diverge.
- `opYield` snapshots the frame and unwinds **only the generator's own frames
  and stack slots**, then ends the nested `RunLoop`. Unwinding to stack zero
  also destroyed the caller's frame, which made a generator usable exactly once
  inside a loop — the bug that took longest to find.
- `RunGenerator` seeds locals on the first run and restores the snapshot on
  later ones, pushing the sent value as the result of the `yield` expression.
- `for…of` steps a generator through its own `next()`, and `yield*` lowers to
  an iterate-and-yield loop over the delegated iterable.

**Known limitation.** A generator cannot be resumed after the script that
created it ends; the activation environment is released with the script. This
is documented rather than silently failing.

**Tests.** Laziness, `next()` shape and values, parameters, `yield` outside a
generator, resumption across yields, completion via `return`, sent values
becoming the `yield` result, locals surviving suspension, `for…of` over a
generator (including a generator containing a loop), two independent
iterations, manual `while` draining, `return()` early completion, and `yield*`
over arrays, strings, and the empty iterable. Verified against Node over 16
cases: no differences.

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
- Reject non-reference assignment targets. `1 += 2`, `f() &&= 1`, and
  `(a + b) = 1` should be `SyntaxError`, but the parser only rejects optional
  chains, so the compiler silently produces `undefined`. This affects every
  assignment operator, including the plain `=`, and was found while adding
  `&&=`/`||=`.

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

`with` is rejected at parse time rather than at run time, so unsupported syntax
fails loudly as the policy above requires. `debugger` is a supported no-op
keyword, so it is not deferred.

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
- Update `docs/language-support.md` as part of the same commit. Re-read the
  page for statements the change just invalidated; several were stale before
  the P0/P1 work and have been corrected one task at a time.
- Update the API pages when public signatures/behaviour change.
- Tick a checkbox only after the tests and docs are in place.
