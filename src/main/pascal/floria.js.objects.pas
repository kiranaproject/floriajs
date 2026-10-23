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

procedure FloriaJSRegisterObjects(AHeap: TFloriaJSHeap; AObjectCtor: TFloriaJSNativeMethod);

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
  arr: TFloriaJSArray;
  heap: TFloriaJSHeap;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() or (AArgs[0].IsFunction()) then
  begin
    heap := nil;
    if AThis.IsFunction() then
      heap := AThis.AsFunction().Heap
    else if AThis.IsObject() then
      heap := AThis.AsObject().Heap;
    if heap <> nil then
      arr := heap.NewArray()
    else
      arr := nil;
    Exit(JSMakeArray(arr));
  end;

  obj := AArgs[0].AsObject();
  Result := JSMakeArray(GetKeysArray(obj.Heap, obj));
end;

function JSObjectValues(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  arr: TFloriaJSArray;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() or AArgs[0].IsFunction() then
  begin
    if AThis.IsFunction() then
      arr := AThis.AsFunction().Heap.NewArray()
    else
      arr := nil;
    Exit(JSMakeArray(arr));
  end;

  obj := AArgs[0].AsObject();
  Result := JSMakeArray(GetValuesArray(obj.Heap, obj));
end;

function JSObjectEntries(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  arr: TFloriaJSArray;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() or AArgs[0].IsFunction() then
  begin
    if AThis.IsFunction() then
      arr := AThis.AsFunction().Heap.NewArray()
    else
      arr := nil;
    Exit(JSMakeArray(arr));
  end;

  obj := AArgs[0].AsObject();
  Result := JSMakeArray(GetEntriesArray(obj.Heap, obj));
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
    if not AArgs[i].IsObject() or AArgs[i].IsFunction() or AArgs[i].IsArray() then
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
  if heap = nil then Exit(JSMakeObject(nil));

  proto := nil;
  if (Length(AArgs) > 0) and AArgs[0].IsObject() and (not AArgs[0].IsFunction()) then
    proto := AArgs[0].AsObject();

  Result := JSMakeObject(heap.NewObject(proto));
end;

function JSObjectPrototypeHasOwnProperty(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  obj: TFloriaJSObject;
  name: string;
begin
  if (Length(AArgs) = 0) then
    Exit(JSMakeBoolean(False));

  name := AArgs[0].ToString();

  if AThis.IsObject() and (not AThis.IsFunction()) then
  begin
    obj := AThis.AsObject();
    if obj <> nil then
      Exit(JSMakeBoolean(obj.HasOwnProperty(name)));
  end;

  Exit(JSMakeBoolean(False));
end;

function JSFunctionToString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if AThis.IsFunction() then
    Result := JSMakeString('function ' + AThis.AsFunction().Name + '() { [native code] }')
  else
    Result := JSMakeString('[object Object]');
end;

procedure FloriaJSRegisterObjects(AHeap: TFloriaJSHeap; AObjectCtor: TFloriaJSNativeMethod);
var
  objectObj: TFloriaJSFunction;
  funcProto: TFloriaJSObject;
begin
  if (AHeap = nil) then Exit;

  objectObj := AHeap.NewNativeMethod('Object', AObjectCtor);
  objectObj.SetProperty('keys', JSMakeFunction(AHeap.NewNativeFunction('keys', @JSObjectKeys)));
  objectObj.SetProperty('values', JSMakeFunction(AHeap.NewNativeFunction('values', @JSObjectValues)));
  objectObj.SetProperty('entries', JSMakeFunction(AHeap.NewNativeFunction('entries', @JSObjectEntries)));
  objectObj.SetProperty('assign', JSMakeFunction(AHeap.NewNativeFunction('assign', @JSObjectAssign)));
  objectObj.SetProperty('create', JSMakeFunction(AHeap.NewNativeFunction('create', @JSObjectCreate)));

  { Object.prototype hasOwnProperty }
  { The built-in object prototype is the prototype of objects created by
    NewObject(nil); attach hasOwnProperty to it when available. }
  if AHeap.GetArrayPrototype() <> nil then
  begin
    AHeap.GetArrayPrototype().SetProperty('hasOwnProperty',
      JSMakeFunction(AHeap.NewNativeFunction('hasOwnProperty', @JSObjectPrototypeHasOwnProperty)));
  end;

  if AObjectCtor <> nil then
  begin
    { installed by caller }
  end;
end;

end.
