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
  Classes, SysUtils, Math, floria.js.types, floria.js.ast;

type
  { Forward Declarations }
  TFloriaJSObject = class;
  TFloriaJSArray = class;
  TFloriaJSFunction = class;
  TFloriaJSHeap = class;
  TFloriaJSPromise = class;

  { Promise Settlement State }
  TFloriaJSPromiseState = (fjspPending, fjspFulfilled, fjspRejected);

  { Dynamic JavaScript Runtime Value }
  TFloriaJSValue = record
    Kind: TFloriaJSType;
    NumVal: Double;
    BoolVal: Boolean;
    StrVal: string;
    ObjVal: TFloriaJSObject;

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
    function IsTruthy(): Boolean;

    function ToBoolean(): Boolean;
    function ToNumber(): Double;
    function ToString(): string;

    function AsObject(): TFloriaJSObject;
    function AsArray(): TFloriaJSArray;
    function AsFunction(): TFloriaJSFunction;
    function AsPromise(): TFloriaJSPromise;
  end;

  { Callback Used by Heap-Side Built-ins to Invoke a JavaScript Function.
    The evaluator installs it, so native methods such as Array.map can call
    back into user code without depending on the evaluator unit. }
  TFloriaJSFunctionInvoker = function(const AFuncVal: TFloriaJSValue;
    const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue of object;

  { Property Key-Value Entry }
  TFloriaJSPropertyPair = record
    Key: string;
    Value: TFloriaJSValue;
    Getter: TFloriaJSValue;
    Setter: TFloriaJSValue;
    HasGetter: Boolean;
    HasSetter: Boolean;
  end;

  { Heap-allocated Base JavaScript Object }
  TFloriaJSObject = class
  private
    FPrototype: TFloriaJSObject;
    FProperties: array of TFloriaJSPropertyPair;
    FPropCount: Integer;
    FRefCount: Integer;
    FHeap: TFloriaJSHeap;
    FHeapOwned: Boolean;
    FPinned: Boolean;
    function FindPropertyIndex(const AName: string): Integer;
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
    procedure DefineGetter(const AName: string; const AGetter: TFloriaJSValue);
    procedure DefineSetter(const AName: string; const ASetter: TFloriaJSValue);
    function  HasProperty(const AName: string): Boolean; virtual;
    function  DeleteProperty(const AName: string): Boolean; virtual;

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
  end;

  { Heap-allocated JavaScript Array }
  TFloriaJSArray = class(TFloriaJSObject)
  private
    FElements: array of TFloriaJSValue;
    FCount: Integer;
    procedure GrowCapacity(AMinCapacity: Integer);
  public
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
    function  GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); override;
    function  HasProperty(const AName: string): Boolean; override;
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
    FParamNames: TStringList;
    FBody: TFloriaJSStmtNode;
    FBytecode: TObject;
    FClosureEnv: Pointer; // Lexical environment TFloriaJSEnvironment
    FIsAsync: Boolean;
    FIsArrow: Boolean;
  public
    constructor CreateNative(const AName: string; AProc: TFloriaJSNativeProc);
    constructor CreateNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod);
    constructor CreateUser(const AName: string; AParams: TStrings; ABody: TFloriaJSStmtNode; AClosure: Pointer; AOwnsBody: Boolean = False; AIsAsync: Boolean = False; AIsArrow: Boolean = False);
    constructor CreateBytecode(const AName: string; ABytecode: TObject; AClosure: Pointer; AIsArrow: Boolean = False; AIsAsync: Boolean = False);
    destructor Destroy(); override;

    function GetProperty(const AName: string): TFloriaJSValue; override;
    function GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue; override;

    property Name: string read FName write FName;
    property IsNative: Boolean read FIsNative;
    property IsAsync: Boolean read FIsAsync;
    property IsArrow: Boolean read FIsArrow write FIsArrow;
    property NativeProc: TFloriaJSNativeProc read FNativeProc;
    property NativeMethod: TFloriaJSNativeMethod read FNativeMethod;
    property ParamNames: TStringList read FParamNames;
    property Body: TFloriaJSStmtNode read FBody;
    property Bytecode: TObject read FBytecode write FBytecode;
    property ClosureEnv: Pointer read FClosureEnv;
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

  { Deferred Microtask that Runs One Promise Reaction }
  TFloriaJSPromiseJob = record
    OnFulfilled: TFloriaJSValue;
    OnRejected: TFloriaJSValue;
    OnFinally: TFloriaJSValue;
    IsFinally: Boolean;
    IsRejection: Boolean;
    Value: TFloriaJSValue;
    Child: TFloriaJSPromise;
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
    procedure Attach(const AOnFulfilled, AOnRejected, AOnFinally: TFloriaJSValue; AIsFinally: Boolean; AChild: TFloriaJSPromise);
  public
    constructor Create(AHeap: TFloriaJSHeap);
    destructor Destroy(); override;

    function  GetProperty(const AName: string): TFloriaJSValue; override;
    function  GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    function  HasProperty(const AName: string): Boolean; override;

    procedure Fulfill(const AValue: TFloriaJSValue);
    procedure Reject(const AValue: TFloriaJSValue);
    function  Chain(const AOnFulfilled, AOnRejected: TFloriaJSValue): TFloriaJSPromise;
    function  ChainFinally(const AOnFinally: TFloriaJSValue): TFloriaJSPromise;

    property State: TFloriaJSPromiseState read FState;
    property ResultValue: TFloriaJSValue read FResult;
  end;

  { Callback Used by the Evaluator to Execute Deferred Promise Jobs }
  TFloriaJSJobRunner = procedure(const AJob: TFloriaJSPromiseJob) of object;

  { Heap Allocator & Lifetime Tracker }
  TFloriaJSHeap = class
  private
    FObjects: TFPList;
    FEnvironments: TFPList;
    FPromiseJobs: TFPList;
    FJobRunner: TFloriaJSJobRunner;
    FInvoker: TFloriaJSFunctionInvoker;
    FArrayPrototype: TFloriaJSObject;
    FStringPrototype: TFloriaJSObject;
    FObjectPrototype: TFloriaJSObject;
    FErrorPrototype: TFloriaJSObject;
    FTypeErrorPrototype: TFloriaJSObject;
    FRangeErrorPrototype: TFloriaJSObject;
    FReferenceErrorPrototype: TFloriaJSObject;
    FSyntaxErrorPrototype: TFloriaJSObject;
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
    function  NewError(const AName, AMessage: string): TFloriaJSError;
    function  NewPromise(): TFloriaJSPromise;
    function  NewNativeFunction(const AName: string; AProc: TFloriaJSNativeProc): TFloriaJSFunction;
    function  NewNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod): TFloriaJSFunction;
    function  NewUserFunction(const AName: string; AParams: TStrings; ABody: TFloriaJSStmtNode; AClosure: Pointer; AOwnsBody: Boolean = False; AIsAsync: Boolean = False; AIsArrow: Boolean = False): TFloriaJSFunction;
    function  NewBytecodeFunction(const AName: string; ABytecode: TObject; AClosure: Pointer; AIsArrow: Boolean = False; AIsAsync: Boolean = False): TFloriaJSFunction;

    { The shared prototypes are created on first use and pinned, so they stay
      alive for as long as the heap does even when no value refers to them. }
    function  GetArrayPrototype(): TFloriaJSObject;
    function  GetStringPrototype(): TFloriaJSObject;
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

    procedure SetJobRunner(ARunner: TFloriaJSJobRunner);
    procedure EnqueuePromiseJob(const AJob: TFloriaJSPromiseJob);
    function  DequeuePromiseJob(out AJob: TFloriaJSPromiseJob): Boolean;
    function  HasPromiseJobs(): Boolean;
    procedure RunPendingJobs();

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
function JSMakeArray(AArr: TFloriaJSArray): TFloriaJSValue;
function JSMakeFunction(AFunc: TFloriaJSFunction): TFloriaJSValue;
function JSMakePromise(APromise: TFloriaJSPromise): TFloriaJSValue;
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
  Result.BoolVal := False;
  Result.StrVal := '';
  Result.ObjVal := nil;
