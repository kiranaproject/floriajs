{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Declarative Reactive Property Binding System    }
{   (Floria Toolkit Markup Language)                                       }
{                                                                          }
{   Tracks property dependencies, detects change notifications, and        }
{   automatically re-evaluates bound expressions in topological order.     }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.ftml.binding;

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  Classes, SysUtils, floria.js.types, floria.js.lexer, floria.js.ast, floria.js.value,
  floria.js.env, floria.js.bytecode, floria.js.vm, floria.js.compiler,
  floria.ftml.types;

type
  { Forward Declarations }
  TFloriaFTMLBindingManager = class;

  { Single Dependency Record }
  TFloriaFTMLDependency = record
    SourceItem: TFloriaFTMLItem;
    PropertyName: string;
  end;

  { Reactive Property Binding Node }
  TFloriaFTMLBinding = class
  private
    FManager: TFloriaFTMLBindingManager;
    FTargetItem: TFloriaFTMLItem;
    FTargetProperty: string;
    FExpression: TFloriaJSExprNode;
    FBytecode: TFloriaJSBytecode;
    FEnv: TFloriaJSEnvironment;
    FDependencies: array of TFloriaFTMLDependency;
    FDepCount: Integer;
    FIsEvaluating: Boolean;
    FEnabled: Boolean;
  public
    constructor Create(AManager: TFloriaFTMLBindingManager; ATargetItem: TFloriaFTMLItem;
      const ATargetProperty: string; AExpr: TFloriaJSExprNode; AEnv: TFloriaJSEnvironment);
    destructor Destroy(); override;

    procedure AddDependency(ASourceItem: TFloriaFTMLItem; const APropName: string);
    procedure ClearDependencies();
    function  HasDependency(ASourceItem: TFloriaFTMLItem; const APropName: string): Boolean;

    function  Evaluate(): TFloriaJSValue;
    function  TryFastValue(AExpr: TFloriaJSExprNode;
      out AValue: TFloriaJSValue): Boolean;
    function  TryFastEvaluate(out AValue: TFloriaJSValue): Boolean;

    property TargetItem: TFloriaFTMLItem read FTargetItem;
    property TargetProperty: string read FTargetProperty;
    property Expression: TFloriaJSExprNode read FExpression;
    property Bytecode: TFloriaJSBytecode read FBytecode;
    property Env: TFloriaJSEnvironment read FEnv;
    property IsEvaluating: Boolean read FIsEvaluating;
    property Enabled: Boolean read FEnabled write FEnabled;
    property DependencyCount: Integer read FDepCount;
  end;

  { Reactive Binding Manager }
  TFloriaFTMLBindingManager = class(TObject, IFloriaFTMLBindingManager)
  private
    FVM: TFloriaJSVM;
    FCompiler: TFloriaJSCompiler;
    FActiveBindings: TFPList;
    FBindings: TFPList;
    FCascadeDepth: Integer;
    FMaxCascadeDepth: Integer;
    FDependencyIndex: TStringList;
    FShuttingDown: Boolean;

    function GetBindingCount(): Integer;
    function DependencyKey(AItem: TFloriaFTMLItem; const APropName: string): string;
    procedure IndexDependency(ABinding: TFloriaFTMLBinding; AItem: TFloriaFTMLItem;
      const APropName: string);
    procedure UnindexDependency(ABinding: TFloriaFTMLBinding; AItem: TFloriaFTMLItem;
      const APropName: string);
  public
    constructor Create(AVM: TFloriaJSVM = nil; ACompiler: TFloriaJSCompiler = nil);
    destructor Destroy(); override;

    { IFloriaFTMLBindingManager Implementation }
    procedure RecordPropertyRead(AItem: TObject; const APropName: string);
    procedure NotifyPropertyChanged(AItem: TObject; const APropName: string);
    procedure RemoveBindingsForTarget(ATargetItem: TObject; const ATargetProperty: string = '');

    { Active Evaluation Stack }
    procedure PushActiveBinding(ABinding: TFloriaFTMLBinding);
    procedure PopActiveBinding();
    function  CurrentActiveBinding(): TFloriaFTMLBinding;

    { Binding Factory & Lifecycle }
    function  CreateBinding(ATargetItem: TFloriaFTMLItem; const ATargetProperty: string;
      AExpr: TFloriaJSExprNode; AEnv: TFloriaJSEnvironment): TFloriaFTMLBinding;
    procedure RemoveBinding(ABinding: TFloriaFTMLBinding);

    property VM: TFloriaJSVM read FVM write FVM;
    property Compiler: TFloriaJSCompiler read FCompiler write FCompiler;
    property BindingCount: Integer read GetBindingCount;
    property MaxCascadeDepth: Integer read FMaxCascadeDepth write FMaxCascadeDepth;
  end;

