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
| `var`, `let`, `const` | Yes | `let`/`const` are block-scoped; `var` declarations hoist to the enclosing function/top-level environment. `const` reassignment throws `TypeError`. Cross-scope `var`/`let` conflicts raise `SyntaxError`. |
| Destructuring declarations | Yes | `var { a, b: c = 1, ...rest } = obj;`, `var [a, , b = 2, ...rest] = arr;` |
| Destructuring assignments | Yes | Array and object patterns, defaults, rest, and member targets. Reject non-iterables in array destructuring with `TypeError`. |
| Blocks | Yes | Create a child scope. |
| `if` / `else` | Yes | |
| `while`, `do…while` | Yes | `break` / `continue`, including labels. |
| Classic `for` | Yes | `var`/`let`/`const` initializers, multiple declarators, optional clauses. |
| `for…of` | Yes | Arrays and strings. Non-iterables throw `TypeError`. `Map`/`Set` iterator protocol scheduled for P2-05. Target must be a plain identifier. |
| `for…in` | Yes | Own and inherited keys of objects, skipping `Object.prototype`. On an array it enumerates the present element indices; holes are skipped. Target must be a plain identifier. |
| `switch` / `case` / `default` | Yes | Strict equality, fall-through, `break`. |
| `try` / `catch` / `finally` | Yes | Catch binding is optional; `finally` always runs. |
| `throw` | Yes | Throws any value; caught as `EFloriaJSThrow` by the runtime. |
| `break` / `continue` with labels | Yes | Labels work on `for`, `for…in`, `for…of`, `while`, and labeled statements. |
| `return` | Yes | Not allowed outside a function (raises). |
| Empty statement (`;`) | Yes | Treated as an empty block. |
| `with` | No | Rejected at parse time with a clear error; it never runs as an undeclared name. |
| `debugger` | Yes | A no-op statement, recognised as a keyword. It is reserved, so it cannot be used as an identifier. |
| `class` | No | Not a keyword: every form (`class A {}`, `class {}`, `extends`) parses as the identifier `class` and throws `ReferenceError: class is not defined`. Scheduled as P2-06. |
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
| Function declarations | Yes | Hoisted in function bodies, program bodies, and switch bodies. |
| Function expressions | Yes | Named and anonymous. |
| Arrow functions | Yes | Expression and block bodies, zero or more parameters, `async` arrows. |
| Lexical `this` in arrows | Yes | Arrows do not rebind `this` and have no `prototype`. They are rejected by `new`. |
| Default parameters | Yes | Applied when the argument is `undefined`; `null` is kept. |
| Rest parameters | Yes | `function f(...args)`; must be last. |
| Destructured parameters | Yes | Object and array patterns, with defaults and rest. |
| `arguments` | Yes | An array-like **array** of the call's arguments. Present even inside arrow functions (unlike JavaScript). |
| `bind` and `new` | Yes | A bound function is constructable exactly when its target is; `new Bound(...)` ignores the bound `this` and uses the target's prototype. Bound functions have no own `prototype`. |
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
- `delete` follows ECMAScript:
  - `delete obj.p` / `delete obj[k]` removes the property (or turns an array
    element into a hole, leaving `length` unchanged) and returns `true`.
    Deleting a missing property is `true`. A member expression on
    `null`/`undefined` throws `TypeError` while it is being evaluated.
  - `delete identifier` never reads the binding. A declared binding (`var`,
    `let`, `const`, parameter, function local) is non-deletable, so it returns
    `false` and the binding keeps its value. An undeclared name returns `true`
    and creates nothing.
  - Any other operand (`delete 1`, `delete f()`) is evaluated and yields
    `true`.
- Optional chaining short-circuits the full chain across member accesses and calls (`a?.b.c` and `a?.b()` return `undefined` on nullish `a`). Grouping boundaries `(a?.b).c` terminate the optional chain. `new a?.b()` and optional-chain assignment/update targets, including parenthesized targets such as `(a?.b)++`, are rejected as syntax errors.
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
| Tagged templates | No | The tag is **not called**. `tag\`x\`` parses as the expression `tag` followed by a template literal, and the whole thing evaluates to the template string, so `tag` is never invoked |
| Array literals | Yes | Holes/elisions (`[1, , 3]`), spread (`[...a]`), trailing commas. Holes are tracked separately from explicit `undefined`. |
| Object literals | Yes | Shorthand, computed keys, spread, methods, getters/setters, trailing commas |
| Spread in calls | Yes | `f(...args)` |
| Destructuring assignment | Yes | `[a, b] = arr;`, `({ a } = obj);` |
| Comments | Yes | `//` and `/* … */`; **not nested** |
| Regex literals | Yes | `/pattern/flags`, with `g`, `i`, and `m` |

