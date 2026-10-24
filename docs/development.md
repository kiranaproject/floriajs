# Development Guide

This guide covers the repository layout, build and test workflow, coding rules,
and the safe way to add language or standard-library features.

## Repository layout

```text
floriajs/
├── docs/                 Documentation (this directory)
├── examples/             Compilable Pascal examples
├── scratch/              Local gap-scan harnesses (ignored by Git)
├── src/
│   ├── main/pascal/      Library units
│   └── test/pascal/      fpcunit test runner
├── target/               Build output (ignored)
├── project.xml           PasBuild descriptor
├── build.sh              Convenience wrapper
├── README.md             Project overview
└── GEMINI.md             Coding rules summary
```

Everything under `scratch/` and `target/` is ignored. Generated example
binaries are also ignored.

## Build commands

```bash
pasbuild compile      # compile the library
pasbuild test         # compile and run target/TestRunner
pasbuild install      # install into the local PasBuild repository
pasbuild clean        # remove build output
./build.sh examples   # compile examples with FPC directly
```

The test binary is `target/TestRunner`; PasBuild invokes it with
`--all --format=plain`. You can run it directly for a subset:

```bash
./target/TestRunner --list
./target/TestRunner --suite=TFloriaJSEvaluatorTest
```

If the FPU raises `Invalid floating point operation` on numeric edge cases,
remember that the test runner calls
`SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision])`.
Native code that performs floating-point work should mask exceptions at the
appropriate boundary if it relies on `NaN`/`Infinity` propagation.

## Test suite

`src/test/pascal/TestRunner.pas` uses fpcunit. Test classes are registered at
the bottom of the file. Published methods are discovered automatically.

Current suites cover:

- types, engine/context lifecycle, lexer, AST, parser;
- values and object/array primitives;
- evaluator: arithmetic, scopes, loops, functions, closures, recursion,
  host callbacks, console capture, operators, arrows, globals, Object, JSON,
  template interpolation, literal completion, iteration statements, and
  parameter/destructuring forms;
- FTML: item types, bindings, engine loading, anchors/layout, lifecycle;
- lifetime/reclamation: loop and recursion heap stability, closures, shared
  AST reference counting;
- switch/try-catch, construction (`new`/`this`/prototypes), array methods.

When adding a test:

1. Add `procedure TestSomething();` to the appropriate published section.
2. Implement it using `TFloriaJSEngine` / `TFloriaJSContext` unless you are
   testing an internal layer.
3. Assert on `res.Success` before asserting values, so a parse failure produces
   a useful first failure.
4. If the feature allocates objects, add a lifetime/reclamation assertion or
   extend the leak harness.

## Gap scan

`scratch/run_gapscan.sh` compiles and runs `gapscan.pas` and `gapscan2.pas`
against `src/main/pascal`. Each probe prints `OK -> <value>` or
`ERR -> <message>`.

```bash
bash scratch/run_gapscan.sh
```

Use it to:

- verify that a feature is reachable from JavaScript (not just from Pascal),
- find silent gaps where syntax parses but the result is `undefined` or wrong,
- confirm that a fix did not change unrelated probes.

Add a probe for every user-visible feature. The files are ignored, but they are
the working record behind the [roadmap](roadmap.md). A probe that merely
returns a plausible value is not enough: check the expected value in the
script, as several old probes printed “OK” for silent no-ops.

## Coding conventions

The authoritative rules are in
[`.agents/rules/floria_development.md`](../.agents/rules/floria_development.md)
and [GEMINI.md](../GEMINI.md). In short:

- `project.xml` is the only project descriptor. Never add `pasbuild.json`.
- Every zero-parameter procedure/function/constructor/destructor and call site
  uses empty parentheses: `procedure Reset();`, `Engine.Free();`.
- Units use dotted namespaces (`floria.js.*`, `floria.ftml.*`).
- Types use `T`, interfaces `I`, private fields `F`, arguments `A`, constants
  `ALL_CAPS_WITH_UNDERSCORES`.
- Private fields and methods are PascalCase.
- Public APIs evolve additively.
- Comments are Pascal comments. **Do not put a `{` inside a `{ … }` comment**:
  FPC supports nested comments, so an unmatched brace in the text silently
  swallows following code. Prefer words (“left brace”) over literal braces.

