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
  Classes, SysUtils, Math, floria.js.types, floria.js.value, floria.js.env,
  floria.js.utf16, floria.js.regexp, floria.js.symbol;

type
  { Map Key-Value Entry }
  TFloriaJSMapEntry = record
    Key: TFloriaJSValue;
    Value: TFloriaJSValue;
  end;
  TFloriaJSMapEntryArray = array of TFloriaJSMapEntry;

  { What an iterator walks. }
  TFloriaJSIterKind = (fikArray, fikArrayKeys, fikArrayEntries, fikString,
    fikMapKeys, fikMapValues, fikMapEntries, fikSetValues, fikSetEntries,
    fikRegExpMatches);

  { A native iterator object implementing the ECMAScript iteration protocol.

    It holds the source and a cursor, so `next()` is O(1) and the source is
    walked lazily rather than copied into a temporary array. `[Symbol.iterator]`
    returns the iterator itself, which is what makes an iterator usable directly
    in `for…of` and in spread. }
  TFloriaJSIterator = class(TFloriaJSObject)
  private
    FKind: TFloriaJSIterKind;
    FSource: TFloriaJSValue;
    FCursor: Integer;
    FDone: Boolean;
    FNextFn: TFloriaJSFunction;
    FSelfIteratorFn: TFloriaJSFunction;
    function Produce(out AValue: TFloriaJSValue): Boolean;
  public
    constructor Create(AHeap: TFloriaJSHeap; AKind: TFloriaJSIterKind;
      const ASource: TFloriaJSValue);
    destructor Destroy(); override;

    function  GetPropertyWithReceiver(const AName: string;
      AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    function  HasProperty(const AName: string): Boolean; override;

    function  Step(out AValue: TFloriaJSValue): Boolean;
    function  Next(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  SelfIterator(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;

    property Kind: TFloriaJSIterKind read FKind;
    property Source: TFloriaJSValue read FSource;
  end;

  { Map Collection Object }
  TFloriaJSMap = class(TFloriaJSObject)
  private
    FEntries: TFloriaJSMapEntryArray;
    FCount: Integer;
    FCapacity: Integer;
    { A weak map holds its keys without retaining them. The collector prunes
      entries whose key is dead, so a key can be reclaimed while the map is
      still alive. }
    FWeakKeys: Boolean;
    function FindIndex(const AKey: TFloriaJSValue): Integer;
    procedure EnsureCapacity(AMinCapacity: Integer);
  public
    constructor Create(AProto: TFloriaJSObject = nil; AWeakKeys: Boolean = False);
    destructor Destroy(); override;

    function  GetSize(): Integer;
    procedure SetItem(const AKey, AValue: TFloriaJSValue);
    function  GetItem(const AKey: TFloriaJSValue): TFloriaJSValue;
    function  HasItem(const AKey: TFloriaJSValue): Boolean;
    function  DeleteItem(const AKey: TFloriaJSValue): Boolean;
    procedure Clear();
    { Drops entries whose key object has been reclaimed. Returns True when an
      entry was removed. }
    function  PruneDeadKeys(): Boolean;
    function  PruneWeakEntries(): Boolean; override;

    property Size: Integer read FCount;
    property WeakKeys: Boolean read FWeakKeys;
    property Entries: TFloriaJSMapEntryArray read FEntries;
  end;

  { WeakMap: a Map that does not retain its keys. The distinct class makes the
    internal-slot brand check observable: `WeakMap.prototype.set.call(new Map(), …)`
    must throw. }
  TFloriaJSWeakMap = class(TFloriaJSMap)
  public
    constructor Create(AProto: TFloriaJSObject = nil);
    destructor Destroy(); override;
  end;

  { Set Collection Object }
  TFloriaJSSet = class(TFloriaJSObject)
  private
    FValues: array of TFloriaJSValue;
    FCount: Integer;
    FCapacity: Integer;
    FWeakValues: Boolean;
    function FindIndex(const AValue: TFloriaJSValue): Integer;
    procedure EnsureCapacity(AMinCapacity: Integer);
  public
    constructor Create(AProto: TFloriaJSObject = nil; AWeakValues: Boolean = False);
    destructor Destroy(); override;

    function  GetSize(): Integer;
    procedure AddItem(const AValue: TFloriaJSValue);
    function  HasItem(const AValue: TFloriaJSValue): Boolean;
    function  DeleteItem(const AValue: TFloriaJSValue): Boolean;
    procedure Clear();
    { The stored value at an index, in insertion order. Used by the iterator. }
    function  GetItem(AIndex: Integer): TFloriaJSValue;
    function  PruneDeadValues(): Boolean;
    function  PruneWeakEntries(): Boolean; override;

    property Size: Integer read FCount;
    property WeakValues: Boolean read FWeakValues;
  end;

  { WeakSet: a Set that does not retain its values. }
  TFloriaJSWeakSet = class(TFloriaJSSet)
  public
    constructor Create(AProto: TFloriaJSObject = nil);
    destructor Destroy(); override;
  end;


procedure FloriaJSRegisterCollections(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);

{ WeakMap/WeakSet hold object keys without retaining them. }
procedure FloriaJSRegisterWeakCollections(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);

{ Builds an iterator over AValue. Returns False when the value is not iterable,
  so the caller can raise the ECMAScript TypeError with its own wording. }
{ Array.prototype.values / [Symbol.iterator]: returns an iterator over the
  receiver. Registered here because this unit owns the iterator type. }
function JSArrayValues(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
function JSArrayKeys(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
function JSArrayEntries(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;

function JSGetIterator(AHeap: TFloriaJSHeap; const AValue: TFloriaJSValue;
  out AIterator: TFloriaJSIterator): Boolean;
{ Steps an iterator: returns False when it is done, otherwise the next value. }
function JSIteratorNext(const AIterator: TFloriaJSIterator;
  out AValue: TFloriaJSValue): Boolean;
{ Collects a whole iterator into a fresh array. }
function JSIteratorToArray(const AIterator: TFloriaJSIterator): TFloriaJSArray;

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

constructor TFloriaJSWeakMap.Create(AProto: TFloriaJSObject = nil);
begin
  inherited Create(AProto, True);
end;

destructor TFloriaJSWeakMap.Destroy();
begin
  { The heap keeps a list of weak collections to prune. A reclaimed collection
    must leave that list, or the next collection would dereference it. }
  if Heap <> nil then
    Heap.UnregisterWeakCollection(Self);
  inherited Destroy();
end;

constructor TFloriaJSMap.Create(AProto: TFloriaJSObject = nil;
  AWeakKeys: Boolean = False);
begin
  inherited Create(AProto);
  FCount := 0;
  FCapacity := 8;
  FWeakKeys := AWeakKeys;
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
    if not FWeakKeys then
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

  if not FWeakKeys then
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
    if not FWeakKeys then
      JSReleaseValue(FEntries[i].Key);
    JSReleaseValue(FEntries[i].Value);
    FEntries[i].Key := JSMakeUndefined();
    FEntries[i].Value := JSMakeUndefined();
  end;
  FCount := 0;
end;

{ A weak map drops the entries whose key object the collector has reclaimed. }
function TFloriaJSMap.PruneDeadKeys(): Boolean;
var
  i, kept: Integer;
begin
  Result := False;
  if not FWeakKeys then
    Exit;
  kept := 0;
  for i := 0 to FCount - 1 do
  begin
    { A key with no references is about to be reclaimed. Pruning runs before
      the sweep, so the object is still addressable here. }
    if FEntries[i].Key.IsObject() and
       (FEntries[i].Key.ObjVal.RefCount > 0) then
    begin
      if kept <> i then
        FEntries[kept] := FEntries[i];
      Inc(kept);
    end
    else if (not FEntries[i].Key.IsObject()) then
    begin
      if kept <> i then
        FEntries[kept] := FEntries[i];
      Inc(kept);
    end
    else
    begin
      { The key is gone; the entry's value reference goes with it. }
      if (Heap = nil) or (not Heap.IsClearing) then
        JSReleaseValue(FEntries[i].Value);
      FEntries[i].Key := JSMakeUndefined();
      FEntries[i].Value := JSMakeUndefined();
      Result := True;
    end;
  end;
  FCount := kept;
end;

function TFloriaJSMap.PruneWeakEntries(): Boolean;
begin
  Result := PruneDeadKeys();
end;

{ TFloriaJSSet }

constructor TFloriaJSWeakSet.Create(AProto: TFloriaJSObject = nil);
begin
  inherited Create(AProto, True);
end;

destructor TFloriaJSWeakSet.Destroy();
begin
  if Heap <> nil then
    Heap.UnregisterWeakCollection(Self);
  inherited Destroy();
end;

constructor TFloriaJSSet.Create(AProto: TFloriaJSObject = nil;
  AWeakValues: Boolean = False);
begin
  inherited Create(AProto);
  FCount := 0;
  FCapacity := 8;
  FWeakValues := AWeakValues;
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

function TFloriaJSSet.GetItem(AIndex: Integer): TFloriaJSValue;
begin
  if (AIndex >= 0) and (AIndex < FCount) then
    Result := FValues[AIndex]
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSSet.GetSize(): Integer;
begin
  Result := FCount;
end;

function TFloriaJSSet.PruneDeadValues(): Boolean;
var
  i, kept: Integer;
begin
  Result := False;
  if not FWeakValues then
    Exit;
  kept := 0;
  for i := 0 to FCount - 1 do
  begin
    if (not FValues[i].IsObject()) or (FValues[i].ObjVal.RefCount > 0) then
    begin
      if kept <> i then
        FValues[kept] := FValues[i];
      Inc(kept);
    end
    else
    begin
      FValues[i] := JSMakeUndefined();
      Result := True;
    end;
  end;
  FCount := kept;
end;

procedure TFloriaJSSet.AddItem(const AValue: TFloriaJSValue);
begin
  if FindIndex(AValue) >= 0 then Exit;

  EnsureCapacity(FCount + 1);
  FValues[FCount] := AValue;
  if not FWeakValues then
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
    if not FWeakValues then
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

var
  GSharedWeakMapProto: TFloriaJSObject = nil;
  GSharedWeakSetProto: TFloriaJSObject = nil;

{ CanBeHeldWeakly: only a non-registered symbol or an object qualifies. }
function CanBeHeldWeakly(const AValue: TFloriaJSValue): Boolean;
begin
  { An object, or a symbol that is not in the global registry, may be held
    weakly. A `Symbol.for` registration lives for the lifetime of the realm. }
  Result := AValue.IsObject() or
    (AValue.IsSymbol() and (not JSSymbolIsRegistered(AValue)));
end;

{ Installs Symbol.toStringTag under the actual well-known symbol key, so a
  descriptor lookup with `Symbol.toStringTag` finds it. }
procedure DefineToStringTag(AObj: TFloriaJSObject; const AValue: string);
var
  sym: TFloriaJSValue;
begin
  sym := JSWellKnownSymbol('Symbol.toStringTag');
  if sym.IsUndefined() then
  begin
    AObj.DefineDataProperty(JSPropertyKeyName(JSMakeSymbol('Symbol.toStringTag', 0)),
      JSMakeString(AValue), False, False, True);
    Exit;
  end;
  AObj.DefineDataProperty(JSPropertyKeyName(sym), JSMakeString(AValue), False, False, True);
end;

function WeakCollectionError(const AMessage: string): TFloriaJSValue;
begin
  if GSharedCollectionsHeap <> nil then
    Exit(JSMakeObject(GSharedCollectionsHeap.NewError('TypeError', AMessage)));
  Result := JSMakeObject(TFloriaJSError.Create('TypeError', AMessage));
end;

function RequireWeakKey(const AValue: TFloriaJSValue;
  const AMethod: string): TFloriaJSValue;
begin
  if CanBeHeldWeakly(AValue) then
    Exit(AValue);
  if AValue.IsObject() and (AValue.ObjVal.Heap <> nil) then
    raise EFloriaJSThrow.Create(JSMakeObject(
      AValue.ObjVal.Heap.NewError('TypeError', 'Invalid value used as weak ' + AMethod)));
  if GSharedCollectionsHeap <> nil then
    raise EFloriaJSThrow.Create(JSMakeObject(
      GSharedCollectionsHeap.NewError('TypeError', 'Invalid value used as weak ' + AMethod)));
  raise EFloriaJSThrow.Create(JSMakeString('TypeError: invalid weak key'));
end;

function JSWeakMapCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  map: TFloriaJSMap;
  heap: TFloriaJSHeap;
  iter: TFloriaJSIterator;
  entry, k, v, adder: TFloriaJSValue;
begin
  heap := GSharedCollectionsHeap;
  if heap = nil then
    Exit(JSMakeUndefined());
  { WeakMap is a constructor: a plain call is a TypeError. A construction
    arrives with the freshly created instance bound to `this`. }
  if (not heap.CurrentNewTarget.IsFunction()) and
     (AThis.IsObject() and (AThis.ObjVal is TFloriaJSWeakMap)) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Constructor WeakMap requires new'));
  map := TFloriaJSWeakMap(heap.Track(TFloriaJSWeakMap.Create(GSharedWeakMapProto)));
  heap.RegisterWeakCollection(map);

  if (Length(AArgs) > 0) and (not AArgs[0].IsUndefined()) and
     (not AArgs[0].IsNull()) then
  begin
    if not JSGetIterator(heap, AArgs[0], iter) then
      raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
        'WeakMap iterable is not iterable')));
    while JSIteratorNext(iter, entry) do
    begin
      if not entry.IsObject() then
        raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
          'Iterator value is not an entry object')));
      k := entry.AsObject().GetProperty('0');
      v := entry.AsObject().GetProperty('1');
      RequireWeakKey(k, 'key');
      adder := JSMakeUndefined();
      if GSharedWeakMapProto <> nil then
        adder := GSharedWeakMapProto.GetProperty('set');
      if adder.IsFunction() then
        heap.InvokeFunction(adder, [k, v], JSMakeObject(map))
      else
        map.SetItem(k, v);
    end;
  end;
  Result := JSMakeObject(map);
end;

function JSWeakMapSet(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSWeakMap) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method WeakMap.prototype.set called on incompatible receiver'));
  if Length(AArgs) < 1 then
    raise EFloriaJSThrow.Create(WeakCollectionError('Invalid value used as weak map key'));
  RequireWeakKey(AArgs[0], 'map key');
  if Length(AArgs) > 1 then
    TFloriaJSMap(AThis.ObjVal).SetItem(AArgs[0], AArgs[1])
  else
    TFloriaJSMap(AThis.ObjVal).SetItem(AArgs[0], JSMakeUndefined());
  Result := AThis;
end;

function JSWeakMapGet(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSWeakMap) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method WeakMap.prototype.get called on incompatible receiver'));
  if Length(AArgs) < 1 then
    Exit(JSMakeUndefined());
  Result := TFloriaJSMap(AThis.ObjVal).GetItem(AArgs[0]);
end;

function JSWeakMapHas(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSWeakMap) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method WeakMap.prototype.has called on incompatible receiver'));
  if Length(AArgs) < 1 then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(TFloriaJSMap(AThis.ObjVal).HasItem(AArgs[0]));
end;

function JSWeakMapDelete(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSWeakMap) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method WeakMap.prototype.delete called on incompatible receiver'));
  if Length(AArgs) < 1 then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(TFloriaJSMap(AThis.ObjVal).DeleteItem(AArgs[0]));
end;

{ WeakMap.prototype.getOrInsert(key, value) — returns the existing value, or
  inserts `value` and returns it. }
function JSWeakMapGetOrInsert(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  map: TFloriaJSMap;
  v: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSWeakMap) then
    raise EFloriaJSThrow.Create(WeakCollectionError(
      'Method WeakMap.prototype.getOrInsert called on incompatible receiver'));
  if Length(AArgs) < 1 then
    raise EFloriaJSThrow.Create(WeakCollectionError('Invalid value used as weak map key'));
  RequireWeakKey(AArgs[0], 'map key');
  map := TFloriaJSMap(AThis.ObjVal);
  if map.HasItem(AArgs[0]) then
    Exit(map.GetItem(AArgs[0]));
  if Length(AArgs) > 1 then v := AArgs[1] else v := JSMakeUndefined();
  map.SetItem(AArgs[0], v);
  Result := v;
end;

function JSWeakMapGetOrInsertComputed(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  map: TFloriaJSMap;
  heap: TFloriaJSHeap;
  v: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSWeakMap) then
    raise EFloriaJSThrow.Create(WeakCollectionError(
      'Method WeakMap.prototype.getOrInsertComputed called on incompatible receiver'));
  if (Length(AArgs) < 2) or (not AArgs[1].IsFunction()) then
    raise EFloriaJSThrow.Create(WeakCollectionError(
      'WeakMap.prototype.getOrInsertComputed requires a callable callback'));
  RequireWeakKey(AArgs[0], 'map key');
  map := TFloriaJSMap(AThis.ObjVal);
  if map.HasItem(AArgs[0]) then
    Exit(map.GetItem(AArgs[0]));
  heap := map.Heap;
  if heap = nil then
    heap := GSharedCollectionsHeap;
  v := heap.InvokeFunction(AArgs[1], [AArgs[0]], JSMakeUndefined());
  { The callback may have inserted the key itself. }
  if map.HasItem(AArgs[0]) then
    Exit(map.GetItem(AArgs[0]));
  map.SetItem(AArgs[0], v);
  Result := v;
end;

function JSWeakSetCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  setObj: TFloriaJSSet;
  heap: TFloriaJSHeap;
  iter: TFloriaJSIterator;
  item, adder: TFloriaJSValue;
begin
  heap := GSharedCollectionsHeap;
  if heap = nil then
    Exit(JSMakeUndefined());
  if (not heap.CurrentNewTarget.IsFunction()) and
     (AThis.IsObject() and (AThis.ObjVal is TFloriaJSWeakSet)) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Constructor WeakSet requires new'));
  setObj := TFloriaJSWeakSet(heap.Track(TFloriaJSWeakSet.Create(GSharedWeakSetProto)));
  heap.RegisterWeakCollection(setObj);

  if (Length(AArgs) > 0) and (not AArgs[0].IsUndefined()) and
     (not AArgs[0].IsNull()) then
  begin
    if not JSGetIterator(heap, AArgs[0], iter) then
      raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
        'WeakSet iterable is not iterable')));
    while JSIteratorNext(iter, item) do
    begin
      RequireWeakKey(item, 'set value');
      adder := JSMakeUndefined();
      if GSharedWeakSetProto <> nil then
        adder := GSharedWeakSetProto.GetProperty('add');
      if adder.IsFunction() then
        heap.InvokeFunction(adder, [item], JSMakeObject(setObj))
      else
        setObj.AddItem(item);
    end;
  end;
  Result := JSMakeObject(setObj);
