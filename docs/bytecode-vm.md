# Bytecode VM

floriajs executes JavaScript through a **bytecode compiler and stack-based
virtual machine**. The old recursive tree-walking evaluator has been retired;
the AST is still the parser's output, but it is compiled to flat bytecode
before execution.

This page explains the VM architecture, the instruction set, the execution
model, and the extension points.

## Pipeline

```text
JavaScript source
       │
       ▼
 TFloriaJSLexer ── tokens ──► TFloriaJSParser
                                  │
                                  ▼
                             AST (floria.js.ast)
                                  │
                                  ▼
                        TFloriaJSCompiler
                                  │
                                  ▼
                    TFloriaJSBytecode chunk
                    (code, constants, locals,
                     arguments, sub-functions)
                                  │
                                  ▼
                           TFloriaJSVM
                    (value stack, call frames,
                     try handlers, environments)
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
           TFloriaJSEnvironment           TFloriaJSHeap
           (lexical scopes)               (values, objects,
                                           prototypes, jobs)
```

`TFloriaJSContext` owns the whole pipeline: a heap, global environment,
bytecode compiler, VM, and console buffer. It compiles and runs a script on
each `Evaluate` call; there is currently no persistent compilation cache.

## Units

| Unit | Responsibility |
| :--- | :--- |
| `floria.js.bytecode` | Opcode enum, instruction record, constant pool, chunks, disassembler. |
| `floria.js.compiler` | AST → bytecode compiler. |
| `floria.js.vm` | Stack machine, call frames, exception handlers, execution loop. |
| `floria.js.compiler` / `.vm` are re-exported by `floriajs` as `TFloriaJSCompiler` and `TFloriaJSVM`. |

## Bytecode chunk

`TFloriaJSBytecode` is both the compiled unit and the function prototype:

```pascal
TFloriaJSInstruction = packed record
  Op: TFloriaJSOpcode;
  Imm: Int32;    // operand: constant index, local slot, jump target, arg count
  Line: Int32;   // source line for diagnostics
end;
```

A chunk contains:

- **Code**: an array of instructions.
- **Constants**: a pool of `TFloriaJSValue` constants (numbers, strings, etc.).
- **Local names**: named local slots (used by compiler temporaries and
  function locals).
- **Argument names**: the function signature.
- **Sub-functions**: nested function chunks created by `opClosure`.
- **Flags**: `IsArrow`, `IsAsync`.
- **Reference count**: `Retain`/`Release`, so closures can outlive the script
  that declared them.

Key methods:

```pascal
function  Emit(AOp: TFloriaJSOpcode; AImm: Int32 = 0; ALine: Int32 = 0): Integer;
procedure PatchJump(AIndex: Integer; ATarget: Integer);
function  AddConstant(const AValue: TFloriaJSValue): Integer;
function  AddStringConstant(const AStr: string): Integer;
function  AddNumberConstant(ANum: Double): Integer;
function  AddLocal(const AName: string): Integer;
function  AddArgument(const AName: string): Integer;
function  AddSubFunction(AFunc: TFloriaJSBytecode): Integer;
function  Disassemble(): string;
```

`Disassemble` is the main inspection tool when debugging the compiler.

## Compiler

`TFloriaJSCompiler` walks the AST and emits bytecode.

```pascal
function CompileProgram(AProgram: TFloriaJSProgram): TFloriaJSBytecode;
function CompileExpression(AExpr: TFloriaJSExprNode): TFloriaJSBytecode;
function CompileFunctionBody(const AName: string; AParams: TStringList;
  ABody: TFloriaJSStmtNode; AIsAsync: Boolean = False;
  AIsArrow: Boolean = False): TFloriaJSBytecode;
```

Coverage:

- **Expressions**: literals, identifiers, unary/binary/conditional,
  assignment/compound assignment, member access (named/computed/optional),
  calls (plain, optional, spread, `new`), arrays/objects (including spread,
  holes, methods, getters/setters), functions/arrows, template interpolation,
  `delete`, `typeof`, `in`, `instanceof`, comma.
- **Statements**: declarations and destructuring, blocks, `if`, classic
  `for`, `for…in`/`for…of`, `while`/`do…while`, `switch`, `try`/`catch`/
  `finally`, `throw`, `return`, `break`/`continue`, labeled statements,
  function declarations.
