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
- Functions: declarations, function expressions, arrow functions (including
  lexical `this`), closures, recursion, `async`/`await`, `new` and `this`,
  default/rest parameters, and destructured parameters.
- Operators: arithmetic, comparison, logical, bitwise, shifts, `typeof`,
  `delete`, `in`, `instanceof`, `**`, `??`, optional chaining
  (`?.`, `?.[k]`, `?.()`), comma, and compound assignment including `**=` and
  `??=`.
- Literals: numbers (hex, octal, binary, exponent, numeric separators),
  strings with escapes, template interpolation, array/object spread, array
  holes, shorthand and computed properties, object methods, getters/setters,
  and regular expression literals.
- Standard library: `console`, `Math`, `Number`, `String`, `Boolean`,
  `parseInt`/`parseFloat`, `isNaN`/`isFinite`, the standard error constructors
  (including `SyntaxError` and `URIError`), `Object` utilities, Array and
  String prototypes, `Promise`, `globalThis`, RFC 8259-style `JSON`, `Map`,
  `Set`, `Date`, `Symbol`, `RegExp`, URI helpers, and host timers.
- Strict runtime checks: reading/writing properties of `null`/`undefined` and
  calling a non-function throw catchable `TypeError` objects.
- FTML: component instantiation, IDs, compiled reactive property bindings,
  dependency tracking, anchors, signals, and document lifecycle management.

Not implemented yet (see the [roadmap](roadmap.md)):

- `class`, generators/`yield`, tagged templates, `for await`, and
  `import`/`export`.
- `BigInt`, the `void` operator, and logical assignment (`&&=`, `||=`).
- Convenience methods such as `String.fromCharCode`, `Array.prototype.flat`,
  and `Object.is`.
- A JIT/AOT compiler, hidden classes/inline caches, and persistent bytecode
  caching. The VM is currently a pure interpreter.

The runtime also keeps some non-standard semantics, mostly in coercion,
numeric formatting, and the still-missing operators. See
[language support](language-support.md#semantic-deviations) for the complete
list.

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
