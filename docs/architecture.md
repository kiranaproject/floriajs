# Architecture

floriajs is a **bytecode virtual machine** for JavaScript with a separate
declarative UI layer (FTML). The lexer and parser still produce an AST, but the
AST is compiled to flat bytecode before execution; the old recursive
tree-walking evaluator has been retired.

This page describes the pipeline, the units, the execution model, and the
memory model. The instruction set and VM internals are covered in more detail
in [Bytecode VM](bytecode-vm.md).

## Pipeline

```text
JavaScript source / FTML source
            │
            ▼
   TFloriaJSLexer  ── tokens ──►  TFloriaJSParser
                                      │
                                      ▼
                                 AST (floria.js.ast)
                                      │
                                      ▼
                            TFloriaJSCompiler
                                      │
                                      ▼
                         TFloriaJSBytecode chunks
                    (opcodes, constants, locals, args,
                     sub-functions, source lines)
                                      │
                                      ▼
                                TFloriaJSVM
                    (value stack, call frames, try handlers)
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
           TFloriaJSEnvironment                TFloriaJSHeap
           (lexical scopes)                    (values, objects,
                                               prototypes, jobs)
```

`TFloriaJSContext` wires the pipeline together: it owns a heap, a global
environment, a compiler, a VM, and a console buffer. `TFloriaFTMLEngine` builds
on the same context to instantiate component trees, compile bindings, and
dispatch signals.

## Units

### Core language

| Unit | Responsibility |
| :--- | :--- |
| `floria.js.types` | Version constants, result codes, `TFloriaJSType`, `TFloriaJSResult`. |
| `floria.js.lexer` | Single-pass UTF-8 tokenizer, including regex literals. |
| `floria.js.ast` | Expression/statement node classes, FTML component AST, visitor interface. |
| `floria.js.parser` | Pratt expression parser, recursive-descent statements, FTML parser. |
| `floria.js.bytecode` | Opcode set, instruction record, constant pool, bytecode chunks, disassembler. |
| `floria.js.compiler` | AST-to-bytecode compiler. |
| `floria.js.vm` | Stack-based bytecode interpreter, call frames, exception handlers. |
| `floria.js.value` | `TFloriaJSValue`, objects, arrays, functions, errors, promises, heap, coercion helpers. |
| `floria.js.number` | ECMAScript-exact double-to-string and string-to-double conversion on exact decimal digit strings. |
| `floria.js.env` | Lexical environments, bindings, parent lookup, delegated item scope. |

### Standard library

| Unit | Responsibility |
| :--- | :--- |
| `floria.js.arrays` | `Array` prototype methods and `Array` statics. |
| `floria.js.strings` | `String` prototype methods and regex-aware string operations. |
| `floria.js.objects` | `Object` constructor, static utilities, `Object.prototype` members. |
| `floria.js.json` | `JSON.stringify` / `JSON.parse`. |
| `floria.js.collections` | `Map` and `Set`. |
| `floria.js.date` | `Date` constructor, parsing, accessors, and ISO formatting. |
| `floria.js.symbol` | `Symbol` primitive, registry, and well-known symbols. |
| `floria.js.regexp` | `RegExp` object and pattern matching. |
| `floria.js.uri` | URI encoding/decoding and `URIError`. |
| `floria.js.timers` | `setTimeout`/`setInterval` host timers. |
| `floria.js.stdlib` | Installs globals and the units above; `console`, `Math`, `Promise`, errors, `globalThis`. |
| `floria.js.core` | Public `TFloriaJSEngine` and `TFloriaJSContext` façade. |

### FTML

| Unit | Responsibility |
| :--- | :--- |
| `floria.ftml.types` | Item hierarchy, property storage, anchors, signals, anchor-line objects. |
| `floria.ftml.binding` | Compiled reactive bindings and dependency tracking. |
| `floria.ftml.engine` | FTML parsing/instantiation, ID registry, document lifecycle. |
| `floriajs` | Umbrella unit re-exporting the public API. |

## Lexer

- Input is a UTF-8 Pascal `string`; every token carries line/column positions.
- Whitespace and both comment forms (`//…` and `/*…*/`) are skipped by
  `NextToken`; callers never see comment tokens in normal parsing.
- Keywords are recognised through a lookup table. Identifiers used as member
  names carry their source text.
- Numeric literals support decimal, hex (`0x`), binary (`0b`), octal (`0o`),
  fraction/exponent forms, and numeric separators (`1_000_000`). Separators
  are stripped before conversion.
- String literals support the common escapes, `\xNN`, `\uNNNN`, and escaped
  quotes/backslashes.
