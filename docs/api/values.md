# Values and Heap API

This page documents the runtime value layer in `floria.js.value`. Most host
integrations only need the factories (`JSMake*`), a few accessors, and the
lifetime rules at the end.

## `TFloriaJSValue`

```pascal
TFloriaJSValue = record
  Kind: TFloriaJSType;
  NumVal: Double;
  BoolVal: Boolean;
  StrVal: string;
  ObjVal: TFloriaJSObject;
end;
```

Treat the record as opaque apart from the type checks and conversions below.
Construct values with the `JSMake*` factories.

### Type predicates

| Method | True when |
| :--- | :--- |
| `IsUndefined()` | kind is `fjstUndefined` |
| `IsNull()` | kind is `fjstNull` |
| `IsBoolean()` | kind is `fjstBoolean` |
| `IsNumber()` | kind is `fjstNumber` |
| `IsString()` | kind is `fjstString` |
| `IsObject()` | kind is object, array, function, or error (all heap objects) |
| `IsArray()` | kind is `fjstArray` |
| `IsFunction()` | kind is `fjstFunction` |
| `IsPromise()` | object is a `TFloriaJSPromise` |
| `IsTruthy()` | alias for `ToBoolean()` |

Object-valued kinds (`array`, `function`, `error`) satisfy `IsObject()`.

### Accessors

```pascal
function AsObject(): TFloriaJSObject;
function AsArray(): TFloriaJSArray;
function AsFunction(): TFloriaJSFunction;
function AsPromise(): TFloriaJSPromise;
```

These return the underlying pointer without checking. Guard with the matching
predicate first:

```pascal
if V.IsArray() then
  WriteLn(V.AsArray().Length());
```

Calling `AsObject()` on a primitive or a value with a nil object pointer is
undefined behaviour at the Pascal level.

### Conversions

`ToBoolean()`:

| Kind | Result |
| :--- | :--- |
| `undefined`, `null` | `False` |
| boolean | the value |
| number | `False` for `0`, `NaN`, and `-0`; otherwise `True` |
| string | `False` for `''`; otherwise `True` |
| object/array/function | `True` when the object pointer is non-nil |

`ToNumber()`:

| Kind | Result |
| :--- | :--- |
| `undefined` | `NaN` |
| `null` | `0` |
| boolean | `1` / `0` |
| number | the value |
| string | trimmed empty string → `0`; Pascal numeric parse → the number; otherwise `NaN` |
| array with exactly one element | number conversion of that element |
| array with zero or several elements | `NaN` |
| object/function | `NaN` |

`ToString()`:

| Kind | Result |
| :--- | :--- |
| `undefined` | `undefined` |
| `null` | `null` |
| boolean | `true` / `false` |
| number | `NaN`, `Infinity`, `-Infinity`, or the shortest available decimal form; integral values print without a fractional part |
| string | the string itself |
| array | elements joined with `,` |
| function | `function name() { [native code] }` (placeholder, including user functions) |
| error | `Name: message` |
| other object | `[object Object]` |

These differ from ECMAScript in a few corners (for example an empty array
converts to `NaN`, not `0`). Do not rely on full spec coercion in host code.

## Value factories

```pascal
function JSMakeUndefined(): TFloriaJSValue;
function JSMakeNull(): TFloriaJSValue;
function JSMakeBoolean(ABool: Boolean): TFloriaJSValue;
function JSMakeNumber(ANum: Double): TFloriaJSValue;
function JSMakeString(const AStr: string): TFloriaJSValue;
function JSMakeObject(AObj: TFloriaJSObject): TFloriaJSValue;
function JSMakeArray(AArr: TFloriaJSArray): TFloriaJSValue;
function JSMakeFunction(AFunc: TFloriaJSFunction): TFloriaJSValue;
function JSMakePromise(APromise: TFloriaJSPromise): TFloriaJSValue;
```

Factory-created object values do **not** retain or pin the object. Ownership is
carried by the container you put the value into (a property, array element,
environment binding, or a host pin).

## `TFloriaJSObject`

Base class for all heap objects.

