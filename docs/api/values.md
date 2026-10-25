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
| `IsSymbol()` | kind is `fjstSymbol` |
| `IsPromise()` | object is a `TFloriaJSPromise` |
| `IsTruthy()` | alias for `ToBoolean()` |

Object-valued kinds (`array`, `function`, `error`) satisfy `IsObject()`.
`Symbol` is a primitive kind and does not satisfy `IsObject()`.

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
| symbol | `True` |
| object/array/function | `True` when the object pointer is non-nil |

`ToNumber()`:

| Kind | Result |
| :--- | :--- |
| `undefined` | `NaN` |
| `null` | `0` |
| boolean | `1` / `0` |
| number | the value |
| string | trimmed empty string → `0`; `0x`/`0b`/`0o` prefixes and `Infinity` → the number; otherwise the correctly rounded decimal parse, or `NaN` |
| array with exactly one element | number conversion of that element |
| array with zero or several elements | `NaN` |
| symbol | `NaN` |
| object/function | `NaN` |

`ToString()`:

| Kind | Result |
| :--- | :--- |
| `undefined` | `undefined` |
| `null` | `null` |
| boolean | `true` / `false` |
| number | ECMAScript `Number::toString`: `NaN`, `Infinity`, `-Infinity`, or the shortest decimal that round-trips, in fixed notation for `1e-6 <= \|x\| < 1e21` and scientific notation outside it |
| string | the string itself |
| symbol | `Symbol(description)` (or `Symbol()`) |
| array | elements joined with `,` |
| function | `function name() { [native code] }` (placeholder, including user functions) |
| error | `Name: message` |
| other object | `[object Object]` |

