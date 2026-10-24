# Engine and Context API

The public façade is `floria.js.core` (re-exported by the umbrella unit
`floriajs`):

```pascal
uses floriajs;
```

## Constants and result types

From `floria.js.types`:

```pascal
const
  FLORIA_JS_VERSION_MAJOR = 0;
  FLORIA_JS_VERSION_MINOR = 0;
  FLORIA_JS_VERSION_PATCH = 1;
  FLORIA_JS_VERSION_STRING = '0.0.1-SNAPSHOT';

  FLORIA_JS_OK            = 0;
  FLORIA_JS_ERROR_GENERIC = -1;
  FLORIA_JS_ERROR_SYNTAX  = -2;
  FLORIA_JS_ERROR_TYPE    = -3;
  FLORIA_JS_ERROR_TIMEOUT = -4;
```

```pascal
type
  TFloriaJSType = (
    fjstUndefined, fjstNull, fjstBoolean, fjstNumber,
    fjstString, fjstObject, fjstArray, fjstFunction,
    fjstSymbol, fjstError
  );

  TFloriaJSResult = record
    Success: Boolean;
    ResultType: TFloriaJSType;
    StringValue: string;
    NumberValue: Double;
    BooleanValue: Boolean;
    ErrorMessage: string;
  end;

function FloriaJSMakeOkResult(const AStringVal: string = ''): TFloriaJSResult;
function FloriaJSMakeErrorResult(const AErrorMsg: string): TFloriaJSResult;
```

`TFloriaJSResult` is a plain value; it does not own a JavaScript object. The
`Evaluate` path copies only primitive projections of the result value into the
record.

## `TFloriaJSEngine`

```pascal
constructor Create();
destructor Destroy(); override;

procedure Initialize(); virtual;
function  CreateContext(const AName: string = ''): TFloriaJSContext;
procedure DestroyContext(AContext: TFloriaJSContext);

function  Execute(const AScript: string): TFloriaJSResult; virtual;
function  ExecuteValue(const AScript: string): TFloriaJSValue; virtual;
function  ExecuteBytecode(const AScript: string): TFloriaJSResult; virtual;
procedure ReleaseValue(const AValue: TFloriaJSValue); virtual;
procedure RegisterFunction(const AName: string; AProc: TFloriaJSNativeProc);

property Initialized: Boolean read FInitialized;
property DefaultContext: TFloriaJSContext read FDefaultContext;
property MemoryLimit: NativeUInt read FMemoryLimit write FMemoryLimit;
property Backend: TFloriaJSExecutionBackend read GetBackend write SetBackend;
```

### Construction and contexts

- `Create` allocates the engine and immediately calls `Initialize`.
- `Initialize` is idempotent. It creates the default context named `default`.
- `CreateContext` creates an independent context. An empty name becomes
  `context_<n>`, where `<n>` is the number of contexts currently tracked.
  Contexts are owned by the engine.
- `DestroyContext` removes the context from the engine and frees it. If it was
  the default context, `DefaultContext` becomes `nil`.
- `Destroy` frees every context still tracked by the engine.
- Creating the default context also installs the standard library on it.

```pascal
Engine := TFloriaJSEngine.Create();
try
  A := Engine.DefaultContext;
  B := Engine.CreateContext('sandbox');
  try
    B.Evaluate('var x = 1;');
    // A.Evaluate('x;') -> undefined (separate globals)
  finally
    Engine.DestroyContext(B);
  end;
finally
  Engine.Free();
end;
```

Do not call `Free` on a context that the engine still tracks.

### `Execute` and `ExecuteValue`

These forward to `DefaultContext`:

- If no default context exists, `Execute` returns an error result with
  “No active execution context”, and `ExecuteValue` returns `undefined`.
- Otherwise they behave exactly like `TFloriaJSContext.Evaluate` and
  `EvaluateValue` (see below).
- `ReleaseValue` forwards to the default context's `ReleaseValue`.
- `ExecuteBytecode` is the explicit VM entry point; it currently produces the
  same result as `Execute` because `Evaluate` always uses the bytecode VM.
- `Backend` selects between `fjbInterpreter` and `fjbBytecodeVM`. The
  tree-walking interpreter has been removed; both values currently execute
  bytecode. `fjbInterpreter` is retained for source compatibility.

### `RegisterFunction`

Installs a free native function in the default context's global scope:

```pascal
function Add(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(AArgs[0].ToNumber() + AArgs[1].ToNumber());
end;

Engine.RegisterFunction('add', @Add);
Engine.Execute('add(2, 3);');   // Success, StringValue = "5"
```