String `length`, indexing, and `for…of` operate on **UTF-8 bytes**, not UTF-16
code units. Non-ASCII characters count as multiple units.

## Built-in library

### Globals

| Name | Notes |
| :--- | :--- |
| `undefined`, `NaN`, `Infinity` | Standard values. |
| `parseInt`, `parseFloat`, `isNaN`, `isFinite` | `parseInt` honours the radix and `0x` prefixes; `parseFloat` accepts a numeric prefix. |
| `Number`, `String`, `Boolean` | Conversion functions (called with or without `new`). Number conversion and formatting are ECMAScript-exact: `String(x)` produces the shortest decimal that round-trips, and `Number(s)` produces the nearest double. |
| `Number.isNaN`, `isFinite`, `isInteger`, `parseInt`, `parseFloat` | Plus `NaN`, `POSITIVE_INFINITY`, `NEGATIVE_INFINITY`, `MAX_VALUE`, `MIN_VALUE`, `MAX_SAFE_INTEGER`, `MIN_SAFE_INTEGER`, `EPSILON`. |
| `Array` | Constructor plus `isArray`, `from`, `of`. |
| `Object` | Constructor plus `keys`, `values`, `entries`, `assign`, `create`, `getPrototypeOf`. `Object.prototype` has `hasOwnProperty` and `toString`. |
| `JSON` | `stringify` and `parse` (see below). |
| `Math` | See below. |
| `Promise` | Object with `resolve`, `reject`, `all`, `race`. It is not a constructor: `new Promise(...)` is not supported. |
| `Error`, `TypeError`, `RangeError`, `ReferenceError`, `SyntaxError` | Constructors returning error objects with standard prototype chains, `name`, `message`, and `toString()`. |
| `console` | `log`, `warn`, `error`. Output is captured per context. |
| `globalThis` | A snapshot object containing references to the globals above. It is **not** a live global proxy: `var x = 1; globalThis.x` is `undefined`. |
| `arguments` | Available inside user functions; an `Array`. |
| `Map`, `Set` | Collections (see below). |
| `Date` | Date/time object (see below). |
| `Symbol` | Primitive symbols, registry, and well-known symbols. |
| `RegExp` | Regular-expression constructor and regex literals. |
| `URIError`, `encodeURIComponent`, `decodeURIComponent`, `encodeURI`, `decodeURI` | URI helpers. |
| `setTimeout`, `clearTimeout`, `setInterval`, `clearInterval` | Host timers. They require the host to pump `FloriaJSProcessTimers`. |
| `Intl`, `eval`, `alert`, `BigInt` | Not defined; accessing them yields `undefined`. |

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

Sparse arrays follow ECMAScript: an array literal elision, `new Array(n)`, and
`length = n` create **holes**, which read as `undefined` but are not own
properties. `hasOwnProperty`, `in`, `Object.keys`/`values`/`entries`, and
`for…in` therefore distinguish a hole from an explicit `undefined` element.
Hole-skipping methods (`map`, `forEach`, `filter`, `some`, `every`, `reduce`,
`reduceRight`, `indexOf`, `lastIndexOf`) skip holes while `map` preserves them
in its result; `sort` moves holes to the end; `join`/`toString` render them as
empty text; `JSON.stringify` emits `null`; spread materialises holes as
explicit `undefined`. `length = n` extends with holes or truncates the array,
and invalid lengths raise `RangeError`.

Not implemented: `flat`, `flatMap`, `fill`, `copyWithin`, `at`, `keys`,
`values`, `entries`. `arr.toString()` returns comma-joined elements like `arr.join()`.

### String

`charAt`, `charCodeAt`, `indexOf`, `lastIndexOf`, `includes`, `startsWith`,
`endsWith`, `slice`, `substring`, `substr`, `toUpperCase`, `toLowerCase`,
`trim`, `trimStart`, `trimEnd`, `split`, `replace`, `replaceAll`, `concat`,
`repeat`, `padStart`, `padEnd`, `match`, `search`, `toString`, `valueOf`.

