# Architecture

floriajs is a tree-walking JavaScript interpreter with a separate declarative
UI layer (FTML). This document explains how the pieces fit together and which
invariants each layer maintains.

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
                            TFloriaJSEvaluator
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
           TFloriaJSEnvironment                TFloriaJSHeap
           (lexical scopes)                    (values, objects,
                                               prototypes, jobs)
```

`TFloriaJSContext` wires the pipeline together: it owns a heap, a global
environment, an evaluator, and a console buffer. `TFloriaFTMLEngine` builds on
the same context to instantiate component trees and reactive bindings.

## Units

| Unit | Responsibility |
| :--- | :--- |
| `floria.js.types` | Version constants, result codes, `TFloriaJSType`, `TFloriaJSResult`. |
| `floria.js.lexer` | Single-pass UTF-8 tokenizer. |
| `floria.js.ast` | Expression/statement node classes, FTML component AST, visitor interface. |
| `floria.js.parser` | Pratt expression parser, recursive-descent statements, FTML parser. |
| `floria.js.value` | `TFloriaJSValue`, objects, arrays, functions, errors, promises, heap, coercion helpers. |
| `floria.js.env` | Lexical environments, bindings, parent lookup, delegated item scope. |
| `floria.js.evaluator` | Tree-walking interpreter, function calls, control flow, promise jobs. |
| `floria.js.arrays` | `Array` prototype methods and `Array` statics. |
| `floria.js.strings` | `String` prototype methods, applied to primitive strings. |
| `floria.js.objects` | `Object` constructor, static utilities, `Object.prototype` members. |
| `floria.js.json` | `JSON.stringify` / `JSON.parse` (RFC 8259 subset, indentation, circular detection). |
| `floria.js.stdlib` | Installs `console`, `Math`, `Number`, globals, errors, `globalThis`; calls the registration units above. |
| `floria.js.core` | Public `TFloriaJSEngine` and `TFloriaJSContext` façade. |
| `floria.ftml.types` | FTML item hierarchy, property storage, anchors, signals. |
| `floria.ftml.binding` | Dependency tracking and reactive binding evaluation. |
| `floria.ftml.engine` | FTML parsing/instantiation, ID registry, document lifecycle. |
| `floriajs` | Umbrella unit re-exporting the public API. |

## Lexer

- Input is a UTF-8 Pascal `string`. The lexer stores line and column positions
  for every token.
- Whitespace and both comment forms (`//…` and `/*…*/`) are skipped by
  `NextToken`; callers never see comment tokens in normal parsing.
- Keywords are recognised through a lookup table. All identifiers (including
  contextual keywords used as member names) carry their source text.
- Numeric literals support decimal, hex (`0x`), binary (`0b`), octal (`0o`),
  fraction/exponent forms, and numeric separators (`1_000_000`). Separators are
  stripped before conversion.
- String literals support the common escapes, `\xNN`, `\uNNNN`, and escaped
  quotes/backslashes.
- Template strings are scanned into `tkTemplateString` when they contain no
  interpolation, or into head/middle/tail tokens when they do. The parser
  lowers interpolation to string concatenation, so `` `v=${n + 1}` `` is
  evaluated as `"v=" + (n + 1)` with normal JavaScript `+` semantics.
- Tagged templates are not parsed as a distinct construct yet.
- Peeking is supported with `PeekToken`; the lexer remembers one look-ahead
  token.

## Parser

The parser combines:

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
  properties, computed keys, methods, and getters/setters.
- A separate recursive-descent entry point for FTML (`ParseFTMLComponent`).

Errors are accumulated in a `TStringList` instead of aborting immediately.
`HasErrors`, `GetErrorCount`, and `GetError` expose them. `ParseProgram` and
`ParseFTMLComponent` still return a (possibly partial) tree, so callers that
care about correctness must check `HasErrors`.

## AST and ownership

- Every node derives from `TFloriaJSASTNode` and carries line/column metadata.
- Nodes are owned by their parent and freed in the parent's destructor.
- Function bodies are the exception: `TFloriaJSFunctionExpr` and
  `TFloriaJSFunctionDecl` call `Release` instead of `Free` on their body.
  `TFloriaJSFunction` instances `Retain` the body, so closures can outlive the
  script that declared them. `TFloriaJSASTNode.Retain`/`Release` implement this
  small reference count.
- `IFloriaJSASTVisitor` exists for tooling; the interpreter itself dispatches
  with `is` checks in the evaluator.

## Evaluator

Execution is a recursive walk over the AST:

- **Statements** return the completion value of the last executed statement.
  `var`/`let`/`const` declarations (including destructuring), expression
  statements, blocks, classic and `for…in`/`for…of` loops, `switch`, `try`, and
  function declarations are supported.
- **Environments** form a parent chain. Block statements, loops, `switch`
  bodies, catch clauses, and function calls get a child environment. `for…in`
  and `for…of` create a fresh per-iteration environment so closures capture the
  current binding. A `while` or `do…while` body uses its enclosing environment
  unless the body itself is a block. Closures capture the environment chain;
  `MarkCaptured` keeps the chain alive.
- **Scopes are block-scoped for all declarations.** `var` is not hoisted to
  function scope; it behaves like a block-scoped binding in this runtime.
- **Control flow** uses Pascal exceptions: `EFloriaJSReturn`,
  `EFloriaJSBreak`, and `EFloriaJSContinue`. Labels are carried on the
  exception and matched by enclosing loops/labeled statements.
- **`this`** is resolved from the call environment. Method calls bind `this` to
  the receiver; plain calls pass `undefined`. Arrow functions do not rebind
  `this` and do not have a `prototype` property.
