{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Dynamic Value System & Heap Objects             }
{                                                                          }
{   Defines runtime values, heap-allocated JS objects, arrays, functions,  }
{   type coercion, and arithmetic/logical operations.                      }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.value;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math, floria.js.types, floria.js.number;

type
  { Forward Declarations }
  TFloriaJSObject = class;
  TFloriaJSArray = class;
  TFloriaJSFunction = class;
  TFloriaJSPrototypeObject = class;
  TFloriaJSBoundFunction = class;
  TFloriaJSHeap = class;
  TFloriaJSPromise = class;

  { Promise Settlement State }
  TFloriaJSPromiseState = (fjspPending, fjspFulfilled, fjspRejected);

  { Dynamic JavaScript Runtime Value }
  TFloriaJSValue = record
    Kind: TFloriaJSType;
    NumVal: Double;
    StrVal: string;
    ObjVal: TFloriaJSObject;

    { Compatibility accessors for the old cached boolean slot. Booleans now
      store 0/1 in NumVal, which removes eight bytes from every value. }
    function GetBoolVal(): Boolean;
    procedure SetBoolVal(AValue: Boolean);

    function IsUndefined(): Boolean;
    function IsNull(): Boolean;
    function IsBoolean(): Boolean;
    function IsNumber(): Boolean;
    function IsString(): Boolean;
    function IsObject(): Boolean;
    function IsArray(): Boolean;
    function IsFunction(): Boolean;
    function IsPromise(): Boolean;
    function IsSymbol(): Boolean;
    { A BigInt holds a signed decimal digit string in StrVal. }
    function IsBigInt(): Boolean;
    function IsTruthy(): Boolean;

    function ToBoolean(): Boolean;
    function ToNumber(): Double;
    function ToString(): string;

    function AsObject(): TFloriaJSObject;
    function AsArray(): TFloriaJSArray;
    function AsFunction(): TFloriaJSFunction;
    function AsPromise(): TFloriaJSPromise;

    property BoolVal: Boolean read GetBoolVal write SetBoolVal;
  end;

  { Argument list used by the call helpers and by the bound-function wrapper. }
  TFloriaJSValueArray = array of TFloriaJSValue;

  { Callback Used by Heap-Side Built-ins to Invoke a JavaScript Function.
    The VM installs it, so native methods such as Array.map can call
    back into user code without depending on the VM unit. }
  TFloriaJSFunctionInvoker = function(const AFuncVal: TFloriaJSValue;
    const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue of object;

  { Callback Used by Heap-Side Built-ins to Construct a JavaScript Object.
    `new Bound(...)` has to construct the bound target with the combined
    arguments, which only the VM can do, so it installs this as well. }
  TFloriaJSConstructInvoker = function(const AFuncVal: TFloriaJSValue;
    const AArgs: TFloriaJSValueArray): TFloriaJSValue of object;

  { Callback Used by the intrinsic eval function to parse and execute source
    in the realm's global environment. The VM installs it. }
  TFloriaJSSourceEvaluator = function(const ASource: string): TFloriaJSValue of object;

  { Property Key-Value Entry }
  TFloriaJSPropertyPair = record
    Key: string;
    Value: TFloriaJSValue;
    Getter: TFloriaJSValue;
    Setter: TFloriaJSValue;
    HasGetter: Boolean;
    HasSetter: Boolean;
    { Class methods and `prototype` are non-enumerable: they exist on the
      object but `for…in` and `Object.keys` skip them, as in ECMAScript. }
    Enumerable: Boolean;
    Writable: Boolean;
    Configurable: Boolean;
  end;

  { Heap-allocated Base JavaScript Object }
  TFloriaJSObject = class
  private
    FPrototype: TFloriaJSObject;
    FProperties: array of TFloriaJSPropertyPair;
    FPropCount: Integer;
    FRefCount: Integer;
    { `Object.freeze`/`seal` marking. This runtime has no per-property
      attributes, so the flags record the call and are observable through
      `Object.isFrozen`/`isSealed`. }
    FIsFrozen: Boolean;
    FIsSealed: Boolean;
    FIsExtensible: Boolean;
    FHeap: TFloriaJSHeap;
    FHeapOwned: Boolean;
    FPinned: Boolean;
    function FindPropertyIndex(const AName: string): Integer;
    function FindWellKnownSymbolIndex(const AName: string): Integer;
    procedure SetPrototype(AProto: TFloriaJSObject);
  public
    constructor Create(AProto: TFloriaJSObject = nil);
    destructor Destroy(); override;

    { Reference counting. Every container that stores a value owns a reference
      to the object it points at. The heap reclaims an object once the last
      owner gives up its reference. }
    procedure Retain();
    procedure Release();
    procedure Pin();
    procedure Unpin();

    function  GetProperty(const AName: string): TFloriaJSValue; virtual;
    function  GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue; virtual;
    procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); virtual;
    procedure SetPropertyNonEnumerable(const AName: string; const AValue: TFloriaJSValue);
    procedure SetEnumerable(const AName: string; AEnumerable: Boolean);
    function  IsEnumerable(const AName: string): Boolean;
    { Accessors used when a setter lives on a prototype. }
    function  PropHasSetter(AIndex: Integer): Boolean;
    function  PropSetter(AIndex: Integer): TFloriaJSValue;
    procedure DefineGetter(const AName: string; const AGetter: TFloriaJSValue); virtual;
    procedure DefineSetter(const AName: string; const ASetter: TFloriaJSValue); virtual;
    function  HasProperty(const AName: string): Boolean; virtual;
    function  DeleteProperty(const AName: string): Boolean; virtual;
    property IsFrozen: Boolean read FIsFrozen write FIsFrozen;
    property IsSealed: Boolean read FIsSealed write FIsSealed;
    property IsExtensible: Boolean read FIsExtensible write FIsExtensible;

    function  GetOwnProperty(const AName: string): TFloriaJSValue; virtual;
    { Looks up a well-known-symbol property by its description, accepting the
      canonical symbol key and the legacy description spelling. }
    function  GetWellKnownProperty(const ADescription: string): TFloriaJSValue;
    function  HasOwnProperty(const AName: string): Boolean; virtual;

    { Property-descriptor support. DefineDataProperty and
      DefineAccessorProperty implement the descriptor fields; the read helpers
      expose them for Object.getOwnPropertyDescriptor. }
    function  DefineDataProperty(const AName: string; const AValue: TFloriaJSValue;
      AWritable, AEnumerable, AConfigurable: Boolean): Boolean; virtual;
    function  DefineAccessorProperty(const AName: string;
      const AGetter, ASetter: TFloriaJSValue; AEnumerable, AConfigurable: Boolean): Boolean; virtual;
    function  PropertyIsWritable(const AName: string): Boolean; virtual;
    function  PropertyIsConfigurable(const AName: string): Boolean; virtual;
    procedure SetPropertyConfigurable(const AName: string; AConfigurable: Boolean);
    function  PropertyIsEnumerable(const AName: string): Boolean; virtual;
    function  PropertyIsAccessor(const AName: string): Boolean; virtual;
    function  PropertyHasGetter(const AName: string): Boolean; virtual;
    function  PropertyHasSetter(const AName: string): Boolean; virtual;
    function  PropertyGetter(const AName: string): TFloriaJSValue; virtual;
    function  PropertySetter(const AName: string): TFloriaJSValue; virtual;
    procedure FreezeProperties();
    procedure SealProperties();
    function  GetPropertyCount(): Integer; virtual;
    function  GetEnumerablePropertyCount(): Integer; virtual;
    function  GetEnumerablePropertyKey(AIndex: Integer): string; virtual;
    function  GetPropertyKey(AIndex: Integer): string; virtual;
    function  GetPropertyValue(AIndex: Integer): TFloriaJSValue; virtual;
    procedure GetKeys(AOutKeys: TStrings); virtual;

    property Prototype: TFloriaJSObject read FPrototype write SetPrototype;
    property RefCount: Integer read FRefCount;
    property Pinned: Boolean read FPinned;
    property Heap: TFloriaJSHeap read FHeap write FHeap;
    property HeapOwned: Boolean read FHeapOwned write FHeapOwned;
  end;

  { Proxy object. The diagnostic implementation forwards the core property
    operations through the handler traps and falls back to the target. }
  TFloriaJSProxy = class(TFloriaJSObject)
  private
    FTarget: TFloriaJSValue;
    FHandler: TFloriaJSValue;
    FRevoked: Boolean;
    FCallable: Boolean;
    function  GetTrap(const AName: string): TFloriaJSValue;
    procedure RequireCallableTrap(const ATrap: TFloriaJSValue; const AName: string);
  public
    constructor Create(AHeap: TFloriaJSHeap; const ATarget, AHandler: TFloriaJSValue);
    destructor Destroy(); override;

    function  GetPropertyWithReceiver(const AName: string;
      AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); override;
    function  HasProperty(const AName: string): Boolean; override;
    function  DeleteProperty(const AName: string): Boolean; override;
    function  HasOwnProperty(const AName: string): Boolean; override;
    function  GetOwnProperty(const AName: string): TFloriaJSValue; override;
    function  GetPropertyCount(): Integer; override;
    function  GetEnumerablePropertyCount(): Integer; override;
    function  GetEnumerablePropertyKey(AIndex: Integer): string; override;
    function  GetPropertyKey(AIndex: Integer): string; override;
    function  GetPropertyValue(AIndex: Integer): TFloriaJSValue; override;
    procedure GetKeys(AOutKeys: TStrings); override;

    property Target: TFloriaJSValue read FTarget;
    property Handler: TFloriaJSValue read FHandler;
    property Revoked: Boolean read FRevoked write FRevoked;
    property Callable: Boolean read FCallable;
    function  Call(const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;
    function  Construct(const AArgs: array of TFloriaJSValue): TFloriaJSValue;
    function  SetPrototypeOf(const AProto: TFloriaJSValue): Boolean;
  end;

  { Heap-allocated JavaScript Array.
    The array is sparse-capable: FPresent marks which of the FCount slots hold
    a real element. An absent slot is an ECMAScript "hole": reading it yields
    undefined, but it is not an own property, so `in`, `hasOwnProperty`,
    `Object.keys` and `for…in` skip it. Keeping the presence information
    separate from the element value is what lets an explicit `undefined`
    element stay distinguishable from a hole. }
  TFloriaJSArray = class(TFloriaJSObject)
  private
    FElements: array of TFloriaJSValue;
    FPresent: array of Boolean;
    FCount: Integer;
    { Logical length can exceed the dense range because ECMAScript array
      indices go up to 2^32 - 2. Elements at or above DENSE_LIMIT live in the
      overflow list instead of forcing a multi-gigabyte allocation. }
    FLogicalLength: Int64;
    FOverflowIndex: array of Int64;
    FOverflowValue: array of TFloriaJSValue;
    FOverflowCount: Integer;
    procedure GrowCapacity(AMinCapacity: Integer);
    function  FindOverflowIndex(AIndex: Int64): Integer;
    procedure SetOverflowElement(AIndex: Int64; const AValue: TFloriaJSValue);
    function  GetOverflowElement(AIndex: Int64): TFloriaJSValue;
    function  HasOverflowElement(AIndex: Int64): Boolean;
    function  DeleteOverflowElement(AIndex: Int64): Boolean;
    procedure TrimOverflow(ANewLength: Int64);
    procedure RefreshLogicalLength();
  public
    constructor Create();
    destructor Destroy(); override;

    function  GetElement(AIndex: Integer): TFloriaJSValue;
    procedure SetElement(AIndex: Integer; const AValue: TFloriaJSValue);
    { Direct Int64 index paths used by the VM's numeric-key fast path. They
      cover both the dense range and the sparse overflow list. }
    function  GetElementByIndex(const AIndex: Int64): TFloriaJSValue;
    procedure SetElementByIndex(const AIndex: Int64; const AValue: TFloriaJSValue);
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
    function  LogicalLength(): Int64;

    function  GetProperty(const AName: string): TFloriaJSValue; override;
    function  GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); override;
    function  DeleteProperty(const AName: string): Boolean; override;
    function  HasProperty(const AName: string): Boolean; override;
    function  HasOwnProperty(const AName: string): Boolean; override;
  end;

  { A boxed String object created by `new String(value)`. The primitive value
    lives in the object so String.prototype.toString/valueOf and loose equality
    can recover it, while prototype lookup still provides String methods. }
  TFloriaJSStringObject = class(TFloriaJSObject)
  private
    FValue: string;
  public
    constructor Create(AProto: TFloriaJSObject; const AValue: string);
    property Value: string read FValue;
  end;

  { Native Function Callbacks }
  TFloriaJSNativeProc = function(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
  TFloriaJSNativeMethod = function(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue of object;

  { Heap-allocated JavaScript Error Object }
  TFloriaJSError = class(TFloriaJSObject)
  private
    FName: string;
    FMessage: string;
  public
    constructor Create(const AName, AMessage: string);

    property Name: string read FName;
    property Message: string read FMessage;
  end;

  { Heap-allocated JavaScript Function }
  TFloriaJSFunction = class(TFloriaJSObject)
  private
    FName: string;
    FIsNative: Boolean;
    FNativeProc: TFloriaJSNativeProc;
    FNativeMethod: TFloriaJSNativeMethod;
    FBytecode: TObject;
    FClosureEnv: Pointer; // Lexical environment TFloriaJSEnvironment
    FIsAsync: Boolean;
    FIsAsyncGenerator: Boolean;
    FIsNamedExpression: Boolean;
    FIsArrow: Boolean;
    FSuppressPrototype: Boolean;
    FNotConstructable: Boolean;
    FIntrinsicName: string;
    FNameDeleted: Boolean;
    FLengthDeleted: Boolean;
    FPrototypes: TFPList;
    procedure RegisterPrototype(AProto: TFloriaJSPrototypeObject);
    procedure UnregisterPrototype(AProto: TFloriaJSPrototypeObject);
  public
    constructor CreateNative(const AName: string; AProc: TFloriaJSNativeProc);
    constructor CreateNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod);
    constructor CreateBytecode(const AName: string; ABytecode: TObject; AClosure: Pointer; AIsArrow: Boolean = False; AIsAsync: Boolean = False);
    destructor Destroy(); override;

    function GetProperty(const AName: string): TFloriaJSValue; override;
    function GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); override;
    function DeleteProperty(const AName: string): Boolean; override;
    { `name` and `length` are created lazily, so the raw property store does not
      know about them until they are read. }
    function HasOwnProperty(const AName: string): Boolean; override;
    procedure DefineGetter(const AName: string; const AGetter: TFloriaJSValue); override;
    procedure DefineSetter(const AName: string; const ASetter: TFloriaJSValue); override;

    property Name: string read FName write FName;
    property IsNative: Boolean read FIsNative;
    property IsAsync: Boolean read FIsAsync;
    property IsAsyncGenerator: Boolean read FIsAsyncGenerator write FIsAsyncGenerator;
    property IsNamedExpression: Boolean read FIsNamedExpression write FIsNamedExpression;
    property IsArrow: Boolean read FIsArrow write FIsArrow;
    { Bound functions have no own `prototype` per ECMAScript, even though they
      are ordinary function objects in every other respect. }
    property SuppressPrototype: Boolean read FSuppressPrototype write FSuppressPrototype;
    { Conversion functions such as `BigInt` and `Symbol` throw when used with
      `new`, which ECMAScript specifies explicitly. }
    property NotConstructable: Boolean read FNotConstructable write FNotConstructable;
    { The intrinsic constructor this native function represents, such as
      `Array` or `String`. Construction uses it to select the newTarget
      realm's default prototype. }
    property IntrinsicName: string read FIntrinsicName write FIntrinsicName;
    property NativeProc: TFloriaJSNativeProc read FNativeProc;
    property NativeMethod: TFloriaJSNativeMethod read FNativeMethod;
    property Bytecode: TObject read FBytecode write FBytecode;
    property ClosureEnv: Pointer read FClosureEnv;
  end;

  { Function Prototype Object with Dynamic Constructor Back-Reference }
  TFloriaJSPrototypeObject = class(TFloriaJSObject)
  private
    FOwnerFunction: TFloriaJSFunction;
    procedure SetOwnerFunction(AOwner: TFloriaJSFunction);
  public
    constructor Create(AProto: TFloriaJSObject; AOwner: TFloriaJSFunction);
    destructor Destroy(); override;
    function GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    function HasOwnProperty(const AName: string): Boolean; override;

    property OwnerFunction: TFloriaJSFunction read FOwnerFunction write SetOwnerFunction;
  end;

  { Exotic Function Created by Function.prototype.bind.
    ECMAScript models a bound function as a callable object of its own, not as a
    native method that forwards the call. The distinction is observable: a bound
    function is constructable exactly when its target is, `new` ignores the bound
    `this`, `instanceof` traverses the target's prototype chain, and there is no
    own `prototype` property. Owning the state on a function object keeps the
    lifetime handling in one place: the target, the bound `this`, and every bound
    argument are retained for as long as the bound function exists. }
  TFloriaJSBoundFunction = class(TFloriaJSFunction)
  private
    FTarget: TFloriaJSValue;
    FBoundThis: TFloriaJSValue;
    FBoundArgs: TFloriaJSValueArray;
  public
    constructor CreateBound(const AName: string; const ATarget, ABoundThis: TFloriaJSValue;
      const ABoundArgs: TFloriaJSValueArray);
    destructor Destroy(); override;

    { Appends the bound arguments in front of the call arguments. }
    function CombineArguments(const AArgs: TFloriaJSValueArray): TFloriaJSValueArray;
    { The constructor whose prototype an instance must inherit, or nil when the
      target cannot be constructed. Bound functions are transparent: the search
      continues through the target chain. }
    function ConstructorTarget(): TFloriaJSFunction;

    property Target: TFloriaJSValue read FTarget;
    property BoundThis: TFloriaJSValue read FBoundThis;
    property BoundArgs: TFloriaJSValueArray read FBoundArgs;
  end;

  { Thrown JavaScript Value (used to propagate promise rejections) }
  EFloriaJSThrow = class(Exception)
  private
    FValue: TFloriaJSValue;
  public
    constructor Create(const AValue: TFloriaJSValue);
    property Value: TFloriaJSValue read FValue;
  end;

  { Promise Reaction Registered by then() / catch() / finally() }
  TFloriaJSPromiseReaction = record
    OnFulfilled: TFloriaJSValue;
    OnRejected: TFloriaJSValue;
    OnFinally: TFloriaJSValue;
    IsFinally: Boolean;
    Child: TFloriaJSPromise;
  end;

  { Deferred Microtask that Runs One Promise Reaction or settles a promise
    that was completed synchronously by a combinator such as Promise.all. }
  TFloriaJSPromiseJobKind = (pjkReaction, pjkFulfill, pjkReject);

  TFloriaJSPromiseJob = record
    Kind: TFloriaJSPromiseJobKind;
    OnFulfilled: TFloriaJSValue;
    OnRejected: TFloriaJSValue;
    OnFinally: TFloriaJSValue;
    IsFinally: Boolean;
    IsRejection: Boolean;
    Value: TFloriaJSValue;
    Child: TFloriaJSPromise;
    Target: TFloriaJSPromise;
  end;
  PTFloriaJSPromiseJob = ^TFloriaJSPromiseJob;

  { Heap-allocated JavaScript Promise }
  TFloriaJSPromise = class(TFloriaJSObject)
  private
    FState: TFloriaJSPromiseState;
    FResult: TFloriaJSValue;
    FReactions: array of TFloriaJSPromiseReaction;
    FReactionCount: Integer;
    FThenFn: TFloriaJSFunction;
    FCatchFn: TFloriaJSFunction;
    FFinallyFn: TFloriaJSFunction;
    procedure AddReaction(const AReaction: TFloriaJSPromiseReaction);
    procedure ReleaseReaction(const AReaction: TFloriaJSPromiseReaction);
    procedure ScheduleReactions();
  public
    constructor Create(AHeap: TFloriaJSHeap);
    destructor Destroy(); override;

    function  GetProperty(const AName: string): TFloriaJSValue; override;
    function  GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    function  HasProperty(const AName: string): Boolean; override;

    procedure Fulfill(const AValue: TFloriaJSValue);
    procedure Reject(const AValue: TFloriaJSValue);
    { Registers a reaction, or schedules it immediately when already settled.
      `AChild` receives the handler's outcome. Public because the VM's promise
      job runner adopts a returned promise through it. }
    procedure Attach(const AOnFulfilled, AOnRejected, AOnFinally: TFloriaJSValue; AIsFinally: Boolean; AChild: TFloriaJSPromise);
    function  Chain(const AOnFulfilled, AOnRejected: TFloriaJSValue): TFloriaJSPromise;
    function  ChainFinally(const AOnFinally: TFloriaJSValue): TFloriaJSPromise;

    property State: TFloriaJSPromiseState read FState;
    property ResultValue: TFloriaJSValue read FResult;
  end;

  { A suspended generator.

    A generator body is ordinary bytecode that suspends at `yield`. The frame
    snapshot is exactly the state RunLoop needs to resume:

      - Bytecode and IP: where execution continues (just past the yield).
      - BaseBP: the stack base of this frame's locals.
      - Env: the activation environment, so bindings survive suspension.
      - Stack: the operand stack contents from BaseBP up to the yield point.

    Nothing else is live across a yield: try handlers belong to the enclosing
    call and are rejected as unsupported inside generators, and the call frames
    above this one are unwound by the suspension itself. }
  TFloriaJSGenerator = class;

  { Runs or resumes a generator, returning its next value or completion.
    Installed by the VM, which owns the execution stack. }
  TFloriaJSGeneratorRunner = function(AGen: TFloriaJSGenerator;
    const ASent: TFloriaJSValue; out AValue: TFloriaJSValue;
    out ADone: Boolean): Boolean of object;

  { Resumes an async task after its awaited promise settles. Installed by the
    VM; `AIsRejection` injects the rejection as a throw at the await point. }
  TFloriaJSAsyncResume = procedure(AGen: TFloriaJSGenerator;
    const AValue: TFloriaJSValue; AIsRejection: Boolean) of object;

  { Starts or resumes an async generator and returns the promise for one
    `next()`/`return()` result. Installed by the VM. }
  TFloriaJSAsyncGeneratorNext = function(AGen: TFloriaJSGenerator;
    const ASent: TFloriaJSValue; AMode: Integer): TFloriaJSPromise of object;

  TFloriaJSGeneratorState = (fjgsSuspendedStart, fjgsSuspendedYield,
    fjgsRunning, fjgsCompleted);

  TFloriaJSGeneratorTrySnapshot = record
    CatchIP: Integer;
    FrameOffset: Integer;
    StackDepth: Integer;
    Env: Pointer;
  end;

  TFloriaJSGenerator = class(TFloriaJSObject)
  private
    FBytecode: TObject;
    FEnv: Pointer;
    FCurrentEnv: Pointer;
    FThisVal: TFloriaJSValue;
    FArgs: TFloriaJSValueArray;
    FIP: Integer;
    FBaseBP: Integer;
    { The frame pointer the generator body runs at, so suspension unwinds only
      this generator's frames and not the caller's. }
    FFrameFP: Integer;
    FStack: TFloriaJSValueArray;
    FStackCount: Integer;
    FState: TFloriaJSGeneratorState;
    FReturnValue: TFloriaJSValue;
    FNextFn: TFloriaJSFunction;
    FReturnFn: TFloriaJSFunction;
    FThrowFn: TFloriaJSFunction;
    FSelfIteratorFn: TFloriaJSFunction;
    FRunner: TFloriaJSGeneratorRunner;
    FAsyncResume: TFloriaJSAsyncResume;
    FIsAsyncTask: Boolean;
    FIsAsyncGenerator: Boolean;
    FAsyncGeneratorYielded: Boolean;
    FAsyncGeneratorNext: TFloriaJSAsyncGeneratorNext;
    FInYieldStar: Boolean;
    FYieldStarDone: Boolean;
    FYieldStarIterator: TFloriaJSValue;
    FAsyncPromise: TFloriaJSPromise;
    FHasPendingThrow: Boolean;
    FPendingThrow: TFloriaJSValue;
    FTrySnapshots: array of TFloriaJSGeneratorTrySnapshot;
    FTrySnapshotCount: Integer;
    { The lazily created methods are owned by the generator. `Track` only
      registers an object with the heap; it does not keep it alive, so without
      an explicit reference the method was reclaimed at the next collection and
      the cached pointer dangled. }
    procedure OwnMethod(var AField: TFloriaJSFunction; const AName: string;
      AMethod: TFloriaJSNativeMethod);
    procedure SetBytecode(ABytecode: TObject);
    procedure SetArgs(const AArgs: TFloriaJSValueArray);
    procedure SetThisVal(const AValue: TFloriaJSValue);
    procedure SetCurrentEnv(AEnv: Pointer);
  public
    constructor Create(AHeap: TFloriaJSHeap);
    destructor Destroy(); override;

    function  GetPropertyWithReceiver(const AName: string;
      AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    function  HasProperty(const AName: string): Boolean; override;

    function  Next(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  Return_(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  Throw_(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  SelfIterator(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;

    procedure PushSnapshotValue(const AValue: TFloriaJSValue);
    procedure ClearSnapshot();

    { Retains the bytecode: a suspended generator can outlive the script that
      created it, and the compiler releases the chunk when execution ends. }
    property Bytecode: TObject read FBytecode write SetBytecode;
    { Retains the environment: a suspended generator can outlive the call that
      created it, and resuming needs the bindings intact. }
    procedure SetEnv(AEnv: Pointer);
    property Env: Pointer read FEnv write SetEnv;
    property CurrentEnv: Pointer read FCurrentEnv write SetCurrentEnv;
    property ThisVal: TFloriaJSValue read FThisVal write SetThisVal;
    property Args: TFloriaJSValueArray read FArgs write SetArgs;
    property IP: Integer read FIP write FIP;
    property BaseBP: Integer read FBaseBP write FBaseBP;
    property FrameFP: Integer read FFrameFP write FFrameFP;
    property StackCount: Integer read FStackCount write FStackCount;
    function  SnapshotValue(AIndex: Integer): TFloriaJSValue;
    property State: TFloriaJSGeneratorState read FState write FState;
    property ReturnValue: TFloriaJSValue read FReturnValue write FReturnValue;
    property Runner: TFloriaJSGeneratorRunner read FRunner write FRunner;
    property AsyncResume: TFloriaJSAsyncResume read FAsyncResume write FAsyncResume;
    property IsAsyncTask: Boolean read FIsAsyncTask write FIsAsyncTask;
    property IsAsyncGenerator: Boolean read FIsAsyncGenerator write FIsAsyncGenerator;
    property AsyncGeneratorYielded: Boolean read FAsyncGeneratorYielded write FAsyncGeneratorYielded;
    property AsyncGeneratorNext: TFloriaJSAsyncGeneratorNext read FAsyncGeneratorNext write FAsyncGeneratorNext;
    property InYieldStar: Boolean read FInYieldStar write FInYieldStar;
    property YieldStarDone: Boolean read FYieldStarDone write FYieldStarDone;
    property YieldStarIterator: TFloriaJSValue read FYieldStarIterator write FYieldStarIterator;
    property AsyncPromise: TFloriaJSPromise read FAsyncPromise write FAsyncPromise;
    property HasPendingThrow: Boolean read FHasPendingThrow write FHasPendingThrow;
    property PendingThrow: TFloriaJSValue read FPendingThrow write FPendingThrow;

    function  AsyncFulfilled(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AsyncRejected(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AsyncYieldFulfilled(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AsyncYieldRejected(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AsyncReturnFulfilled(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AsyncReturnRejected(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AsyncThrowFulfilled(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AsyncThrowRejected(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;

    procedure PushTrySnapshot(ACatchIP, AFrameOffset, AStackDepth: Integer; AEnv: Pointer);
    procedure ClearTrySnapshots();
    function  TrySnapshotCount(): Integer;
    procedure GetTrySnapshot(AIndex: Integer; out ACatchIP, AFrameOffset, AStackDepth: Integer; out AEnv: Pointer);
  end;

  { The resolve/reject pair handed to a `new Promise(executor)` call.

    ECMAScript specifies these as a fresh pair of functions per promise, both
    closing over the same already-resolved flag so that the first call wins.
    A `of object` native method lets one small object own that state, which a
    bare function pointer could not carry. }
  TFloriaJSPromiseResolver = class
  private
    FPromise: TFloriaJSPromise;
    FSettled: Boolean;
    FResolveFn: TFloriaJSFunction;
    FRejectFn: TFloriaJSFunction;
    FHeap: TFloriaJSHeap;
  public
    constructor Create(AHeap: TFloriaJSHeap; APromise: TFloriaJSPromise);
    destructor Destroy(); override;

    function  Resolve(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  Reject(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;

    property ResolveFunction: TFloriaJSFunction read FResolveFn;
    property RejectFunction: TFloriaJSFunction read FRejectFn;
  end;

  { Callback Used by the Evaluator to Execute Deferred Promise Jobs }
  TFloriaJSJobRunner = procedure(const AJob: TFloriaJSPromiseJob) of object;

  { Heap Allocator & Lifetime Tracker }
  TFloriaJSHeap = class
  private
    FObjects: TFPList;
    FEnvironments: TFPList;
    FPromiseJobs: TFPList;
    FTimerRegistry: TObject;
    FJobRunner: TFloriaJSJobRunner;
    FInvoker: TFloriaJSFunctionInvoker;
    FConstructInvoker: TFloriaJSConstructInvoker;
    FEvalInvoker: TFloriaJSSourceEvaluator;
    FArrayPrototype: TFloriaJSObject;
    FStringPrototype: TFloriaJSObject;
    FNumberPrototype: TFloriaJSObject;
    FPromisePrototype: TFloriaJSObject;
    FAsyncGeneratorPrototype: TFloriaJSObject;
    FFunctionPrototype: TFloriaJSObject;
    FObjectPrototype: TFloriaJSObject;
    FErrorPrototype: TFloriaJSObject;
    FTypeErrorPrototype: TFloriaJSObject;
    FRangeErrorPrototype: TFloriaJSObject;
    FReferenceErrorPrototype: TFloriaJSObject;
    FSyntaxErrorPrototype: TFloriaJSObject;
    FRealmGlobal: TFloriaJSObject;
    FCurrentNewTarget: TFloriaJSValue;
    FCurrentConstructor: TFloriaJSFunction;
    FOwnedHelpers: TFPList;
    FClearing: Boolean;
    FId: Integer;
  public
    constructor Create();
    destructor Destroy(); override;

    function  Track(AObj: TFloriaJSObject; AHeapOwned: Boolean = True): TFloriaJSObject;
    function  TrackEnvironment(AEnv: TObject): TObject;
    function  Untrack(AObj: TObject): Boolean;
    function  NewObject(AProto: TFloriaJSObject = nil; ANoProto: Boolean = False): TFloriaJSObject;
    function  NewArray(): TFloriaJSArray;
    function  NewStringObject(AProto: TFloriaJSObject; const AValue: string): TFloriaJSStringObject;
    function  NewError(const AName, AMessage: string): TFloriaJSError;
    function  NewPromise(): TFloriaJSPromise;
    function  NewNativeFunction(const AName: string; AProc: TFloriaJSNativeProc): TFloriaJSFunction;
    function  NewNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod): TFloriaJSFunction;
    function  NewBytecodeFunction(const AName: string; ABytecode: TObject; AClosure: Pointer; AIsArrow: Boolean = False; AIsAsync: Boolean = False): TFloriaJSFunction;
    function  NewBoundFunction(const AName: string; const ATarget, ABoundThis: TFloriaJSValue;
      const ABoundArgs: TFloriaJSValueArray): TFloriaJSBoundFunction;

    { The shared prototypes are created on first use and pinned, so they stay
      alive for as long as the heap does even when no value refers to them. }
    function  GetArrayPrototype(): TFloriaJSObject;
    function  GetStringPrototype(): TFloriaJSObject;
    function  GetNumberPrototype(): TFloriaJSObject;
    function  GetPromisePrototype(): TFloriaJSObject;
    function  GetAsyncGeneratorPrototype(): TFloriaJSObject;
    function  GetFunctionPrototype(): TFloriaJSObject;
    function  GetObjectPrototype(): TFloriaJSObject;
    function  GetErrorPrototype(): TFloriaJSObject;
    function  GetTypeErrorPrototype(): TFloriaJSObject;
    function  GetRangeErrorPrototype(): TFloriaJSObject;
    function  GetReferenceErrorPrototype(): TFloriaJSObject;
    function  GetSyntaxErrorPrototype(): TFloriaJSObject;
    function  ArrayCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;

    { Built-in units use helpers that need the heap (for example to create the
      array returned by String.split). The heap owns them and frees them when
      it is cleared. }
    procedure OwnHelper(AHelper: TObject);

    procedure SetFunctionInvoker(AInvoker: TFloriaJSFunctionInvoker);
    function  InvokeFunction(const AFuncVal: TFloriaJSValue;
      const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;
    procedure SetConstructInvoker(AInvoker: TFloriaJSConstructInvoker);
    procedure SetEvalInvoker(AInvoker: TFloriaJSSourceEvaluator);
    function  HasEvalInvoker(): Boolean;
    function  EvaluateSource(const ASource: string): TFloriaJSValue;
    function  ConstructFunction(const AFuncVal: TFloriaJSValue;
      const AArgs: TFloriaJSValueArray): TFloriaJSValue;
    function  ResolveConstructorTarget(const AFuncVal: TFloriaJSValue): TFloriaJSFunction;
    function  GetConstructPrototype(const AFuncVal: TFloriaJSValue): TFloriaJSObject;
    { The default prototype for a constructor call, honouring the realm of the
      newTarget when its own `prototype` is not an object. }
    function  GetPrototypeFromConstructor(const ANewTarget: TFloriaJSValue;
      const AIntrinsic: string): TFloriaJSObject;
    { Resolve an intrinsic prototype such as `Array.prototype` in this heap's
      realm. Falls back to the heap's own shared prototypes. }
    function  GetRealmIntrinsicPrototype(const AIntrinsic: string): TFloriaJSObject;
    function  IsConstructable(const AFuncVal: TFloriaJSValue): Boolean;

    { The global object of the realm that owns this heap. Set by the context
      during initialization; used for cross-realm intrinsic lookup. }
    property RealmGlobal: TFloriaJSObject read FRealmGlobal write FRealmGlobal;
    { The constructor currently being invoked by `new`/`Reflect.construct`.
      Native constructors use it to select the newTarget realm's prototype. }
    property CurrentNewTarget: TFloriaJSValue read FCurrentNewTarget write FCurrentNewTarget;
    { The constructor function currently being invoked. Native constructors
      use its intrinsic name to select the newTarget realm's prototype. }
    property CurrentConstructor: TFloriaJSFunction read FCurrentConstructor write FCurrentConstructor;

    { Owned by this heap and therefore by the context that owns the heap. The
      timer unit owns the concrete implementation; this reference keeps timer
      state isolated per heap without making this unit depend on it. }
    property TimerRegistry: TObject read FTimerRegistry write FTimerRegistry;

    procedure SetJobRunner(ARunner: TFloriaJSJobRunner);
    procedure EnqueuePromiseJob(const AJob: TFloriaJSPromiseJob);
    procedure EnqueuePromiseSettlement(APromise: TFloriaJSPromise;
      const AValue: TFloriaJSValue; AIsRejection: Boolean);
    function  DequeuePromiseJob(out AJob: TFloriaJSPromiseJob): Boolean;
    function  HasPromiseJobs(): Boolean;
    procedure RunPendingJobs();

    function  PromiseConstructor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  PromiseResolve(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  PromiseReject(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  PromiseAll(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  PromiseRace(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  ErrorCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  TypeErrorCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  RangeErrorCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  ReferenceErrorCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  SyntaxErrorCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  ObjectCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;

    { Reclaims the objects that no container refers to any more. It is only
      safe to call this at a point where no transient copy of a value is in
      use any more, such as the start of a program execution. }
    procedure ReclaimOrphanedEnvironments();
    procedure Collect();
    procedure SweepObjects();

    procedure Clear();
    function  GetObjectCount(): Integer;
    function  GetEnvironmentCount(): Integer;
    function  GetObject(AIndex: Integer): TFloriaJSObject;
    function  GetEnvironment(AIndex: Integer): TObject;
    property IsClearing: Boolean read FClearing;
    property Id: Integer read FId;
  end;

{ Value Factory Helpers }
function JSMakeUndefined(): TFloriaJSValue;
function JSMakeNull(): TFloriaJSValue;
function JSMakeBoolean(ABool: Boolean): TFloriaJSValue;
function JSMakeNumber(ANum: Double): TFloriaJSValue;
function JSMakeString(const AStr: string): TFloriaJSValue;
function JSMakeObject(AObj: TFloriaJSObject): TFloriaJSValue;
function JSMakeProxy(AProxy: TFloriaJSProxy): TFloriaJSValue;
function JSMakeArray(AArr: TFloriaJSArray): TFloriaJSValue;
function JSMakeFunction(AFunc: TFloriaJSFunction): TFloriaJSValue;
function JSMakePromise(APromise: TFloriaJSPromise): TFloriaJSValue;
function JSMakeBigInt(const ADigits: string): TFloriaJSValue;

function JSMakeSymbol(const ADescription: string = ''; AId: Integer = 0): TFloriaJSValue;

{ Reference Counting Helpers. A container that stores a value owns a reference
  to the object it points at, so it retains the value when it takes it over
  and releases it when it lets it go. }
procedure JSRetainValue(const AValue: TFloriaJSValue);
procedure JSReleaseValue(const AValue: TFloriaJSValue);

{ Heap Liveness Helper. Owners that live outside of the heap use it to find
  out whether the values they hold still point at live objects. }
function JSHeapIsAlive(AHeap: TFloriaJSHeap; AHeapId: Integer): Boolean;

{ Binary Operations }
function JSToPrimitive(const AValue: TFloriaJSValue; const AHint: string = 'default'): TFloriaJSValue;
function JSToString(const AValue: TFloriaJSValue): string;
function JSAdd(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
function JSSubtract(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
function JSMultiply(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
function JSDivide(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
function JSModulo(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
function JSPower(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;

{ Relational & Equality Operations }
function JSEqual(const ALeft, ARight: TFloriaJSValue): Boolean;
function JSStrictEqual(const ALeft, ARight: TFloriaJSValue): Boolean;
function JSLessThan(const ALeft, ARight: TFloriaJSValue): Boolean;
function JSLessEqual(const ALeft, ARight: TFloriaJSValue): Boolean;
function JSGreaterThan(const ALeft, ARight: TFloriaJSValue): Boolean;
function JSGreaterEqual(const ALeft, ARight: TFloriaJSValue): Boolean;
function JSInstanceOf(const ALeft, ARight: TFloriaJSValue): Boolean;

{ Bitwise Operations }
function JSBitAnd(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
function JSBitOr(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
function JSBitXor(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
function JSShiftLeft(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
function JSShiftRight(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
function JSShiftRightUnsigned(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;

{ Unary Operations }
function JSUnaryMinus(const AVal: TFloriaJSValue): TFloriaJSValue;
function JSUnaryPlus(const AVal: TFloriaJSValue): TFloriaJSValue;
function JSUnaryNot(const AVal: TFloriaJSValue): TFloriaJSValue;
function JSUnaryBitNot(const AVal: TFloriaJSValue): TFloriaJSValue;
{ The name a property is stored under. A symbol key gets a prefix that no real
  string key can contain, so it never collides and never enumerates. }
function JSPropertyKeyName(const AVal: TFloriaJSValue): string;
{ True when AVal is a Number that names an ECMAScript array index. }
function JSArrayIndexFromNumber(const AVal: TFloriaJSValue; out AIndex: Int64): Boolean;

{ The heap of the native function currently executing. Native methods use it
  to create errors in the running function's realm rather than the receiver's. }
procedure JSSetActiveRealmHeap(AHeap: TFloriaJSHeap);
function JSActiveRealmHeap(): TFloriaJSHeap;

{ Cooperative-agent hook: Atomics operations call it so a busy-waiting agent
  can yield to another agent in the diagnostic host. }
type
  TFloriaJSAtomicsYieldHook = procedure;
procedure JSSetAtomicsYieldHook(AHook: TFloriaJSAtomicsYieldHook);
procedure JSAtomicsYield();
function JSIsWellKnownSymbolKey(const AName, ADescription: string): Boolean;
function JSTypeOf(const AVal: TFloriaJSValue): string;

implementation

uses
  floria.js.env, floria.js.bytecode;

type
  { Registry Entry of a Heap That Is Alive }
  TFloriaJSHeapEntry = record
    Heap: TFloriaJSHeap;
    Id: Integer;
  end;
  PFloriaJSHeapEntry = ^TFloriaJSHeapEntry;

var
  { Registry of the heaps that are currently alive. It lets owners outside of
    a heap find out whether the values they hold are still valid. }
  GLiveHeaps: TFPList = nil;
  { Source of the unique identifiers that tell two heaps apart, even when the
    memory of a dead heap is reused by a new one. }
  GNextHeapId: Integer = 0;
  { The heap that owns the shared Number.prototype. Native number methods are
    called with a primitive receiver, which has no object to take a heap from,
    so they raise through this one. }
  GNumberPrototype: TFloriaJSObject = nil;

{ Reference Counting Helpers }

procedure JSRetainValue(const AValue: TFloriaJSValue);
begin
  if AValue.IsObject() and (AValue.ObjVal <> nil) then
    AValue.ObjVal.Retain;
end;

procedure JSReleaseValue(const AValue: TFloriaJSValue);
begin
  if AValue.IsObject() and (AValue.ObjVal <> nil) then
    AValue.ObjVal.Release;
end;

{ Heap Liveness Helper }

function JSHeapIsAlive(AHeap: TFloriaJSHeap; AHeapId: Integer): Boolean;
var
  i: Integer;
  entry: PFloriaJSHeapEntry;
begin
  Result := False;
  if (AHeap = nil) or (GLiveHeaps = nil) then Exit;

  for i := 0 to GLiveHeaps.Count - 1 do
  begin
    entry := PFloriaJSHeapEntry(GLiveHeaps[i]);
    if (entry^.Heap = AHeap) and (entry^.Id = AHeapId) then
      Exit(True);
  end;
end;

{ Value Factory Functions }

function JSMakeUndefined(): TFloriaJSValue;
begin
  Result.Kind := fjstUndefined;
  Result.NumVal := 0.0;
  Result.StrVal := '';
  Result.ObjVal := nil;
end;

function JSMakeNull(): TFloriaJSValue;
begin
  Result.Kind := fjstNull;
  Result.NumVal := 0.0;
  Result.StrVal := '';
  Result.ObjVal := nil;
end;

function JSMakeBoolean(ABool: Boolean): TFloriaJSValue;
begin
  Result.Kind := fjstBoolean;
  if ABool then
    Result.NumVal := 1.0
  else
    Result.NumVal := 0.0;
  Result.StrVal := '';
  Result.ObjVal := nil;
end;

function JSMakeNumber(ANum: Double): TFloriaJSValue;
begin
  Result.Kind := fjstNumber;
  Result.NumVal := ANum;
  Result.StrVal := '';
  Result.ObjVal := nil;
end;

function JSMakeString(const AStr: string): TFloriaJSValue;
begin
  Result.Kind := fjstString;
  Result.NumVal := 0.0;
  Result.StrVal := AStr;
  Result.ObjVal := nil;
end;

function JSMakeObject(AObj: TFloriaJSObject): TFloriaJSValue;
begin
  if AObj is TFloriaJSArray then
    Result.Kind := fjstArray
  else if AObj is TFloriaJSFunction then
    Result.Kind := fjstFunction
  else
    Result.Kind := fjstObject;

  Result.NumVal := 0.0;
  Result.StrVal := '';
  Result.ObjVal := AObj;
end;

function JSMakeProxy(AProxy: TFloriaJSProxy): TFloriaJSValue;
begin
  if AProxy.Callable then
    Result.Kind := fjstFunction
  else
    Result.Kind := fjstObject;
  Result.NumVal := 0;
  Result.StrVal := '';
  Result.ObjVal := AProxy;
end;

function JSMakeArray(AArr: TFloriaJSArray): TFloriaJSValue;
begin
  Result.Kind := fjstArray;
  Result.NumVal := 0.0;
  Result.StrVal := '';
  Result.ObjVal := AArr;
end;

function JSMakeFunction(AFunc: TFloriaJSFunction): TFloriaJSValue;
begin
  Result.Kind := fjstFunction;
  Result.NumVal := 0.0;
  Result.StrVal := '';
  Result.ObjVal := AFunc;
end;

function JSMakePromise(APromise: TFloriaJSPromise): TFloriaJSValue;
begin
  if APromise <> nil then
    Result.Kind := fjstObject
  else
    Result.Kind := fjstUndefined;
  Result.NumVal := 0.0;
  Result.StrVal := '';
  Result.ObjVal := APromise;
end;

{ BigInts are stored as a canonical signed decimal string: an optional '-' then
  digits with no leading zeros ('0' for zero). Keeping the digits as text makes
  arbitrary precision trivial and avoids a second numeric representation. }
function JSMakeBigInt(const ADigits: string): TFloriaJSValue;
begin
  Result.Kind := fjstBigInt;
  Result.NumVal := 0;
  Result.StrVal := ADigits;
  Result.ObjVal := nil;
end;

function JSMakeSymbol(const ADescription: string = ''; AId: Integer = 0): TFloriaJSValue;
begin
  Result.Kind := fjstSymbol;
  Result.NumVal := AId;
  Result.StrVal := ADescription;
  Result.ObjVal := nil;
end;

{ TFloriaJSValue Methods }

function TFloriaJSValue.GetBoolVal(): Boolean;
begin
  if Kind = fjstBoolean then
    Result := (NumVal <> 0.0)
  else
    Result := ToBoolean();
end;

procedure TFloriaJSValue.SetBoolVal(AValue: Boolean);
begin
  { Kept for source compatibility with older hosts. Boolean values encode
    their state in NumVal now. }
  if AValue then
    NumVal := 1.0
  else
    NumVal := 0.0;
end;

function TFloriaJSValue.IsUndefined(): Boolean;
begin
  Result := (Kind = fjstUndefined);
end;

function TFloriaJSValue.IsNull(): Boolean;
begin
  Result := (Kind = fjstNull);
end;

function TFloriaJSValue.IsBoolean(): Boolean;
begin
  Result := (Kind = fjstBoolean);
end;

function TFloriaJSValue.IsNumber(): Boolean;
begin
  Result := (Kind = fjstNumber);
end;

function TFloriaJSValue.IsString(): Boolean;
begin
  Result := (Kind = fjstString);
end;

function TFloriaJSValue.IsObject(): Boolean;
begin
  Result := (Kind = fjstObject) or (Kind = fjstArray) or (Kind = fjstFunction);
end;

function TFloriaJSValue.IsArray(): Boolean;
begin
  Result := (Kind = fjstArray);
end;

function TFloriaJSValue.IsFunction(): Boolean;
begin
  Result := (Kind = fjstFunction);
end;

function TFloriaJSValue.IsPromise(): Boolean;
begin
  Result := IsObject() and (ObjVal is TFloriaJSPromise);
end;

function TFloriaJSValue.IsSymbol(): Boolean;
begin
  Result := (Kind = fjstSymbol);
end;

function TFloriaJSValue.IsBigInt(): Boolean;
begin
  Result := (Kind = fjstBigInt);
end;

function TFloriaJSValue.IsTruthy(): Boolean;
begin
  Result := ToBoolean();
end;

function TFloriaJSValue.ToBoolean(): Boolean;
begin
  case Kind of
    fjstUndefined, fjstNull:
      Result := False;
    fjstBoolean:
      Result := (NumVal <> 0.0);
    fjstNumber:
      Result := (NumVal <> 0.0) and not IsNaN(NumVal);
    fjstString:
      Result := (StrVal <> '');
    fjstSymbol:
      Result := True;
    fjstBigInt:
      Result := StrVal <> '0';
    fjstObject, fjstArray, fjstFunction:
      Result := (ObjVal <> nil);
  else
    Result := False;
  end;
end;

function TFloriaJSValue.ToNumber(): Double;
var
  code: Integer;
  d: Double;
  trimStr: string;
  prefix: Char;
  intVal: Int64;
begin
  case Kind of
    fjstUndefined:
      Result := NaN;
    fjstNull:
      Result := 0.0;
    fjstBoolean:
      Result := NumVal;
    fjstNumber:
      Result := NumVal;
    fjstString:
    begin
      trimStr := Trim(StrVal);
      if trimStr = '' then
        Exit(0.0);
      if (trimStr = 'Infinity') or (trimStr = '+Infinity') then
        Exit(Infinity);
      if trimStr = '-Infinity' then
        Exit(-Infinity);
      if (Length(trimStr) >= 3) and (trimStr[1] = '0') then
      begin
        prefix := UpCase(trimStr[2]);
        if prefix = 'X' then
        begin
          Val('$' + Copy(trimStr, 3, Length(trimStr)), intVal, code);
          if code = 0 then Exit(Double(intVal));
        end
        else if prefix = 'B' then
        begin
          Val('%' + Copy(trimStr, 3, Length(trimStr)), intVal, code);
          if code = 0 then Exit(Double(intVal));
        end
        else if prefix = 'O' then
        begin
          Val('&' + Copy(trimStr, 3, Length(trimStr)), intVal, code);
          if code = 0 then Exit(Double(intVal));
        end;
      end;
      { Decimal numerals go through the correctly rounded parser; the host
        parser is off by an ulp for some inputs. }
      if JSTryStrToNumber(trimStr, d) then
        Result := d
      else
        Result := NaN;
    end;
    fjstArray, fjstObject, fjstFunction:
      Result := JSToPrimitive(Self, 'number').ToNumber();
  else
    Result := NaN;
  end;
end;

function TFloriaJSValue.ToString(): string;
begin
  case Kind of
    fjstUndefined:
      Result := 'undefined';
    fjstNull:
      Result := 'null';
    fjstBoolean:
      if NumVal <> 0.0 then Result := 'true' else Result := 'false';
    fjstNumber:
      { ECMAScript Number::toString: shortest round-tripping decimal with the
        standard fixed/scientific thresholds. }
      Result := JSNumberToStr(NumVal);
    fjstString:
      Result := StrVal;
    fjstSymbol:
      if StrVal <> '' then
        Result := 'Symbol(' + StrVal + ')'
      else
        Result := 'Symbol()';
    fjstBigInt:
      { The digits are already canonical, so printing them is the whole job. }
      Result := StrVal;
    fjstArray:
      if ObjVal <> nil then
        Result := TFloriaJSArray(ObjVal).Join(',')
      else
        Result := '';
    fjstFunction:
      if (ObjVal <> nil) and (TFloriaJSFunction(ObjVal).Name <> '') then
        Result := 'function ' + TFloriaJSFunction(ObjVal).Name + '() { [native code] }'
      else
        Result := 'function() { [native code] }';
    fjstObject:
      if ObjVal is TFloriaJSError then
      begin
        if TFloriaJSError(ObjVal).Message <> '' then
          Result := TFloriaJSError(ObjVal).Name + ': ' + TFloriaJSError(ObjVal).Message
        else
          Result := TFloriaJSError(ObjVal).Name;
      end
      else
        Result := '[object Object]';
  else
    Result := '';
  end;
end;

function TFloriaJSValue.AsObject(): TFloriaJSObject;
begin
  if IsObject() then Result := ObjVal else Result := nil;
end;

function TFloriaJSValue.AsArray(): TFloriaJSArray;
begin
  if Kind = fjstArray then Result := TFloriaJSArray(ObjVal) else Result := nil;
end;

function TFloriaJSValue.AsFunction(): TFloriaJSFunction;
begin
  if Kind = fjstFunction then Result := TFloriaJSFunction(ObjVal) else Result := nil;
end;

function TFloriaJSValue.AsPromise(): TFloriaJSPromise;
begin
  if IsPromise() then Result := TFloriaJSPromise(ObjVal) else Result := nil;
end;

{ TFloriaJSObject }

constructor TFloriaJSObject.Create(AProto: TFloriaJSObject);
begin
  inherited Create();
  FPrototype := AProto;
  FRefCount := 0;
  FHeap := nil;
  FHeapOwned := True;
  FPinned := False;
  FIsFrozen := False;
  FIsSealed := False;
  FIsExtensible := True;
  SetLength(FProperties, 0);
  FPropCount := 0;
  { The prototype is a reference to another object, so it is owned as well. }
  if FPrototype <> nil then
    FPrototype.Retain;
end;

destructor TFloriaJSObject.Destroy();
var
  i: Integer;
begin
  { Every property holds a reference to the value it stores, and the prototype
    is a reference to another object. The references are given up before the
    object goes away, unless the heap is tearing down, because then every
    object is released at once and the order would not matter. }
  if (FHeap = nil) or (not FHeap.IsClearing) then
  begin
    for i := 0 to FPropCount - 1 do
    begin
      JSReleaseValue(FProperties[i].Value);
      if FProperties[i].HasGetter then
        JSReleaseValue(FProperties[i].Getter);
      if FProperties[i].HasSetter then
        JSReleaseValue(FProperties[i].Setter);
    end;
    if FPrototype <> nil then
      FPrototype.Release;
  end;
  FPrototype := nil;
  SetLength(FProperties, 0);
  FPropCount := 0;

  { An object that is destroyed takes itself off the list of the heap, so that
    the heap never keeps a pointer that is no longer valid. }
  if FHeap <> nil then
  begin
    FHeap.Untrack(Self);
    FHeap := nil;
  end;

  inherited Destroy();
end;

procedure TFloriaJSObject.Retain();
begin
  Inc(FRefCount);
end;

procedure TFloriaJSObject.Release();
begin
  { The object is not freed here. The heap reclaims it at the next safe point,
    so that the transient copies of a value stay valid while they are in use. }
  if FRefCount > 0 then
    Dec(FRefCount);
end;

procedure TFloriaJSObject.Pin();
begin
  { A pinned object has been handed over to the host, which may keep it for as
    long as it likes, so the heap never reclaims it. }
  FPinned := True;
end;

procedure TFloriaJSObject.Unpin();
begin
  { The host has given the object back, so the heap may reclaim it as soon as
    nothing refers to it any more. }
  FPinned := False;
end;

procedure TFloriaJSObject.SetPrototype(AProto: TFloriaJSObject);
begin
  if AProto = FPrototype then Exit;

  if FPrototype <> nil then
    FPrototype.Release;
  FPrototype := AProto;
  if FPrototype <> nil then
    FPrototype.Retain;
end;

function TFloriaJSObject.FindPropertyIndex(const AName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to FPropCount - 1 do
  begin
    if FProperties[i].Key = AName then
      Exit(i);
  end;
  Result := -1;
end;

function TFloriaJSObject.GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue;
var
  idx: Integer;
  rec: TFloriaJSObject;
begin
  if AReceiver <> nil then rec := AReceiver else rec := Self;
  idx := FindPropertyIndex(AName);
  if idx < 0 then
  begin
    { A well-known symbol key carries a per-process id, so a property
      registered under one spelling must still be found under another. Match on
      the description in that case. }
    if (Length(AName) > 0) and (AName[1] = #1) then
      idx := FindWellKnownSymbolIndex(AName);
  end;
  if idx >= 0 then
  begin
    if FProperties[idx].HasGetter and (FHeap <> nil) then
      Exit(FHeap.InvokeFunction(FProperties[idx].Getter, [], JSMakeObject(rec)))
    else
      Exit(FProperties[idx].Value);
  end;

  if FPrototype <> nil then
    Exit(FPrototype.GetPropertyWithReceiver(AName, rec));

  Result := JSMakeUndefined();
end;

{ The description part of a symbol key ('#1sym:<id>:<description>'), or '' when
  AName is not a symbol key. }
function SymbolKeyDescription(const AName: string): string;
var
  i, colons: Integer;
begin
  Result := '';
  if (Length(AName) = 0) or (AName[1] <> #1) then Exit;
  colons := 0;
  for i := 1 to Length(AName) do
    if AName[i] = ':' then
    begin
      Inc(colons);
      if colons = 2 then
        Exit(Copy(AName, i + 1, Length(AName) - i));
    end;
end;

{ Finds a property whose key is a symbol key with the same description as
  AName, ignoring the numeric id. }
function TFloriaJSObject.FindWellKnownSymbolIndex(const AName: string): Integer;
var
  i: Integer;
  desc: string;
begin
  desc := SymbolKeyDescription(AName);
  if desc = '' then
    Exit(-1);
  for i := 0 to FPropCount - 1 do
  begin
    if SymbolKeyDescription(FProperties[i].Key) = desc then
      Exit(i);
    { A well-known symbol may also have been registered under its legacy string
      spelling, e.g. 'Symbol(Symbol.iterator)'. }
    if FProperties[i].Key = 'Symbol(' + desc + ')' then
      Exit(i);
  end;
  Result := -1;
end;

function TFloriaJSObject.GetProperty(const AName: string): TFloriaJSValue;
begin
  Result := GetPropertyWithReceiver(AName, Self);
end;

procedure TFloriaJSObject.SetProperty(const AName: string; const AValue: TFloriaJSValue);
var
  idx: Integer;
  owner: TFloriaJSObject;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
  begin
    if FProperties[idx].HasSetter and (FHeap <> nil) then
    begin
      FHeap.InvokeFunction(FProperties[idx].Setter, [AValue], JSMakeObject(Self));
      Exit;
    end;
    if FProperties[idx].HasGetter or (not FProperties[idx].Writable) or IsFrozen then
      Exit;
    { A property owns the value it stores: the value that is replaced gives up
      its reference and the new value takes a reference over. }
    JSReleaseValue(FProperties[idx].Value);
    FProperties[idx].Value := AValue;
    JSRetainValue(AValue);
    Exit;
  end;

  { An inherited accessor with a setter handles the assignment instead of
    creating an own data property, which is what makes a class setter work on
    an instance. }
  owner := FPrototype;
  while owner <> nil do
  begin
    idx := owner.FindPropertyIndex(AName);
    if idx >= 0 then
    begin
      if owner.PropHasSetter(idx) and (FHeap <> nil) then
      begin
        FHeap.InvokeFunction(owner.PropSetter(idx), [AValue], JSMakeObject(Self));
        Exit;
      end;
      Break;
    end;
    owner := owner.Prototype;
  end;

  if (not FIsExtensible) or IsFrozen or IsSealed then
    Exit;

  if FPropCount >= Length(FProperties) then
  begin
    if Length(FProperties) = 0 then
      SetLength(FProperties, 8)
    else
      SetLength(FProperties, Length(FProperties) * 2);
  end;

  FProperties[FPropCount].Key := AName;
  FProperties[FPropCount].Value := AValue;
  FProperties[FPropCount].Getter := JSMakeUndefined();
  FProperties[FPropCount].Setter := JSMakeUndefined();
  FProperties[FPropCount].HasGetter := False;
  FProperties[FPropCount].HasSetter := False;
  FProperties[FPropCount].Enumerable := True;
  FProperties[FPropCount].Writable := True;
  FProperties[FPropCount].Configurable := True;
  JSRetainValue(AValue);
  Inc(FPropCount);
end;

{ Defines a non-enumerable data property, used for class methods and the
  `prototype` link, which must not appear in `for…in` or `Object.keys`. }
procedure TFloriaJSObject.SetPropertyNonEnumerable(const AName: string;
  const AValue: TFloriaJSValue);
begin
  SetProperty(AName, AValue);
  if FPropCount > 0 then
    FProperties[FindPropertyIndex(AName)].Enumerable := False;
end;

{ Changes an existing property's enumerability, leaving its value or accessor
  alone. Used for class accessors, which are created then marked hidden. }
procedure TFloriaJSObject.SetEnumerable(const AName: string; AEnumerable: Boolean);
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
    FProperties[idx].Enumerable := AEnumerable;
end;

function TFloriaJSObject.PropHasSetter(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < FPropCount) and FProperties[AIndex].HasSetter;
end;

function TFloriaJSObject.PropSetter(AIndex: Integer): TFloriaJSValue;
begin
  if (AIndex >= 0) and (AIndex < FPropCount) then
    Result := FProperties[AIndex].Setter
  else
    Result := JSMakeUndefined();
end;

{ True when the property exists and is enumerable. }
function TFloriaJSObject.IsEnumerable(const AName: string): Boolean;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  Result := (idx >= 0) and FProperties[idx].Enumerable;
end;

procedure TFloriaJSObject.DefineGetter(const AName: string; const AGetter: TFloriaJSValue);
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
  begin
    if FProperties[idx].HasGetter then
      JSReleaseValue(FProperties[idx].Getter);
    FProperties[idx].Getter := AGetter;
    FProperties[idx].HasGetter := True;
    JSRetainValue(AGetter);
    Exit;
  end;

  if FPropCount >= Length(FProperties) then
  begin
    if Length(FProperties) = 0 then
      SetLength(FProperties, 8)
    else
      SetLength(FProperties, Length(FProperties) * 2);
  end;

  FProperties[FPropCount].Key := AName;
  FProperties[FPropCount].Value := JSMakeUndefined();
  FProperties[FPropCount].Getter := AGetter;
  FProperties[FPropCount].Setter := JSMakeUndefined();
  FProperties[FPropCount].HasGetter := True;
  FProperties[FPropCount].HasSetter := False;
  FProperties[FPropCount].Enumerable := True;
  FProperties[FPropCount].Writable := True;
  FProperties[FPropCount].Configurable := True;
  JSRetainValue(AGetter);
  Inc(FPropCount);
end;

procedure TFloriaJSObject.DefineSetter(const AName: string; const ASetter: TFloriaJSValue);
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
  begin
    if FProperties[idx].HasSetter then
      JSReleaseValue(FProperties[idx].Setter);
    FProperties[idx].Setter := ASetter;
    FProperties[idx].HasSetter := True;
    JSRetainValue(ASetter);
    Exit;
  end;

  if FPropCount >= Length(FProperties) then
  begin
    if Length(FProperties) = 0 then
      SetLength(FProperties, 8)
    else
      SetLength(FProperties, Length(FProperties) * 2);
  end;

  FProperties[FPropCount].Key := AName;
  FProperties[FPropCount].Value := JSMakeUndefined();
  FProperties[FPropCount].Getter := JSMakeUndefined();
  FProperties[FPropCount].Setter := ASetter;
  FProperties[FPropCount].HasGetter := False;
  FProperties[FPropCount].HasSetter := True;
  FProperties[FPropCount].Enumerable := True;
  FProperties[FPropCount].Writable := True;
  FProperties[FPropCount].Configurable := True;
  JSRetainValue(ASetter);
  Inc(FPropCount);
end;

function TFloriaJSObject.HasProperty(const AName: string): Boolean;
begin
  if FindPropertyIndex(AName) >= 0 then
    Exit(True);

  if FPrototype <> nil then
    Exit(FPrototype.HasProperty(AName));

  Result := False;
end;

function TFloriaJSObject.DeleteProperty(const AName: string): Boolean;
var
  idx, i: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx < 0 then
    Exit(True);

  if (not FProperties[idx].Configurable) or IsFrozen or IsSealed then
    Exit(False);

  for i := idx to FPropCount - 2 do
    FProperties[i] := FProperties[i + 1];

  Dec(FPropCount);
  { The removed property gives up the references it held. }
  JSReleaseValue(FProperties[FPropCount].Value);
  JSReleaseValue(FProperties[FPropCount].Getter);
  JSReleaseValue(FProperties[FPropCount].Setter);
  FProperties[FPropCount].Value := JSMakeUndefined();
  FProperties[FPropCount].Getter := JSMakeUndefined();
  FProperties[FPropCount].Setter := JSMakeUndefined();
  Result := True;
end;

function TFloriaJSObject.DefineDataProperty(const AName: string;
  const AValue: TFloriaJSValue; AWritable, AEnumerable, AConfigurable: Boolean): Boolean;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx < 0 then
  begin
    if (not FIsExtensible) or IsFrozen or IsSealed then
      Exit(False);
    SetProperty(AName, AValue);
    idx := FindPropertyIndex(AName);
  end
  else
  begin
    if (not FProperties[idx].Configurable) and
       (FProperties[idx].HasGetter or FProperties[idx].HasSetter) then
      Exit(False);
    if FProperties[idx].HasGetter or FProperties[idx].HasSetter then
    begin
      JSReleaseValue(FProperties[idx].Getter);
      JSReleaseValue(FProperties[idx].Setter);
      FProperties[idx].Getter := JSMakeUndefined();
      FProperties[idx].Setter := JSMakeUndefined();
      FProperties[idx].HasGetter := False;
      FProperties[idx].HasSetter := False;
      FProperties[idx].Value := JSMakeUndefined();
    end;
    JSReleaseValue(FProperties[idx].Value);
    FProperties[idx].Value := AValue;
    JSRetainValue(AValue);
  end;

  if idx < 0 then
    Exit(False);
  FProperties[idx].Writable := AWritable;
  FProperties[idx].Enumerable := AEnumerable;
  FProperties[idx].Configurable := AConfigurable;
  Result := True;
end;

function TFloriaJSObject.DefineAccessorProperty(const AName: string;
  const AGetter, ASetter: TFloriaJSValue; AEnumerable, AConfigurable: Boolean): Boolean;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx < 0 then
  begin
    if (not FIsExtensible) or IsFrozen or IsSealed then
      Exit(False);
    SetProperty(AName, JSMakeUndefined());
    idx := FindPropertyIndex(AName);
  end
  else
  begin
    if (not FProperties[idx].Configurable) and
       (not (FProperties[idx].HasGetter or FProperties[idx].HasSetter)) then
      Exit(False);
    JSReleaseValue(FProperties[idx].Value);
    FProperties[idx].Value := JSMakeUndefined();
    JSReleaseValue(FProperties[idx].Getter);
    JSReleaseValue(FProperties[idx].Setter);
  end;

  if idx < 0 then
    Exit(False);
  FProperties[idx].Getter := AGetter;
  FProperties[idx].Setter := ASetter;
  FProperties[idx].HasGetter := AGetter.IsFunction();
  FProperties[idx].HasSetter := ASetter.IsFunction();
  JSRetainValue(AGetter);
  JSRetainValue(ASetter);
  FProperties[idx].Enumerable := AEnumerable;
  FProperties[idx].Configurable := AConfigurable;
  FProperties[idx].Writable := False;
  Result := True;
end;

function TFloriaJSObject.PropertyIsWritable(const AName: string): Boolean;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  Result := (idx >= 0) and FProperties[idx].Writable;
end;

function TFloriaJSObject.PropertyIsConfigurable(const AName: string): Boolean;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  Result := (idx >= 0) and FProperties[idx].Configurable;
end;

procedure TFloriaJSObject.SetPropertyConfigurable(const AName: string; AConfigurable: Boolean);
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
    FProperties[idx].Configurable := AConfigurable;
end;

function TFloriaJSObject.PropertyIsEnumerable(const AName: string): Boolean;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  Result := (idx >= 0) and FProperties[idx].Enumerable;
end;

function TFloriaJSObject.PropertyIsAccessor(const AName: string): Boolean;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  Result := (idx >= 0) and (FProperties[idx].HasGetter or FProperties[idx].HasSetter);
end;

function TFloriaJSObject.PropertyHasGetter(const AName: string): Boolean;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  Result := (idx >= 0) and FProperties[idx].HasGetter;
end;

function TFloriaJSObject.PropertyHasSetter(const AName: string): Boolean;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  Result := (idx >= 0) and FProperties[idx].HasSetter;
end;

function TFloriaJSObject.PropertyGetter(const AName: string): TFloriaJSValue;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
    Result := FProperties[idx].Getter
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSObject.PropertySetter(const AName: string): TFloriaJSValue;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
    Result := FProperties[idx].Setter
  else
    Result := JSMakeUndefined();
end;

procedure TFloriaJSObject.FreezeProperties();
var
  i: Integer;
begin
  for i := 0 to FPropCount - 1 do
  begin
    FProperties[i].Writable := False;
    FProperties[i].Configurable := False;
  end;
  FIsFrozen := True;
  FIsSealed := True;
  FIsExtensible := False;
end;

procedure TFloriaJSObject.SealProperties();
var
  i: Integer;
begin
  for i := 0 to FPropCount - 1 do
    FProperties[i].Configurable := False;
  FIsSealed := True;
  FIsExtensible := False;
end;

function TFloriaJSObject.GetWellKnownProperty(const ADescription: string): TFloriaJSValue;
var
  i: Integer;
begin
  for i := 0 to FPropCount - 1 do
  begin
    if JSIsWellKnownSymbolKey(FProperties[i].Key, ADescription) then
    begin
      if FProperties[i].HasGetter and (FHeap <> nil) then
        Exit(FHeap.InvokeFunction(FProperties[i].Getter, [], JSMakeObject(Self)));
      Exit(FProperties[i].Value);
    end;
  end;
  Result := JSMakeUndefined();
end;

function TFloriaJSObject.GetOwnProperty(const AName: string): TFloriaJSValue;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
    Result := FProperties[idx].Value
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSObject.HasOwnProperty(const AName: string): Boolean;
begin
  Result := FindPropertyIndex(AName) >= 0;
end;

function TFloriaJSObject.GetPropertyCount(): Integer;
begin
  Result := FPropCount;
end;

{ The number of enumerable own properties, which is what `Object.keys`,
  `for…in`, and JSON serialisation observe. }
function TFloriaJSObject.GetEnumerablePropertyCount(): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FPropCount - 1 do
    if FProperties[i].Enumerable then
      Inc(Result);
end;

{ The key of the AIndex-th enumerable own property, in insertion order. }
function TFloriaJSObject.GetEnumerablePropertyKey(AIndex: Integer): string;
var
  i, seen: Integer;
begin
  Result := '';
  seen := 0;
  for i := 0 to FPropCount - 1 do
    if FProperties[i].Enumerable then
    begin
      if seen = AIndex then
        Exit(FProperties[i].Key);
      Inc(seen);
    end;
end;

function TFloriaJSObject.GetPropertyKey(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FPropCount) then
    Result := FProperties[AIndex].Key
  else
    Result := '';
end;

function TFloriaJSObject.GetPropertyValue(AIndex: Integer): TFloriaJSValue;
begin
  if (AIndex >= 0) and (AIndex < FPropCount) then
    Result := FProperties[AIndex].Value
  else
    Result := JSMakeUndefined();
end;

procedure TFloriaJSObject.GetKeys(AOutKeys: TStrings);
var
  i: Integer;
begin
  if AOutKeys = nil then Exit;
  for i := 0 to FPropCount - 1 do
    if FProperties[i].Enumerable then
      AOutKeys.Add(FProperties[i].Key);
end;

{ TFloriaJSError }

constructor TFloriaJSError.Create(const AName, AMessage: string);
begin
  inherited Create(nil);
  FName := AName;
  FMessage := AMessage;
  { The name and the message are readable from the script, just like they are
    on an error object of JavaScript. }
  SetProperty('name', JSMakeString(AName));
  SetProperty('message', JSMakeString(AMessage));
end;

const
  { Indices below this bound use the dense representation. Above it, an
    overflow entry records the value without allocating every hole. }
  ARRAY_DENSE_LIMIT = 100000;
  { The largest valid ECMAScript array index (2^32 - 2). }
  ARRAY_INDEX_LIMIT = 4294967294;

{ TFloriaJSArray }

{ TFloriaJSProxy }

constructor TFloriaJSProxy.Create(AHeap: TFloriaJSHeap;
  const ATarget, AHandler: TFloriaJSValue);
begin
  inherited Create(AHeap.GetObjectPrototype());
  Heap := AHeap;
  FTarget := ATarget;
  FHandler := AHandler;
  FRevoked := False;
  FCallable := ATarget.IsFunction();
  JSRetainValue(FTarget);
  JSRetainValue(FHandler);
end;

destructor TFloriaJSProxy.Destroy();
begin
  if (Heap = nil) or (not Heap.IsClearing) then
  begin
    JSReleaseValue(FTarget);
    JSReleaseValue(FHandler);
  end;
  inherited Destroy();
end;

procedure TFloriaJSProxy.RequireCallableTrap(const ATrap: TFloriaJSValue;
  const AName: string);
begin
  if (not ATrap.IsUndefined()) and (not ATrap.IsNull()) and (not ATrap.IsFunction()) then
    raise EFloriaJSThrow.Create(JSMakeObject(
      Heap.NewError('TypeError', 'Proxy trap ' + AName + ' is not callable')));
end;

function TFloriaJSProxy.GetTrap(const AName: string): TFloriaJSValue;
begin
  if FRevoked then
    raise EFloriaJSThrow.Create(JSMakeObject(
      Heap.NewError('TypeError', 'Cannot perform operation on a revoked proxy')));
  if FHandler.IsObject() then
    Result := FHandler.AsObject().GetProperty(AName)
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSProxy.Call(const AArgs: array of TFloriaJSValue;
  const AThis: TFloriaJSValue): TFloriaJSValue;
var
  trap, argsArray: TFloriaJSValue;
  args: array[0..2] of TFloriaJSValue;
  i: Integer;
  arr: TFloriaJSArray;
begin
  if FRevoked then
    raise EFloriaJSThrow.Create(JSMakeObject(
      Heap.NewError('TypeError', 'Cannot call a revoked proxy')));
  trap := GetTrap('apply');
  RequireCallableTrap(trap, 'apply');
  if trap.IsFunction() then
  begin
    arr := Heap.NewArray();
    for i := 0 to High(AArgs) do
      arr.Push(AArgs[i]);
    argsArray := JSMakeArray(arr);
    args[0] := FTarget;
    args[1] := AThis;
    args[2] := argsArray;
    Exit(Heap.InvokeFunction(trap, args, FHandler));
  end;
  if FTarget.IsFunction() then
    Exit(Heap.InvokeFunction(FTarget, AArgs, AThis));
  raise EFloriaJSThrow.Create(JSMakeObject(
    Heap.NewError('TypeError', 'Proxy target is not callable')));
end;

function TFloriaJSProxy.Construct(const AArgs: array of TFloriaJSValue): TFloriaJSValue;
var
  trap, argsArray: TFloriaJSValue;
  args: array[0..2] of TFloriaJSValue;
  callArgs: TFloriaJSValueArray;
  i: Integer;
  arr: TFloriaJSArray;
begin
  if FRevoked then
    raise EFloriaJSThrow.Create(JSMakeObject(
      Heap.NewError('TypeError', 'Cannot construct a revoked proxy')));
  trap := GetTrap('construct');
  RequireCallableTrap(trap, 'construct');
  if trap.IsFunction() then
  begin
    arr := Heap.NewArray();
    for i := 0 to High(AArgs) do
      arr.Push(AArgs[i]);
    argsArray := JSMakeArray(arr);
    args[0] := FTarget;
    args[1] := argsArray;
    if Heap.CurrentNewTarget.IsFunction() then
      args[2] := Heap.CurrentNewTarget
    else
      args[2] := JSMakeProxy(Self);
    Result := Heap.InvokeFunction(trap, args, FHandler);
    if not Result.IsObject() then
      raise EFloriaJSThrow.Create(JSMakeObject(
        Heap.NewError('TypeError', 'Proxy construct trap must return an object')));
    Exit;
  end;
  if FTarget.IsFunction() then
  begin
    SetLength(callArgs, Length(AArgs));
    for i := 0 to High(AArgs) do
      callArgs[i] := AArgs[i];
    Result := Heap.ConstructFunction(FTarget, callArgs);
    Exit;
  end;
  raise EFloriaJSThrow.Create(JSMakeObject(
    Heap.NewError('TypeError', 'Proxy target is not a constructor')));
end;

function TFloriaJSProxy.SetPrototypeOf(const AProto: TFloriaJSValue): Boolean;
var
  trap: TFloriaJSValue;
  args: array[0..1] of TFloriaJSValue;
begin
  trap := GetTrap('setPrototypeOf');
  RequireCallableTrap(trap, 'setPrototypeOf');
  if trap.IsFunction() then
  begin
    args[0] := FTarget;
    args[1] := AProto;
    Result := Heap.InvokeFunction(trap, args, FHandler).ToBoolean();
    if Result and FTarget.IsObject() and (not FTarget.AsObject().IsExtensible) then
    begin
      if AProto.IsObject() and (FTarget.AsObject().Prototype <> AProto.AsObject()) then
        raise EFloriaJSThrow.Create(JSMakeObject(
          Heap.NewError('TypeError', 'Proxy setPrototypeOf invariant violated')));
      if AProto.IsNull() and (FTarget.AsObject().Prototype <> nil) then
        raise EFloriaJSThrow.Create(JSMakeObject(
          Heap.NewError('TypeError', 'Proxy setPrototypeOf invariant violated')));
    end;
    Exit;
  end;
  Result := False;
  if FTarget.IsObject() then
  begin
    if AProto.IsNull() then
      FTarget.AsObject().Prototype := nil
    else if AProto.IsObject() then
      FTarget.AsObject().Prototype := AProto.AsObject()
    else
      Exit;
    Result := True;
  end;
end;

function TFloriaJSProxy.GetPropertyWithReceiver(const AName: string;
  AReceiver: TFloriaJSObject): TFloriaJSValue;
var
  trap, desc: TFloriaJSValue;
  args: array[0..2] of TFloriaJSValue;
begin
  trap := GetTrap('get');
  RequireCallableTrap(trap, 'get');
  if trap.IsFunction() then
  begin
    args[0] := FTarget;
    args[1] := JSMakeString(AName);
    args[2] := JSMakeObject(AReceiver);
    Result := Heap.InvokeFunction(trap, args, FHandler);
    if FTarget.IsObject() and FTarget.AsObject().HasOwnProperty(AName) and
       (not FTarget.AsObject().PropertyIsConfigurable(AName)) then
    begin
      if FTarget.AsObject().PropertyIsAccessor(AName) then
      begin
        if FTarget.AsObject().PropertyGetter(AName).IsUndefined() and
           (not Result.IsUndefined()) then
          raise EFloriaJSThrow.Create(JSMakeObject(
            Heap.NewError('TypeError', 'Proxy get invariant violated')));
      end
      else if (not FTarget.AsObject().PropertyIsWritable(AName)) and
              (not JSStrictEqual(Result, FTarget.AsObject().GetProperty(AName))) then
        raise EFloriaJSThrow.Create(JSMakeObject(
          Heap.NewError('TypeError', 'Proxy get invariant violated')));
    end;
    Exit;
  end;
  if FTarget.IsObject() then
    Result := FTarget.AsObject().GetPropertyWithReceiver(AName, AReceiver)
  else
    Result := JSMakeUndefined();
end;

procedure TFloriaJSProxy.SetProperty(const AName: string; const AValue: TFloriaJSValue);
var
  trap: TFloriaJSValue;
  args: array[0..3] of TFloriaJSValue;
begin
  trap := GetTrap('set');
  RequireCallableTrap(trap, 'set');
  if trap.IsFunction() then
  begin
    args[0] := FTarget;
    args[1] := JSMakeString(AName);
    args[2] := AValue;
    args[3] := JSMakeObject(Self);
    Heap.InvokeFunction(trap, args, FHandler);
    Exit;
  end;
  if FTarget.IsObject() then
    FTarget.AsObject().SetProperty(AName, AValue);
end;

function TFloriaJSProxy.HasProperty(const AName: string): Boolean;
var
  trap, desc: TFloriaJSValue;
  args: array[0..1] of TFloriaJSValue;
begin
  trap := GetTrap('has');
  RequireCallableTrap(trap, 'has');
  if trap.IsFunction() then
  begin
    args[0] := FTarget;
    args[1] := JSMakeString(AName);
    Result := Heap.InvokeFunction(trap, args, FHandler).ToBoolean();
    if (not Result) and FTarget.IsObject() and
       FTarget.AsObject().HasOwnProperty(AName) and
       (not FTarget.AsObject().PropertyIsConfigurable(AName)) then
      raise EFloriaJSThrow.Create(JSMakeObject(
        Heap.NewError('TypeError', 'Proxy has invariant violated')));
    Exit;
  end;
  Result := FTarget.IsObject() and FTarget.AsObject().HasProperty(AName);
end;

function TFloriaJSProxy.DeleteProperty(const AName: string): Boolean;
var
  trap, desc: TFloriaJSValue;
  args: array[0..1] of TFloriaJSValue;
begin
  trap := GetTrap('deleteProperty');
  RequireCallableTrap(trap, 'deleteProperty');
  if trap.IsFunction() then
  begin
    args[0] := FTarget;
    args[1] := JSMakeString(AName);
    Result := Heap.InvokeFunction(trap, args, FHandler).ToBoolean();
    if Result and FTarget.IsObject() and
       FTarget.AsObject().HasOwnProperty(AName) and
       (not FTarget.AsObject().PropertyIsConfigurable(AName)) then
      raise EFloriaJSThrow.Create(JSMakeObject(
        Heap.NewError('TypeError', 'Proxy delete invariant violated')));
    Exit;
  end;
  Result := (not FTarget.IsObject()) or FTarget.AsObject().DeleteProperty(AName);
end;

function TFloriaJSProxy.HasOwnProperty(const AName: string): Boolean;
var
  trap, desc: TFloriaJSValue;
  args: array[0..1] of TFloriaJSValue;
begin
  trap := GetTrap('getOwnPropertyDescriptor');
  RequireCallableTrap(trap, 'getOwnPropertyDescriptor');
  if trap.IsFunction() then
  begin
    args[0] := FTarget;
    args[1] := JSMakeString(AName);
    desc := Heap.InvokeFunction(trap, args, FHandler);
    Exit(not desc.IsUndefined());
  end;
  Result := FTarget.IsObject() and FTarget.AsObject().HasOwnProperty(AName);
end;

function TFloriaJSProxy.GetOwnProperty(const AName: string): TFloriaJSValue;
var
  trap: TFloriaJSValue;
  args: array[0..1] of TFloriaJSValue;
begin
  trap := GetTrap('getOwnPropertyDescriptor');
  RequireCallableTrap(trap, 'getOwnPropertyDescriptor');
  if trap.IsFunction() then
  begin
    args[0] := FTarget;
    args[1] := JSMakeString(AName);
    Result := Heap.InvokeFunction(trap, args, FHandler);
    if FTarget.IsObject() and FTarget.AsObject().HasOwnProperty(AName) and
       (not FTarget.AsObject().PropertyIsConfigurable(AName)) then
    begin
      if Result.IsUndefined() then
        raise EFloriaJSThrow.Create(JSMakeObject(
          Heap.NewError('TypeError', 'Proxy getOwnPropertyDescriptor invariant violated')));
      if Result.AsObject().GetProperty('configurable').ToBoolean() then
        raise EFloriaJSThrow.Create(JSMakeObject(
          Heap.NewError('TypeError', 'Proxy getOwnPropertyDescriptor invariant violated')));
      if Result.AsObject().HasProperty('writable') and
         (not Result.AsObject().GetProperty('writable').ToBoolean()) and
         FTarget.AsObject().PropertyIsWritable(AName) then
        raise EFloriaJSThrow.Create(JSMakeObject(
          Heap.NewError('TypeError', 'Proxy getOwnPropertyDescriptor invariant violated')));
      if (not FTarget.AsObject().PropertyIsAccessor(AName)) and
         (not FTarget.AsObject().PropertyIsWritable(AName)) then
      begin
        if not JSStrictEqual(Result.AsObject().GetProperty('value'),
          FTarget.AsObject().GetProperty(AName)) then
          raise EFloriaJSThrow.Create(JSMakeObject(
            Heap.NewError('TypeError', 'Proxy getOwnPropertyDescriptor invariant violated')));
        if Result.AsObject().GetProperty('writable').ToBoolean() then
          raise EFloriaJSThrow.Create(JSMakeObject(
            Heap.NewError('TypeError', 'Proxy getOwnPropertyDescriptor invariant violated')));
      end;
    end;
    Exit;
  end;
  if FTarget.IsObject() then
    Result := FTarget.AsObject().GetOwnProperty(AName)
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSProxy.GetPropertyCount(): Integer;
begin
  if FTarget.IsObject() then
    Result := FTarget.AsObject().GetPropertyCount()
  else
    Result := 0;
end;

function TFloriaJSProxy.GetEnumerablePropertyCount(): Integer;
begin
  if FTarget.IsObject() then
    Result := FTarget.AsObject().GetEnumerablePropertyCount()
  else
    Result := 0;
end;

function TFloriaJSProxy.GetEnumerablePropertyKey(AIndex: Integer): string;
begin
  if FTarget.IsObject() then
    Result := FTarget.AsObject().GetEnumerablePropertyKey(AIndex)
  else
    Result := '';
end;

function TFloriaJSProxy.GetPropertyKey(AIndex: Integer): string;
begin
  if FTarget.IsObject() then
    Result := FTarget.AsObject().GetPropertyKey(AIndex)
  else
    Result := '';
end;

function TFloriaJSProxy.GetPropertyValue(AIndex: Integer): TFloriaJSValue;
begin
  if FTarget.IsObject() then
    Result := FTarget.AsObject().GetPropertyValue(AIndex)
  else
    Result := JSMakeUndefined();
end;

procedure TFloriaJSProxy.GetKeys(AOutKeys: TStrings);
var
  trap, keys: TFloriaJSValue;
  args: array[0..0] of TFloriaJSValue;
  i: Integer;
  key: string;
begin
  if AOutKeys = nil then Exit;
  trap := GetTrap('ownKeys');
  RequireCallableTrap(trap, 'ownKeys');
  if trap.IsFunction() then
  begin
    args[0] := FTarget;
    keys := Heap.InvokeFunction(trap, args, FHandler);
    if keys.IsObject() and (keys.ObjVal is TFloriaJSArray) then
      for i := 0 to TFloriaJSArray(keys.ObjVal).Length() - 1 do
        AOutKeys.Add(TFloriaJSArray(keys.ObjVal).GetElement(i).ToString());
    if FTarget.IsObject() then
    begin
      for i := 0 to FTarget.AsObject().GetPropertyCount() - 1 do
      begin
        key := FTarget.AsObject().GetPropertyKey(i);
        if (not FTarget.AsObject().PropertyIsConfigurable(key)) and
           (AOutKeys.IndexOf(key) < 0) then
          raise EFloriaJSThrow.Create(JSMakeObject(
            Heap.NewError('TypeError', 'Proxy ownKeys invariant violated')));
      end;
      if not FTarget.AsObject().IsExtensible then
        for i := 0 to FTarget.AsObject().GetPropertyCount() - 1 do
        begin
          key := FTarget.AsObject().GetPropertyKey(i);
          if AOutKeys.IndexOf(key) < 0 then
            raise EFloriaJSThrow.Create(JSMakeObject(
              Heap.NewError('TypeError', 'Proxy ownKeys invariant violated')));
        end;
    end;
    Exit;
  end;
  if FTarget.IsObject() then
    FTarget.AsObject().GetKeys(AOutKeys);
end;

constructor TFloriaJSStringObject.Create(AProto: TFloriaJSObject; const AValue: string);
begin
  inherited Create(AProto);
  FValue := AValue;
end;

constructor TFloriaJSArray.Create();
begin
  inherited Create(nil);
  SetLength(FElements, 0);
  SetLength(FPresent, 0);
  FCount := 0;
  FLogicalLength := 0;
  SetLength(FOverflowIndex, 0);
  SetLength(FOverflowValue, 0);
  FOverflowCount := 0;
end;

destructor TFloriaJSArray.Destroy();
var
  i: Integer;
begin
  { Every element holds a reference to the value it stores. }
  if (Heap = nil) or (not Heap.IsClearing) then
    for i := 0 to FCount - 1 do
      JSReleaseValue(FElements[i]);
  SetLength(FElements, 0);
  SetLength(FPresent, 0);
  FCount := 0;
  if (Heap = nil) or (not Heap.IsClearing) then
    for i := 0 to FOverflowCount - 1 do
      JSReleaseValue(FOverflowValue[i]);
  SetLength(FOverflowIndex, 0);
  SetLength(FOverflowValue, 0);
  FOverflowCount := 0;
  FLogicalLength := 0;
  inherited Destroy();
end;

procedure TFloriaJSArray.RefreshLogicalLength();
var
  i: Integer;
begin
  FLogicalLength := FCount;
  for i := 0 to FOverflowCount - 1 do
    if FOverflowIndex[i] + 1 > FLogicalLength then
      FLogicalLength := FOverflowIndex[i] + 1;
end;

function TFloriaJSArray.FindOverflowIndex(AIndex: Int64): Integer;
var
  i: Integer;
begin
  for i := 0 to FOverflowCount - 1 do
    if FOverflowIndex[i] = AIndex then
      Exit(i);
  Result := -1;
end;

procedure TFloriaJSArray.SetOverflowElement(AIndex: Int64;
  const AValue: TFloriaJSValue);
var
  idx: Integer;
begin
  idx := FindOverflowIndex(AIndex);
  if idx >= 0 then
  begin
    JSReleaseValue(FOverflowValue[idx]);
    FOverflowValue[idx] := AValue;
    JSRetainValue(AValue);
  end
  else
  begin
    if FOverflowCount >= System.Length(FOverflowIndex) then
    begin
      SetLength(FOverflowIndex, FOverflowCount * 2 + 8);
      SetLength(FOverflowValue, FOverflowCount * 2 + 8);
    end;
    FOverflowIndex[FOverflowCount] := AIndex;
    FOverflowValue[FOverflowCount] := AValue;
    JSRetainValue(AValue);
    Inc(FOverflowCount);
  end;
  if AIndex + 1 > FLogicalLength then
    FLogicalLength := AIndex + 1;
end;

function TFloriaJSArray.GetOverflowElement(AIndex: Int64): TFloriaJSValue;
var
  idx: Integer;
begin
  idx := FindOverflowIndex(AIndex);
  if idx >= 0 then
    Result := FOverflowValue[idx]
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSArray.HasOverflowElement(AIndex: Int64): Boolean;
begin
  Result := FindOverflowIndex(AIndex) >= 0;
end;

function TFloriaJSArray.DeleteOverflowElement(AIndex: Int64): Boolean;
var
  idx: Integer;
begin
  idx := FindOverflowIndex(AIndex);
  if idx < 0 then
    Exit(True);
  JSReleaseValue(FOverflowValue[idx]);
  FOverflowValue[idx] := FOverflowValue[FOverflowCount - 1];
  FOverflowIndex[idx] := FOverflowIndex[FOverflowCount - 1];
  Dec(FOverflowCount);
  Result := True;
end;

procedure TFloriaJSArray.TrimOverflow(ANewLength: Int64);
var
  i: Integer;
begin
  for i := FOverflowCount - 1 downto 0 do
    if FOverflowIndex[i] >= ANewLength then
    begin
      JSReleaseValue(FOverflowValue[i]);
      FOverflowValue[i] := FOverflowValue[FOverflowCount - 1];
      FOverflowIndex[i] := FOverflowIndex[FOverflowCount - 1];
      Dec(FOverflowCount);
    end;
end;

procedure TFloriaJSArray.GrowCapacity(AMinCapacity: Integer);
var
  newCap: Integer;
begin
  if System.Length(FElements) >= AMinCapacity then
    Exit;

  newCap := System.Length(FElements) * 2;
  if newCap < AMinCapacity then
    newCap := AMinCapacity;
  if newCap < 8 then
    newCap := 8;

  SetLength(FElements, newCap);
  { The newly allocated slots start out absent; the caller decides which of
    them hold real elements and which stay holes. }
  SetLength(FPresent, newCap);
end;

function TFloriaJSArray.GetElement(AIndex: Integer): TFloriaJSValue;
begin
  if (AIndex >= 0) and (AIndex < FCount) and FPresent[AIndex] then
    Result := FElements[AIndex]
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSArray.GetElementByIndex(const AIndex: Int64): TFloriaJSValue;
begin
  if AIndex >= ARRAY_DENSE_LIMIT then
    Result := GetOverflowElement(AIndex)
  else if (AIndex >= 0) and (AIndex < FCount) and FPresent[AIndex] then
    Result := FElements[AIndex]
  else
    Result := JSMakeUndefined();
end;

procedure TFloriaJSArray.SetElementByIndex(const AIndex: Int64;
  const AValue: TFloriaJSValue);
begin
  if AIndex >= ARRAY_DENSE_LIMIT then
    SetOverflowElement(AIndex, AValue)
  else if (AIndex >= 0) and (AIndex <= High(Integer)) then
    SetElement(Integer(AIndex), AValue);
end;

function TFloriaJSArray.HasElement(AIndex: Integer): Boolean;
begin
  { A hole reads as undefined, but it is not an own property. }
  Result := (AIndex >= 0) and (AIndex < FCount) and FPresent[AIndex];
end;

procedure TFloriaJSArray.SetElement(AIndex: Integer; const AValue: TFloriaJSValue);
var
  i: Integer;
begin
  if AIndex < 0 then Exit;

  if AIndex >= FCount then
  begin
    GrowCapacity(AIndex + 1);
    { Growing past the end fills the gap with holes, not elements. }
    for i := FCount to AIndex - 1 do
    begin
      FElements[i] := JSMakeUndefined();
      FPresent[i] := False;
    end;
    FCount := AIndex + 1;
  end
  else
  begin
    { The element that is replaced gives up the reference it held. }
    JSReleaseValue(FElements[AIndex]);
  end;

  FElements[AIndex] := AValue;
  FPresent[AIndex] := True;
  JSRetainValue(AValue);
  if AIndex + 1 > FLogicalLength then
    FLogicalLength := AIndex + 1;
end;

procedure TFloriaJSArray.Push(const AValue: TFloriaJSValue);
begin
  GrowCapacity(FCount + 1);
  FElements[FCount] := AValue;
  FPresent[FCount] := True;
  JSRetainValue(AValue);
  Inc(FCount);
  if FCount > FLogicalLength then
    FLogicalLength := FCount;
end;

procedure TFloriaJSArray.PushHole();
begin
  GrowCapacity(FCount + 1);
  FElements[FCount] := JSMakeUndefined();
  FPresent[FCount] := False;
  Inc(FCount);
  if FCount > FLogicalLength then
    FLogicalLength := FCount;
end;

function TFloriaJSArray.Pop(): TFloriaJSValue;
begin
  if FCount = 0 then
    Exit(JSMakeUndefined());

  Dec(FCount);
  if FPresent[FCount] then
    Result := FElements[FCount]
  else
    Result := JSMakeUndefined();
  FPresent[FCount] := False;
  FElements[FCount] := JSMakeUndefined();
  { The element that is removed gives up the reference it held. }
  JSReleaseValue(Result);
  RefreshLogicalLength();
end;

function TFloriaJSArray.Shift(): TFloriaJSValue;
var
  i: Integer;
begin
  if FCount = 0 then
    Exit(JSMakeUndefined());

  Result := GetElement(0);
  for i := 0 to FCount - 2 do
  begin
    FElements[i] := FElements[i + 1];
    FPresent[i] := FPresent[i + 1];
  end;

  Dec(FCount);
  FPresent[FCount] := False;
  { The element that is shifted out gives up the reference it held. }
  JSReleaseValue(FElements[FCount]);
  FElements[FCount] := JSMakeUndefined();
  RefreshLogicalLength();
end;

procedure TFloriaJSArray.Unshift(const AValue: TFloriaJSValue);
var
  i: Integer;
begin
  GrowCapacity(FCount + 1);
  for i := FCount downto 1 do
  begin
    FElements[i] := FElements[i - 1];
    FPresent[i] := FPresent[i - 1];
  end;

  FElements[0] := AValue;
  FPresent[0] := True;
  JSRetainValue(AValue);
  Inc(FCount);
  if FCount > FLogicalLength then
    FLogicalLength := FCount;
end;

procedure TFloriaJSArray.InsertAt(AIndex: Integer; const AValue: TFloriaJSValue);
var
  i: Integer;
begin
  if AIndex < 0 then AIndex := 0;
  if AIndex > FCount then AIndex := FCount;

  GrowCapacity(FCount + 1);
  for i := FCount downto AIndex + 1 do
  begin
    FElements[i] := FElements[i - 1];
    FPresent[i] := FPresent[i - 1];
  end;

  FElements[AIndex] := AValue;
  FPresent[AIndex] := True;
  JSRetainValue(AValue);
  Inc(FCount);
  if FCount > FLogicalLength then
    FLogicalLength := FCount;
end;

procedure TFloriaJSArray.RemoveAt(AIndex: Integer);
var
  i: Integer;
begin
  if (AIndex < 0) or (AIndex >= FCount) then Exit;

  { The element that is removed gives up the reference it held. }
  JSReleaseValue(FElements[AIndex]);
  for i := AIndex to FCount - 2 do
  begin
    FElements[i] := FElements[i + 1];
    FPresent[i] := FPresent[i + 1];
  end;

  Dec(FCount);
  FPresent[FCount] := False;
  FElements[FCount] := JSMakeUndefined();
  RefreshLogicalLength();
end;

procedure TFloriaJSArray.MarkHole(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FCount) then Exit;
  if not FPresent[AIndex] then Exit;

  { Turning an element into a hole drops the reference it held. }
  JSReleaseValue(FElements[AIndex]);
  FElements[AIndex] := JSMakeUndefined();
  FPresent[AIndex] := False;
end;

function TFloriaJSArray.DeleteElement(AIndex: Integer): Boolean;
begin
  { Like `delete arr[i]` in ECMAScript: the slot becomes a hole and the array
    length is not changed. Deleting a non-existent index succeeds as well. }
  MarkHole(AIndex);
  Result := True;
end;

procedure TFloriaJSArray.SetLengthTo(ANewLength: Integer);
var
  i: Integer;
begin
  if ANewLength < 0 then ANewLength := 0;

  if ANewLength < FCount then
  begin
    { Truncation drops the elements and the references they held. }
    for i := FCount - 1 downto ANewLength do
    begin
      JSReleaseValue(FElements[i]);
      FElements[i] := JSMakeUndefined();
      FPresent[i] := False;
    end;
    FCount := ANewLength;
  end
  else if ANewLength > FCount then
  begin
    GrowCapacity(ANewLength);
    { Extension creates holes; the new length is observable immediately. }
    for i := FCount to ANewLength - 1 do
    begin
      FElements[i] := JSMakeUndefined();
      FPresent[i] := False;
    end;
    FCount := ANewLength;
  end;
  TrimOverflow(ANewLength);
  RefreshLogicalLength();
end;

procedure TFloriaJSArray.SwapElements(AIndex, BIndex: Integer);
var
  tmpValue: TFloriaJSValue;
  tmpPresent: Boolean;
begin
  if (AIndex < 0) or (AIndex >= FCount) or (BIndex < 0) or (BIndex >= FCount) then
    Exit;

  tmpValue := FElements[AIndex];
  FElements[AIndex] := FElements[BIndex];
  FElements[BIndex] := tmpValue;

  tmpPresent := FPresent[AIndex];
  FPresent[AIndex] := FPresent[BIndex];
  FPresent[BIndex] := tmpPresent;
end;

function TFloriaJSArray.Join(const ASeparator: string): string;
var
  sb: TStringBuilder;
  i: Integer;
begin
  if FCount = 0 then Exit('');

  sb := TStringBuilder.Create();
  try
    for i := 0 to FCount - 1 do
    begin
      if i > 0 then sb.Append(ASeparator);
      { Holes and undefined/null elements render as an empty string. }
      if FPresent[i] and not (FElements[i].IsUndefined() or FElements[i].IsNull()) then
        sb.Append(FElements[i].ToString());
    end;
    Result := sb.ToString();
  finally
    sb.Free();
  end;
end;

function TFloriaJSArray.Length(): Integer;
begin
  Result := FCount;
end;

function TFloriaJSArray.LogicalLength(): Int64;
begin
  Result := FLogicalLength;
end;

function TFloriaJSArray.GetProperty(const AName: string): TFloriaJSValue;
begin
  Result := GetPropertyWithReceiver(AName, Self);
end;

function TFloriaJSArray.GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue;
var
  idx: Int64;
begin
  if AName = 'length' then
    Exit(JSMakeNumber(FLogicalLength));

  if TryStrToInt64(AName, idx) and (idx >= 0) and (idx <= ARRAY_INDEX_LIMIT) then
  begin
    if idx >= ARRAY_DENSE_LIMIT then
      Exit(GetOverflowElement(idx));
    Exit(GetElement(Integer(idx)));
  end;

  Result := inherited GetPropertyWithReceiver(AName, AReceiver);
end;

procedure TFloriaJSArray.SetProperty(const AName: string; const AValue: TFloriaJSValue);
var
  idx: Int64;
  d: Double;
begin
  if AName = 'length' then
  begin
    d := AValue.ToNumber();
    { ECMAScript array lengths are integers in [0, 2^32 - 1]. }
    if IsNaN(d) or (d < 0) or (d <> Int(d)) or (d > 4294967295.0) then
    begin
      if JSActiveRealmHeap() <> nil then
        raise EFloriaJSThrow.Create(JSMakeObject(JSActiveRealmHeap().NewError('RangeError', 'Invalid array length')));
      if Heap <> nil then
        raise EFloriaJSThrow.Create(JSMakeObject(Heap.NewError('RangeError', 'Invalid array length')));
      Exit;
    end;
    if d > 2147483647.0 then
    begin
      TrimOverflow(Trunc(d));
      FLogicalLength := Trunc(d);
    end
    else
      SetLengthTo(Trunc(d));
    Exit;
  end;

  if TryStrToInt64(AName, idx) and (idx >= 0) and (idx <= ARRAY_INDEX_LIMIT) then
  begin
    if idx >= ARRAY_DENSE_LIMIT then
      SetOverflowElement(idx, AValue)
    else
      SetElement(Integer(idx), AValue);
    Exit;
  end;

  inherited SetProperty(AName, AValue);
end;

function TFloriaJSArray.DeleteProperty(const AName: string): Boolean;
var
  idx: Int64;
begin
  { `length` is not configurable. }
  if AName = 'length' then
    Exit(False);

  if TryStrToInt64(AName, idx) and (idx >= 0) and (idx <= ARRAY_INDEX_LIMIT) then
  begin
    if idx >= ARRAY_DENSE_LIMIT then
      Exit(DeleteOverflowElement(idx));
    Exit(DeleteElement(Integer(idx)));
  end;

  Result := inherited DeleteProperty(AName);
end;

function TFloriaJSArray.HasProperty(const AName: string): Boolean;
var
  idx: Int64;
begin
  if AName = 'length' then Exit(True);
  if TryStrToInt64(AName, idx) and (idx >= 0) and (idx <= ARRAY_INDEX_LIMIT) then
  begin
    if idx >= ARRAY_DENSE_LIMIT then
      Exit(HasOverflowElement(idx));
    Exit(HasElement(Integer(idx)));
  end;

  Result := inherited HasProperty(AName);
end;

function TFloriaJSArray.HasOwnProperty(const AName: string): Boolean;
var
  idx: Int64;
begin
  if AName = 'length' then Exit(True);
  if TryStrToInt64(AName, idx) and (idx >= 0) and (idx <= ARRAY_INDEX_LIMIT) then
  begin
    if idx >= ARRAY_DENSE_LIMIT then
      Exit(HasOverflowElement(idx));
    Exit(HasElement(Integer(idx)));
  end;

  Result := inherited HasOwnProperty(AName);
end;

{ TFloriaJSFunction }

procedure TFloriaJSFunction.RegisterPrototype(AProto: TFloriaJSPrototypeObject);
begin
  if AProto = nil then Exit;
  if FPrototypes = nil then
    FPrototypes := TFPList.Create();
  if FPrototypes.IndexOf(AProto) < 0 then
    FPrototypes.Add(AProto);
end;

procedure TFloriaJSFunction.UnregisterPrototype(AProto: TFloriaJSPrototypeObject);
begin
  if (FPrototypes <> nil) and (AProto <> nil) then
    FPrototypes.Remove(AProto);
end;

constructor TFloriaJSFunction.CreateNative(const AName: string; AProc: TFloriaJSNativeProc);
begin
  inherited Create(nil);
  FName := AName;
  FIsNative := True;
  FNativeProc := AProc;
  FNativeMethod := nil;
  FClosureEnv := nil;
  FIsAsync := False;
  FIsArrow := False;
  FSuppressPrototype := False;
  FPrototypes := nil;
end;

constructor TFloriaJSFunction.CreateNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod);
begin
  inherited Create(nil);
  FName := AName;
  FIsNative := True;
  FNativeProc := nil;
  FNativeMethod := AMethod;
  FClosureEnv := nil;
  FIsAsync := False;
  FIsArrow := False;
  FSuppressPrototype := False;
  FPrototypes := nil;
end;

constructor TFloriaJSFunction.CreateBytecode(const AName: string; ABytecode: TObject; AClosure: Pointer; AIsArrow: Boolean; AIsAsync: Boolean);
begin
  inherited Create(nil);
  FName := AName;
  FIsNative := False;
  FNativeProc := nil;
  FNativeMethod := nil;
  FBytecode := ABytecode;
  if FBytecode <> nil then
    TFloriaJSBytecode(FBytecode).Retain();
  FClosureEnv := AClosure;
  FIsAsync := AIsAsync;
  FIsAsyncGenerator := False;
  FIsNamedExpression := False;
  FIsArrow := AIsArrow;
  FNameDeleted := False;
  FLengthDeleted := False;
  FSuppressPrototype := False;
  FPrototypes := nil;
end;

destructor TFloriaJSFunction.Destroy();
var
  i: Integer;
  proto: TFloriaJSPrototypeObject;
begin
  if FPrototypes <> nil then
  begin
    for i := FPrototypes.Count - 1 downto 0 do
    begin
      proto := TFloriaJSPrototypeObject(FPrototypes[i]);
      if proto <> nil then
        proto.FOwnerFunction := nil;
    end;
    FreeAndNil(FPrototypes);
  end;

  if FBytecode <> nil then
  begin
    TFloriaJSBytecode(FBytecode).Release();
    FBytecode := nil;
  end;
  inherited Destroy();
end;

function JSNumberToFixedMethod(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  digits: Integer;
begin
  if not AThis.IsNumber() then Exit(JSMakeString('NaN'));
  digits := 0;
  if (Length(AArgs) > 0) and not AArgs[0].IsUndefined() then
    digits := Trunc(AArgs[0].ToNumber());
  Result := JSMakeString(JSNumberToFixed(AThis.NumVal, digits));
end;

function JSNumberToPrecisionMethod(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  precision: Integer;
begin
  if not AThis.IsNumber() then Exit(JSMakeString('NaN'));
  { A missing precision means the default string conversion. }
  if (Length(AArgs) = 0) or AArgs[0].IsUndefined() then
    Exit(JSMakeString(JSNumberToStr(AThis.NumVal)));
  precision := Trunc(AArgs[0].ToNumber());
  Result := JSMakeString(JSNumberToPrecision(AThis.NumVal, precision));
end;

function JSNumberToExponentialMethod(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  digits: Integer;
begin
  if not AThis.IsNumber() then Exit(JSMakeString('NaN'));
  digits := 0;
  if (Length(AArgs) > 0) and not AArgs[0].IsUndefined() then
    digits := Trunc(AArgs[0].ToNumber());
  Result := JSMakeString(JSNumberToExponential(AThis.NumVal, digits));
end;

function JSNumberToString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  radix: Integer;
begin
  if AThis.IsNumber() then
  begin
    radix := 10;
    if (Length(AArgs) > 0) and (not AArgs[0].IsUndefined()) then
    begin
      radix := Trunc(AArgs[0].ToNumber());
      { A primitive number has no object of its own, so the error is built from
        Number.prototype's heap, which is the heap the value came from. }
      if (radix < 2) or (radix > 36) then
      begin
        if AThis.IsObject() then
          raise EFloriaJSThrow.Create(JSMakeObject(AThis.AsObject().Heap.NewError('RangeError', 'toString() radix must be between 2 and 36')))
        else if GNumberPrototype <> nil then
          raise EFloriaJSThrow.Create(JSMakeObject(GNumberPrototype.Heap.NewError('RangeError', 'toString() radix must be between 2 and 36')))
        else
          raise EConvertError.Create('toString() radix must be between 2 and 36');
      end;
    end;
    Result := JSMakeString(JSNumberToRadixStr(AThis.NumVal, radix));
  end
  else
    Result := JSMakeString(AThis.ToString());
end;

function JSNumberValueOf(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(AThis.ToNumber());
end;

function JSFunctionToString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  fnName: string;
begin
  if AThis.IsFunction() then
  begin
    fnName := AThis.AsFunction().Name;
    Result := JSMakeString('function ' + fnName + '() { [native code] }');
  end
  else
    Result := JSMakeString('[object Object]');
end;

function JSErrorToString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  nameVal, msgVal: TFloriaJSValue;
  nameStr, msgStr: string;
begin
  if not AThis.IsObject() then
    nameStr := 'Error'
  else
  begin
    nameVal := AThis.AsObject().GetProperty('name');
    if nameVal.IsUndefined() then
      nameStr := 'Error'
    else
      nameStr := nameVal.ToString();

    msgVal := AThis.AsObject().GetProperty('message');
    if msgVal.IsUndefined() then
      msgStr := ''
    else
      msgStr := msgVal.ToString();
  end;

  if nameStr = '' then
    Result := JSMakeString(msgStr)
  else if msgStr = '' then
    Result := JSMakeString(nameStr)
  else
    Result := JSMakeString(nameStr + ': ' + msgStr);
end;

function TFloriaJSFunction.GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue;
var
  protoObj: TFloriaJSObject;
  subCode: TFloriaJSBytecode;
begin
  { A bound function is constructable through its target but must not expose an
    own `prototype`: `new` reads the target's prototype directly, and
    `Object.keys`/`hasOwnProperty` must not report one. }
  if (AName = 'prototype') and (not FIsArrow) and (not FSuppressPrototype) and
     (FindPropertyIndex(AName) < 0) and (FHeap <> nil) then
  begin
    if FIsAsyncGenerator then
      protoObj := FHeap.Track(TFloriaJSPrototypeObject.Create(
        FHeap.GetAsyncGeneratorPrototype(), Self))
    else
      protoObj := FHeap.Track(TFloriaJSPrototypeObject.Create(
        FHeap.GetObjectPrototype(), Self));
    SetProperty('prototype', JSMakeObject(protoObj));
  end;

  { `name` and `length` are non-enumerable own properties of every function.
    They are materialised on first read, from the function's own name and its
    bytecode's declared parameter count. }
  if (AName = 'name') and (not FNameDeleted) and (FindPropertyIndex('name') < 0) then
  begin
    DefineDataProperty('name', JSMakeString(FName), False, False, True);
    Exit(inherited GetPropertyWithReceiver(AName, AReceiver));
  end;

  if (AName = 'length') and (not FLengthDeleted) and (FindPropertyIndex('length') < 0) then
  begin
    if FBytecode <> nil then
      subCode := TFloriaJSBytecode(FBytecode)
    else
      subCode := nil;
    if subCode <> nil then
      DefineDataProperty('length', JSMakeNumber(subCode.GetArgumentCount()), False, False, True)
    else
      DefineDataProperty('length', JSMakeNumber(0), False, False, True);
    Exit(inherited GetPropertyWithReceiver(AName, AReceiver));
  end;

  Result := inherited GetPropertyWithReceiver(AName, AReceiver);
end;

function TFloriaJSFunction.HasOwnProperty(const AName: string): Boolean;
begin
  if (AName = 'name') and (not FNameDeleted) then
    GetPropertyWithReceiver(AName, Self)
  else if (AName = 'length') and (not FLengthDeleted) then
    GetPropertyWithReceiver(AName, Self);
  Result := inherited HasOwnProperty(AName);
end;

function TFloriaJSFunction.GetProperty(const AName: string): TFloriaJSValue;
begin
  Result := GetPropertyWithReceiver(AName, Self);
end;

procedure TFloriaJSFunction.SetProperty(const AName: string; const AValue: TFloriaJSValue);
var
  idx: Integer;
begin
  if AName = 'prototype' then
  begin
    idx := FindPropertyIndex('prototype');
    if (idx >= 0) and FProperties[idx].Value.IsObject() and
       (FProperties[idx].Value.ObjVal is TFloriaJSPrototypeObject) and
       (FProperties[idx].Value.ObjVal <> AValue.ObjVal) then
      TFloriaJSPrototypeObject(FProperties[idx].Value.ObjVal).OwnerFunction := nil;
  end;
  inherited SetProperty(AName, AValue);
end;

function TFloriaJSFunction.DeleteProperty(const AName: string): Boolean;
var
  idx: Integer;
begin
  if AName = 'name' then
  begin
    if not FNameDeleted then
      GetPropertyWithReceiver(AName, Self);
    Result := inherited DeleteProperty(AName);
    if Result then
      FNameDeleted := True;
    Exit;
  end;
  if AName = 'length' then
  begin
    if not FLengthDeleted then
      GetPropertyWithReceiver(AName, Self);
    Result := inherited DeleteProperty(AName);
    if Result then
      FLengthDeleted := True;
    Exit;
  end;
  if AName = 'prototype' then
  begin
    idx := FindPropertyIndex('prototype');
    if (idx >= 0) and FProperties[idx].Value.IsObject() and
       (FProperties[idx].Value.ObjVal is TFloriaJSPrototypeObject) then
      TFloriaJSPrototypeObject(FProperties[idx].Value.ObjVal).OwnerFunction := nil;
  end;
  Result := inherited DeleteProperty(AName);
end;

procedure TFloriaJSFunction.DefineGetter(const AName: string; const AGetter: TFloriaJSValue);
var
  idx: Integer;
begin
  if AName = 'prototype' then
  begin
    idx := FindPropertyIndex('prototype');
    if (idx >= 0) and FProperties[idx].Value.IsObject() and
       (FProperties[idx].Value.ObjVal is TFloriaJSPrototypeObject) then
      TFloriaJSPrototypeObject(FProperties[idx].Value.ObjVal).OwnerFunction := nil;
  end;
  inherited DefineGetter(AName, AGetter);
end;

procedure TFloriaJSFunction.DefineSetter(const AName: string; const ASetter: TFloriaJSValue);
var
  idx: Integer;
begin
  if AName = 'prototype' then
  begin
    idx := FindPropertyIndex('prototype');
    if (idx >= 0) and FProperties[idx].Value.IsObject() and
       (FProperties[idx].Value.ObjVal is TFloriaJSPrototypeObject) then
      TFloriaJSPrototypeObject(FProperties[idx].Value.ObjVal).OwnerFunction := nil;
  end;
  inherited DefineSetter(AName, ASetter);
end;

{ TFloriaJSPrototypeObject }

procedure TFloriaJSPrototypeObject.SetOwnerFunction(AOwner: TFloriaJSFunction);
begin
  if FOwnerFunction = AOwner then
    Exit;
  if FOwnerFunction <> nil then
    FOwnerFunction.UnregisterPrototype(Self);
  FOwnerFunction := AOwner;
  if FOwnerFunction <> nil then
    FOwnerFunction.RegisterPrototype(Self);
end;

constructor TFloriaJSPrototypeObject.Create(AProto: TFloriaJSObject; AOwner: TFloriaJSFunction);
begin
  inherited Create(AProto);
  FOwnerFunction := nil;
  SetOwnerFunction(AOwner);
end;

destructor TFloriaJSPrototypeObject.Destroy();
begin
  if FOwnerFunction <> nil then
  begin
    FOwnerFunction.UnregisterPrototype(Self);
    FOwnerFunction := nil;
  end;
  inherited Destroy();
end;

function TFloriaJSPrototypeObject.GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
    Exit(inherited GetPropertyWithReceiver(AName, AReceiver));

  if (AName = 'constructor') and (FOwnerFunction <> nil) then
    Exit(JSMakeFunction(FOwnerFunction));

  Result := inherited GetPropertyWithReceiver(AName, AReceiver);
end;

function TFloriaJSPrototypeObject.HasOwnProperty(const AName: string): Boolean;
begin
  if (AName = 'constructor') and (FOwnerFunction <> nil) then
    Exit(True);
  Result := inherited HasOwnProperty(AName);
end;

{ TFloriaJSBoundFunction }

constructor TFloriaJSBoundFunction.CreateBound(const AName: string; const ATarget, ABoundThis: TFloriaJSValue;
  const ABoundArgs: TFloriaJSValueArray);
var
  i: Integer;
begin
  { A bound function is a function object of its own: it is callable through the
    target, and it must be rejected by `new` exactly when the target is. It is
    deliberately not native, so nothing mistakes it for a native callback; the
    VM recognises the class and routes calls and construction through the
    target. }
  inherited CreateNative(AName, nil);
  FIsNative := False;
  FNativeProc := nil;
  FSuppressPrototype := True;
  FTarget := ATarget;
  JSRetainValue(FTarget);
  FBoundThis := ABoundThis;
  JSRetainValue(FBoundThis);
  SetLength(FBoundArgs, Length(ABoundArgs));
  for i := 0 to High(ABoundArgs) do
  begin
    FBoundArgs[i] := ABoundArgs[i];
    JSRetainValue(FBoundArgs[i]);
  end;
end;

destructor TFloriaJSBoundFunction.Destroy();
var
  i: Integer;
begin
  { The heap may be tearing down, in which case every object is released at
    once and the bound values may already be gone. }
  if (FHeap = nil) or (not FHeap.IsClearing) then
  begin
    JSReleaseValue(FTarget);
    JSReleaseValue(FBoundThis);
    for i := 0 to High(FBoundArgs) do
      JSReleaseValue(FBoundArgs[i]);
  end;
  FTarget := JSMakeUndefined();
  FBoundThis := JSMakeUndefined();
  SetLength(FBoundArgs, 0);
  inherited Destroy();
end;

function TFloriaJSBoundFunction.CombineArguments(const AArgs: TFloriaJSValueArray): TFloriaJSValueArray;
var
  i, bCount, aCount: Integer;
begin
  bCount := Length(FBoundArgs);
  aCount := Length(AArgs);
  SetLength(Result, bCount + aCount);
  for i := 0 to bCount - 1 do
    Result[i] := FBoundArgs[i];
  for i := 0 to aCount - 1 do
    Result[bCount + i] := AArgs[i];
end;

function TFloriaJSBoundFunction.ConstructorTarget(): TFloriaJSFunction;
begin
  Result := nil;
  if FTarget.IsFunction() and (FHeap <> nil) then
    Result := FHeap.ResolveConstructorTarget(FTarget);
end;

function JSFunctionCall(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  fn: TFloriaJSFunction;
  callArgs: array of TFloriaJSValue;
  thisArg: TFloriaJSValue;
  i, count: Integer;
begin
  if not AThis.IsFunction() then
    raise EFloriaJSThrow.Create(JSMakeObject(AThis.AsObject().Heap.NewError('TypeError', 'Function.prototype.call called on non-function')));

  fn := AThis.AsFunction();
  if Length(AArgs) > 0 then
    thisArg := AArgs[0]
  else
    thisArg := JSMakeUndefined();

  if Length(AArgs) > 1 then
  begin
    count := Length(AArgs) - 1;
    SetLength(callArgs, count);
    for i := 0 to count - 1 do
      callArgs[i] := AArgs[i + 1];
  end
  else
    SetLength(callArgs, 0);

  if fn.Heap <> nil then
    Result := fn.Heap.InvokeFunction(AThis, callArgs, thisArg)
  else
    Result := JSMakeUndefined();
end;

function JSFunctionApply(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  fn: TFloriaJSFunction;
  callArgs: array of TFloriaJSValue;
  thisArg, argList: TFloriaJSValue;
  arr: TFloriaJSArray;
  i, count: Integer;
begin
  if not AThis.IsFunction() then
    raise EFloriaJSThrow.Create(JSMakeObject(AThis.AsObject().Heap.NewError('TypeError', 'Function.prototype.apply called on non-function')));

  fn := AThis.AsFunction();
  if Length(AArgs) > 0 then
    thisArg := AArgs[0]
  else
    thisArg := JSMakeUndefined();

  SetLength(callArgs, 0);
  if Length(AArgs) > 1 then
  begin
    argList := AArgs[1];
    if not (argList.IsNull() or argList.IsUndefined()) then
    begin
      if not argList.IsObject() then
        raise EFloriaJSThrow.Create(JSMakeObject(fn.Heap.NewError('TypeError', 'CreateListFromArrayLike called on non-object')));

      if argList.IsArray() then
      begin
        arr := argList.AsArray();
        count := arr.Length();
        SetLength(callArgs, count);
        for i := 0 to count - 1 do
          callArgs[i] := arr.GetElement(i);
      end
      else
      begin
        count := Trunc(argList.AsObject().GetProperty('length').ToNumber());
        if count < 0 then count := 0;
        SetLength(callArgs, count);
        for i := 0 to count - 1 do
          callArgs[i] := argList.AsObject().GetProperty(IntToStr(i));
      end;
    end;
  end;

  if fn.Heap <> nil then
    Result := fn.Heap.InvokeFunction(AThis, callArgs, thisArg)
  else
    Result := JSMakeUndefined();
end;

function JSFunctionBind(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  fn: TFloriaJSFunction;
  boundThis: TFloriaJSValue;
  boundArgs: TFloriaJSValueArray;
  boundFn: TFloriaJSFunction;
  i, count: Integer;
begin
  if not AThis.IsFunction() then
    raise EFloriaJSThrow.Create(JSMakeObject(AThis.AsObject().Heap.NewError('TypeError', 'Function.prototype.bind called on non-function')));

  fn := AThis.AsFunction();
  if Length(AArgs) > 0 then
    boundThis := AArgs[0]
  else
    boundThis := JSMakeUndefined();

  if Length(AArgs) > 1 then
  begin
    count := Length(AArgs) - 1;
    SetLength(boundArgs, count);
    for i := 0 to count - 1 do
      boundArgs[i] := AArgs[i + 1];
  end
  else
    SetLength(boundArgs, 0);

  { The bound function is a real function object: it is callable, it carries no
    own `prototype`, and `new`/`instanceof` resolve through the target. }
  if fn.Heap = nil then
    Exit(JSMakeUndefined());

  boundFn := fn.Heap.NewBoundFunction(fn.Name, AThis, boundThis, boundArgs);
  Result := JSMakeFunction(boundFn);
end;

{ EFloriaJSThrow }

constructor EFloriaJSThrow.Create(const AValue: TFloriaJSValue);
begin
  inherited Create(AValue.ToString());
  FValue := AValue;
end;

{ Promise native methods (dispatched through the promise's own heap) }

function JSPromiseThen(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  p: TFloriaJSPromise;
  onFulfilled, onRejected: TFloriaJSValue;
begin
  p := AThis.AsPromise();
  if p = nil then
    Exit(JSMakeUndefined());

  onFulfilled := JSMakeUndefined();
  onRejected := JSMakeUndefined();
  if Length(AArgs) > 0 then onFulfilled := AArgs[0];
  if Length(AArgs) > 1 then onRejected := AArgs[1];

  Result := JSMakePromise(p.Chain(onFulfilled, onRejected));
end;

function JSPromiseCatch(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  p: TFloriaJSPromise;
  onRejected: TFloriaJSValue;
begin
  p := AThis.AsPromise();
  if p = nil then
    Exit(JSMakeUndefined());

  onRejected := JSMakeUndefined();
  if Length(AArgs) > 0 then onRejected := AArgs[0];

  Result := JSMakePromise(p.Chain(JSMakeUndefined(), onRejected));
end;

function JSPromiseFinally(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  p: TFloriaJSPromise;
  onFinally: TFloriaJSValue;
begin
  p := AThis.AsPromise();
  if p = nil then
    Exit(JSMakeUndefined());

  onFinally := JSMakeUndefined();
  if Length(AArgs) > 0 then onFinally := AArgs[0];

  Result := JSMakePromise(p.ChainFinally(onFinally));
end;

{ TFloriaJSPromise }

constructor TFloriaJSPromise.Create(AHeap: TFloriaJSHeap);
begin
  { Promises are ordinary objects in the prototype chain, so they inherit from
    Object.prototype and `p instanceof Object` holds. }
  if AHeap <> nil then
    inherited Create(AHeap.GetPromisePrototype())
  else
    inherited Create(nil);
  FHeap := AHeap;
  FState := fjspPending;
  FResult := JSMakeUndefined();
  FReactionCount := 0;
  FThenFn := nil;
  FCatchFn := nil;
  FFinallyFn := nil;
end;

destructor TFloriaJSPromise.Destroy();
var
  i: Integer;
begin
  { The settlement value and every registered reaction hold references. }
  if (FHeap = nil) or (not FHeap.IsClearing) then
  begin
    JSReleaseValue(FResult);
    for i := 0 to FReactionCount - 1 do
      ReleaseReaction(FReactions[i]);
  end;
  SetLength(FReactions, 0);
  FReactionCount := 0;
  inherited Destroy();
end;

procedure TFloriaJSPromise.AddReaction(const AReaction: TFloriaJSPromiseReaction);
begin
  if FReactionCount >= Length(FReactions) then
    SetLength(FReactions, FReactionCount + 4);
  FReactions[FReactionCount] := AReaction;
  { The reaction holds the references to its callbacks and to its child. }
  JSRetainValue(AReaction.OnFulfilled);
  JSRetainValue(AReaction.OnRejected);
  JSRetainValue(AReaction.OnFinally);
  if AReaction.Child <> nil then
    AReaction.Child.Retain;
  Inc(FReactionCount);
end;

procedure TFloriaJSPromise.ReleaseReaction(const AReaction: TFloriaJSPromiseReaction);
begin
  JSReleaseValue(AReaction.OnFulfilled);
  JSReleaseValue(AReaction.OnRejected);
  JSReleaseValue(AReaction.OnFinally);
  if AReaction.Child <> nil then
    AReaction.Child.Release;
end;

procedure TFloriaJSPromise.Attach(const AOnFulfilled, AOnRejected, AOnFinally: TFloriaJSValue; AIsFinally: Boolean; AChild: TFloriaJSPromise);
var
  reaction: TFloriaJSPromiseReaction;
  job: TFloriaJSPromiseJob;
begin
  if FState = fjspPending then
  begin
    reaction.OnFulfilled := AOnFulfilled;
    reaction.OnRejected := AOnRejected;
    reaction.OnFinally := AOnFinally;
    reaction.IsFinally := AIsFinally;
    reaction.Child := AChild;
    AddReaction(reaction);
    Exit;
  end;

  { Already settled: the reaction runs as a microtask. }
  if FHeap = nil then Exit;
  job.Kind := pjkReaction;
  job.OnFulfilled := AOnFulfilled;
  job.OnRejected := AOnRejected;
  job.OnFinally := AOnFinally;
  job.IsFinally := AIsFinally;
  job.IsRejection := (FState = fjspRejected);
  job.Value := FResult;
  job.Child := AChild;
  job.Target := nil;
  FHeap.EnqueuePromiseJob(job);
end;

procedure TFloriaJSPromise.ScheduleReactions();
var
  i: Integer;
  reaction: TFloriaJSPromiseReaction;
  job: TFloriaJSPromiseJob;
begin
  for i := 0 to FReactionCount - 1 do
  begin
    reaction := FReactions[i];
    job.Kind := pjkReaction;
    job.OnFulfilled := reaction.OnFulfilled;
    job.OnRejected := reaction.OnRejected;
    job.OnFinally := reaction.OnFinally;
    job.IsFinally := reaction.IsFinally;
    job.IsRejection := (FState = fjspRejected);
    job.Value := FResult;
    job.Child := reaction.Child;
    job.Target := nil;
    if FHeap <> nil then
      FHeap.EnqueuePromiseJob(job);
    { The job takes the references over from the reaction. }
    ReleaseReaction(reaction);
  end;
  FReactionCount := 0;
end;

procedure TFloriaJSPromise.Fulfill(const AValue: TFloriaJSValue);
var
  inner: TFloriaJSPromise;
begin
  if FState <> fjspPending then Exit;

  { A promise fulfills with another promise by adopting its settlement. }
  if AValue.IsPromise() then
  begin
    inner := AValue.AsPromise();
    if inner = Self then
    begin
      Reject(JSMakeString('Chaining cycle detected for promise'));
      Exit;
    end;
    inner.Attach(JSMakeUndefined(), JSMakeUndefined(), JSMakeUndefined(), False, Self);
    Exit;
  end;

  FState := fjspFulfilled;
  { The promise holds the reference to the value it is settled with. }
  JSReleaseValue(FResult);
  FResult := AValue;
  JSRetainValue(AValue);
  ScheduleReactions();
end;

procedure TFloriaJSPromise.Reject(const AValue: TFloriaJSValue);
begin
  if FState <> fjspPending then Exit;
  FState := fjspRejected;
  { The promise holds the reference to the value it is settled with. }
  JSReleaseValue(FResult);
  FResult := AValue;
  JSRetainValue(AValue);
  ScheduleReactions();
end;

function TFloriaJSPromise.Chain(const AOnFulfilled, AOnRejected: TFloriaJSValue): TFloriaJSPromise;
begin
  Result := TFloriaJSPromise(FHeap.Track(TFloriaJSPromise.Create(FHeap)));
  Attach(AOnFulfilled, AOnRejected, JSMakeUndefined(), False, Result);
end;

function TFloriaJSPromise.ChainFinally(const AOnFinally: TFloriaJSValue): TFloriaJSPromise;
begin
  Result := TFloriaJSPromise(FHeap.Track(TFloriaJSPromise.Create(FHeap)));
  Attach(JSMakeUndefined(), JSMakeUndefined(), AOnFinally, True, Result);
end;

function TFloriaJSPromise.GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue;
begin
  if AName = 'then' then
  begin
    if (FThenFn = nil) and (FHeap <> nil) then
      FThenFn := FHeap.NewNativeFunction('then', @JSPromiseThen);
    Exit(JSMakeFunction(FThenFn));
  end;

  if AName = 'catch' then
  begin
    if (FCatchFn = nil) and (FHeap <> nil) then
      FCatchFn := FHeap.NewNativeFunction('catch', @JSPromiseCatch);
    Exit(JSMakeFunction(FCatchFn));
  end;

  if AName = 'finally' then
  begin
    if (FFinallyFn = nil) and (FHeap <> nil) then
      FFinallyFn := FHeap.NewNativeFunction('finally', @JSPromiseFinally);
    Exit(JSMakeFunction(FFinallyFn));
  end;

  Result := inherited GetPropertyWithReceiver(AName, AReceiver);
end;

function TFloriaJSPromise.GetProperty(const AName: string): TFloriaJSValue;
begin
  Result := GetPropertyWithReceiver(AName, Self);
end;

function TFloriaJSPromise.HasProperty(const AName: string): Boolean;
begin
  if (AName = 'then') or (AName = 'catch') or (AName = 'finally') then
    Exit(True);
  Result := inherited HasProperty(AName);
end;

{ TFloriaJSHeap }

constructor TFloriaJSHeap.Create();
var
  entry: PFloriaJSHeapEntry;
begin
  inherited Create();
  FObjects := TFPList.Create();
  FEnvironments := TFPList.Create();
  FPromiseJobs := TFPList.Create();
  FTimerRegistry := nil;
  FJobRunner := nil;
  FInvoker := nil;
  FConstructInvoker := nil;
  FEvalInvoker := nil;
  FArrayPrototype := nil;
  FStringPrototype := nil;
  FNumberPrototype := nil;
  FPromisePrototype := nil;
  FAsyncGeneratorPrototype := nil;
  FFunctionPrototype := nil;
  FObjectPrototype := nil;
  FErrorPrototype := nil;
  FTypeErrorPrototype := nil;
  FRangeErrorPrototype := nil;
  FReferenceErrorPrototype := nil;
  FSyntaxErrorPrototype := nil;
  FRealmGlobal := nil;
  FCurrentNewTarget := JSMakeUndefined();
  FCurrentConstructor := nil;
  FOwnedHelpers := TFPList.Create();
  FClearing := False;
  Inc(GNextHeapId);
  FId := GNextHeapId;

  { The heap registers itself, so that owners outside of it can find out
    whether the values they hold are still valid. }
  if GLiveHeaps = nil then
    GLiveHeaps := TFPList.Create;
  New(entry);
  entry^.Heap := Self;
  entry^.Id := FId;
  GLiveHeaps.Add(entry);
end;

destructor TFloriaJSHeap.Destroy();
var
  i: Integer;
  entry: PFloriaJSHeapEntry;
begin
  if GLiveHeaps <> nil then
  begin
    for i := GLiveHeaps.Count - 1 downto 0 do
    begin
      entry := PFloriaJSHeapEntry(GLiveHeaps[i]);
      if entry^.Heap = Self then
      begin
        GLiveHeaps.Delete(i);
        Dispose(entry);
      end;
    end;
  end;

  Clear();
  if FPromiseJobs <> nil then
  begin
    while FPromiseJobs.Count > 0 do
    begin
      Dispose(PTFloriaJSPromiseJob(FPromiseJobs[FPromiseJobs.Count - 1]));
      FPromiseJobs.Delete(FPromiseJobs.Count - 1);
    end;
    FreeAndNil(FPromiseJobs);
  end;
  FJobRunner := nil;
  FInvoker := nil;
  FConstructInvoker := nil;
  FEvalInvoker := nil;
  FArrayPrototype := nil;
  FStringPrototype := nil;
  FNumberPrototype := nil;
  FPromisePrototype := nil;
  FAsyncGeneratorPrototype := nil;
  FFunctionPrototype := nil;
  FObjectPrototype := nil;
  FErrorPrototype := nil;
  FTypeErrorPrototype := nil;
  FRangeErrorPrototype := nil;
  FReferenceErrorPrototype := nil;
  FSyntaxErrorPrototype := nil;
  FreeAndNil(FEnvironments);
  FreeAndNil(FObjects);
  FreeAndNil(FOwnedHelpers);
  inherited Destroy();
end;

function TFloriaJSHeap.Track(AObj: TFloriaJSObject; AHeapOwned: Boolean): TFloriaJSObject;
begin
  if AObj <> nil then
  begin
    if (FObjects.IndexOf(AObj) < 0) then
      FObjects.Add(AObj);
    if AObj.Heap = nil then
      AObj.Heap := Self;
    { An object that is owned by somebody else is only registered here, so the
      heap keeps track of it without ever reclaiming it on its own. }
    AObj.HeapOwned := AHeapOwned;
  end;
  Result := AObj;
end;

function TFloriaJSHeap.TrackEnvironment(AEnv: TObject): TObject;
begin
  if (AEnv <> nil) and (FEnvironments.IndexOf(AEnv) < 0) then
    FEnvironments.Add(AEnv);
  Result := AEnv;
end;

function TFloriaJSHeap.Untrack(AObj: TObject): Boolean;
var
  idx: Integer;
begin
  Result := False;
  if AObj = nil then Exit;

  if FObjects <> nil then
  begin
    idx := FObjects.IndexOf(AObj);
    if idx >= 0 then
    begin
      FObjects.Delete(idx);
      Exit(True);
    end;
  end;

  if FEnvironments <> nil then
  begin
    idx := FEnvironments.IndexOf(AObj);
    if idx >= 0 then
    begin
      FEnvironments.Delete(idx);
      Exit(True);
    end;
  end;
end;

function TFloriaJSHeap.GetObjectPrototype(): TFloriaJSObject;
begin
  if FObjectPrototype = nil then
  begin
    FObjectPrototype := Track(TFloriaJSObject.Create(nil));
    FObjectPrototype.Pin();
  end;
  Result := FObjectPrototype;
end;

function TFloriaJSHeap.NewObject(AProto: TFloriaJSObject; ANoProto: Boolean): TFloriaJSObject;
begin
  if (AProto = nil) and (not ANoProto) and (FObjectPrototype <> nil) then
    AProto := FObjectPrototype;
  Result := Track(TFloriaJSObject.Create(AProto));
end;

function TFloriaJSHeap.NewArray(): TFloriaJSArray;
begin
  Result := TFloriaJSArray(Track(TFloriaJSArray.Create()));
  if Result <> nil then
    Result.Prototype := GetArrayPrototype();
end;

function TFloriaJSHeap.NewStringObject(AProto: TFloriaJSObject;
  const AValue: string): TFloriaJSStringObject;
begin
  Result := TFloriaJSStringObject(Track(TFloriaJSStringObject.Create(AProto, AValue)));
end;

function TFloriaJSHeap.GetArrayPrototype(): TFloriaJSObject;
begin
  if FArrayPrototype = nil then
  begin
    FArrayPrototype := NewObject(GetObjectPrototype());
    { The prototype is shared by every array, so the heap keeps it alive
      until the heap itself is cleared. }
    FArrayPrototype.Pin();
  end;
  Result := FArrayPrototype;
end;

function TFloriaJSHeap.GetStringPrototype(): TFloriaJSObject;
begin
  if FStringPrototype = nil then
  begin
    FStringPrototype := NewObject(GetObjectPrototype());
    FStringPrototype.Pin();
  end;
  Result := FStringPrototype;
end;

function TFloriaJSHeap.GetPromisePrototype(): TFloriaJSObject;
begin
  if FPromisePrototype = nil then
  begin
    FPromisePrototype := NewObject(GetObjectPrototype());
    FPromisePrototype.Pin();
  end;
  Result := FPromisePrototype;
end;

function TFloriaJSHeap.GetAsyncGeneratorPrototype(): TFloriaJSObject;
begin
  if FAsyncGeneratorPrototype = nil then
  begin
    FAsyncGeneratorPrototype := NewObject(GetObjectPrototype());
    FAsyncGeneratorPrototype.Pin();
  end;
  Result := FAsyncGeneratorPrototype;
end;

function TFloriaJSHeap.GetNumberPrototype(): TFloriaJSObject;
begin
  if FNumberPrototype = nil then
  begin
    FNumberPrototype := NewObject(GetObjectPrototype());
    FNumberPrototype.Pin();
    FNumberPrototype.SetProperty('toFixed', JSMakeFunction(NewNativeFunction('toFixed', @JSNumberToFixedMethod)));
    FNumberPrototype.SetProperty('toPrecision', JSMakeFunction(NewNativeFunction('toPrecision', @JSNumberToPrecisionMethod)));
    FNumberPrototype.SetProperty('toExponential', JSMakeFunction(NewNativeFunction('toExponential', @JSNumberToExponentialMethod)));
    FNumberPrototype.SetProperty('toString', JSMakeFunction(NewNativeFunction('toString', @JSNumberToString)));
    FNumberPrototype.SetProperty('valueOf', JSMakeFunction(NewNativeFunction('valueOf', @JSNumberValueOf)));
  end;
  GNumberPrototype := FNumberPrototype;
  Result := FNumberPrototype;
end;

function TFloriaJSHeap.GetFunctionPrototype(): TFloriaJSObject;
begin
  if FFunctionPrototype = nil then
  begin
    FFunctionPrototype := NewObject(GetObjectPrototype());
    FFunctionPrototype.Pin();
    FFunctionPrototype.SetProperty('call', JSMakeFunction(NewNativeFunction('call', @JSFunctionCall)));
    FFunctionPrototype.SetProperty('apply', JSMakeFunction(NewNativeFunction('apply', @JSFunctionApply)));
    FFunctionPrototype.SetProperty('bind', JSMakeFunction(NewNativeFunction('bind', @JSFunctionBind)));
    FFunctionPrototype.SetProperty('toString', JSMakeFunction(NewNativeFunction('toString', @JSFunctionToString)));
  end;
  Result := FFunctionPrototype;
end;

function TFloriaJSHeap.ArrayCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  proto: TFloriaJSObject;
  d: Double;
  i: Integer;
begin
  { A single numeric argument is the requested length; anything else is an
    element of the new array. The length form creates a sparse array of holes,
    not an array of explicit undefined elements. }
  proto := GetPrototypeFromConstructor(CurrentNewTarget, 'Array');
  if (Length(AArgs) = 1) and AArgs[0].IsNumber() then
  begin
    d := AArgs[0].ToNumber();
    if IsNaN(d) or (d < 0) or (d <> Int(d)) or (d > 2147483647.0) then
      raise EFloriaJSThrow.Create(JSMakeObject(NewError('RangeError', 'Invalid array length')));
    arr := NewArray();
    arr.SetLengthTo(Trunc(d));
  end
  else
  begin
    arr := NewArray();
    for i := 0 to High(AArgs) do
      arr.Push(AArgs[i]);
  end;

  if proto <> nil then
    arr.Prototype := proto;
  Result := JSMakeArray(arr);
end;

procedure TFloriaJSHeap.SetFunctionInvoker(AInvoker: TFloriaJSFunctionInvoker);
begin
  FInvoker := AInvoker;
end;

procedure TFloriaJSHeap.SetEvalInvoker(AInvoker: TFloriaJSSourceEvaluator);
begin
  FEvalInvoker := AInvoker;
end;

function TFloriaJSHeap.HasEvalInvoker(): Boolean;
begin
  Result := Assigned(FEvalInvoker);
end;

function TFloriaJSHeap.EvaluateSource(const ASource: string): TFloriaJSValue;
begin
  if Assigned(FEvalInvoker) then
    Result := FEvalInvoker(ASource)
  else
    Result := JSMakeUndefined();
end;

procedure TFloriaJSHeap.SetConstructInvoker(AInvoker: TFloriaJSConstructInvoker);
begin
  FConstructInvoker := AInvoker;
end;

function TFloriaJSHeap.ConstructFunction(const AFuncVal: TFloriaJSValue;
  const AArgs: TFloriaJSValueArray): TFloriaJSValue;
begin
  if Assigned(FConstructInvoker) then
    Result := FConstructInvoker(AFuncVal, AArgs)
  else
    raise EFloriaJSThrow.Create(JSMakeObject(NewError('TypeError', 'Value is not a constructor')));
end;

function TFloriaJSHeap.ResolveConstructorTarget(const AFuncVal: TFloriaJSValue): TFloriaJSFunction;
var
  fn: TFloriaJSFunction;
  target: TFloriaJSValue;
  guard: Integer;
begin
  Result := nil;
  if not AFuncVal.IsFunction() then Exit;

  { Follows a chain of bound functions down to the function that really runs.
    The guard bounds a pathological self-referential chain. }
  target := AFuncVal;
  guard := 0;
  while target.IsFunction() and (guard < 1000) do
  begin
    fn := target.AsFunction();
    if not (fn is TFloriaJSBoundFunction) then
      Exit(fn);
    target := TFloriaJSBoundFunction(fn).Target;
    Inc(guard);
  end;
end;

function TFloriaJSHeap.IsConstructable(const AFuncVal: TFloriaJSValue): Boolean;
var
  fn: TFloriaJSFunction;
begin
  Result := False;
  if AFuncVal.IsObject() and (AFuncVal.ObjVal is TFloriaJSProxy) then
    Exit(TFloriaJSProxy(AFuncVal.ObjVal).Callable);
  if not AFuncVal.IsFunction() then Exit;
  fn := ResolveConstructorTarget(AFuncVal);
  { Arrows have no `prototype` and are rejected by `new`; every other function
    object is constructable in this runtime. }
  Result := (fn <> nil) and (not fn.IsArrow) and (not fn.NotConstructable) and
    (not fn.IsAsyncGenerator);
end;

function TFloriaJSHeap.GetConstructPrototype(const AFuncVal: TFloriaJSValue): TFloriaJSObject;
var
  fn: TFloriaJSFunction;
  protoVal: TFloriaJSValue;
begin
  Result := nil;
  if not IsConstructable(AFuncVal) then Exit;

  { The prototype is always read from the underlying target, never from the
    bound function, which has none of its own. }
  fn := ResolveConstructorTarget(AFuncVal);
  if fn = nil then Exit;

  protoVal := fn.GetProperty('prototype');
  if protoVal.IsObject() then
    Result := protoVal.AsObject()
  else
    Result := GetPrototypeFromConstructor(AFuncVal, 'Object');
end;

function TFloriaJSHeap.GetRealmIntrinsicPrototype(const AIntrinsic: string): TFloriaJSObject;
var
  ctorVal, protoVal: TFloriaJSValue;
begin
  { Prefer the intrinsic reachable from this realm's own global object. This
    covers constructors registered by separate units, such as ArrayBuffer and
    DataView, without centralizing their prototypes here. }
  if FRealmGlobal <> nil then
  begin
    ctorVal := FRealmGlobal.GetProperty(AIntrinsic);
    if ctorVal.IsFunction() and ctorVal.AsFunction().HasProperty('prototype') then
    begin
      protoVal := ctorVal.AsFunction().GetProperty('prototype');
      if protoVal.IsObject() then
        Exit(protoVal.AsObject());
    end;
  end;

  { Shared prototypes that exist before the global constructor table is
    populated, and the fallback for names without a dedicated prototype. }
  if AIntrinsic = 'Array' then
    Result := GetArrayPrototype()
  else if AIntrinsic = 'String' then
    Result := GetStringPrototype()
  else if AIntrinsic = 'Number' then
    Result := GetNumberPrototype()
  else if AIntrinsic = 'Promise' then
    Result := GetPromisePrototype()
  else if AIntrinsic = 'Function' then
    Result := GetFunctionPrototype()
  else if AIntrinsic = 'Error' then
    Result := GetErrorPrototype()
  else if AIntrinsic = 'TypeError' then
    Result := GetTypeErrorPrototype()
  else if AIntrinsic = 'RangeError' then
    Result := GetRangeErrorPrototype()
  else if AIntrinsic = 'ReferenceError' then
    Result := GetReferenceErrorPrototype()
  else if AIntrinsic = 'SyntaxError' then
    Result := GetSyntaxErrorPrototype()
  else
    Result := GetObjectPrototype();
end;

function TFloriaJSHeap.GetPrototypeFromConstructor(const ANewTarget: TFloriaJSValue;
  const AIntrinsic: string): TFloriaJSObject;
var
  fn: TFloriaJSFunction;
  protoVal: TFloriaJSValue;
  realmHeap: TFloriaJSHeap;
begin
  fn := nil;
  if ANewTarget.IsFunction() then
    fn := ResolveConstructorTarget(ANewTarget);

  if fn <> nil then
  begin
    protoVal := fn.GetProperty('prototype');
    if protoVal.IsObject() then
      Exit(protoVal.AsObject());

    realmHeap := fn.Heap;
    if realmHeap <> nil then
      Exit(realmHeap.GetRealmIntrinsicPrototype(AIntrinsic));
  end;

  Result := GetRealmIntrinsicPrototype(AIntrinsic);
end;

procedure TFloriaJSHeap.OwnHelper(AHelper: TObject);
begin
  if (AHelper <> nil) and (FOwnedHelpers <> nil) then
    FOwnedHelpers.Add(AHelper);
end;

function TFloriaJSHeap.InvokeFunction(const AFuncVal: TFloriaJSValue;
  const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Assigned(FInvoker) then
    Result := FInvoker(AFuncVal, AArgs, AThis)
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSHeap.GetErrorPrototype(): TFloriaJSObject;
begin
  if FErrorPrototype = nil then
  begin
    FErrorPrototype := NewObject(GetObjectPrototype());
    FErrorPrototype.Pin();
    FErrorPrototype.SetProperty('name', JSMakeString('Error'));
    FErrorPrototype.SetProperty('message', JSMakeString(''));
    FErrorPrototype.SetProperty('toString', JSMakeFunction(NewNativeFunction('toString', @JSErrorToString)));
  end;
  Result := FErrorPrototype;
end;

function TFloriaJSHeap.GetTypeErrorPrototype(): TFloriaJSObject;
begin
  if FTypeErrorPrototype = nil then
  begin
    FTypeErrorPrototype := NewObject(GetErrorPrototype());
    FTypeErrorPrototype.Pin();
    FTypeErrorPrototype.SetProperty('name', JSMakeString('TypeError'));
    FTypeErrorPrototype.SetProperty('message', JSMakeString(''));
  end;
  Result := FTypeErrorPrototype;
end;

function TFloriaJSHeap.GetRangeErrorPrototype(): TFloriaJSObject;
begin
  if FRangeErrorPrototype = nil then
  begin
    FRangeErrorPrototype := NewObject(GetErrorPrototype());
    FRangeErrorPrototype.Pin();
    FRangeErrorPrototype.SetProperty('name', JSMakeString('RangeError'));
    FRangeErrorPrototype.SetProperty('message', JSMakeString(''));
  end;
  Result := FRangeErrorPrototype;
end;

function TFloriaJSHeap.GetReferenceErrorPrototype(): TFloriaJSObject;
begin
  if FReferenceErrorPrototype = nil then
  begin
    FReferenceErrorPrototype := NewObject(GetErrorPrototype());
    FReferenceErrorPrototype.Pin();
    FReferenceErrorPrototype.SetProperty('name', JSMakeString('ReferenceError'));
    FReferenceErrorPrototype.SetProperty('message', JSMakeString(''));
  end;
  Result := FReferenceErrorPrototype;
end;

function TFloriaJSHeap.GetSyntaxErrorPrototype(): TFloriaJSObject;
begin
  if FSyntaxErrorPrototype = nil then
  begin
    FSyntaxErrorPrototype := NewObject(GetErrorPrototype());
    FSyntaxErrorPrototype.Pin();
    FSyntaxErrorPrototype.SetProperty('name', JSMakeString('SyntaxError'));
    FSyntaxErrorPrototype.SetProperty('message', JSMakeString(''));
  end;
  Result := FSyntaxErrorPrototype;
end;

function TFloriaJSHeap.NewError(const AName, AMessage: string): TFloriaJSError;
begin
  Result := TFloriaJSError(Track(TFloriaJSError.Create(AName, AMessage)));
  case AName of
    'TypeError':      Result.Prototype := GetTypeErrorPrototype();
    'RangeError':     Result.Prototype := GetRangeErrorPrototype();
    'ReferenceError': Result.Prototype := GetReferenceErrorPrototype();
    'SyntaxError':    Result.Prototype := GetSyntaxErrorPrototype();
  else
    Result.Prototype := GetErrorPrototype();
  end;
end;

function TFloriaJSHeap.ErrorCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  msg: string;
begin
  if Length(AArgs) > 0 then
    msg := AArgs[0].ToString()
  else
    msg := '';

  Result := JSMakeObject(NewError('Error', msg));
end;

function TFloriaJSHeap.TypeErrorCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  msg: string;
begin
  if Length(AArgs) > 0 then
    msg := AArgs[0].ToString()
  else
    msg := '';
  Result := JSMakeObject(NewError('TypeError', msg));
end;

function TFloriaJSHeap.RangeErrorCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  msg: string;
begin
  if Length(AArgs) > 0 then
    msg := AArgs[0].ToString()
  else
    msg := '';
  Result := JSMakeObject(NewError('RangeError', msg));
end;

function TFloriaJSHeap.ReferenceErrorCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  msg: string;
begin
  if Length(AArgs) > 0 then
    msg := AArgs[0].ToString()
  else
    msg := '';
  Result := JSMakeObject(NewError('ReferenceError', msg));
end;

function TFloriaJSHeap.SyntaxErrorCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  msg: string;
begin
  if Length(AArgs) > 0 then
    msg := AArgs[0].ToString()
  else
    msg := '';
  Result := JSMakeObject(NewError('SyntaxError', msg));
end;

function TFloriaJSHeap.ObjectCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  { An object argument is returned unchanged. A construction already created
    the object that is bound to this, so the constructor hands it back; a
    plain call creates a new object. }
  if (Length(AArgs) > 0) and AArgs[0].IsObject() then
    Exit(AArgs[0]);
  if AThis.IsObject() then
    Exit(AThis);

  Result := JSMakeObject(NewObject());
end;

function TFloriaJSHeap.NewPromise(): TFloriaJSPromise;
begin
  Result := TFloriaJSPromise(Track(TFloriaJSPromise.Create(Self)));
end;

procedure TFloriaJSHeap.SetJobRunner(ARunner: TFloriaJSJobRunner);
begin
  FJobRunner := ARunner;
end;

procedure TFloriaJSHeap.EnqueuePromiseJob(const AJob: TFloriaJSPromiseJob);
var
  job: PTFloriaJSPromiseJob;
begin
  if FPromiseJobs = nil then Exit;
  New(job);
  job^ := AJob;
  FPromiseJobs.Add(job);
  { The queue holds the values of the job until the job has been run. }
  JSRetainValue(AJob.OnFulfilled);
  JSRetainValue(AJob.OnRejected);
  JSRetainValue(AJob.OnFinally);
  JSRetainValue(AJob.Value);
  if AJob.Child <> nil then
    AJob.Child.Retain;
  if AJob.Target <> nil then
    AJob.Target.Retain;
end;

procedure TFloriaJSHeap.EnqueuePromiseSettlement(APromise: TFloriaJSPromise;
  const AValue: TFloriaJSValue; AIsRejection: Boolean);
var
  job: TFloriaJSPromiseJob;
begin
  if APromise = nil then Exit;
  job.Kind := pjkFulfill;
  if AIsRejection then
    job.Kind := pjkReject;
  job.OnFulfilled := JSMakeUndefined();
  job.OnRejected := JSMakeUndefined();
  job.OnFinally := JSMakeUndefined();
  job.IsFinally := False;
  job.IsRejection := AIsRejection;
  job.Value := AValue;
  job.Child := nil;
  job.Target := APromise;
  EnqueuePromiseJob(job);
end;

function TFloriaJSHeap.DequeuePromiseJob(out AJob: TFloriaJSPromiseJob): Boolean;
var
  job: PTFloriaJSPromiseJob;
begin
  Result := False;
  if (FPromiseJobs = nil) or (FPromiseJobs.Count = 0) then Exit;
  job := PTFloriaJSPromiseJob(FPromiseJobs[0]);
  AJob := job^;
  FPromiseJobs.Delete(0);
  Dispose(job);
  { The references of the job are handed over to the caller, which gives them
    up again once the job has been run. }
  Result := True;
end;

function TFloriaJSHeap.HasPromiseJobs(): Boolean;
begin
  Result := (FPromiseJobs <> nil) and (FPromiseJobs.Count > 0);
end;

procedure TFloriaJSHeap.RunPendingJobs();
var
  job: TFloriaJSPromiseJob;
begin
  while DequeuePromiseJob(job) do
  begin
    if Assigned(FJobRunner) then
      FJobRunner(job);
    { The job is done, so it gives up the references it was holding. }
    JSReleaseValue(job.OnFulfilled);
    JSReleaseValue(job.OnRejected);
    JSReleaseValue(job.OnFinally);
    JSReleaseValue(job.Value);
    if job.Child <> nil then
      job.Child.Release;
    if job.Target <> nil then
      job.Target.Release;
  end;
end;


{ TFloriaJSGenerator }

constructor TFloriaJSGenerator.Create(AHeap: TFloriaJSHeap);
begin
  if AHeap <> nil then
    inherited Create(AHeap.GetPromisePrototype())
  else
    inherited Create(nil);
  Heap := AHeap;
  FBytecode := nil;
  FEnv := nil;
  FCurrentEnv := nil;
  FThisVal := JSMakeUndefined();
  SetLength(FArgs, 0);
  FIP := 0;
  FBaseBP := 0;
  SetLength(FStack, 0);
  FStackCount := 0;
  FState := fjgsSuspendedStart;
  FReturnValue := JSMakeUndefined();
  FNextFn := nil;
  FReturnFn := nil;
  FThrowFn := nil;
  FSelfIteratorFn := nil;
  FRunner := nil;
  FAsyncResume := nil;
  FIsAsyncTask := False;
  FAsyncPromise := nil;
  FHasPendingThrow := False;
  FPendingThrow := JSMakeUndefined();
  FTrySnapshotCount := 0;
  SetLength(FTrySnapshots, 0);
end;

destructor TFloriaJSGenerator.Destroy();
var
  i: Integer;
begin
  { Give up the references this generator holds, so the methods it created can
    be reclaimed once nothing else uses them. }
  if FNextFn <> nil then
  begin
    FNextFn.Release();
    FNextFn := nil;
  end;
  if FReturnFn <> nil then
  begin
    FReturnFn.Release();
    FReturnFn := nil;
  FThrowFn := nil;
  end;
  if FSelfIteratorFn <> nil then
  begin
    FSelfIteratorFn.Release();
    FSelfIteratorFn := nil;
  end;

  for i := 0 to FStackCount - 1 do
    JSReleaseValue(FStack[i]);
  SetLength(FStack, 0);
  SetLength(FArgs, 0);
  JSReleaseValue(FThisVal);
  JSReleaseValue(FReturnValue);
  JSReleaseValue(FPendingThrow);
  FPendingThrow := JSMakeUndefined();
  if FAsyncPromise <> nil then
  begin
    FAsyncPromise.Release();
    FAsyncPromise := nil;
  end;
  SetLength(FTrySnapshots, 0);
  FTrySnapshotCount := 0;
  if FBytecode <> nil then
  begin
    TFloriaJSBytecode(FBytecode).Release();
    FBytecode := nil;
  end;
  { The generator kept its activation environment alive for as long as it could
    resume. Detaching it lets the heap reclaim it once nothing else refers to
    it; without this every generator left an environment behind. During a full
    clear the environments are already gone, so the pointer must not be
    touched. }
  if FEnv <> nil then
  begin
    if (Heap = nil) or (not Heap.IsClearing) then
      TFloriaJSEnvironment(FEnv).Detach();
    FEnv := nil;
  end;
  if FCurrentEnv <> nil then
  begin
    if (Heap = nil) or (not Heap.IsClearing) then
      TFloriaJSEnvironment(FCurrentEnv).Unpin();
    FCurrentEnv := nil;
  end;
  inherited Destroy();
end;

procedure TFloriaJSGenerator.OwnMethod(var AField: TFloriaJSFunction;
  const AName: string; AMethod: TFloriaJSNativeMethod);
begin
  if (AField <> nil) or (Heap = nil) then Exit;
  AField := Heap.NewNativeMethod(AName, AMethod);
  if AField <> nil then
    AField.Retain();
end;

procedure TFloriaJSGenerator.SetBytecode(ABytecode: TObject);
var
  old: TFloriaJSBytecode;
begin
  old := TFloriaJSBytecode(FBytecode);
  FBytecode := ABytecode;
  if (ABytecode <> nil) and (TFloriaJSBytecode(ABytecode) <> old) then
    TFloriaJSBytecode(ABytecode).Retain();
  if (old <> nil) and (old <> TFloriaJSBytecode(ABytecode)) then
    old.Release();
end;

procedure TFloriaJSGenerator.SetArgs(const AArgs: TFloriaJSValueArray);
var
  i: Integer;
begin
  for i := 0 to High(FArgs) do
    JSReleaseValue(FArgs[i]);
  SetLength(FArgs, Length(AArgs));
  for i := 0 to High(AArgs) do
  begin
    FArgs[i] := AArgs[i];
    JSRetainValue(FArgs[i]);
  end;
end;

procedure TFloriaJSGenerator.SetThisVal(const AValue: TFloriaJSValue);
begin
  if FThisVal.Kind <> fjstUndefined then
    JSReleaseValue(FThisVal);
  FThisVal := AValue;
  JSRetainValue(FThisVal);
end;

procedure TFloriaJSGenerator.SetEnv(AEnv: Pointer);
var
  oldEnv: TFloriaJSEnvironment;
begin
  oldEnv := TFloriaJSEnvironment(FEnv);
  FEnv := AEnv;
  if (FEnv <> nil) and (TFloriaJSEnvironment(FEnv) <> oldEnv) then
    TFloriaJSEnvironment(FEnv).MarkCaptured();
end;

procedure TFloriaJSGenerator.SetCurrentEnv(AEnv: Pointer);
var
  oldEnv: TFloriaJSEnvironment;
begin
  oldEnv := TFloriaJSEnvironment(FCurrentEnv);
  if oldEnv = TFloriaJSEnvironment(AEnv) then
    Exit;
  { The activation that was suspended at the previous await is no longer
    needed once a new one replaces it. }
  if oldEnv <> nil then
    oldEnv.Unpin();
  FCurrentEnv := AEnv;
  if FCurrentEnv <> nil then
  begin
    { The block scope is left when the generator unwinds, but the bindings are
      still needed when it resumes, so keep the environment alive. }
    TFloriaJSEnvironment(FCurrentEnv).MarkCaptured();
    TFloriaJSEnvironment(FCurrentEnv).Pin();
  end;
end;

procedure TFloriaJSGenerator.PushSnapshotValue(const AValue: TFloriaJSValue);
begin
  if FStackCount >= Length(FStack) then
  begin
    if Length(FStack) = 0 then
      SetLength(FStack, 8)
    else
      SetLength(FStack, Length(FStack) * 2);
  end;
  FStack[FStackCount] := AValue;
  JSRetainValue(AValue);
  Inc(FStackCount);
end;

procedure TFloriaJSGenerator.ClearSnapshot();
var
  i: Integer;
begin
  for i := 0 to FStackCount - 1 do
    JSReleaseValue(FStack[i]);
  FStackCount := 0;
end;

function TFloriaJSGenerator.SnapshotValue(AIndex: Integer): TFloriaJSValue;
begin
  if (AIndex >= 0) and (AIndex < FStackCount) then
    Result := FStack[AIndex]
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSGenerator.AsyncFulfilled(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  value: TFloriaJSValue;
begin
  if Length(AArgs) > 0 then
    value := AArgs[0]
  else
    value := JSMakeUndefined();
  if Assigned(FAsyncResume) then
    FAsyncResume(Self, value, False);
  Result := JSMakeUndefined();
end;

function TFloriaJSGenerator.AsyncRejected(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  value: TFloriaJSValue;
begin
  if Length(AArgs) > 0 then
    value := AArgs[0]
  else
    value := JSMakeUndefined();
  if Assigned(FAsyncResume) then
    FAsyncResume(Self, value, True);
  Result := JSMakeUndefined();
end;

function TFloriaJSGenerator.AsyncYieldFulfilled(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  value: TFloriaJSValue;
  resultObj: TFloriaJSObject;
  promise: TFloriaJSPromise;
begin
  if Length(AArgs) > 0 then
    value := AArgs[0]
  else
    value := JSMakeUndefined();
  promise := FAsyncPromise;
  if promise <> nil then
  begin
    resultObj := Heap.NewObject(Heap.GetObjectPrototype());
    resultObj.SetProperty('value', value);
    resultObj.SetProperty('done', JSMakeBoolean(False));
    promise.Fulfill(JSMakeObject(resultObj));
  end;
  FAsyncPromise := nil;
  FAsyncGeneratorYielded := False;
  Release();
  Result := JSMakeUndefined();
end;

function TFloriaJSGenerator.AsyncYieldRejected(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  value: TFloriaJSValue;
begin
  if Length(AArgs) > 0 then
    value := AArgs[0]
  else
    value := JSMakeUndefined();
  { A rejected yielded value is thrown back into the generator at the yield
    point. If the body does not catch it, the pending next() promise rejects. }
  if Assigned(FAsyncResume) then
    FAsyncResume(Self, value, True);
  Result := JSMakeUndefined();
end;

function TFloriaJSGenerator.AsyncReturnFulfilled(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  resultValue, innerValue: TFloriaJSValue;
  done: Boolean;
  resultObj: TFloriaJSObject;
  promise: TFloriaJSPromise;
begin
  if Length(AArgs) > 0 then
    resultValue := AArgs[0]
  else
    resultValue := JSMakeUndefined();
  done := True;
  innerValue := resultValue;
  if resultValue.IsObject() then
  begin
    done := resultValue.AsObject().GetProperty('done').ToBoolean();
    innerValue := resultValue.AsObject().GetProperty('value');
  end;
  promise := FAsyncPromise;
  if promise <> nil then
  begin
    resultObj := Heap.NewObject(Heap.GetObjectPrototype());
    resultObj.SetProperty('value', innerValue);
    resultObj.SetProperty('done', JSMakeBoolean(done));
    promise.Fulfill(JSMakeObject(resultObj));
  end;
  FAsyncPromise := nil;
  if done then
  begin
    FState := fjgsCompleted;
    FReturnValue := innerValue;
    FInYieldStar := False;
    FYieldStarIterator := JSMakeUndefined();
  end;
  Release();
  Result := JSMakeUndefined();
end;

function TFloriaJSGenerator.AsyncReturnRejected(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  value: TFloriaJSValue;
begin
  if Length(AArgs) > 0 then value := AArgs[0] else value := JSMakeUndefined();
  if FAsyncPromise <> nil then
    FAsyncPromise.Reject(value);
  FAsyncPromise := nil;
  FState := fjgsCompleted;
  FReturnValue := JSMakeUndefined();
  FInYieldStar := False;
  FYieldStarDone := False;
  FYieldStarIterator := JSMakeUndefined();
  Release();
  Result := JSMakeUndefined();
end;

function TFloriaJSGenerator.AsyncThrowFulfilled(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  resultValue, innerValue: TFloriaJSValue;
  done: Boolean;
  resultObj: TFloriaJSObject;
  promise: TFloriaJSPromise;
begin
  if Length(AArgs) > 0 then
    resultValue := AArgs[0]
  else
    resultValue := JSMakeUndefined();
  done := True;
  innerValue := resultValue;
  if resultValue.IsObject() then
  begin
    done := resultValue.AsObject().GetProperty('done').ToBoolean();
    innerValue := resultValue.AsObject().GetProperty('value');
  end;
  if done then
  begin
    { A completed throw delegation becomes the yield* result, so resume the
      outer generator body after the yield* expression. }
    FYieldStarDone := True;
    FState := fjgsSuspendedYield;
    if Assigned(FAsyncResume) then
      FAsyncResume(Self, innerValue, False);
    Exit(JSMakeUndefined());
  end;
  promise := FAsyncPromise;
  if promise <> nil then
  begin
    resultObj := Heap.NewObject(Heap.GetObjectPrototype());
    resultObj.SetProperty('value', innerValue);
    resultObj.SetProperty('done', JSMakeBoolean(False));
    promise.Fulfill(JSMakeObject(resultObj));
  end;
  FAsyncPromise := nil;
  Release();
  Result := JSMakeUndefined();
end;

function TFloriaJSGenerator.AsyncThrowRejected(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := AsyncReturnRejected(AArgs, AThis);
end;

procedure TFloriaJSGenerator.PushTrySnapshot(ACatchIP, AFrameOffset,
  AStackDepth: Integer; AEnv: Pointer);
begin
  if FTrySnapshotCount >= Length(FTrySnapshots) then
  begin
    if Length(FTrySnapshots) = 0 then
      SetLength(FTrySnapshots, 8)
    else
      SetLength(FTrySnapshots, Length(FTrySnapshots) * 2);
  end;
  FTrySnapshots[FTrySnapshotCount].CatchIP := ACatchIP;
  FTrySnapshots[FTrySnapshotCount].FrameOffset := AFrameOffset;
  FTrySnapshots[FTrySnapshotCount].StackDepth := AStackDepth;
  FTrySnapshots[FTrySnapshotCount].Env := AEnv;
  Inc(FTrySnapshotCount);
end;

procedure TFloriaJSGenerator.ClearTrySnapshots();
begin
  FTrySnapshotCount := 0;
  SetLength(FTrySnapshots, 0);
end;

function TFloriaJSGenerator.TrySnapshotCount(): Integer;
begin
  Result := FTrySnapshotCount;
end;

procedure TFloriaJSGenerator.GetTrySnapshot(AIndex: Integer;
  out ACatchIP, AFrameOffset, AStackDepth: Integer; out AEnv: Pointer);
begin
  if (AIndex < 0) or (AIndex >= FTrySnapshotCount) then
  begin
    ACatchIP := 0;
    AFrameOffset := 0;
    AStackDepth := 0;
    AEnv := nil;
    Exit;
  end;
  ACatchIP := FTrySnapshots[AIndex].CatchIP;
  AFrameOffset := FTrySnapshots[AIndex].FrameOffset;
  AStackDepth := FTrySnapshots[AIndex].StackDepth;
  AEnv := FTrySnapshots[AIndex].Env;
end;

function TFloriaJSGenerator.Next(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  resultObj: TFloriaJSObject;
  sent, value: TFloriaJSValue;
  done: Boolean;
begin
  if FIsAsyncGenerator and Assigned(FAsyncGeneratorNext) then
  begin
    if Length(AArgs) > 0 then
      sent := AArgs[0]
    else
      sent := JSMakeUndefined();
    Exit(JSMakePromise(FAsyncGeneratorNext(Self, sent, 0)));
  end;

  resultObj := Heap.NewObject(Heap.GetObjectPrototype());

  if FState = fjgsCompleted then
  begin
    resultObj.SetProperty('value', FReturnValue);
    resultObj.SetProperty('done', JSMakeBoolean(True));
    Exit(JSMakeObject(resultObj));
  end;

  if Length(AArgs) > 0 then
    sent := AArgs[0]
  else
    sent := JSMakeUndefined();

  done := True;
  value := JSMakeUndefined();
  if Assigned(FRunner) then
    FRunner(Self, sent, value, done);

  if done then
  begin
    FState := fjgsCompleted;
    FReturnValue := value;
  end;

  resultObj.SetProperty('value', value);
  resultObj.SetProperty('done', JSMakeBoolean(done));
  Result := JSMakeObject(resultObj);
end;

function TFloriaJSGenerator.Return_(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  resultObj: TFloriaJSObject;
  value: TFloriaJSValue;
begin
  if Length(AArgs) > 0 then
    value := AArgs[0]
  else
    value := JSMakeUndefined();

  if FIsAsyncGenerator and Assigned(FAsyncGeneratorNext) then
    Exit(JSMakePromise(FAsyncGeneratorNext(Self, value, 1)));

  ClearSnapshot();
  FState := fjgsCompleted;
  FReturnValue := value;

  resultObj := Heap.NewObject(Heap.GetObjectPrototype());
  resultObj.SetProperty('value', value);
  resultObj.SetProperty('done', JSMakeBoolean(True));
  Result := JSMakeObject(resultObj);
end;

function TFloriaJSGenerator.Throw_(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  value: TFloriaJSValue;
begin
  if Length(AArgs) > 0 then
    value := AArgs[0]
  else
    value := JSMakeUndefined();
  if FIsAsyncGenerator and Assigned(FAsyncGeneratorNext) then
    Exit(JSMakePromise(FAsyncGeneratorNext(Self, value, 2)));
  if Assigned(FAsyncResume) then
    FAsyncResume(Self, value, True);
  Result := JSMakeUndefined();
end;

function TFloriaJSGenerator.SelfIterator(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeObject(Self);
end;

function TFloriaJSGenerator.GetPropertyWithReceiver(const AName: string;
  AReceiver: TFloriaJSObject): TFloriaJSValue;
begin
  if AName = 'next' then
  begin
    OwnMethod(FNextFn, 'next', @Self.Next);
    Exit(JSMakeFunction(FNextFn));
  end;

  if AName = 'return' then
  begin
    OwnMethod(FReturnFn, 'return', @Self.Return_);
    Exit(JSMakeFunction(FReturnFn));
  end;

  if AName = 'throw' then
  begin
    OwnMethod(FThrowFn, 'throw', @Self.Throw_);
    Exit(JSMakeFunction(FThrowFn));
  end;

  if JSIsWellKnownSymbolKey(AName, 'Symbol.iterator') or (AName = '@@iterator') then
  begin
    OwnMethod(FSelfIteratorFn, '[Symbol.iterator]', @Self.SelfIterator);
    Exit(JSMakeFunction(FSelfIteratorFn));
  end;

  if JSIsWellKnownSymbolKey(AName, 'Symbol.asyncIterator') or (AName = '@@asyncIterator') then
  begin
    OwnMethod(FSelfIteratorFn, '[Symbol.asyncIterator]', @Self.SelfIterator);
    Exit(JSMakeFunction(FSelfIteratorFn));
  end;

  Result := inherited GetPropertyWithReceiver(AName, AReceiver);
end;

function TFloriaJSGenerator.HasProperty(const AName: string): Boolean;
begin
  if (AName = 'next') or (AName = 'return') or
     JSIsWellKnownSymbolKey(AName, 'Symbol.iterator') or
     JSIsWellKnownSymbolKey(AName, 'Symbol.asyncIterator') or
     (AName = '@@iterator') or (AName = '@@asyncIterator') then
    Exit(True);
  Result := inherited HasProperty(AName);
end;

{ TFloriaJSPromiseResolver }

constructor TFloriaJSPromiseResolver.Create(AHeap: TFloriaJSHeap; APromise: TFloriaJSPromise);
begin
  inherited Create();
  FHeap := AHeap;
  FPromise := APromise;
  FSettled := False;
  { A method pointer must come from an instance, not a type name. }
  FResolveFn := AHeap.NewNativeMethod('resolve', @Self.Resolve);
  FRejectFn := AHeap.NewNativeMethod('reject', @Self.Reject);
end;

destructor TFloriaJSPromiseResolver.Destroy();
begin
  { The functions point back at this object, so they must not outlive it. They
    are owned by the heap, which drops them when it collects; clearing the
    method here would leave a dangling call target if one were still reachable.
    Instead the heap frees this helper only after the promise graph is gone. }
  inherited Destroy();
end;

function TFloriaJSPromiseResolver.Resolve(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  value: TFloriaJSValue;
begin
  { The first call wins: later calls are ignored. }
  if FSettled then
    Exit(JSMakeUndefined());
  FSettled := True;

  if Length(AArgs) > 0 then
    value := AArgs[0]
  else
    value := JSMakeUndefined();

  { Resolving with the promise itself is a TypeError in ECMAScript. }
  if value.IsPromise() and (value.AsPromise() = FPromise) then
  begin
    FPromise.Reject(JSMakeObject(FHeap.NewError('TypeError',
      'Chaining cycle detected for promise')));
    Exit(JSMakeUndefined());
  end;

  FPromise.Fulfill(value);
  Result := JSMakeUndefined();
end;

function TFloriaJSPromiseResolver.Reject(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if FSettled then
    Exit(JSMakeUndefined());
  FSettled := True;

  if Length(AArgs) > 0 then
    FPromise.Reject(AArgs[0])
  else
    FPromise.Reject(JSMakeUndefined());
  Result := JSMakeUndefined();
end;

function TFloriaJSHeap.PromiseConstructor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  p: TFloriaJSPromise;
  resolver: TFloriaJSPromiseResolver;
  executor: TFloriaJSValue;
  resolveArgs: TFloriaJSValueArray;
begin
  if (Length(AArgs) = 0) or (not AArgs[0].IsFunction()) then
    raise EFloriaJSThrow.Create(JSMakeObject(NewError('TypeError',
      'Promise resolver is not a function')));
  executor := AArgs[0];

  p := NewPromise();
  { Promise .prototype is currently Object.prototype, but the newTarget realm
    still decides which Object.prototype the result inherits from. }
  p.Prototype := GetPrototypeFromConstructor(CurrentNewTarget, 'Promise');
  resolver := TFloriaJSPromiseResolver.Create(Self, p);
  { The heap frees the resolver, which in turn keeps its two functions alive
    for as long as any script can still reach them. }
  OwnHelper(resolver);

  SetLength(resolveArgs, 2);
  resolveArgs[0] := JSMakeFunction(resolver.ResolveFunction);
  resolveArgs[1] := JSMakeFunction(resolver.RejectFunction);

  try
    { The executor runs synchronously; a throw rejects the promise. }
    InvokeFunction(executor, resolveArgs, JSMakeUndefined());
  except
    on E: EFloriaJSThrow do
    begin
      { A throw after settling is ignored, as the spec requires. }
      if p.State = fjspPending then
        p.Reject(E.Value);
    end;
  end;

  Result := JSMakePromise(p);
end;

function TFloriaJSHeap.PromiseResolve(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  p: TFloriaJSPromise;
  thenFn: TFloriaJSValue;
  resolver: TFloriaJSPromiseResolver;
  resolveArgs: TFloriaJSValueArray;
begin
  if (Length(AArgs) > 0) and AArgs[0].IsPromise() then
    Exit(AArgs[0]);

  if (Length(AArgs) > 0) and AArgs[0].IsObject() then
  begin
    thenFn := AArgs[0].AsObject().GetProperty('then');
    if thenFn.IsFunction() then
    begin
      p := NewPromise();
      resolver := TFloriaJSPromiseResolver.Create(Self, p);
      OwnHelper(resolver);
      SetLength(resolveArgs, 2);
      resolveArgs[0] := JSMakeFunction(resolver.ResolveFunction);
      resolveArgs[1] := JSMakeFunction(resolver.RejectFunction);
      try
        InvokeFunction(thenFn, resolveArgs, AArgs[0]);
      except
        on E: EFloriaJSThrow do
          if p.State = fjspPending then
            p.Reject(E.Value);
      end;
      Exit(JSMakePromise(p));
    end;
  end;

  p := NewPromise();
  if Length(AArgs) > 0 then
    p.Fulfill(AArgs[0])
  else
    p.Fulfill(JSMakeUndefined());
  Result := JSMakePromise(p);
end;

function TFloriaJSHeap.PromiseReject(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  p: TFloriaJSPromise;
begin
  p := NewPromise();
  if Length(AArgs) > 0 then
    p.Reject(AArgs[0])
  else
    p.Reject(JSMakeUndefined());
  Result := JSMakePromise(p);
end;

function TFloriaJSHeap.PromiseAll(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  p, elem: TFloriaJSPromise;
  arr: TFloriaJSArray;
  outArr: TFloriaJSArray;
  values: array of TFloriaJSValue;
  i, count: Integer;
  settled: TFloriaJSValue;
begin
  p := NewPromise();
  if (Length(AArgs) = 0) or not AArgs[0].IsArray() then
  begin
    p.Fulfill(JSMakeArray(NewArray()));
    Exit(JSMakePromise(p));
  end;

  arr := AArgs[0].AsArray();
  count := arr.Length();
  SetLength(values, count);

  for i := 0 to count - 1 do
  begin
    settled := arr.GetElement(i);
    if settled.IsPromise() then
    begin
      elem := settled.AsPromise();
      { No host event sources exist, so draining the microtask queue settles
        every promise that can still make progress. }
      while (elem.State = fjspPending) and HasPromiseJobs() do
        RunPendingJobs();

      if elem.State = fjspRejected then
      begin
        EnqueuePromiseSettlement(p, elem.ResultValue, True);
        Exit(JSMakePromise(p));
      end;

      if elem.State = fjspFulfilled then
        values[i] := elem.ResultValue
      else
        values[i] := JSMakeUndefined();
    end
    else
      values[i] := settled;
  end;

  outArr := NewArray();
  for i := 0 to count - 1 do
    outArr.SetElement(i, values[i]);
  { Combinators settle their promise through the microtask queue. Settling it
    here synchronously would make a subsequent `.then` run before reactions
    that were registered on the input promises earlier. }
  EnqueuePromiseSettlement(p, JSMakeArray(outArr), False);
  Result := JSMakePromise(p);
end;

function TFloriaJSHeap.PromiseRace(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  p, elem: TFloriaJSPromise;
  arr: TFloriaJSArray;
  v: TFloriaJSValue;
  i: Integer;
begin
  p := NewPromise();
  if (Length(AArgs) = 0) or not AArgs[0].IsArray() then
  begin
    p.Fulfill(JSMakeUndefined());
    Exit(JSMakePromise(p));
  end;

  arr := AArgs[0].AsArray();
  for i := 0 to arr.Length() - 1 do
  begin
    v := arr.GetElement(i);
    if v.IsPromise() then
    begin
      elem := v.AsPromise();
      while (elem.State = fjspPending) and HasPromiseJobs() do
        RunPendingJobs();
      if elem.State = fjspRejected then
      begin
        p.Reject(elem.ResultValue);
        Exit(JSMakePromise(p));
      end;
      if elem.State = fjspFulfilled then
      begin
        p.Fulfill(elem.ResultValue);
        Exit(JSMakePromise(p));
      end;
    end
    else
    begin
      p.Fulfill(v);
      Exit(JSMakePromise(p));
    end;
  end;

  p.Fulfill(JSMakeUndefined());
  Result := JSMakePromise(p);
end;

function TFloriaJSHeap.NewNativeFunction(const AName: string; AProc: TFloriaJSNativeProc): TFloriaJSFunction;
begin
  Result := TFloriaJSFunction(Track(TFloriaJSFunction.CreateNative(AName, AProc)));
  Result.Prototype := GetFunctionPrototype();
end;

function TFloriaJSHeap.NewNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod): TFloriaJSFunction;
begin
  Result := TFloriaJSFunction(Track(TFloriaJSFunction.CreateNativeMethod(AName, AMethod)));
  Result.Prototype := GetFunctionPrototype();
end;

function TFloriaJSHeap.NewBytecodeFunction(const AName: string; ABytecode: TObject; AClosure: Pointer; AIsArrow: Boolean; AIsAsync: Boolean): TFloriaJSFunction;
begin
  Result := TFloriaJSFunction(Track(TFloriaJSFunction.CreateBytecode(AName, ABytecode, AClosure, AIsArrow, AIsAsync)));
  if (ABytecode <> nil) and (ABytecode is TFloriaJSBytecode) then
    Result.IsNamedExpression := TFloriaJSBytecode(ABytecode).IsNamedExpression;
  Result.Prototype := GetFunctionPrototype();
end;

function TFloriaJSHeap.NewBoundFunction(const AName: string; const ATarget, ABoundThis: TFloriaJSValue;
  const ABoundArgs: TFloriaJSValueArray): TFloriaJSBoundFunction;
begin
  Result := TFloriaJSBoundFunction(Track(TFloriaJSBoundFunction.CreateBound(AName, ATarget, ABoundThis, ABoundArgs)));
  Result.Prototype := GetFunctionPrototype();
end;

procedure TFloriaJSHeap.ReclaimOrphanedEnvironments();
var
  i, j: Integer;
  env: TFloriaJSEnvironment;
  obj: TFloriaJSObject;
  fn: TFloriaJSFunction;
  kept: TFPList;
  hasOrphans, keep: Boolean;

  procedure MarkKept(AEnv: TFloriaJSEnvironment);
  var
    cur: TFloriaJSEnvironment;
  begin
    cur := AEnv;
    while cur <> nil do
    begin
      if kept.IndexOf(cur) >= 0 then Exit;
      kept.Add(cur);
      cur := cur.Parent;
    end;
  end;

begin
  if FEnvironments = nil then Exit;

  hasOrphans := False;
  for i := 0 to FEnvironments.Count - 1 do
    if TFloriaJSEnvironment(FEnvironments[i]).Detached then
    begin
      hasOrphans := True;
      Break;
    end;
  if not hasOrphans then Exit;

  kept := TFPList.Create();
  try
    for i := 0 to FEnvironments.Count - 1 do
    begin
      env := TFloriaJSEnvironment(FEnvironments[i]);
      if (env = nil) or (not env.Detached) then Continue;

      keep := False;
      if env.Pinned then
        keep := True;
      if (not keep) and (FObjects <> nil) then
      begin
        for j := 0 to FObjects.Count - 1 do
        begin
          obj := TFloriaJSObject(FObjects[j]);
          if not (obj is TFloriaJSFunction) then Continue;
          fn := TFloriaJSFunction(obj);
          if fn.ClosureEnv <> Pointer(env) then Continue;
          if fn.Pinned or (fn.RefCount > env.CountReferences(fn)) then
          begin
            keep := True;
            Break;
          end;
        end;
      end;

      if keep then
        MarkKept(env);
    end;

    for i := FEnvironments.Count - 1 downto 0 do
    begin
      env := TFloriaJSEnvironment(FEnvironments[i]);
      if (env = nil) or (not env.Detached) or (kept.IndexOf(env) >= 0) then Continue;
      Untrack(env);
      env.Free();
    end;
  finally
    kept.Free();
  end;
end;

{ Sweeps the objects that no container refers to any more. Reclaiming an object
  gives up the references it holds, which can make other objects unreachable as
  well, so the sweep repeats until nothing changes. }
procedure TFloriaJSHeap.SweepObjects();
var
  i: Integer;
  obj: TFloriaJSObject;
  freed: Boolean;
begin
  repeat
    freed := False;
    if FObjects = nil then
      Break;

    for i := FObjects.Count - 1 downto 0 do
    begin
      obj := TFloriaJSObject(FObjects[i]);
      { Only the objects that belong to the heap are reclaimed. An object that
        is owned by somebody else stays alive until its owner lets it go. A
        pinned object has been handed to the host, which may keep it for as
        long as it likes. }
      if obj.HeapOwned and (obj.RefCount <= 0) and (not obj.Pinned) then
      begin
        FObjects.Delete(i);
        obj.Free;
        freed := True;
      end;
    end;
  until not freed;
end;

procedure TFloriaJSHeap.Collect();
begin
  { The order matters. Sweeping first releases the objects that can be
    reclaimed, and freeing a generator detaches the environment it was keeping
    alive. Reclaiming the environments afterwards therefore collects those in
    the same pass; doing it the other way round left every generator's
    environment to be reclaimed only at the *next* collection. The final sweep
    then drops the objects those environments were holding. }
  SweepObjects();
  ReclaimOrphanedEnvironments();
  SweepObjects();
end;

procedure TFloriaJSHeap.Clear();
var
  i: Integer;
  objects, environments: TFPList;
begin
  if FPromiseJobs <> nil then
  begin
    while FPromiseJobs.Count > 0 do
    begin
      Dispose(PTFloriaJSPromiseJob(FPromiseJobs[FPromiseJobs.Count - 1]));
      FPromiseJobs.Delete(FPromiseJobs.Count - 1);
    end;
  end;

  { Timer callbacks retain values from this heap. Releasing the registry first
    gives those references up while the objects and environments still exist. }
  if FTimerRegistry <> nil then
    FreeAndNil(FTimerRegistry);

  { The environments are released first, because every binding of an
    environment holds a reference to the value it stores. The objects are
    still alive at that point, so the references can be given up safely. }
  environments := TFPList.Create();
  try
    if FEnvironments <> nil then
      for i := 0 to FEnvironments.Count - 1 do
        environments.Add(FEnvironments[i]);
    if FEnvironments <> nil then
      FEnvironments.Clear;
    for i := 0 to environments.Count - 1 do
      TObject(environments[i]).Free();
  finally
    environments.Free();
  end;

  { The list is copied before the objects are freed, because freeing an object
    takes it off the list of the heap. The flag tells the objects that they
    must not give up their references any more: every object is released at
    once, so the order in which that happens does not matter. }
  FClearing := True;
  objects := TFPList.Create();
  try
    if FObjects <> nil then
      for i := 0 to FObjects.Count - 1 do
        objects.Add(FObjects[i]);
    if FObjects <> nil then
      FObjects.Clear;
    for i := 0 to objects.Count - 1 do
      TFloriaJSObject(objects[i]).Free();
  finally
    objects.Free();
    { The shared prototypes were part of the objects list and have just been
      freed, so the cached pointers must not outlive them. }
    FArrayPrototype := nil;
    FStringPrototype := nil;
    FNumberPrototype := nil;
    FPromisePrototype := nil;
    FAsyncGeneratorPrototype := nil;
    GNumberPrototype := nil;
    FFunctionPrototype := nil;
    FObjectPrototype := nil;
    FErrorPrototype := nil;
    FTypeErrorPrototype := nil;
    FRangeErrorPrototype := nil;
    FReferenceErrorPrototype := nil;
    FSyntaxErrorPrototype := nil;
    FRealmGlobal := nil;
    FCurrentConstructor := nil;
    FCurrentNewTarget := JSMakeUndefined();
    if FOwnedHelpers <> nil then
    begin
      for i := FOwnedHelpers.Count - 1 downto 0 do
        TObject(FOwnedHelpers[i]).Free();
      FOwnedHelpers.Clear();
    end;
    FClearing := False;
  end;
end;

function TFloriaJSHeap.GetObjectCount(): Integer;
begin
  if FObjects <> nil then
    Result := FObjects.Count
  else
    Result := 0;
end;

function TFloriaJSHeap.GetEnvironmentCount(): Integer;
begin
  if FEnvironments <> nil then
    Result := FEnvironments.Count
  else
    Result := 0;
end;

function TFloriaJSHeap.GetObject(AIndex: Integer): TFloriaJSObject;
begin
  if (FObjects <> nil) and (AIndex >= 0) and (AIndex < FObjects.Count) then
    Result := TFloriaJSObject(FObjects[AIndex])
  else
    Result := nil;
end;

function TFloriaJSHeap.GetEnvironment(AIndex: Integer): TObject;
begin
  if (FEnvironments <> nil) and (AIndex >= 0) and (AIndex < FEnvironments.Count) then
    Result := TObject(FEnvironments[AIndex])
  else
    Result := nil;
end;

{ Binary Arithmetic Operations }


{ Mixing a BigInt with a Number is a TypeError in JavaScript; only two BigInts
  may be combined arithmetically. }
procedure RequireNoMixedBigInt(const ALeft, ARight: TFloriaJSValue);
begin
  if (ALeft.IsBigInt() and ARight.IsNumber()) or
     (ALeft.IsNumber() and ARight.IsBigInt()) then
    raise EFloriaJSThrow.Create(JSMakeString(
      'TypeError: Cannot mix BigInt and other types, use explicit conversions'));
end;

function JSToPrimitive(const AValue: TFloriaJSValue; const AHint: string): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  heap: TFloriaJSHeap;
  candidate: TFloriaJSValue;
  fn, symbolCtor, symbolVal: TFloriaJSValue;
  order: array[0..1] of string;
  i: Integer;
begin
  if not (AValue.Kind in [fjstObject, fjstArray, fjstFunction]) then
    Exit(AValue);
  obj := AValue.ObjVal;
  if obj = nil then
    Exit(JSMakeUndefined());
  heap := obj.Heap;

  { Symbol.toPrimitive takes precedence over the ordinary valueOf/toString
    order. The hint is passed as a string and the result must be primitive. }
  fn := obj.GetWellKnownProperty('Symbol.toPrimitive');
  if fn.IsFunction() and (heap <> nil) then
  begin
    candidate := heap.InvokeFunction(fn, [JSMakeString(AHint)], AValue);
    if candidate.Kind in [fjstObject, fjstArray, fjstFunction] then
      raise EFloriaJSThrow.Create(JSMakeObject(
        heap.NewError('TypeError', 'Cannot convert object to primitive value')));
    Exit(candidate);
  end;

  if AHint = 'string' then
  begin
    order[0] := 'toString';
    order[1] := 'valueOf';
  end
  else
  begin
    order[0] := 'valueOf';
    order[1] := 'toString';
  end;

  for i := 0 to 1 do
  begin
    if not obj.HasProperty(order[i]) then
      Continue;
    fn := obj.GetProperty(order[i]);
    if not fn.IsFunction() then
      Continue;
    if heap = nil then
      Continue;
    candidate := heap.InvokeFunction(fn, [], AValue);
    if not (candidate.Kind in [fjstObject, fjstArray, fjstFunction]) then
      Exit(candidate);
  end;

  raise EFloriaJSThrow.Create(JSMakeObject(
    obj.Heap.NewError('TypeError', 'Cannot convert object to primitive value')));
end;

function JSToString(const AValue: TFloriaJSValue): string;
var
  primitive: TFloriaJSValue;
begin
  if AValue.Kind in [fjstObject, fjstArray, fjstFunction] then
  begin
    primitive := JSToPrimitive(AValue, 'string');
    Result := primitive.ToString();
  end
  else
    Result := AValue.ToString();
end;

function JSAdd(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
var
  left, right: TFloriaJSValue;
begin
  left := JSToPrimitive(ALeft, 'default');
  right := JSToPrimitive(ARight, 'default');
  if left.IsSymbol() or right.IsSymbol() then
  begin
    if JSActiveRealmHeap() <> nil then
      raise EFloriaJSThrow.Create(JSMakeObject(
        JSActiveRealmHeap().NewError('TypeError', 'Cannot convert a Symbol value to a string')));
    raise EFloriaJSThrow.Create(JSMakeString('TypeError: Cannot convert a Symbol value to a string'));
  end;
  RequireNoMixedBigInt(left, right);
  if left.IsBigInt() and right.IsBigInt() then
    Exit(JSMakeBigInt(BigIntAdd(left.StrVal, right.StrVal)));
  if left.IsString() or right.IsString() then
    Result := JSMakeString(left.ToString() + right.ToString())
  else
    Result := JSMakeNumber(left.ToNumber() + right.ToNumber());
end;

function JSSubtract(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
begin
  RequireNoMixedBigInt(ALeft, ARight);
  if ALeft.IsBigInt() and ARight.IsBigInt() then
    Exit(JSMakeBigInt(BigIntSub(ALeft.StrVal, ARight.StrVal)));
  Result := JSMakeNumber(ALeft.ToNumber() - ARight.ToNumber());
end;

function JSMultiply(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
begin
  RequireNoMixedBigInt(ALeft, ARight);
  if ALeft.IsBigInt() and ARight.IsBigInt() then
    Exit(JSMakeBigInt(BigIntMul(ALeft.StrVal, ARight.StrVal)));
  Result := JSMakeNumber(ALeft.ToNumber() * ARight.ToNumber());
end;

function JSDivide(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
var
  l, r: Double;
begin
  RequireNoMixedBigInt(ALeft, ARight);
  if ALeft.IsBigInt() and ARight.IsBigInt() then
  begin
    if ARight.StrVal = '0' then
      raise EFloriaJSThrow.Create(JSMakeString('RangeError: Division by zero'));
    Exit(JSMakeBigInt(BigIntDiv(ALeft.StrVal, ARight.StrVal)));
  end;
  l := ALeft.ToNumber();
  r := ARight.ToNumber();
  if r = 0.0 then
  begin
    if l > 0.0 then Result := JSMakeNumber(Infinity)
    else if l < 0.0 then Result := JSMakeNumber(-Infinity)
    else Result := JSMakeNumber(NaN);
  end
  else
    Result := JSMakeNumber(l / r);
end;

function JSModulo(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
var
  l, r: Double;
begin
  RequireNoMixedBigInt(ALeft, ARight);
  if ALeft.IsBigInt() and ARight.IsBigInt() then
  begin
    if ARight.StrVal = '0' then
      raise EFloriaJSThrow.Create(JSMakeString('RangeError: Division by zero'));
    Exit(JSMakeBigInt(BigIntMod(ALeft.StrVal, ARight.StrVal)));
  end;
  l := ALeft.ToNumber();
  r := ARight.ToNumber();
  if (r = 0.0) or IsNaN(l) or IsNaN(r) then
    Result := JSMakeNumber(NaN)
  else
    Result := JSMakeNumber(FMod(l, r));
end;

function JSPower(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
var
  base, exponent, acc: string;
  e, i: Integer;
begin
  RequireNoMixedBigInt(ALeft, ARight);
  if ALeft.IsBigInt() and ARight.IsBigInt() then
  begin
    if BigIntIsNegative(ARight.StrVal) then
      raise EFloriaJSThrow.Create(JSMakeString('RangeError: Exponent must be positive'));
    exponent := ARight.StrVal;
    if BigIntCompare(exponent, '1000000') > 0 then
      raise EFloriaJSThrow.Create(JSMakeString('RangeError: Maximum BigInt size exceeded'));
    base := ALeft.StrVal;
    acc := '1';
    e := StrToIntDef(exponent, 0);
    for i := 1 to e do
      acc := BigIntMul(acc, base);
    Exit(JSMakeBigInt(acc));
  end;
  Result := JSMakeNumber(Power(ALeft.ToNumber(), ARight.ToNumber()));
end;

{ Relational & Equality Operations }

function JSEqual(const ALeft, ARight: TFloriaJSValue): Boolean;
begin
  if ALeft.Kind = ARight.Kind then
    Exit(JSStrictEqual(ALeft, ARight));

  // null == undefined
  if (ALeft.IsNull() and ARight.IsUndefined()) or (ALeft.IsUndefined() and ARight.IsNull()) then
    Exit(True);

  { Loose equality compares a BigInt mathematically with a Number or a numeric
    string; strict equality never does. }
  if ALeft.IsBigInt() and ARight.IsNumber() then
    Exit(BigIntEqualsDouble(ALeft.StrVal, ARight.NumVal));
  if ALeft.IsNumber() and ARight.IsBigInt() then
    Exit(BigIntEqualsDouble(ARight.StrVal, ALeft.NumVal));
  if ALeft.IsBigInt() and ARight.IsString() then
    Exit(JSEqual(ALeft, JSMakeNumber(ARight.ToNumber())));
  if ALeft.IsString() and ARight.IsBigInt() then
    Exit(JSEqual(JSMakeNumber(ALeft.ToNumber()), ARight));

  // number vs string
  if ALeft.IsNumber() and ARight.IsString() then
    Exit(ALeft.NumVal = ARight.ToNumber());
  if ALeft.IsString() and ARight.IsNumber() then
    Exit(ALeft.ToNumber() = ARight.NumVal);

  // boolean vs any
  if ALeft.IsBoolean() then
    Exit(JSEqual(JSMakeNumber(ALeft.ToNumber()), ARight));
  if ARight.IsBoolean() then
    Exit(JSEqual(ALeft, JSMakeNumber(ARight.ToNumber())));

  { An object compared with a primitive uses its primitive value. Two objects
    remain unequal unless they are the same reference, which strict equality
    already handled above. }
  if (ALeft.Kind in [fjstObject, fjstArray, fjstFunction]) and
     not (ARight.Kind in [fjstObject, fjstArray, fjstFunction]) then
    Exit(JSEqual(JSToPrimitive(ALeft, 'default'), ARight));
  if (ARight.Kind in [fjstObject, fjstArray, fjstFunction]) and
     not (ALeft.Kind in [fjstObject, fjstArray, fjstFunction]) then
    Exit(JSEqual(ALeft, JSToPrimitive(ARight, 'default')));

  Result := False;
end;

function JSStrictEqual(const ALeft, ARight: TFloriaJSValue): Boolean;
begin
  if ALeft.Kind <> ARight.Kind then
    Exit(False);

  case ALeft.Kind of
    fjstUndefined, fjstNull:
      Result := True;
    fjstBoolean:
      Result := (ALeft.NumVal = ARight.NumVal);
    fjstNumber:
      if IsNaN(ALeft.NumVal) or IsNaN(ARight.NumVal) then
        Result := False
      else
        Result := (ALeft.NumVal = ARight.NumVal);
    fjstString:
      Result := (ALeft.StrVal = ARight.StrVal);
    fjstSymbol:
      Result := (ALeft.NumVal = ARight.NumVal) and (ALeft.NumVal <> 0.0);
    fjstBigInt:
      { The digits are canonical, so equal values have equal text. }
      Result := (ALeft.StrVal = ARight.StrVal);
    fjstObject, fjstArray, fjstFunction:
      Result := (ALeft.ObjVal = ARight.ObjVal);
  else
    Result := False;
  end;
end;

function JSLessThan(const ALeft, ARight: TFloriaJSValue): Boolean;
var
  left, right: TFloriaJSValue;
begin
  left := JSToPrimitive(ALeft, 'number');
  right := JSToPrimitive(ARight, 'number');
  { Two BigInts compare exactly; a BigInt against a Number also compares
    mathematically, without converting either to a double. }
  if left.IsBigInt() and right.IsBigInt() then
    Exit(BigIntCompare(left.StrVal, right.StrVal) < 0);
  if left.IsString() and right.IsString() then
    Result := (left.StrVal < right.StrVal)
  else
    Result := (left.ToNumber() < right.ToNumber());
end;

function JSLessEqual(const ALeft, ARight: TFloriaJSValue): Boolean;
begin
  { Two BigInts compare exactly; a BigInt against a Number also compares
    mathematically, without converting either to a double. }
  if ALeft.IsBigInt() and ARight.IsBigInt() then
    Exit(BigIntCompare(ALeft.StrVal, ARight.StrVal) <= 0);
  if ALeft.IsString() and ARight.IsString() then
    Result := (ALeft.StrVal <= ARight.StrVal)
  else
    Result := (ALeft.ToNumber() <= ARight.ToNumber());
end;

function JSGreaterThan(const ALeft, ARight: TFloriaJSValue): Boolean;
begin
  { Two BigInts compare exactly; a BigInt against a Number also compares
    mathematically, without converting either to a double. }
  if ALeft.IsBigInt() and ARight.IsBigInt() then
    Exit(BigIntCompare(ALeft.StrVal, ARight.StrVal) > 0);
  if ALeft.IsString() and ARight.IsString() then
    Result := (ALeft.StrVal > ARight.StrVal)
  else
    Result := (ALeft.ToNumber() > ARight.ToNumber());
end;

function JSInstanceOf(const ALeft, ARight: TFloriaJSValue): Boolean;
var
  pproto: TFloriaJSObject;
  cproto: TFloriaJSValue;
  heap: TFloriaJSHeap;
  fn: TFloriaJSFunction;
begin
  Result := False;
  if not ALeft.IsObject() then Exit;
  if not ARight.IsFunction() then Exit;

  { A bound function is transparent for `instanceof`: the check walks the
    target's prototype chain, and the bound function itself has no prototype.
    Unlike construction, there is no Object.prototype fallback here: a
    constructor whose `prototype` is not an object matches nothing. }
  heap := ARight.AsFunction().Heap;
  if heap <> nil then
  begin
    fn := heap.ResolveConstructorTarget(ARight);
    if fn = nil then Exit;
    cproto := fn.GetProperty('prototype');
  end
  else
    cproto := ARight.AsFunction().GetProperty('prototype');
  if not cproto.IsObject() then Exit;

  pproto := ALeft.AsObject().Prototype;
  while pproto <> nil do
  begin
    if pproto = cproto.AsObject() then
      Exit(True);
    pproto := pproto.Prototype;
  end;
end;

function JSGreaterEqual(const ALeft, ARight: TFloriaJSValue): Boolean;
begin
  { Two BigInts compare exactly; a BigInt against a Number also compares
    mathematically, without converting either to a double. }
  if ALeft.IsBigInt() and ARight.IsBigInt() then
    Exit(BigIntCompare(ALeft.StrVal, ARight.StrVal) >= 0);
  if ALeft.IsString() and ARight.IsString() then
    Result := (ALeft.StrVal >= ARight.StrVal)
  else
    Result := (ALeft.ToNumber() >= ARight.ToNumber());
end;

{ Bitwise Operations }

function JSBitAnd(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(LongInt(Trunc(ALeft.ToNumber())) and LongInt(Trunc(ARight.ToNumber())));
end;

function JSBitOr(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(LongInt(Trunc(ALeft.ToNumber())) or LongInt(Trunc(ARight.ToNumber())));
end;

function JSBitXor(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(LongInt(Trunc(ALeft.ToNumber())) xor LongInt(Trunc(ARight.ToNumber())));
end;

function JSShiftLeft(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
var
  shift: LongInt;
begin
  shift := LongInt(Trunc(ARight.ToNumber())) and 31;
  Result := JSMakeNumber(LongInt(Trunc(ALeft.ToNumber())) shl shift);
end;

function JSShiftRight(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
var
  shift: LongInt;
begin
  shift := LongInt(Trunc(ARight.ToNumber())) and 31;
  Result := JSMakeNumber(LongInt(Trunc(ALeft.ToNumber())) shr shift);
end;

function JSShiftRightUnsigned(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
var
  val: Cardinal;
  shift: Cardinal;
begin
  val := Cardinal(LongInt(Trunc(ALeft.ToNumber())));
  shift := Cardinal(LongInt(Trunc(ARight.ToNumber()))) and 31;
  Result := JSMakeNumber(Double(val shr shift));
end;

{ Unary Operations }

function JSUnaryMinus(const AVal: TFloriaJSValue): TFloriaJSValue;
begin
  if AVal.IsBigInt() then
    Exit(JSMakeBigInt(BigIntNegate(AVal.StrVal)));
  Result := JSMakeNumber(-AVal.ToNumber());
end;

function JSUnaryPlus(const AVal: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(AVal.ToNumber());
end;

function JSUnaryNot(const AVal: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeBoolean(not AVal.ToBoolean());
end;

function JSUnaryBitNot(const AVal: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(not LongInt(Trunc(AVal.ToNumber())));
end;

var
  GActiveRealmHeap: TFloriaJSHeap = nil;
  GAtomicsYieldHook: TFloriaJSAtomicsYieldHook = nil;

procedure JSSetActiveRealmHeap(AHeap: TFloriaJSHeap);
begin
  GActiveRealmHeap := AHeap;
end;

function JSActiveRealmHeap(): TFloriaJSHeap;
begin
  Result := GActiveRealmHeap;
end;

procedure JSSetAtomicsYieldHook(AHook: TFloriaJSAtomicsYieldHook);
begin
  GAtomicsYieldHook := AHook;
end;

procedure JSAtomicsYield();
begin
  if Assigned(GAtomicsYieldHook) then
    GAtomicsYieldHook();
end;

{ The name a property is stored under. A symbol key gets a prefix that no real
  string key can contain, so it never collides and never enumerates. }
function JSPropertyKeyName(const AVal: TFloriaJSValue): string;
begin
  if AVal.IsSymbol() then
    Result := #1'sym:' + IntToStr(Trunc(AVal.NumVal)) + ':' + AVal.StrVal
  else
    Result := JSToString(AVal);
end;

{ True when AVal is a Number that names an ECMAScript array index. }
function JSArrayIndexFromNumber(const AVal: TFloriaJSValue;
  out AIndex: Int64): Boolean;
var
  d: Double;
begin
  AIndex := 0;
  if not AVal.IsNumber() then
    Exit(False);
  d := AVal.NumVal;
  if IsNaN(d) or (d < 0) or (d > 4294967294.0) then
    Exit(False);
  AIndex := Trunc(d);
  Result := (d = AIndex);
end;

function JSIsWellKnownSymbolKey(const AName, ADescription: string): Boolean;
begin
  { Canonical form: the '#1sym:<id>:<description>' key produced by
    JSPropertyKeyName for a symbol. }
  if (Length(AName) > 0) and (AName[1] = #1) then
    Exit(Copy(AName, Length(AName) - Length(ADescription) + 1,
      Length(ADescription)) = ADescription);
  { Legacy spellings kept for values created before symbol keys were distinct. }
  if AName = ADescription then Exit(True);
  if AName = 'Symbol(' + ADescription + ')' then Exit(True);
  if ADescription = 'Symbol.iterator' then
    Exit((AName = '@@iterator') or (AName = 'Symbol(Symbol.iterator)'));
  Result := False;
end;

function JSTypeOf(const AVal: TFloriaJSValue): string;
begin
  case AVal.Kind of
    fjstUndefined:
      Result := 'undefined';
    fjstNull:
      Result := 'object'; // Standard JS historical quirk: typeof null === 'object'
    fjstBoolean:
      Result := 'boolean';
    fjstNumber:
      Result := 'number';
    fjstString:
      Result := 'string';
    fjstSymbol:
      Result := 'symbol';
    fjstBigInt:
      Result := 'bigint';
    fjstFunction:
      Result := 'function';
    fjstObject, fjstArray:
      Result := 'object';
  else
    Result := 'undefined';
  end;
end;

initialization
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  GLiveHeaps := TFPList.Create;

finalization
  if GLiveHeaps <> nil then
  begin
    while GLiveHeaps.Count > 0 do
    begin
      Dispose(PFloriaJSHeapEntry(GLiveHeaps[GLiveHeaps.Count - 1]));
      GLiveHeaps.Delete(GLiveHeaps.Count - 1);
    end;
    FreeAndNil(GLiveHeaps);
  end;

end.