`replace`/`replaceAll` accept string or regex patterns and optional function
replacers (called with `match`, `index`, and the whole string). `$&`-style
replacement templates are not supported. `match`/`search`/`split` work with
regex patterns. Not implemented: `localeCompare`, `normalize`,
`String.fromCharCode`, `String.fromCodePoint`.

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

Function objects expose `prototype`, `toString`, `call`, `apply`, and `bind`.
Constructors have lifetime-safe `prototype.constructor` back-references.

A bound function is a function object of its own, as in ECMAScript:

- `bind` curries arguments and fixes `this`; a call of the bound function
  ignores the receiver it is called with and passes the bound arguments before
  the call arguments.
- `new Bound(...)` ignores the bound `this`, constructs the target with the
  combined arguments, and gives the instance the target's prototype. A bound
  function is constructable exactly when its target is, so `new` on a bound
  arrow function throws `TypeError`.
- `instanceof` resolves through the target's prototype chain, so an instance
  created by `new Bound()` satisfies both `x instanceof Bound` and
  `x instanceof Target`.
- A bound function has no own `prototype`; `"prototype" in B` and
  `B.hasOwnProperty("prototype")` are `false`.

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

### Map and Set

- `new Map()` / `new Map([[key, value], …])`, `new Set()` /
  `new Set([value, …])`.
- `Map`: `set`, `get`, `has`, `delete`, `clear`, `keys`, `values`, `entries`,
  `forEach`, and the `size` getter.
- `Set`: `add`, `has`, `delete`, `clear`, `keys`, `values`, `entries`,
  `forEach`, and the `size` getter.
- Keys use SameValueZero: `NaN` equals `NaN`, and `+0`/`-0` are the same key.
- `keys`, `values`, and `entries` return **arrays**, not iterator objects.
  `Map`/`Set` are not iterable themselves: `for…of` over one throws `TypeError`
  (`5 is not iterable`-style), so iterate the returned arrays instead.

### Date

- `new Date()`, `new Date(ms)`, `new Date("ISO-8601")`, and
  `new Date(year, month, day[, h, m, s, ms])`.
- `Date.now()`, `Date.parse(string)`, `Date.UTC(...)`.
- `getTime`, `valueOf`, `toISOString`, `toUTCString`, `toDateString`,
  `toTimeString`, `toString`, `getTimezoneOffset`, and the UTC/local
  component getters (`getFullYear`, `getMonth`, `getDate`, `getDay`,
  `getHours`, `getMinutes`, `getSeconds`, `getMilliseconds`, and their
  `getUTC*` forms).
- `setTime(ms)` is supported. The other component setters
  (`setFullYear`, `setMonth`, …) are not implemented.

### Symbol

- `Symbol(description)` creates a primitive symbol; `typeof` is `symbol`.
- `Symbol.for(key)` / `Symbol.keyFor(symbol)` use the global registry.
- Well-known symbols: `Symbol.iterator`, `Symbol.toStringTag`,
  `Symbol.hasInstance`, `Symbol.isConcatSpreadable`, `Symbol.toPrimitive`.
- `new Symbol(...)` is rejected (as in JavaScript), and symbols coerce to
  strings as `Symbol(description)`.

### RegExp

- Regex literals: `/pattern/flags` with `g`, `i`, and `m` flags.
- `new RegExp(pattern[, flags])`, `test(string)`, `exec(string)`, and
  `toString()`.
- `exec` returns an array with the whole match, capture groups, `index`, and
  `input`; global expressions track an internal position for repeated
  `exec` calls, but a JavaScript-visible `lastIndex` property is not exposed.
- `String.prototype.match`, `search`, `replace`, and `split` accept regex
  objects.
- The implementation is backed by Pascal's `RegExpr` engine, so very advanced
  ECMAScript regex features (lookbehind, named groups, Unicode property
  escapes) should not be assumed.

### URI helpers

`encodeURIComponent`, `decodeURIComponent`, `encodeURI`, and `decodeURI` are
available, along with `URIError`. Invalid percent-encoding raises a catchable
`URIError`.

### Timers

