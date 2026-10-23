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
    FDelegateObject: TFloriaJSObject;
    FBindings: array of TFloriaJSBinding;
    FBindingCount: Integer;
    FCaptured: Boolean;
    FDetached: Boolean;

    function FindLocalIndex(const AName: string): Integer;
  public
    constructor Create(AParent: TFloriaJSEnvironment = nil);
    destructor Destroy(); override;

    procedure Define(const AName: string; const AValue: TFloriaJSValue; AIsConst: Boolean = False);
    procedure Undefine(const AName: string);
    { Marks the environment as captured by a closure. A captured environment
      must outlive the scope it belongs to, because the closure still refers
      to it and to the scopes it is nested in. }
    procedure MarkCaptured();
    { The scope that created the environment is done with it, but a closure may
      still refer to it. The environment is not released immediately: the
      runtime decides at the next safe point whether it is still reachable. }
    procedure Detach();
    { Counts how many bindings of the environment hold the given object. }
    function  CountReferences(AObj: TFloriaJSObject): Integer;
    function  Assign(const AName: string; const AValue: TFloriaJSValue): Boolean;
    function  Get(const AName: string; out AValue: TFloriaJSValue): Boolean;
    function  GetDefault(const AName: string; const ADefault: TFloriaJSValue): TFloriaJSValue;
    function  Has(const AName: string): Boolean;
    function  HasLocal(const AName: string): Boolean;

    function  GetBindingCount(): Integer;
    function  GetBindingName(AIndex: Integer): string;
    function  GetBindingValue(AIndex: Integer): TFloriaJSValue;

    property Parent: TFloriaJSEnvironment read FParent;
    property DelegateObject: TFloriaJSObject read FDelegateObject write FDelegateObject;
    property Captured: Boolean read FCaptured;
    property Detached: Boolean read FDetached;
  end;

implementation

{ TFloriaJSEnvironment }

constructor TFloriaJSEnvironment.Create(AParent: TFloriaJSEnvironment);
begin
  inherited Create();
  FParent := AParent;
  FDelegateObject := nil;
  FCaptured := False;
  FDetached := False;
  SetLength(FBindings, 0);
  FBindingCount := 0;
end;

destructor TFloriaJSEnvironment.Destroy();
var
  i: Integer;
begin
  { Every binding holds a reference to the value it stores. }
  for i := 0 to FBindingCount - 1 do
    JSReleaseValue(FBindings[i].Value);
  SetLength(FBindings, 0);
  FBindingCount := 0;
  inherited Destroy();
end;

procedure TFloriaJSEnvironment.MarkCaptured();
var
  env: TFloriaJSEnvironment;
begin
  { The scopes the environment is nested in are marked as well, because a
    closure that captured the environment reaches them too. }
  env := Self;
  while env <> nil do
  begin
    env.FCaptured := True;
    env := env.FParent;
  end;
end;

procedure TFloriaJSEnvironment.Detach();
begin
  FDetached := True;
end;

function TFloriaJSEnvironment.CountReferences(AObj: TFloriaJSObject): Integer;
var
  i: Integer;
begin
  Result := 0;
  if AObj = nil then Exit;
  for i := 0 to FBindingCount - 1 do
    if FBindings[i].Value.IsObject() and (FBindings[i].Value.ObjVal = AObj) then
      Inc(Result);
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
    { A binding owns the value it stores: the value that is replaced gives up
      its reference and the new value takes a reference over. }
    JSReleaseValue(FBindings[idx].Value);
    FBindings[idx].Value := AValue;
    JSRetainValue(AValue);
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
  JSRetainValue(AValue);
  FBindings[FBindingCount].IsConst := AIsConst;
  Inc(FBindingCount);
end;

procedure TFloriaJSEnvironment.Undefine(const AName: string);
var
  idx, i: Integer;
begin
  idx := FindLocalIndex(AName);
  if idx < 0 then Exit;

  { The removed binding gives up the reference it held. The reference is given
    up before the bindings are shifted, because the shift moves the value of
    the next binding into the slot of the removed one. }
  JSReleaseValue(FBindings[idx].Value);

  for i := idx to FBindingCount - 2 do
    FBindings[i] := FBindings[i + 1];

  Dec(FBindingCount);
  FBindings[FBindingCount].Name := '';
  FBindings[FBindingCount].Value := JSMakeUndefined();
  FBindings[FBindingCount].IsConst := False;
end;

function TFloriaJSEnvironment.Assign(const AName: string; const AValue: TFloriaJSValue): Boolean;
var
  idx: Integer;
begin
  idx := FindLocalIndex(AName);
  if idx >= 0 then
  begin
    { A binding owns the value it stores: the value that is replaced gives up
      its reference and the new value takes a reference over. }
    JSReleaseValue(FBindings[idx].Value);
    FBindings[idx].Value := AValue;
    JSRetainValue(AValue);
    Exit(True);
  end;

  if (FDelegateObject <> nil) and (AName <> 'this') and FDelegateObject.HasProperty(AName) then
  begin
    FDelegateObject.SetProperty(AName, AValue);
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

  if FDelegateObject <> nil then
  begin
    if AName = 'this' then
    begin
      AValue := JSMakeObject(FDelegateObject);
      Exit(True);
    end;
    if FDelegateObject.HasProperty(AName) then
    begin
      AValue := FDelegateObject.GetProperty(AName);
      Exit(True);
    end;
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

  if FDelegateObject <> nil then
  begin
    if (AName = 'this') or FDelegateObject.HasProperty(AName) then
      Exit(True);
  end;

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
