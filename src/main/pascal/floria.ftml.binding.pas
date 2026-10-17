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
  Classes, SysUtils, floria.js.types, floria.js.ast, floria.js.value,
  floria.js.env, floria.js.evaluator, floria.ftml.types;

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

    property TargetItem: TFloriaFTMLItem read FTargetItem;
    property TargetProperty: string read FTargetProperty;
    property Expression: TFloriaJSExprNode read FExpression;
    property Env: TFloriaJSEnvironment read FEnv;
    property IsEvaluating: Boolean read FIsEvaluating;
    property Enabled: Boolean read FEnabled write FEnabled;
    property DependencyCount: Integer read FDepCount;
  end;

  { Reactive Binding Manager }
  TFloriaFTMLBindingManager = class(TObject, IFloriaFTMLBindingManager)
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

    property Evaluator: TFloriaJSEvaluator read FEvaluator write FEvaluator;
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
  SetLength(FDependencies, 0);
  FDepCount := 0;
  FIsEvaluating := False;
  FEnabled := True;
end;

destructor TFloriaFTMLBinding.Destroy();
begin
  ClearDependencies();
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
end;

procedure TFloriaFTMLBinding.ClearDependencies();
begin
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

function TFloriaFTMLBinding.Evaluate(): TFloriaJSValue;
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

{ TFloriaFTMLBindingManager }

constructor TFloriaFTMLBindingManager.Create(AEvaluator: TFloriaJSEvaluator);
begin
  inherited Create();
  FEvaluator := AEvaluator;
  FActiveBindings := TFPList.Create();
  FBindings := TFPList.Create();
  FCascadeDepth := 0;
  FMaxCascadeDepth := 100;
end;

destructor TFloriaFTMLBindingManager.Destroy();
var
  i: Integer;
begin
  if FActiveBindings <> nil then
    FreeAndNil(FActiveBindings);

  if FBindings <> nil then
  begin
    for i := FBindings.Count - 1 downto 0 do
      TFloriaFTMLBinding(FBindings[i]).Free();
    FreeAndNil(FBindings);
  end;
  inherited Destroy();
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
  depsToUpdate: TFPList;
begin
  if not (AItem is TFloriaFTMLItem) then Exit;
  item := TFloriaFTMLItem(AItem);

  if FCascadeDepth >= FMaxCascadeDepth then
    Exit; // Circuit breaker for runaway cascades

  Inc(FCascadeDepth);
  depsToUpdate := TFPList.Create();
  try
    // Collect all active bindings dependent on (item, APropName)
    for i := 0 to FBindings.Count - 1 do
    begin
      binding := TFloriaFTMLBinding(FBindings[i]);
      if binding.Enabled and (not binding.IsEvaluating) and binding.HasDependency(item, APropName) then
        depsToUpdate.Add(binding);
    end;

    // Re-evaluate each dependent binding
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
