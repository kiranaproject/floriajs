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
| `for…of` | Yes | Follows the iteration protocol: arrays, strings, `Map`, `Set`, and any iterator object. Non-iterables throw `TypeError`. The target may be a plain identifier or a destructuring pattern (`for (const [k, v] of map)`). |
| `for…in` | Yes | Own and inherited keys of objects, skipping `Object.prototype`. On an array it enumerates the present element indices; holes are skipped. Strings enumerate their indices. The target may be a plain identifier or a destructuring pattern. |
| `switch` / `case` / `default` | Yes | Strict equality, fall-through, `break`. |
| `try` / `catch` / `finally` | Yes | Catch binding is optional; `finally` always runs. |
| `throw` | Yes | Throws any value; caught as `EFloriaJSThrow` by the runtime. |
| `break` / `continue` with labels | Yes | Labels work on `for`, `for…in`, `for…of`, `while`, and labeled statements. |
| `return` | Yes | Not allowed outside a function (raises). |
| Empty statement (`;`) | Yes | Treated as an empty block. |
| `with` | Yes (sloppy) | Supported in sloppy mode, including boxed primitives. Strict mode rejects it as a `SyntaxError`. |
| `debugger` | Yes | A no-op statement, recognised as a keyword. It is reserved, so it cannot be used as an identifier. |
| `class` | Yes | Declarations and expressions, `constructor`, methods, `get`/`set`, `static`, `extends`, and `super`. Methods are non-enumerable. Class fields are not supported. |
| Generators (`function*`, `yield`) | Yes | `function*` bodies run lazily and suspend at `yield`; `yield*` delegates. Generator objects implement `next()`, `return()`, and `Symbol.iterator`, and may be resumed by a later script. |
| `for await` | Yes | Async iteration over async iterators and sync iterables; each step awaits the iterator result. `async function*` is supported, including `yield`, `await`, and `yield*`. |

Automatic semicolon insertion covers the restricted productions and statement
boundaries:

- a line break after `return`, `break`, `continue`, or `throw` ends the
  statement; `return` and `break`/`continue` without an operand or label, and a
  `throw` with no expression on its line, are handled accordingly;
- a line break before postfix `++`/`--` ends the previous statement instead of
  applying the operator;
- a line break may terminate a statement that the grammar would otherwise
  continue, and `}` or end of input also terminate a statement;
- a semicolon is still required between two statements on the same line.

```javascript
function f() { return
  1; }        // returns undefined, as in JavaScript

var x = 1
x
++x           // x is 1, and the prefix increment applies to a new statement
```

A `throw` followed by a line break is a syntax error, because ECMAScript does
not allow the newline there:

```javascript
throw
new Error("boom");   // SyntaxError: Illegal newline after throw
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
| `async` / `await` | Yes | Async function bodies are resumable state machines: `await` suspends and resumes when the awaited promise settles, including timers and try/catch across awaits. |
| `eval` | Yes | Direct `eval(source)` runs in the caller's environment and returns the completion value; indirect eval runs in global scope. Parse/compile errors become catchable `SyntaxError`s. Non-strict eval `var` declarations reach the caller's variable environment while `let`/`const` are scoped to the eval; strict eval gets its own variable environment. |
| Generators / `yield` | Yes | See the Generators section. |

## Operators

| Group | Operators |
| :--- | :--- |
| Assignment | `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `**=`, `??=`, `&=`, `\|=`, `^=`, `<<=`, `>>=`, `>>>=` |
| Logical assignment | `&&=`, `\|\|=`, including short-circuiting: the right-hand side is not evaluated when the assignment is skipped |
| Conditional | `? :` (right-associative chains work) |
| Nullish | `??` |
| Logical | `\|\|`, `&&` |
| Bitwise | `\|`, `^`, `&`, `~`, `<<`, `>>`, `>>>` |
| Equality | `==`, `!=`, `===`, `!==` |
| Relational | `<`, `<=`, `>`, `>=`, `in`, `instanceof` |
| Additive / multiplicative | `+`, `-`, `*`, `/`, `%` |
| Exponentiation | `**` (right-associative) |
| Unary | `!`, `~`, `+`, `-`, `typeof`, `delete`, `void`, `await`, prefix `++`/`--` |
| Postfix | `++`, `--` |
| Comma | `(a, b)` — evaluates left to right, yields the right value |
| Optional chaining | `a?.b`, `a?.[k]`, `a?.()` |
| `void` | `void expr` evaluates the operand and yields `undefined` |

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
  Object-to-primitive coercion uses `valueOf` and `toString` for arithmetic, `+`, loose equality, and relational operators.

