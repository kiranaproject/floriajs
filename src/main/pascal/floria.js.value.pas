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
    function IsTruthy(): Boolean;

    function ToBoolean(): Boolean;
    function ToNumber(): Double;
    function ToString(): string;

    function AsObject(): TFloriaJSObject;
    function AsArray(): TFloriaJSArray;
    function AsFunction(): TFloriaJSFunction;
  end;

  { Property Key-Value Entry }
  TFloriaJSPropertyPair = record
    Key: string;
    Value: TFloriaJSValue;
  end;

  { Heap-allocated Base JavaScript Object }
  TFloriaJSObject = class
  private
    FPrototype: TFloriaJSObject;
    FProperties: array of TFloriaJSPropertyPair;
    FPropCount: Integer;
    function FindPropertyIndex(const AName: string): Integer;
  public
    constructor Create(AProto: TFloriaJSObject = nil);
    destructor Destroy(); override;

    function  GetProperty(const AName: string): TFloriaJSValue; virtual;
    procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); virtual;
    function  HasProperty(const AName: string): Boolean; virtual;
    function  DeleteProperty(const AName: string): Boolean; virtual;

    function  GetPropertyCount(): Integer;
    function  GetPropertyKey(AIndex: Integer): string;
    function  GetPropertyValue(AIndex: Integer): TFloriaJSValue;
    procedure GetKeys(AOutKeys: TStrings);

    property Prototype: TFloriaJSObject read FPrototype write FPrototype;
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
    function  Join(const ASeparator: string = ','): string;
    function  Length(): Integer;

    function  GetProperty(const AName: string): TFloriaJSValue; override;
    procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); override;
    function  HasProperty(const AName: string): Boolean; override;
  end;

  { Native Function Callbacks }
  TFloriaJSNativeProc = function(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
  TFloriaJSNativeMethod = function(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue of object;

  { Heap-allocated JavaScript Function }
  TFloriaJSFunction = class(TFloriaJSObject)
  private
    FName: string;
    FIsNative: Boolean;
    FNativeProc: TFloriaJSNativeProc;
    FNativeMethod: TFloriaJSNativeMethod;
    FParamNames: TStringList;
    FBody: TFloriaJSStmtNode;
    FClosureEnv: Pointer; // Lexical environment TFloriaJSEnvironment
    FOwnsBody: Boolean;
  public
    constructor CreateNative(const AName: string; AProc: TFloriaJSNativeProc);
    constructor CreateNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod);
    constructor CreateUser(const AName: string; AParams: TStrings; ABody: TFloriaJSStmtNode; AClosure: Pointer; AOwnsBody: Boolean = False);
    destructor Destroy(); override;

    property Name: string read FName write FName;
    property IsNative: Boolean read FIsNative;
    property NativeProc: TFloriaJSNativeProc read FNativeProc;
    property NativeMethod: TFloriaJSNativeMethod read FNativeMethod;
    property ParamNames: TStringList read FParamNames;
    property Body: TFloriaJSStmtNode read FBody;
    property ClosureEnv: Pointer read FClosureEnv;
  end;

  { Heap Allocator & Lifetime Tracker }
  TFloriaJSHeap = class
  private
    FObjects: TFPList;
    FEnvironments: TFPList;
  public
    constructor Create();
    destructor Destroy(); override;

    function  Track(AObj: TFloriaJSObject): TFloriaJSObject;
    function  TrackEnvironment(AEnv: TObject): TObject;
    function  NewObject(AProto: TFloriaJSObject = nil): TFloriaJSObject;
    function  NewArray(): TFloriaJSArray;
    function  NewNativeFunction(const AName: string; AProc: TFloriaJSNativeProc): TFloriaJSFunction;
    function  NewNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod): TFloriaJSFunction;
    function  NewUserFunction(const AName: string; AParams: TStrings; ABody: TFloriaJSStmtNode; AClosure: Pointer; AOwnsBody: Boolean = False): TFloriaJSFunction;

    procedure Clear();
    function  GetObjectCount(): Integer;
    function  GetEnvironmentCount(): Integer;
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
  Result.BoolVal := (ANum <> 0.0) and not IsNaN(ANum);
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

{ TFloriaJSObject }

constructor TFloriaJSObject.Create(AProto: TFloriaJSObject);
begin
  inherited Create();
  FPrototype := AProto;
  SetLength(FProperties, 0);
  FPropCount := 0;
end;

destructor TFloriaJSObject.Destroy();
begin
  SetLength(FProperties, 0);
  inherited Destroy();
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

function TFloriaJSObject.GetProperty(const AName: string): TFloriaJSValue;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
    Exit(FProperties[idx].Value);

  if FPrototype <> nil then
    Exit(FPrototype.GetProperty(AName));

  Result := JSMakeUndefined();
end;