- **Calls** evaluate the callee, evaluate arguments left to right, and invoke
  either a native callback or a user function. User calls create a fresh
  environment, bind parameters (including defaults, rest arrays, and
  destructuring patterns) plus `arguments`, and execute the body.
- **Construction** (`new`) creates an object with the constructor's
  `prototype`, calls the constructor with `this` set to the new object, and
  returns the object unless the constructor returns an object explicitly.
- **Promises** are scheduled as jobs on the heap. `ExecuteProgram` drains
  pending microtasks before returning, and `await` drains them while settling.
- **Safe points**: at the start of a program run, the evaluator reclaims
  orphaned environments and collects unreachable objects.

## Value model

`TFloriaJSValue` is a record with a type tag and four payload fields:

```pascal
TFloriaJSValue = record
  Kind: TFloriaJSType;
  NumVal: Double;
  BoolVal: Boolean;
  StrVal: string;
  ObjVal: TFloriaJSObject;
end;
```

- `fjstUndefined`, `fjstNull`, `fjstBoolean`, `fjstNumber`, `fjstString` are
  primitive.
- `fjstObject`, `fjstArray`, `fjstFunction`, `fjstError` (and promises) point
  at heap-allocated objects through `ObjVal`.
- The payload fields that do not apply to a kind are initialised to zero/nil by
  the `JSMake*` factories. Always construct values through those factories or
  copy an existing value; do not build a record field-by-field.
- Object properties may be data or accessors. `DefineGetter`/`DefineSetter`
  store accessor functions, and `GetProperty`/`SetProperty` invoke them with
  the object as `this`. Object literals with `get`/`set` use this mechanism.
- Coercion (`ToBoolean`, `ToNumber`, `ToString`) follows JavaScript closely.
  Numbers are IEEE doubles; integers print without a decimal part. See
  [Values and heap](api/values.md) for the exact rules.

## Memory model

The runtime uses **reference counting plus explicit safe-point reclamation**,
not a tracing collector.

- `TFloriaJSObject` has `Retain`/`Release`. Containers that store a value (heap
  property tables, array elements, environment bindings, promise results, FTML
  properties) retain what they take and release what they replace.
- The heap tracks every object it creates, plus every environment registered
  with `TrackEnvironment`.
- `TFloriaJSHeap.Collect` frees tracked objects whose reference count has
  dropped to zero, that are heap-owned, and that are not pinned.
- Host-held values are **pinned** (`Pin`/`Unpin`). `EvaluateValue` and `Call`
  pin object results; `ReleaseValue` unpins them.
- Shared prototypes (`Object`, `Array`, `String`) are pinned by the heap so
  they live as long as the heap, even when no value currently refers to them.
- Functions expose `prototype` lazily. That prototype deliberately has no
  `constructor` property: the back-reference would form a cycle that reference
  counting cannot break.
- Closures mark their environment chain as captured. When the declaring scope
  exits, the environment is *detached* rather than freed; the evaluator
  reclaims detached environments that no live closure reaches at the next safe
  point.
- `TFloriaJSHeap.Clear` frees all environments first, then all objects, and
  resets the cached prototype pointers. `TFloriaJSContext.Reset` uses it.

Because there is no cycle collector, host code should avoid creating cycles
that cross the host–runtime boundary.

## Standard library layering

`FloriaJSRegisterStdLib(AEnv, AHeap, ALogOutput)` is the single registration
entry point used by `TFloriaJSContext`. It:

1. Installs shared prototypes and globals through `FloriaJSRegisterArray`,
   `FloriaJSRegisterString`, `FloriaJSRegisterObjects`, and
   `FloriaJSRegisterJSON`.
2. Creates `console`, `Math`, `Promise`, error constructors, `Number`,
   `String`, `Boolean`, `parseInt`, `parseFloat`, `isNaN`, `isFinite`, and
   `globalThis`.

Heap-side helpers (array/string methods) call back into JavaScript through
`TFloriaJSHeap.SetFunctionInvoker`, which the evaluator wires to
`CallFunction`. This keeps `floria.js.arrays` and `floria.js.strings` free of a
dependency on `floria.js.evaluator`.

The console output sink is a unit-level global, so it points at the context
whose standard library was installed last. This is why multi-context console
capture should be treated as “last registered context wins”.

## FTML runtime

`TFloriaFTMLEngine` adds a declarative layer on top of the JavaScript runtime:

1. `TFloriaJSParser.ParseFTMLComponent` produces a component AST.
2. `InstantiateItem` creates a `TFloriaFTMLItem` subclass per component, builds
   the parent/child hierarchy, creates a scoped environment per item (with the
   item as its delegate object), registers IDs, and binds component functions
   and signal handlers.
3. `SetupItemBindings` evaluates literal properties once and creates reactive
   bindings for expressions.
4. `TFloriaFTMLBindingManager` records property reads during evaluation and
   re-evaluates dependants when a property changes.
5. Anchors are resolved between items; `Column`/`Row` provide simple stacking
   relayout, while `FlexBox`/`Grid` expose layout properties for the host.
   Rendering and widget creation are host responsibilities.

Document reloads are carefully ordered: bindings are destroyed while their AST
and target items are still valid, IDs are withdrawn from the global scope, and
documents referenced by escaping runtime closures are kept alive until those
closures are gone. See the [FTML guide](ftml.md) for the user-facing view.

## Design constraints

- **Portable Object Pascal.** The core avoids platform-specific units.
- **Additive evolution.** Public APIs should be extended, not changed
  incompatibly.
- **Predictable lifetime.** Every ownership transfer is explicit; the test
  suite contains leak and reclamation checks.
- **Practical subset, not full conformance.** Unsupported syntax should fail
  loudly at parse time where possible. Silent gaps are tracked in the
  [roadmap](roadmap.md).