end;

function JSMakeNull(): TFloriaJSValue;
begin
  Result.Kind := fjstNull;
  Result.NumVal := 0.0;
  Result.BoolVal := False;
  Result.StrVal := '';
  Result.ObjVal := nil;
end;

function JSMakeBoolean(ABool: Boolean): TFloriaJSValue;
begin
  Result.Kind := fjstBoolean;
  Result.NumVal := 0.0;
  Result.BoolVal := ABool;
  Result.StrVal := '';
  Result.ObjVal := nil;
end;

function JSMakeNumber(ANum: Double): TFloriaJSValue;
begin
  Result.Kind := fjstNumber;
  Result.NumVal := ANum;
  if IsNaN(ANum) then
    Result.BoolVal := False
  else
    Result.BoolVal := (ANum <> 0.0);
  Result.StrVal := '';
  Result.ObjVal := nil;
end;

function JSMakeString(const AStr: string): TFloriaJSValue;
begin
  Result.Kind := fjstString;
  Result.NumVal := 0.0;
  Result.BoolVal := (AStr <> '');
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
  Result.BoolVal := (AObj <> nil);
  Result.StrVal := '';
  Result.ObjVal := AObj;
end;

function JSMakeArray(AArr: TFloriaJSArray): TFloriaJSValue;
begin
  Result.Kind := fjstArray;
  Result.NumVal := 0.0;
  Result.BoolVal := (AArr <> nil);
  Result.StrVal := '';
  Result.ObjVal := AArr;