```pascal
constructor Create(AProto: TFloriaJSObject = nil);
destructor Destroy(); override;

procedure Retain();
procedure Release();
procedure Pin();
procedure Unpin();

function  GetProperty(const AName: string): TFloriaJSValue; virtual;
procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); virtual;
function  HasProperty(const AName: string): Boolean; virtual;
function  DeleteProperty(const AName: string): Boolean; virtual;
procedure DefineGetter(const AName: string; const AGetter: TFloriaJSValue);
procedure DefineSetter(const AName: string; const ASetter: TFloriaJSValue);

function  GetOwnProperty(const AName: string): TFloriaJSValue;
function  HasOwnProperty(const AName: string): Boolean; virtual;
function  GetPropertyCount(): Integer;
function  GetPropertyKey(AIndex: Integer): string;
function  GetPropertyValue(AIndex: Integer): TFloriaJSValue;
procedure GetKeys(AOutKeys: TStrings);

property Prototype: TFloriaJSObject read FPrototype write SetPrototype;
property RefCount: Integer read FRefCount;
property Pinned: Boolean read FPinned;
property Heap: TFloriaJSHeap read FHeap write FHeap;
property HeapOwned: Boolean read FHeapOwned write FHeapOwned;
```

- `GetProperty` walks the prototype chain; `GetOwnProperty` does not. If a
  property has a getter, reading it invokes the getter with `this` set to the
  object.
- `SetProperty` invokes a setter when one is defined; otherwise it updates an
  existing property or appends a new one. It retains the new value and releases
  the old one.
- `DefineGetter` / `DefineSetter` install accessor properties. Object literals
  with `get`/`set` syntax use these internally.
- Property order is insertion order, which is what `Object.keys` and property
  iteration observe.
- `Prototype` retains the new prototype and releases the old one.
- `HeapOwned = False` means the heap only tracks the object and will not
  reclaim it on `Collect`. It is used for objects whose lifetime another owner
  manages.

## `TFloriaJSArray`

```pascal
constructor Create();
destructor Destroy(); override;

function  GetElement(AIndex: Integer): TFloriaJSValue;
procedure SetElement(AIndex: Integer; const AValue: TFloriaJSValue);
procedure Push(const AValue: TFloriaJSValue);
function  Pop(): TFloriaJSValue;
function  Shift(): TFloriaJSValue;
procedure Unshift(const AValue: TFloriaJSValue);
procedure InsertAt(AIndex: Integer; const AValue: TFloriaJSValue);
procedure RemoveAt(AIndex: Integer);
function  Join(const ASeparator: string = ','): string;
function  Length(): Integer;

function  GetProperty(const AName: string): TFloriaJSValue; override;
procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); override;
function  HasProperty(const AName: string): Boolean; override;
```

- Reading `length` returns the element count.
- Numeric property names map to elements; out-of-range reads return
  `undefined`.
- `HasProperty` (and `in`) recognises `length` and valid numeric indices.
  `HasOwnProperty` currently only sees named properties, so
  `arr.HasOwnProperty('0')` is `false` even when the element exists.
- `Pop` and `Shift` release the array's own reference to the removed value.
  If the caller wants to keep it, pin/retain it immediately.
- Assigning `length` truncates the array when the new length is smaller.
  Assigning a larger value currently does not extend the element count.
- JavaScript array methods (`push`, `map`, `sort`, …) are installed on the
  shared array prototype by `floria.js.arrays`; these Pascal methods are the
  primitive operations used by that layer.

## `TFloriaJSFunction`

```pascal
constructor CreateNative(const AName: string; AProc: TFloriaJSNativeProc);
constructor CreateNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod);
constructor CreateUser(const AName: string; AParams: TStrings;
  ABody: TFloriaJSStmtNode; AClosure: Pointer;
  AOwnsBody: Boolean = False; AIsAsync: Boolean = False;
  AIsArrow: Boolean = False);
destructor Destroy(); override;

function GetProperty(const AName: string): TFloriaJSValue; override;

property Name: string read FName write FName;
property IsNative: Boolean read FIsNative;
property IsAsync: Boolean read FIsAsync;
property IsArrow: Boolean read FIsArrow write FIsArrow;
property NativeProc: TFloriaJSNativeProc read FNativeProc;
property NativeMethod: TFloriaJSNativeMethod read FNativeMethod;
property ParamNames: TStringList read FParamNames;
property Body: TFloriaJSStmtNode read FBody;
property ClosureEnv: Pointer read FClosureEnv;
```

