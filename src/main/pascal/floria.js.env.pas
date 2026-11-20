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
  { Binding Declarator Kind }
  TFloriaJSBindingKind = (bkVar, bkLet, bkConst, bkImport);

  { Resolves the current value of a live import binding. It is a method
    pointer so the context can carry its own state. }
  TFloriaJSImportReader = function(AModule: TObject;
    const AImportName: string): TFloriaJSValue of object;

  { Single Scoped Variable Binding }
  TFloriaJSBinding = record
    Name: string;
    Value: TFloriaJSValue;
    IsConst: Boolean;
    Kind: TFloriaJSBindingKind;
    { False between block entry and the declaration's initializer. Reading or
      assigning such a binding raises the temporal-dead-zone ReferenceError. }
    Initialized: Boolean;
    { For bkImport: the exporting module and the name inside it. A read
      resolves through them, so an import is live rather than a snapshot. }
    ImportModule: TObject;
    ImportName: string;
    ImportReader: TFloriaJSImportReader;
  end;

  { Lexical Scope Environment }
  TFloriaJSEnvironment = class
  private
    FParent: TFloriaJSEnvironment;
    FHeap: TFloriaJSHeap;
    FDelegateObject: TFloriaJSObject;
    FBindings: array of TFloriaJSBinding;
    FBindingCount: Integer;
    FCaptured: Boolean;
    FDetached: Boolean;
    FPinned: Boolean;

    function FindLocalIndex(const AName: string): Integer;
  public
    constructor Create(AParent: TFloriaJSEnvironment = nil; AHeap: TFloriaJSHeap = nil);
    destructor Destroy(); override;

    procedure Define(const AName: string; const AValue: TFloriaJSValue; AIsConst: Boolean = False; AKind: TFloriaJSBindingKind = bkVar);
    { Creates a live import binding: every read calls AReader, so a value
      changed by the exporting module is observed. }
    procedure DefineImport(const AName: string; AModule: TObject;
      const AImportName: string; AReader: TFloriaJSImportReader);
    { Defines a global built-in: a writable, non-enumerable, configurable data
      property of the global object, as clauses 18-26 require. }
    procedure DefineBuiltin(const AName: string; const AValue: TFloriaJSValue);
    { Creates an uninitialized block-scoped binding at scope entry. }
    procedure DeclareLexical(const AName: string; AIsConst: Boolean; AKind: TFloriaJSBindingKind);
    { Initializes a predeclared lexical binding. Returns False when the binding
      is not present locally (for example a per-iteration copy). }
    function  InitializeLexical(const AName: string; const AValue: TFloriaJSValue): Boolean;
    procedure DeclareVar(const AName: string);
    procedure Undefine(const AName: string);
    { Marks the environment as captured by a closure. A captured environment
      must outlive the scope it belongs to, because the closure still refers
      to it and to the scopes it is nested in. }
    procedure MarkCaptured();
    { The scope that created the environment is done with it, but a closure may
      still refer to it. The environment is not released immediately: the
      runtime decides at the next safe point whether it is still reachable. }
    procedure Detach();
    { A pinned environment is still needed by a suspended activation (for
      example an async task waiting at an await). The heap must not reclaim it
      even though the scope that created it has already been left. }
    procedure Pin();
    procedure Unpin();
    { Counts how many bindings of the environment hold the given object. }
    function  CountReferences(AObj: TFloriaJSObject): Integer;
    function  Assign(const AName: string; const AValue: TFloriaJSValue; AStrict: Boolean = False): Boolean;
    function  Get(const AName: string; out AValue: TFloriaJSValue): Boolean;
    function  GetDefault(const AName: string; const ADefault: TFloriaJSValue): TFloriaJSValue;
    function  Has(const AName: string): Boolean;
    function  HasLocal(const AName: string): Boolean;

    function  GetBindingCount(): Integer;
    function  GetBindingName(AIndex: Integer): string;
    function  GetBindingValue(AIndex: Integer): TFloriaJSValue;

    property Parent: TFloriaJSEnvironment read FParent;
    property Heap: TFloriaJSHeap read FHeap write FHeap;
    property DelegateObject: TFloriaJSObject read FDelegateObject write FDelegateObject;
    property Captured: Boolean read FCaptured;
    property Detached: Boolean read FDetached;
    property Pinned: Boolean read FPinned;
  end;

