{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Declarative QML Engine & Document Runtime       }
{                                                                          }
{   Parses QML documents, instantiates component hierarchies, wires        }
{   reactive property bindings, resolves IDs, and handles signals.         }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.qml.engine;

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  Classes, SysUtils, floria.js.types, floria.js.ast, floria.js.parser,
  floria.js.value, floria.js.env, floria.js.evaluator, floria.js.core,
  floria.qml.types, floria.qml.binding;

type
  { Declarative QML Engine }
  TFloriaQMLEngine = class(TObject, IFloriaQMLEngineContext)
  private
    FContext: TFloriaJSContext;
    FOwnsContext: Boolean;
    FBindingManager: TFloriaQMLBindingManager;
    FRootItem: TFloriaQMLItem;
    FRootAST: TFloriaJSQMLComponent;
    FRootEnv: TFloriaJSEnvironment;
    FRegistry: TStringList;
    FItemsById: TStringList;
    FLastError: string;

    function  InstantiateItem(AAST: TFloriaJSQMLComponent; AParentItem: TFloriaQMLItem; AParentEnv: TFloriaJSEnvironment): TFloriaQMLItem;
    procedure SetupItemBindings(AAST: TFloriaJSQMLComponent; AItem: TFloriaQMLItem);
    procedure TriggerCompletedSignals(AItem: TFloriaQMLItem);
  public
    constructor Create(AContext: TFloriaJSContext = nil);
    destructor Destroy(); override;

    { IFloriaQMLEngineContext Implementation }
    function GetEvaluator(): TFloriaJSEvaluator;

    { Component Type Registration }
    procedure RegisterComponentType(const ATypeName: string; AClass: TFloriaQMLItemClass);
    function  CreateItem(const ATypeName: string): TFloriaQMLItem;

    { Loading & Instantiation }
    function  LoadString(const AQMLSource: string): TFloriaQMLItem;
    function  LoadFile(const AFileName: string): TFloriaQMLItem;

    { Item Lookup & Script Execution }
    function  FindItemById(const AId: string): TFloriaQMLItem;
    function  Evaluate(const AScript: string): TFloriaJSValue;
    function  HasErrors(): Boolean;

    property JSContext: TFloriaJSContext read FContext;
    property BindingManager: TFloriaQMLBindingManager read FBindingManager;
    property Root: TFloriaQMLItem read FRootItem;
    property LastError: string read FLastError;
  end;

implementation

{ TFloriaQMLEngine }

constructor TFloriaQMLEngine.Create(AContext: TFloriaJSContext);
begin
  inherited Create();
  if AContext <> nil then
  begin
    FContext := AContext;
    FOwnsContext := False;
  end
  else
  begin
    FContext := TFloriaJSContext.Create(nil);
    FOwnsContext := True;
  end;

  FBindingManager := TFloriaQMLBindingManager.Create(FContext.Evaluator);
  FRootItem := nil;
  FRootAST := nil;
  FRootEnv := nil;
  FLastError := '';

  FRegistry := TStringList.Create();
  FRegistry.CaseSensitive := False;

  FItemsById := TStringList.Create();
  FItemsById.CaseSensitive := True;

  // Register standard built-in QML components
  RegisterComponentType('Item', TFloriaQMLItem);
  RegisterComponentType('Rectangle', TFloriaQMLRectangle);
  RegisterComponentType('Text', TFloriaQMLText);
  RegisterComponentType('Button', TFloriaQMLButton);
  RegisterComponentType('TextInput', TFloriaQMLTextInput);
  RegisterComponentType('Column', TFloriaQMLColumn);
  RegisterComponentType('Row', TFloriaQMLRow);
end;

destructor TFloriaQMLEngine.Destroy();
begin
  if FRootAST <> nil then
    FreeAndNil(FRootAST);

  if FBindingManager <> nil then
    FreeAndNil(FBindingManager);

  if FOwnsContext and (FContext <> nil) then
    FreeAndNil(FContext);

  if FRegistry <> nil then
    FreeAndNil(FRegistry);

  if FItemsById <> nil then
    FreeAndNil(FItemsById);

  inherited Destroy();
end;

function TFloriaQMLEngine.GetEvaluator(): TFloriaJSEvaluator;
begin
  if FContext <> nil then
    Result := FContext.Evaluator
  else
    Result := nil;
end;

