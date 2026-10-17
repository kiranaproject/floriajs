{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Declarative Reactive Property Binding System    }
{                                                                          }
{   Tracks property dependencies, detects change notifications, and        }
{   automatically re-evaluates bound expressions in topological order.     }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.qml.binding;

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  Classes, SysUtils, floria.js.types, floria.js.ast, floria.js.value,
  floria.js.env, floria.js.evaluator, floria.qml.types;

type
  { Forward Declarations }
  TFloriaQMLBindingManager = class;

  { Single Dependency Record }
  TFloriaQMLDependency = record
    SourceItem: TFloriaQMLItem;
    PropertyName: string;
  end;

  { Reactive Property Binding Node }
  TFloriaQMLBinding = class
  private
    FManager: TFloriaQMLBindingManager;
    FTargetItem: TFloriaQMLItem;
    FTargetProperty: string;
    FExpression: TFloriaJSExprNode;
    FEnv: TFloriaJSEnvironment;
    FDependencies: array of TFloriaQMLDependency;
    FDepCount: Integer;
    FIsEvaluating: Boolean;
    FEnabled: Boolean;
  public
    constructor Create(AManager: TFloriaQMLBindingManager; ATargetItem: TFloriaQMLItem;
      const ATargetProperty: string; AExpr: TFloriaJSExprNode; AEnv: TFloriaJSEnvironment);
    destructor Destroy(); override;

    procedure AddDependency(ASourceItem: TFloriaQMLItem; const APropName: string);
    procedure ClearDependencies();
    function  HasDependency(ASourceItem: TFloriaQMLItem; const APropName: string): Boolean;

    function  Evaluate(): TFloriaJSValue;

    property TargetItem: TFloriaQMLItem read FTargetItem;
    property TargetProperty: string read FTargetProperty;
    property Expression: TFloriaJSExprNode read FExpression;
    property Env: TFloriaJSEnvironment read FEnv;
    property IsEvaluating: Boolean read FIsEvaluating;
    property Enabled: Boolean read FEnabled write FEnabled;
    property DependencyCount: Integer read FDepCount;
  end;

  { Reactive Binding Manager }
  TFloriaQMLBindingManager = class(TObject, IFloriaQMLBindingManager)
  private
    FEvaluator: TFloriaJSEvaluator;
    FActiveBindings: TFPList;
    FBindings: TFPList;
    FCascadeDepth: Integer;
    FMaxCascadeDepth: Integer;

    function GetBindingCount(): Integer;
  public
    constructor Create(AEvaluator: TFloriaJSEvaluator);
    destructor Destroy(); override;

    { IFloriaQMLBindingManager Implementation }
    procedure RecordPropertyRead(AItem: TObject; const APropName: string);
    procedure NotifyPropertyChanged(AItem: TObject; const APropName: string);

    { Active Evaluation Stack }
    procedure PushActiveBinding(ABinding: TFloriaQMLBinding);
    procedure PopActiveBinding();
    function  CurrentActiveBinding(): TFloriaQMLBinding;

    { Binding Factory & Lifecycle }
    function  CreateBinding(ATargetItem: TFloriaQMLItem; const ATargetProperty: string;
      AExpr: TFloriaJSExprNode; AEnv: TFloriaJSEnvironment): TFloriaQMLBinding;
    procedure RemoveBinding(ABinding: TFloriaQMLBinding);
    procedure RemoveBindingsForTarget(ATargetItem: TObject; const ATargetProperty: string = '');

    property Evaluator: TFloriaJSEvaluator read FEvaluator write FEvaluator;
    property BindingCount: Integer read GetBindingCount;
    property MaxCascadeDepth: Integer read FMaxCascadeDepth write FMaxCascadeDepth;
  end;

implementation

{ TFloriaQMLBinding }

constructor TFloriaQMLBinding.Create(AManager: TFloriaQMLBindingManager; ATargetItem: TFloriaQMLItem;
  const ATargetProperty: string; AExpr: TFloriaJSExprNode; AEnv: TFloriaJSEnvironment);
begin
  inherited Create();
  FManager := AManager;
  FTargetItem := ATargetItem;
  FTargetProperty := ATargetProperty;
  FExpression := AExpr;
  FEnv := AEnv;
  SetLength(FDependencies, 0);
  FDepCount := 0;
  FIsEvaluating := False;
  FEnabled := True;
end;

destructor TFloriaQMLBinding.Destroy();
begin
  ClearDependencies();
  inherited Destroy();
end;

procedure TFloriaQMLBinding.AddDependency(ASourceItem: TFloriaQMLItem; const APropName: string);
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
end;

procedure TFloriaQMLBinding.ClearDependencies();
begin
  SetLength(FDependencies, 0);
  FDepCount := 0;
end;

function TFloriaQMLBinding.HasDependency(ASourceItem: TFloriaQMLItem; const APropName: string): Boolean;
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

function TFloriaQMLBinding.Evaluate(): TFloriaJSValue;
var
  newVal: TFloriaJSValue;
begin
  if (not FEnabled) or (FTargetItem = nil) or (FExpression = nil) or (FEnv = nil) then
    Exit(JSMakeUndefined());

  // Prevent recursive cycle re-entry on the same binding
  if FIsEvaluating then
    Exit(FTargetItem.GetProperty(FTargetProperty));

  FIsEvaluating := True;
  try
    // Dynamic dependency tracking: clear previous dependencies before evaluating
    ClearDependencies();

    if FManager <> nil then
      FManager.PushActiveBinding(Self);

    try
      if (FManager <> nil) and (FManager.Evaluator <> nil) then
        newVal := FManager.Evaluator.EvaluateExpr(FExpression, FEnv)
      else
        newVal := JSMakeUndefined();
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

