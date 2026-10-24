{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Map & Set Collection Data Types                 }
{                                                                          }
{   Provides standard JavaScript Map and Set objects with SameValueZero    }
{   key/value identity, iteration, and size tracking.                      }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.collections;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, floria.js.types, floria.js.value, floria.js.env;

type
  { Map Key-Value Entry }
  TFloriaJSMapEntry = record
    Key: TFloriaJSValue;
    Value: TFloriaJSValue;
  end;
  TFloriaJSMapEntryArray = array of TFloriaJSMapEntry;

  { Map Collection Object }
  TFloriaJSMap = class(TFloriaJSObject)
  private
    FEntries: TFloriaJSMapEntryArray;
    FCount: Integer;
    FCapacity: Integer;
    function FindIndex(const AKey: TFloriaJSValue): Integer;
    procedure EnsureCapacity(AMinCapacity: Integer);
  public
    constructor Create(AProto: TFloriaJSObject = nil);
    destructor Destroy(); override;

    function  GetSize(): Integer;
    procedure SetItem(const AKey, AValue: TFloriaJSValue);
    function  GetItem(const AKey: TFloriaJSValue): TFloriaJSValue;
    function  HasItem(const AKey: TFloriaJSValue): Boolean;
    function  DeleteItem(const AKey: TFloriaJSValue): Boolean;
    procedure Clear();

    property Size: Integer read FCount;
    property Entries: TFloriaJSMapEntryArray read FEntries;
  end;

  { Set Collection Object }
  TFloriaJSSet = class(TFloriaJSObject)
  private
    FValues: array of TFloriaJSValue;
    FCount: Integer;
    FCapacity: Integer;
    function FindIndex(const AValue: TFloriaJSValue): Integer;
    procedure EnsureCapacity(AMinCapacity: Integer);
  public
    constructor Create(AProto: TFloriaJSObject = nil);
    destructor Destroy(); override;

    function  GetSize(): Integer;
    procedure AddItem(const AValue: TFloriaJSValue);
    function  HasItem(const AValue: TFloriaJSValue): Boolean;
    function  DeleteItem(const AValue: TFloriaJSValue): Boolean;
    procedure Clear();

    property Size: Integer read FCount;
  end;

procedure FloriaJSRegisterCollections(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);

implementation

{ SameValueZero comparison helper }
function SameValueZero(const A, B: TFloriaJSValue): Boolean;
begin
  if A.Kind <> B.Kind then Exit(False);
  if A.IsNumber() and B.IsNumber() then
  begin
    if IsNaN(A.NumVal) and IsNaN(B.NumVal) then
      Exit(True);
    Exit(A.NumVal = B.NumVal);
  end;
  Result := JSStrictEqual(A, B);
end;

{ TFloriaJSMap }

constructor TFloriaJSMap.Create(AProto: TFloriaJSObject = nil);
begin
  inherited Create(AProto);
  FCount := 0;
  FCapacity := 8;
  SetLength(FEntries, FCapacity);
end;

destructor TFloriaJSMap.Destroy();
begin
  Clear();
  SetLength(FEntries, 0);
  inherited Destroy();
end;

procedure TFloriaJSMap.EnsureCapacity(AMinCapacity: Integer);
begin
  if AMinCapacity > FCapacity then
  begin
    FCapacity := FCapacity * 2;
    if FCapacity < AMinCapacity then
      FCapacity := AMinCapacity;
    SetLength(FEntries, FCapacity);
  end;
end;

function TFloriaJSMap.FindIndex(const AKey: TFloriaJSValue): Integer;
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
    if SameValueZero(FEntries[i].Key, AKey) then
      Exit(i);
  Result := -1;
end;

function TFloriaJSMap.GetSize(): Integer;
begin
  Result := FCount;
end;

procedure TFloriaJSMap.SetItem(const AKey, AValue: TFloriaJSValue);
var
  idx: Integer;
begin
  idx := FindIndex(AKey);
  if idx >= 0 then
  begin
    JSReleaseValue(FEntries[idx].Value);
    FEntries[idx].Value := AValue;
    JSRetainValue(AValue);
  end
  else
  begin
    EnsureCapacity(FCount + 1);
    FEntries[FCount].Key := AKey;
    FEntries[FCount].Value := AValue;
    JSRetainValue(AKey);
    JSRetainValue(AValue);
    Inc(FCount);
  end;