procedure TFloriaQMLEngine.RegisterComponentType(const ATypeName: string; AClass: TFloriaQMLItemClass);
begin
  if (ATypeName <> '') and (AClass <> nil) and (FRegistry <> nil) then
    FRegistry.AddObject(ATypeName, TObject(Pointer(AClass)));
end;

function TFloriaQMLEngine.CreateItem(const ATypeName: string): TFloriaQMLItem;
var
  idx: Integer;
  itemClass: TFloriaQMLItemClass;
begin
  itemClass := TFloriaQMLItem;
  if FRegistry <> nil then
  begin
    idx := FRegistry.IndexOf(ATypeName);
    if idx >= 0 then
      itemClass := TFloriaQMLItemClass(Pointer(FRegistry.Objects[idx]));
  end;

  Result := itemClass.Create(ATypeName, Self);
  if FContext <> nil then
    FContext.Heap.Track(Result);
  Result.BindingManager := FBindingManager;
end;

function TFloriaQMLEngine.InstantiateItem(AAST: TFloriaJSQMLComponent; AParentItem: TFloriaQMLItem;
  AParentEnv: TFloriaJSEnvironment): TFloriaQMLItem;
var
  item: TFloriaQMLItem;
  itemEnv: TFloriaJSEnvironment;
  fnDecl: TFloriaJSFunctionDecl;
  fnObj: TFloriaJSFunction;
  childAST: TFloriaJSQMLComponent;
  childItem: TFloriaQMLItem;
  i: Integer;
begin
  item := CreateItem(AAST.ComponentType);
  item.Id := AAST.Id;

  // Create scoped lexical environment delegating property reads to this item
  itemEnv := TFloriaJSEnvironment.Create(AParentEnv);
  itemEnv.DelegateObject := item;
  item.Env := itemEnv;
  if FContext <> nil then
    FContext.Heap.TrackEnvironment(itemEnv);

  // Register ID globally in document root scope and global context
  if AAST.Id <> '' then
  begin
    if FRootEnv <> nil then
      FRootEnv.Define(AAST.Id, JSMakeObject(item), True);
    if FContext <> nil then
      FContext.GlobalEnv.Define(AAST.Id, JSMakeObject(item), True);
    if FItemsById <> nil then
      FItemsById.AddObject(AAST.Id, item);
  end;

  // Bind custom component functions
  for i := 0 to AAST.GetFunctionCount() - 1 do
  begin
    fnDecl := AAST.GetFunction(i);
    if fnDecl <> nil then
    begin
      fnObj := FContext.Heap.NewUserFunction(fnDecl.Name, fnDecl.Parameters, fnDecl.Body, Pointer(itemEnv));
      itemEnv.Define(fnDecl.Name, JSMakeObject(fnObj));
      item.SetProperty(fnDecl.Name, JSMakeObject(fnObj));
    end;
  end;

  // Bind signal handlers
  for i := 0 to AAST.GetSignalCount() - 1 do
  begin
    item.AddSignalHandler(AAST.GetSignalName(i), AAST.GetSignalHandler(i));
  end;

  // Hierarchy wiring
  if AParentItem <> nil then
    AParentItem.AddChild(item);

  // Recursively instantiate children
  for i := 0 to AAST.GetChildCount() - 1 do
  begin
    childAST := AAST.GetChild(i);
    childItem := InstantiateItem(childAST, item, itemEnv);
    // Child is already added to parent via AParentItem.AddChild above
    if childItem = nil then { no-op };
  end;

  Result := item;
end;

procedure TFloriaQMLEngine.SetupItemBindings(AAST: TFloriaJSQMLComponent; AItem: TFloriaQMLItem);
var
  i: Integer;
  propName: string;
  propExpr: TFloriaJSExprNode;
  litVal: TFloriaJSValue;
  binding: TFloriaQMLBinding;
  childAST: TFloriaJSQMLComponent;
  childItem: TFloriaQMLItem;
begin
  if (AAST = nil) or (AItem = nil) then Exit;

  for i := 0 to AAST.GetPropertyCount() - 1 do
  begin
    propName := AAST.GetPropertyName(i);
    propExpr := AAST.GetPropertyExpr(i);

    if (propName <> '') and (propExpr <> nil) then
    begin
      if propExpr is TFloriaJSLiteralExpr then
      begin
        // Static literal: evaluate once directly without overhead of dynamic binding
        litVal := FContext.Evaluator.EvaluateExpr(propExpr, AItem.Env);
        AItem.SetProperty(propName, litVal);
      end
      else
      begin
        // Dynamic expression: establish reactive property binding
        binding := FBindingManager.CreateBinding(AItem, propName, propExpr, AItem.Env);
        binding.Evaluate();
      end;
    end;
  end;

  // Recurse for all children
  for i := 0 to AAST.GetChildCount() - 1 do
  begin
    childAST := AAST.GetChild(i);
    childItem := AItem.GetChild(i);
    if (childAST <> nil) and (childItem <> nil) then
      SetupItemBindings(childAST, childItem);
  end;