implementation

{ TFloriaFTMLBinding }

constructor TFloriaFTMLBinding.Create(AManager: TFloriaFTMLBindingManager; ATargetItem: TFloriaFTMLItem;
  const ATargetProperty: string; AExpr: TFloriaJSExprNode; AEnv: TFloriaJSEnvironment);
begin
  inherited Create();
  FManager := AManager;
  FTargetItem := ATargetItem;
  FTargetProperty := ATargetProperty;
  FExpression := AExpr;
  FEnv := AEnv;
  FBytecode := nil;
  if (FManager <> nil) and (FManager.Compiler <> nil) and (FExpression <> nil) then
    FBytecode := FManager.Compiler.CompileExpression(FExpression);
  SetLength(FDependencies, 0);
  FDepCount := 0;
  FIsEvaluating := False;
  FEnabled := True;
end;

destructor TFloriaFTMLBinding.Destroy();
begin
  ClearDependencies();
  if FBytecode <> nil then
  begin
    FBytecode.Release();
    FBytecode := nil;
  end;
  inherited Destroy();
end;

procedure TFloriaFTMLBinding.AddDependency(ASourceItem: TFloriaFTMLItem; const APropName: string);
begin
  if (ASourceItem = nil) or (APropName = '') then Exit;
  if HasDependency(ASourceItem, APropName) then Exit;

  if FDepCount >= Length(FDependencies) then
  begin
    if Length(FDependencies) = 0 then
      SetLength(FDependencies, 4)
    else
      SetLength(FDependencies, Length(FDependencies) * 2);
  end;

  FDependencies[FDepCount].SourceItem := ASourceItem;
  FDependencies[FDepCount].PropertyName := APropName;
  Inc(FDepCount);
  if FManager <> nil then
    FManager.IndexDependency(Self, ASourceItem, APropName);
end;

procedure TFloriaFTMLBinding.ClearDependencies();
var
  i: Integer;
begin
  if FManager <> nil then
    for i := 0 to FDepCount - 1 do
      FManager.UnindexDependency(Self, FDependencies[i].SourceItem,
        FDependencies[i].PropertyName);
  SetLength(FDependencies, 0);
  FDepCount := 0;
end;

function TFloriaFTMLBinding.HasDependency(ASourceItem: TFloriaFTMLItem; const APropName: string): Boolean;
var
  i: Integer;
begin
  for i := 0 to FDepCount - 1 do
  begin
    if (FDependencies[i].SourceItem = ASourceItem) and (FDependencies[i].PropertyName = APropName) then
      Exit(True);
  end;
  Result := False;
end;

function TFloriaFTMLBinding.TryFastValue(AExpr: TFloriaJSExprNode;
  out AValue: TFloriaJSValue): Boolean;
var
  bin: TFloriaJSBinaryExpr;
  member: TFloriaJSMemberExpr;
  ident: TFloriaJSIdentifierExpr;
  lit: TFloriaJSLiteralExpr;
  leftVal, rightVal: TFloriaJSValue;
  item: TFloriaFTMLItem;