end;

function JSMakeFunction(AFunc: TFloriaJSFunction): TFloriaJSValue;
begin
  Result.Kind := fjstFunction;
  Result.NumVal := 0.0;
  Result.BoolVal := (AFunc <> nil);
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
  Result.BoolVal := (APromise <> nil);
  Result.StrVal := '';
  Result.ObjVal := APromise;
end;

function JSMakeSymbol(const ADescription: string = ''; AId: Integer = 0): TFloriaJSValue;
begin
  Result.Kind := fjstSymbol;
  Result.NumVal := AId;
  Result.BoolVal := True;
  Result.StrVal := ADescription;
  Result.ObjVal := nil;
end;

{ TFloriaJSValue Methods }

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
      Result := BoolVal;
    fjstNumber:
      Result := (NumVal <> 0.0) and not IsNaN(NumVal);
    fjstString:
      Result := (StrVal <> '');
    fjstSymbol:
      Result := True;
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
begin
  case Kind of
    fjstUndefined:
      Result := NaN;
    fjstNull:
      Result := 0.0;
    fjstBoolean:
      if BoolVal then Result := 1.0 else Result := 0.0;
    fjstNumber:
      Result := NumVal;
    fjstString:
    begin
      if Trim(StrVal) = '' then
        Exit(0.0);
      Val(StrVal, d, code);
      if code = 0 then
        Result := d
      else
        Result := NaN;
    end;
    fjstArray:
    begin
      if (ObjVal <> nil) and (TFloriaJSArray(ObjVal).Length() = 1) then
        Result := TFloriaJSArray(ObjVal).GetElement(0).ToNumber()
      else
        Result := NaN;
    end;
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
      if BoolVal then Result := 'true' else Result := 'false';
    fjstNumber:
      if IsNaN(NumVal) then
        Result := 'NaN'
      else if IsInfinite(NumVal) then
      begin
        if NumVal > 0 then Result := 'Infinity' else Result := '-Infinity';
      end
      else if Frac(NumVal) = 0.0 then
        Result := IntToStr(Round(NumVal))
      else
        Result := FloatToStr(NumVal);
    fjstString:
      Result := StrVal;
    fjstSymbol:
      if StrVal <> '' then
        Result := 'Symbol(' + StrVal + ')'
      else
        Result := 'Symbol()';
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

function TFloriaJSObject.GetProperty(const AName: string): TFloriaJSValue;
begin
  Result := GetPropertyWithReceiver(AName, Self);
end;