implementation

{ TFloriaJSEnvironment }

constructor TFloriaJSEnvironment.Create(AParent: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
begin
  inherited Create();
  FParent := AParent;
  if AParent <> nil then
    FHeap := AParent.Heap
  else
    FHeap := AHeap;
  FDelegateObject := nil;
  FCaptured := False;
  FDetached := False;
  FPinned := False;
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

procedure TFloriaJSEnvironment.Pin();
begin
  FPinned := True;
end;

procedure TFloriaJSEnvironment.Unpin();
begin
  FPinned := False;
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

procedure TFloriaJSEnvironment.DefineBuiltin(const AName: string;
  const AValue: TFloriaJSValue);
begin
  if (FDelegateObject <> nil) and (FParent = nil) then
  begin
    FDelegateObject.DefineDataProperty(AName, AValue, True, False, True);
    Exit;
  end;
  Define(AName, AValue, True);
end;

procedure TFloriaJSEnvironment.DefineImport(const AName: string;
  AModule: TObject; const AImportName: string; AReader: TFloriaJSImportReader);
var
  idx: Integer;
begin
  idx := FindLocalIndex(AName);
  if idx >= 0 then
  begin
    JSReleaseValue(FBindings[idx].Value);
    FBindings[idx].Value := JSMakeUndefined();
    FBindings[idx].Kind := bkImport;
    FBindings[idx].IsConst := True;
    FBindings[idx].Initialized := True;
    FBindings[idx].ImportModule := AModule;
    FBindings[idx].ImportName := AImportName;
    FBindings[idx].ImportReader := AReader;
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
  FBindings[FBindingCount].Value := JSMakeUndefined();
  FBindings[FBindingCount].Kind := bkImport;
  FBindings[FBindingCount].IsConst := True;
  FBindings[FBindingCount].Initialized := True;
  FBindings[FBindingCount].ImportModule := AModule;
  FBindings[FBindingCount].ImportName := AImportName;
  FBindings[FBindingCount].ImportReader := AReader;
  Inc(FBindingCount);
end;

procedure TFloriaJSEnvironment.Define(const AName: string; const AValue: TFloriaJSValue; AIsConst: Boolean; AKind: TFloriaJSBindingKind);
var
  idx: Integer;
begin
  { Global var/function bindings are properties of the live global object. The
    object is the delegate of the root environment; lexical let/const and
    explicitly const-published host values stay in the environment. }
  if (FDelegateObject <> nil) and (FParent = nil) and
     (AKind = bkVar) and (not AIsConst) then
  begin
    { Global function/var bindings are writable, enumerable, non-configurable
      data properties. Function declarations may replace an existing
      configurable property with these attributes. }
    FDelegateObject.DefineDataProperty(AName, AValue, True, True, False);
    Exit;
  end;

  idx := FindLocalIndex(AName);
  if idx >= 0 then
  begin
    if (FParent <> nil) and ((FBindings[idx].Kind in [bkLet, bkConst]) or (AKind in [bkLet, bkConst])) then
    begin
      if FHeap <> nil then
        raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('SyntaxError', 'Identifier ''' + AName + ''' has already been declared')))
      else
        raise Exception.Create('Identifier ''' + AName + ''' has already been declared');
    end;

    { A binding owns the value it stores: the value that is replaced gives up
      its reference and the new value takes a reference over. }
    JSReleaseValue(FBindings[idx].Value);
    FBindings[idx].Value := AValue;
    JSRetainValue(AValue);
    FBindings[idx].IsConst := AIsConst;
    FBindings[idx].Kind := AKind;
    FBindings[idx].Initialized := True;
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
  FBindings[FBindingCount].Kind := AKind;
  FBindings[FBindingCount].Initialized := True;
  Inc(FBindingCount);
end;

procedure TFloriaJSEnvironment.DeclareLexical(const AName: string;
  AIsConst: Boolean; AKind: TFloriaJSBindingKind);
var
  idx: Integer;
begin
  idx := FindLocalIndex(AName);
  if idx >= 0 then
  begin
    { Duplicate declarations in one program are rejected at compile time by
      TFloriaJSDeclarationScope. At run time an existing binding can only come
      from an earlier evaluation in the same context, or from a previous entry
      into this block, so it is reset for the new scope entry. }
    JSReleaseValue(FBindings[idx].Value);
    FBindings[idx].Value := JSMakeUndefined();
    FBindings[idx].IsConst := AIsConst;
    FBindings[idx].Kind := AKind;
    FBindings[idx].Initialized := False;
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
  FBindings[FBindingCount].Value := JSMakeUndefined();
  FBindings[FBindingCount].IsConst := AIsConst;
  FBindings[FBindingCount].Kind := AKind;
  FBindings[FBindingCount].Initialized := False;
  Inc(FBindingCount);
end;

function TFloriaJSEnvironment.InitializeLexical(const AName: string;
  const AValue: TFloriaJSValue): Boolean;
var
  idx: Integer;
begin
  idx := FindLocalIndex(AName);
  if idx < 0 then
    Exit(False);

  { Initialization is not assignment: it is allowed for a const binding, and
    it must succeed for the declaration that follows the hoisted declaration. }
  JSReleaseValue(FBindings[idx].Value);
  FBindings[idx].Value := AValue;
  JSRetainValue(AValue);
  FBindings[idx].Initialized := True;
  Result := True;
end;

procedure TFloriaJSEnvironment.DeclareVar(const AName: string);
var
  idx: Integer;
begin
  if (FDelegateObject <> nil) and (FParent = nil) then
  begin
    if not FDelegateObject.HasOwnProperty(AName) then
    begin
      FDelegateObject.SetProperty(AName, JSMakeUndefined());
      FDelegateObject.SetPropertyConfigurable(AName, False);
    end;
    Exit;
  end;

  idx := FindLocalIndex(AName);
  if idx >= 0 then Exit;
  Define(AName, JSMakeUndefined(), False, bkVar);
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
  FBindings[FBindingCount].Kind := bkVar;
  FBindings[FBindingCount].Initialized := False;
end;

procedure RaiseTemporalDeadZone(AHeap: TFloriaJSHeap; const AName: string);
var
  message: string;
begin
  message := 'Cannot access ''' + AName + ''' before initialization';
  if AHeap <> nil then
    raise EFloriaJSThrow.Create(JSMakeObject(AHeap.NewError('ReferenceError', message)))
  else
    raise Exception.Create(message);
end;

function TFloriaJSEnvironment.Assign(const AName: string; const AValue: TFloriaJSValue; AStrict: Boolean): Boolean;
var
  idx: Integer;
begin
  idx := FindLocalIndex(AName);
  if idx >= 0 then
  begin
    if not FBindings[idx].Initialized then
      RaiseTemporalDeadZone(FHeap, AName);

    if FBindings[idx].IsConst then
    begin
      if FHeap <> nil then
        raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Assignment to constant variable.')))
      else
        raise Exception.Create('Assignment to constant variable.');
    end;

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
    Exit(FParent.Assign(AName, AValue, AStrict));

  if AStrict then
  begin
    if FHeap <> nil then
      raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('ReferenceError',
        AName + ' is not defined')))
    else
      raise Exception.Create(AName + ' is not defined');
  end;

  // If not found in scope chain, define in global scope (standard JS non-strict behavior)
  if (FDelegateObject <> nil) and (FParent = nil) then
    FDelegateObject.SetProperty(AName, AValue)
  else
    Define(AName, AValue, False, bkVar);
  Result := True;
end;

function TFloriaJSEnvironment.Get(const AName: string; out AValue: TFloriaJSValue): Boolean;
var
  idx: Integer;
begin
  idx := FindLocalIndex(AName);
  if idx >= 0 then
  begin
    if not FBindings[idx].Initialized then
      RaiseTemporalDeadZone(FHeap, AName);
    if (FBindings[idx].Kind = bkImport) and
       Assigned(FBindings[idx].ImportReader) then
      AValue := FBindings[idx].ImportReader(FBindings[idx].ImportModule,
        FBindings[idx].ImportName)
    else
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