{ TFloriaQMLBindingManager }

constructor TFloriaQMLBindingManager.Create(AEvaluator: TFloriaJSEvaluator);
begin
  inherited Create();
  FEvaluator := AEvaluator;
  FActiveBindings := TFPList.Create();
  FBindings := TFPList.Create();
  FCascadeDepth := 0;
  FMaxCascadeDepth := 100;
end;

destructor TFloriaQMLBindingManager.Destroy();
var
  i: Integer;
begin
  if FActiveBindings <> nil then
    FreeAndNil(FActiveBindings);

  if FBindings <> nil then
  begin
    for i := FBindings.Count - 1 downto 0 do
      TFloriaQMLBinding(FBindings[i]).Free();
    FreeAndNil(FBindings);
  end;
  inherited Destroy();
end;

procedure TFloriaQMLBindingManager.RecordPropertyRead(AItem: TObject; const APropName: string);
var
  curr: TFloriaQMLBinding;
begin
  curr := CurrentActiveBinding();
  if (curr <> nil) and (AItem is TFloriaQMLItem) then
    curr.AddDependency(TFloriaQMLItem(AItem), APropName);
end;

procedure TFloriaQMLBindingManager.NotifyPropertyChanged(AItem: TObject; const APropName: string);
var
  i: Integer;
  item: TFloriaQMLItem;
  binding: TFloriaQMLBinding;
  depsToUpdate: TFPList;
begin
  if not (AItem is TFloriaQMLItem) then Exit;
  item := TFloriaQMLItem(AItem);

  if FCascadeDepth >= FMaxCascadeDepth then
    Exit; // Circuit breaker for runaway cascades

  Inc(FCascadeDepth);
  depsToUpdate := TFPList.Create();
  try
    // Collect all active bindings dependent on (item, APropName)
    for i := 0 to FBindings.Count - 1 do
    begin
      binding := TFloriaQMLBinding(FBindings[i]);
      if binding.Enabled and (not binding.IsEvaluating) and binding.HasDependency(item, APropName) then
        depsToUpdate.Add(binding);
    end;

    // Re-evaluate each dependent binding
    for i := 0 to depsToUpdate.Count - 1 do
    begin
      binding := TFloriaQMLBinding(depsToUpdate[i]);
      binding.Evaluate();
    end;
  finally
    depsToUpdate.Free();
    Dec(FCascadeDepth);
  end;
end;

procedure TFloriaQMLBindingManager.PushActiveBinding(ABinding: TFloriaQMLBinding);
begin
  if (ABinding <> nil) and (FActiveBindings <> nil) then
    FActiveBindings.Add(ABinding);
end;

procedure TFloriaQMLBindingManager.PopActiveBinding();
begin
  if (FActiveBindings <> nil) and (FActiveBindings.Count > 0) then
    FActiveBindings.Delete(FActiveBindings.Count - 1);
end;

function TFloriaQMLBindingManager.CurrentActiveBinding(): TFloriaQMLBinding;
begin
  if (FActiveBindings <> nil) and (FActiveBindings.Count > 0) then
    Result := TFloriaQMLBinding(FActiveBindings[FActiveBindings.Count - 1])
  else
    Result := nil;
end;

function TFloriaQMLBindingManager.CreateBinding(ATargetItem: TFloriaQMLItem; const ATargetProperty: string;
  AExpr: TFloriaJSExprNode; AEnv: TFloriaJSEnvironment): TFloriaQMLBinding;
var
  binding: TFloriaQMLBinding;
begin
  RemoveBindingsForTarget(ATargetItem, ATargetProperty);

  binding := TFloriaQMLBinding.Create(Self, ATargetItem, ATargetProperty, AExpr, AEnv);
  FBindings.Add(binding);
  ATargetItem.AttachBinding(ATargetProperty, binding);
  Result := binding;
end;

procedure TFloriaQMLBindingManager.RemoveBinding(ABinding: TFloriaQMLBinding);
begin
  if (ABinding <> nil) and (FBindings <> nil) then
  begin
    FBindings.Remove(ABinding);
    if ABinding.TargetItem <> nil then
      ABinding.TargetItem.DetachBinding(ABinding.TargetProperty);
    ABinding.Free();
  end;
end;

procedure TFloriaQMLBindingManager.RemoveBindingsForTarget(ATargetItem: TObject; const ATargetProperty: string);
var
  i: Integer;
  binding: TFloriaQMLBinding;
begin
  if (ATargetItem = nil) or (FBindings = nil) or (not (ATargetItem is TFloriaQMLItem)) then Exit;

  for i := FBindings.Count - 1 downto 0 do
  begin
    binding := TFloriaQMLBinding(FBindings[i]);
    if (binding.TargetItem = ATargetItem) and
       ((ATargetProperty = '') or (binding.TargetProperty = ATargetProperty)) then
    begin
      FBindings.Delete(i);
      binding.TargetItem.DetachBinding(binding.TargetProperty);
      binding.Free();
    end;
  end;
end;

function TFloriaQMLBindingManager.GetBindingCount(): Integer;
begin
  if FBindings <> nil then
    Result := FBindings.Count
  else
    Result := 0;
end;

end.