## Literals and lexical features

| Feature | Status | Notes |
| :--- | :--- | :--- |
| Decimal / fraction numbers | Yes | `.5`, `5.`, `1e3` |
| Hex / binary / octal | Yes | `0x10`, `0b1010`, `0o17` |
| Numeric separators | Yes | `1_000_000` (decimal forms) |
| Strings | Yes | `\n`, `\r`, `\t`, `\b`, `\f`, `\v`, `\0`, `\\`, `\'`, `\"`, `\xNN`, `\uNNNN` |
| Template literals | Yes | `` `v=${n + 1}` `` interpolation via string concatenation |
| Tagged templates | Yes | `tag\`a${b}c\`` calls `tag` with the cooked strings array (which carries a `raw` array of the source text) followed by the substitution values |
| Array literals | Yes | Holes/elisions (`[1, , 3]`), spread (`[...a]`), trailing commas. Holes are tracked separately from explicit `undefined`. |
| Object literals | Yes | Shorthand, computed keys, spread, methods, getters/setters, trailing commas |
| Spread in calls | Yes | `f(...args)` |
| Destructuring assignment | Yes | `[a, b] = arr;`, `({ a } = obj);` |
| Comments | Yes | `//` and `/* … */`; **not nested** |
| Regex literals | Yes | `/pattern/flags`, with `g`, `i`, and `m` |

String `length`, indexing, `charCodeAt`, slicing, and `for…of` operate on
UTF-16 code units. A non-BMP character is a surrogate pair and therefore has
length 2; the string iterator yields the whole code point as one value. Regex
matching and byte-level lexer storage still use UTF-8 internally.

## Built-in library

### Globals

