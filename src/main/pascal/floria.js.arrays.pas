{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Built-in Array Methods                          }
{                                                                          }
{   Implements the JavaScript-visible Array prototype and the Array global  }
{   object. Callback-based methods (map, filter, sort, ...) reach user      }
{   functions through the heap's function invoker, which the VM            }
{   installs, so this unit does not depend on the VM.                      }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.arrays;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, floria.js.types, floria.js.value, floria.js.env,
  floria.js.collections, floria.js.utf16;

procedure FloriaJSRegisterArray(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);

implementation

function ThisArray(const AThis: TFloriaJSValue): TFloriaJSArray;
begin
  Result := AThis.AsArray();
end;

{ Copies the receiver, preserving holes, into a fresh array. }
function CopyArray(AArr: TFloriaJSArray): TFloriaJSArray;
var
  i: Integer;
begin
  Result := AArr.Heap.NewArray();
  for i := 0 to AArr.Length() - 1 do
  begin
    if AArr.HasElement(i) then
      Result.Push(AArr.GetElement(i))
    else
      Result.PushHole();
  end;
end;

{ ToLength for a generic array-like receiver. }
function ArrayLikeLength(const AThis: TFloriaJSValue): Integer;
var
  d: Double;
  heap: TFloriaJSHeap;
begin
  if AThis.IsArray() then
    Exit(AThis.AsArray().Length());
  if AThis.IsString() then
    Exit(JSUTF16Length(AThis.StrVal));
  if not AThis.IsObject() then
    Exit(0);
  if AThis.AsObject().GetProperty('length').IsSymbol() then
  begin
    heap := AThis.AsObject().Heap;
    if heap = nil then heap := JSActiveRealmHeap();
    if heap <> nil then
      raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
        'Cannot convert a Symbol value to a number')));
    Exit(0);
  end;
  d := AThis.AsObject().GetProperty('length').ToNumber();
  if IsNaN(d) or (d <= 0) then
    Exit(0);
  { An array length above 2^32 - 1 is a RangeError. }
  if d > 4294967295.0 then
  begin
    heap := AThis.AsObject().Heap;
    if heap = nil then heap := JSActiveRealmHeap();
    if heap <> nil then
      raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('RangeError',
        'Invalid array length')));
    Exit(0);
  end;
  if d >= 2147483647.0 then
    Exit(2147483647);
  Result := Trunc(d);
end;

function ArrayLikeGet(const AThis: TFloriaJSValue; AIndex: Integer): TFloriaJSValue;
begin
  if AThis.IsArray() then
    Exit(AThis.AsArray().GetElement(AIndex));
  if AThis.IsString() then
    Exit(JSMakeString(JSUTF16CharAt(AThis.StrVal, AIndex)));
  if AThis.IsObject() then
    Exit(AThis.AsObject().GetProperty(IntToStr(AIndex)));
  Result := JSMakeUndefined();
end;

{ ToLength for findLast/findLastIndex: clamped to 2^53 - 1, not 2^32 - 1. }
function ArrayLikeLength64(const AThis: TFloriaJSValue): Int64;
var
  d: Double;
begin
  if AThis.IsArray() then
    Exit(AThis.AsArray().Length());
  if AThis.IsString() then
    Exit(JSUTF16Length(AThis.StrVal));
  if not AThis.IsObject() then
    Exit(0);
  if AThis.AsObject().GetProperty('length').IsSymbol() then
    raise EFloriaJSThrow.Create(JSMakeObject(AThis.AsObject().Heap.NewError('TypeError',
      'Cannot convert a Symbol value to a number')));
  d := AThis.AsObject().GetProperty('length').ToNumber();
  if IsNaN(d) or (d <= 0) then
    Exit(0);
  if d >= 9007199254740991.0 then
    Exit(9007199254740991);
  Result := Trunc(d);
end;

{ Materialises a generic array-like into a fresh array. A real array keeps its
  holes; any other receiver has no holes. }
function MaterializeArrayLike(const AThis: TFloriaJSValue): TFloriaJSArray;
var
  len, i: Integer;
  heap: TFloriaJSHeap;
  arr: TFloriaJSArray;
begin
  if AThis.IsNull() or AThis.IsUndefined() then
  begin
    heap := JSActiveRealmHeap();
    if heap <> nil then
      raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
        'Array method called on null or undefined')));
    Exit(nil);
  end;
  if AThis.IsObject() then
    heap := AThis.AsObject().Heap
  else
    heap := JSActiveRealmHeap();
  if heap = nil then
    Exit(nil);
  Result := heap.NewArray();
  if AThis.IsArray() then
  begin
    { These methods read through Get, so a hole becomes undefined. }
    arr := AThis.AsArray();
    for i := 0 to arr.Length() - 1 do
      Result.Push(arr.GetElement(i));
    Exit;
  end;
  len := ArrayLikeLength(AThis);
  for i := 0 to len - 1 do
    Result.Push(ArrayLikeGet(AThis, i));
end;

function NumberToInt(const AValue: TFloriaJSValue): Integer;
var
  d: Double;
begin
  d := AValue.ToNumber();
  if IsNaN(d) then
    Exit(0);
  if d >= 2147483647.0 then
    Exit(2147483647);
  if d <= -2147483648.0 then
    Exit(-2147483648);
  Result := Trunc(d);
end;

function IntArg(const AArgs: array of TFloriaJSValue; AIndex, ADefault: Integer): Integer;
begin
  if AIndex > High(AArgs) then
    Exit(ADefault);
  if AArgs[AIndex].IsUndefined() then
    Exit(ADefault);
  Result := NumberToInt(AArgs[AIndex]);
end;

function NormalizeIndex(AIndex, ALen: Integer): Integer;
begin
  if AIndex < 0 then
  begin
    Result := ALen + AIndex;
    if Result < 0 then Result := 0;
  end
  else if AIndex > ALen then
    Result := ALen
  else
    Result := AIndex;
