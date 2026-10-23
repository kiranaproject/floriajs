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

## Baseline at the time of writing

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
- closures, block scoping for `let`, recursion and environment reclamation

## Two kinds of gaps

1. **Hard gaps** — the parser or lexer rejects the syntax. Easy to notice.
2. **Silent gaps** — the syntax is accepted but the runtime is missing the
   behaviour. Examples:
   - `[1,2,3].join("-")` → `undefined`
   - `var a = [1]; a.push(2); a.length` → `1`
   - `Math.sign(-3)` → `undefined`
   - `parseInt("10", 2)` → `10` (the radix is ignored)
   - `` `v=${n + 1}` `` → the literal text `v=${n + 1}`

Priority is therefore given to closing silent gaps first, then to syntax that
unlocks idiomatic modern JavaScript.

---

## Priority 1 — Everyday JavaScript

These items are prerequisites for writing ordinary scripts without workarounds.
They are also what FTML handlers and UI bindings are most likely to use.

### 1. Array methods

Status: not exposed. `TFloriaJSArray` has Pascal-side `Push`, `Pop`, `Shift`,
`Unshift` and `Join`, but no JavaScript-visible methods. Every method call
currently returns `undefined` because the property is missing.

- [ ] `push`, `pop`, `shift`, `unshift`
- [ ] `join`, `concat`, `reverse`, `sort` (with optional comparator)
- [ ] `indexOf`, `lastIndexOf`, `includes`
- [ ] `slice`, `splice`
- [ ] `map`, `filter`, `reduce`, `forEach`, `some`, `every`, `find`
- [ ] `Array.isArray`, `Array.from`
- [ ] Correct array length/assignment behaviour while the methods run

Touch points: `src/main/pascal/floria.js.value.pas` (`TFloriaJSArray.GetProperty`),
`src/main/pascal/floria.js.stdlib.pas`, `src/main/pascal/floria.js.evaluator.pas`
(callback invocation with the right `this`).

### 2. String methods

Status: not exposed. `GetMemberValue` in the evaluator only handles `length` and
numeric indexing; every other property is `undefined`.

- [ ] `charAt`, `charCodeAt`
- [ ] `indexOf`, `lastIndexOf`, `includes`, `startsWith`, `endsWith`
- [ ] `slice`, `substring`, `substr`
- [ ] `toUpperCase`, `toLowerCase`
- [ ] `trim`, `trimStart`, `trimEnd`
- [ ] `split`
- [ ] `replace` / `replaceAll` (string patterns first; regex later)
- [ ] `concat`, `repeat`, `padStart`, `padEnd`

Touch points: `src/main/pascal/floria.js.evaluator.pas` (`GetMemberValue`) and a
string helper module or extension of `floria.js.stdlib.pas`.

### 3. Standard globals

Status: mostly missing. These are one-line definitions but their absence makes
basic coercion and comparisons fail.

- [ ] `NaN`, `Infinity`
- [ ] `Number()`, `String()`, `Boolean()` constructors and conversions
- [ ] `Number.isNaN`, `Number.isFinite`, `Number.parseInt`, `Number.parseFloat`
- [ ] `globalThis`
- [ ] `arguments` inside function calls
- [ ] Fix `parseInt` to honour the radix argument
- [ ] Fix `parseFloat` (currently raises *Invalid floating point operation* on
      partially numeric input such as `"3.5x"`)

### 4. Object utilities

- [ ] `Object.keys`, `Object.values`, `Object.entries`
- [ ] `Object.assign`, `Object.create`
- [ ] `hasOwnProperty` on objects
- [ ] `Function.prototype.toString` (at least a stable placeholder)
- [ ] Keep the existing prototype-chain lookup working for objects made with
      `Object.create`

### 5. JSON

- [ ] `JSON.stringify` for primitives, arrays, objects, nested values
- [ ] `JSON.parse`
- [ ] Round-trip tests, including `undefined`/function properties being omitted

JSON is a common way for host integrations to exchange data, so it is grouped
with Priority 1 despite being a larger item.

### 6. Arrow functions

Status: hard gap. The parser has an `tkArrow` hook, but it currently builds a
plain binary node instead of a function.

- [ ] `x => expression`
- [ ] `(x, y) => expression`
- [ ] `(x) => { statements }`
- [ ] Lexical `this` (arrow functions must not rebind `this`)
- [ ] Interaction with the existing closure and environment reclamation rules

### 7. Template literal interpolation

Status: silently wrong. `` `v=${n + 1}` `` evaluates to the literal string.