| Name | Notes |
| :--- | :--- |
| `undefined`, `NaN`, `Infinity` | Standard values. |
| `parseInt`, `parseFloat`, `isNaN`, `isFinite` | Arguments go through the full ToString path (including `valueOf`/`toString`), so a boxed Number or a custom `toString` is honoured. `parseInt` honours the radix and `0x` prefixes and keeps accumulating past 2^63 as a Number; `parseFloat` scans the longest valid `StrDecimalLiteral` prefix. Both trim the ECMAScript whitespace set. |
| `Number`, `String`, `Boolean` | Conversion functions (called with or without `new`). Number conversion and formatting are ECMAScript-exact: `String(x)` produces the shortest decimal that round-trips, and `Number(s)` produces the nearest double. |
| `Number.isNaN`, `isFinite`, `isInteger`, `isSafeInteger`, `parseInt`, `parseFloat` | Plus `NaN`, `POSITIVE_INFINITY`, `NEGATIVE_INFINITY`, `MAX_VALUE`, `MIN_VALUE`, `MAX_SAFE_INTEGER`, `MIN_SAFE_INTEGER`, `EPSILON`. |
| `Array` | Constructor plus `isArray`, `from`, `of`. |
| `Object` | Constructor plus `keys`, `values`, `entries`, `fromEntries`, `assign`, `create`, `getPrototypeOf`, `setPrototypeOf`, `is`, `hasOwn`, `groupBy`, `getOwnPropertyNames`, `getOwnPropertySymbols`, `getOwnPropertyDescriptor`, `getOwnPropertyDescriptors`, `defineProperty`, `defineProperties`, `freeze`, `seal`, `preventExtensions`, `isExtensible`, `isFrozen`, `isSealed`. `Object.prototype` has `hasOwnProperty`, `isPrototypeOf`, `propertyIsEnumerable`, `valueOf`, and `toString`. |
| `JSON` | `stringify` and `parse` (see below). |
| `Math` | See below. |
| `Promise` | Constructor: `new Promise(executor)` runs the executor synchronously with `resolve`/`reject` callbacks (first settlement wins; a throw rejects). Plus `resolve`, `reject`, `all`, `allSettled`, `any`, `race`. |
| `Error`, `TypeError`, `RangeError`, `ReferenceError`, `SyntaxError`, `URIError` | Constructors returning error objects with standard prototype chains, `name`, `message`, and `toString()`. `message` is an own non-enumerable property only when supplied; a Symbol message throws `TypeError`; `new Error(msg, { cause })` installs a non-enumerable `cause`. |
| `console` | `log`, `warn`, `error`. Output is captured per context. |
| `globalThis` | The live global object. Global `var`/function bindings are its properties, and property writes through it update the globals. Global lexical `let`/`const` bindings are not properties. |
| `arguments` | Available inside user functions; an `Array`. |
| `Map`, `Set` | Collections (see below). |
| `WeakMap`, `WeakSet` | True weak collections: a key/value is not retained, so an entry disappears once only the collection refers to it. Only objects and non-registered symbols may be held weakly, and the constructors are not callable without `new`. `WeakMap` also has the `getOrInsert`/`getOrInsertComputed` upsert methods. |
| `Date` | Date/time object (see below). |
| `Symbol` | Primitive symbols, registry, and well-known symbols (`iterator`, `asyncIterator`, `toStringTag`, `hasInstance`, `isConcatSpreadable`, `species`, `toPrimitive`, `match`, `matchAll`, `replace`, `search`, `split`). |
| `RegExp` | Regular-expression constructor and regex literals. |
| `URIError`, `encodeURIComponent`, `decodeURIComponent`, `encodeURI`, `decodeURI` | URI helpers. Arguments go through ToString; encoding emits UTF-8 percent escapes for astral code points; decoding validates the byte sequence (overlong forms, surrogate halves, and out-of-range code points raise `URIError`). `decodeURI` keeps reserved characters escaped and preserves the source spelling. |
| `setTimeout`, `clearTimeout`, `setInterval`, `clearInterval` | Host timers. They require the owner context to pump timers (`Ctx.PumpTimers()` or the compatibility helper `FloriaJSProcessTimers(Ctx.Heap)`). |
| `BigInt` | Conversion function. `new BigInt()` throws; it is not a constructor. |
| `queueMicrotask`, `structuredClone` | Host-style globals. `queueMicrotask` runs its callback with no arguments on the microtask queue; `structuredClone` deep-clones primitives, arrays, plain objects, `Map`, `Set`, `Date`, and `RegExp`, including cycles. |
| `AggregateError` | Error subclass with an `errors` own property, `message`, `cause`, and the standard prototype chain. |
| `Intl` and `alert` | Not defined. Reading them throws `ReferenceError`; only `typeof` yields `undefined`. |

### Math

Constants: `E`, `LN10`, `LN2`, `LOG2E`, `LOG10E`, `PI`, `SQRT1_2`, `SQRT2`.

Functions: `abs`, `acos`, `acosh`, `asin`, `asinh`, `atan`, `atan2`, `atanh`,
`cbrt`, `ceil`, `clz32`, `cos`, `cosh`, `exp`, `expm1`, `floor`, `fround`,
`hypot`, `imul`, `log`, `log1p`, `log2`, `log10`, `max`, `min`, `pow`,
`random`, `round`, `sign`, `sin`, `sinh`, `sqrt`, `tan`, `tanh`, `trunc`.

### Array

Prototype methods:

`push`, `pop`, `shift`, `unshift`, `join`, `concat`, `reverse`, `sort`
(optional comparator), `slice`, `splice`, `indexOf`, `lastIndexOf`, `includes`,
`map`, `filter`, `forEach`, `some`, `every`, `find`, `findIndex`, `findLast`,
`findLastIndex`, `reduce`, `reduceRight`, `toSorted`, `toReversed`, `toSpliced`,
`with`.

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
empty text unless the prototype chain supplies a value for that index;
`JSON.stringify` emits `null`; spread materialises holes as
explicit `undefined`. `length = n` extends with holes or truncates the array,
and invalid lengths raise `RangeError`.

