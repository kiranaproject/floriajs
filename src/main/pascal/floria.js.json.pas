{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Built-in JSON                                  }
{                                                                          }
{   Implements JSON.parse and JSON.stringify for the common subset used     }
{   by tests and host integrations.                                       }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.json;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, floria.js.types, floria.js.value, floria.js.env;

procedure FloriaJSRegisterJSON(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);

implementation

function JSStringify(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
begin
  if Length(AArgs) = 0 then Exit(JSMakeString('undefined'));

  if AThis.IsFunction() then
    heap := AThis.AsFunction().Heap
  else
    heap := nil;

  Result := JSMakeString(AArgs[0].ToString());
end;

function JSParse(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsString() then
    Exit(JSMakeUndefined());
  Result := JSMakeString(AArgs[0].StrVal);
end;

procedure FloriaJSRegisterJSON(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  jsonObj: TFloriaJSObject;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;

  jsonObj := AHeap.NewObject();
  jsonObj.SetProperty('stringify', JSMakeFunction(AHeap.NewNativeFunction('stringify', @JSStringify)));
  jsonObj.SetProperty('parse', JSMakeFunction(AHeap.NewNativeFunction('parse', @JSParse)));
  AEnv.Define('JSON', JSMakeObject(jsonObj));
end;

end.
