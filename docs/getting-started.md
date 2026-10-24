# Getting Started

This guide takes you from a fresh checkout to an embedded JavaScript runtime in
a Free Pascal application.

## Prerequisites

| Requirement | Notes |
| :--- | :--- |
| Free Pascal Compiler (FPC) | 3.2.x or newer. The project is developed and tested with FPC 3.2.3. |
| [PasBuild](https://github.com/graemeg/pasbuild) | The build driver used by `project.xml`. The project is tested with PasBuild 1.9. |
| `florialib` | Required dependency declared in `project.xml`. Install it into the local PasBuild repository before building floriajs. |

No GUI toolkit is required to use the JavaScript engine. The FTML runtime is
also toolkit-independent; rendering is the host application's responsibility.

## Build and test

From the repository root:

```bash
# Compile the library into target/
pasbuild compile

# Run the full automated test suite
pasbuild test

# Install the package into the local PasBuild repository
pasbuild install

# Build the bundled examples
./build.sh examples
```

The same commands are available through `build.sh`:

```bash
./build.sh compile
./build.sh test
./build.sh install
./build.sh examples
```

If PasBuild is not on your `PATH`, invoke it by its full path or add its
directory to `PATH`. Build artifacts are written below `target/`.

## Your first embedded script

```pascal
program hello_floriajs;

{$mode objfpc}{$H+}

uses
  SysUtils, floriajs;

var
  Engine: TFloriaJSEngine;
  Ctx: TFloriaJSContext;
  Res: TFloriaJSResult;
begin
  Engine := TFloriaJSEngine.Create();
  try
    Ctx := Engine.DefaultContext;

    Res := Ctx.Evaluate(
      'let name = "Floria";' + LineEnding +
      'console.log("Hello, " + name + "!");' + LineEnding +
      'Math.round(2.6);'
    );

    if Res.Success then
      WriteLn('Result: ', Res.StringValue)
    else
      WriteLn('Error: ', Res.ErrorMessage);

    WriteLn('Captured console output:');
    WriteLn(Ctx.Output.Text);
  finally
    Engine.Free();
  end;
end.
```

Typical output:

```text
Result: 3
Captured console output:
Hello, Floria!
```

`TFloriaJSEngine.Create()` creates a *default context* automatically. A context
owns its own heap, global environment, evaluator, and console output buffer.
`Engine.Free()` destroys every context the engine created.

## The two evaluation entry points

`TFloriaJSContext` exposes two ways to run a script:

```pascal
function Evaluate(const AScript: string): TFloriaJSResult; virtual;
function EvaluateValue(const AScript: string): TFloriaJSValue; virtual;
```

- **`Evaluate`** never raises for script errors. It returns a
  `TFloriaJSResult` record with `Success`, `ResultType`, `StringValue`,
  `NumberValue`, `BooleanValue`, and `ErrorMessage`.
- **`EvaluateValue`** returns the raw runtime value and lets exceptions
  propagate. Use it when you need the actual value, an object, an array, or a
  function. Values it returns are pinned; give them back with
  `ReleaseValue` when you are done (see [Memory and lifetime](#memory-and-lifetime)).

The convenience methods on `TFloriaJSEngine` (`Execute`, `ExecuteValue`,
`ReleaseValue`, `RegisterFunction`) forward to the default context.

## Calling Pascal from JavaScript

Register a plain function:

```pascal
function PascalAdd(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) < 2 then
    Exit(JSMakeNumber(0));
  Result := JSMakeNumber(AArgs[0].ToNumber() + AArgs[1].ToNumber());
end;

Engine.RegisterFunction('pascalAdd', @PascalAdd);
Res := Engine.Execute('pascalAdd(20, 22);');   // -> "42"
```

Register a method when the callback should be bound to a Pascal object:

```pascal
type
  THost = class
    function Multiply(const AArgs: array of TFloriaJSValue;
      AThis: TFloriaJSValue): TFloriaJSValue;
  end;

function THost.Multiply(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(AArgs[0].ToNumber() * AArgs[1].ToNumber());
end;

Ctx.RegisterMethod('multiply', @Host.Multiply);  // Host is a live THost instance
```

> **Pascal-side callbacks must not raise.** Return a JavaScript error value, or
> signal failure through your own host API, instead of letting an exception
> escape into the interpreter. Native callbacks also receive `AThis`; for a
> free function called from JavaScript it is `undefined`.

## Calling JavaScript from Pascal

Look up a global function by name and call it:

```pascal
var
  Greeting: TFloriaJSValue;
begin
  Ctx.Evaluate('function greet(name) { return "Hi " + name; }');

  Greeting := Ctx.Call('greet', [JSMakeString('Ada')]);
  try
    WriteLn(Greeting.ToString());   // Hi Ada
  finally
    Ctx.ReleaseValue(Greeting);     // only needed for object results
  end;
end;
```

`Call` returns `undefined` when the name does not refer to a function. The same
caveat as above applies to returned objects: the context pins them so they stay
alive for the caller, and `ReleaseValue` releases the pin.

## Variables and globals

```pascal
var
  v: TFloriaJSValue;
begin
  Ctx.SetVariable('app_name', 'FloriaJS');       // string global
  Ctx.SetGlobal('limit', JSMakeNumber(10));      // typed global
  WriteLn(Ctx.GetVariable('app_name'));          // FloriaJS
  v := Ctx.GetGlobal('limit');                   // TFloriaJSValue
end;
```

`SetGlobal` / `GetGlobal` work with `TFloriaJSValue`, so they can carry any
value the runtime understands. `SetVariable` / `GetVariable` use strings.

## Multiple contexts and reset

```pascal
CtxA := Engine.CreateContext('sandbox-a');
CtxB := Engine.CreateContext('sandbox-b');

CtxA.Evaluate('var state = 1;');
CtxB.Evaluate('state;');       // undefined: contexts do not share globals
```

Each context has an independent global environment. The engine owns its
contexts; use `Engine.DestroyContext(Ctx)` to destroy one early, or let the
engine free them. Do not free a context with `Free` directly while the engine
still tracks it.

`Ctx.Reset()` clears the heap, recreates the global environment, clears the
console buffer, and reinstalls the standard library. It does not delete the
context object itself.

> **Console routing.** `console.log`/`warn`/`error` are captured in the
> `Output` list of the context whose standard library was installed most
> recently, because the console sink is process-wide. In a single-context
> application this is always the context you expect. For several contexts,
> read `Output` from the context you last created, or install a custom logging
> strategy at the host level.

## Error handling

```pascal
Res := Ctx.Evaluate('let x = ;');
if not Res.Success then
  WriteLn('Script failed: ', Res.ErrorMessage);
```

`Evaluate` catches both parser errors and runtime exceptions and converts them
to `Success = False`. When you need the original exception, use
`EvaluateValue`:

```pascal
try
  Ctx.EvaluateValue('throw new Error("boom");');
except
  on E: Exception do
    WriteLn(E.ClassName, ': ', E.Message);
end;
```

JavaScript `throw` values are propagated as `EFloriaJSThrow`. A thrown Error
object's `ToString` renders as `Name: message`, for example
`TypeError: not a function`.

For FTML documents, use `TFloriaFTMLEngine.LoadString`; it checks parse errors
and exposes `HasErrors` and `LastError` instead of raising for syntax problems.
See the [FTML guide](ftml.md).

## Memory and lifetime

Values are reference-counted. Host code does not usually need to think about
it, but two rules matter:

1. **Object results from `EvaluateValue` / `Call` are pinned.** Call
   `ReleaseValue` when you are done with them. Primitive values need no
   release.
2. **Objects handed to JavaScript stay alive while JavaScript refers to them.**
   If you create an object with the heap and store it in a global, the global
   binding keeps it alive.

```pascal
var
  arr: TFloriaJSValue;
begin
  arr := Ctx.EvaluateValue('[1, 2, 3]');
  try
    WriteLn(arr.AsArray().Length());
  finally
    Ctx.ReleaseValue(arr);
  end;
end;
```

Avoid creating reference cycles between host objects and JavaScript objects:
the runtime uses reference counting, not a tracing collector, so a cycle that
spans the host boundary is never reclaimed. Within the runtime, the shared
`Function.prototype` deliberately has no back-reference to its constructor for
this reason.

## Next steps

- [Language support](language-support.md) — what JavaScript works today.
- [Engine and context API](api/engine.md) — complete API reference.
- [Values and heap API](api/values.md) — native values and coercion.
- [FTML guide](ftml.md) — declarative UI with reactive bindings.
- [Development guide](development.md) — tests, conventions, and adding features.