Native callback signatures:

```pascal
TFloriaJSNativeProc = function(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
TFloriaJSNativeMethod = function(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue of object;
```

- `CreateNative` is for free functions; `RegisterFunction` uses it.
- `CreateNativeMethod` binds an object method; `RegisterMethod` uses it.
- `CreateUser` is used by the evaluator. It retains the AST body unless
  `AOwnsBody` says the caller has already transferred a reference to it. The
  function always releases the body in its destructor.
- `prototype` is created lazily on first access for non-arrow functions. It
  deliberately has no `constructor` back-reference to avoid a reference cycle.
- Arrow functions have no `prototype` and are rejected by `new`.
- `toString` is provided as a placeholder: `function <name>() { [native code] }`.
- `GetProperty('prototype')` is the safe way to obtain the constructor
  prototype for `instanceof` or host-side checks.

## `TFloriaJSError`

```pascal
constructor Create(const AName, AMessage: string);
property Name: string read FName;
property Message: string read FMessage;
```

`TFloriaJSError` is a heap object with `name`/`message` semantics. `ToString`
returns `Name: Message`. `Error`, `TypeError`, `RangeError`, and
`ReferenceError` constructors create instances with the matching name. Error
objects currently use a null prototype, so `instanceof` and
`hasOwnProperty` are not available on them.

## `TFloriaJSPromise`

```pascal
procedure Fulfill(const AValue: TFloriaJSValue);
procedure Reject(const AValue: TFloriaJSValue);
function  Chain(const AOnFulfilled, AOnRejected: TFloriaJSValue): TFloriaJSPromise;
function  ChainFinally(const AOnFinally: TFloriaJSValue): TFloriaJSPromise;

property State: TFloriaJSPromiseState read FState;
property ResultValue: TFloriaJSValue read FResult;
```

States are `fjspPending`, `fjspFulfilled`, and `fjspRejected`. The JavaScript
face of a promise (`then`, `catch`, `finally`) is installed by
`TFloriaJSPromise.GetProperty`.

## `TFloriaJSHeap`

```pascal
constructor Create();
destructor Destroy(); override;

function  Track(AObj: TFloriaJSObject; AHeapOwned: Boolean = True): TFloriaJSObject;
function  TrackEnvironment(AEnv: TObject): TObject;
function  Untrack(AObj: TObject): Boolean;

function  NewObject(AProto: TFloriaJSObject = nil; ANoProto: Boolean = False): TFloriaJSObject;
function  NewArray(): TFloriaJSArray;
function  NewError(const AName, AMessage: string): TFloriaJSError;
function  NewPromise(): TFloriaJSPromise;
function  NewNativeFunction(const AName: string; AProc: TFloriaJSNativeProc): TFloriaJSFunction;
function  NewNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod): TFloriaJSFunction;
function  NewUserFunction(const AName: string; AParams: TStrings;
  ABody: TFloriaJSStmtNode; AClosure: Pointer;
  AOwnsBody: Boolean = False; AIsAsync: Boolean = False;
  AIsArrow: Boolean = False): TFloriaJSFunction;

function  GetArrayPrototype(): TFloriaJSObject;
function  GetStringPrototype(): TFloriaJSObject;
function  GetObjectPrototype(): TFloriaJSObject;

procedure OwnHelper(AHelper: TObject);
procedure SetFunctionInvoker(AInvoker: TFloriaJSFunctionInvoker);
function  InvokeFunction(const AFuncVal: TFloriaJSValue;
  const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;

procedure SetJobRunner(ARunner: TFloriaJSJobRunner);
procedure EnqueuePromiseJob(const AJob: TFloriaJSPromiseJob);
function  DequeuePromiseJob(out AJob: TFloriaJSPromiseJob): Boolean;
function  HasPromiseJobs(): Boolean;
procedure RunPendingJobs();

procedure Collect();
procedure Clear();
function  GetObjectCount(): Integer;
function  GetEnvironmentCount(): Integer;
function  GetObject(AIndex: Integer): TFloriaJSObject;
function  GetEnvironment(AIndex: Integer): TObject;

property IsClearing: Boolean read FClearing;
property Id: Integer read FId;
```

