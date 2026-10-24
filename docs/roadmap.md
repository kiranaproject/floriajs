# floriajs — Implementation Roadmap

This roadmap records the JavaScript features that are still missing or silently
incomplete, ordered by the value they add to real scripts running on the Floria
JS runtime.

The list is derived from the gap-scan harnesses in `scratch/` (`gapscan.pas` and
`gapscan2.pas`), which run 120 small probes against the current library. The
`scratch/` directory is ignored by Git; the harnesses are working tools, not
part of the published test suite.

## How to refresh the scan

```bash
bash scratch/run_gapscan.sh
```

The probes are deliberately small: each one exercises a single language feature
or standard-library entry point and prints either `OK -> <value>` or
`ERR -> <message>`.

## Historical baseline (before the Priority 1–3 work)

These numbers describe the state when this roadmap was first written; they are
kept for context, not as a current status.

- 120 probes total.
- 27 probes report an error: 25 are parse/lex gaps, one is the expected uncaught
  `throw` probe, and one is the `parseFloat` bug.
- About 45 of the remaining 93 probes *parse and run* but return `undefined`
  or a wrong value. These silent gaps are the most damaging kind, because a
  script looks like it works while producing incorrect results.

Recently implemented and now passing in the scan:

- `switch`, `try` / `catch` / `finally`, `throw`
- `new` and `this` (including constructor prototypes and methods)
- `async` / `await`, promises, `do...while`, exponentiation
- Closures, block scoping for `let`, recursion and environment reclamation
- Array prototype and static methods (`push`, `pop`, `shift`, `unshift`, `join`, `concat`, `reverse`, `sort`, `slice`, `splice`, `indexOf`, `lastIndexOf`, `includes`, `map`, `filter`, `reduce`, `forEach`, `some`, `every`, `find`, `Array.isArray`, `Array.from`, `Array.of`)
- String prototype methods (`charAt`, `indexOf`, `slice`, `toUpperCase`, `trim`, `split`, `replace`, `concat`, `repeat`, etc.)
- Arrow functions (`x => expr`, `(x, y) => expr`, `(x) => { statements }`, `() => ...` with lexical `this`)
- Operators: comma operator `(a, b)`, `in`, `instanceof`, optional chaining `?.`, `??=`, `**=`, labeled `break`/`continue`
- Standard globals: `NaN`, `Infinity`, `Number()`, `String()`, `Boolean()`, `Number.isNaN`, `Number.isFinite`, `Number.isInteger`, `Number.parseInt`, `Number.parseFloat`, `globalThis`, `arguments` inside function calls
- Object utilities: `Object.keys`, `Object.values`, `Object.entries`, `Object.assign`, `Object.create`, `hasOwnProperty`, `Object.prototype.toString`, `Function.prototype.toString`
- Real JSON serialization & parsing: `JSON.stringify` (with indentation and circular reference detection) and `JSON.parse`
- Template literal interpolation: `${...}` with recursive expression evaluation
- Object and array literal completion: shorthand `{ x }`, computed keys `{ [k]: v }`, spread `{ ...o }`, array spread `[...a]`, array holes `[1, , 3]`, object methods `{ f() {} }`, getters and setters `{ get x() {}, set x(v) {} }`
- Iteration statements: `for...of` (arrays, strings), `for...in` (prototype chain keys), per-iteration closure environment isolation
- Function parameter forms & Destructuring: default parameters `f(a = 3)`, rest parameters `f(...args)`, destructuring declarations `var { a } = obj`, `var [a, b] = arr`, destructuring parameters in regular and arrow functions
- Math extensions: `Math.log2`, `Math.log10`, `Math.sign`, `Math.trunc`, `Math.hypot`, `Math.cbrt`, `Math.imul`, `Math.clz32`
- Numeric separators (`1_000_000`), exponent literals (`1e3`), hex string parsing
- Error handling & runtime type errors: `Error`, `TypeError`, `RangeError`, `ReferenceError`, and `SyntaxError` with prototype chain inheritance, standard `toString()`, and runtime `TypeError` / `RangeError` throwing for invalid calls, stack overflow, and `null`/`undefined` property operations
- Priority 3 Advanced & Host Features: `Map`, `Set` collections with SameValueZero key comparison, `Date` constructor, epoch MS, UTC/local accessors and ISO-8601 formatting, `Symbol` primitive, registry (`Symbol.for`, `Symbol.keyFor`), and well-known symbols, `RegExp` engine with `/pattern/flags` regex literals, `test()`, `exec()`, and string pattern matching (`match`, `search`, `replace`, `split`), URI utilities (`encodeURIComponent`, `decodeURIComponent`, `encodeURI`, `decodeURI`), and host timers (`setTimeout`, `clearTimeout`, `setInterval`, `clearInterval`).

