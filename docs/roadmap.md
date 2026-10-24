# floriajs — Implementation Roadmap

This roadmap tracks the development of the Floria JS runtime, prioritizing the
resolution of semantic deviations from JavaScript standards, missing syntax
capabilities, and performance optimizations for declarative FTML UI applications.

---

## Current State & Milestone Status

- **Bytecode Virtual Machine Transition**: 100% Completed. The legacy AST
  tree-walking interpreter has been fully retired and removed. All execution,
  reactive bindings, and signal dispatching run exclusively on the flat stack-based
  `TFloriaJSVM`.
- **Core Primitives & Standard Library**: Completed. Comprehensive implementations
  of `Array`, `String`, `Math`, `JSON`, `Map`, `Set`, `Date`, `RegExp`, `Symbol`,
  `URI`, and host timer APIs (`setTimeout`, `setInterval`) are active.
- **Test Suite**: 168 of 168 automated unit tests pass cleanly with 0 errors and 0 failures.

---

## Priority 1 — Semantic Deviations & Core Language Correctness (Completed)

These items address the behavioral differences documented in [`language-support.md`](language-support.md)
that violate JavaScript developer expectations, silently mask syntax errors, or break
common idioms.

### 1.1 Variable Scope & Declaration Integrity

- [x] **`const` Reassignment Rejection**:
  - Track `IsConst: Boolean` in environment bindings (`TFloriaJSEnvironment`).
  - Attempting to reassign or mutate a `const` variable via assignment (`=`, `+=`, etc.)
    or update operators (`++`, `--`) must throw a catchable `TypeError: Assignment to constant variable`.
  - Reject duplicate `let` / `const` declarations in the same scope.
- [x] **`ReferenceError` on Undeclared Identifier Reads**:
  - Reading an unresolvable identifier must throw a catchable `ReferenceError: <name> is not defined`.
  - Exempt the `typeof` unary operator: `typeof undeclaredVar` must continue to yield `'undefined'`.
  - Preserve assignment behavior: assigning to an undeclared identifier in non-strict mode
    creates a property in the global environment.
- [x] **Function Declaration Hoisting**:
  - Implement a compilation pre-pass in `TFloriaJSCompiler` (`CompileProgram`,
    `CompileFunctionBody`, and block bodies) to discover all `TFloriaJSFunctionDecl` nodes.
  - Instantiate and bind function objects in the target environment before any statements
    execute, allowing functions to be invoked prior to their textual definition.

### 1.2 Array & Object Semantic Parity

- [x] **`Array.prototype.toString`**:
  - Provide a dedicated `toString` method on `Array.prototype` that behaves like `join(',')`.
  - Replaces inheritance of `Object.prototype.toString` which incorrectly produces `[object Array]`.
- [x] **Array Enumeration in `for…in`**:
  - Fix `for…in` loops iterating over array objects to enumerate element indices (`'0'`, `'1'`, ...)
    rather than prototype method names (`'push'`, `'pop'`, `'slice'`).
- [x] **`Object.keys`, `values`, and `entries` on Arrays**:
  - Ensure `Object.keys(arr)` includes array element indices (`['0', '1', ...]`).
  - Ensure `Object.values(arr)` yields array values.
  - Ensure `Object.entries(arr)` yields `[['0', val0], ['1', val1], ...]`.
- [x] **Array Index Property Reflection**:
  - Fix `arr.hasOwnProperty(index)` to return `true` for present elements.
  - Ensure `index in arr` returns `false` for array holes.

### 1.3 Function & Parameter Parity

- [x] **Function Prototype Invocation Methods**:
  - Implement `Function.prototype.call(thisArg, ...args)`: invoke function with explicit `this`.
  - Implement `Function.prototype.apply(thisArg, argsArray)`: invoke function with an array of arguments.
  - Implement `Function.prototype.bind(thisArg, ...args)`: return a bound function closure.
  - Expose `Function.prototype` as a shared prototype object.
- [x] **Lexical `arguments` in Arrow Functions**:
  - Arrow functions must not instantiate their own `arguments` array.
  - Accessing `arguments` inside an arrow function must resolve lexically to the enclosing
    standard function's `arguments` object.
- [x] **Constructor Publication on Function Prototypes**:
  - Ensure every user function's `prototype` object exposes a `constructor` property pointing
    back to the function itself (`Foo.prototype.constructor === Foo`).

### 1.4 Lexical & Numeric Parsing Fixes

- [x] **Hexadecimal & Octal Number Parsing**:
  - Fix `Number("0x10")` to return `16` (currently yields `NaN`).
  - Fix `parseInt("010")` to parse with leading zeros without returning `NaN`.
- [x] **Number Formatting for Large Exponents**:
  - Prevent integer formatting overflow when printing large numbers (e.g. `1e20`).

---

## Priority 2 — Ergonomic Operator & Runtime Gaps

Features that complete common JavaScript expressions and streamline promise-based
asynchronous programming.

### 2.1 Operators & Syntax Sugar

- [ ] **`void` Operator**:
  - Add `tkVoid` keyword to `floria.js.lexer.pas`.
  - Parse `void <expr>` as a unary expression that evaluates `<expr>` and discards its result,
    yielding `undefined`.