end;

function TFloriaJSMap.GetItem(const AKey: TFloriaJSValue): TFloriaJSValue;
var
  idx: Integer;
begin
  idx := FindIndex(AKey);
  if idx >= 0 then
    Result := FEntries[idx].Value
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSMap.HasItem(const AKey: TFloriaJSValue): Boolean;
begin
  Result := (FindIndex(AKey) >= 0);
end;

function TFloriaJSMap.DeleteItem(const AKey: TFloriaJSValue): Boolean;
var
  idx, i: Integer;
begin
  idx := FindIndex(AKey);
  if idx < 0 then Exit(False);

  JSReleaseValue(FEntries[idx].Key);
  JSReleaseValue(FEntries[idx].Value);

  for i := idx to FCount - 2 do
    FEntries[i] := FEntries[i + 1];

  Dec(FCount);
  FEntries[FCount].Key := JSMakeUndefined();
  FEntries[FCount].Value := JSMakeUndefined();
  Result := True;
end;

procedure TFloriaJSMap.Clear();
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
  begin
    JSReleaseValue(FEntries[i].Key);
    JSReleaseValue(FEntries[i].Value);
    FEntries[i].Key := JSMakeUndefined();
    FEntries[i].Value := JSMakeUndefined();
  end;
  FCount := 0;
end;

{ TFloriaJSSet }

constructor TFloriaJSSet.Create(AProto: TFloriaJSObject = nil);
begin
  inherited Create(AProto);
  FCount := 0;
  FCapacity := 8;
  SetLength(FValues, FCapacity);
end;

destructor TFloriaJSSet.Destroy();
begin
  Clear();
  SetLength(FValues, 0);
  inherited Destroy();
end;

procedure TFloriaJSSet.EnsureCapacity(AMinCapacity: Integer);
begin
  if AMinCapacity > FCapacity then
  begin
    FCapacity := FCapacity * 2;
    if FCapacity < AMinCapacity then
      FCapacity := AMinCapacity;
    SetLength(FValues, FCapacity);
  end;
end;

function TFloriaJSSet.FindIndex(const AValue: TFloriaJSValue): Integer;
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
    if SameValueZero(FValues[i], AValue) then
      Exit(i);
  Result := -1;
end;

function TFloriaJSSet.GetSize(): Integer;
begin
  Result := FCount;
end;

procedure TFloriaJSSet.AddItem(const AValue: TFloriaJSValue);
begin
  if FindIndex(AValue) >= 0 then Exit;

  EnsureCapacity(FCount + 1);
  FValues[FCount] := AValue;
  JSRetainValue(AValue);
  Inc(FCount);
end;

function TFloriaJSSet.HasItem(const AValue: TFloriaJSValue): Boolean;
begin
  Result := (FindIndex(AValue) >= 0);
end;

function TFloriaJSSet.DeleteItem(const AValue: TFloriaJSValue): Boolean;
var
  idx, i: Integer;
begin
  idx := FindIndex(AValue);
  if idx < 0 then Exit(False);

  JSReleaseValue(FValues[idx]);
  for i := idx to FCount - 2 do
    FValues[i] := FValues[i + 1];

  Dec(FCount);
  FValues[FCount] := JSMakeUndefined();
  Result := True;
end;

procedure TFloriaJSSet.Clear();
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
  begin
    JSReleaseValue(FValues[i]);
    FValues[i] := JSMakeUndefined();
  end;
  FCount := 0;
end;

{ Map JS Bindings }

function JSMapCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  map: TFloriaJSMap;
  iterArr: TFloriaJSArray;
  entryVal, k, v: TFloriaJSValue;
  i: Integer;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    Exit(JSMakeUndefined());

  map := TFloriaJSMap(AThis.ObjVal);

  // If iterable passed to constructor: new Map([[k1, v1], [k2, v2]])
  if (Length(AArgs) > 0) and AArgs[0].IsArray() then
  begin
    iterArr := AArgs[0].AsArray();
    for i := 0 to iterArr.Length() - 1 do
    begin
      entryVal := iterArr.GetElement(i);
      if entryVal.IsArray() and (entryVal.AsArray().Length() >= 2) then
      begin
        k := entryVal.AsArray().GetElement(0);
        v := entryVal.AsArray().GetElement(1);
        map.SetItem(k, v);
      end;
    end;
  end;

  Result := AThis;