end;

function SameValueZero(const ALeft, ARight: TFloriaJSValue): Boolean;
begin
  { NaN is considered equal to itself by includes/indexOf-style lookups that
    use SameValueZero, unlike the strict equality operator. }
  if ALeft.IsNumber() and ARight.IsNumber() then
  begin
    if IsNaN(ALeft.ToNumber()) and IsNaN(ARight.ToNumber()) then
      Exit(True);
  end;
  Result := JSStrictEqual(ALeft, ARight);
end;

{ ArraySpeciesCreate for the diagnostic subset. The result is a new array whose
  prototype follows an explicit species constructor. When the species is
  another realm's Array intrinsic, ECMAScript falls back to the current realm's
  Array.prototype; that case is preserved here. }
function ArraySpeciesCreate(AHeap: TFloriaJSHeap; AArr: TFloriaJSArray;
  const ALength: Integer): TFloriaJSArray;
var
  ctorVal, speciesVal, realmArray, speciesSymbol: TFloriaJSValue;
  speciesFn: TFloriaJSFunction;
  proto: TFloriaJSObject;
begin
  Result := AHeap.NewArray();
  Result.SetLengthTo(ALength);
  if AArr = nil then Exit;

  ctorVal := AArr.GetProperty('constructor');
  if not ctorVal.IsFunction() then Exit;

  { If the constructor is another realm's Array intrinsic, ECMAScript treats it
    as undefined before reading @@species. This also avoids invoking a species
    getter that the test expects not to run. }
  speciesFn := ctorVal.AsFunction();
  if (speciesFn.Heap <> nil) and (speciesFn.Heap <> AHeap) and
     (speciesFn.Heap.RealmGlobal <> nil) then
  begin
    realmArray := speciesFn.Heap.RealmGlobal.GetProperty('Array');
    if realmArray.IsFunction() and (realmArray.ObjVal = speciesFn) then
      Exit;
  end;

  { Resolve the well-known Symbol.species key in this heap's realm. }
  speciesSymbol := JSMakeUndefined();
  if AHeap.RealmGlobal <> nil then
  begin
    speciesSymbol := AHeap.RealmGlobal.GetProperty('Symbol');
    if speciesSymbol.IsFunction() then
      speciesSymbol := speciesSymbol.AsFunction().GetProperty('species');
  end;

  if speciesSymbol.IsSymbol() then
    speciesVal := ctorVal.AsFunction().GetProperty(JSPropertyKeyName(speciesSymbol))
  else
    speciesVal := ctorVal.AsFunction().GetProperty('Symbol(Symbol.species)');
  if not speciesVal.IsFunction() then Exit;

  speciesFn := speciesVal.AsFunction();

  proto := AHeap.GetPrototypeFromConstructor(speciesVal, 'Array');
  if proto <> nil then
    Result.Prototype := proto;
end;

procedure RequireCallback(AHeap: TFloriaJSHeap; const ACallback: TFloriaJSValue;
  const AMethod: string);
begin
  if not ACallback.IsFunction() then
    raise EFloriaJSThrow.Create(JSMakeObject(
      AHeap.NewError('TypeError', AMethod + ' callback is not a function')));
end;

function CompareValues(AHeap: TFloriaJSHeap; const AComparator: TFloriaJSValue;
  const ALeft, ARight: TFloriaJSValue): Integer;
var
  res: TFloriaJSValue;
  d: Double;
  args: array[0..1] of TFloriaJSValue;
begin
  if AComparator.IsFunction() then
  begin
    args[0] := ALeft;
    args[1] := ARight;
    res := AHeap.InvokeFunction(AComparator, args, JSMakeUndefined());
    d := res.ToNumber();
    if IsNaN(d) then
      Exit(0);
    if d < 0 then
      Exit(-1);
    if d > 0 then
      Exit(1);
    Exit(0);
  end;

  { The default sort compares the string forms of the elements. }
  Result := CompareStr(ALeft.ToString(), ARight.ToString());
end;

{ Mutating methods }

function JSArrayPush(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  i: Integer;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  for i := 0 to High(AArgs) do
    arr.Push(AArgs[i]);

  Result := JSMakeNumber(arr.Length());
end;

function JSArrayPop(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());
  Result := arr.Pop();
end;

function JSArrayShift(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());
  Result := arr.Shift();
end;

function JSArrayUnshift(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  i: Integer;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  { unshift(a, b) puts a before b, so the arguments are inserted backwards. }
  for i := High(AArgs) downto 0 do
    arr.Unshift(AArgs[i]);

  Result := JSMakeNumber(arr.Length());
end;

function JSArrayReverse(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  i, j: Integer;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  i := 0;
  j := arr.Length() - 1;
  while i < j do
  begin
    { Swapping the slots keeps holes at the mirrored positions. }
    arr.SwapElements(i, j);
    Inc(i);
    Dec(j);
  end;

  Result := AThis;
end;

function JSArraySort(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  comparator: TFloriaJSValue;
  values: array of TFloriaJSValue;
  n, present, count, i, j: Integer;
  key: TFloriaJSValue;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  n := arr.Length();
  present := 0;
  for i := 0 to n - 1 do
    if arr.HasElement(i) then
      Inc(present);

  if present > 1 then
  begin
    SetLength(values, present);
    count := 0;
    for i := 0 to n - 1 do
      if arr.HasElement(i) then
      begin
        values[count] := arr.GetElement(i);
        Inc(count);
      end;

    comparator := JSMakeUndefined();
    if Length(AArgs) > 0 then
      comparator := AArgs[0];

    { Insertion sort keeps the implementation simple and preserves the order
      of elements that compare equal. }
    for i := 1 to present - 1 do
    begin
      key := values[i];
      j := i - 1;
      while (j >= 0) and (CompareValues(arr.Heap, comparator, values[j], key) > 0) do
      begin
        values[j + 1] := values[j];
        Dec(j);
      end;
      values[j + 1] := key;
    end;

    { The elements are written densely; ECMAScript sorts holes to the end. }
    for i := 0 to present - 1 do
      arr.SetElement(i, values[i]);
    for i := present to n - 1 do
      arr.MarkHole(i);
  end;

  Result := AThis;
end;

function JSArraySplice(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr, removed: TFloriaJSArray;
  start, deleteCount, count, i: Integer;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  start := NormalizeIndex(IntArg(AArgs, 0, 0), arr.Length());

  if Length(AArgs) <= 1 then
    deleteCount := arr.Length() - start
  else
    deleteCount := NumberToInt(AArgs[1]);

  if deleteCount < 0 then deleteCount := 0;
  if deleteCount > arr.Length() - start then
    deleteCount := arr.Length() - start;

  removed := ArraySpeciesCreate(arr.Heap, arr, 0);
  for i := 1 to deleteCount do
  begin
    { splice preserves holes in the removed slice. }
    if arr.HasElement(start) then
      removed.Push(arr.GetElement(start))
    else
      removed.PushHole();
    arr.RemoveAt(start);
  end;

  count := Length(AArgs) - 2;
  for i := 0 to count - 1 do
    arr.InsertAt(start + i, AArgs[i + 2]);

  Result := JSMakeArray(removed);
end;

{ Non-mutating accessors }

{ ToLength for the generic array-like path: negative and NaN become 0. }
function JoinLength(const AValue: TFloriaJSValue): Integer;
var
  d: Double;
begin
  d := AValue.ToNumber();
  if IsNaN(d) or (d <= 0) then
    Exit(0);
  if d >= 2147483647.0 then
    Exit(2147483647);
  Result := Trunc(d);
end;

function JSArrayJoin(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  separator: string;
  obj: TFloriaJSObject;
  len, i: Integer;
  elem: TFloriaJSValue;
  sb: TStringBuilder;
  heap: TFloriaJSHeap;
begin
  if AThis.IsNull() or AThis.IsUndefined() then
  begin
    heap := JSActiveRealmHeap();
    if heap <> nil then
      raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
        'Array.prototype.join called on null or undefined')));
    Exit(JSMakeUndefined());
  end;

  separator := ',';
  if (Length(AArgs) > 0) and not AArgs[0].IsUndefined() then
    separator := JSToString(AArgs[0]);

  { The fast path for a real array. }
  arr := AThis.AsArray();
  if arr <> nil then
    Exit(JSMakeString(arr.Join(separator)));

  { join is intentionally generic: any array-like with a `length` and indexed
    properties works, including strings and plain objects. }
  if AThis.IsString() then
  begin
    sb := TStringBuilder.Create();
    try
      len := JSUTF16Length(AThis.StrVal);
      for i := 0 to len - 1 do
      begin
        if i > 0 then sb.Append(separator);
        sb.Append(JSUTF16CharAt(AThis.StrVal, i));
      end;
      Result := JSMakeString(sb.ToString());
    finally
      sb.Free();
    end;
    Exit;
  end;

  if not AThis.IsObject() then
    Exit(JSMakeString(''));

  obj := AThis.AsObject();
  len := JoinLength(obj.GetProperty('length'));
  sb := TStringBuilder.Create();
  try
    for i := 0 to len - 1 do
    begin
      if i > 0 then sb.Append(separator);
      elem := obj.GetProperty(IntToStr(i));
      if not (elem.IsUndefined() or elem.IsNull()) then
        sb.Append(JSToString(elem));
    end;
    Result := JSMakeString(sb.ToString());
  finally
    sb.Free();
  end;
end;

function JSArrayToString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSArrayJoin([], AThis);
end;

function JSArrayConcat(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr, res, other: TFloriaJSArray;
  i, k: Integer;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  res := ArraySpeciesCreate(arr.Heap, arr, 0);
  for i := 0 to arr.Length() - 1 do
  begin
    { concat preserves the holes of the source array. }
    if arr.HasElement(i) then
      res.Push(arr.GetElement(i))
    else
      res.PushHole();
  end;

  for i := 0 to High(AArgs) do
  begin
    if AArgs[i].IsArray() then
    begin
      other := AArgs[i].AsArray();
      if other <> nil then
        for k := 0 to other.Length() - 1 do
        begin
          if other.HasElement(k) then
            res.Push(other.GetElement(k))
          else
            res.PushHole();
        end;
    end
    else
      res.Push(AArgs[i]);
  end;

  Result := JSMakeArray(res);
end;

function JSArraySlice(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr, res: TFloriaJSArray;
  start, finish, i: Integer;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  start := NormalizeIndex(IntArg(AArgs, 0, 0), arr.Length());
  finish := NormalizeIndex(IntArg(AArgs, 1, arr.Length()), arr.Length());

  res := ArraySpeciesCreate(arr.Heap, arr, 0);
  for i := start to finish - 1 do
  begin
    { slice copies holes as holes. }
    if arr.HasElement(i) then
      res.Push(arr.GetElement(i))
    else
      res.PushHole();
  end;

  Result := JSMakeArray(res);
end;

function JSArrayIndexOf(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  needle: TFloriaJSValue;
  i, start: Integer;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  needle := JSMakeUndefined();
  if Length(AArgs) > 0 then needle := AArgs[0];

  start := IntArg(AArgs, 1, 0);
  if start < 0 then
  begin
    start := arr.Length() + start;
    if start < 0 then start := 0;
  end;

  for i := start to arr.Length() - 1 do
    if arr.HasElement(i) and JSStrictEqual(arr.GetElement(i), needle) then
      Exit(JSMakeNumber(i));

  Result := JSMakeNumber(-1);
end;

function JSArrayLastIndexOf(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  needle: TFloriaJSValue;
  i, start: Integer;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  needle := JSMakeUndefined();
  if Length(AArgs) > 0 then needle := AArgs[0];

  start := IntArg(AArgs, 1, arr.Length() - 1);
  if start < 0 then
    start := arr.Length() + start
  else if start >= arr.Length() then
    start := arr.Length() - 1;

  { indexOf/lastIndexOf skip holes: they are not own properties. }
  for i := start downto 0 do
    if arr.HasElement(i) and JSStrictEqual(arr.GetElement(i), needle) then
      Exit(JSMakeNumber(i));

  Result := JSMakeNumber(-1);
end;

function JSArrayIncludes(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  needle: TFloriaJSValue;
  i, start: Integer;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  needle := JSMakeUndefined();
  if Length(AArgs) > 0 then needle := AArgs[0];

  start := IntArg(AArgs, 1, 0);
  if start < 0 then
  begin
    start := arr.Length() + start;
    if start < 0 then start := 0;
  end;

  for i := start to arr.Length() - 1 do
    if SameValueZero(arr.GetElement(i), needle) then
      Exit(JSMakeBoolean(True));

  Result := JSMakeBoolean(False);
end;

{ Callback-driven methods }


{ `Array.prototype.flat(depth = 1)` — flattens nested arrays. }
function JSArrayFlat(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  depth: Integer;

  procedure FlattenInto(const ASource: TFloriaJSArray; ALevel: Integer; ATarget: TFloriaJSArray);
  var
    i: Integer;
    item: TFloriaJSValue;
  begin
    for i := 0 to ASource.Length() - 1 do
    begin
      if not ASource.HasElement(i) then
        Continue;
      item := ASource.GetElement(i);
      if (ALevel > 0) and item.IsArray() then
        FlattenInto(item.AsArray(), ALevel - 1, ATarget)
      else
        ATarget.Push(item);
    end;
  end;

begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  depth := 1;
  if (Length(AArgs) > 0) and not AArgs[0].IsUndefined() then
    depth := Trunc(AArgs[0].ToNumber());
  if depth < 0 then depth := 0;

  Result := JSMakeArray(arr.Heap.NewArray());
  FlattenInto(arr, depth, Result.AsArray());
end;

{ `Array.prototype.flatMap(cb)` — map, then flatten one level. }
function JSArrayFlatMap(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  res: TFloriaJSArray;
  callback: TFloriaJSValue;
  i, j: Integer;
  mapped: TFloriaJSValue;
  cbArgs: array[0..2] of TFloriaJSValue;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  callback := JSMakeUndefined();
  if Length(AArgs) > 0 then callback := AArgs[0];
  RequireCallback(arr.Heap, callback, 'flatMap');

  res := arr.Heap.NewArray();
  for i := 0 to arr.Length() - 1 do
  begin
    if not arr.HasElement(i) then
      Continue;
    cbArgs[0] := arr.GetElement(i);
    cbArgs[1] := JSMakeNumber(i);
    cbArgs[2] := JSMakeArray(arr);
    mapped := arr.Heap.InvokeFunction(callback, cbArgs, JSMakeUndefined());
    { One level of flattening, as specified. }
    if mapped.IsArray() then
    begin
      for j := 0 to mapped.AsArray().Length() - 1 do
        if mapped.AsArray().HasElement(j) then
          res.Push(mapped.AsArray().GetElement(j));
    end
    else
      res.Push(mapped);
  end;
  Result := JSMakeArray(res);
end;

{ `Array.prototype.fill(value, start = 0, end = length)` — fills in place. }
function JSArrayFill(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  i, startIdx, endIdx, len: Integer;
  value: TFloriaJSValue;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  value := JSMakeUndefined();
  if Length(AArgs) > 0 then value := AArgs[0];

  len := arr.Length();
  startIdx := 0;
  if (Length(AArgs) > 1) and not AArgs[1].IsUndefined() then
  begin
    startIdx := Trunc(AArgs[1].ToNumber());
    if startIdx < 0 then
    begin
      Inc(startIdx, len);
      if startIdx < 0 then startIdx := 0;
    end;
  end;

  endIdx := len;
  if (Length(AArgs) > 2) and not AArgs[2].IsUndefined() then
  begin
    endIdx := Trunc(AArgs[2].ToNumber());
    if endIdx < 0 then
    begin
      Inc(endIdx, len);
      if endIdx < 0 then endIdx := 0;
    end;
    if endIdx > len then endIdx := len;
  end;

  for i := startIdx to endIdx - 1 do
    arr.SetElement(i, value);
  Result := AThis;
end;

{ `Array.prototype.copyWithin(target, start = 0, end = length)` — in place. }
function JSArrayCopyWithin(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  i, target, startIdx, endIdx, len: Integer;
  temp: TFloriaJSValueArray;
  count: Integer;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  len := arr.Length();
  target := 0;
  if (Length(AArgs) > 0) and not AArgs[0].IsUndefined() then
  begin
    target := Trunc(AArgs[0].ToNumber());
    if target < 0 then
    begin
      Inc(target, len);
      if target < 0 then target := 0;
    end;
  end;

  startIdx := 0;
  if (Length(AArgs) > 1) and not AArgs[1].IsUndefined() then
  begin
    startIdx := Trunc(AArgs[1].ToNumber());
    if startIdx < 0 then
    begin
      Inc(startIdx, len);
      if startIdx < 0 then startIdx := 0;
    end;
  end;

  endIdx := len;
  if (Length(AArgs) > 2) and not AArgs[2].IsUndefined() then
  begin
    endIdx := Trunc(AArgs[2].ToNumber());
    if endIdx < 0 then
    begin
      Inc(endIdx, len);
      if endIdx < 0 then endIdx := 0;
    end;
    if endIdx > len then endIdx := len;
  end;

  { Copy first: the ranges may overlap. }
  count := endIdx - startIdx;
  if count <= 0 then Exit(AThis);
  if target + count > len then count := len - target;
  if count <= 0 then Exit(AThis);

  SetLength(temp, count);
  for i := 0 to count - 1 do
    temp[i] := arr.GetElement(startIdx + i);
  for i := 0 to count - 1 do
    arr.SetElement(target + i, temp[i]);

  Result := AThis;
end;

{ `Array.prototype.at(i)` — supports negative indices. }
function JSArrayAt(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  idx: Integer;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  idx := 0;
  if Length(AArgs) > 0 then idx := Trunc(AArgs[0].ToNumber());
  if idx < 0 then idx := arr.Length() + idx;
  if (idx < 0) or (idx >= arr.Length()) then
    Exit(JSMakeUndefined());
  Result := arr.GetElement(idx);
end;

function JSArrayMap(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  res: TFloriaJSArray;
  callback, thisArg: TFloriaJSValue;
  i: Integer;
  cbArgs: array[0..2] of TFloriaJSValue;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  callback := JSMakeUndefined();
  if Length(AArgs) > 0 then callback := AArgs[0];
  RequireCallback(arr.Heap, callback, 'map');

  thisArg := JSMakeUndefined();
  if Length(AArgs) > 1 then thisArg := AArgs[1];

  res := ArraySpeciesCreate(arr.Heap, arr, 0);
  for i := 0 to arr.Length() - 1 do
  begin
    if not arr.HasElement(i) then
    begin
      { map skips holes and leaves a hole at the same index in the result. }
      res.PushHole();
      Continue;
    end;
    cbArgs[0] := arr.GetElement(i);
    cbArgs[1] := JSMakeNumber(i);
    cbArgs[2] := AThis;
    res.Push(arr.Heap.InvokeFunction(callback, cbArgs, thisArg));
  end;

  Result := JSMakeArray(res);
end;

function JSArrayFilter(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  res: TFloriaJSArray;
  callback, thisArg, element: TFloriaJSValue;
  i: Integer;
  cbArgs: array[0..2] of TFloriaJSValue;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  callback := JSMakeUndefined();
  if Length(AArgs) > 0 then callback := AArgs[0];
  RequireCallback(arr.Heap, callback, 'filter');

  thisArg := JSMakeUndefined();
  if Length(AArgs) > 1 then thisArg := AArgs[1];

  res := ArraySpeciesCreate(arr.Heap, arr, 0);
  for i := 0 to arr.Length() - 1 do
  begin
    if not arr.HasElement(i) then
      Continue;
    element := arr.GetElement(i);
    cbArgs[0] := element;
    cbArgs[1] := JSMakeNumber(i);
    cbArgs[2] := AThis;
    if arr.Heap.InvokeFunction(callback, cbArgs, thisArg).ToBoolean() then
      res.Push(element);
  end;

  Result := JSMakeArray(res);
end;

function JSArrayForEach(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  callback, thisArg: TFloriaJSValue;
  i: Integer;
  cbArgs: array[0..2] of TFloriaJSValue;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  callback := JSMakeUndefined();
  if Length(AArgs) > 0 then callback := AArgs[0];
  RequireCallback(arr.Heap, callback, 'forEach');

  thisArg := JSMakeUndefined();
  if Length(AArgs) > 1 then thisArg := AArgs[1];

  for i := 0 to arr.Length() - 1 do
  begin
    if not arr.HasElement(i) then
      Continue;
    cbArgs[0] := arr.GetElement(i);
    cbArgs[1] := JSMakeNumber(i);
    cbArgs[2] := AThis;
    arr.Heap.InvokeFunction(callback, cbArgs, thisArg);
  end;

  Result := JSMakeUndefined();
end;

function JSArraySome(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  callback, thisArg: TFloriaJSValue;
  i: Integer;
  cbArgs: array[0..2] of TFloriaJSValue;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  callback := JSMakeUndefined();
  if Length(AArgs) > 0 then callback := AArgs[0];
  RequireCallback(arr.Heap, callback, 'some');

  thisArg := JSMakeUndefined();
  if Length(AArgs) > 1 then thisArg := AArgs[1];

  for i := 0 to arr.Length() - 1 do
  begin
    if not arr.HasElement(i) then
      Continue;
    cbArgs[0] := arr.GetElement(i);
    cbArgs[1] := JSMakeNumber(i);
    cbArgs[2] := AThis;
    if arr.Heap.InvokeFunction(callback, cbArgs, thisArg).ToBoolean() then
      Exit(JSMakeBoolean(True));
  end;

  Result := JSMakeBoolean(False);
end;

function JSArrayEvery(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  callback, thisArg: TFloriaJSValue;
  i: Integer;
  cbArgs: array[0..2] of TFloriaJSValue;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  callback := JSMakeUndefined();
  if Length(AArgs) > 0 then callback := AArgs[0];
  RequireCallback(arr.Heap, callback, 'every');

  thisArg := JSMakeUndefined();
  if Length(AArgs) > 1 then thisArg := AArgs[1];

  for i := 0 to arr.Length() - 1 do
  begin
    if not arr.HasElement(i) then
      Continue;
    cbArgs[0] := arr.GetElement(i);
    cbArgs[1] := JSMakeNumber(i);
    cbArgs[2] := AThis;
    if not arr.Heap.InvokeFunction(callback, cbArgs, thisArg).ToBoolean() then
      Exit(JSMakeBoolean(False));
  end;

  Result := JSMakeBoolean(True);
end;

function JSArrayFind(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  callback, thisArg, element: TFloriaJSValue;
  i: Integer;
  cbArgs: array[0..2] of TFloriaJSValue;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  callback := JSMakeUndefined();
  if Length(AArgs) > 0 then callback := AArgs[0];
  RequireCallback(arr.Heap, callback, 'find');

  thisArg := JSMakeUndefined();
  if Length(AArgs) > 1 then thisArg := AArgs[1];

  for i := 0 to arr.Length() - 1 do
  begin
    element := arr.GetElement(i);
    cbArgs[0] := element;
    cbArgs[1] := JSMakeNumber(i);
    cbArgs[2] := AThis;
    if arr.Heap.InvokeFunction(callback, cbArgs, thisArg).ToBoolean() then
      Exit(element);
  end;

  Result := JSMakeUndefined();
end;

function JSArrayFindIndex(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  callback, thisArg: TFloriaJSValue;
  i: Integer;
  cbArgs: array[0..2] of TFloriaJSValue;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  callback := JSMakeUndefined();
  if Length(AArgs) > 0 then callback := AArgs[0];
  RequireCallback(arr.Heap, callback, 'findIndex');

  thisArg := JSMakeUndefined();
  if Length(AArgs) > 1 then thisArg := AArgs[1];

  for i := 0 to arr.Length() - 1 do
  begin
    cbArgs[0] := arr.GetElement(i);
    cbArgs[1] := JSMakeNumber(i);
    cbArgs[2] := AThis;
    if arr.Heap.InvokeFunction(callback, cbArgs, thisArg).ToBoolean() then
      Exit(JSMakeNumber(i));
  end;

  Result := JSMakeNumber(-1);
end;

function JSArrayFindLast(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
  callback, thisArg, element: TFloriaJSValue;
  i, len: Int64;
  cbArgs: array[0..2] of TFloriaJSValue;
begin
  if AThis.IsNull() or AThis.IsUndefined() then
  begin
    heap := JSActiveRealmHeap();
    if heap <> nil then
      raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
        'Array.prototype.findLast called on null or undefined')));
    Exit(JSMakeUndefined());
  end;
  if AThis.IsObject() then heap := AThis.AsObject().Heap else heap := JSActiveRealmHeap();
  if heap = nil then Exit(JSMakeUndefined());

  callback := JSMakeUndefined();
  if Length(AArgs) > 0 then callback := AArgs[0];
  RequireCallback(heap, callback, 'findLast');

  thisArg := JSMakeUndefined();
  if Length(AArgs) > 1 then thisArg := AArgs[1];

  len := ArrayLikeLength64(AThis);
  for i := len - 1 downto 0 do
  begin
    element := ArrayLikeGet(AThis, i);
    cbArgs[0] := element;
    cbArgs[1] := JSMakeNumber(i);
    cbArgs[2] := AThis;
    if heap.InvokeFunction(callback, cbArgs, thisArg).ToBoolean() then
      Exit(element);
  end;

  Result := JSMakeUndefined();
end;

function JSArrayFindLastIndex(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
  callback, thisArg: TFloriaJSValue;
  i, len: Int64;
  cbArgs: array[0..2] of TFloriaJSValue;
begin
  if AThis.IsNull() or AThis.IsUndefined() then
  begin
    heap := JSActiveRealmHeap();
    if heap <> nil then
      raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
        'Array.prototype.findLastIndex called on null or undefined')));
    Exit(JSMakeUndefined());
  end;
  if AThis.IsObject() then heap := AThis.AsObject().Heap else heap := JSActiveRealmHeap();
  if heap = nil then Exit(JSMakeUndefined());

  callback := JSMakeUndefined();
  if Length(AArgs) > 0 then callback := AArgs[0];
  RequireCallback(heap, callback, 'findLastIndex');

  thisArg := JSMakeUndefined();
  if Length(AArgs) > 1 then thisArg := AArgs[1];

  len := ArrayLikeLength64(AThis);
  for i := len - 1 downto 0 do
  begin
    cbArgs[0] := ArrayLikeGet(AThis, i);
    cbArgs[1] := JSMakeNumber(i);
    cbArgs[2] := AThis;
    if heap.InvokeFunction(callback, cbArgs, thisArg).ToBoolean() then
      Exit(JSMakeNumber(i));
  end;

  Result := JSMakeNumber(-1);
end;

function JSArrayToReversed(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  src, res: TFloriaJSArray;
  i: Integer;
begin
  src := MaterializeArrayLike(AThis);
  if src = nil then Exit(JSMakeUndefined());
  res := src.Heap.NewArray();
  for i := 0 to src.Length() - 1 do
    if src.HasElement(src.Length() - 1 - i) then
      res.Push(src.GetElement(src.Length() - 1 - i))
    else
      res.PushHole();
  Result := JSMakeArray(res);
end;

function JSArrayToSorted(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  res: TFloriaJSArray;
  comparator: TFloriaJSValue;
begin
  res := MaterializeArrayLike(AThis);
  if res = nil then Exit(JSMakeUndefined());
  comparator := JSMakeUndefined();
  if Length(AArgs) > 0 then comparator := AArgs[0];
  JSArraySort([comparator], JSMakeArray(res));
  Result := JSMakeArray(res);
end;

function JSArrayToSpliced(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  res: TFloriaJSArray;
  start, deleteCount, i: Integer;
  spliceArgs: array of TFloriaJSValue;
begin
  res := MaterializeArrayLike(AThis);
  if res = nil then Exit(JSMakeUndefined());

  start := NormalizeIndex(IntArg(AArgs, 0, 0), res.Length());
  if Length(AArgs) <= 1 then
    deleteCount := res.Length() - start
  else
    deleteCount := NumberToInt(AArgs[1]);
  if deleteCount < 0 then deleteCount := 0;
  if deleteCount > res.Length() - start then
    deleteCount := res.Length() - start;

  if Length(AArgs) > 2 then
    SetLength(spliceArgs, Length(AArgs))
  else
    SetLength(spliceArgs, 2);
  spliceArgs[0] := JSMakeNumber(start);
  spliceArgs[1] := JSMakeNumber(deleteCount);
  for i := 2 to High(AArgs) do
    spliceArgs[i] := AArgs[i];
  JSArraySplice(spliceArgs, JSMakeArray(res));
  Result := JSMakeArray(res);
end;

function JSArrayWith(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  res: TFloriaJSArray;
  idx, len: Integer;
  heap: TFloriaJSHeap;
begin
  res := MaterializeArrayLike(AThis);
  if res = nil then Exit(JSMakeUndefined());
  if Length(AArgs) < 2 then
    Exit(JSMakeUndefined());
  len := res.Length();
  idx := Trunc(AArgs[0].ToNumber());
  if idx < 0 then idx := len + idx;
  if (idx < 0) or (idx >= len) then
  begin
    heap := res.Heap;
    if heap <> nil then
      raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('RangeError',
        'Invalid index')));
    Exit(JSMakeUndefined());
  end;
  res.SetElement(idx, AArgs[1]);
  Result := JSMakeArray(res);
end;

function JSArrayReduce(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  callback, accumulator: TFloriaJSValue;
  i: Integer;
  hasAccumulator: Boolean;
  cbArgs: array[0..3] of TFloriaJSValue;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  callback := JSMakeUndefined();
  if Length(AArgs) > 0 then callback := AArgs[0];
  RequireCallback(arr.Heap, callback, 'reduce');

  hasAccumulator := Length(AArgs) > 1;
  if hasAccumulator then
    accumulator := AArgs[1];

  i := 0;
  while i < arr.Length() do
  begin
    { reduce skips holes. Without an initial value the first present element
      becomes the accumulator and the callback starts at the next one. }
    if arr.HasElement(i) then
    begin
      if not hasAccumulator then
      begin
        accumulator := arr.GetElement(i);
        hasAccumulator := True;
      end
      else
      begin
        cbArgs[0] := accumulator;
        cbArgs[1] := arr.GetElement(i);
        cbArgs[2] := JSMakeNumber(i);
        cbArgs[3] := AThis;
        accumulator := arr.Heap.InvokeFunction(callback, cbArgs, JSMakeUndefined());
      end;
    end;
    Inc(i);
  end;

  if not hasAccumulator then
    raise EFloriaJSThrow.Create(JSMakeObject(arr.Heap.NewError('TypeError', 'Reduce of empty array with no initial value')));

  Result := accumulator;
end;

function JSArrayReduceRight(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  callback, accumulator: TFloriaJSValue;
  i: Integer;
  hasAccumulator: Boolean;
  cbArgs: array[0..3] of TFloriaJSValue;
begin
  arr := ThisArray(AThis);
  if arr = nil then Exit(JSMakeUndefined());

  callback := JSMakeUndefined();
  if Length(AArgs) > 0 then callback := AArgs[0];
  RequireCallback(arr.Heap, callback, 'reduceRight');

  hasAccumulator := Length(AArgs) > 1;
  if hasAccumulator then
    accumulator := AArgs[1];

  i := arr.Length() - 1;
  while i >= 0 do
  begin
    if arr.HasElement(i) then
    begin
      if not hasAccumulator then
      begin
        accumulator := arr.GetElement(i);
        hasAccumulator := True;
      end
      else
      begin
        cbArgs[0] := accumulator;
        cbArgs[1] := arr.GetElement(i);
        cbArgs[2] := JSMakeNumber(i);
        cbArgs[3] := AThis;
        accumulator := arr.Heap.InvokeFunction(callback, cbArgs, JSMakeUndefined());
      end;
    end;
    Dec(i);
  end;

  if not hasAccumulator then
    raise EFloriaJSThrow.Create(JSMakeObject(arr.Heap.NewError('TypeError', 'Reduce of empty array with no initial value')));

  Result := accumulator;
end;

{ Array global object }

function JSArrayIsArray(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeBoolean((Length(AArgs) > 0) and AArgs[0].IsArray());
end;

function MaybeMap(AHeap: TFloriaJSHeap; const AMapFn, AMapThis, AItem: TFloriaJSValue;
  AIndex: Integer): TFloriaJSValue;
var
  cbArgs: array[0..1] of TFloriaJSValue;
begin
  if not AMapFn.IsFunction() then
    Exit(AItem);
  cbArgs[0] := AItem;
  cbArgs[1] := JSMakeNumber(AIndex);
  Result := AHeap.InvokeFunction(AMapFn, cbArgs, AMapThis);
end;

function JSArrayFrom(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
  res: TFloriaJSArray;
  source, mapFn, mapThis, item: TFloriaJSValue;
  i, len: Integer;
  obj: TFloriaJSObject;
  iter: TFloriaJSIterator;
begin
  { Static methods are called through the Array object, whose heap owns the
    new array. }
  if AThis.IsFunction() then
    heap := AThis.AsFunction().Heap
  else
    heap := nil;
  if heap = nil then Exit(JSMakeUndefined());

  res := heap.NewArray();
  res.Prototype := heap.GetPrototypeFromConstructor(AThis, 'Object');
  if Length(AArgs) = 0 then
    Exit(JSMakeArray(res));

  source := AArgs[0];
  mapFn := JSMakeUndefined();
  if Length(AArgs) > 1 then mapFn := AArgs[1];
  mapThis := JSMakeUndefined();
  if Length(AArgs) > 2 then mapThis := AArgs[2];

  { An iterator (including Map/Set) is consumed through the iteration protocol
    first; plain array-likes keep using `length`. }
  if JSGetIterator(heap, source, iter) then
  begin
    i := 0;
    while JSIteratorNext(iter, item) do
    begin
      res.Push(MaybeMap(heap, mapFn, mapThis, item, i));
      Inc(i);
    end;
  end
  else if source.IsObject() then
  begin
    obj := source.AsObject();
    len := NumberToInt(obj.GetProperty('length'));
    for i := 0 to len - 1 do
    begin
      item := obj.GetProperty(IntToStr(i));
      res.Push(MaybeMap(heap, mapFn, mapThis, item, i));
    end;
  end;

  Result := JSMakeArray(res);
end;

function JSArrayOf(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
  res: TFloriaJSArray;
  i: Integer;
begin
  if AThis.IsFunction() then
    heap := AThis.AsFunction().Heap
  else
    heap := nil;
  if heap = nil then Exit(JSMakeUndefined());

  res := heap.NewArray();
  res.Prototype := heap.GetPrototypeFromConstructor(AThis, 'Object');
  for i := 0 to High(AArgs) do
    res.Push(AArgs[i]);

  Result := JSMakeArray(res);
end;

procedure RegisterMethod(AHeap: TFloriaJSHeap; AProto: TFloriaJSObject;
  const AName: string; AProc: TFloriaJSNativeProc; ALength: Integer = -1);
var
  fn: TFloriaJSFunction;
begin
  fn := AHeap.NewNativeFunction(AName, AProc);
  { A prototype method is not a constructor, has no `prototype` property, is a
    non-enumerable own property, and has a fixed `length`. }
  fn.NotConstructable := True;
  fn.SuppressPrototype := True;
  fn.LengthOverride := ALength;
  AProto.DefineDataProperty(AName, JSMakeFunction(fn), True, False, True);
end;

procedure FloriaJSRegisterArray(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  proto: TFloriaJSObject;
  arrayObj: TFloriaJSFunction;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;

  proto := AHeap.GetArrayPrototype();
  RegisterMethod(AHeap, proto, 'push', @JSArrayPush);
  RegisterMethod(AHeap, proto, 'pop', @JSArrayPop);
  RegisterMethod(AHeap, proto, 'shift', @JSArrayShift);
  RegisterMethod(AHeap, proto, 'unshift', @JSArrayUnshift);
  RegisterMethod(AHeap, proto, 'join', @JSArrayJoin, 1);
  RegisterMethod(AHeap, proto, 'toString', @JSArrayToString);
  RegisterMethod(AHeap, proto, 'concat', @JSArrayConcat);
  RegisterMethod(AHeap, proto, 'reverse', @JSArrayReverse);
  RegisterMethod(AHeap, proto, 'sort', @JSArraySort);
  RegisterMethod(AHeap, proto, 'slice', @JSArraySlice);
  RegisterMethod(AHeap, proto, 'splice', @JSArraySplice);
  RegisterMethod(AHeap, proto, 'indexOf', @JSArrayIndexOf);
  RegisterMethod(AHeap, proto, 'lastIndexOf', @JSArrayLastIndexOf);
  RegisterMethod(AHeap, proto, 'includes', @JSArrayIncludes);
  RegisterMethod(AHeap, proto, 'flat', @JSArrayFlat);
  RegisterMethod(AHeap, proto, 'flatMap', @JSArrayFlatMap);
  RegisterMethod(AHeap, proto, 'fill', @JSArrayFill);
  RegisterMethod(AHeap, proto, 'copyWithin', @JSArrayCopyWithin);
  RegisterMethod(AHeap, proto, 'at', @JSArrayAt);
  RegisterMethod(AHeap, proto, 'map', @JSArrayMap);
  RegisterMethod(AHeap, proto, 'filter', @JSArrayFilter);
  RegisterMethod(AHeap, proto, 'forEach', @JSArrayForEach);
  RegisterMethod(AHeap, proto, 'some', @JSArraySome);
  RegisterMethod(AHeap, proto, 'every', @JSArrayEvery);
  RegisterMethod(AHeap, proto, 'find', @JSArrayFind);
  RegisterMethod(AHeap, proto, 'findIndex', @JSArrayFindIndex);
  RegisterMethod(AHeap, proto, 'findLast', @JSArrayFindLast, 1);
  RegisterMethod(AHeap, proto, 'findLastIndex', @JSArrayFindLastIndex, 1);
  RegisterMethod(AHeap, proto, 'toReversed', @JSArrayToReversed, 0);
  RegisterMethod(AHeap, proto, 'toSorted', @JSArrayToSorted, 1);
  RegisterMethod(AHeap, proto, 'toSpliced', @JSArrayToSpliced, 2);
  RegisterMethod(AHeap, proto, 'with', @JSArrayWith, 2);
  RegisterMethod(AHeap, proto, 'reduce', @JSArrayReduce);
  RegisterMethod(AHeap, proto, 'reduceRight', @JSArrayReduceRight);

  arrayObj := AHeap.NewNativeMethod('Array', @AHeap.ArrayCtor);
  arrayObj.IntrinsicName := 'Array';
  { Publish the shared array prototype on the constructor, so instanceof and
    Array.prototype access go through the same object the arrays use. }
  arrayObj.SetProperty('prototype', JSMakeObject(proto));
  { Array.prototype is itself array-like: it has a non-enumerable length and a
    constructor back-reference. `new Proxy(Object.create(Array.prototype), {})`
    relies on `"length" in target` walking to this property. }
  proto.DefineDataProperty('length', JSMakeNumber(0), True, False, False);
  proto.DefineDataProperty('constructor', JSMakeFunction(arrayObj), True, False, True);
  arrayObj.SetProperty('isArray', JSMakeFunction(AHeap.NewNativeFunction('isArray', @JSArrayIsArray)));
  arrayObj.SetProperty('from', JSMakeFunction(AHeap.NewNativeFunction('from', @JSArrayFrom)));
  arrayObj.SetProperty('of', JSMakeFunction(AHeap.NewNativeFunction('of', @JSArrayOf)));
  AEnv.Define('Array', JSMakeFunction(arrayObj));
end;

end.