`flat`, `flatMap`, `fill`, `copyWithin`, `at`, and `values` are implemented.
`toSorted`, `toReversed`, `toSpliced`, and `with` return a new array and leave
the receiver unchanged; they read through `Get`, so a hole becomes `undefined`
in the result.
Array indices in `[0, 2^32 - 2]` extend `length`; very large sparse indices are
stored in an overflow list instead of forcing a dense allocation. `length`
accepts the full `2^32 - 1` boundary.

`keys`, `entries`, and `values` return iterator objects. `arr.toString()`
returns comma-joined elements like `arr.join()`.

### String

`charAt`, `charCodeAt`, `indexOf`, `lastIndexOf`, `includes`, `startsWith`,
`endsWith`, `slice`, `substring`, `substr`, `toUpperCase`, `toLowerCase`,
`trim`, `trimStart`, `trimEnd`, `split`, `replace`, `replaceAll`, `concat`,
`repeat`, `padStart`, `padEnd`, `match`, `matchAll`, `search`, `at`, `toString`,
`valueOf`.

`replace`/`replaceAll` accept string or regex patterns and optional function
replacers (called with `match`, `index`, and the whole string). `$&`-style
replacement templates are not supported. `match`/`search`/`split` work with
regex patterns. `String.fromCharCode` and `String.fromCodePoint` build strings
from code units and code points. `fromCharCode` treats each argument as a single code unit; `fromCodePoint` encodes an astral point as a surrogate pair.

`normalize` supports NFC, NFD, NFKC, and NFKD. `localeCompare` uses
deterministic code-point order after canonical decomposition; it is not
locale-sensitive collation.

`String.prototype` is the shared prototype used by primitive strings, so
`String.prototype.charAt === "".charAt` is true. `new String(value)` creates a
boxed String object: `typeof` is `"object"`, `toString`/`valueOf` return the
primitive, loose equality compares the primitive value, and
`String.prototype.constructor` is `String`.

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
- `Function.prototype.toString` returns the function's original source text,
  including comments and whitespace. A built-in or bound function reports
  `function name() { [native code] }` (bound functions have no name). A class
  constructor reports the whole `class ... { ... }` definition.

Function objects expose `prototype`, `toString`, `call`, `apply`, and `bind`.
Every prototype has an own `constructor` data property pointing back at its
function — writable, non-enumerable, and configurable, as the specification
requires. Replacing `Foo.prototype` leaves the old prototype's `constructor`
pointing at `Foo`, and a new plain prototype inherits `Object.prototype.constructor`
until it is assigned its own.

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

