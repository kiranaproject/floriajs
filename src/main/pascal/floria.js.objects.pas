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
  Classes, SysUtils, Math, floria.js.types, floria.js.value, floria.js.env;

procedure FloriaJSRegisterObjects(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap; AObjectCtor: TFloriaJSNativeMethod);

implementation

function GetKeysArray(AHeap: TFloriaJSHeap; AObj: TFloriaJSObject): TFloriaJSArray;
var
  arr: TFloriaJSArray;
  i: Integer;
begin
  arr := AHeap.NewArray();
  if AObj = nil then
    Exit(arr);

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
  i: Integer;
begin
  heap := nil;
  if AThis.IsFunction() then
    heap := AThis.AsFunction().Heap
  else if AThis.IsObject() then
    heap := AThis.AsObject().Heap;
  if heap = nil then
    Exit(JSMakeUndefined());

  arr := heap.NewArray();
  if (Length(AArgs) > 0) and AArgs[0].IsObject() then
  begin
    obj := AArgs[0].AsObject();
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

{ `Object.defineProperty(o, key, descriptor)` — defines one property.

  Only the data-descriptor fields and accessors are honoured; the return value
  is the object, as ECMAScript specifies. }
function JSObjectDefineProperty(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  key: string;
  desc: TFloriaJSObject;
  enumerable: Boolean;
begin
  if (Length(AArgs) < 3) or not AArgs[0].IsObject() or not AArgs[2].IsObject() then
    Exit(JSMakeUndefined());

  obj := AArgs[0].AsObject();
  key := AArgs[1].ToString();
  desc := AArgs[2].AsObject();

  { A property defined this way is non-enumerable unless stated otherwise. }
  enumerable := desc.GetProperty('enumerable').ToBoolean();

  if desc.HasProperty('get') or desc.HasProperty('set') then
  begin
    if desc.GetProperty('get').IsFunction() then
      obj.DefineGetter(key, desc.GetProperty('get'));
    if desc.GetProperty('set').IsFunction() then
      obj.DefineSetter(key, desc.GetProperty('set'));
  end
  else
    obj.SetProperty(key, desc.GetProperty('value'));

  if not enumerable then
    obj.SetPropertyNonEnumerable(key, obj.GetProperty(key));

  Result := AArgs[0];
end;

{ `Object.freeze(o)` / `Object.seal(o)` — this runtime has no property
  attributes beyond enumerability, so both mark the object and return it. The
  marking is observable through `Object.isFrozen`/`isSealed`. }
function JSObjectFreeze(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
    Exit(JSMakeUndefined());
  obj := AArgs[0].AsObject();
  obj.IsFrozen := True;
  obj.IsSealed := True;
  Result := AArgs[0];
end;

function JSObjectSeal(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
    Exit(JSMakeUndefined());
  obj := AArgs[0].AsObject();
  obj.IsSealed := True;
  Result := AArgs[0];
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
  else
    Result := JSMakeString('[object Object]');
end;

procedure FloriaJSRegisterObjects(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap; AObjectCtor: TFloriaJSNativeMethod);
var
  objectObj: TFloriaJSFunction;
  proto: TFloriaJSObject;
begin
  if (AHeap = nil) then Exit;

  proto := AHeap.GetObjectPrototype();
  proto.SetProperty('hasOwnProperty',
    JSMakeFunction(AHeap.NewNativeFunction('hasOwnProperty', @JSObjectPrototypeHasOwnProperty)));
  proto.SetProperty('toString',
    JSMakeFunction(AHeap.NewNativeFunction('toString', @JSObjectPrototypeToString)));

  objectObj := AHeap.NewNativeMethod('Object', AObjectCtor);
  objectObj.SetProperty('prototype', JSMakeObject(proto));
  proto.SetProperty('constructor', JSMakeFunction(objectObj));
  objectObj.SetProperty('keys', JSMakeFunction(AHeap.NewNativeFunction('keys', @JSObjectKeys)));
  objectObj.SetProperty('values', JSMakeFunction(AHeap.NewNativeFunction('values', @JSObjectValues)));
  objectObj.SetProperty('entries', JSMakeFunction(AHeap.NewNativeFunction('entries', @JSObjectEntries)));
  objectObj.SetProperty('assign', JSMakeFunction(AHeap.NewNativeFunction('assign', @JSObjectAssign)));
  objectObj.SetProperty('create', JSMakeFunction(AHeap.NewNativeFunction('create', @JSObjectCreate)));
  objectObj.SetProperty('getPrototypeOf', JSMakeFunction(AHeap.NewNativeFunction('getPrototypeOf', @JSObjectGetPrototypeOf)));
  objectObj.SetProperty('is', JSMakeFunction(AHeap.NewNativeFunction('is', @JSObjectIs)));
  objectObj.SetProperty('getOwnPropertyNames', JSMakeFunction(AHeap.NewNativeFunction('getOwnPropertyNames', @JSObjectGetOwnPropertyNames)));
  objectObj.SetProperty('defineProperty', JSMakeFunction(AHeap.NewNativeFunction('defineProperty', @JSObjectDefineProperty)));
  objectObj.SetProperty('freeze', JSMakeFunction(AHeap.NewNativeFunction('freeze', @JSObjectFreeze)));
  objectObj.SetProperty('seal', JSMakeFunction(AHeap.NewNativeFunction('seal', @JSObjectSeal)));
  objectObj.SetProperty('isFrozen', JSMakeFunction(AHeap.NewNativeFunction('isFrozen', @JSObjectIsFrozen)));
  objectObj.SetProperty('isSealed', JSMakeFunction(AHeap.NewNativeFunction('isSealed', @JSObjectIsSealed)));

  if AEnv <> nil then
    AEnv.Define('Object', JSMakeFunction(objectObj));
end;

end.