## Two kinds of gaps

1. **Hard gaps** — the parser or lexer rejects the syntax. Easy to notice.
2. **Silent gaps** — the syntax is accepted but the runtime is missing the
   behaviour. Examples:
   - `[k]: 1` inside object literals
   - `` `v=${n + 1}` `` → the literal text `v=${n + 1}`
   - `Object.keys({a: 1})` → `undefined`

Priority is therefore given to closing silent gaps first, then to syntax that
unlocks idiomatic modern JavaScript.

---

## Priority 1 — Everyday JavaScript

These items are prerequisites for writing ordinary scripts without workarounds.
They are also what FTML handlers and UI bindings are most likely to use.

### 1. Array methods

Status: supported and verified. Full suite of Array prototype and static methods implemented in `src/main/pascal/floria.js.arrays.pas` with unit tests in `TestRunner.pas` and gap-scan probes.

- [x] `push`, `pop`, `shift`, `unshift`
- [x] `join`, `concat`, `reverse`, `sort` (with optional comparator)
- [x] `indexOf`, `lastIndexOf`, `includes`
- [x] `slice`, `splice`
- [x] `map`, `filter`, `reduce`, `forEach`, `some`, `every`, `find` (plus `findIndex`, `reduceRight`)
- [x] `Array.isArray`, `Array.from` (plus `Array.of`)
- [x] Correct array length/assignment behaviour while the methods run

### 2. String methods

Status: supported and verified. Full suite of String prototype methods implemented in `src/main/pascal/floria.js.strings.pas` and registered via `FloriaJSRegisterString` on the heap's string prototype.

- [x] `charAt`, `charCodeAt`
- [x] `indexOf`, `lastIndexOf`, `includes`, `startsWith`, `endsWith`
- [x] `slice`, `substring`, `substr`
- [x] `toUpperCase`, `toLowerCase`
- [x] `trim`, `trimStart`, `trimEnd`
- [x] `split`
- [x] `replace` / `replaceAll` (string patterns)
- [x] `concat`, `repeat`, `padStart`, `padEnd`

### 3. Standard globals

Status: supported and verified. Global constants, type conversion constructors, static methods on `Number`, `globalThis`, and `arguments` parameter object are fully implemented and verified with tests and gap-scan probes.

- [x] `NaN`, `Infinity`
- [x] `Number()`, `String()`, `Boolean()` constructors and conversions
- [x] `Number.isNaN`, `Number.isFinite`, `Number.isInteger`, `Number.parseInt`, `Number.parseFloat`
- [x] `globalThis`
- [x] `arguments` inside function calls
- [x] Fix `parseInt` to honour the radix argument
- [x] Fix `parseFloat` (handles partial numeric prefix like `"3.5x"`)

### 4. Object utilities

Status: supported and verified. Full suite of `Object` utilities, `hasOwnProperty`, `toString` helpers, and prototype-chain traversal implemented and wired to the global environment and object prototype.

- [x] `Object.keys`, `Object.values`, `Object.entries`
- [x] `Object.assign`, `Object.create`
- [x] `hasOwnProperty` on objects
- [x] `Function.prototype.toString` (and `Object.prototype.toString`)
- [x] Keep the existing prototype-chain lookup working for objects made with
      `Object.create`

### 5. JSON

Status: supported and verified. Fully compliant RFC 8259 parser and serializer implemented in `src/main/pascal/floria.js.json.pas` supporting primitives, nested objects/arrays, indentation spacing, and circular reference detection.

