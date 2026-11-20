# floriajs Documentation

**floriajs** is an embeddable JavaScript runtime and declarative UI (FTML)
engine written in Object Pascal. It is designed for the Floria Toolkit, but the
JavaScript core has no desktop dependency and can be embedded in any Free Pascal
or Delphi-compatible application.

This directory is the reference documentation. The short project overview and
the quick-start example live in the top-level [README](../README.md).

## Start here

| Document | Read it when you want to… |
| :--- | :--- |
| [Getting started](getting-started.md) | Build the library, run a script, call Pascal from JavaScript, and embed the runtime in an application. |
| [Language support](language-support.md) | See which JavaScript syntax and standard-library APIs are implemented, and which ones are not. |
| [Architecture](architecture.md) | Understand the lexer → parser → compiler → bytecode VM pipeline, the value model, and the memory model. |
| [Bytecode VM](bytecode-vm.md) | Understand the opcode set, compiler output, stack machine, call frames, and how to extend it. |
| [FTML guide](ftml.md) | Write declarative component markup with reactive property bindings, anchors, and signals. |
| [Development guide](development.md) | Contribute code, run the test suite and gap scan, and add new built-ins safely. |
| [Test262 support](test262.md) | Understand the diagnostic Test262 policy, pinned corpus, result vocabulary, async execution, and current limitations. |
| [Test262 host](test262-host.md) | Build the single-scenario host and understand its CLI, JSON results, exit statuses, and fixture checks. |
| [Test262 planner](test262-plan.md) | Parse metadata safely and prepare supported execution scenarios without assigning verdicts. |
| [Test262 runner](test262-runner.md) | Execute supported synchronous Test262 scenarios, apply positive and negative verdicts, write reports, and compare reviewed baselines. |
| [Roadmap](roadmap.md) | See the prioritised list of missing features and current delivery slices. |

## API reference

| Document | Covers |
| :--- | :--- |
| [Engine and context](api/engine.md) | `TFloriaJSEngine`, `TFloriaJSContext`, results, contexts, console capture, lifetime. |
| [Values and heap](api/values.md) | `TFloriaJSValue`, objects, arrays, functions, errors, promises, the heap, coercion helpers, and ECMAScript-exact number formatting/parsing. |
| [Language pipeline](api/language-pipeline.md) | Lexer, parser, AST, bytecode compiler, VM, and standard-library registration. |
| [FTML API](api/ftml.md) | `TFloriaFTMLEngine`, item classes, bindings, signals, and host integration. |

## Status at a glance

floriajs is at **0.0.1-SNAPSHOT**. It implements a practical, embedded subset of
JavaScript rather than full ECMAScript conformance.

Implemented and covered by the test suite:

- **Execution engine**: AST → bytecode compiler, stack-based VM, local slots,
  jump-based control flow, exception handler stack, closures, async functions,
  and a disassembler.
- Core statements: declarations (including destructuring), blocks, `if`,
  classic `for`, `for…in`, `for…of`, `while`, `do…while`, `switch`,
  `try`/`catch`/`finally`, `throw`, labeled `break`/`continue`.
- Classes: declarations and expressions, `constructor`, methods, `get`/`set`,
  `static`, `extends`, and `super`. Methods are non-enumerable.
- Generators: `function*`, `yield`, `yield*`, and the generator object
  (`next`/`return`/`Symbol.iterator`).
- Async iteration: `for await` over async iterators and sync iterables, and
  `async function*` generators with `yield`, `await`, and `yield*`.
- Modules: real ECMAScript module records with `import`/`export`, live
  bindings, `import.meta`, dynamic `import()`, star and namespace re-exports,
  import attributes, and cycle-safe evaluation.
- Binary and concurrency data: `ArrayBuffer`, `SharedArrayBuffer`, `DataView`,
  BigInt typed arrays, and core `Atomics`; the diagnostic host also provides
  cooperative `$262.agent` agents.
- Reflection: `Proxy` and `Reflect` traps, genuinely weak `WeakMap`/`WeakSet`
  whose dead entries are pruned by the collector, and real `Symbol`-keyed
  properties.