`setTimeout`, `clearTimeout`, `setInterval`, and `clearInterval` register
callbacks in a process-wide queue. The runtime has no wall-clock event loop:
the host must call `FloriaJSProcessTimers(Heap)` periodically. Without that
pump, delayed and repeating callbacks do not execute.

### Numbers

- `String(x)`, `` `${x}` ``, `x.toString()`, and `JSON.stringify` all produce the
  same ECMAScript form: the shortest decimal that parses back to the same
  double, with fixed notation for `1e-6 <= |x| < 1e21` and scientific notation
  outside that range (`1e-7`, `1e+21`). So `String(1e20)` is
  `"100000000000000000000"` and `(0.1 + 0.2).toString()` is
  `"0.30000000000000004"`.
- `Number(text)`, numeric literals, and `parseFloat` are correctly rounded:
  they produce the nearest double, ties to even. `Number("1e309")` is
  `Infinity`, and values below the subnormal range become `0`.
- `Number.prototype.toString(radix)` supports radix 2 through 36, including the
  fractional part, and throws `RangeError` outside that range.
- `NaN` and the infinities stringify as `"NaN"`, `"Infinity"`, and
  `"-Infinity"`; both zeros stringify as `"0"`.

### Errors and promises

- `new Error(msg)`, `new TypeError(msg)`, `new RangeError(msg)`,
  `new ReferenceError(msg)`, `new SyntaxError(msg)`, and `URIError(...)`
  create error objects with `name`, `message`, and `ToString()` =
  `Name: message`.
- Error objects have proper prototype chains: `err instanceof TypeError`,
  `err.hasOwnProperty(...)`, and inherited `toString()` work.
- The VM throws catchable `TypeError`/`RangeError` objects for property access
  or assignment on `null`/`undefined`, calling a non-function, and exceeding
  the call-depth limit.
- `throw` can throw any value. `catch (e)` receives it.
- `async` functions return promises; `.then`, `.catch`, and `.finally` are
  available on promises. `Promise.resolve/reject/all/race` are supported, but
  there is no promise constructor or host event loop. Microtasks are drained
  after a script runs.

## FTML expressions

FTML property expressions and signal handlers use this same language. See the
[FTML guide](ftml.md) for scope rules, bindings, anchors, and signals.

## Semantic deviations

These are the differences most likely to surprise a JavaScript developer. They
are grouped by cause, because the three groups have different answers:

- **Deliberate embedded trade-offs** are design decisions for a small,
  dependency-free runtime. They are not scheduled to change.
- **Missing features** are unimplemented syntax or APIs. Each is scheduled on
  the [roadmap](roadmap.md) under the priority named here.
- **Known gaps** are places where the implementation differs from ECMAScript
  without a specific scheduled task yet; they are the most likely to bite.

### Deliberate embedded trade-offs

| Area | Behaviour | Why |
| :--- | :--- | :--- |
| Execution engine | Pure bytecode interpreter; no JIT/AOT, hidden classes, inline caches, or persistent bytecode cache. | Keeps the runtime embeddable and dependency-free. Optional work is P3. |
| Timers | Require the host to call `FloriaJSProcessTimers`; no built-in event loop, and timer state is process-wide. | The host owns the main loop. |
| Strings | Byte-oriented (UTF-8), including `length`, indexing, and `for…of`. | Avoids a UTF-16 representation in an embedded runtime. |
| `globalThis` | A snapshot object, not a live binding to the global scope. | A live proxy would need a global object model. |
| `Map`/`Set` storage | Lookup is linear rather than hash-based; `keys`/`values`/`entries` return arrays, not iterator objects. | Simplicity; the full iterator protocol is P2-05. |
| Regular expressions | Backed by Pascal `RegExpr`; advanced ECMAScript features (lookbehind, named groups, Unicode property escapes) are not guaranteed. `lastIndex` is internal, not a JS property. | Reuses the FPC regex engine instead of shipping one. |
| `Symbol` property keys | Symbols are primitives, but `obj[sym]` stores under the string form `Symbol(description)`; not real symbol-keyed properties. | Would require a separate symbol-keyed property table. |

### Missing features (scheduled)