- Template strings are scanned into a single token when they have no
  interpolation, or into head/middle/tail tokens when they do. The parser
  lowers interpolation to string concatenation.
- Regular expression literals (`/pattern/flags`) are scanned as `tkRegExp`
  when `/` appears in expression position; otherwise `/` is division.
- Tagged templates are not parsed as a distinct construct yet.
- Peeking is supported with `PeekToken`; the lexer remembers one look-ahead
  token.

## Parser

- **Pratt parsing** for expressions, with precedence levels defined in
  `floria.js.parser`:

  | Level | Operators |
  | :--- | :--- |
  | 1 | `,` |
  | 2 | `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `**=`, `??=` |
  | 3 | `? :` |
  | 4 | `??` |
  | 5 | `\|\|` |
  | 6 | `&&` |
  | 7–9 | `\|`, `^`, `&` |
  | 10 | `==`, `!=`, `===`, `!==` |
  | 11 | `<`, `<=`, `>`, `>=`, `in`, `instanceof` |
  | 12 | `<<`, `>>`, `>>>` |
  | 13 | `+`, `-` |
  | 14 | `*`, `/`, `%` |
  | 15 | `**` (right-associative) |
  | 16 | unary `!`, `~`, `+`, `-`, `typeof`, `delete`, `await`, prefix `++`/`--` |
  | 17 | postfix `++`, `--` |
  | 18 | call, member access, `?.` |

- **Recursive descent** for statements and declarations: blocks, `if`,
  classic `for`, `for…in`, `for…of`, `while`, `do…while`, `switch`, `try`,
  declarations (including destructuring patterns), functions (default, rest,
  and destructured parameters), and expression statements.
- **Literal parsing** supports array/object spread, holes, shorthand
  properties, computed keys, methods, getters/setters, and regex literals.
- A separate recursive-descent entry point for FTML (`ParseFTMLComponent`).

Errors are accumulated in a `TStringList` instead of aborting immediately.
`HasErrors`, `GetErrorCount`, and `GetError` expose them. `ParseProgram` and
`ParseFTMLComponent` still return a (possibly partial) tree, so callers that
care about correctness must check `HasErrors`.

## AST and ownership

- Every node derives from `TFloriaJSASTNode` and carries line/column metadata.
- Nodes are owned by their parent and freed in the parent's destructor.
- Function bodies are shared with closures through `Retain`/`Release` on
  `TFloriaJSASTNode`.
- `IFloriaJSASTVisitor` exists for tooling. The compiler does not use the
  visitor interface; it dispatches with `is` checks.

## Compiler

`TFloriaJSCompiler` walks the AST and emits `TFloriaJSBytecode`:

```pascal
function CompileProgram(AProgram: TFloriaJSProgram): TFloriaJSBytecode;
function CompileExpression(AExpr: TFloriaJSExprNode): TFloriaJSBytecode;
function CompileFunctionBody(const AName: string; AParams: TStringList;
  ABody: TFloriaJSStmtNode; AIsAsync: Boolean = False;
  AIsArrow: Boolean = False): TFloriaJSBytecode;
```

- **Expressions** compile to postfix-style stack operations (`OP_CONST`,
  `OP_ADD`, `OP_GET_PROP_NAMED`, `OP_CALL`, …).
- **Declarations** emit `DEFINE_ENV` into the current environment. Blocks with
  `let`/`const` (or function declarations) emit `PUSH_ENV`/`POP_ENV`; plain
  blocks with only `var`-style bindings do not create an extra scope, so `var`
  binds in the enclosing function/top-level environment. There is no hoisting.
- **Classic `for` declarations** of `let`/`const` create an outer loop
  environment plus a fresh per-iteration environment for the body, so closures
  capture per-iteration values. `for…in`/`for…of` also create per-iteration
  environments.
- **Control flow** uses jumps. Loops and conditionals patch forward jumps after
  compiling their bodies. `break`/`continue` jumps are collected per loop
  context and patched to the loop's exit/continue targets, including labels.
- **Closures** compile nested functions into sub-function chunks. `OP_CLOSURE`
  creates a bytecode function object capturing the current environment.
- **Exceptions** use `PUSH_TRY`/`POP_TRY` and a handler stack in the VM;
  `catch`/`finally` targets and stack depths are recorded by the compiler.
- **Top-level completion value** is stored in a hidden `$result` local so a
  script's completion value matches the last top-level expression.
- **Destructuring, default/rest parameters, spread calls, object/array spread,
  getters/setters, `for…in`/`for…of`, and optional chaining** are lowered into
  the corresponding generic opcodes.

The compiler uses VM local slots for parameters and compiler temporaries. User
variables are still resolved through environments by name; this keeps closure,
block-scope, and FTML delegate-object semantics unchanged while removing AST
dispatch from the hot path.

## Bytecode

A chunk (`TFloriaJSBytecode`) contains code, constants, local/argument names,
sub-functions, `IsArrow`/`IsAsync` flags, and a reference count.

```pascal
TFloriaJSInstruction = packed record
  Op: TFloriaJSOpcode;
  Imm: Int32;    // constant index, local slot, jump target, or argument count
  Line: Int32;   // source line