begin
  AValue := JSMakeUndefined();
  if AExpr = nil then
    Exit(False);

  if AExpr is TFloriaJSGroupExpr then
    Exit(TryFastValue(TFloriaJSGroupExpr(AExpr).Expression, AValue));

  if AExpr is TFloriaJSLiteralExpr then
  begin
    lit := TFloriaJSLiteralExpr(AExpr);
    case lit.ValueType of
      fjstNumber: AValue := JSMakeNumber(lit.NumberVal);
      fjstString: AValue := JSMakeString(lit.StringVal);
      fjstBoolean: AValue := JSMakeBoolean(lit.BoolVal);
      fjstNull: AValue := JSMakeNull();
      fjstUndefined: AValue := JSMakeUndefined();
    else
      Exit(False);
    end;
    Exit(True);
  end;

  if AExpr is TFloriaJSMemberExpr then
  begin
    member := TFloriaJSMemberExpr(AExpr);
    if member.Computed or (not (member.Target is TFloriaJSIdentifierExpr)) then
      Exit(False);
    ident := TFloriaJSIdentifierExpr(member.Target);
    if not FEnv.Get(ident.Name, leftVal) then
      Exit(False);
    if not (leftVal.IsObject() and (leftVal.ObjVal is TFloriaFTMLItem)) then
      Exit(False);
    item := TFloriaFTMLItem(leftVal.ObjVal);
    AValue := item.GetProperty(member.PropertyName);
    AddDependency(item, member.PropertyName);
    Exit(True);
  end;

  if AExpr is TFloriaJSBinaryExpr then
  begin
    bin := TFloriaJSBinaryExpr(AExpr);
    if not (bin.Op in [tkPlus, tkMinus, tkMultiply, tkDivide]) then
      Exit(False);
    if not TryFastValue(bin.Left, leftVal) then
      Exit(False);
    if not TryFastValue(bin.Right, rightVal) then
      Exit(False);
    case bin.Op of
      tkPlus: AValue := JSAdd(leftVal, rightVal);
      tkMinus: AValue := JSSubtract(leftVal, rightVal);
      tkMultiply: AValue := JSMultiply(leftVal, rightVal);
      tkDivide: AValue := JSDivide(leftVal, rightVal);
    end;
    Exit(True);
  end;

  Result := False;
end;

function TFloriaFTMLBinding.TryFastEvaluate(out AValue: TFloriaJSValue): Boolean;
begin
  if FExpression = nil then
    Exit(False);
  Result := TryFastValue(FExpression, AValue);
end;

function TFloriaFTMLBinding.Evaluate(): TFloriaJSValue;
var
  newVal: TFloriaJSValue;
begin
  if (not FEnabled) or (FTargetItem = nil) or (FEnv = nil) then
    Exit(JSMakeUndefined());

  // Prevent recursive cycle re-entry on the same binding
  if FIsEvaluating then
    Exit(FTargetItem.GetProperty(FTargetProperty));

  FIsEvaluating := True;
  try
    { Dependencies are cached. Keeping the previous set is conservative: a
      property that is no longer read may cause an extra re-evaluation, but it
      can never miss one. This avoids tearing down and rebuilding the dependency
      index on every update. }
    if FManager <> nil then
      FManager.PushActiveBinding(Self);

    try
      try
        if (FBytecode = nil) and (FManager <> nil) and (FManager.Compiler <> nil) and (FExpression <> nil) then
          FBytecode := FManager.Compiler.CompileExpression(FExpression);

        if TryFastEvaluate(newVal) then
        begin
          { The snippet handled a simple member/arithmetic expression without a
            VM frame; dependencies were recorded directly. }
        end
        else if (FBytecode <> nil) and (FManager <> nil) and (FManager.VM <> nil) then
          newVal := FManager.VM.Execute(FBytecode, FEnv)
        else
          newVal := JSMakeUndefined();
      except
        on E: Exception do
          newVal := JSMakeUndefined();
      end;
    finally
      if FManager <> nil then
        FManager.PopActiveBinding();
    end;

    // Apply evaluated value to target item without breaking this binding
    FTargetItem.SetPropertyFromBinding(FTargetProperty, newVal);
    Result := newVal;
  finally
    FIsEvaluating := False;
  end;