| Area | Current behaviour | Task |
| :--- | :--- | :--- |
| `void` | Not a keyword or operator: `void` parses as an identifier, so any use throws `ReferenceError: void is not defined`. | P2-01 |
| Logical assignment | `&&=` and `\|\|=` are not implemented; `a &&= b` is a parse error. | P2-02 |
| Promise construction | `new Promise(executor)` is not supported (`TypeError: Value is not a constructor`); use `Promise.resolve`/`reject`/`all`/`race`. | P2-03 |
| `JSON` parity | `JSON.stringify` ignores the replacer, does not invoke getters, and does not call `toJSON`; `JSON.parse` has no reviver. | P2-04 |
| `for…of` on Map/Set | Throws `TypeError` because they are not iterable; use `keys()`/`values()`/`entries()`, which return arrays. | P2-05 |
| `class` | Not a keyword: every form (`class A {}`, `class {}`, `extends`) parses as the identifier `class` and throws `ReferenceError: class is not defined`. | P2-06 |
| Generators / `for await` | `function*` and `for await` are parse errors. | P2-07 |
| Tagged templates | The tag is never called: `tag\`x\`` evaluates to the template string itself, so `function t(s){ return 1; } t\`x\`` is `"x"`, not `1`. | P2-08 |
| `BigInt` | `10n` is not supported. | P2-09 |
| Function metadata | `Function` constructor, `length`, `name`, and `toString` parity. | P2-10 |
| Library completeness | `Object.is`/`defineProperty`/`getOwnPropertyNames`/`freeze`/`seal`/`fromEntries`, `Array.prototype.flat`/`flatMap`/`fill`/`copyWithin`/`at`, `String.fromCharCode`/`fromCodePoint`, `String.prototype.localeCompare`/`normalize`, `Date` setters, `Intl`, `eval`, `alert`. | P2-11 |
| Modules | `import`/`export` are not implemented; no module system. | — |

### Known gaps

| Area | Behaviour |
| :--- | :--- |
| TDZ | There is no temporal dead zone before a `let`/`const` declaration. |
| `var` | Hoisted to function or script root. `let`/`const` are block-scoped. Cross-scope collisions raise `SyntaxError`. |
| Classic `for` with `let`/`const` | Loop bindings are block-scoped and invisible after the loop. Each iteration gets a fresh binding, so closures capture per-iteration values; `var` loop bindings remain function/script scoped. |
| `with` | Unsupported: rejected at parse time rather than as a runtime `ReferenceError`. |
| Loose equality | No object-to-primitive coercion: `[1] == 1` and `[] == false` are `false`, and a custom `toString`/`valueOf` is not consulted by `+` or `==`. |
| Object spread from an array | Copies no elements, because indices are not own object properties. Use array spread (`[...arr]`) for arrays. |
| `for…in`/`for…of` targets | Must be simple identifiers; destructuring targets are not parsed. |
| `for…in` on strings | Produces no keys (strings are not objects). |
| `for…of` on non-iterables | Throws `TypeError`. |
| Optional chaining | Full chain short-circuiting across member accesses and calls. Grouping boundaries `(a?.b)` terminate the chain. `new a?.b()` and optional-chain assignment/update targets, including parenthesized targets, are rejected as syntax errors. |
| `this` | Behaves as if every function were strict: a plain call sees `this === undefined` rather than the global object, so `function f(){ return this; } f()` is `undefined`. At the top level of a script `this` is not bound at all, and reading it throws `ReferenceError`; use `globalThis` instead. Methods, `new`, and lexical `this` in arrows behave normally. |
| Detached `prototype.constructor` | `Foo.prototype.constructor === Foo` works, but the back-reference is a weak registration. After `var p = Foo.prototype; Foo.prototype = {}`, `p.constructor` is `Object` rather than `Foo`. |

## Not implemented

Unimplemented syntax and APIs are listed once, in
[Missing features (scheduled)](#missing-features-scheduled), together with the
roadmap task that covers them. That table is the authoritative list; this page
does not repeat it, so the two cannot drift apart.

`import`/`export` is listed there without a task number because it is not yet
scheduled in detail; there is no module system.

## Verifying behaviour

- Run `pasbuild test` for the unit suite.
- Run `bash scratch/run_gapscan.sh` for the JavaScript-level probe matrix.
- Run `bash scratch/run_docclaims.sh` to check that the statements on this page
  still match the runtime. Each claim in `scratch/docclaims.pas` asserts one
  documented behaviour, so correcting the docs and adding the claim go
  together.
- When adding a feature, update this page and the [roadmap](roadmap.md).