Number-to-string and string-to-number conversion are ECMAScript-exact; see
[`floria.js.number`](#floriajsnumber). Other coercions still differ from the
spec in a few corners (for example an empty array converts to `NaN`, not `0`),
so do not rely on full spec coercion in host code.

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
function JSMakeSymbol(const ADescription: string = '';
  AId: Integer = 0): TFloriaJSValue;
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
function  GetPropertyWithReceiver(const AName: string;
  AReceiver: TFloriaJSObject): TFloriaJSValue; virtual;
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
- `GetPropertyWithReceiver` is the VM-facing lookup used for prototype
  traversal. It forwards the original receiver through the chain so getters
  and methods execute with the correct `this`, including FTML item properties
  and promise methods. Most host code can use `GetProperty`.
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

## `TFloriaJSPrototypeObject`

The object a user function exposes as its `prototype` property.

```pascal
constructor Create(AProto: TFloriaJSObject; AOwner: TFloriaJSFunction);
destructor Destroy(); override;

function  GetPropertyWithReceiver(const AName: string;
  AReceiver: TFloriaJSObject): TFloriaJSValue; override;
function  HasOwnProperty(const AName: string): Boolean; override;

property OwnerFunction: TFloriaJSFunction read FOwnerFunction write SetOwnerFunction;
```

- The `constructor` back-reference to the owning function is **not stored as a
  normal property**. Reference counting cannot reclaim a cycle, and
  `Foo.prototype.constructor === Foo` would otherwise keep every function and
  its prototype alive forever.
- Instead the object holds a *weak owner registration*: `OwnerFunction` is
  assigned directly, without retaining, and the function is told to unregister
  the prototype when either side goes away. `constructor` reads are answered
  from that registration, and `hasOwnProperty('constructor')` reports `true`,
  so the property looks ordinary from JavaScript.
- Replacing the `prototype` property (or handing it to another function)
  updates the registration. A detached prototype therefore stops answering
  `constructor` with its former owner and falls back to `Object`, whereas
  ECMAScript keeps `constructor` on the old object. This is a deliberate
  consequence of the weak registration and is listed under known gaps in
  [language support](../language-support.md#known-gaps).
- `AProto` is normally `Object.prototype`, which is what makes
  `instanceof Object` true for user instances.

Host code should not need this class directly; `TFloriaJSHeap` creates these
objects when it installs `prototype` on a user function.

## `TFloriaJSArray`

```pascal
constructor Create();
destructor Destroy(); override;

function  GetElement(AIndex: Integer): TFloriaJSValue;
procedure SetElement(AIndex: Integer; const AValue: TFloriaJSValue);
function  HasElement(AIndex: Integer): Boolean;
procedure Push(const AValue: TFloriaJSValue);
procedure PushHole();
function  Pop(): TFloriaJSValue;
function  Shift(): TFloriaJSValue;
procedure Unshift(const AValue: TFloriaJSValue);
procedure InsertAt(AIndex: Integer; const AValue: TFloriaJSValue);
procedure RemoveAt(AIndex: Integer);
procedure MarkHole(AIndex: Integer);
function  DeleteElement(AIndex: Integer): Boolean;
procedure SetLengthTo(ANewLength: Integer);
procedure SwapElements(AIndex, BIndex: Integer);
function  Join(const ASeparator: string = ','): string;
function  Length(): Integer;

function  GetProperty(const AName: string): TFloriaJSValue; override;
function  GetPropertyWithReceiver(const AName: string;
  AReceiver: TFloriaJSObject): TFloriaJSValue; override;
procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); override;
function  DeleteProperty(const AName: string): Boolean; override;
function  HasProperty(const AName: string): Boolean; override;
function  HasOwnProperty(const AName: string): Boolean; override;
```

- Reading `length` returns the element count. The array keeps a parallel
  presence bitmap, so a **hole** (an elision, a grown `length` slot, or a
  deleted element) is length-bearing but is not an own property. `HasElement`
  reports presence; `GetElement` returns `undefined` for both a hole and an
  explicit `undefined` element.
- `PushHole` appends a hole, `MarkHole` turns a present element into a hole
  (releasing its reference), and `DeleteElement` is the primitive behind
  `delete arr[i]` (it keeps the length). `SetLengthTo` grows with holes or
  truncates; `SetProperty('length', …)` validates the value first and raises
  `RangeError` for a fractional, negative, or too-large length.
- `SwapElements` swaps both the value and the presence flag, which keeps holes
  at their positions during `reverse`/`sort`.
- Numeric property names map to elements; out-of-range reads return
  `undefined`. Out-of-range writes extend the array with holes in the gap.
  `HasProperty`, `HasOwnProperty`, and `in` recognise `length` and only the
  numeric indices that hold a present element, so an explicit `undefined`
  element is an own property while a hole is not.
- `Pop` and `Shift` release the array's own reference to the removed value.
  If the caller wants to keep it, pin/retain it immediately.
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
constructor CreateBytecode(const AName: string; ABytecode: TObject;
  AClosure: Pointer; AIsArrow: Boolean = False;
  AIsAsync: Boolean = False);
destructor Destroy(); override;

function GetProperty(const AName: string): TFloriaJSValue; override;
function GetPropertyWithReceiver(const AName: string;
  AReceiver: TFloriaJSObject): TFloriaJSValue; override;

property Name: string read FName write FName;
property IsNative: Boolean read FIsNative;
property IsAsync: Boolean read FIsAsync;
property IsArrow: Boolean read FIsArrow write FIsArrow;
property SuppressPrototype: Boolean read FSuppressPrototype
  write FSuppressPrototype;
property NotConstructable: Boolean read FNotConstructable
  write FNotConstructable;
property NativeProc: TFloriaJSNativeProc read FNativeProc;
property NativeMethod: TFloriaJSNativeMethod read FNativeMethod;
property ParamNames: TStringList read FParamNames;
property Body: TFloriaJSStmtNode read FBody;
property Bytecode: TObject read FBytecode write FBytecode;
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
- `CreateUser` stores an AST body. The VM compiles the body lazily on first
  call if no bytecode is attached. It retains the AST body unless `AOwnsBody`
  says the caller has already transferred a reference; the destructor always
  releases it.
- `CreateBytecode` takes a compiled `TFloriaJSBytecode` chunk (stored as
  `TObject` to keep the value unit independent of the bytecode unit) and
  retains it. This is what `OP_CLOSURE` uses for nested functions.
- `Bytecode` exposes the compiled chunk, or `nil` for native/AST-backed
  functions that have not been compiled yet.
- `prototype` is created lazily on first access for non-arrow functions. Its
  `constructor` back-reference is a weak link: it is cleared when the function
  is destroyed, and the prototype then delegates to `Object.prototype`.
- Arrow functions have no `prototype` and are rejected by `new`.
- `SuppressPrototype` keeps the lazy `prototype` from being created. Bound
  functions set it, because ECMAScript gives them no own `prototype`.
- `toString` is provided as a placeholder: `function <name>() { [native code] }`.
- `GetProperty('prototype')` is the safe way to obtain the constructor
  prototype for `instanceof` or host-side checks.

`name` and `length` are exposed as **non-enumerable own properties**, created
lazily on first read. `name` comes from the function's own name (an anonymous
function assigned to an object property takes the property's name), and
`length` from the bytecode's declared parameter count. Because they are created
lazily, `HasOwnProperty` materialises them before answering, so
`f.hasOwnProperty("name")` is `true` while `Object.keys(f)` stays empty.

`NotConstructable` marks conversion functions such as `BigInt` that throw when
called with `new`.

## `TFloriaJSBoundFunction`

```pascal
constructor CreateBound(const AName: string;
  const ATarget, ABoundThis: TFloriaJSValue;
  const ABoundArgs: TFloriaJSValueArray);
destructor Destroy(); override;

function CombineArguments(
  const AArgs: TFloriaJSValueArray): TFloriaJSValueArray;
function ConstructorTarget(): TFloriaJSFunction;

property Target: TFloriaJSValue read FTarget;
property BoundThis: TFloriaJSValue read FBoundThis;
property BoundArgs: TFloriaJSValueArray read FBoundArgs;
```

`TFloriaJSBoundFunction` is the object `Function.prototype.bind` creates. It
derives from `TFloriaJSFunction`, so it is a callable function object with the
shared function prototype, but it owns the target, the bound `this`, and the
bound arguments, retaining each of them. The heap frees it like any other
tracked object, and its destructor releases the retained values unless the heap
is being cleared.

- `NewBoundFunction` is the heap factory. Use it instead of calling the
  constructor directly so the object is tracked and gets the shared function
  prototype.
- Calls of a bound function ignore the receiver: the VM routes them through
  the target with `BoundThis` and `CombineArguments`.
- `new` on a bound function constructs the target with the combined arguments.
  A bound function is constructable exactly when its target is, so a bound
  arrow function is rejected.
- `ConstructorTarget` follows a chain of bound functions to the underlying
  function; `instanceof` and construction read the prototype from there.
- Bound functions set `SuppressPrototype`, so `"prototype" in B` is `false`.

## `TFloriaJSError`

```pascal
constructor Create(const AName, AMessage: string);
property Name: string read FName;
property Message: string read FMessage;
```

`TFloriaJSError` is a heap object with `name`/`message` semantics. `ToString`
returns `Name: Message`. `Error`, `TypeError`, `RangeError`,
`ReferenceError`, and `SyntaxError` constructors create instances with the
matching name and prototype chain; `URIError` comes from the URI support.
`err instanceof TypeError`, `hasOwnProperty`, and `toString()` therefore work.
`TFloriaJSHeap.NewError` selects the corresponding prototype for `TypeError`,
`RangeError`, `ReferenceError`, and `SyntaxError`; other names use the base
`Error` prototype.

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
function  NewBytecodeFunction(const AName: string; ABytecode: TObject;
  AClosure: Pointer; AIsArrow: Boolean = False;
  AIsAsync: Boolean = False): TFloriaJSFunction;
function  NewBoundFunction(const AName: string;
  const ATarget, ABoundThis: TFloriaJSValue;
  const ABoundArgs: TFloriaJSValueArray): TFloriaJSBoundFunction;

function  GetArrayPrototype(): TFloriaJSObject;
function  GetStringPrototype(): TFloriaJSObject;
function  GetObjectPrototype(): TFloriaJSObject;
function  GetErrorPrototype(): TFloriaJSObject;
function  GetTypeErrorPrototype(): TFloriaJSObject;
function  GetRangeErrorPrototype(): TFloriaJSObject;
function  GetReferenceErrorPrototype(): TFloriaJSObject;
function  GetSyntaxErrorPrototype(): TFloriaJSObject;

procedure OwnHelper(AHelper: TObject);
procedure SetFunctionInvoker(AInvoker: TFloriaJSFunctionInvoker);
function  InvokeFunction(const AFuncVal: TFloriaJSValue;
  const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;

procedure SetConstructInvoker(AInvoker: TFloriaJSConstructInvoker);
function  ConstructFunction(const AFuncVal: TFloriaJSValue;
  const AArgs: TFloriaJSValueArray): TFloriaJSValue;
function  ResolveConstructorTarget(
  const AFuncVal: TFloriaJSValue): TFloriaJSFunction;
function  GetConstructPrototype(
  const AFuncVal: TFloriaJSValue): TFloriaJSObject;
function  IsConstructable(const AFuncVal: TFloriaJSValue): Boolean;

procedure SetJobRunner(ARunner: TFloriaJSJobRunner);
procedure EnqueuePromiseJob(const AJob: TFloriaJSPromiseJob);
function  DequeuePromiseJob(out AJob: TFloriaJSPromiseJob): Boolean;
function  HasPromiseJobs(): Boolean;
procedure RunPendingJobs();

procedure ReclaimOrphanedEnvironments();
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
- `NewBoundFunction` creates the object behind `Function.prototype.bind`. It
  retains the target, the bound `this`, and the bound arguments, and it has no
  own `prototype`.
- `NewUserFunction` stores an AST-backed function; the VM compiles its body
  lazily on first call. The AST body must outlive the function; the function
  retains it unless ownership is transferred.
- `NewBytecodeFunction` creates a function from an already compiled
  `TFloriaJSBytecode`; the heap retains the chunk through the function.

### Prototypes

The `Get*Prototype` methods lazily create and pin a shared prototype.
They are stable for the lifetime of the heap and are reset by `Clear`. Error
prototypes form the standard inheritance chain (`TypeError` → `Error` →
`Object`), which is what makes `instanceof` and inherited `toString` work.

### Helpers and callbacks

- `OwnHelper` registers a Pascal object (for example the string-method helper)
  that the heap frees on `Clear`.
- `SetFunctionInvoker` is wired by the VM so heap-side native methods can
  call back into JavaScript. `InvokeFunction` is the wrapper built-ins use.
- `SetConstructInvoker` is the same arrangement for `new`: it lets a bound
  function construct its target without the value unit depending on the VM.
  `ConstructFunction` is the wrapper. `IsConstructable`,
  `ResolveConstructorTarget`, and `GetConstructPrototype` answer the questions
  `new` and `instanceof` ask: whether a value can be constructed, which
  underlying function owns the prototype, and what that prototype is. All three
  look through bound functions, whose own `prototype` does not exist.
- `SetJobRunner` / `RunPendingJobs` implement the promise microtask queue.
  `TFloriaJSContext.Evaluate` drains it after executing a script.

### Collection and clearing

- `ReclaimOrphanedEnvironments` frees detached environments that no live
  closure can reach. It is called by `Collect`, which the context invokes
  before executing a script.
- `Collect` first reclaims orphaned environments, then repeatedly sweeps
  tracked objects with `RefCount <= 0` that are `HeapOwned` and not pinned.
  Every freed object releases the references it held, which may make more
  objects collectible in the same call.
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
by the VM:

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

Use these in native methods to match the VM's coercion behaviour instead of
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
retains the AST body. On first call, the VM compiles the body into a bytecode
chunk and stores it on the function; subsequent calls reuse the chunk. The AST
declaration that owns the body releases its own reference when it is freed, so
a closure can outlive the script that declared it without dangling pointers.

## `floria.js.number`

```pascal
function JSNumberToStr(const V: Double): string;
function JSTryStrToNumber(const S: string; out V: Double): Boolean;
function JSNumberToRadixStr(const V: Double; ARadix: Integer): string;
```

JavaScript numbers are doubles, and both directions of conversion are visible
from a script, so both must match ECMAScript. The host formatter and parser are
not correctly rounded for every value (`FloatToStr` truncates, and
`StrToFloat("1e126")` is one ulp off), so this unit converts through **exact
decimal digit strings** instead.

- `JSNumberToStr` returns the shortest decimal that parses back to the same
  double, in the notation ECMAScript specifies: fixed for
  `1e-6 <= |x| < 1e21`, scientific otherwise, with `e+`/`e-` and no zero
  padding. `NaN`, the infinities, and both zeros (`"0"`) follow the spec.
- `JSTryStrToNumber` parses `[+-]digits[.digits][e[+-]digits]` and returns the
  nearest double, ties to even. It seeds from the host parser and then walks
  the double grid against the exact rounding interval, which corrects the
  host's rounding. Overflow saturates to `Infinity`; underflow becomes `0`.
  It returns `False` only when the text is not a decimal numeral.
- `JSNumberToRadixStr` implements `toString(radix)` for radix 2..36, including
  the fractional part. Radix 10 delegates to `JSNumberToStr`.

### How it works

Every finite double is `m * 2^e` with a 53-bit `m`, so it has an exact finite
decimal expansion; for negative `e` the unit multiplies by `5^k` and shifts the
point by `10^k`. The decimals that round to a given double are the closed
interval between the midpoints to its neighbours, where an endpoint is included
only when the mantissa is even. Formatting searches digit counts from one
upward and returns the first decimal inside that interval, which is by
construction the shortest representation. Nothing is approximated.

The conversion is intentionally isolated in its own unit so the value unit, the
JSON writer, and the lexer all share one implementation. `TFloriaJSValue`
`ToString`/`ToNumber`, `JSON.stringify`, and numeric literals delegate here.
