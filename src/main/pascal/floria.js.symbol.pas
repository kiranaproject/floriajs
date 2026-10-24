{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Symbol Global & Primitive Support               }
{                                                                          }
{   Provides standard JavaScript Symbol primitive factory, global symbol  }
{   registry (Symbol.for, Symbol.keyFor), and well-known symbols.         }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.symbol;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, floria.js.types, floria.js.value, floria.js.env;

procedure FloriaJSRegisterSymbol(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);

implementation

var
  GSymbolRegistry: TStringList = nil;
  GNextSymbolId: Integer = 1000;

function NextSymbolId(): Integer;
begin
  Inc(GNextSymbolId);
  Result := GNextSymbolId;
end;

{ Symbol([description]) }
function JSSymbolCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  desc: string;
begin
  // Calling new Symbol() is a TypeError in standard JS
  if AThis.IsObject() and (AThis.ObjVal <> nil) and (AThis.ObjVal.Prototype = AThis.ObjVal) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Symbol is not a constructor')));

  desc := '';
  if (Length(AArgs) > 0) and not AArgs[0].IsUndefined() then
    desc := AArgs[0].ToString();

  Result := JSMakeSymbol(desc, NextSymbolId());
end;

{ Symbol.for(key) }
function JSSymbolFor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  key: string;
  idx: Integer;
  symId: Integer;
begin
  key := '';
  if Length(AArgs) > 0 then
    key := AArgs[0].ToString();

  if GSymbolRegistry = nil then
    GSymbolRegistry := TStringList.Create();

  idx := GSymbolRegistry.IndexOf(key);
  if idx >= 0 then
  begin
    symId := PtrInt(GSymbolRegistry.Objects[idx]);
    Result := JSMakeSymbol(key, symId);
  end
  else
  begin
    symId := NextSymbolId();
    GSymbolRegistry.AddObject(key, TObject(PtrInt(symId)));
    Result := JSMakeSymbol(key, symId);
  end;
end;

{ Symbol.keyFor(sym) }
function JSSymbolKeyFor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  symVal: TFloriaJSValue;
  targetId, i: Integer;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeUndefined());

  symVal := AArgs[0];
  if not symVal.IsSymbol() then
    Exit(JSMakeUndefined());

  targetId := Round(symVal.NumVal);
  if GSymbolRegistry <> nil then
  begin
    for i := 0 to GSymbolRegistry.Count - 1 do
    begin
      if PtrInt(GSymbolRegistry.Objects[i]) = targetId then
        Exit(JSMakeString(GSymbolRegistry[i]));
    end;
  end;

  Result := JSMakeUndefined();
end;

{ Symbol.prototype.toString() }
function JSSymbolProtoToString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsSymbol() then
    Exit(JSMakeString('Symbol()'));
  Result := JSMakeString(AThis.ToString());
end;

{ Symbol.prototype.valueOf() }
function JSSymbolProtoValueOf(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := AThis;
end;

{ Symbol.prototype.description getter }
function JSSymbolProtoGetDescription(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsSymbol() then
    Exit(JSMakeUndefined());
  if AThis.StrVal = '' then
    Exit(JSMakeUndefined())
  else
    Exit(JSMakeString(AThis.StrVal));
end;

procedure FloriaJSRegisterSymbol(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  symCtor: TFloriaJSFunction;
  symProto: TFloriaJSObject;
  descGetter: TFloriaJSFunction;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;

  symProto := AHeap.NewObject();
  symProto.SetProperty('toString', JSMakeFunction(AHeap.NewNativeFunction('toString', @JSSymbolProtoToString)));
  symProto.SetProperty('valueOf', JSMakeFunction(AHeap.NewNativeFunction('valueOf', @JSSymbolProtoValueOf)));

  descGetter := AHeap.NewNativeFunction('get description', @JSSymbolProtoGetDescription);
  symProto.DefineGetter('description', JSMakeFunction(descGetter));

  symCtor := AHeap.NewNativeFunction('Symbol', @JSSymbolCtor);
  symCtor.SetProperty('prototype', JSMakeObject(symProto));
  symCtor.SetProperty('for', JSMakeFunction(AHeap.NewNativeFunction('for', @JSSymbolFor)));
  symCtor.SetProperty('keyFor', JSMakeFunction(AHeap.NewNativeFunction('keyFor', @JSSymbolKeyFor)));

  // Well-known symbols
  symCtor.SetProperty('iterator', JSMakeSymbol('Symbol.iterator', NextSymbolId()));
  symCtor.SetProperty('toStringTag', JSMakeSymbol('Symbol.toStringTag', NextSymbolId()));
  symCtor.SetProperty('hasInstance', JSMakeSymbol('Symbol.hasInstance', NextSymbolId()));
  symCtor.SetProperty('isConcatSpreadable', JSMakeSymbol('Symbol.isConcatSpreadable', NextSymbolId()));
  symCtor.SetProperty('toPrimitive', JSMakeSymbol('Symbol.toPrimitive', NextSymbolId()));

  AEnv.Define('Symbol', JSMakeFunction(symCtor));
end;

initialization

finalization
  if GSymbolRegistry <> nil then
    FreeAndNil(GSymbolRegistry);

end.