- [x] `JSON.stringify` for primitives, arrays, objects, nested values
- [x] `JSON.parse`
- [x] Round-trip tests, including `undefined`/function properties being omitted

### 6. Arrow functions

Status: supported and verified. Parser handles concise bodies and block bodies, zero, single, and multi parameters, async arrows, and runtime enforces lexical `this` without constructor instantiation.

- [x] `x => expression`
- [x] `(x, y) => expression`
- [x] `(x) => { statements }`
- [x] Lexical `this` (arrow functions must not rebind `this`)
- [x] Interaction with the existing closure and environment reclamation rules

### 7. Template literal interpolation

Status: supported and verified. Interpolation `${...}` expressions inside template strings are recursively lexed and evaluated with results concatenated into the template literal.

- [x] Parse `${...}` sections inside template strings
- [x] Evaluate the embedded expressions and concatenate the results
- [x] Keep plain template strings working
- [ ] Tagged templates are a Priority 3 item and stay out of this step

### 8. Object and array literal completion

Status: supported and verified. Support for shorthand properties, computed keys, object and array spread, array holes with correct length, object method definitions, and getters/setters.

- [x] Object shorthand: `{ x }`
- [x] Computed keys: `{ [k]: value }`
- [x] Object spread: `{ ...source }`
- [x] Array spread: `[0, ...items]`
- [x] Array holes: `[1, , 3]` with the expected `length`
- [x] Object methods: `{ f() { ... } }`
- [x] Getters/setters (`get x()` / `set x(v)`)

### 9. Iteration statements

Status: supported and verified. `for...of` over arrays and strings, `for...in` over own and inherited enumerable keys (skipping non-enumerable `Object.prototype`), `break`/`continue` handling, and isolated per-iteration closure environments.

- [x] `for...of` over arrays and strings
- [x] `for...in` over enumerable keys
- [x] `for (const x of ...)` and `for (let x of ...)`
- [x] `for (const i = 0; ...; ...)` in classic `for` loops
- [x] `break`/`continue` inside loops (including multi-level labeled loops)

### 10. Function parameter forms

Status: supported and verified. Default parameters, rest parameters, array and object destructuring declarations, and parameter destructuring in both standard functions and arrow functions.

- [x] Default parameters: `function f(a = 3)`
- [x] Rest parameters: `function f(...args)`
- [x] Destructuring parameters: `function f({ a })` / `([a, b])`
- [x] Destructuring declarations: `var { a } = obj;` / `var [a, b] = arr;`

---

## Priority 2 — Correctness and common idioms

These items mostly affect semantics rather than enabling new syntax.

### 11. Silent operator gaps

- [x] `in` returns a real boolean instead of `undefined`
- [x] `instanceof` returns a real boolean, using the prototype chain
- [x] Optional chaining: `a?.b`, `a?.[k]`, `a?.()`
- [x] Nullish assignment: `??=`
- [x] Power assignment: `**=`
- [x] Comma operator: `(a, b)`
- [x] Labeled `break` / `continue`

### 12. Error handling polish

Status: supported and verified. Builtin constructors `Error`, `TypeError`, `RangeError`, `ReferenceError`, and `SyntaxError` with prototype inheritance, JavaScript standard `toString()` formatting, and runtime `TypeError` / `RangeError` throwing for invalid operations.

- [x] `TypeError`, `RangeError`, `ReferenceError`, `SyntaxError` constructor objects
- [x] Throwing a `TypeError` from the runtime where JavaScript requires it
      (see the cross-cutting item below)
- [x] Error `name`, `message`, and `toString()` behaviour matching JavaScript

### 13. Math extensions

- [x] `Math.log2`, `Math.log10`, `Math.sign`, `Math.hypot`
- [x] `Math.cbrt`, `Math.imul`, `Math.clz32` (lower priority)
- [x] Keep the existing `Math` constants and functions unchanged

### 14. Numeric and lexer gaps

- [x] Numeric separators: `1_000_000`
- [x] Exponent notation (`1e3`) and hex literals (`0x10`) confirmed in lexer/parser

---

## Priority 3 — Advanced and host-oriented features