end;

procedure TFloriaQMLEngine.TriggerCompletedSignals(AItem: TFloriaQMLItem);
var
  i: Integer;
begin
  if AItem = nil then Exit;

  // Trigger children first
  for i := 0 to AItem.ChildCount() - 1 do
    TriggerCompletedSignals(AItem.GetChild(i));

  // Trigger onCompleted signals if registered
  AItem.EmitSignal('Component.onCompleted', []);
  AItem.EmitSignal('completed', []);
end;

function TFloriaQMLEngine.LoadString(const AQMLSource: string): TFloriaQMLItem;
var
  parser: TFloriaJSParser;
  rootItem: TFloriaQMLItem;
begin
  FLastError := '';

  // Free previous bindings and AST
  if FBindingManager <> nil then
  begin
    FreeAndNil(FBindingManager);
    FBindingManager := TFloriaQMLBindingManager.Create(FContext.Evaluator);
  end;

  if FRootAST <> nil then
    FreeAndNil(FRootAST);

  if FItemsById <> nil then
    FItemsById.Clear();

  FRootItem := nil;

  // Step 1: Parse QML syntax
  parser := TFloriaJSParser.Create(AQMLSource);
  try
    FRootAST := parser.ParseQMLComponent();
    if parser.HasErrors() or (FRootAST = nil) then
    begin
      if parser.GetErrorCount() > 0 then
        FLastError := parser.GetError(0)
      else
        FLastError := 'Failed to parse QML component';
      Exit(nil);
    end;
  finally
    parser.Free();
  end;

  // Step 2: Document root lexical environment
  FRootEnv := TFloriaJSEnvironment.Create(FContext.GlobalEnv);
  FContext.Heap.TrackEnvironment(FRootEnv);

  // Step 3: Instantiate component tree
  rootItem := InstantiateItem(FRootAST, nil, FRootEnv);
  FRootItem := rootItem;

  // Step 4: Wire and evaluate reactive property bindings
  SetupItemBindings(FRootAST, rootItem);

  // Step 5: Relayout layout containers if applicable
  if rootItem is TFloriaQMLColumn then
    TFloriaQMLColumn(rootItem).Relayout()
  else if rootItem is TFloriaQMLRow then
    TFloriaQMLRow(rootItem).Relayout();

  // Step 6: Dispatch Component.onCompleted signals
  TriggerCompletedSignals(rootItem);

  Result := rootItem;
end;

function TFloriaQMLEngine.LoadFile(const AFileName: string): TFloriaQMLItem;
var
  sl: TStringList;
begin
  if not FileExists(AFileName) then
  begin
    FLastError := 'File not found: ' + AFileName;
    Exit(nil);
  end;

  sl := TStringList.Create();
  try
    sl.LoadFromFile(AFileName);
    Result := LoadString(sl.Text);
  finally
    sl.Free();
  end;
end;

function TFloriaQMLEngine.FindItemById(const AId: string): TFloriaQMLItem;
var
  idx: Integer;
begin
  if (FItemsById <> nil) and (AId <> '') then
  begin
    idx := FItemsById.IndexOf(AId);
    if idx >= 0 then
      Exit(TFloriaQMLItem(FItemsById.Objects[idx]));
  end;

  if FRootItem <> nil then
    Result := FRootItem.FindById(AId)
  else
    Result := nil;
end;

function TFloriaQMLEngine.Evaluate(const AScript: string): TFloriaJSValue;
var
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  targetEnv: TFloriaJSEnvironment;
begin
  if FContext = nil then Exit(JSMakeUndefined());

  if FRootEnv <> nil then
    targetEnv := FRootEnv
  else
    targetEnv := FContext.GlobalEnv;

  parser := TFloriaJSParser.Create(AScript);
  try
    prog := parser.ParseProgram();
    try
      Result := FContext.Evaluator.ExecuteProgram(prog, targetEnv);
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;
end;

function TFloriaQMLEngine.HasErrors(): Boolean;
begin
  Result := (FLastError <> '');
end;

end.