- [ ] **Logical Assignment Operators**:
  - Implement `&&=` (logical AND assignment): `x &&= y` -> evaluate `y` and assign only if `x` is truthy.
  - Implement `||=` (logical OR assignment): `x ||= y` -> evaluate `y` and assign only if `x` is falsy.
- [ ] **Classic `for` Loop `let` Block Scoping**:
  - Ensure `for (let i = 0; ...; ...)` creates a dedicated outer scope for `i` so it does not
    leak past the loop statement.

### 2.2 Standard Library Polish

- [ ] **`new Promise(executor)` Constructor**:
  - Implement constructor support: `new Promise(function(resolve, reject) { ... })`.
  - Pass native callback functions for `resolve` and `reject` that settle the underlying
    `TFloriaJSPromise`.
- [ ] **`JSON.stringify` `toJSON` Invocation**:
  - Check for and call `toJSON()` on objects (e.g. `Date.prototype.toJSON`) before serialization.
  - Honor the `replacer` argument when provided as a mapping function or key filter array.
- [ ] **`for…of` Iteration for `Map` and `Set`**:
  - Support direct iteration: `for (const [key, value] of myMap)` and `for (const item of mySet)`.

---

## Priority 3 — Syntax Depth & Advanced Language Features

Larger language grammar additions that expand compatibility with modern ES6+ libraries.

### 3.1 Object-Oriented Classes

- [ ] **`class` Declarations and Expressions**:
  - Parse `class Foo { constructor(...) {} method() {} static method() {} }`.
  - Desugar into prototype constructor functions with non-enumerable methods.
  - Subclassing with `class Child extends Parent`: prototype inheritance chain wiring.
  - `super(...)` constructor calls and `super.method(...)` dynamic dispatch.

### 3.2 Metaprogramming & Advanced Syntax

- [ ] **Tagged Template Literals**:
  - Support `tag`string text ${expression}`` syntax.
  - Pass the call site string array as the first argument, followed by evaluated expressions.
- [ ] **Generators (`function*` and `yield`)**:
  - Parse generator functions and `yield` / `yield*` expressions.
  - Bytecode suspension and resumption with stateful generator iterator objects.
- [ ] **Async Iteration (`for await…of`)**:
  - Allow consuming async iterables and promise streams.
- [ ] **`BigInt` Primitive**:
  - Arbitrary-precision integer literal syntax (`12345678901234567890n`) and `BigInt()` constructor.

---

## Priority 4 — Performance & QML V4-Class VM Optimization

Long-term engine optimizations to deliver instant startup, low memory footprint, and
high-frequency evaluation of declarative FTML visual bindings.

### 4.1 64-Bit NaN-Boxed Value Representation

- [ ] **Register-Friendly `TFloriaJSValue` (`QWord`)**:
  - Replace heavy multi-field union records with 64-bit NaN-boxed IEEE 754 representations.
  - Pack doubles, 32-bit integers, booleans, `null`, `undefined`, and heap object pointers
    into a single 64-bit value fitting CPU registers (`RAX`/`RDI`).
  - Reduce value stack memory footprint to 8 bytes per slot.
- [ ] **Shape-Based Hidden Classes (`TFloriaJSShape`)**:
  - Transition objects from dictionary maps to indexed property arrays guided by shared shapes.

### 4.2 FTML Reactive Fast-Path & Inline Caching

- [ ] **Decouple Native FTML Items from Generic Object Dictionaries**:
  - Use native Pascal memory handles for item geometry (`x`, `y`, `width`, `height`).
- [ ] **Specialized Dependency Tracking Bytecode**:
  - Emit specialized opcodes (`OP_GET_PROP_SUBSCRIBE`) in compiled binding snippets
    that record dependencies directly in the binding manager with zero proxy overhead.
- [ ] **Monomorphic Inline Caches**:
  - Cache property lookup offsets at call sites to bypass dictionary lookups for hot properties.

### 4.3 Ahead-of-Time (AOT) & Baseline JIT Compilation

- [ ] **AOT Binding Compilation**:
  - Translate pure arithmetic layout bindings (`width: parent.width * 0.5`) directly into
    native Pascal function pointers during FTML document parsing.
- [ ] **Baseline Machine Code JIT (x86_64, AArch64)**:
  - Generate native machine code for hot loops and animation step functions on supported platforms.

---

## Deliberately Deferred & Pragmatic Embedded Semantics

The following behaviors are intentionally documented trade-offs for an embedded UI scripting
engine and are not scheduled for modification:

1. **UTF-8 Byte String Indexing**:
   - `String.prototype.length` and character indexing operate on native UTF-8 bytes rather
     than UTF-16 code units. This avoids conversion and memory bloat when interacting with
     native Pascal libraries and host visual text components.
2. **`globalThis` as an Isolated Snapshot**:
   - `globalThis` provides references to standard library globals without acting as a live
     proxy to the internal execution environment. This preserves script sandboxing and prevents
     accidental host pollution.
3. **Loose Equality Object Coercion**:
   - Full ECMAScript object-to-primitive coercion for loose equality (`[1] == 1`, `[] == false`)
     is omitted; strict equality (`===`) is the recommended standard.
4. **`with` and `debugger` Statements**:
   - `with` is rejected or treated as an unknown identifier; `debugger` is a no-op.
5. **ES Modules (`import` / `export`)**:
   - Deferred until a host modular package and component loading specification is defined.
