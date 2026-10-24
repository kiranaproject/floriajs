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
| [Architecture](architecture.md) | Understand the lexer → parser → AST → evaluator pipeline, the value model, and the memory model. |
| [FTML guide](ftml.md) | Write declarative component markup with reactive property bindings, anchors, and signals. |
| [Development guide](development.md) | Contribute code, run the test suite and gap scan, and add new built-ins safely. |
| [Roadmap](roadmap.md) | See the prioritised list of missing features and current delivery slices. |

## API reference

| Document | Covers |
| :--- | :--- |
| [Engine and context](api/engine.md) | `TFloriaJSEngine`, `TFloriaJSContext`, results, contexts, console capture, lifetime. |
| [Values and heap](api/values.md) | `TFloriaJSValue`, objects, arrays, functions, errors, promises, the heap, and coercion helpers. |
| [Language pipeline](api/language-pipeline.md) | Lexer, parser, AST, evaluator, and the standard-library registration entry points. |
| [FTML API](api/ftml.md) | `TFloriaFTMLEngine`, item classes, bindings, signals, and host integration. |

## Status at a glance

floriajs is at **0.0.1-SNAPSHOT**. It implements a practical, embedded subset of
JavaScript rather than full ECMAScript conformance.

Implemented and covered by the test suite:

- Core statements: declarations (including destructuring), blocks, `if`,
  classic `for`, `for…in`, `for…of`, `while`, `do…while`, `switch`,
  `try`/`catch`/`finally`, `throw`, labeled `break`/`continue`.
- Functions: declarations, function expressions, arrow functions (including
  lexical `this`), closures, recursion, `async`/`await`, `new` and `this`,
  default/rest parameters, and destructured parameters.
- Operators: arithmetic, comparison, logical, bitwise, shifts, `typeof`,
  `delete`, `in`, `instanceof`, `**`, `??`, optional chaining
  (`?.`, `?.[k]`, `?.()`), comma, and compound assignment including `**=` and
  `??=`.
- Literals: numbers (hex, octal, binary, exponent, numeric separators),
  strings with escapes, template interpolation, array/object spread, array
  holes, shorthand and computed properties, object methods, and
  getters/setters.
- Standard library: `console`, `Math`, `Number`, `String`, `Boolean`,
  `parseInt`/`parseFloat`, `isNaN`/`isFinite`, `Error`/`TypeError`/
  `RangeError`/`ReferenceError`, `Object` utilities, Array and String
  prototypes, `Promise`, `globalThis`, and RFC 8259-style `JSON`.
- FTML: component instantiation, IDs, property bindings, dependency tracking,
  anchors, signals, and document lifecycle management.

Not implemented yet (see the [roadmap](roadmap.md)):

- `Map`, `Set`, `Date`, `Symbol`, `RegExp`, generators/`yield`, real `class`
  syntax, tagged templates, and `for await`.
- The `void` operator and logical assignment (`&&=`, `||=`).
- Runtime `TypeError`s for calling a non-function or accessing a property of
  `null`/`undefined` (these currently return `undefined`).
- URI helpers, timers, and other host-provided globals.

The runtime also keeps some non-standard semantics: `const` reassignment is
allowed, `var` is block-scoped, and some coercion corners differ from
ECMAScript. See [language support](language-support.md#semantic-deviations)
for the complete list.

## Documentation conventions

- Code blocks are Free Pascal unless they show JavaScript.
- API signatures are quoted exactly as declared in the source.
- “Current behaviour” describes the implementation on `main`; “not
  implemented” means the parser rejects the syntax or the runtime returns
  `undefined`.
- All paths are relative to the repository root.

## Keeping the docs accurate

When a language or API change lands:

1. Update the relevant reference page and, if behaviour is user-visible, the
   [language support](language-support.md) matrix.
2. Add or update the test in `src/test/pascal/TestRunner.pas`.
3. Add a probe to the gap scan in `scratch/` when the feature is observable
   from JavaScript.
4. Tick or amend the corresponding item in the [roadmap](roadmap.md).