It is a no-op when there is no default context.

### `MemoryLimit`

The property is stored and defaults to 64 MiB, but the current runtime does not
enforce it. Treat it as reserved for a future allocation policy.

## `TFloriaJSContext`

```pascal
constructor Create(AEngine: TFloriaJSEngine; const AName: string = 'global');
destructor Destroy(); override;

procedure SetVariable(const AKey, AValue: string);
function  GetVariable(const AKey: string): string;
function  HasVariable(const AKey: string): Boolean;

procedure SetGlobal(const AName: string; const AValue: TFloriaJSValue);
function  GetGlobal(const AName: string): TFloriaJSValue;
procedure RegisterFunction(const AName: string; AProc: TFloriaJSNativeProc);
procedure RegisterMethod(const AName: string; AMethod: TFloriaJSNativeMethod);

function  Evaluate(const AScript: string): TFloriaJSResult; virtual;
function  EvaluateValue(const AScript: string): TFloriaJSValue; virtual;
function  EvaluateBytecode(const AScript: string): TFloriaJSResult; virtual;
function  Call(const AFuncName: string; const AArgs: array of TFloriaJSValue): TFloriaJSValue; virtual;
procedure ReleaseValue(const AValue: TFloriaJSValue); virtual;
procedure Reset(); virtual;

property Engine: TFloriaJSEngine read FEngine;
property Name: string read FName write FName;
property Heap: TFloriaJSHeap read FHeap;
property GlobalEnv: TFloriaJSEnvironment read FGlobalEnv;
property VM: TFloriaJSVM read FVM;
property Compiler: TFloriaJSCompiler read FCompiler;
property Backend: TFloriaJSExecutionBackend read FBackend write FBackend;
property Output: TStringList read FOutput;
```

A context owns:

- a `TFloriaJSHeap`,
- a global `TFloriaJSEnvironment` tracked by that heap,
- a `TFloriaJSCompiler`,
- a `TFloriaJSVM` bound to the heap and global environment,
- a `TStringList` console buffer (`Output`),
- the standard library installation.

The constructor accepts `AEngine = nil`; this is useful for standalone use or
when another object manages the context (the FTML engine does this when it
creates its own context). It defaults to the bytecode backend.

### Variables and globals

- `SetVariable` / `GetVariable` are string convenience wrappers around
  `SetGlobal` / `GetGlobal`.
- `GetVariable` returns an empty string when the name is not defined.
- `HasVariable` checks the global environment chain.
- `SetGlobal` defines or replaces a global binding.
- `GetGlobal` returns `undefined` for an unknown name.
- `RegisterFunction` / `RegisterMethod` install callable globals. A method
  callback receives `Self` implicitly; a function callback does not.

```pascal
Ctx.SetVariable('app_name', 'FloriaJS');
Ctx.SetGlobal('answer', JSMakeNumber(42));

WriteLn(Ctx.GetVariable('app_name'));      // FloriaJS
WriteLn(Ctx.GetGlobal('answer').ToString()); // 42
```

### `Evaluate`

```pascal
function Evaluate(const AScript: string): TFloriaJSResult;
```

- Empty or whitespace-only input returns a successful result with an empty
  string.
- It parses the script, compiles it to a `TFloriaJSBytecode` chunk, and
  executes that chunk on `VM` in the global environment. The chunk is released
  after execution; there is no automatic bytecode cache.
- Any parser error or runtime exception is caught and reported through
  `Success = False` and `ErrorMessage`.
- On success the record receives `ResultType` (the value kind),
  `StringValue` (`val.ToString()`), `NumberValue` (`val.ToNumber()`), and
  `BooleanValue` (`val.ToBoolean()`). These projections can lose information
  for objects; use `EvaluateValue` when you need the real value.

```pascal
Res := Ctx.Evaluate('1 + 2;');
if Res.Success then
  WriteLn(Res.StringValue);    // 3
```

### `EvaluateBytecode`

```pascal
function EvaluateBytecode(const AScript: string): TFloriaJSResult;
```

Explicitly selects `fjbBytecodeVM` for the duration of the call and delegates
to `Evaluate`. Since the tree-walking evaluator has been removed, this is
currently equivalent to `Evaluate`; it exists for hosts that want a clear
backend intent and for compatibility with code written during the migration.

To avoid re-parsing and re-compiling, compile directly with `Ctx.Compiler`
and run the chunk with `Ctx.VM.Execute`:

```pascal
Parser := TFloriaJSParser.Create('1 + 2;');
try
  Prog := Parser.ParseProgram();
  try
    Code := Ctx.Compiler.CompileProgram(Prog);
    try
      Value := Ctx.VM.Execute(Code, Ctx.GlobalEnv);
    finally
      Code.Release();
    end;
  finally
    Prog.Free();
  end;
finally
  Parser.Free();
end;
```

### `EvaluateValue`

```pascal
function EvaluateValue(const AScript: string): TFloriaJSValue;
```

- Same execution path, but exceptions propagate to the caller.
- Object results are pinned before being returned. Call `ReleaseValue` when
  you no longer need the value.
- Primitive results need no release.

```pascal
Value := Ctx.EvaluateValue('[1, 2, 3]');
try
  WriteLn(Value.AsArray().Join('-'));
finally
  Ctx.ReleaseValue(Value);
end;
```

If you forget to release a pinned object it will not be reclaimed until the
context is reset or destroyed. That is safe, but it is a leak for long-lived
contexts.

### `Call`

```pascal
function Call(const AFuncName: string;
  const AArgs: array of TFloriaJSValue): TFloriaJSValue;
```

- Looks the name up in the global environment and requires a function value.
  Non-functions and missing names return `undefined`.
- Calls with `this = undefined`.
- Object results are pinned, like `EvaluateValue`.

```pascal
Ctx.Evaluate('function sum(a, b) { return a + b; }');
Result := Ctx.Call('sum', [JSMakeNumber(20), JSMakeNumber(22)]);
try
  WriteLn(Result.ToNumber());   // 42
finally
  Ctx.ReleaseValue(Result);
end;
```

### `ReleaseValue`

Unpins an object previously returned by `EvaluateValue` or `Call`. It does
nothing for primitive values. Do not release a value twice, and do not release
values you did not receive from the context.

Values obtained directly from `GetGlobal` are not pinned by that call; they are
kept alive only while the global binding exists. If you need to keep one beyond
the binding's lifetime, pin it yourself with `Value.ObjVal.Pin` and later
`Unpin`.

### `Reset`

```pascal
procedure Reset();
```

Clears the heap (objects and tracked environments), resets the VM stacks,
clears `Output`, recreates the global environment, and reinstalls the standard
library. Pinned values from before the reset become invalid. Release them
before calling `Reset`.

### `Output`

`console.log`, `console.warn`, and `console.error` append to `Output`:

| Call | Entry |
| :--- | :--- |
| `console.log(a, b)` | `a b` |
| `console.warn(a)` | `[WARN] a` |
| `console.error(a)` | `[ERROR] a` |

Arguments are space-joined using `ToString`. If the standard library was
installed without a log list (for example when calling
`FloriaJSRegisterStdLib` directly with `nil`), entries are written to standard
output/error instead.

The sink is process-wide and is rebound by each standard-library installation;
with several contexts, the most recently created/registered context receives
console output.

### Timers

`setTimeout`, `clearTimeout`, `setInterval`, and `clearInterval` are installed
by the standard library, but the runtime does not run a wall-clock event loop.
The host must call:

```pascal
procedure FloriaJSProcessTimers(AHeap: TFloriaJSHeap);
```

periodically (for example from the UI event loop). Timer state is currently
process-wide, so use one timer queue per process or add host-side isolation if
you embed several independent contexts.

## Error objects and exceptions

The runtime defines `EFloriaJSThrow`, an exception carrying a `TFloriaJSValue`.
`throw` raises it, and `catch` binds the carried value. If a throw escapes the
top level, `Evaluate` turns it into an error result; `EvaluateValue` lets it
escape.

Standard error constructors are available to scripts:

```javascript
new Error("plain");
new TypeError("wrong type");
new RangeError("out of range");
new ReferenceError("missing name");
new SyntaxError("bad syntax");
```

`URIError` is additionally provided by the URI support. Error instances use
proper prototype chains, so `err instanceof TypeError`, `hasOwnProperty`, and
`toString()` work. Their `ToString` form is `Name: message`.

The VM also throws catchable `TypeError`/`RangeError` objects for invalid
property access on `null`/`undefined`, setting a property on `null`/
`undefined`, calling a non-function, and exceeding the call-depth limit.

## Threading

The runtime is not documented as thread-safe. Use one engine/context per
thread, and do not move `TFloriaJSValue` objects between threads or heaps.