end;

var
  GSharedMapProto: TFloriaJSObject = nil;
  GSharedSetProto: TFloriaJSObject = nil;
  GSharedCollectionsHeap: TFloriaJSHeap = nil;

function GetHeap(const AVal: TFloriaJSValue): TFloriaJSHeap;
begin
  if AVal.IsObject() and (AVal.ObjVal <> nil) and (AVal.ObjVal.Heap <> nil) then
    Result := AVal.ObjVal.Heap
  else
    Result := GSharedCollectionsHeap;
end;

function AllocArray(AHeap: TFloriaJSHeap): TFloriaJSArray;
begin
  if AHeap <> nil then
    Result := AHeap.NewArray()
  else
    Result := TFloriaJSArray.Create();
end;

function JSMapSet(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  k, v: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Map.prototype.set called on incompatible receiver')));

  if Length(AArgs) > 0 then k := AArgs[0] else k := JSMakeUndefined();
  if Length(AArgs) > 1 then v := AArgs[1] else v := JSMakeUndefined();

  TFloriaJSMap(AThis.ObjVal).SetItem(k, v);
  Result := AThis;
end;

function JSMapGet(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  k: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Map.prototype.get called on incompatible receiver')));

  if Length(AArgs) > 0 then k := AArgs[0] else k := JSMakeUndefined();
  Result := TFloriaJSMap(AThis.ObjVal).GetItem(k);
end;

function JSMapHas(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  k: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Map.prototype.has called on incompatible receiver')));

  if Length(AArgs) > 0 then k := AArgs[0] else k := JSMakeUndefined();
  Result := JSMakeBoolean(TFloriaJSMap(AThis.ObjVal).HasItem(k));
end;

function JSMapDelete(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  k: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Map.prototype.delete called on incompatible receiver')));

  if Length(AArgs) > 0 then k := AArgs[0] else k := JSMakeUndefined();
  Result := JSMakeBoolean(TFloriaJSMap(AThis.ObjVal).DeleteItem(k));
end;

function JSMapClear(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Map.prototype.clear called on incompatible receiver')));

  TFloriaJSMap(AThis.ObjVal).Clear();
  Result := JSMakeUndefined();
end;

function JSMapGetSize(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    Exit(JSMakeNumber(0));
  Result := JSMakeNumber(TFloriaJSMap(AThis.ObjVal).GetSize());
end;

function JSMapKeys(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  map: TFloriaJSMap;
  arr: TFloriaJSArray;
  i: Integer;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Map.prototype.keys called on incompatible receiver')));

  map := TFloriaJSMap(AThis.ObjVal);
  arr := AllocArray(GetHeap(AThis));
  for i := 0 to map.FCount - 1 do
    arr.Push(map.FEntries[i].Key);

  Result := JSMakeObject(arr);
end;

function JSMapValues(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  map: TFloriaJSMap;
  arr: TFloriaJSArray;
  i: Integer;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Map.prototype.values called on incompatible receiver')));

  map := TFloriaJSMap(AThis.ObjVal);
  arr := AllocArray(GetHeap(AThis));
  for i := 0 to map.FCount - 1 do
    arr.Push(map.FEntries[i].Value);

  Result := JSMakeObject(arr);
end;

function JSMapEntries(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  map: TFloriaJSMap;
  arr, pairArr: TFloriaJSArray;
  i: Integer;
  h: TFloriaJSHeap;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Map.prototype.entries called on incompatible receiver')));

  map := TFloriaJSMap(AThis.ObjVal);
  h := GetHeap(AThis);
  arr := AllocArray(h);
  for i := 0 to map.FCount - 1 do
  begin
    pairArr := AllocArray(h);
    pairArr.Push(map.FEntries[i].Key);
    pairArr.Push(map.FEntries[i].Value);
    arr.Push(JSMakeObject(pairArr));
  end;

  Result := JSMakeObject(arr);
end;

function JSMapForEach(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  map: TFloriaJSMap;
  cb, thisArg: TFloriaJSValue;
  cbArgs: array[0..2] of TFloriaJSValue;
  i: Integer;
  h: TFloriaJSHeap;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Map.prototype.forEach called on incompatible receiver')));

  if (Length(AArgs) = 0) or not AArgs[0].IsFunction() then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Callback must be a function')));

  cb := AArgs[0];
  if Length(AArgs) > 1 then thisArg := AArgs[1] else thisArg := JSMakeUndefined();

  map := TFloriaJSMap(AThis.ObjVal);
  h := GetHeap(AThis);

  if h <> nil then
  begin
    for i := 0 to map.FCount - 1 do
    begin
      cbArgs[0] := map.FEntries[i].Value;
      cbArgs[1] := map.FEntries[i].Key;
      cbArgs[2] := AThis;
      h.InvokeFunction(cb, cbArgs, thisArg);
    end;
  end;

  Result := JSMakeUndefined();
end;

{ Set JS Bindings }

function JSSetCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: TFloriaJSSet;
  iterArr: TFloriaJSArray;
  i: Integer;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    Exit(JSMakeUndefined());

  s := TFloriaJSSet(AThis.ObjVal);

  if (Length(AArgs) > 0) and AArgs[0].IsArray() then
  begin
    iterArr := AArgs[0].AsArray();
    for i := 0 to iterArr.Length() - 1 do
      s.AddItem(iterArr.GetElement(i));
  end;

  Result := AThis;
end;

function JSSetAdd(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  v: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Set.prototype.add called on incompatible receiver')));

  if Length(AArgs) > 0 then v := AArgs[0] else v := JSMakeUndefined();
  TFloriaJSSet(AThis.ObjVal).AddItem(v);
  Result := AThis;
end;

function JSSetHas(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  v: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Set.prototype.has called on incompatible receiver')));

  if Length(AArgs) > 0 then v := AArgs[0] else v := JSMakeUndefined();
  Result := JSMakeBoolean(TFloriaJSSet(AThis.ObjVal).HasItem(v));
end;

function JSSetDelete(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  v: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Set.prototype.delete called on incompatible receiver')));

  if Length(AArgs) > 0 then v := AArgs[0] else v := JSMakeUndefined();
  Result := JSMakeBoolean(TFloriaJSSet(AThis.ObjVal).DeleteItem(v));
end;

function JSSetClear(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Set.prototype.clear called on incompatible receiver')));

  TFloriaJSSet(AThis.ObjVal).Clear();
  Result := JSMakeUndefined();
end;

function JSSetGetSize(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    Exit(JSMakeNumber(0));
  Result := JSMakeNumber(TFloriaJSSet(AThis.ObjVal).GetSize());
end;

function JSSetValues(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: TFloriaJSSet;
  arr: TFloriaJSArray;
  i: Integer;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Set.prototype.values called on incompatible receiver')));

  s := TFloriaJSSet(AThis.ObjVal);
  arr := AllocArray(GetHeap(AThis));
  for i := 0 to s.FCount - 1 do
    arr.Push(s.FValues[i]);

  Result := JSMakeObject(arr);
end;

function JSSetEntries(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: TFloriaJSSet;
  arr, pairArr: TFloriaJSArray;
  i: Integer;
  h: TFloriaJSHeap;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Set.prototype.entries called on incompatible receiver')));

  s := TFloriaJSSet(AThis.ObjVal);
  h := GetHeap(AThis);
  arr := AllocArray(h);
  for i := 0 to s.FCount - 1 do
  begin
    pairArr := AllocArray(h);
    pairArr.Push(s.FValues[i]);
    pairArr.Push(s.FValues[i]);
    arr.Push(JSMakeObject(pairArr));
  end;

  Result := JSMakeObject(arr);
end;

function JSSetForEach(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: TFloriaJSSet;
  cb, thisArg: TFloriaJSValue;
  cbArgs: array[0..2] of TFloriaJSValue;
  i: Integer;
  h: TFloriaJSHeap;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method Set.prototype.forEach called on incompatible receiver')));

  if (Length(AArgs) = 0) or not AArgs[0].IsFunction() then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Callback must be a function')));

  cb := AArgs[0];
  if Length(AArgs) > 1 then thisArg := AArgs[1] else thisArg := JSMakeUndefined();

  s := TFloriaJSSet(AThis.ObjVal);
  h := GetHeap(AThis);

  if h <> nil then
  begin
    for i := 0 to s.FCount - 1 do
    begin
      cbArgs[0] := s.FValues[i];
      cbArgs[1] := s.FValues[i];
      cbArgs[2] := AThis;
      h.InvokeFunction(cb, cbArgs, thisArg);
    end;
  end;

  Result := JSMakeUndefined();
end;

{ Registration }

function FactoryNewMap(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  map: TFloriaJSMap;
begin
  map := TFloriaJSMap.Create(GSharedMapProto);
  if GSharedCollectionsHeap <> nil then
    GSharedCollectionsHeap.Track(map);
  Result := JSMakeObject(map);
  JSMapCtor(AArgs, Result);
end;

function FactoryNewSet(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: TFloriaJSSet;
begin
  s := TFloriaJSSet.Create(GSharedSetProto);
  if GSharedCollectionsHeap <> nil then
    GSharedCollectionsHeap.Track(s);
  Result := JSMakeObject(s);
  JSSetCtor(AArgs, Result);
end;

procedure FloriaJSRegisterCollections(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  mapCtor, setCtor: TFloriaJSFunction;
  sizeGetter: TFloriaJSFunction;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;
  GSharedCollectionsHeap := AHeap;

  // 1. Map Prototype
  GSharedMapProto := AHeap.NewObject();
  GSharedMapProto.SetProperty('set', JSMakeFunction(AHeap.NewNativeFunction('set', @JSMapSet)));
  GSharedMapProto.SetProperty('get', JSMakeFunction(AHeap.NewNativeFunction('get', @JSMapGet)));
  GSharedMapProto.SetProperty('has', JSMakeFunction(AHeap.NewNativeFunction('has', @JSMapHas)));
  GSharedMapProto.SetProperty('delete', JSMakeFunction(AHeap.NewNativeFunction('delete', @JSMapDelete)));
  GSharedMapProto.SetProperty('clear', JSMakeFunction(AHeap.NewNativeFunction('clear', @JSMapClear)));
  GSharedMapProto.SetProperty('keys', JSMakeFunction(AHeap.NewNativeFunction('keys', @JSMapKeys)));
  GSharedMapProto.SetProperty('values', JSMakeFunction(AHeap.NewNativeFunction('values', @JSMapValues)));
  GSharedMapProto.SetProperty('entries', JSMakeFunction(AHeap.NewNativeFunction('entries', @JSMapEntries)));
  GSharedMapProto.SetProperty('forEach', JSMakeFunction(AHeap.NewNativeFunction('forEach', @JSMapForEach)));

  sizeGetter := AHeap.NewNativeFunction('get size', @JSMapGetSize);
  GSharedMapProto.DefineGetter('size', JSMakeFunction(sizeGetter));

  mapCtor := AHeap.NewNativeFunction('Map', @FactoryNewMap);
  mapCtor.SetProperty('prototype', JSMakeObject(GSharedMapProto));
  AEnv.Define('Map', JSMakeFunction(mapCtor));

  // 2. Set Prototype
  GSharedSetProto := AHeap.NewObject();
  GSharedSetProto.SetProperty('add', JSMakeFunction(AHeap.NewNativeFunction('add', @JSSetAdd)));
  GSharedSetProto.SetProperty('has', JSMakeFunction(AHeap.NewNativeFunction('has', @JSSetHas)));
  GSharedSetProto.SetProperty('delete', JSMakeFunction(AHeap.NewNativeFunction('delete', @JSSetDelete)));
  GSharedSetProto.SetProperty('clear', JSMakeFunction(AHeap.NewNativeFunction('clear', @JSSetClear)));
  GSharedSetProto.SetProperty('keys', JSMakeFunction(AHeap.NewNativeFunction('keys', @JSSetValues)));
  GSharedSetProto.SetProperty('values', JSMakeFunction(AHeap.NewNativeFunction('values', @JSSetValues)));
  GSharedSetProto.SetProperty('entries', JSMakeFunction(AHeap.NewNativeFunction('entries', @JSSetEntries)));
  GSharedSetProto.SetProperty('forEach', JSMakeFunction(AHeap.NewNativeFunction('forEach', @JSSetForEach)));

  sizeGetter := AHeap.NewNativeFunction('get size', @JSSetGetSize);
  GSharedSetProto.DefineGetter('size', JSMakeFunction(sizeGetter));

  setCtor := AHeap.NewNativeFunction('Set', @FactoryNewSet);
  setCtor.SetProperty('prototype', JSMakeObject(GSharedSetProto));
  AEnv.Define('Set', JSMakeFunction(setCtor));
end;

end.