end;
```

The opcode groups are stack manipulation, constants, locals, globals and
environments, objects, arrays, arithmetic, comparison, unary/logic, jumps,
calls/construction, exceptions, iteration, and VM control. See
[Bytecode VM](bytecode-vm.md#instruction-set) for the list.

`TFloriaJSBytecode.Disassemble` renders a readable dump for debugging.

## Virtual machine

`TFloriaJSVM` is a stack machine with explicit call frames:

- **Value stack** for operands and temporaries.
- **Call frames** storing bytecode, instruction pointer, base stack pointer,
  `this`, environment, constructor state, and environment ownership.
- **Try-handler stack** storing catch targets, frame/stack depth, and the
  environment to restore.
- **Environments** are created per call and per block scope as needed; the VM
  frees uncaptured environments when a frame or scope is popped.
- **Calls** bind arguments, `this`, and `arguments` in a new environment,
  reserve local slots, and execute the nested chunk. Native functions are
  invoked directly.
- **Construction** (`new`) creates an object with the constructor's
  `prototype`, runs the constructor with the new object as `this`, and uses an
  explicitly returned object when there is one.
- **Async functions** run the chunk and fulfill/reject a promise; `await`
  drains the promise job queue when the awaited value is a promise.
- **Errors** are routed through `HandleThrow` to the nearest handler. An
  uncaught value leaves the VM as `EFloriaJSThrow`.
- **Call depth** defaults to 512 and raises a `RangeError` when exceeded.

Execution entry points:

```pascal
function Execute(ABytecode: TFloriaJSBytecode;
  AEnv: TFloriaJSEnvironment = nil): TFloriaJSValue;
function CallFunction(const AFuncVal: TFloriaJSValue;
  const AArgs: array of TFloriaJSValue): TFloriaJSValue;
function ConstructObject(const AFuncVal: TFloriaJSValue;
  const AArgs: array of TFloriaJSValue): TFloriaJSValue;
```

## Value model

`TFloriaJSValue` is a tagged record:

```pascal
TFloriaJSValue = record
  Kind: TFloriaJSType;
  NumVal: Double;
  BoolVal: Boolean;
  StrVal: string;
  ObjVal: TFloriaJSObject;
