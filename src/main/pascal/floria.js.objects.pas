{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Built-in Object Utilities                        }
{                                                                          }
{   Implements Object.keys/values/entries/assign/create and adds            }
{   hasOwnProperty/function helpers to objects and functions.               }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.objects;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, floria.js.types, floria.js.value, floria.js.env,
  floria.js.collections;

procedure FloriaJSRegisterObjects(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap; AObjectCtor: TFloriaJSNativeMethod);

implementation

function GetKeysArray(AHeap: TFloriaJSHeap; AObj: TFloriaJSObject): TFloriaJSArray;
var
  arr: TFloriaJSArray;
  i: Integer;
  keys: TStringList;
begin
  arr := AHeap.NewArray();
  if AObj = nil then
    Exit(arr);

  if AObj is TFloriaJSProxy then
  begin
    keys := TStringList.Create();
    try
      AObj.GetKeys(keys);
      for i := 0 to keys.Count - 1 do
        arr.Push(JSMakeString(keys[i]));
    finally
      keys.Free();
    end;
    Exit(arr);
  end;

  if AObj is TFloriaJSArray then
  begin
    { Numeric indices are own properties only when they hold an element; a
      hole is absent even though reading it yields undefined. }
    for i := 0 to TFloriaJSArray(AObj).Length() - 1 do
      if TFloriaJSArray(AObj).HasElement(i) then
        arr.Push(JSMakeString(IntToStr(i)));
  end;

  for i := 0 to AObj.GetEnumerablePropertyCount() - 1 do
    arr.Push(JSMakeString(AObj.GetEnumerablePropertyKey(i)));

  Result := arr;
end;

function GetValuesArray(AHeap: TFloriaJSHeap; AObj: TFloriaJSObject): TFloriaJSArray;
var
  arr: TFloriaJSArray;
  i: Integer;
begin
  arr := AHeap.NewArray();
  if AObj = nil then
    Exit(arr);

  if AObj is TFloriaJSArray then
  begin
    for i := 0 to TFloriaJSArray(AObj).Length() - 1 do
      if TFloriaJSArray(AObj).HasElement(i) then
        arr.Push(TFloriaJSArray(AObj).GetElement(i));
  end;

  for i := 0 to AObj.GetPropertyCount() - 1 do
    arr.Push(AObj.GetPropertyValue(i));

  Result := arr;
end;

function GetEntriesArray(AHeap: TFloriaJSHeap; AObj: TFloriaJSObject): TFloriaJSArray;
var
  arr, pair: TFloriaJSArray;
  i: Integer;
begin
  arr := AHeap.NewArray();
  if AObj = nil then
    Exit(arr);

  if AObj is TFloriaJSArray then
  begin
    for i := 0 to TFloriaJSArray(AObj).Length() - 1 do
    begin
      if TFloriaJSArray(AObj).HasElement(i) then
      begin
        pair := AHeap.NewArray();
        pair.Push(JSMakeString(IntToStr(i)));
        pair.Push(TFloriaJSArray(AObj).GetElement(i));
        arr.Push(JSMakeArray(pair));
      end;
    end;
  end;

  for i := 0 to AObj.GetPropertyCount() - 1 do
  begin
    pair := AHeap.NewArray();
    pair.Push(JSMakeString(AObj.GetPropertyKey(i)));
    pair.Push(AObj.GetPropertyValue(i));
    arr.Push(JSMakeArray(pair));
  end;

  Result := arr;
end;

function ThisObject(const AThis: TFloriaJSValue): TFloriaJSObject;
begin
  Result := AThis.AsObject();
end;