end;

{ TFloriaFTMLBindingManager }

constructor TFloriaFTMLBindingManager.Create(AVM: TFloriaJSVM; ACompiler: TFloriaJSCompiler);
begin
  inherited Create();
  FVM := AVM;
  FCompiler := ACompiler;
  FActiveBindings := TFPList.Create();
  FBindings := TFPList.Create();
  FCascadeDepth := 0;
  FMaxCascadeDepth := 100;
  FShuttingDown := False;
  FDependencyIndex := TStringList.Create;
  FDependencyIndex.Sorted := True;
  FDependencyIndex.Duplicates := dupIgnore;
  FDependencyIndex.NameValueSeparator := #0;
end;

destructor TFloriaFTMLBindingManager.Destroy();
var
  i: Integer;
begin
  if FActiveBindings <> nil then
    FreeAndNil(FActiveBindings);

  FShuttingDown := True;
  if FBindings <> nil then
  begin
    for i := FBindings.Count - 1 downto 0 do
      TFloriaFTMLBinding(FBindings[i]).Free();
    FreeAndNil(FBindings);
  end;
  if FDependencyIndex <> nil then
  begin
    for i := 0 to FDependencyIndex.Count - 1 do
      FDependencyIndex.Objects[i].Free();
    FreeAndNil(FDependencyIndex);
  end;
  inherited Destroy();
end;

function TFloriaFTMLBindingManager.DependencyKey(AItem: TFloriaFTMLItem;
  const APropName: string): string;
begin
  Result := IntToStr(PtrUInt(AItem)) + #0 + APropName;
end;

procedure TFloriaFTMLBindingManager.IndexDependency(ABinding: TFloriaFTMLBinding;
  AItem: TFloriaFTMLItem; const APropName: string);
var
  key: string;
  idx: Integer;
  list: TFPList;
begin
  if FShuttingDown or (ABinding = nil) or (AItem = nil) then Exit;
  key := DependencyKey(AItem, APropName);
  idx := FDependencyIndex.IndexOf(key);
  if idx < 0 then
  begin
    list := TFPList.Create();
    FDependencyIndex.AddObject(key, list);
  end
  else
    list := TFPList(FDependencyIndex.Objects[idx]);
  if list.IndexOf(ABinding) < 0 then
    list.Add(ABinding);
end;

procedure TFloriaFTMLBindingManager.UnindexDependency(ABinding: TFloriaFTMLBinding;
  AItem: TFloriaFTMLItem; const APropName: string);
var
  key: string;
  idx, pos: Integer;
  list: TFPList;
begin
  if FShuttingDown or (ABinding = nil) or (AItem = nil) or (FDependencyIndex = nil) then Exit;
  key := DependencyKey(AItem, APropName);
  idx := FDependencyIndex.IndexOf(key);
  if idx < 0 then Exit;
  list := TFPList(FDependencyIndex.Objects[idx]);
  pos := list.IndexOf(ABinding);
  if pos >= 0 then
    list.Delete(pos);
  if list.Count = 0 then
  begin
    FDependencyIndex.Delete(idx);
    list.Free();
  end;
end;

procedure TFloriaFTMLBindingManager.RecordPropertyRead(AItem: TObject; const APropName: string);
var
  curr: TFloriaFTMLBinding;
begin
  curr := CurrentActiveBinding();
  if (curr <> nil) and (AItem is TFloriaFTMLItem) then
    curr.AddDependency(TFloriaFTMLItem(AItem), APropName);
end;

procedure TFloriaFTMLBindingManager.NotifyPropertyChanged(AItem: TObject; const APropName: string);
var
  i: Integer;
  item: TFloriaFTMLItem;
  binding: TFloriaFTMLBinding;
  depsToUpdate, source: TFPList;
  idx: Integer;