### Creating objects

- `NewObject` returns a tracked object. Unless `ANoProto` is true, a new object
  inherits from the shared `Object.prototype`. Pass an explicit prototype to
  create instances of a constructor. Use `ANoProto = True` for a
  null-prototype object.
- `NewArray` returns an array whose prototype is the shared array prototype.
- `NewNativeFunction` / `NewNativeMethod` create callable objects. They do not
  add the function to any environment by themselves.
- `NewUserFunction` is primarily for the evaluator and the FTML engine. It
  expects an AST body that outlives the function.

### Prototypes

The three `Get*Prototype` methods lazily create and pin a shared prototype.
They are stable for the lifetime of the heap and are reset by `Clear`.

### Helpers and callbacks

- `OwnHelper` registers a Pascal object (for example the string-method helper)
  that the heap frees on `Clear`.
- `SetFunctionInvoker` is wired by the evaluator so heap-side native methods can
  call back into JavaScript. `InvokeFunction` is the wrapper built-ins use.
- `SetJobRunner` / `RunPendingJobs` implement the promise microtask queue.
  `ExecuteProgram` drains it automatically.

### Collection and clearing

- `Collect` repeatedly sweeps tracked objects with `RefCount <= 0` that are
  `HeapOwned` and not pinned. Every freed object releases the references it
  held, which may make more objects collectible in the same call.
- `Clear` frees **all** tracked environments and **all** tracked objects,
  regardless of `HeapOwned`/pinning, then resets cached prototypes and frees
  owned helpers. Hosts must not call it while they still hold objects created
  by that heap.
- `Untrack` removes an object or environment from the heap without freeing it.

## Reference-counting helpers

```pascal
procedure JSRetainValue(const AValue: TFloriaJSValue);
procedure JSReleaseValue(const AValue: TFloriaJSValue);
```

These are no-ops for primitives and call `Retain`/`Release` for objects.
Containers use them when they take over a value or let it go. Host code should
prefer `Pin`/`Unpin` through `TFloriaJSContext` instead of manipulating the
count directly.

## Operator helpers

`floria.js.value` exposes the coercion-aware binary and unary operations used
by the evaluator:

```pascal
function JSAdd(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
function JSSubtract(...); function JSMultiply(...); function JSDivide(...);
function JSModulo(...); function JSPower(...);

function JSEqual(...); function JSStrictEqual(...);
function JSLessThan(...); function JSLessEqual(...);
function JSGreaterThan(...); function JSGreaterEqual(...);
function JSInstanceOf(...): Boolean;

function JSBitAnd(...); function JSBitOr(...); function JSBitXor(...);
function JSShiftLeft(...); function JSShiftRight(...); function JSShiftRightUnsigned(...);

function JSUnaryMinus(...); function JSUnaryPlus(...);
function JSUnaryNot(...); function JSUnaryBitNot(...);
function JSTypeOf(...): string;
```

Use these in native methods to match the interpreter's coercion instead of
coercing manually.

## Lifetime rules for host code

1. **Do not retain raw object pointers without pinning.** A tracked object with
   no references can be reclaimed at the next safe point. Use `Pin` for
   long-lived host handles and `Unpin` when done.
2. **Release values returned by `EvaluateValue` / `Call`.** They are pinned for
   you; `ReleaseValue` removes the pin.
3. **Do not release values twice**, and do not release values that came from a
   property read or `GetGlobal` (those are not pinned by the accessor).
4. **Do not keep values across `Reset` or context destruction.**
5. **Avoid cycles across the host boundary.** Reference counting reclaims
   acyclic garbage only.

## Implementation note on user functions

`NewUserFunction` ultimately calls `TFloriaJSFunction.CreateUser`, which
retains the AST body. The AST declaration that owns the body releases its own
reference when it is freed. This is what lets a closure outlive the script
that declared it without dangling pointers.