function JSObjectKeys(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  heap: TFloriaJSHeap;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
  begin
    heap := nil;
    if AThis.IsFunction() then
      heap := AThis.AsFunction().Heap
    else if AThis.IsObject() then
      heap := AThis.AsObject().Heap;
    if heap <> nil then
      Exit(JSMakeArray(heap.NewArray()))
    else
      Exit(JSMakeUndefined());
  end;

  obj := AArgs[0].AsObject();
  heap := obj.Heap;
  if (heap = nil) and AThis.IsFunction() then
    heap := AThis.AsFunction().Heap;
  if heap = nil then
    Exit(JSMakeUndefined());

  Result := JSMakeArray(GetKeysArray(heap, obj));
end;

function JSObjectValues(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  heap: TFloriaJSHeap;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
  begin
    heap := nil;
    if AThis.IsFunction() then
      heap := AThis.AsFunction().Heap
    else if AThis.IsObject() then
      heap := AThis.AsObject().Heap;
    if heap <> nil then
      Exit(JSMakeArray(heap.NewArray()))
    else
      Exit(JSMakeUndefined());
  end;

  obj := AArgs[0].AsObject();
  heap := obj.Heap;
  if (heap = nil) and AThis.IsFunction() then
    heap := AThis.AsFunction().Heap;
  if heap = nil then
    Exit(JSMakeUndefined());

  Result := JSMakeArray(GetValuesArray(heap, obj));
end;

function JSObjectEntries(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  heap: TFloriaJSHeap;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
  begin
    heap := nil;
    if AThis.IsFunction() then
      heap := AThis.AsFunction().Heap
    else if AThis.IsObject() then
      heap := AThis.AsObject().Heap;
    if heap <> nil then
      Exit(JSMakeArray(heap.NewArray()))
    else
      Exit(JSMakeUndefined());
  end;

  obj := AArgs[0].AsObject();
  heap := obj.Heap;
  if (heap = nil) and AThis.IsFunction() then
    heap := AThis.AsFunction().Heap;
  if heap = nil then
    Exit(JSMakeUndefined());

  Result := JSMakeArray(GetEntriesArray(heap, obj));
end;

function JSObjectFromEntries(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
  iter: TFloriaJSIterator;
  obj: TFloriaJSObject;
  entry, key, value: TFloriaJSValue;
begin
  heap := nil;
  if AThis.IsFunction() then
    heap := AThis.AsFunction().Heap
  else if AThis.IsObject() then
    heap := AThis.AsObject().Heap;
  if heap = nil then
  begin
    if (Length(AArgs) > 0) and AArgs[0].IsObject() then
      heap := AArgs[0].AsObject().Heap;
  end;
  if heap = nil then
    Exit(JSMakeUndefined());

  if (Length(AArgs) = 0) or (not AArgs[0].IsObject()) then
    raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
      'Object.fromEntries requires an iterable')));

  obj := heap.NewObject(heap.GetObjectPrototype());
  if not JSGetIterator(heap, AArgs[0], iter) then
    raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
      'Object.fromEntries requires an iterable')));

  while JSIteratorNext(iter, entry) do
  begin
    if not entry.IsObject() then
      raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
        'Object.fromEntries entry is not an object')));
    key := entry.AsObject().GetProperty('0');
    value := entry.AsObject().GetProperty('1');
    obj.SetProperty(JSPropertyKeyName(key), value);
  end;
  Result := JSMakeObject(obj);
end;