These are valuable for completeness and for richer host integration, but they
are not on the critical path for ordinary UI scripts.

### 15. Collections and data types

Status: supported and verified. Implemented `Map` and `Set` collections (`floria.js.collections.pas`) with SameValueZero semantics, `Date` object (`floria.js.date.pas`) with UTC/local accessors, ISO formatting, and epoch calculations, and `Symbol` primitive (`floria.js.symbol.pas`) with global registry (`Symbol.for`, `Symbol.keyFor`) and well-known symbols.

- [x] `Map`
- [x] `Set`
- [x] `Date` (at least `now()` and basic construction/formatting)
- [x] `Symbol` (at least well-known symbols used by the host API)
- [ ] `BigInt` (only if host interop needs it)

### 16. Regular expressions

Status: supported and verified. Native Pascal `RegExpr` engine wrapper (`floria.js.regexp.pas`) providing `RegExp` constructor, `/pattern/flags` regex literal parsing in lexer and parser, `test()`, `exec()`, and integration into `String.prototype.match`, `search`, `replace`, and `split`.

- [x] Regex literals: `/ab+c/i`
- [x] `RegExp` constructor
- [x] `test`, `exec`
- [x] Regex-aware `String.replace` / `split` / `match` (and `search`)

### 17. Syntax depth

- [ ] `class` syntax (currently silently ignored — `class A {} 1;` returns `1`)
- [ ] Generators: `function*` and `yield`
- [ ] Tagged template literals
- [ ] Async iteration (`for await`)
- [ ] `import` / `export` (only if a module system is in scope)

### 18. Host-provided globals

Status: supported and verified. Implemented standard URI utilities (`floria.js.uri.pas`) for component and full URI encoding/decoding, and timer host globals (`floria.js.timers.pas`) with `setTimeout`, `clearTimeout`, `setInterval`, `clearInterval`, and promise job integration.

- [x] `setTimeout` / `clearTimeout` (bridge to the existing promise job queue)
- [x] `encodeURIComponent` / `decodeURIComponent`, `encodeURI` / `decodeURI`
- [x] Any UI-specific globals belong in the host adapter, not the core language

---

## Cross-cutting work

### Make invalid operations throw instead of returning `undefined`

Currently `var o = {}; o.nope();` and `var o; o.nope;` both return `undefined`
without an error. This is why dozens of missing standard-library methods looked
like passing probes. Changing these to throw `TypeError` is closer to JavaScript
and makes future gaps immediately visible.

- [x] Calling a non-function throws `TypeError`
- [x] Property access on `null` / `undefined` throws `TypeError`
- [x] Setting a property on `null` / `undefined` throws `TypeError`
- [x] Audit existing tests, examples, and FTML engine code for scripts that
      relied on the silent behaviour

This is a small code change with a large diagnostic payoff, but it should be
done deliberately because it is observable behaviour.

### Testing expectations

Every feature above should land with:

- Unit tests in `src/test/pascal/TestRunner.pas` (new suite or extension of the
  existing suites, following the current naming style).
- At least one probe added to the gap scan so the feature stays covered.
- A leak check for anything that creates objects, functions, or environments:
  the engine uses reference counting plus safe-point reclamation, so new
  container types must not introduce cycles or accumulate heap objects.

### Library layout

`floria.js.stdlib.pas` is currently the single place where globals are
registered. As string, array, JSON, and collection support grows, consider
splitting helper implementations into additive units such as
`floria.js.stdlib.strings`, `floria.js.stdlib.arrays`, and
`floria.js.stdlib.json`, while keeping registration in the existing
`RegisterGlobals` entry point. This keeps the public API additive and avoids one
oversized file.

---

## Suggested delivery slices

### Slice A — "usable scripts"

Array methods, string methods, standard globals, `Object.keys`, `JSON`, plus the
`parseInt`/`parseFloat` fixes.

Acceptance:

- The existing gaps for array/string methods and coercion disappear from the
  scan.
- No new heap growth in the leak harnesses.
- At least one end-to-end example script using arrays, strings, and JSON.

### Slice B — "modern syntax"