- BigInt: `123n` literals in decimal and every radix, arbitrary-precision
  arithmetic and comparison, and `BigInt()` conversion.
- Function metadata: `fn.length`, `fn.name` (including inference for anonymous
  functions assigned to properties), `fn.toString()` with the original source
  text, and the `Function(...)` constructor.
- Library coverage: `Object.is`/`getOwnPropertyNames`/`defineProperty`/
  `freeze`/`seal`/`fromEntries`, `Array.flat`/`flatMap`/`fill`/`copyWithin`/
  `at`/`keys`/`entries`, `String.fromCharCode`/`fromCodePoint`/`normalize`/
  `localeCompare`, Date component setters, and symbol-keyed properties.
- Coercion: `join`, `parseInt`/`parseFloat`, the URI helpers, and `Error`
  messages all convert through ToString; bitwise and shift compound
  assignments (`&=`, `|=`, `^=`, `<<=`, `>>=`, `>>>=`) are supported.
- Modern built-ins: `Object.hasOwn`/`groupBy`/`getOwnPropertyDescriptors`/
  `defineProperties`/`getOwnPropertySymbols`, `Array.findLast`/`toSorted`/
  `toReversed`/`toSpliced`/`with`, `String.at`/`matchAll`,
  `Promise.allSettled`/`any`, `Number.isSafeInteger`, the full `Math`
  hyperbolic set, `AggregateError`, `Map.groupBy`, `queueMicrotask`, and
  `structuredClone`.
- Functions: declarations, function expressions, arrow functions (including
  lexical `this`), closures, recursion, `async`/`await`, `new` and `this`,
  default/rest parameters, and destructured parameters.
- Operators: arithmetic, comparison, logical, bitwise, shifts, `typeof`,
  `delete`, `void`, `in`, `instanceof`, `**`, `??`, optional chaining
  (`?.`, `?.[k]`, `?.()`), comma, and compound assignment including `**=`,
  `??=`, and the short-circuiting `&&=`/`||=`.
- Literals: numbers (hex, octal, binary, exponent, numeric separators),
  strings with escapes, template interpolation and tagged templates,
  array/object spread, array holes, shorthand and computed properties, object
  methods, getters/setters, and regular expression literals.
- Standard library: `console`, `Math`, `Number`, `String`, `Boolean`,
  `parseInt`/`parseFloat`, `isNaN`/`isFinite`, the standard error constructors
  (including `SyntaxError` and `URIError`), `Object` utilities, Array and
  String prototypes, `Promise`, `globalThis`, RFC 8259-style `JSON`, `Map`,
  `Set`, `Date`, `Symbol`, `RegExp`, URI helpers, and host timers.
- Strict runtime checks: reading/writing properties of `null`/`undefined` and
  calling a non-function throw catchable `TypeError` objects.
- FTML: component instantiation, IDs, compiled reactive property bindings,
  dependency tracking, anchors, signals, and document lifecycle management.

Not implemented yet (see [language support](language-support.md) for details):

- `Intl` and `alert`.
- A machine-code JIT, full hidden-class transitions, and persistent bytecode
  caching. AOT binding snippets and per-site property caches already exist.

The runtime also keeps some non-standard semantics. The
[language support](language-support.md#semantic-deviations) page groups them by
cause: deliberate embedded trade-offs, missing features with the roadmap task
that covers each one, and known gaps. Number formatting and parsing are
ECMAScript-exact, so they are not among them.

## Documentation conventions

- Code blocks are Free Pascal unless they show JavaScript.
- API signatures are quoted exactly as declared in the source.
- “Current behaviour” describes the implementation on `main`; “not
  implemented” means the syntax is rejected, ignored, or lacks the expected
  runtime behaviour.
- All paths are relative to the repository root.

## Keeping the docs accurate

When a language or API change lands:

1. Update the relevant reference page and, if behaviour is user-visible, the
   [language support](language-support.md) matrix.
2. Add or update the test in `src/test/pascal/TestRunner.pas`.
3. Add a probe to the gap scan in `scratch/` when the feature is observable
   from JavaScript.
4. Tick or amend the corresponding item in the [roadmap](roadmap.md).
