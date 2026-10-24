# Language Support

floriajs implements a practical subset of JavaScript aimed at embedded scripts
and declarative UI handlers. It is not a conforming ECMAScript implementation.
This page describes what works today, what does not, and where the semantics
differ from a browser engine.

The status was verified against the automated test suite and the gap-scan
probes in `scratch/`. See [development](development.md#gap-scan) for how to run
them.

## Statements and declarations

| Feature | Status | Notes |
| :--- | :--- | :--- |
| `var`, `let`, `const` | Yes | All are block-scoped. `var` is not function-scoped and there is no hoisting. `const` reassignment is **not** rejected. |
| Destructuring declarations | Yes | `var { a, b: c = 1, ...rest } = obj;`, `var [a, , b = 2, ...rest] = arr;` |
| Blocks | Yes | Create a child scope. |
| `if` / `else` | Yes | |
| `while`, `do…while` | Yes | `break` / `continue`, including labels. |
| Classic `for` | Yes | `var`/`let`/`const` initializers, multiple declarators, optional clauses. |
| `for…of` | Yes | Arrays and strings. Target must be a plain identifier. |
| `for…in` | Yes | Own and inherited keys of objects, skipping `Object.prototype`. On an array it enumerates prototype method names rather than indices; use `for…of` for arrays. Target must be a plain identifier. |
| `switch` / `case` / `default` | Yes | Strict equality, fall-through, `break`. |
| `try` / `catch` / `finally` | Yes | Catch binding is optional; `finally` always runs. |
| `throw` | Yes | Throws any value; caught as `EFloriaJSThrow` by the runtime. |
| `break` / `continue` with labels | Yes | Labels work on `for`, `for…in`, `for…of`, `while`, and labeled statements. |
| `return` | Yes | Not allowed outside a function (raises). |
| Empty statement (`;`) | Yes | Treated as an empty block. |
| `with` | No | Parsed as an identifier/expression; no binding semantics. |
| `debugger` | No | Parsed as an identifier; no effect. |
| `class` | No | Some forms are silently ignored, others fail to parse. |
| Generators (`function*`, `yield`) | No | Parse error. |
| `for await` | No | Parse error. |

There is no automatic semicolon insertion in the ECMAScript sense. Semicolons
are usually optional because the grammar accepts statement boundaries, but
line breaks do not terminate expressions:

```javascript
function f() { return
  1; }        // returns 1 in floriajs; undefined in JavaScript
```

## Functions

| Feature | Status | Notes |
| :--- | :--- | :--- |
| Function declarations | Yes | **Not hoisted**: a call before the declaration does not see it. |
| Function expressions | Yes | Named and anonymous. |
| Arrow functions | Yes | Expression and block bodies, zero or more parameters, `async` arrows. |
| Lexical `this` in arrows | Yes | Arrows do not rebind `this` and have no `prototype`. They are rejected by `new`. |
| Default parameters | Yes | Applied when the argument is `undefined`; `null` is kept. |
| Rest parameters | Yes | `function f(...args)`; must be last. |
| Destructured parameters | Yes | Object and array patterns, with defaults and rest. |
| `arguments` | Yes | An array-like **array** of the call's arguments. Present even inside arrow functions (unlike JavaScript). |
| Closures / recursion | Yes | Environments are reference-counted and reclaimed when unreachable. |
| `async` / `await` | Yes | Async functions return a promise; `await` drains pending jobs when needed. |
| Generators / `yield` | No | Parse error. |

## Operators

| Group | Operators |
| :--- | :--- |
| Assignment | `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `**=`, `??=` |
| Logical assignment | `&&=`, `\|\|=` — **not implemented** |
| Conditional | `? :` (right-associative chains work) |
| Nullish | `??` |
| Logical | `\|\|`, `&&` |
| Bitwise | `\|`, `^`, `&`, `~`, `<<`, `>>`, `>>>` |
| Equality | `==`, `!=`, `===`, `!==` |
| Relational | `<`, `<=`, `>`, `>=`, `in`, `instanceof` |
| Additive / multiplicative | `+`, `-`, `*`, `/`, `%` |
| Exponentiation | `**` (right-associative) |
| Unary | `!`, `~`, `+`, `-`, `typeof`, `delete`, `await`, prefix `++`/`--` |
| Postfix | `++`, `--` |
| Comma | `(a, b)` — evaluates left to right, yields the right value |
| Optional chaining | `a?.b`, `a?.[k]`, `a?.()` |
| `void` | **Not implemented** (lexed as an identifier) |

Notes:

- `in` requires an object on the right; otherwise it returns `false`.
- `instanceof` walks the prototype chain through the constructor's
  `prototype`; arrow functions return `false`.
- `delete` removes object properties and clears array elements. Deleting a
  plain variable returns `false`. It returns `true` for missing properties.
- Optional chaining short-circuits the immediate access/call. Because property
  access on `undefined` returns `undefined`, chained accesses usually behave as
  expected. Argument expressions of `a?.f(x)` are still evaluated when `a` is
  null/undefined.
- `==` handles `null == undefined`, number/string, and boolean conversions.
  Object-to-primitive coercion is not implemented (`[1] == 1` is `false`).

## Literals and lexical features

| Feature | Status | Notes |
| :--- | :--- | :--- |
| Decimal / fraction numbers | Yes | `.5`, `5.`, `1e3` |
| Hex / binary / octal | Yes | `0x10`, `0b1010`, `0o17` |
| Numeric separators | Yes | `1_000_000` (decimal forms) |
| Strings | Yes | `\n`, `\r`, `\t`, `\b`, `\f`, `\v`, `\0`, `\\`, `\'`, `\"`, `\xNN`, `\uNNNN` |
| Template literals | Yes | `` `v=${n + 1}` `` interpolation via string concatenation |
| Tagged templates | No | `tag\`x\`` is silently treated as adjacent expressions |
| Array literals | Yes | Holes (`[1, , 3]`), spread (`[...a]`), trailing commas |
| Object literals | Yes | Shorthand, computed keys, spread, methods, getters/setters, trailing commas |
| Spread in calls | Yes | `f(...args)` |
| Destructuring assignment | Yes | `[a, b] = arr;`, `({ a } = obj);` |
| Comments | Yes | `//` and `/* … */`; **not nested** |
| Regex literals | No | `/` is always division; regex literals fail to parse |

String `length`, indexing, and `for…of` operate on **UTF-8 bytes**, not UTF-16
code units. Non-ASCII characters count as multiple units.

## Built-in library

### Globals

| Name | Notes |
| :--- | :--- |
| `undefined`, `NaN`, `Infinity` | Standard values. |
| `parseInt`, `parseFloat`, `isNaN`, `isFinite` | `parseInt` honours the radix and `0x` prefixes; `parseFloat` accepts a numeric prefix. |
| `Number`, `String`, `Boolean` | Conversion functions (called with or without `new`). |
| `Number.isNaN`, `isFinite`, `isInteger`, `parseInt`, `parseFloat` | Plus `NaN`, `POSITIVE_INFINITY`, `NEGATIVE_INFINITY`, `MAX_VALUE`, `MIN_VALUE`, `MAX_SAFE_INTEGER`, `MIN_SAFE_INTEGER`, `EPSILON`. |
| `Array` | Constructor plus `isArray`, `from`, `of`. |
| `Object` | Constructor plus `keys`, `values`, `entries`, `assign`, `create`, `getPrototypeOf`. `Object.prototype` has `hasOwnProperty` and `toString`. |
| `JSON` | `stringify` and `parse` (see below). |
| `Math` | See below. |
| `Promise` | Object with `resolve`, `reject`, `all`, `race`. It is not a constructor: `new Promise(...)` is not supported. |
| `Error`, `TypeError`, `RangeError`, `ReferenceError` | Constructors returning error objects with `name` and `message`. |
| `console` | `log`, `warn`, `error`. Output is captured per context. |
| `globalThis` | A snapshot object containing references to the globals above. It is **not** a live global proxy: `var x = 1; globalThis.x` is `undefined`. |
| `arguments` | Available inside user functions; an `Array`. |
| `Date`, `Map`, `Set`, `Symbol`, `RegExp`, `Intl`, `eval`, timers, URI helpers | Not defined; accessing them yields `undefined`. |

### Math

Constants: `E`, `LN10`, `LN2`, `LOG2E`, `LOG10E`, `PI`, `SQRT1_2`, `SQRT2`.

Functions: `abs`, `acos`, `asin`, `atan`, `atan2`, `ceil`, `cos`, `exp`,
`floor`, `log`, `max`, `min`, `pow`, `random`, `round`, `sin`, `sqrt`, `tan`,
`trunc`, `log2`, `log10`, `sign`, `cbrt`, `hypot`, `imul`, `clz32`.

### Array

Prototype methods:

`push`, `pop`, `shift`, `unshift`, `join`, `concat`, `reverse`, `sort`
(optional comparator), `slice`, `splice`, `indexOf`, `lastIndexOf`, `includes`,
`map`, `filter`, `forEach`, `some`, `every`, `find`, `findIndex`, `reduce`,
`reduceRight`.

Statics: `Array.isArray`, `Array.from` (arrays, strings, array-like objects,
optional map function), `Array.of`. `Array.prototype` is the shared prototype
used by array values, and `[] instanceof Array` is `true`.

Not implemented: `flat`, `flatMap`, `fill`, `copyWithin`, `at`, `keys`,
`values`, `entries`. `arr.toString()` currently resolves to the generic
`Object.prototype.toString` and yields `[object Array]`; use `String(arr)` or
`arr.join()`.

### String

`charAt`, `charCodeAt`, `indexOf`, `lastIndexOf`, `includes`, `startsWith`,
`endsWith`, `slice`, `substring`, `substr`, `toUpperCase`, `toLowerCase`,
`trim`, `trimStart`, `trimEnd`, `split`, `replace`, `replaceAll`, `concat`,
`repeat`, `padStart`, `padEnd`, `toString`, `valueOf`.

`replace`/`replaceAll` support **string patterns** and optional function
replacers (called with `match`, `index`, and the whole string). They do not
support regex patterns or `$&`-style replacement templates. Not implemented:
`match`, `search`, `localeCompare`, `normalize`, `String.fromCharCode`,
`String.fromCodePoint`.

`String.prototype` is the shared prototype used by primitive strings, so
`String.prototype.charAt === "".charAt` is true.

### Object

- `Object.keys/values/entries` enumerate **own** properties in insertion order.
  Accessors are listed by key, but `values`/`entries` read the stored slot
  without invoking the getter.
- `Object.assign` copies own enumerable properties from object sources. Arrays
  and functions have no stored own properties in this runtime, so assigning
  from them copies nothing.
- `Object.create(proto)` creates an object with the given prototype;
  `Object.create(null)` creates a null-prototype object.
- `Object.getPrototypeOf` returns the prototype or `null`.
- `hasOwnProperty` is available through `Object.prototype` on normal objects.
- `Function.prototype.toString` returns a stable placeholder:
  `function name() { [native code] }`.

Function objects currently expose only `prototype` and `toString`.
`call`, `apply`, `bind`, `length`, and `name` are not implemented (accessing
them yields `undefined`).

Not implemented: `Object.is`, `defineProperty`, `getOwnPropertyNames`,
`freeze`/`seal`, `fromEntries`.

### JSON

- `JSON.stringify(value[, replacer[, space]])` supports primitives, arrays,
  nested objects, indentation via a numeric or string `space`, and circular
  reference detection (throws a `TypeError` error object). The `replacer`
  argument is ignored. Functions and `undefined` are omitted from objects and
  become `null` inside arrays; top-level `undefined`/function yields
  `undefined`.
- `JSON.parse(text)` parses RFC 8259-style JSON and throws a `SyntaxError`
  error object with a position on invalid input. A reviver argument is not
  supported.
- Getters are not invoked by `JSON.stringify`; it serialises stored property
  values.

### Errors and promises

- `new Error(msg)`, `new TypeError(msg)`, `new RangeError(msg)`, and
  `new ReferenceError(msg)` create error objects with `name`, `message`, and
  `ToString()` = `Name: message`.
- Error objects currently have a null prototype: `err instanceof Error` is
  `false` and `err.hasOwnProperty(...)` is unavailable.
- `throw` can throw any value. `catch (e)` receives it.
- `async` functions return promises; `.then`, `.catch`, and `.finally` are
  available on promises. `Promise.resolve/reject/all/race` are supported, but
  there is no promise constructor or host event loop. Microtasks are drained
  before `ExecuteProgram` returns.

## FTML expressions

FTML property expressions and signal handlers use this same language. See the
[FTML guide](ftml.md) for scope rules, bindings, anchors, and signals.

## Semantic deviations

These are the differences most likely to surprise a JavaScript developer:

| Area | Current behaviour |
| :--- | :--- |
| `const` | Reassignment is allowed. |
| `var` | Block-scoped; not hoisted. |
| Function declarations | Not hoisted. |
| `void` | Not an operator. `void 0` happens to yield `0` because it is two expressions. |
| Logical assignment | `&&=` and `\|\|=` are not implemented. |
| Tagged templates | Not implemented; often silently treated as two expressions. |
| Regex | No regex literals or `RegExp`. |
| `class` | Not implemented; some forms fail, some are ignored. |
| Property access on `null`/`undefined` | Returns `undefined` instead of throwing `TypeError`. |
| Calling a non-function | Returns `undefined` instead of throwing `TypeError`. (The exception is `new`, which throws.) |
| Assigning to a property of `null`/`undefined` | Silently does nothing. |
| `instanceof` for errors | `err instanceof Error` is `false`. |
| `globalThis` | Snapshot, not a live binding to the global scope. |
| `arguments` in arrows | Arrows get their own `arguments` array. |
| Strings | Byte-oriented (UTF-8), including `length`, indexing, and `for…of`. |
| Loose equality | No object-to-primitive coercion. |
| Number formatting | Integral doubles print without a fractional part; general formatting uses the host locale. |
| Array `toString` | Inherits `Object.prototype.toString` and yields `[object Array]`. |
| Array enumeration | `Object.keys/values/entries(arr)` only see named properties; numeric indices and `length` are not included. `arr.hasOwnProperty(0)` is `false`. Use `in` or direct indexing instead. |
| Object spread from an array | Copies no elements, because indices are not own object properties. Use array spread (`[...arr]`) for arrays. |
| `JSON.stringify` | Ignores the replacer and does not invoke getters. |
| Promise construction | `new Promise(executor)` is not supported. |
| Optional chaining | Short-circuits the immediate operation, not argument evaluation of `a?.f(args)`. |
| `for…in`/`for…of` targets | Must be simple identifiers; destructuring targets are not parsed. |
| `for…in` on strings | Produces no keys (strings are not objects). |
| `for…in` on arrays | Enumerates prototype method names, not element indices. Prefer `for…of` or a classic index loop. |
| `for…of` on non-iterables | Runs zero iterations. |

## Verifying behaviour

- Run `pasbuild test` for the unit suite.
- Run `bash scratch/run_gapscan.sh` for the JavaScript-level probe matrix.
- When adding a feature, update this page and the [roadmap](roadmap.md).