function JSObjectAssign(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target, src: TFloriaJSObject;
  i, j: Integer;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
    Exit(JSMakeUndefined());

  target := AArgs[0].AsObject();
  for i := 1 to High(AArgs) do
  begin
    if not AArgs[i].IsObject() then
      Continue;
    src := AArgs[i].AsObject();
    { Array elements are own properties too, even though they are stored in the
      dense element array rather than the property table. }
    if src is TFloriaJSArray then
      for j := 0 to TFloriaJSArray(src).Length() - 1 do
        if TFloriaJSArray(src).HasElement(j) then
          target.SetProperty(IntToStr(j), TFloriaJSArray(src).GetElement(j));
    for j := 0 to src.GetPropertyCount() - 1 do
      target.SetProperty(src.GetPropertyKey(j), src.GetPropertyValue(j));
  end;

  Result := AArgs[0];
end;

function JSObjectCreate(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
  proto: TFloriaJSObject;
begin
  if AThis.IsFunction() then
    heap := AThis.AsFunction().Heap
  else
    heap := nil;
  if (heap = nil) and (Length(AArgs) > 0) and AArgs[0].IsObject() then
    heap := AArgs[0].AsObject().Heap;
  if heap = nil then Exit(JSMakeObject(nil));

  if (Length(AArgs) > 0) and AArgs[0].IsNull() then
    Exit(JSMakeObject(heap.NewObject(nil, True)));

  proto := nil;
  if (Length(AArgs) > 0) and AArgs[0].IsObject() and (not AArgs[0].IsFunction()) then
    proto := AArgs[0].AsObject();

  Result := JSMakeObject(heap.NewObject(proto));
end;


{ `Object.is(a, b)` — SameValue, which differs from === for NaN and -0. }
function JSObjectIs(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  a, b: TFloriaJSValue;
begin
  if Length(AArgs) < 2 then
    Exit(JSMakeBoolean(False));
  a := AArgs[0];
  b := AArgs[1];

  { NaN is the same value as itself. }
  if a.IsNumber() and b.IsNumber() then
  begin
    if IsNaN(a.NumVal) and IsNaN(b.NumVal) then
      Exit(JSMakeBoolean(True));
    { +0 and -0 are different values. }
    if (a.NumVal = 0.0) and (b.NumVal = 0.0) then
      Exit(JSMakeBoolean(1.0 / a.NumVal = 1.0 / b.NumVal));
  end;

  Result := JSMakeBoolean(JSStrictEqual(a, b));
end;

{ `Object.getOwnPropertyNames(o)` — own keys, including non-enumerable ones. }
function JSObjectGetOwnPropertyNames(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  heap: TFloriaJSHeap;
  arr: TFloriaJSArray;
  keys: TStringList;
  i: Integer;
begin
  heap := nil;
  { Host utilities can call a saved reference as a plain function, so the heap
    must come from the argument, not from `this`. }
  if (Length(AArgs) > 0) and AArgs[0].IsFunction() then
    heap := AArgs[0].AsFunction().Heap
  else if (Length(AArgs) > 0) and AArgs[0].IsObject() then
    heap := AArgs[0].AsObject().Heap;
  if heap = nil then
  begin
    if AThis.IsFunction() then
      heap := AThis.AsFunction().Heap
    else if AThis.IsObject() then
      heap := AThis.AsObject().Heap;
  end;
  if heap = nil then
    Exit(JSMakeUndefined());

  arr := heap.NewArray();
  if (Length(AArgs) > 0) and AArgs[0].IsObject() then
  begin
    obj := AArgs[0].AsObject();
    if obj is TFloriaJSProxy then
    begin
      keys := TStringList.Create();
      try
        obj.GetKeys(keys);
        for i := 0 to keys.Count - 1 do
          arr.Push(JSMakeString(keys[i]));
      finally
        keys.Free();
      end;
      Exit(JSMakeArray(arr));
    end;
    if obj is TFloriaJSArray then
    begin
      for i := 0 to TFloriaJSArray(obj).Length() - 1 do
        if TFloriaJSArray(obj).HasElement(i) then
          arr.Push(JSMakeString(IntToStr(i)));
      arr.Push(JSMakeString('length'));
    end;
    { Every own key, enumerable or not, in insertion order. }
    for i := 0 to obj.GetPropertyCount() - 1 do
      arr.Push(JSMakeString(obj.GetPropertyKey(i)));
  end
  else if (Length(AArgs) > 0) and AArgs[0].IsArray() then
  begin
    obj := AArgs[0].AsObject();
    for i := 0 to obj.GetPropertyCount() - 1 do
      arr.Push(JSMakeString(obj.GetPropertyKey(i)));
  end;
  Result := JSMakeArray(arr);
end;

{ `Object.getOwnPropertyDescriptor(o, key)` — returns the descriptor object or
  undefined when the property is not an own property. }
function JSObjectGetOwnPropertyDescriptor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  heap: TFloriaJSHeap;
  key, message: string;
  desc: TFloriaJSObject;
  index: Integer;
  arrayObj: TFloriaJSArray;
begin
  if (Length(AArgs) < 2) or not AArgs[0].IsObject() then
    Exit(JSMakeUndefined());
  obj := AArgs[0].AsObject();
  heap := obj.Heap;
  if heap = nil then
    Exit(JSMakeUndefined());
  key := AArgs[1].ToString();

  if obj is TFloriaJSArray then
  begin
    arrayObj := TFloriaJSArray(obj);
    if key = 'length' then
    begin
      desc := heap.NewObject(heap.GetObjectPrototype());
      desc.SetProperty('value', JSMakeNumber(arrayObj.Length()));
      desc.SetProperty('writable', JSMakeBoolean(True));
      desc.SetProperty('enumerable', JSMakeBoolean(False));
      desc.SetProperty('configurable', JSMakeBoolean(False));
      Exit(JSMakeObject(desc));
    end;
    if TryStrToInt(key, index) and (index >= 0) and
       (IntToStr(index) = key) and arrayObj.HasElement(index) then
    begin
      desc := heap.NewObject(heap.GetObjectPrototype());
      desc.SetProperty('value', arrayObj.GetElement(index));
      desc.SetProperty('writable', JSMakeBoolean(True));
      desc.SetProperty('enumerable', JSMakeBoolean(True));
      desc.SetProperty('configurable', JSMakeBoolean(True));
      Exit(JSMakeObject(desc));
    end;
  end;

  if obj is TFloriaJSProxy then
    Exit(obj.GetOwnProperty(key));

  if not obj.HasOwnProperty(key) then
    Exit(JSMakeUndefined());

  desc := heap.NewObject(heap.GetObjectPrototype());
  if obj.PropertyIsAccessor(key) then
  begin
    desc.SetProperty('get', obj.PropertyGetter(key));
    desc.SetProperty('set', obj.PropertySetter(key));
  end
  else
  begin
    desc.SetProperty('value', obj.GetOwnProperty(key));
    desc.SetProperty('writable', JSMakeBoolean(obj.PropertyIsWritable(key)));
  end;
  desc.SetProperty('enumerable', JSMakeBoolean(obj.PropertyIsEnumerable(key)));
  desc.SetProperty('configurable', JSMakeBoolean(obj.PropertyIsConfigurable(key)));
  Result := JSMakeObject(desc);
end;

{ `Object.defineProperty(o, key, descriptor)` — defines one property. }
function JSObjectDefineProperty(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  key: string;
  desc: TFloriaJSObject;
  writable, enumerable, configurable, existed: Boolean;
  value, getter, setter: TFloriaJSValue;
begin
  if (Length(AArgs) < 3) or not AArgs[0].IsObject() or not AArgs[2].IsObject() then
    Exit(JSMakeUndefined());

  obj := AArgs[0].AsObject();
  key := AArgs[1].ToString();
  desc := AArgs[2].AsObject();
  existed := obj.HasOwnProperty(key);

  if existed then
  begin
    writable := obj.PropertyIsWritable(key);
    enumerable := obj.PropertyIsEnumerable(key);
    configurable := obj.PropertyIsConfigurable(key);
  end
  else
  begin
    writable := False;
    enumerable := False;
    configurable := False;
  end;
  if desc.HasProperty('writable') then
    writable := desc.GetProperty('writable').ToBoolean();
  if desc.HasProperty('enumerable') then
    enumerable := desc.GetProperty('enumerable').ToBoolean();
  if desc.HasProperty('configurable') then
    configurable := desc.GetProperty('configurable').ToBoolean();

  if desc.HasProperty('get') or desc.HasProperty('set') then
  begin
    getter := desc.GetProperty('get');
    setter := desc.GetProperty('set');
    if not getter.IsFunction() then
      getter := JSMakeUndefined();
    if not setter.IsFunction() then
      setter := JSMakeUndefined();
    obj.DefineAccessorProperty(key, getter, setter, enumerable, configurable);
  end
  else
  begin
    value := desc.GetProperty('value');
    obj.DefineDataProperty(key, value, writable, enumerable, configurable);
  end;

  Result := AArgs[0];
end;

function JSObjectFreeze(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
    Exit(JSMakeUndefined());
  obj := AArgs[0].AsObject();
  obj.FreezeProperties();
  Result := AArgs[0];
end;

function JSObjectSeal(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
    Exit(JSMakeUndefined());
  obj := AArgs[0].AsObject();
  obj.SealProperties();
  Result := AArgs[0];
end;

function JSObjectPreventExtensions(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
    Exit(JSMakeUndefined());
  AArgs[0].AsObject().IsExtensible := False;
  Result := AArgs[0];
end;

function JSObjectIsExtensible(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(AArgs[0].AsObject().IsExtensible);
end;

function JSObjectIsFrozen(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
    Exit(JSMakeBoolean(True));
  Result := JSMakeBoolean(AArgs[0].AsObject().IsFrozen);
end;

function JSObjectIsSealed(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
    Exit(JSMakeBoolean(True));
  Result := JSMakeBoolean(AArgs[0].AsObject().IsSealed);
end;

function JSObjectGetPrototypeOf(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
    Exit(JSMakeUndefined());

  obj := AArgs[0].AsObject();
  if (obj <> nil) and (obj.Prototype <> nil) then
    Exit(JSMakeObject(obj.Prototype))
  else
    Exit(JSMakeNull());
end;

function JSObjectPrototypeHasOwnProperty(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  name: string;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeBoolean(False));

  name := AArgs[0].ToString();

  if AThis.IsObject() then
  begin
    obj := AThis.AsObject();
    if obj <> nil then
      Exit(JSMakeBoolean(obj.HasOwnProperty(name)));
  end;

  Exit(JSMakeBoolean(False));
end;

function JSObjectPrototypeToString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if AThis.IsArray() then
    Result := JSMakeString('[object Array]')
  else if AThis.IsFunction() then
    Result := JSMakeString('[object Function]')
  else if AThis.IsObject() and (AThis.ObjVal is TFloriaJSStringObject) then
    Result := JSMakeString('[object String]')
  else
    Result := JSMakeString('[object Object]');
end;

function JSObjectPrototypePropertyIsEnumerable(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  key: string;
begin
  if (Length(AArgs) = 0) or (not AThis.IsObject()) then
    Exit(JSMakeBoolean(False));
  obj := AThis.AsObject();
  key := AArgs[0].ToString();
  Result := JSMakeBoolean(obj.PropertyIsEnumerable(key));
end;

function ReflectTarget(const AArgs: array of TFloriaJSValue): TFloriaJSObject;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
    Exit(nil);
  Result := AArgs[0].AsObject();
end;

function JSReflectGet(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: TFloriaJSObject;
  receiver: TFloriaJSObject;
begin
  target := ReflectTarget(AArgs);
  if (target = nil) or (Length(AArgs) < 2) then
    Exit(JSMakeUndefined());
  receiver := target;
  if (Length(AArgs) > 2) and AArgs[2].IsObject() then
    receiver := AArgs[2].AsObject();
  Result := target.GetPropertyWithReceiver(AArgs[1].ToString(), receiver);
end;

function JSReflectSet(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: TFloriaJSObject;
begin
  target := ReflectTarget(AArgs);
  if (target = nil) or (Length(AArgs) < 3) then
    Exit(JSMakeBoolean(False));
  target.SetProperty(AArgs[1].ToString(), AArgs[2]);
  Result := JSMakeBoolean(True);
end;

function JSReflectHas(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: TFloriaJSObject;
begin
  target := ReflectTarget(AArgs);
  if (target = nil) or (Length(AArgs) < 2) then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(target.HasProperty(AArgs[1].ToString()));
end;

function JSReflectDeleteProperty(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: TFloriaJSObject;
begin
  target := ReflectTarget(AArgs);
  if (target = nil) or (Length(AArgs) < 2) then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(target.DeleteProperty(AArgs[1].ToString()));
end;

function JSReflectOwnKeys(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: TFloriaJSObject;
  arr: TFloriaJSArray;
  i: Integer;
begin
  target := ReflectTarget(AArgs);
  if target = nil then
    Exit(JSMakeUndefined());
  arr := target.Heap.NewArray();
  for i := 0 to target.GetPropertyCount() - 1 do
    arr.Push(JSMakeString(target.GetPropertyKey(i)));
  if target is TFloriaJSArray then
  begin
    for i := 0 to TFloriaJSArray(target).Length() - 1 do
      if TFloriaJSArray(target).HasElement(i) then
        arr.Push(JSMakeString(IntToStr(i)));
    arr.Push(JSMakeString('length'));
  end;
  Result := JSMakeArray(arr);
end;

function JSReflectGetPrototypeOf(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: TFloriaJSObject;
begin
  target := ReflectTarget(AArgs);
  if (target = nil) or (target.Prototype = nil) then
    Exit(JSMakeNull());
  Result := JSMakeObject(target.Prototype);
end;

function JSReflectSetPrototypeOf(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: TFloriaJSObject;
begin
  target := ReflectTarget(AArgs);
  if (target = nil) or (Length(AArgs) < 2) then
    Exit(JSMakeBoolean(False));
  if target is TFloriaJSProxy then
    Exit(JSMakeBoolean(TFloriaJSProxy(target).SetPrototypeOf(AArgs[1])));
  if AArgs[1].IsNull() then
    target.Prototype := nil
  else if AArgs[1].IsObject() then
    target.Prototype := AArgs[1].AsObject()
  else
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(True);
end;

function JSObjectSetPrototypeOf(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
begin
  if (Length(AArgs) < 2) or not AArgs[0].IsObject() then
    Exit(JSMakeUndefined());
  obj := AArgs[0].AsObject();
  if obj is TFloriaJSProxy then
  begin
    if not TFloriaJSProxy(obj).SetPrototypeOf(AArgs[1]) then
      raise EFloriaJSThrow.Create(JSMakeObject(
        obj.Heap.NewError('TypeError', 'Cannot set prototype')));
    Exit(AArgs[0]);
  end;
  if AArgs[1].IsNull() then
    obj.Prototype := nil
  else if AArgs[1].IsObject() then
    obj.Prototype := AArgs[1].AsObject()
  else
    raise EFloriaJSThrow.Create(JSMakeObject(
      obj.Heap.NewError('TypeError', 'Object prototype may only be an Object or null')));
  Result := AArgs[0];
end;

function JSReflectApply(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
  args: TFloriaJSValueArray;
  i: Integer;
  thisVal: TFloriaJSValue;
begin
  if (Length(AArgs) < 1) or not AArgs[0].IsFunction() then
    Exit(JSMakeUndefined());
  if AArgs[0].IsObject() and (AArgs[0].ObjVal is TFloriaJSProxy) then
    heap := AArgs[0].ObjVal.Heap
  else
    heap := AArgs[0].AsFunction().Heap;
  thisVal := JSMakeUndefined();
  if Length(AArgs) > 1 then thisVal := AArgs[1];
  SetLength(args, 0);
  if (Length(AArgs) > 2) and AArgs[2].IsObject() and
     (AArgs[2].AsObject() is TFloriaJSArray) then
  begin
    SetLength(args, TFloriaJSArray(AArgs[2].AsObject()).Length());
    for i := 0 to High(args) do
      args[i] := TFloriaJSArray(AArgs[2].AsObject()).GetElement(i);
  end;
  Result := heap.InvokeFunction(AArgs[0], args, thisVal);
end;

function JSReflectConstruct(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
  args: TFloriaJSValueArray;
  newTarget, savedNewTarget: TFloriaJSValue;
  i: Integer;
begin
  if (Length(AArgs) < 1) or not AArgs[0].IsFunction() then
    Exit(JSMakeUndefined());
  if AArgs[0].IsObject() and (AArgs[0].ObjVal is TFloriaJSProxy) then
    heap := AArgs[0].ObjVal.Heap
  else
    heap := AArgs[0].AsFunction().Heap;
  SetLength(args, 0);
  if (Length(AArgs) > 1) and AArgs[1].IsObject() and
     (AArgs[1].AsObject() is TFloriaJSArray) then
  begin
    SetLength(args, TFloriaJSArray(AArgs[1].AsObject()).Length());
    for i := 0 to High(args) do
      args[i] := TFloriaJSArray(AArgs[1].AsObject()).GetElement(i);
  end;

  newTarget := AArgs[0];
  if Length(AArgs) > 2 then
    newTarget := AArgs[2];
  if (not newTarget.IsFunction()) or (not heap.IsConstructable(newTarget)) then
    raise EFloriaJSThrow.Create(JSMakeObject(
      heap.NewError('TypeError', 'Reflect.construct newTarget is not a constructor')));

  savedNewTarget := heap.CurrentNewTarget;
  heap.CurrentNewTarget := newTarget;
  try
    Result := heap.ConstructFunction(AArgs[0], args);
  finally
    heap.CurrentNewTarget := savedNewTarget;
  end;
end;

function JSReflectIsExtensible(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: TFloriaJSObject;
begin
  target := ReflectTarget(AArgs);
  Result := JSMakeBoolean((target <> nil) and target.IsExtensible);
end;

function JSReflectPreventExtensions(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: TFloriaJSObject;
begin
  target := ReflectTarget(AArgs);
  if target <> nil then
    target.IsExtensible := False;
  Result := JSMakeBoolean(target <> nil);
end;

type
  TFloriaJSProxyRevoker = class
  private
    FProxy: TFloriaJSProxy;
  public
    constructor Create(AProxy: TFloriaJSProxy);
    function Revoke(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
  end;

constructor TFloriaJSProxyRevoker.Create(AProxy: TFloriaJSProxy);
begin
  inherited Create();
  FProxy := AProxy;
end;

function TFloriaJSProxyRevoker.Revoke(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if FProxy <> nil then
    FProxy.Revoked := True;
  Result := JSMakeUndefined();
end;

function JSProxyCtor(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
begin
  if (Length(AArgs) < 2) or not AArgs[0].IsObject() or not AArgs[1].IsObject() then
    raise EFloriaJSThrow.Create(JSMakeString('TypeError: Proxy target and handler must be objects'));
  heap := AArgs[0].AsObject().Heap;
  if heap = nil then
    Exit(JSMakeUndefined());
  Result := JSMakeProxy(TFloriaJSProxy(heap.Track(TFloriaJSProxy.Create(heap, AArgs[0], AArgs[1]))));
end;

function JSProxyRevocable(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
  proxy: TFloriaJSProxy;
  revoker: TFloriaJSProxyRevoker;
  resultObj: TFloriaJSObject;
begin
  if (Length(AArgs) < 2) or not AArgs[0].IsObject() or not AArgs[1].IsObject() then
    raise EFloriaJSThrow.Create(JSMakeString('TypeError: Proxy target and handler must be objects'));
  heap := AArgs[0].AsObject().Heap;
  if heap = nil then
    Exit(JSMakeUndefined());
  proxy := TFloriaJSProxy(heap.Track(TFloriaJSProxy.Create(heap, AArgs[0], AArgs[1])));
  revoker := TFloriaJSProxyRevoker.Create(proxy);
  heap.OwnHelper(revoker);
  resultObj := heap.NewObject(heap.GetObjectPrototype());
  resultObj.SetProperty('proxy', JSMakeProxy(proxy));
  resultObj.SetProperty('revoke', JSMakeFunction(
    heap.NewNativeMethod('revoke', @revoker.Revoke)));
  Result := JSMakeObject(resultObj);
end;

procedure FloriaJSRegisterObjects(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap; AObjectCtor: TFloriaJSNativeMethod);
var
  objectObj, proxyObj: TFloriaJSFunction;
  proto, reflectObj: TFloriaJSObject;
begin
  if (AHeap = nil) then Exit;

  proto := AHeap.GetObjectPrototype();
  proto.SetProperty('hasOwnProperty',
    JSMakeFunction(AHeap.NewNativeFunction('hasOwnProperty', @JSObjectPrototypeHasOwnProperty)));
  proto.SetProperty('toString',
    JSMakeFunction(AHeap.NewNativeFunction('toString', @JSObjectPrototypeToString)));
  proto.SetProperty('propertyIsEnumerable',
    JSMakeFunction(AHeap.NewNativeFunction('propertyIsEnumerable', @JSObjectPrototypePropertyIsEnumerable)));

  objectObj := AHeap.NewNativeMethod('Object', AObjectCtor);
  objectObj.IntrinsicName := 'Object';
  objectObj.SetProperty('prototype', JSMakeObject(proto));
  proto.SetProperty('constructor', JSMakeFunction(objectObj));
  objectObj.SetProperty('keys', JSMakeFunction(AHeap.NewNativeFunction('keys', @JSObjectKeys)));
  objectObj.SetProperty('values', JSMakeFunction(AHeap.NewNativeFunction('values', @JSObjectValues)));
  objectObj.SetProperty('entries', JSMakeFunction(AHeap.NewNativeFunction('entries', @JSObjectEntries)));
  objectObj.SetProperty('fromEntries', JSMakeFunction(AHeap.NewNativeFunction('fromEntries', @JSObjectFromEntries)));
  objectObj.SetProperty('assign', JSMakeFunction(AHeap.NewNativeFunction('assign', @JSObjectAssign)));
  objectObj.SetProperty('create', JSMakeFunction(AHeap.NewNativeFunction('create', @JSObjectCreate)));
  objectObj.SetProperty('getPrototypeOf', JSMakeFunction(AHeap.NewNativeFunction('getPrototypeOf', @JSObjectGetPrototypeOf)));
  objectObj.SetProperty('setPrototypeOf', JSMakeFunction(AHeap.NewNativeFunction('setPrototypeOf', @JSObjectSetPrototypeOf)));
  objectObj.SetProperty('is', JSMakeFunction(AHeap.NewNativeFunction('is', @JSObjectIs)));
  objectObj.SetProperty('getOwnPropertyNames', JSMakeFunction(AHeap.NewNativeFunction('getOwnPropertyNames', @JSObjectGetOwnPropertyNames)));
  objectObj.SetProperty('defineProperty', JSMakeFunction(AHeap.NewNativeFunction('defineProperty', @JSObjectDefineProperty)));
  objectObj.SetProperty('getOwnPropertyDescriptor', JSMakeFunction(AHeap.NewNativeFunction('getOwnPropertyDescriptor', @JSObjectGetOwnPropertyDescriptor)));
  objectObj.SetProperty('freeze', JSMakeFunction(AHeap.NewNativeFunction('freeze', @JSObjectFreeze)));
  objectObj.SetProperty('seal', JSMakeFunction(AHeap.NewNativeFunction('seal', @JSObjectSeal)));
  objectObj.SetProperty('preventExtensions', JSMakeFunction(AHeap.NewNativeFunction('preventExtensions', @JSObjectPreventExtensions)));
  objectObj.SetProperty('isExtensible', JSMakeFunction(AHeap.NewNativeFunction('isExtensible', @JSObjectIsExtensible)));
  objectObj.SetProperty('isFrozen', JSMakeFunction(AHeap.NewNativeFunction('isFrozen', @JSObjectIsFrozen)));
  objectObj.SetProperty('isSealed', JSMakeFunction(AHeap.NewNativeFunction('isSealed', @JSObjectIsSealed)));

  reflectObj := AHeap.NewObject(AHeap.GetObjectPrototype());
  reflectObj.SetProperty('get', JSMakeFunction(AHeap.NewNativeFunction('get', @JSReflectGet)));
  reflectObj.SetProperty('set', JSMakeFunction(AHeap.NewNativeFunction('set', @JSReflectSet)));
  reflectObj.SetProperty('has', JSMakeFunction(AHeap.NewNativeFunction('has', @JSReflectHas)));
  reflectObj.SetProperty('deleteProperty', JSMakeFunction(AHeap.NewNativeFunction('deleteProperty', @JSReflectDeleteProperty)));
  reflectObj.SetProperty('ownKeys', JSMakeFunction(AHeap.NewNativeFunction('ownKeys', @JSReflectOwnKeys)));
  reflectObj.SetProperty('getPrototypeOf', JSMakeFunction(AHeap.NewNativeFunction('getPrototypeOf', @JSReflectGetPrototypeOf)));
  reflectObj.SetProperty('setPrototypeOf', JSMakeFunction(AHeap.NewNativeFunction('setPrototypeOf', @JSReflectSetPrototypeOf)));
  reflectObj.SetProperty('apply', JSMakeFunction(AHeap.NewNativeFunction('apply', @JSReflectApply)));
  reflectObj.SetProperty('construct', JSMakeFunction(AHeap.NewNativeFunction('construct', @JSReflectConstruct)));
  reflectObj.SetProperty('defineProperty', JSMakeFunction(AHeap.NewNativeFunction('defineProperty', @JSObjectDefineProperty)));
  reflectObj.SetProperty('getOwnPropertyDescriptor', JSMakeFunction(AHeap.NewNativeFunction('getOwnPropertyDescriptor', @JSObjectGetOwnPropertyDescriptor)));
  reflectObj.SetProperty('isExtensible', JSMakeFunction(AHeap.NewNativeFunction('isExtensible', @JSReflectIsExtensible)));
  reflectObj.SetProperty('preventExtensions', JSMakeFunction(AHeap.NewNativeFunction('preventExtensions', @JSReflectPreventExtensions)));
  AEnv.Define('Reflect', JSMakeObject(reflectObj));

  if AEnv <> nil then
    AEnv.Define('Object', JSMakeFunction(objectObj));

  proxyObj := AHeap.NewNativeFunction('Proxy', @JSProxyCtor);
  proxyObj.SetProperty('revocable', JSMakeFunction(
    AHeap.NewNativeFunction('revocable', @JSProxyRevocable)));
  AEnv.Define('Proxy', JSMakeFunction(proxyObj));
end;

end.