end;

function JSWeakSetAdd(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSWeakSet) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method WeakSet.prototype.add called on incompatible receiver'));
  if Length(AArgs) < 1 then
    raise EFloriaJSThrow.Create(WeakCollectionError('Invalid value used as weak set value'));
  RequireWeakKey(AArgs[0], 'set value');
  TFloriaJSSet(AThis.ObjVal).AddItem(AArgs[0]);
  Result := AThis;
end;

function JSWeakSetHas(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSWeakSet) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method WeakSet.prototype.has called on incompatible receiver'));
  if Length(AArgs) < 1 then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(TFloriaJSSet(AThis.ObjVal).HasItem(AArgs[0]));
end;

function JSWeakSetDelete(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or (not (AThis.ObjVal is TFloriaJSWeakSet)) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method WeakSet.prototype.delete called on incompatible receiver'));
  if Length(AArgs) < 1 then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(TFloriaJSSet(AThis.ObjVal).DeleteItem(AArgs[0]));
end;

procedure FloriaJSRegisterWeakCollections(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  weakMapCtor, weakSetCtor: TFloriaJSFunction;
  fn: TFloriaJSFunction;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;

  GSharedWeakMapProto := AHeap.NewObject(AHeap.GetObjectPrototype());
  GSharedWeakSetProto := AHeap.NewObject(AHeap.GetObjectPrototype());

  { WeakMap/WeakSet are not constructable-without-new and have length 0, and
    their prototypes expose Symbol.toStringTag. }
  weakMapCtor := AHeap.NewNativeFunction('WeakMap', @JSWeakMapCtor);
  weakMapCtor.LengthOverride := 0;
  DefineToStringTag(GSharedWeakMapProto, 'WeakMap');
  weakMapCtor.DefineDataProperty('prototype', JSMakeObject(GSharedWeakMapProto), False, False, False);
  GSharedWeakMapProto.DefineDataProperty('constructor', JSMakeFunction(weakMapCtor), True, False, True);
  fn := AHeap.NewNativeFunction('set', @JSWeakMapSet);
  fn.NotConstructable := True; fn.SuppressPrototype := True; fn.LengthOverride := 2;
  GSharedWeakMapProto.DefineDataProperty('set', JSMakeFunction(fn), True, False, True);
  fn := AHeap.NewNativeFunction('get', @JSWeakMapGet);
  fn.NotConstructable := True; fn.SuppressPrototype := True; fn.LengthOverride := 1;
  GSharedWeakMapProto.DefineDataProperty('get', JSMakeFunction(fn), True, False, True);
  fn := AHeap.NewNativeFunction('has', @JSWeakMapHas);
  fn.NotConstructable := True; fn.SuppressPrototype := True; fn.LengthOverride := 1;
  GSharedWeakMapProto.DefineDataProperty('has', JSMakeFunction(fn), True, False, True);
  fn := AHeap.NewNativeFunction('delete', @JSWeakMapDelete);
  fn.NotConstructable := True; fn.SuppressPrototype := True; fn.LengthOverride := 1;
  GSharedWeakMapProto.DefineDataProperty('delete', JSMakeFunction(fn), True, False, True);
  fn := AHeap.NewNativeFunction('getOrInsert', @JSWeakMapGetOrInsert);
  fn.NotConstructable := True; fn.SuppressPrototype := True; fn.LengthOverride := 2;
  GSharedWeakMapProto.DefineDataProperty('getOrInsert', JSMakeFunction(fn), True, False, True);
  fn := AHeap.NewNativeFunction('getOrInsertComputed', @JSWeakMapGetOrInsertComputed);
  fn.NotConstructable := True; fn.SuppressPrototype := True; fn.LengthOverride := 2;
  GSharedWeakMapProto.DefineDataProperty('getOrInsertComputed', JSMakeFunction(fn), True, False, True);
  AEnv.DefineBuiltin('WeakMap', JSMakeFunction(weakMapCtor));

  weakSetCtor := AHeap.NewNativeFunction('WeakSet', @JSWeakSetCtor);
  weakSetCtor.LengthOverride := 0;
  DefineToStringTag(GSharedWeakSetProto, 'WeakSet');
  weakSetCtor.DefineDataProperty('prototype', JSMakeObject(GSharedWeakSetProto), False, False, False);
  GSharedWeakSetProto.DefineDataProperty('constructor', JSMakeFunction(weakSetCtor), True, False, True);
  fn := AHeap.NewNativeFunction('add', @JSWeakSetAdd);
  fn.NotConstructable := True; fn.SuppressPrototype := True; fn.LengthOverride := 1;
  GSharedWeakSetProto.DefineDataProperty('add', JSMakeFunction(fn), True, False, True);
  fn := AHeap.NewNativeFunction('has', @JSWeakSetHas);
  fn.NotConstructable := True; fn.SuppressPrototype := True; fn.LengthOverride := 1;
  GSharedWeakSetProto.DefineDataProperty('has', JSMakeFunction(fn), True, False, True);
  fn := AHeap.NewNativeFunction('delete', @JSWeakSetDelete);
  fn.NotConstructable := True; fn.SuppressPrototype := True; fn.LengthOverride := 1;
  GSharedWeakSetProto.DefineDataProperty('delete', JSMakeFunction(fn), True, False, True);
  AEnv.DefineBuiltin('WeakSet', JSMakeFunction(weakSetCtor));
end;


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
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Map.prototype.set called on incompatible receiver'));

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
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Map.prototype.get called on incompatible receiver'));

  if Length(AArgs) > 0 then k := AArgs[0] else k := JSMakeUndefined();
  Result := TFloriaJSMap(AThis.ObjVal).GetItem(k);
end;

function JSMapHas(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  k: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Map.prototype.has called on incompatible receiver'));

  if Length(AArgs) > 0 then k := AArgs[0] else k := JSMakeUndefined();
  Result := JSMakeBoolean(TFloriaJSMap(AThis.ObjVal).HasItem(k));
end;

function JSMapDelete(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  k: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Map.prototype.delete called on incompatible receiver'));

  if Length(AArgs) > 0 then k := AArgs[0] else k := JSMakeUndefined();
  Result := JSMakeBoolean(TFloriaJSMap(AThis.ObjVal).DeleteItem(k));
end;

function JSMapClear(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Map.prototype.clear called on incompatible receiver'));

  TFloriaJSMap(AThis.ObjVal).Clear();
  Result := JSMakeUndefined();
end;

function JSMapGroupBy(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
  items, callback, item, keyVal, group: TFloriaJSValue;
  map: TFloriaJSMap;
  arr: TFloriaJSArray;
  i, len: Integer;
  cbArgs: array[0..1] of TFloriaJSValue;
begin
  heap := JSActiveRealmHeap();
  if heap = nil then
    Exit(JSMakeUndefined());
  if (Length(AArgs) < 2) or not AArgs[1].IsFunction() then
    raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
      'Map.groupBy requires a callable callback')));
  items := AArgs[0];
  callback := AArgs[1];

  map := TFloriaJSMap(heap.Track(TFloriaJSMap.Create(GSharedMapProto)));
  if items.IsArray() then
  begin
    arr := items.AsArray();
    len := arr.Length();
    for i := 0 to len - 1 do
    begin
      item := arr.GetElement(i);
      cbArgs[0] := item;
      cbArgs[1] := JSMakeNumber(i);
      keyVal := heap.InvokeFunction(callback, cbArgs, JSMakeUndefined());
      group := map.GetItem(keyVal);
      if not group.IsArray() then
      begin
        group := JSMakeArray(heap.NewArray());
        map.SetItem(keyVal, group);
      end;
      group.AsArray().Push(item);
    end;
  end;
  Result := JSMakeObject(map);
end;

function JSMapGetSize(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    Exit(JSMakeNumber(0));
  Result := JSMakeNumber(TFloriaJSMap(AThis.ObjVal).GetSize());
end;

function JSMapKeys(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  h: TFloriaJSHeap;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Map.prototype.keys called on incompatible receiver'));

  h := GetHeap(AThis);
  Result := JSMakeObject(h.Track(TFloriaJSIterator.Create(h, fikMapKeys, AThis)));
end;

function JSMapValues(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  h: TFloriaJSHeap;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Map.prototype.values called on incompatible receiver'));

  h := GetHeap(AThis);
  Result := JSMakeObject(h.Track(TFloriaJSIterator.Create(h, fikMapValues, AThis)));
end;

function JSMapEntries(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  h: TFloriaJSHeap;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSMap) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Map.prototype.entries called on incompatible receiver'));

  h := GetHeap(AThis);
  Result := JSMakeObject(h.Track(TFloriaJSIterator.Create(h, fikMapEntries, AThis)));
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
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Map.prototype.forEach called on incompatible receiver'));

  if (Length(AArgs) = 0) or not AArgs[0].IsFunction() then
    raise EFloriaJSThrow.Create(WeakCollectionError('Callback must be a function'));

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
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Set.prototype.add called on incompatible receiver'));

  if Length(AArgs) > 0 then v := AArgs[0] else v := JSMakeUndefined();
  TFloriaJSSet(AThis.ObjVal).AddItem(v);
  Result := AThis;
end;

function JSSetHas(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  v: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Set.prototype.has called on incompatible receiver'));

  if Length(AArgs) > 0 then v := AArgs[0] else v := JSMakeUndefined();
  Result := JSMakeBoolean(TFloriaJSSet(AThis.ObjVal).HasItem(v));
end;

function JSSetDelete(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  v: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Set.prototype.delete called on incompatible receiver'));

  if Length(AArgs) > 0 then v := AArgs[0] else v := JSMakeUndefined();
  Result := JSMakeBoolean(TFloriaJSSet(AThis.ObjVal).DeleteItem(v));
end;

function JSSetClear(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Set.prototype.clear called on incompatible receiver'));

  TFloriaJSSet(AThis.ObjVal).Clear();
  Result := JSMakeUndefined();
end;

function JSSetGetSize(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    Exit(JSMakeNumber(0));
  Result := JSMakeNumber(TFloriaJSSet(AThis.ObjVal).GetSize());
end;

function TFloriaJSSet.PruneWeakEntries(): Boolean;
begin
  Result := PruneDeadValues();
end;

function JSSetValues(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  h: TFloriaJSHeap;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Set.prototype.values called on incompatible receiver'));

  h := GetHeap(AThis);
  Result := JSMakeObject(h.Track(TFloriaJSIterator.Create(h, fikSetValues, AThis)));
end;

function JSSetEntries(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  h: TFloriaJSHeap;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSSet) then
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Set.prototype.entries called on incompatible receiver'));

  h := GetHeap(AThis);
  Result := JSMakeObject(h.Track(TFloriaJSIterator.Create(h, fikSetEntries, AThis)));
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
    raise EFloriaJSThrow.Create(WeakCollectionError('Method Set.prototype.forEach called on incompatible receiver'));

  if (Length(AArgs) = 0) or not AArgs[0].IsFunction() then
    raise EFloriaJSThrow.Create(WeakCollectionError('Callback must be a function'));

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


{ TFloriaJSIterator }

constructor TFloriaJSIterator.Create(AHeap: TFloriaJSHeap; AKind: TFloriaJSIterKind;
  const ASource: TFloriaJSValue);
begin
  if AHeap <> nil then
    inherited Create(AHeap.GetObjectPrototype())
  else
    inherited Create(nil);
  Heap := AHeap;
  FKind := AKind;
  FSource := ASource;
  FCursor := 0;
  FDone := False;
  FNextFn := nil;
  FSelfIteratorFn := nil;
  { The iterator holds its source for as long as it is reachable. }
  JSRetainValue(FSource);
end;

destructor TFloriaJSIterator.Destroy();
begin
  { During a full heap clear the source may already have been freed; the
    clearing flag tells every object to skip reference releases. }
  if (Heap = nil) or (not Heap.IsClearing) then
    JSReleaseValue(FSource);
  inherited Destroy();
end;

{ Produces the next value, advancing the cursor. Returns False when exhausted. }
function TFloriaJSIterator.Step(out AValue: TFloriaJSValue): Boolean;
begin
  { An iterator that has reported `done` stays done, even if the source grows
    afterwards. }
  if FDone then
  begin
    AValue := JSMakeUndefined();
    Exit(False);
  end;
  Result := Produce(AValue);
  if not Result then
    FDone := True;
end;

function TFloriaJSIterator.Produce(out AValue: TFloriaJSValue): Boolean;
var
  arr: TFloriaJSArray;
  map: TFloriaJSMap;
  setObj: TFloriaJSSet;
  str: string;
  pair: TFloriaJSArray;
  re: TFloriaJSRegExp;
begin
  AValue := JSMakeUndefined();

  case FKind of
    fikRegExpMatches:
      begin
        { The source is [regexp, string]; each step runs the regexp once. }
        if not FSource.IsArray() then
          Exit(False);
        arr := FSource.AsArray();
        if (arr.Length() < 2) or not arr.GetElement(0).IsObject() or
           not (arr.GetElement(0).ObjVal is TFloriaJSRegExp) then
          Exit(False);
        re := TFloriaJSRegExp(arr.GetElement(0).ObjVal);
        AValue := re.Exec(arr.GetElement(1).StrVal, Heap);
        Exit(not AValue.IsNull());
      end;

    fikArray, fikArrayKeys, fikArrayEntries, fikString:
      begin
        if FKind = fikString then
        begin
          str := FSource.StrVal;
          if FCursor >= JSUTF16Length(str) then
            Exit(False);
          { The string iterator yields code points, keeping a surrogate pair as
            one yielded value. }
          AValue := JSMakeString(JSUTF16NextCodePoint(str, FCursor));
          Exit(AValue.IsString() and (AValue.StrVal <> ''));
        end;

        if not FSource.IsArray() then
          Exit(False);
        arr := FSource.AsArray();
        if FCursor >= arr.Length() then
          Exit(False);
        if FKind = fikArrayKeys then
          AValue := JSMakeNumber(FCursor)
        else if FKind = fikArrayEntries then
        begin
          pair := Heap.NewArray();
          pair.Push(JSMakeNumber(FCursor));
          pair.Push(arr.GetElement(FCursor));
          AValue := JSMakeObject(pair);
        end
        else
          AValue := arr.GetElement(FCursor);
        Inc(FCursor);
        Exit(True);
      end;

    fikMapKeys, fikMapValues, fikMapEntries:
      begin
        if not FSource.IsObject() or not (FSource.ObjVal is TFloriaJSMap) then
          Exit(False);
        map := TFloriaJSMap(FSource.ObjVal);
        if FCursor >= map.Size then
          Exit(False);

        case FKind of
          fikMapKeys:
            AValue := map.Entries[FCursor].Key;
          fikMapValues:
            AValue := map.Entries[FCursor].Value;
        else
          pair := Heap.NewArray();
          pair.Push(map.Entries[FCursor].Key);
          pair.Push(map.Entries[FCursor].Value);
          AValue := JSMakeObject(pair);
        end;
        Inc(FCursor);
        Exit(True);
      end;

    fikSetValues, fikSetEntries:
      begin
        if not FSource.IsObject() or not (FSource.ObjVal is TFloriaJSSet) then
          Exit(False);
        setObj := TFloriaJSSet(FSource.ObjVal);
        if FCursor >= setObj.Size then
          Exit(False);

        if FKind = fikSetEntries then
        begin
          { Set entries yield [value, value], as ECMAScript specifies. }
          pair := Heap.NewArray();
          pair.Push(setObj.GetItem(FCursor));
          pair.Push(setObj.GetItem(FCursor));
          AValue := JSMakeObject(pair);
        end
        else
          AValue := setObj.GetItem(FCursor);
        Inc(FCursor);
        Exit(True);
      end;
  end;

  Result := False;
end;

function TFloriaJSIterator.Next(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  resultObj: TFloriaJSObject;
  value: TFloriaJSValue;
begin
  resultObj := Heap.NewObject(Heap.GetObjectPrototype());
  if Step(value) then
  begin
    resultObj.SetProperty('value', value);
    resultObj.SetProperty('done', JSMakeBoolean(False));
  end
  else
  begin
    resultObj.SetProperty('value', JSMakeUndefined());
    resultObj.SetProperty('done', JSMakeBoolean(True));
  end;
  Result := JSMakeObject(resultObj);
end;

function TFloriaJSIterator.SelfIterator(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  { An iterator is itself iterable, so it can be used directly in `for…of`. }
  Result := JSMakeObject(Self);
end;

function TFloriaJSIterator.GetPropertyWithReceiver(const AName: string;
  AReceiver: TFloriaJSObject): TFloriaJSValue;
begin
  if AName = 'next' then
  begin
    if (FNextFn = nil) and (Heap <> nil) then
      FNextFn := Heap.NewNativeMethod('next', @Self.Next);
    Exit(JSMakeFunction(FNextFn));
  end;

  { The well-known iterator symbol, in whichever key form it arrives. }
  if JSIsWellKnownSymbolKey(AName, 'Symbol.iterator') then
  begin
    if (FSelfIteratorFn = nil) and (Heap <> nil) then
      FSelfIteratorFn := Heap.NewNativeMethod('[Symbol.iterator]', @Self.SelfIterator);
    Exit(JSMakeFunction(FSelfIteratorFn));
  end;

  Result := inherited GetPropertyWithReceiver(AName, AReceiver);
end;

function TFloriaJSIterator.HasProperty(const AName: string): Boolean;
begin
  if (AName = 'next') or JSIsWellKnownSymbolKey(AName, 'Symbol.iterator') then
    Exit(True);
  Result := inherited HasProperty(AName);
end;

function JSArrayValues(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  h: TFloriaJSHeap;
begin
  if AThis.IsNull() or AThis.IsUndefined() then
  begin
    h := JSActiveRealmHeap();
    if h = nil then h := GSharedCollectionsHeap;
    if h <> nil then
      raise EFloriaJSThrow.Create(JSMakeObject(h.NewError('TypeError',
        'Array.prototype.values called on null or undefined')));
    Exit(JSMakeUndefined());
  end;
  h := GetHeap(AThis);
  if h = nil then
    Exit(JSMakeUndefined());
  Result := JSMakeObject(h.Track(
    TFloriaJSIterator.Create(h, fikArray, AThis)));
end;

function JSArrayKeys(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  h: TFloriaJSHeap;
begin
  if AThis.IsNull() or AThis.IsUndefined() then
  begin
    h := JSActiveRealmHeap();
    if h = nil then h := GSharedCollectionsHeap;
    if h <> nil then
      raise EFloriaJSThrow.Create(JSMakeObject(h.NewError('TypeError',
        'Array.prototype.keys called on null or undefined')));
    Exit(JSMakeUndefined());
  end;
  h := GetHeap(AThis);
  if h = nil then
    Exit(JSMakeUndefined());
  Result := JSMakeObject(h.Track(
    TFloriaJSIterator.Create(h, fikArrayKeys, AThis)));
end;

function JSArrayEntries(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  h: TFloriaJSHeap;
begin
  if AThis.IsNull() or AThis.IsUndefined() then
  begin
    h := JSActiveRealmHeap();
    if h = nil then h := GSharedCollectionsHeap;
    if h <> nil then
      raise EFloriaJSThrow.Create(JSMakeObject(h.NewError('TypeError',
        'Array.prototype.entries called on null or undefined')));
    Exit(JSMakeUndefined());
  end;
  h := GetHeap(AThis);
  if h = nil then
    Exit(JSMakeUndefined());
  Result := JSMakeObject(h.Track(
    TFloriaJSIterator.Create(h, fikArrayEntries, AThis)));
end;

function JSGetIterator(AHeap: TFloriaJSHeap; const AValue: TFloriaJSValue;
  out AIterator: TFloriaJSIterator): Boolean;
begin
  AIterator := nil;
  if AHeap = nil then
    Exit(False);

  if AValue.IsArray() then
  begin
    AIterator := TFloriaJSIterator(AHeap.Track(
      TFloriaJSIterator.Create(AHeap, fikArray, AValue)));
    Exit(True);
  end;

  if AValue.IsString() then
  begin
    AIterator := TFloriaJSIterator(AHeap.Track(
      TFloriaJSIterator.Create(AHeap, fikString, AValue)));
    Exit(True);
  end;

  if AValue.IsObject() and (AValue.ObjVal is TFloriaJSIterator) then
  begin
    AIterator := TFloriaJSIterator(AValue.ObjVal);
    Exit(True);
  end;

  if AValue.IsObject() and (AValue.ObjVal is TFloriaJSMap) then
  begin
    AIterator := TFloriaJSIterator(AHeap.Track(
      TFloriaJSIterator.Create(AHeap, fikMapEntries, AValue)));
    Exit(True);
  end;

  if AValue.IsObject() and (AValue.ObjVal is TFloriaJSSet) then
  begin
    AIterator := TFloriaJSIterator(AHeap.Track(
      TFloriaJSIterator.Create(AHeap, fikSetValues, AValue)));
    Exit(True);
  end;

  Result := False;
end;

function JSIteratorNext(const AIterator: TFloriaJSIterator;
  out AValue: TFloriaJSValue): Boolean;
begin
  AValue := JSMakeUndefined();
  if AIterator = nil then
    Exit(False);
  Result := AIterator.Step(AValue);
end;

function JSIteratorToArray(const AIterator: TFloriaJSIterator): TFloriaJSArray;
var
  value: TFloriaJSValue;
  heap: TFloriaJSHeap;
begin
  heap := nil;
  if (AIterator <> nil) then
    heap := AIterator.Heap;
  if heap <> nil then
    Result := heap.NewArray()
  else
    Result := TFloriaJSArray.Create();

  while JSIteratorNext(AIterator, value) do
    Result.Push(value);
end;

procedure FloriaJSRegisterCollections(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  mapCtor, setCtor, groupByFn: TFloriaJSFunction;
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
  GSharedMapProto.DefineDataProperty('constructor', JSMakeFunction(mapCtor), True, False, True);
  groupByFn := AHeap.NewNativeFunction('groupBy', @JSMapGroupBy);
  groupByFn.NotConstructable := True;
  groupByFn.SuppressPrototype := True;
  groupByFn.LengthOverride := 2;
  mapCtor.DefineDataProperty('groupBy', JSMakeFunction(groupByFn), True, False, True);
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
  GSharedSetProto.DefineDataProperty('constructor', JSMakeFunction(setCtor), True, False, True);
  AEnv.Define('Set', JSMakeFunction(setCtor));
end;

end.