procedure TFloriaJSObject.SetProperty(const AName: string; const AValue: TFloriaJSValue);
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
  begin
    if FProperties[idx].HasSetter and (FHeap <> nil) then
    begin
      FHeap.InvokeFunction(FProperties[idx].Setter, [AValue], JSMakeObject(Self));
      Exit;
    end;
    { A property owns the value it stores: the value that is replaced gives up
      its reference and the new value takes a reference over. }
    JSReleaseValue(FProperties[idx].Value);
    FProperties[idx].Value := AValue;
    JSRetainValue(AValue);
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
  FProperties[FPropCount].Value := AValue;
  FProperties[FPropCount].Getter := JSMakeUndefined();
  FProperties[FPropCount].Setter := JSMakeUndefined();
  FProperties[FPropCount].HasGetter := False;
  FProperties[FPropCount].HasSetter := False;
  JSRetainValue(AValue);
  Inc(FPropCount);
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

  for i := idx to FPropCount - 2 do
    FProperties[i] := FProperties[i + 1];

  Dec(FPropCount);
  { The removed value gives up the reference that the property held for it. }
  JSReleaseValue(FProperties[FPropCount].Value);
  FProperties[FPropCount].Value := JSMakeUndefined();
  Result := True;
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

{ TFloriaJSArray }

constructor TFloriaJSArray.Create();
begin
  inherited Create(nil);
  SetLength(FElements, 0);
  FCount := 0;
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
  FCount := 0;
  inherited Destroy();
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
end;

function TFloriaJSArray.GetElement(AIndex: Integer): TFloriaJSValue;
begin
  if (AIndex >= 0) and (AIndex < FCount) then
    Result := FElements[AIndex]
  else
    Result := JSMakeUndefined();
end;

procedure TFloriaJSArray.SetElement(AIndex: Integer; const AValue: TFloriaJSValue);
var
  i: Integer;
begin
  if AIndex < 0 then Exit;

  if AIndex >= FCount then
  begin
    GrowCapacity(AIndex + 1);
    for i := FCount to AIndex - 1 do
      FElements[i] := JSMakeUndefined();
    FCount := AIndex + 1;
  end
  else
  begin
    { The element that is replaced gives up the reference it held. }
    JSReleaseValue(FElements[AIndex]);
  end;

  FElements[AIndex] := AValue;
  JSRetainValue(AValue);
end;

procedure TFloriaJSArray.Push(const AValue: TFloriaJSValue);
begin
  GrowCapacity(FCount + 1);
  FElements[FCount] := AValue;
  JSRetainValue(AValue);
  Inc(FCount);
end;

function TFloriaJSArray.Pop(): TFloriaJSValue;
begin
  if FCount = 0 then
    Exit(JSMakeUndefined());

  Dec(FCount);
  Result := FElements[FCount];
  FElements[FCount] := JSMakeUndefined();
  { The element that is removed gives up the reference it held. }
  JSReleaseValue(Result);
end;

function TFloriaJSArray.Shift(): TFloriaJSValue;
var
  i: Integer;
begin
  if FCount = 0 then
    Exit(JSMakeUndefined());

  Result := FElements[0];
  for i := 0 to FCount - 2 do
    FElements[i] := FElements[i + 1];

  Dec(FCount);
  { The element that is shifted out gives up the reference it held. }
  JSReleaseValue(FElements[FCount]);
  FElements[FCount] := JSMakeUndefined();
end;

procedure TFloriaJSArray.Unshift(const AValue: TFloriaJSValue);
var
  i: Integer;
begin
  GrowCapacity(FCount + 1);
  for i := FCount downto 1 do
    FElements[i] := FElements[i - 1];

  FElements[0] := AValue;
  JSRetainValue(AValue);
  Inc(FCount);
end;

procedure TFloriaJSArray.InsertAt(AIndex: Integer; const AValue: TFloriaJSValue);
var
  i: Integer;
begin
  if AIndex < 0 then AIndex := 0;
  if AIndex > FCount then AIndex := FCount;

  GrowCapacity(FCount + 1);
  for i := FCount downto AIndex + 1 do
    FElements[i] := FElements[i - 1];

  FElements[AIndex] := AValue;
  JSRetainValue(AValue);
  Inc(FCount);
end;

procedure TFloriaJSArray.RemoveAt(AIndex: Integer);
var
  i: Integer;
begin
  if (AIndex < 0) or (AIndex >= FCount) then Exit;

  { The element that is removed gives up the reference it held. }
  JSReleaseValue(FElements[AIndex]);
  for i := AIndex to FCount - 2 do
    FElements[i] := FElements[i + 1];

  Dec(FCount);
  FElements[FCount] := JSMakeUndefined();
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
      if not (FElements[i].IsUndefined() or FElements[i].IsNull()) then
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