Arrow functions, template interpolation, object/array shorthand and spread,
`for...of` / `for...in`, default/rest parameters.

Acceptance:

- The corresponding hard-gap probes pass.
- Arrow functions preserve lexical `this`.
- Closures created by arrows are reclaimed when they do not escape.

### Slice C — "correctness and polish"

`in` / `instanceof`, optional chaining, assignment operators, labeled
statements, error subclasses, Math extensions, numeric separators.

Acceptance:

- No silent operator gaps remain in the scan.
- Runtime type errors throw catchable `TypeError` objects.

### Slice D — "Bytecode VM Core"

Status: supported and verified. Flat stack-based bytecode virtual machine (`TFloriaJSVM`), bytecode container (`TFloriaJSBytecode`), and AST-to-bytecode compiler (`TFloriaJSCompiler`) with full integration into `TFloriaJSEngine` (`fjbBytecodeVM`).
- All 151 unit test cases pass cleanly against the runtime and VM pipeline.
- 3.0x to 4.3x execution throughput speedup measured over the tree-walking evaluator in micro-benchmarks.
- Support for arithmetic, local registers, jumps, function calls, objects, arrays, exceptions (`try/catch/finally`), `switch`, `for..in`, `for..of`, and labeled breaks.

- [x] Bytecode instruction set & chunk container (`floria.js.bytecode.pas`)
- [x] Stack-based virtual machine execution loop (`floria.js.vm.pas`)
- [x] AST-to-bytecode compiler (`floria.js.compiler.pas`)
- [x] Engine backend selection (`fjbInterpreter` and `fjbBytecodeVM` in `floria.js.core.pas`)
- [x] Verified unit tests and execution benchmark speedup

### Slice E — "QML V4-Class Reactive Bindings & JIT"

Compiled FTML property binding snippets, specialized reactive tracking opcodes,
inline property caching, and optional AOT/JIT compilation for hot layout functions.

Acceptance:

- Thousands of reactive bindings evaluate smoothly at 60+ FPS layout cycles.
- Direct native Pascal item memory access with zero FFI overhead.

---

## Priority 4 — Virtual Machine Architecture (QML V4-Class Engine)

To achieve parity with QML's custom V4 engine, the runtime will evolve from an
AST tree-walking interpreter to a tailored, pure-Pascal bytecode virtual machine.

### Motivation & Strategic Advantages

1. **Parity with QML V4**: QML abandoned full web engines (V8) because UI
   applications do not need multi-megabyte browser runtimes; they need **instant
   startup, low memory per component, and high-frequency micro-evaluations** of
   declarative property bindings (e.g. `width: parent.width * 0.5`).
2. **Zero C ABI Overhead**: A native Pascal VM interacts directly with FTML Pascal
   visual items without FFI marshaling, dual garbage-collection boundaries, or
   `cdecl` wrapping.
3. **Baked-In Reactive Tracking**: Specialized opcodes (`OP_GET_PROPERTY_SUBSCRIBE`)
   record binding dependencies in a single CPU instruction during execution.
4. **Single-Binary Zero-Dependency Distribution**: Compiles purely with Free Pascal
   and Pasbuild across Linux (native X11/XCB desktop integration), Windows, macOS,
   and embedded platforms.

---

### Migration Phases

#### Phase 1: 64-Bit NaN-Boxed Value Representation
Refactor `floria.js.value.pas` to replace the heavy union record with a 64-bit
NaN-boxed `TFloriaJSValue` (`QWord`).
- Doubles, 32-bit integers, booleans, `null`, `undefined`, and heap object
  pointers fit into a single 64-bit CPU register (`RAX`/`RDI`).
- Eliminates memory copying and reduces value stack footprint to 8 bytes per value.
- Introduce shape-based hidden classes (`TFloriaJSShape`) for fast property
  offset indexing.

#### Phase 2: Bytecode Compiler (`floria.js.compiler.pas`) — [~] Partially completed
Status: the compiler and `TFloriaJSBytecode` chunk container are implemented
and drive the VM. The compiler uses direct `is` dispatch rather than a visitor.
Local slots are used for parameters and compiler temporaries; user variables
still resolve through string-keyed environments. FTML parsing remains in
`floria.js.parser` rather than a separate `floria.ftml.parser.pas`.

