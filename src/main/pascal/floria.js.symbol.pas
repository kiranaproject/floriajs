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

{ Returns the well-known symbol with the given description (for example
  'Symbol.matchAll'), or undefined when it has not been registered yet. }
function JSWellKnownSymbol(const ADescription: string): TFloriaJSValue;
{ True when the symbol came from `Symbol.for`, so it lives forever. }
function JSSymbolIsRegistered(const AValue: TFloriaJSValue): Boolean;

implementation

var
  GSymbolRegistry: TStringList = nil;
  GWellKnownSymbols: TStringList = nil;
  GNextSymbolId: Integer = 1000;

function NextSymbolId(): Integer;
begin
  Inc(GNextSymbolId);
  Result := GNextSymbolId;
end;

function JSSymbolIsRegistered(const AValue: TFloriaJSValue): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (not AValue.IsSymbol()) or (GSymbolRegistry = nil) then
    Exit;
  for i := 0 to GSymbolRegistry.Count - 1 do
    if PtrInt(GSymbolRegistry.Objects[i]) = Trunc(AValue.NumVal) then
      Exit(True);
end;

function JSWellKnownSymbol(const ADescription: string): TFloriaJSValue;
var
  idx: Integer;
begin
  if GWellKnownSymbols = nil then
    Exit(JSMakeUndefined());
  idx := GWellKnownSymbols.IndexOfName(ADescription);
  if idx < 0 then
    Exit(JSMakeUndefined());
  Result := JSMakeSymbol(ADescription,
    StrToIntDef(GWellKnownSymbols.ValueFromIndex[idx], 0));
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

procedure AddWellKnownSymbol(ACtor: TFloriaJSFunction; const AName, ADescription: string);
var
  id: Integer;
begin
  id := NextSymbolId();
  ACtor.SetProperty(AName, JSMakeSymbol(ADescription, id));
  GWellKnownSymbols.Add(ADescription + '=' + IntToStr(id));
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
  symProto.DefineDataProperty('constructor', JSMakeFunction(symCtor), True, False, True);
  symCtor.SetProperty('for', JSMakeFunction(AHeap.NewNativeFunction('for', @JSSymbolFor)));
  symCtor.SetProperty('keyFor', JSMakeFunction(AHeap.NewNativeFunction('keyFor', @JSSymbolKeyFor)));

  // Well-known symbols
  if GWellKnownSymbols = nil then
    GWellKnownSymbols := TStringList.Create();
  AddWellKnownSymbol(symCtor, 'iterator', 'Symbol.iterator');
  AddWellKnownSymbol(symCtor, 'toStringTag', 'Symbol.toStringTag');
  AddWellKnownSymbol(symCtor, 'hasInstance', 'Symbol.hasInstance');
  AddWellKnownSymbol(symCtor, 'isConcatSpreadable', 'Symbol.isConcatSpreadable');
  AddWellKnownSymbol(symCtor, 'species', 'Symbol.species');
  AddWellKnownSymbol(symCtor, 'toPrimitive', 'Symbol.toPrimitive');
  AddWellKnownSymbol(symCtor, 'asyncIterator', 'Symbol.asyncIterator');
  AddWellKnownSymbol(symCtor, 'match', 'Symbol.match');
  AddWellKnownSymbol(symCtor, 'matchAll', 'Symbol.matchAll');
  AddWellKnownSymbol(symCtor, 'replace', 'Symbol.replace');
  AddWellKnownSymbol(symCtor, 'search', 'Symbol.search');
  AddWellKnownSymbol(symCtor, 'split', 'Symbol.split');

  AEnv.Define('Symbol', JSMakeFunction(symCtor));
end;

initialization

finalization
  if GSymbolRegistry <> nil then
    FreeAndNil(GSymbolRegistry);

end.