function TFloriaJSArray.GetProperty(const AName: string): TFloriaJSValue;
begin
  Result := GetPropertyWithReceiver(AName, Self);
end;

function TFloriaJSArray.GetPropertyWithReceiver(const AName: string; AReceiver: TFloriaJSObject): TFloriaJSValue;
var
  idx: Integer;
begin
  if AName = 'length' then
    Exit(JSMakeNumber(FCount));

  if TryStrToInt(AName, idx) then
    Exit(GetElement(idx));

  Result := inherited GetPropertyWithReceiver(AName, AReceiver);
end;

procedure TFloriaJSArray.SetProperty(const AName: string; const AValue: TFloriaJSValue);
var
  idx: Integer;
begin
  if AName = 'length' then
  begin
    idx := Trunc(AValue.ToNumber());
    if idx >= 0 then
    begin
      if idx < FCount then
      begin
        { The elements that are dropped give up the references they held. }
        while FCount > idx do
        begin
          Dec(FCount);
          JSReleaseValue(FElements[FCount]);
          FElements[FCount] := JSMakeUndefined();
        end;
      end
      else
        GrowCapacity(idx);
    end;
    Exit;
  end;

  if TryStrToInt(AName, idx) then
  begin
    SetElement(idx, AValue);
    Exit;
  end;

  inherited SetProperty(AName, AValue);
end;

function TFloriaJSArray.HasProperty(const AName: string): Boolean;
var
  idx: Integer;
begin
  if AName = 'length' then Exit(True);
  if TryStrToInt(AName, idx) then
    Exit((idx >= 0) and (idx < FCount));

  Result := inherited HasProperty(AName);
end;

{ TFloriaJSFunction }

constructor TFloriaJSFunction.CreateNative(const AName: string; AProc: TFloriaJSNativeProc);
begin
  inherited Create(nil);
  FName := AName;
  FIsNative := True;
  FNativeProc := AProc;
  FNativeMethod := nil;
  FParamNames := TStringList.Create();
  FBody := nil;
  FClosureEnv := nil;
  FIsAsync := False;
  FIsArrow := False;
end;

constructor TFloriaJSFunction.CreateNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod);
begin
  inherited Create(nil);
  FName := AName;
  FIsNative := True;
  FNativeProc := nil;
  FNativeMethod := AMethod;
  FParamNames := TStringList.Create();
  FBody := nil;
  FClosureEnv := nil;
  FIsAsync := False;
  FIsArrow := False;
end;

constructor TFloriaJSFunction.CreateUser(const AName: string; AParams: TStrings; ABody: TFloriaJSStmtNode; AClosure: Pointer; AOwnsBody: Boolean; AIsAsync: Boolean; AIsArrow: Boolean);
var
  i: Integer;
begin
  inherited Create(nil);
  FName := AName;
  FIsNative := False;
  FNativeProc := nil;
  FNativeMethod := nil;
  FParamNames := TStringList.Create();
  if AParams <> nil then
  begin
    FParamNames.Assign(AParams);
    for i := 0 to FParamNames.Count - 1 do
      if FParamNames.Objects[i] <> nil then
        TFloriaJSASTNode(FParamNames.Objects[i]).Retain();
  end;
  FBody := ABody;
  FClosureEnv := AClosure;
  FIsAsync := AIsAsync;
  FIsArrow := AIsArrow;
  { The body points into the AST that declared it. Holding a reference on it
    keeps the body alive for as long as this function exists, even when the
    script that declared it has already been discarded. }
  if (FBody <> nil) and not AOwnsBody then
    FBody.Retain();
end;

constructor TFloriaJSFunction.CreateBytecode(const AName: string; ABytecode: TObject; AClosure: Pointer; AIsArrow: Boolean; AIsAsync: Boolean);
begin
  inherited Create(nil);
  FName := AName;
  FIsNative := False;
  FNativeProc := nil;
  FNativeMethod := nil;
  FParamNames := TStringList.Create();
  FBody := nil;
  FBytecode := ABytecode;
  if FBytecode <> nil then
    TFloriaJSBytecode(FBytecode).Retain();
  FClosureEnv := AClosure;
  FIsAsync := AIsAsync;
  FIsArrow := AIsArrow;