- [ ] Parse `${...}` sections inside template strings
- [ ] Evaluate the embedded expressions and concatenate the results
- [ ] Keep plain template strings working
- [ ] Tagged templates are a Priority 3 item and stay out of this step

### 8. Object and array literal completion

- [ ] Object shorthand: `{ x }`
- [ ] Computed keys: `{ [k]: value }`
- [ ] Object spread: `{ ...source }`
- [ ] Array spread: `[0, ...items]`
- [ ] Array holes: `[1, , 3]` with the expected `length`
- [ ] Object methods: `{ f() { ... } }`
- [ ] Getters/setters (`get x()` / `set x(v)`) — can follow after methods

### 9. Iteration statements

- [ ] `for...of` over arrays and strings
- [ ] `for...in` over enumerable keys
- [ ] `for (const x of ...)` and `for (let x of ...)`
- [ ] `for (const i = 0; ...; ...)` in classic `for` loops (currently a parse
      error)
- [ ] `break`/`continue` inside the new loops

### 10. Function parameter forms

- [ ] Default parameters: `function f(a = 3)`
- [ ] Rest parameters: `function f(...args)`
- [ ] Destructuring parameters: `function f({ a })` / `([a, b])`
- [ ] Destructuring declarations: `var { a } = obj;` / `var [a, b] = arr;`

---

## Priority 2 — Correctness and common idioms

These items mostly affect semantics rather than enabling new syntax.

### 11. Silent operator gaps

- [ ] `in` returns a real boolean instead of `undefined`
- [ ] `instanceof` returns a real boolean, using the prototype chain
- [ ] Optional chaining: `a?.b`, `a?.[k]`, `a?.()`
- [ ] Nullish assignment: `??=`
- [ ] Power assignment: `**=`
- [ ] Comma operator: `(a, b)`
- [ ] Labeled `break` / `continue`

### 12. Error handling polish

- [ ] `TypeError`, `RangeError`, `ReferenceError` constructor objects
- [ ] Throwing a `TypeError` from the runtime where JavaScript requires it
      (see the cross-cutting item below)
- [ ] Error `name`, `message`, and `toString()` behaviour matching JavaScript

### 13. Math extensions

- [ ] `Math.log2`, `Math.log10`, `Math.sign`, `Math.hypot`
- [ ] `Math.cbrt`, `Math.imul`, `Math.clz32` (lower priority)
- [ ] Keep the existing `Math` constants and functions unchanged

### 14. Numeric and lexer gaps

- [ ] Numeric separators: `1_000_000`
- [ ] Confirm exponent notation and hex/octal/binary literals in edge cases

---

## Priority 3 — Advanced and host-oriented features

These are valuable for completeness and for richer host integration, but they
are not on the critical path for ordinary UI scripts.

### 15. Collections and data types

- [ ] `Map`
- [ ] `Set`
- [ ] `Date` (at least `now()` and basic construction/formatting)
- [ ] `Symbol` (at least well-known symbols used by the host API)
- [ ] `BigInt` (only if host interop needs it)

### 16. Regular expressions

- [ ] Regex literals: `/ab+c/i`
- [ ] `RegExp` constructor
- [ ] `test`, `exec`
- [ ] Regex-aware `String.replace` / `split` / `match`

### 17. Syntax depth

- [ ] `class` syntax (currently silently ignored — `class A {} 1;` returns `1`)
- [ ] Generators: `function*` and `yield`
- [ ] Tagged template literals
- [ ] Async iteration (`for await`)
- [ ] `import` / `export` (only if a module system is in scope)

### 18. Host-provided globals

- [ ] `setTimeout` / `clearTimeout` (bridge to the existing promise job queue)
- [ ] `encodeURIComponent` / `decodeURIComponent`, `encodeURI` / `decodeURI`
- [ ] Any UI-specific globals belong in the host adapter, not the core language

---

## Cross-cutting work

### Make invalid operations throw instead of returning `undefined`

Currently `var o = {}; o.nope();` and `var o; o.nope;` both return `undefined`
without an error. This is why dozens of missing standard-library methods looked
like passing probes. Changing these to throw `TypeError` is closer to JavaScript
and makes future gaps immediately visible.

- [ ] Calling a non-function throws `TypeError`
- [ ] Property access on `null` / `undefined` throws `TypeError`
- [ ] Setting a property on `null` / `undefined` throws `TypeError`
- [ ] Audit existing tests, examples, and FTML engine code for scripts that
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

---

## Deliberately deferred

- `with` — accepted and ignored today; not worth implementing.
- `debugger` — accepted and ignored; that is acceptable.
- `import` / `export` — only if a module system becomes a requirement.
- Full ECMAScript conformance — the goal is a practical embedded runtime, not
  spec completeness.
