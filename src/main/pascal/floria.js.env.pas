{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Lexical Scope & Runtime Environment             }
{                                                                          }
{   Provides scoped variable storage, parent scope delegation, and lookup  }
{   chains for closures, function invocations, and global environments.     }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.env;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, floria.js.types, floria.js.value;

type
  { Single Scoped Variable Binding }
  TFloriaJSBinding = record
    Name: string;
    Value: TFloriaJSValue;
    IsConst: Boolean;
  end;

  { Lexical Scope Environment }
  TFloriaJSEnvironment = class
  private
    FParent: TFloriaJSEnvironment;
    FBindings: array of TFloriaJSBinding;
    FBindingCount: Integer;

    function FindLocalIndex(const AName: string): Integer;
  public
    constructor Create(AParent: TFloriaJSEnvironment = nil);
    destructor Destroy(); override;

    procedure Define(const AName: string; const AValue: TFloriaJSValue; AIsConst: Boolean = False);
    function  Assign(const AName: string; const AValue: TFloriaJSValue): Boolean;
    function  Get(const AName: string; out AValue: TFloriaJSValue): Boolean;
    function  GetDefault(const AName: string; const ADefault: TFloriaJSValue): TFloriaJSValue;
    function  Has(const AName: string): Boolean;
    function  HasLocal(const AName: string): Boolean;

    function  GetBindingCount(): Integer;
    function  GetBindingName(AIndex: Integer): string;
    function  GetBindingValue(AIndex: Integer): TFloriaJSValue;

    property Parent: TFloriaJSEnvironment read FParent;
  end;

implementation

{ TFloriaJSEnvironment }

constructor TFloriaJSEnvironment.Create(AParent: TFloriaJSEnvironment);
begin
  inherited Create();
  FParent := AParent;
  SetLength(FBindings, 0);
  FBindingCount := 0;
end;

destructor TFloriaJSEnvironment.Destroy();
begin
  SetLength(FBindings, 0);
  inherited Destroy();
end;

function TFloriaJSEnvironment.FindLocalIndex(const AName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to FBindingCount - 1 do
  begin
    if FBindings[i].Name = AName then
      Exit(i);
  end;
  Result := -1;
end;

procedure TFloriaJSEnvironment.Define(const AName: string; const AValue: TFloriaJSValue; AIsConst: Boolean);
var
  idx: Integer;
begin
  idx := FindLocalIndex(AName);
  if idx >= 0 then
  begin
    FBindings[idx].Value := AValue;
    FBindings[idx].IsConst := AIsConst;
    Exit;
  end;

  if FBindingCount >= Length(FBindings) then
  begin
    if Length(FBindings) = 0 then
      SetLength(FBindings, 8)
    else
      SetLength(FBindings, Length(FBindings) * 2);
  end;

  FBindings[FBindingCount].Name := AName;
  FBindings[FBindingCount].Value := AValue;
  FBindings[FBindingCount].IsConst := AIsConst;
  Inc(FBindingCount);
end;

function TFloriaJSEnvironment.Assign(const AName: string; const AValue: TFloriaJSValue): Boolean;
var
  idx: Integer;
begin
  idx := FindLocalIndex(AName);
  if idx >= 0 then
  begin
    FBindings[idx].Value := AValue;
    Exit(True);
  end;

  if FParent <> nil then
    Exit(FParent.Assign(AName, AValue));

  // If not found in scope chain, define in global scope (standard JS non-strict behavior)
  Define(AName, AValue, False);
  Result := True;
end;

function TFloriaJSEnvironment.Get(const AName: string; out AValue: TFloriaJSValue): Boolean;
var
  idx: Integer;
begin
  idx := FindLocalIndex(AName);
  if idx >= 0 then
  begin
    AValue := FBindings[idx].Value;
    Exit(True);
  end;

  if FParent <> nil then
    Exit(FParent.Get(AName, AValue));

  AValue := JSMakeUndefined();
  Result := False;
end;

function TFloriaJSEnvironment.GetDefault(const AName: string; const ADefault: TFloriaJSValue): TFloriaJSValue;
var
  val: TFloriaJSValue;
begin
  if Get(AName, val) then
    Result := val
  else
    Result := ADefault;
end;

function TFloriaJSEnvironment.Has(const AName: string): Boolean;
begin
  if FindLocalIndex(AName) >= 0 then
    Exit(True);

  if FParent <> nil then
    Exit(FParent.Has(AName));

  Result := False;
end;

function TFloriaJSEnvironment.HasLocal(const AName: string): Boolean;
begin
  Result := (FindLocalIndex(AName) >= 0);
end;

function TFloriaJSEnvironment.GetBindingCount(): Integer;
begin
  Result := FBindingCount;
end;

function TFloriaJSEnvironment.GetBindingName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FBindingCount) then
    Result := FBindings[AIndex].Name
  else
    Result := '';
end;

function TFloriaJSEnvironment.GetBindingValue(AIndex: Integer): TFloriaJSValue;
begin
  if (AIndex >= 0) and (AIndex < FBindingCount) then
    Result := FBindings[AIndex].Value
  else
    Result := JSMakeUndefined();
end;

end.