- **Scopes**: block-scoped `let`/`const` emit `PUSH_ENV`/`POP_ENV`; `var`
  declarations bind in the enclosing function/top-level environment. Classic
  `for` headers with `let`/`const` get an outer loop environment and a fresh
  per-iteration environment for each body execution; `for…in`/`for…of` also
  create per-iteration environments. Function calls get a call environment;
  closures capture it.
- **Control flow**: loops and conditionals emit jumps patched after the body;
  `break`/`continue` are collected per loop context and patched to the right
  targets.
- **Exceptions**: `try` emits `PUSH_TRY`/`POP_TRY` around the protected range,
  with catch/finally targets patched by the compiler.
- **Top-level completion value**: the compiler keeps a hidden `$result` local
  and stores each top-level expression statement into it, matching the
  completion-value behaviour of scripts.

### Locals and environments

The VM has stack local slots, and the compiler uses them for compiler
temporaries and function parameters. User variables are still resolved through
`TFloriaJSEnvironment` (`LOAD_ENV`/`STORE_ENV`/`DEFINE_ENV`) so closures,
`var`/`let` scoping, destructuring, and delegate-object item scopes keep their
current semantics. This is a pragmatic hybrid: bytecode removes AST dispatch
and control-flow recursion, while environments remain the source of truth for
name resolution.

## VM

`TFloriaJSVM` is a stack machine.

```pascal
constructor Create(AHeap: TFloriaJSHeap = nil; AGlobalEnv: TFloriaJSEnvironment = nil);
destructor Destroy(); override;

function Execute(ABytecode: TFloriaJSBytecode;
  AEnv: TFloriaJSEnvironment = nil): TFloriaJSValue;
function CallFunction(const AFuncVal: TFloriaJSValue;
  const AArgs: array of TFloriaJSValue): TFloriaJSValue;
function CallFunction(const AFuncVal: TFloriaJSValue;
  const AArgs: array of TFloriaJSValue;
  const AThisVal: TFloriaJSValue): TFloriaJSValue;
function ConstructObject(const AFuncVal: TFloriaJSValue;
  const AArgs: array of TFloriaJSValue): TFloriaJSValue;

property Heap: TFloriaJSHeap read FHeap;
property GlobalEnv: TFloriaJSEnvironment read FGlobalEnv write FGlobalEnv;
property MaxCallDepth: Integer read FMaxCallDepth write FMaxCallDepth;
```

Internals:

- **Value stack** (`FStack`/`FSP`): operands and temporary values.
- **Call frames** (`FFrames`/`FFP`): bytecode, instruction pointer, base
  stack pointer, `this`, environment, initial environment, ownership flag,
  constructor flag/object.
- **Try handlers** (`FTryHandlers`): catch instruction pointer, frame index,
  stack depth, and environment to restore.
- **Environments**: each frame starts in a call environment (or the supplied
  environment for a binding snippet) and can push child environments for
  blocks.
- **Calls**: `CallFunction` binds arguments, `this`, and `arguments` in a new
  environment, pushes local slots, and runs a nested `RunLoop`. Native
  callbacks are invoked directly.
- **Errors**: `opThrow` and runtime errors call `HandleThrow`, which unwinds
  frames/stack to the nearest `PUSH_TRY` handler. Uncaught values are
  re-raised as `EFloriaJSThrow`.
- **Max call depth**: defaults to 512; exceeding it raises a `RangeError`.

### Instruction set

The opcode enum lives in `floria.js.bytecode`. The main groups are:

| Group | Opcodes |
| :--- | :--- |
| Stack | `NOP`, `POP`, `DUP`, `DUP2`, `SWAP` |
| Constants | `CONST`, `UNDEFINED`, `NULL`, `TRUE`, `FALSE`, `ZERO`, `ONE` |
| Locals | `LOAD_LOC`, `STORE_LOC`, `SET_LOC` |
| Globals/environments | `LOAD_GLOBAL`, `STORE_GLOBAL`, `SET_GLOBAL`, `LOAD_ENV`, `STORE_ENV`, `DEFINE_ENV`, `PUSH_ENV`, `POP_ENV` |
| Objects | `NEW_OBJECT`, `GET_PROP`, `GET_PROP_NAMED`, `SET_PROP`, `SET_PROP_NAMED`, `GET_PROP_OPT`, `GET_PROP_NAMED_OPT`, `DEFINE_GETTER`, `DEFINE_SETTER`, `OBJECT_REST`, `DELETE_PROP`, `IN`, `INSTANCEOF` |
| Arrays | `NEW_ARRAY` |
| Arithmetic | `ADD`, `SUB`, `MUL`, `DIV`, `MOD`, `POWER`, `NEG`, `POS`, `BIT_NOT`, `BIT_AND`, `BIT_OR`, `BIT_XOR`, `SHL`, `SHR`, `SAR` |
| Comparison | `EQ`, `STRICT_EQ`, `NOT_EQ`, `STRICT_NOT_EQ`, `LT`, `LE`, `GT`, `GE` |
| Unary/logic | `NOT`, `TYPEOF`, `VOID`, `AWAIT` |
| Jumps | `JUMP`, `JUMP_IF_FALSE`, `JUMP_IF_TRUE`, `JUMP_IF_NULLISH`, `JUMP_IF_FALSEY_PEEK`, `JUMP_IF_TRUTHY_PEEK` |
| Calls | `CALL`, `CALL_OPT`, `CALL_SPREAD`, `NEW`, `NEW_SPREAD`, `RETURN`, `CLOSURE` |
| Exceptions | `THROW`, `PUSH_TRY`, `POP_TRY` |
| Iteration | `FOR_IN_INIT`, `FOR_OF_INIT` |
| Control | `HALT` |

`FloriaJSOpcodeToString` maps opcodes to names for dumps. Note that some
opcode names are historical; for example `SHR`/`SAR` correspond to the two
right-shift forms in the parser.

## Engine integration

`TFloriaJSContext` exposes:

```pascal
property VM: TFloriaJSVM read FVM;
property Compiler: TFloriaJSCompiler read FCompiler;
property Backend: TFloriaJSExecutionBackend read FBackend write FBackend;
```

The public backend enum is:

```pascal
TFloriaJSExecutionBackend = (fjbInterpreter, fjbBytecodeVM);
```

`fjbBytecodeVM` is the default. `fjbInterpreter` is retained as a
compatibility enum value; the tree-walking evaluator no longer exists, and
both values currently execute through the bytecode VM. `EvaluateBytecode`
(and `TFloriaJSEngine.ExecuteBytecode`) exists as an explicit VM entry point;
`Evaluate` also uses the VM.

`Evaluate` parses and compiles the source each time. If the same script is
executed repeatedly, keep the returned `TFloriaJSBytecode` and call
`VM.Execute` yourself instead of re-parsing.

## FTML integration

- Each reactive binding compiles its expression **once**, when the binding is
  created, and reuses the chunk on every dependency update.
- Signal handlers are compiled lazily on first dispatch and cached on the
  signal entry.
- `TFloriaFTMLBindingManager` holds the VM and compiler and executes binding
  chunks with the item's environment.
- `IFloriaFTMLEngineContext` exposes `GetVM` and `GetCompiler` to items.

See the [FTML guide](ftml.md) and [FTML API](api/ftml.md).

## Performance

The VM replaces recursive AST dispatch with a flat instruction loop, local
slots for temporaries, jump-based control flow, and cached bytecode for
bindings. The roadmap records roughly **3–4×** throughput improvement over the
retired tree-walking evaluator on micro-benchmarks.

It is still a **pure bytecode interpreter**:

- User-variable lookup still walks environments and compares names.
- Property access still uses linear property tables (no hidden classes or
  inline caches).
- Every dispatched instruction is wrapped in a Pascal `try`/`except` block so
  a JavaScript throw can be routed to `HandleThrow`.
- Function calls still allocate a call environment and an `arguments` array.
- There is no JIT, no AOT bytecode cache, and no shape/feedback optimization.

Those are the subjects of the roadmap's later VM phases.

## Debugging and extending

- Use `TFloriaJSBytecode.Disassemble` to inspect emitted code, constants, and
  sub-functions.
- To add an opcode:
  1. Add it to `TFloriaJSOpcode` and `FloriaJSOpcodeToString`.
  2. Emit it from `floria.js.compiler.pas`.
  3. Implement it in the `RunLoop` case in `floria.js.vm.pas`.
  4. Add a VM test in `TFloriaJSVMTest`, then a JavaScript-level test.
- Keep instruction operands in `Imm` (constant index, local slot, jump target,
  or argument count) and keep stack effects consistent with the compiler.
- Treat `TFloriaJSBytecode` as shareable: `Retain` before sharing with a
  function or binding, and `Release` when done.
