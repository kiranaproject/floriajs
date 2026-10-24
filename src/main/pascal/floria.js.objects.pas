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
  Classes, SysUtils, floria.js.types, floria.js.value, floria.js.env;

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

  for i := 0 to AObj.GetPropertyCount() - 1 do
    arr.Push(JSMakeString(AObj.GetPropertyKey(i)));

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
  objectObj.SetProperty('keys', JSMakeFunction(AHeap.NewNativeFunction('keys', @JSObjectKeys)));
  objectObj.SetProperty('values', JSMakeFunction(AHeap.NewNativeFunction('values', @JSObjectValues)));
  objectObj.SetProperty('entries', JSMakeFunction(AHeap.NewNativeFunction('entries', @JSObjectEntries)));
  objectObj.SetProperty('assign', JSMakeFunction(AHeap.NewNativeFunction('assign', @JSObjectAssign)));
  objectObj.SetProperty('create', JSMakeFunction(AHeap.NewNativeFunction('create', @JSObjectCreate)));
  objectObj.SetProperty('getPrototypeOf', JSMakeFunction(AHeap.NewNativeFunction('getPrototypeOf', @JSObjectGetPrototypeOf)));

  if AEnv <> nil then
    AEnv.Define('Object', JSMakeFunction(objectObj));
end;

end.