end;
```

- Primitive kinds: `undefined`, `null`, boolean, number, string, and symbol.
- Heap kinds: object, array, function, error (and promises).
- `Symbol` is a primitive kind (`fjstSymbol`) carrying its description and a
  unique id in the runtime.
- The `JSMake*` factories initialise all fields; do not build values field by
  field.
- Object properties can be data or accessors. `GetPropertyWithReceiver`
  forwards the original receiver through prototype lookups so getters and
  methods see the right `this`.
- Coercion (`ToBoolean`, `ToNumber`, `ToString`) is documented in
  [Values and heap](api/values.md).

## Memory model

The runtime uses **reference counting plus explicit safe-point reclamation**,
not a tracing collector.

- `TFloriaJSObject` has `Retain`/`Release`; containers retain what they store
  and release what they replace.
- Bytecode chunks are reference-counted too. Functions retain their chunk, and
  FTML bindings retain their compiled expression.
- The heap tracks objects and registered environments.
- `TFloriaJSHeap.ReclaimOrphanedEnvironments` removes detached environments no
  longer reachable from a live closure. `Collect` removes heap-owned objects
  with no references that are not pinned.
- Host-held values are **pinned** (`Pin`/`Unpin`). `EvaluateValue` and `Call`
  pin object results; `ReleaseValue` unpins them.
- Shared prototypes (Object, Array, String, errors, and the built-in
  constructors' prototypes) are pinned by the heap.
- Functions expose `prototype` lazily. That prototype deliberately has no
  `constructor` back-reference, to avoid a reference cycle.
- The VM frees uncaptured call/block environments eagerly when frames/scopes
  pop, and detaches captured environments for later reclamation.
- `TFloriaJSHeap.Clear` frees all environments, then all objects, and resets
  cached prototypes. `TFloriaJSContext.Reset` uses it.

There is no cycle collector, so host code should avoid cycles that cross the
host–runtime boundary. Bytecode chunks and functions are retained/released
explicitly; a chunk shared by a function, binding, or signal cache must not be
freed by the producer.

## Standard library layering

`FloriaJSRegisterStdLib(AEnv, AHeap, ALogOutput)` is the single registration
entry point used by `TFloriaJSContext`. It:

1. Installs shared prototypes and globals through the array, string, object,
   and JSON registrars.
2. Creates `console`, `Math`, `Promise`, error constructors, `Number`,
   `String`, `Boolean`, `parseInt`, `parseFloat`, `isNaN`, and `isFinite`.
3. Calls the advanced registrars: `Symbol`, `Date`, `URI`, `Map`/`Set`,
   timers, and `RegExp`.
4. Builds `globalThis`, including the advanced globals.

Heap-side helpers (array/string methods) call back into JavaScript through
`TFloriaJSHeap.SetFunctionInvoker`, which the VM wires to `CallFunction`.
This keeps the built-in units independent of the VM unit.

The console sink is a unit-level global, so it points at the context whose
standard library was installed last. Multi-context console capture is
therefore “last registered context wins”.

**Timers need a host pump.** `setTimeout`/`setInterval` register callbacks in
a process-wide timer queue. The host must call `FloriaJSProcessTimers(Heap)`
periodically (and provide the event loop that decides when to call it); the VM
does not run a wall-clock timer loop.

## FTML runtime

`TFloriaFTMLEngine` adds a declarative layer on top of the VM:

1. `TFloriaJSParser.ParseFTMLComponent` produces a component AST.
2. `InstantiateItem` creates a `TFloriaFTMLItem` subclass per component, builds
   the hierarchy, creates a scoped environment per item (with the item as its
   delegate object), registers IDs, and binds functions and signal handlers.
3. `SetupItemBindings` evaluates literal properties once and creates reactive
   bindings for expressions.
4. Each binding compiles its expression once to a `TFloriaJSBytecode` chunk via
   the context compiler. On evaluation, the binding manager runs the chunk on
   the context VM with the item environment.
5. Dependency reads are recorded through the item's `GetPropertyWithReceiver`,
   so the binding manager knows which properties to re-evaluate when they
   change.
6. Signal handlers are compiled lazily to bytecode on first dispatch and cached
   in the signal entry.
7. Anchors are resolved between items; `Column`/`Row` provide simple stacking
   relayout. Rendering and widget creation are host responsibilities.

Document reloads are carefully ordered: bindings are destroyed while their AST,
bytecode, and target items are still valid, IDs are withdrawn from the global
scope, and documents referenced by escaping runtime closures are kept alive
until those closures are gone. See the [FTML guide](ftml.md) for the
user-facing view and [FTML API](api/ftml.md) for the types.

## Engine, backend, and caching

`TFloriaJSContext` exposes the VM, compiler, and a compatibility backend flag:

```pascal
property VM: TFloriaJSVM read FVM;
property Compiler: TFloriaJSCompiler read FCompiler;
property Backend: TFloriaJSExecutionBackend read FBackend write FBackend;
```

`TFloriaJSExecutionBackend` still has `fjbInterpreter` and `fjbBytecodeVM`, but
the tree-walking evaluator was removed. Both values currently execute through
the bytecode VM; `fjbInterpreter` is retained for source compatibility.

`Evaluate` parses and compiles the source on each call. There is no automatic
bytecode cache. Hosts that execute the same script repeatedly should compile it
once and call `VM.Execute` directly.

## Performance

The VM removes recursive AST dispatch, uses a flat instruction loop and local
slots, compiles control flow to jumps, and caches compiled FTML bindings and
signals. The roadmap records roughly **3–4×** throughput improvement over the
retired tree walker.

It remains a pure interpreter: user variables still resolve by name through
environments, object properties use linear tables, function calls allocate a
call environment and `arguments`, and each instruction is wrapped in a
`try`/`except` for throw routing. Hidden classes, inline caches, persistent
bytecode caching, and JIT/AOT compilation are future roadmap phases, not
current features.

## Design constraints

- **Portable Object Pascal.** The core avoids platform-specific units.
- **Additive evolution.** Public APIs should be extended, not changed
  incompatibly.
- **Predictable lifetime.** Ownership is explicit; bytecode chunks,
  environments, and objects are reference-counted, and the test suite contains
  leak/reclamation checks.
- **Practical subset, not full conformance.** Unsupported syntax should fail
  loudly where possible. Silent gaps are tracked in the [roadmap](roadmap.md).
