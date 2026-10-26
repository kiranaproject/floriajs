# Development Guide

This guide covers the repository layout, build and test workflow, coding rules,
and the safe way to add language or standard-library features.

## Repository layout

```text
floriajs/
├── docs/                 Documentation (this directory)
├── bench/                Benchmark suite (checked in, with a baseline)
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
./target/TestRunner --suite=TFloriaJSVMTest
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
- language behaviour (`TFloriaJSRuntimeTest`): arithmetic, scopes, loops,
  functions, closures, recursion, host callbacks, console capture, operators,
  arrows, globals, Object, JSON, template interpolation, literal completion,
  iteration statements, parameter/destructuring forms, and async/await;
- bytecode VM: chunks, local variables, jumps, calls, objects, try/catch, and
  compile-and-run;
- Priority 3: Map, Set, Date, Symbol, RegExp, URI, and host globals;
- FTML: item types, compiled bindings, engine loading, anchors/layout,
  lifecycle;
- lifetime/reclamation: loop and recursion heap stability, closures, shared
  AST/bytecode reference counting;
- switch/try-catch, construction (`new`/`this`/prototypes), array methods;
- Priority 1 regressions (`TFloriaJSPriority1Test`): hoisting and declaration
  conflicts, optional-chaining boundaries, array holes and `length` mutation,
  bound-function construction, number formatting/parsing parity, and
  `delete`/`debugger` semantics.

When adding a test:

1. Add `procedure TestSomething();` to the appropriate published section.
2. Implement it using `TFloriaJSEngine` / `TFloriaJSContext` unless you are
   testing an internal layer.
3. Assert on `res.Success` before asserting values, so a parse failure produces
   a useful first failure.
4. If the feature allocates objects, add a lifetime/reclamation assertion or
   extend the leak harness.

## Documentation claims

`scratch/run_docclaims.sh` compiles and runs `scratch/docclaims.pas`, which
asserts the statements in [language support](language-support.md) that are
observable from JavaScript. Each claim records the documented statement, a
script, and the expected result; a mismatch prints `FAIL` with the expected and
actual values and the script exits non-zero.

Run it after any behaviour change that could invalidate the docs:

```bash
bash scratch/run_docclaims.sh
```

The point is that the acceptance criterion for the documentation is "no
statement contradicts the runtime", which is only checkable by running the
statements. When you correct or add a documented behaviour, add or update the
corresponding claim so it cannot silently rot again.

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

## Benchmarks

`bench/` holds the performance suite. Unlike the gap scan it is checked in,
because a measurement is only useful if the same measurement can be repeated.

```bash
bash bench/run_bench.sh            # run and print tables
bash bench/run_bench.sh --save     # also update bench/baseline.txt
bash bench/run_bench.sh --check    # fail on a >20% regression vs the baseline
```

Two programs:

- `bench/bench_js.pas` — VM workloads: loops, calls, property access, strings,
  arithmetic, allocation.
- `bench/bench_ftml.pas` — reactive binding propagation, one to three levels
  deep.

Each workload is **compiled once** and then executed many times, so the figures
describe the interpreter and not the parser. `us/op` is microseconds per loop
iteration or per call, which is comparable across workloads of different sizes.

### Reading the numbers

The reported `us/op` is derived from the **fastest** sample, not the mean or the
median. Interference can only ever make a run slower, so the fastest observed
run is the closest estimate of the work itself. The median and p95 are printed
for context: they move with machine load, and an early version of this suite
reported a 71% swing between two identical runs because it used the median.

`--check` uses a 20% threshold because that is roughly the worst run-to-run
deviation of the stable benchmarks (median deviation is about 3%). Anything
smaller is noise.

## Comparing against Node

`bench/run_compare.sh` runs the same `.js` files under floriajs and under Node,
and reports the ratio:

```bash
bash bench/run_compare.sh            # print the comparison
bash bench/run_compare.sh --save     # also update bench/compare-baseline.txt
bash bench/run_compare.sh --check    # fail on a >25% ratio regression
```

**Why a ratio, not absolute time.** Absolute microseconds depend on the
machine: a baseline from a fast desktop says nothing about a laptop. The ratio
against Node does travel, because both interpreters run on the same hardware in
the same session. That is what makes this comparable across machines.

The workloads live in `bench/workloads/*.js` as real files and are executed by
both engines. `bench/runner/` is a **Pasbuild sub-project** that loads each file
with `ExecuteFile`; `bench/node/run_node.js` loads the same file with `vm`.

### Keeping the two engines honest

Both runners use a fresh context per measurement, one warm-up run, 41 runs, and
report the **fastest**. The comparison refuses to report ratios if the two
engines produced **different results** for a workload: timings from two
interpreters that computed different answers mean nothing. This caught a
deliberately corrupted workload during development.

### Why the runner is a separate Pasbuild project

It declares a dependency on `floriajs`, so it builds the way a host application
does. That dependency resolves to the *installed* copy in
`~/.pasbuild/repository`, which can be stale — an early run reported generators
as unimplemented because the installed units predated them. `run_compare.sh`
therefore compiles the library into `bench/runner/target/units` first, which is
searched before the repository and shadows the stale copy.

### Interleave the engines

Running all of one engine's workloads before the other's biases every ratio by
about 12%, because whichever goes first pays for CPU frequency ramp-up. The
script alternates both the workload order and which engine runs first, which
cancels the bias; run-to-run median deviation is about 5%.

### Two traps this suite hit

Both produced plausible-looking numbers that were wrong by orders of magnitude.
They are worth knowing before adding a workload.

1. **Timing one call instead of the batch.** The calibration measures a batch of
   `N` calls to clear the clock resolution, but the sampling loop originally
   timed a single call while the report divided by `N`. Every figure was
   under-reported by the batch factor — a 240 ns operation printed as 0.3 ns.
   The batch must be what is timed *and* what the divisor describes.

2. **Not collecting between runs.** `TFloriaJSContext.Execute` calls
   `Heap.Collect()` before each script. A benchmark that drives
   `VM.Execute` directly must do the same, or each run leaves its garbage
   behind: the heap grew by about a thousand objects per run and later samples
   were twice as slow as earlier ones.

A third trap is specific to the FTML benchmark: writing the **same** value to a
property short-circuits the update path and costs about a seventh of a real
change. The workload therefore always writes a new value, and the program
asserts that the binding actually propagated — otherwise the timings could
describe a no-op.

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
   - Map/Set: `floria.js.collections.pas`
   - Date/Symbol/RegExp/URI/timers: their matching `floria.js.*` unit
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
   a predicate/callback (`map`, `sort`, `forEach`, …). Never call the VM
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
4. **Compiler** (`floria.js.compiler.pas`): add the AST node case and emit
   bytecode. Decide whether it can be expressed with existing opcodes or needs
   a new one.
5. **VM** (`floria.js.vm.pas`): implement any new opcode in the `RunLoop` case.
6. **Tests and probes**: cover both the happy path and error/edge cases.
7. **Docs**: update [language support](language-support.md), the
   [roadmap](roadmap.md), and any API page.

Watch for parser regressions: an operator that is added to the precedence table
but not handled in the Pratt `case` is silently consumed, producing a
plausible but wrong result. Always add a probe that checks the actual value,
not merely successful parsing.

## Adding a VM opcode

1. Add the opcode to `TFloriaJSOpcode` and `FloriaJSOpcodeToString` in
   `floria.js.bytecode.pas`.
2. Emit it from the compiler and, if it jumps, use `PatchJump`.
3. Implement it in the `RunLoop` `case` in `floria.js.vm.pas`, keeping stack
   effects consistent.
4. Add a `TFloriaJSVMTest` case that compiles source and checks the result,
   plus a JavaScript-level test.
5. Update [Bytecode VM](bytecode-vm.md#instruction-set) and the disassembly
   expectations.

Bytecode chunks are reference-counted. If a new owner keeps a chunk (function,
binding, signal cache), call `Retain` and release it when done.

## Memory and lifetime checklist

The runtime uses reference counting plus safe-point collection, so leaks and
dangling pointers are the main risks.

- **Retain what you store.** `SetProperty`, `Push`, environment `Define`, and
  FTML property setters already retain.
- **Release what you remove.** Use `DeleteProperty`, `Pop`, `SetElement`
  replacements, or call `JSReleaseValue` when detaching a raw value.
- **Do not free AST nodes manually** if they can be shared. Function bodies use
  `Retain`/`Release`.
- **Bytecode chunks are reference-counted.** Functions, bindings, and signal
  caches retain their chunks; producers release their own reference.
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
