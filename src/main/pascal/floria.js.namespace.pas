{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Module Namespace Exotic Object                  }
{                                                                          }
{   The namespace object produced by `import * as ns`. It is an exotic     }
{   object, not an ordinary one: a null prototype, non-extensible, one      }
{   non-writable accessor per exported binding that reads through to the    }
{   exporting environment, and a `Symbol.toStringTag` of "Module".          }
{                                                                          }
{   Copyright (c) 2026 Dio Affrizi                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.namespace;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, floria.js.types, floria.js.value, floria.js.symbol;

type
  { Reads the current value of one exported binding. The closure resolves the
    export through the module graph, so a namespace property is live. }
  TFloriaJSNamespaceReader = function(const AExportName: string): TFloriaJSValue of object;

  { Supplies the getter function a property descriptor reports. }
  TFloriaJSNamespaceGetter = class
  private
    FName: string;
    FReader: TFloriaJSNamespaceReader;
  public
    constructor Create(const AName: string; AReader: TFloriaJSNamespaceReader);
    function Get(const AArgs: array of TFloriaJSValue;
      AThis: TFloriaJSValue): TFloriaJSValue;
  end;

  { The namespace exotic object. Exported names are own non-writable,
    non-enumerable, non-configurable accessor properties; every other property
    is absent. Deleting an export throws in strict mode, which the base class
    reports by answering False from DeleteProperty. }
  TFloriaJSNamespaceObject = class(TFloriaJSObject)
  private
    FNames: TStringList;
    FReader: TFloriaJSNamespaceReader;
    FTagKey: string;
    function  ExportCount(): Integer;
    function  ExportNameAt(AIndex: Integer): string;
  public
    constructor Create(const AExportNames: TStrings;
      AReader: TFloriaJSNamespaceReader);
    destructor Destroy(); override;

    function  GetProperty(const AName: string): TFloriaJSValue; override;
    function  GetPropertyWithReceiver(const AName: string;
      AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); override;
    function  HasProperty(const AName: string): Boolean; override;
    function  DeleteProperty(const AName: string): Boolean; override;
    function  HasOwnProperty(const AName: string): Boolean; override;
    function  GetOwnProperty(const AName: string): TFloriaJSValue; override;
    function  PropertyIsWritable(const AName: string): Boolean; override;
    function  PropertyIsConfigurable(const AName: string): Boolean; override;
    function  PropertyIsEnumerable(const AName: string): Boolean; override;
    function  PropertyIsAccessor(const AName: string): Boolean; override;
    function  PropertyHasGetter(const AName: string): Boolean; override;
    function  PropertyHasSetter(const AName: string): Boolean; override;
    function  PropertyGetter(const AName: string): TFloriaJSValue; override;
    function  PropertySetter(const AName: string): TFloriaJSValue; override;
    function  DefineDataProperty(const AName: string; const AValue: TFloriaJSValue;
      AWritable, AEnumerable, AConfigurable: Boolean): Boolean; override;
    function  DefineAccessorProperty(const AName: string;
      const AGetter, ASetter: TFloriaJSValue; AEnumerable,
      AConfigurable: Boolean): Boolean; override;
    function  SetPrototypeOf(const AProto: TFloriaJSValue): Boolean; override;
    function  RejectsWrite(const AName: string): Boolean; override;
    function  GetPropertyCount(): Integer; override;
    function  GetEnumerablePropertyCount(): Integer; override;
    function  GetEnumerablePropertyKey(AIndex: Integer): string; override;
    function  GetPropertyKey(AIndex: Integer): string; override;
    function  GetPropertyValue(AIndex: Integer): TFloriaJSValue; override;
    procedure GetKeys(AOutKeys: TStrings); override;

    { The `Symbol.toStringTag` key, so the object reports "Module". }
    property TagKey: string read FTagKey write FTagKey;
  end;

{ True when AName is the well-known `Symbol.toStringTag` key in any spelling
  the runtime produces. }
function IsToStringTagKey(const AName: string): Boolean;

implementation

constructor TFloriaJSNamespaceGetter.Create(const AName: string;
  AReader: TFloriaJSNamespaceReader);
begin
  inherited Create();
  FName := AName;
  FReader := AReader;
end;

function TFloriaJSNamespaceGetter.Get(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Assigned(FReader) then
    Result := FReader(FName)
  else
    Result := JSMakeUndefined();
end;

function IsToStringTagKey(const AName: string): Boolean;
begin
  Result := JSIsWellKnownSymbolKey(AName, 'Symbol.toStringTag');
end;

constructor TFloriaJSNamespaceObject.Create(const AExportNames: TStrings;
  AReader: TFloriaJSNamespaceReader);
var
  i: Integer;
begin
  { The namespace has a null prototype and is not extensible. }
  inherited Create(nil);
  IsExtensible := False;
  IsSealed := True;
  IsFrozen := True;
  FReader := AReader;
  FNames := TStringList.Create();
  FNames.CaseSensitive := True;
  FNames.Sorted := False;
  if AExportNames <> nil then
    for i := 0 to AExportNames.Count - 1 do
      if FNames.IndexOf(AExportNames[i]) < 0 then
        FNames.Add(AExportNames[i]);

  { Remember the canonical key of the well-known `Symbol.toStringTag`, so a
    lookup accepts the exact symbol the script used. When the symbol has not
    been registered yet the object still answers to the legacy spelling. }
  FTagKey := JSPropertyKeyName(JSWellKnownSymbol('Symbol.toStringTag'));
  if FTagKey = 'undefined' then
    FTagKey := '';
end;

destructor TFloriaJSNamespaceObject.Destroy();
begin
  FreeAndNil(FNames);
  inherited Destroy();
end;

function TFloriaJSNamespaceObject.ExportCount(): Integer;
begin
  if FNames <> nil then
    Result := FNames.Count
  else
    Result := 0;
end;

function TFloriaJSNamespaceObject.ExportNameAt(AIndex: Integer): string;
begin
  if (FNames <> nil) and (AIndex >= 0) and (AIndex < FNames.Count) then
    Result := FNames[AIndex]
  else
    Result := '';
end;

function TFloriaJSNamespaceObject.GetProperty(
  const AName: string): TFloriaJSValue;
begin
  Result := GetPropertyWithReceiver(AName, Self);
end;

function TFloriaJSNamespaceObject.GetPropertyWithReceiver(const AName: string;
  AReceiver: TFloriaJSObject): TFloriaJSValue;
begin
  { `Symbol.toStringTag` answers "Module". }
  if (FTagKey <> '') and (AName = FTagKey) then
    Exit(JSMakeString('Module'));
  if IsToStringTagKey(AName) then
    Exit(JSMakeString('Module'));

  { An exported binding reads through to the exporting environment. Reading an
    uninitialised binding raises the TDZ ReferenceError inside the reader. }
  if (FNames <> nil) and (FNames.IndexOf(AName) >= 0) then
  begin
    if Assigned(FReader) then
      Exit(FReader(AName));
    Exit(JSMakeUndefined());
  end;

  { There is no prototype chain to continue through. }
  Result := JSMakeUndefined();
end;

procedure TFloriaJSNamespaceObject.SetProperty(const AName: string;
  const AValue: TFloriaJSValue);
begin
  { Every exported property is a read-only accessor and every other property is
    absent. An assignment is a no-op in sloppy mode and a TypeError in strict
    mode; the namespace reports itself frozen, which is how the VM decides. }
end;

function TFloriaJSNamespaceObject.RejectsWrite(const AName: string): Boolean;
begin
  { [[Set]] always returns false: a namespace is read-only. }
  Result := True;
end;

function TFloriaJSNamespaceObject.SetPrototypeOf(
  const AProto: TFloriaJSValue): Boolean;
begin
  { The prototype of a namespace is always null. Setting it to null is a no-op
    that succeeds; anything else is refused. }
  Result := AProto.IsNull();
end;

function TFloriaJSNamespaceObject.HasProperty(const AName: string): Boolean;
begin
  Result := HasOwnProperty(AName);
end;

function TFloriaJSNamespaceObject.HasOwnProperty(const AName: string): Boolean;
begin
  if (FTagKey <> '') and (AName = FTagKey) then
    Exit(True);
  if IsToStringTagKey(AName) then
    Exit(True);
  Result := (FNames <> nil) and (FNames.IndexOf(AName) >= 0);
end;

function TFloriaJSNamespaceObject.GetOwnProperty(
  const AName: string): TFloriaJSValue;
begin
  if not HasOwnProperty(AName) then
    Exit(JSMakeUndefined());
  Result := GetPropertyWithReceiver(AName, Self);
end;

function TFloriaJSNamespaceObject.DeleteProperty(
  const AName: string): Boolean;
begin
  { Both the exports and `Symbol.toStringTag` are non-configurable, so a delete
    answers False and the property survives. }
  Result := not HasOwnProperty(AName);
end;

function TFloriaJSNamespaceObject.PropertyIsWritable(
  const AName: string): Boolean;
begin
  { [[GetOwnProperty]] reports an export as a data property with [[Writable]]
    true; a write is still refused by [[Set]], which is a separate operation. }
  Result := HasOwnProperty(AName) and (not IsToStringTagKey(AName));
end;

function TFloriaJSNamespaceObject.PropertyIsConfigurable(
  const AName: string): Boolean;
begin
  Result := False;
end;

function TFloriaJSNamespaceObject.PropertyIsEnumerable(
  const AName: string): Boolean;
begin
  { Exported bindings are enumerable; `Symbol.toStringTag` is not. }
  if IsToStringTagKey(AName) then
    Exit(False);
  Result := (FNames <> nil) and (FNames.IndexOf(AName) >= 0);
end;

function TFloriaJSNamespaceObject.PropertyIsAccessor(
  const AName: string): Boolean;
begin
  { Every own property, exported binding or the tag, is reported as a data
    property by [[GetOwnProperty]]. }
  Result := False;
end;

function TFloriaJSNamespaceObject.PropertyHasGetter(
  const AName: string): Boolean;
begin
  Result := False;
end;

function TFloriaJSNamespaceObject.PropertyHasSetter(
  const AName: string): Boolean;
begin
  Result := False;
end;

function TFloriaJSNamespaceObject.PropertyGetter(
  const AName: string): TFloriaJSValue;
begin
  { Own properties are data properties, so there is no getter. }
  Result := JSMakeUndefined();
end;

function TFloriaJSNamespaceObject.PropertySetter(
  const AName: string): TFloriaJSValue;
begin
  Result := JSMakeUndefined();
end;

function TFloriaJSNamespaceObject.DefineDataProperty(const AName: string;
  const AValue: TFloriaJSValue; AWritable, AEnumerable,
  AConfigurable: Boolean): Boolean;
begin
  { The namespace is not extensible and its properties are frozen. }
  Result := False;
end;

function TFloriaJSNamespaceObject.DefineAccessorProperty(const AName: string;
  const AGetter, ASetter: TFloriaJSValue; AEnumerable,
  AConfigurable: Boolean): Boolean;
begin
  Result := False;
end;

function TFloriaJSNamespaceObject.GetPropertyCount(): Integer;
begin
  { Own keys are the exports plus `Symbol.toStringTag`, when the runtime has
    registered that symbol. }
  if FTagKey <> '' then
    Result := ExportCount() + 1
  else
    Result := ExportCount();
end;

function TFloriaJSNamespaceObject.GetEnumerablePropertyCount(): Integer;
begin
  Result := ExportCount();
end;

function TFloriaJSNamespaceObject.GetEnumerablePropertyKey(
  AIndex: Integer): string;
begin
  Result := ExportNameAt(AIndex);
end;

function TFloriaJSNamespaceObject.GetPropertyKey(AIndex: Integer): string;
begin
  if AIndex < ExportCount() then
    Result := ExportNameAt(AIndex)
  else
    Result := FTagKey;
end;

function TFloriaJSNamespaceObject.GetPropertyValue(
  AIndex: Integer): TFloriaJSValue;
begin
  Result := GetPropertyWithReceiver(GetPropertyKey(AIndex), Self);
end;

procedure TFloriaJSNamespaceObject.GetKeys(AOutKeys: TStrings);
var
  i: Integer;
begin
  if AOutKeys = nil then Exit;
  for i := 0 to ExportCount() - 1 do
    AOutKeys.Add(ExportNameAt(i));
  if FTagKey <> '' then
    AOutKeys.Add(FTagKey);
end;

end.