Add an AST visitor pass that transforms the existing `TFloriaJSASTNode` trees into
flat bytecode chunks (`TFloriaJSBytecodeChunk`):
- Compact 32-bit or variable-length instructions (`OP_CONST`, `OP_LOAD_LOC`,
  `OP_STORE_LOC`, `OP_ADD`, `OP_CALL`, `OP_JUMP_IF_FALSE`, etc.).
- Local variable resolution at compile time into fixed stack offsets
  (`frame.locals[i]`), obsoleting runtime string-keyed environment lookups.
- Separate declarative FTML parsing into `floria.ftml.parser.pas` to decouple
  FTML syntax from the JS core compiler.

#### Phase 3: Stack-Based Bytecode Interpreter (`floria.js.vm.pas`) — [x] Completed
Implement a tight, register-friendly opcode interpreter loop in Pascal:
- Flat operand and call-frame array stacks.
- Replaces the recursive, stack-hungry tree walker in `floria.js.evaluator.pas`.
- Measured 3.0x–4.3x execution throughput improvement over the retired
  tree-walking evaluator in micro-benchmarks; further gains require the
  fast-path/JIT phases below.
- Pure reference-counted bytecode chunk container (`Retain`/`Release`) allowing
  functions and closures to outlive their declaring scripts.
- Full parity with language constructs: closures, default/rest parameters, object/array
  destructuring, async/await microtasks, try/catch/finally with early return/break unwinding.
- Full test suite parity: 157 of 157 unit tests pass (100%) under the `fjbBytecodeVM` backend.

#### Phase 4: Full Bytecode VM Migration & Evaluator Retirement — [x] Completed
Migrate the entire engine, reactive binding system, and signal dispatcher exclusively to the bytecode VM:
- Compile reactive FTML property bindings and signal handlers (`on<Signal>`) into bytecode snippets executed directly on `TFloriaJSVM`.
- Fully retire and remove the recursive tree-walking interpreter (`floria.js.evaluator.pas`).
- Replaced `FEvaluator` in `TFloriaJSContext` and `TFloriaFTMLBindingManager` with `FVM: TFloriaJSVM` and `FCompiler: TFloriaJSCompiler`.
- Proper frame and environment lifetime management (`AOwnsCallEnv`) ensuring caller-provided document and item environments remain valid across binding evaluations and signal invocations.
- Virtual `GetPropertyWithReceiver` dynamic dispatch implemented across `TFloriaFTMLItem`, `TFloriaFTMLAnchorLine`, and `TFloriaJSPromise`, enabling reactive property subscription tracking and prototype method resolution.
- All 157 unit tests in `./target/TestRunner` pass with 0 errors and 0 failures.

#### Phase 5: FTML Reactive Fast-Path & Inline Caching
Tailor the VM execution specifically for declarative UI property bindings:
- Decouple `TFloriaFTMLItem` from direct `TFloriaJSObject` inheritance; use native
  Pascal handles with inline caches.
- Compile each binding into a lightweight bytecode snippet (4–8 opcodes).
- Specialized opcodes (`OP_GET_PROP_SUBSCRIBE`) track property dependencies
  directly in the binding manager during execution without proxy overhead.
- Direct field offset lookups (Inline Caching) bypass dictionary lookups for item
  geometry (`x`, `y`, `width`, `height`).

#### Phase 6: Hot-Function JIT / Ahead-of-Time (AOT) Compilation
Provide native machine-code compilation for performance-critical execution paths:
- Ahead-of-Time (AOT) binding compiler translating pure arithmetic/layout
  bindings directly to native Pascal functions.
- Lightweight baseline JIT generating native machine code (x86_64, AArch64)
  for hot animation loops and frequently executed functions on platforms with
  writable/executable memory.

---

## Deliberately deferred

- `with` — accepted and ignored today; not worth implementing.
- `debugger` — accepted and ignored; that is acceptable.
- `import` / `export` — only if a module system becomes a requirement.
- Full ECMAScript conformance — the goal is a practical embedded runtime, not
  spec completeness.