end;

destructor TFloriaJSFunction.Destroy();
var
  i: Integer;
begin
  if FParamNames <> nil then
  begin
    for i := 0 to FParamNames.Count - 1 do
      if FParamNames.Objects[i] <> nil then
        TFloriaJSASTNode(FParamNames.Objects[i]).Release();
    FreeAndNil(FParamNames);
  end;
  if FBody <> nil then
  begin
    FBody.Release();
    FBody := nil;
  end;
  if FBytecode <> nil then
  begin
    TFloriaJSBytecode(FBytecode).Release();
    FBytecode := nil;
  end;
  inherited Destroy();
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
begin
  { Every function is a potential constructor, so it offers the prototype
    object that the objects it creates inherit from. It is created on first
    use. It deliberately does not point back at the function through a
    constructor property: that reference cycle would keep both objects alive
    forever under reference counting. Arrow functions do not have a prototype. }
  if (AName = 'prototype') and (not FIsArrow) and (FindPropertyIndex(AName) < 0) and (FHeap <> nil) then
  begin
    protoObj := FHeap.NewObject();
    SetProperty('prototype', JSMakeObject(protoObj));
  end;

  if (AName = 'toString') and (FindPropertyIndex(AName) < 0) and (FHeap <> nil) then
    Exit(JSMakeFunction(FHeap.NewNativeFunction('toString', @JSFunctionToString)));

  Result := inherited GetPropertyWithReceiver(AName, AReceiver);
end;

function TFloriaJSFunction.GetProperty(const AName: string): TFloriaJSValue;
begin
  Result := GetPropertyWithReceiver(AName, Self);
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
  job.OnFulfilled := AOnFulfilled;
  job.OnRejected := AOnRejected;
  job.OnFinally := AOnFinally;
  job.IsFinally := AIsFinally;
  job.IsRejection := (FState = fjspRejected);
  job.Value := FResult;
  job.Child := AChild;
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
    job.OnFulfilled := reaction.OnFulfilled;
    job.OnRejected := reaction.OnRejected;
    job.OnFinally := reaction.OnFinally;
    job.IsFinally := reaction.IsFinally;
    job.IsRejection := (FState = fjspRejected);
    job.Value := FResult;
    job.Child := reaction.Child;
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
  FJobRunner := nil;
  FInvoker := nil;
  FArrayPrototype := nil;
  FStringPrototype := nil;
  FObjectPrototype := nil;
  FErrorPrototype := nil;
  FTypeErrorPrototype := nil;
  FRangeErrorPrototype := nil;
  FReferenceErrorPrototype := nil;
  FSyntaxErrorPrototype := nil;
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
  FArrayPrototype := nil;
  FStringPrototype := nil;
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

function TFloriaJSHeap.ArrayCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  n, i: Integer;
begin
  { A single numeric argument is the requested length; anything else is an
    element of the new array. }
  if (Length(AArgs) = 1) and AArgs[0].IsNumber() then
  begin
    arr := NewArray();
    n := Trunc(AArgs[0].ToNumber());
    if n < 0 then n := 0;
    for i := 1 to n do
      arr.Push(JSMakeUndefined());
  end
  else
  begin
    arr := NewArray();
    for i := 0 to High(AArgs) do
      arr.Push(AArgs[i]);
  end;

  Result := JSMakeArray(arr);
end;

procedure TFloriaJSHeap.SetFunctionInvoker(AInvoker: TFloriaJSFunctionInvoker);
begin
  FInvoker := AInvoker;
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
  end;
end;

function TFloriaJSHeap.PromiseResolve(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  p: TFloriaJSPromise;
begin
  if (Length(AArgs) > 0) and AArgs[0].IsPromise() then
    Exit(AArgs[0]);

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
        p.Reject(elem.ResultValue);
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
  p.Fulfill(JSMakeArray(outArr));
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
end;

function TFloriaJSHeap.NewNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod): TFloriaJSFunction;
begin
  Result := TFloriaJSFunction(Track(TFloriaJSFunction.CreateNativeMethod(AName, AMethod)));
end;