## Adding a built-in function

1. **Pick the layer.**
   - Arrays: `floria.js.arrays.pas`
   - Strings: `floria.js.strings.pas`
   - Object/global utilities: `floria.js.objects.pas`
   - JSON: `floria.js.json.pas`
   - Everything else: `floria.js.stdlib.pas`
2. **Follow the callback signature.**

   ```pascal
   function JSMyMethod(const AArgs: array of TFloriaJSValue;
     AThis: TFloriaJSValue): TFloriaJSValue;
   ```

   For methods that need heap access, use `AThis` (a method is stored on an
   object/function whose `Heap` is set) or create a helper object with a heap
   field registered through `AHeap.OwnHelper`.
3. **Use the runtime helpers** (`JSAdd`, `JSEqual`, `ToNumber`, `ToString`, …)
   instead of ad-hoc coercion.
4. **Call back into JavaScript** with `AHeap.InvokeFunction` when a method takes
   a predicate/callback (`map`, `sort`, `forEach`, …). Never call the evaluator
   directly from a stdlib unit.
5. **Register it** in the relevant `FloriaJSRegister*` procedure. For prototype
   methods, install on `AHeap.GetArrayPrototype()` or
   `AHeap.GetStringPrototype()`; for statics, attach to the constructor object.
6. **Test it** from JavaScript through `TFloriaJSEngine` and add a gap-scan
   probe.
7. **Check lifetime:** if the method stores objects in properties or arrays,
   rely on `SetProperty`/`Push` to retain them. If it removes them, ensure the
   old reference is released.
8. **Document it** in [language support](language-support.md) and, if it is a
   public Pascal API, in the relevant API page.

## Adding syntax

Typical flow:

1. **Lexer** (`floria.js.lexer.pas`): add or reuse a token kind, scan the
   operator/keyword, and add it to `TokenKindToString`.
2. **AST** (`floria.js.ast.pas`): reuse an existing node where possible. Add a
   node only when the shape is genuinely new. Update the visitor interface if
   you add a node.
3. **Parser** (`floria.js.parser.pas`): add the precedence to
   `GetInfixPrecedence`, handle the token in the Pratt loop or in a statement
   parser, and preserve right/left associativity.
4. **Evaluator** (`floria.js.evaluator.pas`): implement the runtime semantics,
   including short-circuiting and reference-count-safe value handling.
5. **Tests and probes**: cover both the happy path and error/edge cases.
6. **Docs**: update [language support](language-support.md), the
   [roadmap](roadmap.md), and any API page.

Watch for parser regressions: an operator that is added to the precedence table
but not handled in the Pratt `case` is silently consumed, producing a
plausible but wrong result. Always add a probe that checks the actual value,
not merely successful parsing.

## Memory and lifetime checklist

The runtime uses reference counting plus safe-point collection, so leaks and
dangling pointers are the main risks.

- **Retain what you store.** `SetProperty`, `Push`, environment `Define`, and
  FTML property setters already retain.
- **Release what you remove.** Use `DeleteProperty`, `Pop`, `SetElement`
  replacements, or call `JSReleaseValue` when detaching a raw value.
- **Do not free AST nodes manually** if they can be shared. Function bodies use
  `Retain`/`Release`.
- **Pin host-facing object values.** `EvaluateValue`/`Call` pin; the host
  unpins with `ReleaseValue`.
- **Avoid cycles.** The collector does not trace cycles. Do not add
  back-references such as `prototype.constructor` unless you also provide a
  cycle-breaking mechanism.
- **Keep heaps and values together.** Do not pass `TFloriaJSValue` from one
  heap/context to another.
- **Release before `Reset`/destruction** and do not call `Heap.Clear` while
  host objects from that heap are still referenced.
- **Run the lifetime suites** after changes to functions, closures, blocks, or
  loops.

## Roadmap and docs maintenance

- [roadmap.md](roadmap.md) is the prioritised feature list. Tick items only
  after a test and a gap-scan probe pass.
- [language-support.md](language-support.md) is the user-facing truth. Update
  it whenever behaviour changes, including silent deviations.
- Keep examples compiling: `./build.sh examples`.
- Use conventional commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`) and
  keep unrelated changes in separate commits.
- Version constants live in `floria.js.types` and `project.xml`; update both
  together for a release.