begin
  if not (AItem is TFloriaFTMLItem) then Exit;
  item := TFloriaFTMLItem(AItem);

  if FCascadeDepth >= FMaxCascadeDepth then
    Exit; // Circuit breaker for runaway cascades

  Inc(FCascadeDepth);
  depsToUpdate := TFPList.Create();
  try
    idx := FDependencyIndex.IndexOf(DependencyKey(item, APropName));
    if idx >= 0 then
    begin
      source := TFPList(FDependencyIndex.Objects[idx]);
      for i := 0 to source.Count - 1 do
      begin
        binding := TFloriaFTMLBinding(source[i]);
        if binding.Enabled and (not binding.IsEvaluating) then
          depsToUpdate.Add(binding);
      end;
    end;

    for i := 0 to depsToUpdate.Count - 1 do
    begin
      binding := TFloriaFTMLBinding(depsToUpdate[i]);
      binding.Evaluate();
    end;
  finally
    depsToUpdate.Free();
    Dec(FCascadeDepth);
  end;
end;

procedure TFloriaFTMLBindingManager.PushActiveBinding(ABinding: TFloriaFTMLBinding);
begin
  if (ABinding <> nil) and (FActiveBindings <> nil) then
    FActiveBindings.Add(ABinding);
end;

procedure TFloriaFTMLBindingManager.PopActiveBinding();
begin
  if (FActiveBindings <> nil) and (FActiveBindings.Count > 0) then
    FActiveBindings.Delete(FActiveBindings.Count - 1);
end;

function TFloriaFTMLBindingManager.CurrentActiveBinding(): TFloriaFTMLBinding;
begin
  if (FActiveBindings <> nil) and (FActiveBindings.Count > 0) then
    Result := TFloriaFTMLBinding(FActiveBindings[FActiveBindings.Count - 1])
  else
    Result := nil;
end;

function TFloriaFTMLBindingManager.CreateBinding(ATargetItem: TFloriaFTMLItem; const ATargetProperty: string;
  AExpr: TFloriaJSExprNode; AEnv: TFloriaJSEnvironment): TFloriaFTMLBinding;
var
  binding: TFloriaFTMLBinding;
begin
  RemoveBindingsForTarget(ATargetItem, ATargetProperty);

  binding := TFloriaFTMLBinding.Create(Self, ATargetItem, ATargetProperty, AExpr, AEnv);
  FBindings.Add(binding);
  ATargetItem.AttachBinding(ATargetProperty, binding);
  Result := binding;
end;

procedure TFloriaFTMLBindingManager.RemoveBinding(ABinding: TFloriaFTMLBinding);
begin
  if (ABinding <> nil) and (FBindings <> nil) then
  begin
    FBindings.Remove(ABinding);
    if ABinding.TargetItem <> nil then
      ABinding.TargetItem.DetachBinding(ABinding.TargetProperty);
    ABinding.Free();
  end;
end;

procedure TFloriaFTMLBindingManager.RemoveBindingsForTarget(ATargetItem: TObject; const ATargetProperty: string);
var
  i: Integer;
  binding: TFloriaFTMLBinding;
begin
  if (ATargetItem = nil) or (FBindings = nil) or (not (ATargetItem is TFloriaFTMLItem)) then Exit;

  for i := FBindings.Count - 1 downto 0 do
  begin
    binding := TFloriaFTMLBinding(FBindings[i]);
    if (binding.TargetItem = TFloriaFTMLItem(ATargetItem)) and
       ((ATargetProperty = '') or (binding.TargetProperty = ATargetProperty)) then
    begin
      FBindings.Delete(i);
      binding.TargetItem.DetachBinding(binding.TargetProperty);
      binding.Free();
    end;
  end;
end;

function TFloriaFTMLBindingManager.GetBindingCount(): Integer;
begin
  if FBindings <> nil then
    Result := FBindings.Count
  else
    Result := 0;
end;

end.