function TFloriaJSHeap.NewUserFunction(const AName: string; AParams: TStrings; ABody: TFloriaJSStmtNode; AClosure: Pointer; AOwnsBody: Boolean; AIsAsync: Boolean; AIsArrow: Boolean): TFloriaJSFunction;
begin
  Result := TFloriaJSFunction(Track(TFloriaJSFunction.CreateUser(AName, AParams, ABody, AClosure, AOwnsBody, AIsAsync, AIsArrow)));
end;

function TFloriaJSHeap.NewBytecodeFunction(const AName: string; ABytecode: TObject; AClosure: Pointer; AIsArrow: Boolean; AIsAsync: Boolean): TFloriaJSFunction;
begin
  Result := TFloriaJSFunction(Track(TFloriaJSFunction.CreateBytecode(AName, ABytecode, AClosure, AIsArrow, AIsAsync)));
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
      if FObjects <> nil then
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

procedure TFloriaJSHeap.Collect();
var
  i: Integer;
  obj: TFloriaJSObject;
  freed: Boolean;
begin
  ReclaimOrphanedEnvironments();

  { Reclaims the objects that no container refers to any more. Reclaiming an
    object gives up the references it holds, which can make other objects
    unreachable as well, so the sweep repeats until nothing changes. }
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
    FObjectPrototype := nil;
    FErrorPrototype := nil;
    FTypeErrorPrototype := nil;
    FRangeErrorPrototype := nil;
    FReferenceErrorPrototype := nil;
    FSyntaxErrorPrototype := nil;
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

function JSAdd(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
begin
  if ALeft.IsString() or ARight.IsString() then
    Result := JSMakeString(ALeft.ToString() + ARight.ToString())
  else
    Result := JSMakeNumber(ALeft.ToNumber() + ARight.ToNumber());
end;

function JSSubtract(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(ALeft.ToNumber() - ARight.ToNumber());
end;

function JSMultiply(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(ALeft.ToNumber() * ARight.ToNumber());
end;

function JSDivide(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
var
  l, r: Double;
begin
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
  l := ALeft.ToNumber();
  r := ARight.ToNumber();
  if (r = 0.0) or IsNaN(l) or IsNaN(r) then
    Result := JSMakeNumber(NaN)
  else
    Result := JSMakeNumber(FMod(l, r));
end;

function JSPower(const ALeft, ARight: TFloriaJSValue): TFloriaJSValue;
begin
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
      Result := (ALeft.BoolVal = ARight.BoolVal);
    fjstNumber:
      if IsNaN(ALeft.NumVal) or IsNaN(ARight.NumVal) then
        Result := False
      else
        Result := (ALeft.NumVal = ARight.NumVal);
    fjstString:
      Result := (ALeft.StrVal = ARight.StrVal);
    fjstSymbol:
      Result := (ALeft.NumVal = ARight.NumVal) and (ALeft.NumVal <> 0.0);
    fjstObject, fjstArray, fjstFunction:
      Result := (ALeft.ObjVal = ARight.ObjVal);
  else
    Result := False;
  end;
end;

function JSLessThan(const ALeft, ARight: TFloriaJSValue): Boolean;
begin
  if ALeft.IsString() and ARight.IsString() then
    Result := (ALeft.StrVal < ARight.StrVal)
  else
    Result := (ALeft.ToNumber() < ARight.ToNumber());
end;

function JSLessEqual(const ALeft, ARight: TFloriaJSValue): Boolean;
begin
  if ALeft.IsString() and ARight.IsString() then
    Result := (ALeft.StrVal <= ARight.StrVal)
  else
    Result := (ALeft.ToNumber() <= ARight.ToNumber());
end;

function JSGreaterThan(const ALeft, ARight: TFloriaJSValue): Boolean;
begin
  if ALeft.IsString() and ARight.IsString() then
    Result := (ALeft.StrVal > ARight.StrVal)
  else
    Result := (ALeft.ToNumber() > ARight.ToNumber());
end;

function JSInstanceOf(const ALeft, ARight: TFloriaJSValue): Boolean;
var
  pproto: TFloriaJSObject;
  cproto: TFloriaJSValue;
begin
  Result := False;
  if not ALeft.IsObject() then Exit;
  if not ARight.IsFunction() then Exit;
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