`Object.is`, `getOwnPropertyNames`, `defineProperty`, `freeze`, `seal`,
`isFrozen`, and `isSealed` are implemented; see
[Built-in coverage](#built-in-coverage) for their exact semantics.

`Object.fromEntries` accepts any iterable of `[key, value]` entries.

### JSON

- `JSON.stringify(value[, replacer[, space]])` supports primitives, arrays,
  nested objects, indentation via a numeric or string `space`, and circular
  reference detection (throws a `TypeError` error object).
- The `replacer` is honoured: a **function** is called with `(key, value)` for
  the root (empty key) and every member, and its result is serialised; an
  **array** restricts which object keys are emitted.
- `toJSON(key)` is called when a value defines it, before the replacer, so
  `Date` and user types can choose their own representation.
- Property values are read **through the property**, so getters run.
- Functions and `undefined` are omitted from objects and become `null` inside
  arrays; a top-level `undefined`/function yields `undefined`.
- `JSON.parse(text[, reviver])` parses RFC 8259-style JSON and throws a
  `SyntaxError` error object with a position on invalid input. With a
  `reviver`, the tree is walked depth-first (children before parents) and the
  reviver is called with `(key, value)` for the root and every member; a
  returned `undefined` deletes the property.

### Map and Set

- `new Map()` / `new Map([[key, value], …])`, `new Set()` /
  `new Set([value, …])`.
- `Map`: `set`, `get`, `has`, `delete`, `clear`, `keys`, `values`, `entries`,
  `forEach`, the `size` getter, and the static `Map.groupBy`.
- `WeakMap`: `set`, `get`, `has`, `delete`, `getOrInsert`,
  `getOrInsertComputed`. `WeakSet`: `add`, `has`, `delete`. Neither is
  iterable and neither has a `size`, because the contents depend on what the
  collector has reclaimed.
- `Set`: `add`, `has`, `delete`, `clear`, `keys`, `values`, `entries`,
  `forEach`, and the `size` getter.
- Keys use SameValueZero: `NaN` equals `NaN`, and `+0`/`-0` are the same key.
- `keys`, `values`, and `entries` return **iterator objects** with `next()`,
  not arrays. `Map` and `Set` are iterable themselves: `for…of` over a `Map`
  yields `[key, value]` pairs and over a `Set` yields its values.
- Lookup remains linear rather than hash-based.

### Date

- `new Date()`, `new Date(ms)`, `new Date("ISO-8601")`, and
  `new Date(year, month, day[, h, m, s, ms])`.
- `Date.now()`, `Date.parse(string)`, `Date.UTC(...)`.
- `getTime`, `valueOf`, `toISOString`, `toUTCString`, `toDateString`,
  `toTimeString`, `toString`, `getTimezoneOffset`, and the UTC/local
  component getters (`getFullYear`, `getMonth`, `getDate`, `getDay`,
  `getHours`, `getMinutes`, `getSeconds`, `getMilliseconds`, and their
  `getUTC*` forms).
- `setTime(ms)` and the component setters (`setFullYear`, `setMonth`,
  `setDate`, `setHours`, `setMinutes`, `setSeconds`, `setMilliseconds`) are
  supported. An out-of-range month or day carries into the next year or month.

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
`URIError`, and so do overlong forms, encoded surrogate halves, truncated
sequences, and code points above U+10FFFF. Encoding a lone surrogate raises
`URIError`, as the spec requires.

Strings are stored as UTF-8, so an unpaired surrogate cannot be represented:
`String.fromCharCode(0xD800)` produces the empty string and the noncharacters
U+FFFE/U+FFFF decode as `?`. Tests that require those code points are excluded
from the focused corpus.

### Timers

`setTimeout`, `clearTimeout`, `setInterval`, and `clearInterval` register
callbacks in a queue owned by the context's heap. The runtime has no wall-clock
event loop: the host must pump the owning context, normally with
`Ctx.PumpTimers()`. `FloriaJSProcessTimers(Ctx.Heap)` remains available as a
compatibility alias. Without a pump, delayed and repeating callbacks do not
execute. A zero-delay callback is queued once, runs exactly once when pumped,
and preserves its callback arguments; `clearTimeout`/`clearInterval` also
cancel work that is due but has not started.

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

### Built-in coverage

Available beyond the earlier sections:

- `Object.is`, `Object.getOwnPropertyNames`, `Object.getOwnPropertyDescriptor`,
  `Object.getOwnPropertyDescriptors`, `Object.getOwnPropertySymbols`,
  `Object.defineProperty`, `Object.defineProperties`, `Object.hasOwn`,
  `Object.groupBy`, `Object.preventExtensions`/`isExtensible`,
  `Object.freeze`/`seal`/`isFrozen`/`isSealed`.
- `Object.prototype.propertyIsEnumerable`, `isPrototypeOf`, and `valueOf`.
- `Array.prototype.flat`, `flatMap`, `fill`, `copyWithin`, `at`, `keys`,
  `entries`, `values`, `findLast`, `findLastIndex`, `toSorted`, `toReversed`,
  `toSpliced`, and `with`.
- `Map.groupBy`, `AggregateError`, `queueMicrotask`, and `structuredClone`.
- `String.fromCharCode` and `String.fromCodePoint`. The latter encodes an
  astral code point as a surrogate pair, matching UTF-16 `length` and indexing.
- `String.prototype.normalize` (NFC/NFD/NFKC/NFKD) and `localeCompare`
  (deterministic code-point order, not locale collation).
- `Number.prototype.toFixed`, `toPrecision`, and `toExponential`, all rounding
  the true binary value, so `(1.005).toFixed(2)` is `"1.00"` and
  `(0.1 + 0.2).toFixed(2)` is `"0.30"`.
- `Math.round` rounds halves toward `+Infinity` (`2.5` → `3`, `-2.5` → `-2`).
- Date component setters: `setFullYear`, `setMonth`, `setDate`, `setHours`,
  `setMinutes`, `setSeconds`, `setMilliseconds`. Out-of-range months and days
  carry into the next year or month, as ECMAScript specifies.
- Symbol-keyed properties are real keys: two symbols with the same description
  are distinct, a symbol key never collides with a string, and symbol-keyed
  properties are non-enumerable (invisible to `Object.keys`, `for…in`, and
  `JSON.stringify`).

### Assignment targets

Only identifiers, member expressions, and destructuring patterns may be
assigned. `1 += 2`, `(a + b) = 1`, and `f() &&= 1` are `SyntaxError`s for every
assignment operator, including plain `=`.

### Functions as values

- `fn.length` is the declared parameter count; `fn.name` is the declared name.
  Both are non-enumerable own properties.
- An anonymous function assigned to an object property takes the property's
  name: `{m: function(){}}` gives `o.m.name === "m"`. An explicitly named
  function keeps its own name.
- `Function(arg1, ..., argN, body)` compiles a function from source at run time,
  and also works with `new`. All but the last argument are parameter names. A
  malformed body throws a `SyntaxError`. The body is compiled in global scope,
  so it does not close over the caller's locals.
- `fn.toString()` returns the original source text, including comments and
  whitespace. Built-in and bound functions report the native placeholder.

### BigInt

- Literals: `123n`, and the radix forms `0x1Fn`, `0b101n`, `0o17n`. A
  fractional or exponent form (`1.5n`, `1e3n`) is a syntax error, as is
  `BigInt(1.5)`.
- Arbitrary precision: values are stored as exact decimal digit strings, so
  `99999999999999999999n + 1n` is exact where a Number would round.
- Arithmetic: `+`, `-`, `*`, `/` (truncating), `%` (sign of the dividend), `**`
  (non-negative exponent), and unary `-`. Division by zero is a `RangeError`.
- Mixing a BigInt with a Number in an arithmetic operator is a `TypeError`, as
  ECMAScript requires; convert explicitly with `BigInt(...)` or `Number(...)`.
- Comparison: two BigInts compare exactly, and `===` requires both sides to be
  BigInts. Loose `==` coerces, so `1n == 1` and `1n == "1"` are `true`.
- `BigInt(value)` converts from a Number (integral only), string, or boolean.
  `typeof` a BigInt is `"bigint"` and `String()` prints the exact digits.

### Generators

- `function* g() { ... }` declares a generator. Calling it does not run the
  body; it returns a generator object.
- The body runs on the first `next()` and suspends at each `yield`, resuming
  where it stopped. `next(v)` makes `v` the result of the suspended `yield`
  expression. Local variables and parameters survive across suspensions.
- `next()` returns `{ value, done }`; a `return` statement completes the
  generator with that value, and `return(v)` completes it early.
- `yield* iterable` delegates, yielding each value of another iterable.
- Generators are iterable, so `for…of g()` drains one, and `yield*` composes
  with it.
- A generator may be resumed by a later script: it keeps its activation
  environment, saved stack, and bytecode alive for as long as it exists.

### Classes

- `class A { ... }` declarations and `var B = class { ... }` expressions.
- `constructor(...)`; methods; `get`/`set` accessors; `static` methods.
- `extends Base` sets `B.prototype`'s prototype to `Base.prototype` and the
  class function's own prototype to `Base`, so instances inherit methods and
  statics are inherited too. `instanceof` works for both the class and the base.
- `super(...)` runs the base constructor with the current receiver;
  `super.method()` calls the base implementation. A derived class without a
  constructor gets an implicit one, which does **not** forward arguments — write
  an explicit constructor when the base needs them.
- Methods and accessors are installed as **non-enumerable** properties, so
  `Object.keys`, `for…in`, and `JSON.stringify` see only the instance's own
  fields.
- Class fields (`class A { x = 1 }`) are **not** supported and are rejected at
  parse time; assign in the constructor instead.

### Errors and promises

- `new Error(msg)`, `new TypeError(msg)`, `new RangeError(msg)`,
  `new ReferenceError(msg)`, `new SyntaxError(msg)`, and `URIError(...)`
  create error objects with `name`, `message`, and `ToString()` =
  `Name: message`. The message argument goes through ToString, so an object
  with a custom `toString` contributes its own text. `message` is an own
  non-enumerable property only when supplied, and `new Error(msg, { cause })`
  installs a non-enumerable `cause`.
- Error objects have proper prototype chains: `err instanceof TypeError`,
  `err.hasOwnProperty(...)`, and inherited `toString()` work.
- The VM throws catchable `TypeError`/`RangeError` objects for property access
  or assignment on `null`/`undefined`, calling a non-function, and exceeding
  the call-depth limit.
- `throw` can throw any value. `catch (e)` receives it.
- `async` functions return promises; `.then`, `.catch`, and `.finally` are
  available on promises and run as microtasks, drained after a script
  completes. `new Promise(executor)` is supported, as are
  `Promise.resolve`/`reject`/`all`/`race`. There is no host event loop, so
  timer-based work still needs an explicit `Ctx.PumpTimers()` call.

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
| Execution engine | Bytecode interpreter with frame slots, object shape tokens, per-site property caches, and AOT FTML binding snippets. No machine-code JIT, full hidden-class transitions, or persistent bytecode cache. | Keeps the runtime embeddable and dependency-free. |
| Timers | Require the host to call `Ctx.PumpTimers()`; no built-in event loop. Timer state is owned by the context's heap, so pumping one context cannot run another context's callbacks. | The host owns the main loop. |
| Strings | Stored as UTF-8, but `length`, indexing, slicing, `charCodeAt`, and `for…of` expose UTF-16 code units. Regular-expression matching still operates on the UTF-8 representation. | Conversion happens at the JS boundary; the internal storage remains compact. |
| `globalThis` | A live global object backed by the root environment. | Global lexical bindings intentionally stay out of the object. |
| `Map`/`Set` storage | Lookup is linear rather than hash-based. | Simplicity; hashing is not scheduled. |
| Regular expressions | Backed by Pascal `RegExpr`; advanced ECMAScript features (lookbehind, named groups, Unicode property escapes) are not guaranteed. `lastIndex` is internal, not a JS property. | Reuses the FPC regex engine instead of shipping one. |
| `Object.freeze` / `seal` | Now update per-property `writable`/`configurable` flags. Frozen objects reject writes, additions, and deletes; sealed objects reject additions and deletes while retaining writability. |
| `Object.defineProperty` | Honours `value`, `writable`, `enumerable`, `configurable`, `get`, and `set`. Existing non-configurable properties cannot be converted between data and accessor forms. Accessor descriptors do not use `writable`. |
| Agents | `$262.agent` runs cooperative single-threaded agents that switch only at explicit agent/Atomics calls; there is no preemptive thread concurrency. `Atomics.waitAsync` waiters are resolved by `Atomics.notify` across agents. |

### Missing features

Everything known to be absent. Nothing here is scheduled; the roadmap's P0–P3
work is complete, so these are deliberate or unplanned gaps rather than pending
work.

| Area | Current behaviour |
| :--- | :--- |
| `Intl` and `alert` | Not defined. Reading them throws `ReferenceError`. |

### Known gaps

| Area | Behaviour |
| :--- | :--- |
| Strict mode | `"use strict"` directives and class bodies enable strict assignment checks: assigning an undeclared name throws `ReferenceError`, duplicate parameters are early errors, legacy octal literals and octal escape sequences are rejected, `delete` of an identifier is rejected, and `eval`/`arguments` bindings are rejected. Strict future reserved words are rejected as identifiers. |
| TDZ | `let`/`const`/`class` bindings are uninitialized from block entry until their declaration. Reading or assigning one early throws `ReferenceError`. `typeof` does not bypass the dead zone. Declarations inside a block are hoisted to that block; see the note below. |
| `var` | Hoisted to function or script root. `let`/`const` are block-scoped. Cross-scope collisions raise `SyntaxError`. |
| Classic `for` with `let`/`const` | Loop bindings are block-scoped and invisible after the loop. Each iteration gets a fresh binding, so closures capture per-iteration values; `var` loop bindings remain function/script scoped. |
| `with` | Supported in sloppy mode; rejected as a `SyntaxError` in strict mode. Primitive objects are boxed. |
| `localeCompare` | Uses deterministic Unicode code-point order after canonical decomposition; it is not locale-sensitive collation. |
| `normalize` | Supports NFC, NFD, NFKC, and NFKD using generated Unicode tables. |
| Loose equality | Objects are converted through `Symbol.toPrimitive` when present, otherwise `valueOf`/`toString`, for `+`, `==`, and relational operators. |
| `for…of` on non-iterables | Throws `TypeError`. |
| Optional chaining | Full chain short-circuiting across member accesses and calls. Grouping boundaries `(a?.b)` terminate the chain. `new a?.b()` and optional-chain assignment/update targets, including parenthesized targets, are rejected as syntax errors. |
| `this` | Top-level `this` is the global object. A plain call of a non-strict function receives the global object; a strict function keeps `this === undefined`. Methods, `new`, and lexical `this` in arrows behave normally. |
| Modules | Real ECMAScript module records: a lexer/parser/AST for `import` and `export`, the five entry lists, `ResolveExport` with star-export ambiguity detection, linking, and cycle-safe evaluation. Link failures are reported as resolution errors, distinct from parse errors, and cover unresolved, missing, and ambiguous imports, unknown import-attribute keys, and a dependency that does not parse. Bindings are live, module bodies run in their own scope, and a host supplies source through a loader callback. `import.meta`, dynamic `import()`, `export *`, `export * as ns`, re-exports, string export names, and import attributes are supported. A namespace is a null-prototype, non-extensible exotic object with data descriptors, `Symbol.toStringTag` `"Module"`, and read-only exports. |
| Proxy | `new Proxy` and `Proxy.revocable` support `get`, `set`, `has`, `deleteProperty`, `ownKeys`, `getOwnPropertyDescriptor`, `apply`, and `construct` traps with the main property invariants, including the `has`-with-`with` rule for non-extensible targets. |
| Realms | `$262.createRealm()` in the diagnostic host creates a genuinely separate context with its own heap, global object, intrinsics, timers, and output. Cross-realm intrinsic selection works for the supported constructors and array species. |

TDZ hoisting is implemented for program bodies, ordinary blocks, function
bodies, `switch` bodies, and the initializer of a classic `for` loop. A
`for…in`/`for…of` binding and a catch parameter are initialized at the point
where the binding is created, so they do not expose a TDZ window.

## Not implemented

Unimplemented syntax and APIs are listed once, in
[Missing features](#missing-features). That table is the authoritative list;
this page does not repeat it, so the two cannot drift apart.

Static `import`/`export` uses real module records inside the engine; the host
chooses how a specifier maps to source through the loader callback.
`$262.createRealm()` and `$262.agent` are available in the diagnostic host;
agents are cooperative and single-threaded.

## Verifying behaviour

- Run `pasbuild test` for the unit suite.
- Run `bash scratch/run_gapscan.sh` for the JavaScript-level probe matrix.
- Run `bash scratch/run_docclaims.sh` to check that the statements on this page
  still match the runtime. Each claim in `scratch/docclaims.pas` asserts one
  documented behaviour, so correcting the docs and adding the claim go
  together.
- When adding a feature, update this page and the [roadmap](roadmap.md).