procedure TFloriaJSObject.SetProperty(const AName: string; const AValue: TFloriaJSValue);
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
  begin
    FProperties[idx].Value := AValue;
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
  Result := True;
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

{ TFloriaJSArray }

constructor TFloriaJSArray.Create();
begin
  inherited Create(nil);
  SetLength(FElements, 0);
  FCount := 0;
end;

destructor TFloriaJSArray.Destroy();
begin
  SetLength(FElements, 0);
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
  end;

  FElements[AIndex] := AValue;
end;

procedure TFloriaJSArray.Push(const AValue: TFloriaJSValue);
begin
  GrowCapacity(FCount + 1);
  FElements[FCount] := AValue;
  Inc(FCount);
end;

function TFloriaJSArray.Pop(): TFloriaJSValue;
begin
  if FCount = 0 then
    Exit(JSMakeUndefined());

  Dec(FCount);
  Result := FElements[FCount];
  FElements[FCount] := JSMakeUndefined();
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
  Inc(FCount);
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
var
  idx: Integer;
begin
  if AName = 'length' then
    Exit(JSMakeNumber(FCount));

  if TryStrToInt(AName, idx) then
    Exit(GetElement(idx));

  Result := inherited GetProperty(AName);
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
        FCount := idx
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
  FOwnsBody := False;
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
  FOwnsBody := False;
end;

constructor TFloriaJSFunction.CreateUser(const AName: string; AParams: TStrings; ABody: TFloriaJSStmtNode; AClosure: Pointer; AOwnsBody: Boolean);
begin
  inherited Create(nil);
  FName := AName;
  FIsNative := False;
  FNativeProc := nil;
  FNativeMethod := nil;
  FParamNames := TStringList.Create();
  if AParams <> nil then
    FParamNames.Assign(AParams);
  FBody := ABody;
  FClosureEnv := AClosure;
  FOwnsBody := AOwnsBody;
end;

destructor TFloriaJSFunction.Destroy();
begin
  FreeAndNil(FParamNames);
  if FOwnsBody and (FBody <> nil) then
    FreeAndNil(FBody);
  inherited Destroy();
end;

{ TFloriaJSHeap }

constructor TFloriaJSHeap.Create();
begin
  inherited Create();
  FObjects := TFPList.Create();
  FEnvironments := TFPList.Create();
end;

destructor TFloriaJSHeap.Destroy();
begin
  Clear();
  FreeAndNil(FEnvironments);
  FreeAndNil(FObjects);
  inherited Destroy();
end;

function TFloriaJSHeap.Track(AObj: TFloriaJSObject): TFloriaJSObject;
begin
  if (AObj <> nil) and (FObjects.IndexOf(AObj) < 0) then
    FObjects.Add(AObj);
  Result := AObj;
end;

function TFloriaJSHeap.TrackEnvironment(AEnv: TObject): TObject;
begin
  if (AEnv <> nil) and (FEnvironments.IndexOf(AEnv) < 0) then
    FEnvironments.Add(AEnv);
  Result := AEnv;
end;

function TFloriaJSHeap.NewObject(AProto: TFloriaJSObject): TFloriaJSObject;
begin
  Result := Track(TFloriaJSObject.Create(AProto));
end;

function TFloriaJSHeap.NewArray(): TFloriaJSArray;
begin
  Result := TFloriaJSArray(Track(TFloriaJSArray.Create()));
end;

function TFloriaJSHeap.NewNativeFunction(const AName: string; AProc: TFloriaJSNativeProc): TFloriaJSFunction;
begin
  Result := TFloriaJSFunction(Track(TFloriaJSFunction.CreateNative(AName, AProc)));
end;

function TFloriaJSHeap.NewNativeMethod(const AName: string; AMethod: TFloriaJSNativeMethod): TFloriaJSFunction;
begin
  Result := TFloriaJSFunction(Track(TFloriaJSFunction.CreateNativeMethod(AName, AMethod)));
end;

function TFloriaJSHeap.NewUserFunction(const AName: string; AParams: TStrings; ABody: TFloriaJSStmtNode; AClosure: Pointer; AOwnsBody: Boolean): TFloriaJSFunction;
begin
  Result := TFloriaJSFunction(Track(TFloriaJSFunction.CreateUser(AName, AParams, ABody, AClosure, AOwnsBody)));
end;

procedure TFloriaJSHeap.Clear();
var
  i: Integer;
begin
  if FObjects <> nil then
  begin
    for i := FObjects.Count - 1 downto 0 do
      TObject(FObjects[i]).Free();
    FObjects.Clear();
  end;
  if FEnvironments <> nil then
  begin
    for i := FEnvironments.Count - 1 downto 0 do
      TObject(FEnvironments[i]).Free();
    FEnvironments.Clear();
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
    fjstFunction:
      Result := 'function';
    fjstObject, fjstArray:
      Result := 'object';
  else
    Result := 'undefined';
  end;
end;

end.
