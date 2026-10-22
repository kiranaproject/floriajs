{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Declarative FTML Engine & Document Runtime      }
{   (Floria Toolkit Markup Language)                                       }
{                                                                          }
{   Parses FTML documents, instantiates component hierarchies, wires       }
{   reactive property bindings, resolves IDs, and handles signals.         }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.ftml.engine;

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  Classes, SysUtils, floria.js.types, floria.js.ast, floria.js.parser,
  floria.js.value, floria.js.env, floria.js.evaluator, floria.js.core,
  floria.ftml.types, floria.ftml.binding;

type
  { Declarative FTML Engine }
  TFloriaFTMLEngine = class(TObject, IFloriaFTMLEngineContext)
  private
    FContext: TFloriaJSContext;
    FOwnsContext: Boolean;
    FBindingManager: TFloriaFTMLBindingManager;
    FRootItem: TFloriaFTMLItem;
    FRootAST: TFloriaFTMLComponent;
    FRootEnv: TFloriaJSEnvironment;
    FRegistry: TStringList;
    FItemsById: TStringList;
    FDocumentObjects: TFPList;
    FEscapedObjects: TFPList;
    FEscapedASTs: TFPList;
    FDocumentEscaped: Boolean;
    FLastError: string;

    function  InstantiateItem(AAST: TFloriaFTMLComponent; AParentItem: TFloriaFTMLItem; AParentEnv: TFloriaJSEnvironment): TFloriaFTMLItem;
    procedure SetupItemBindings(AAST: TFloriaFTMLComponent; AItem: TFloriaFTMLItem);
    procedure TriggerCompletedSignals(AItem: TFloriaFTMLItem);
    procedure ReleaseDocument();
    procedure RemoveDocumentIds();
    function  DocumentHasRuntimeClosure(): Boolean;
    procedure ReleaseObjects(AObjects: TFPList);
    procedure ReleaseEscapedDocuments();
  public
    constructor Create(AContext: TFloriaJSContext = nil);
    destructor Destroy(); override;

    { IFloriaFTMLEngineContext Implementation }
    function GetEvaluator(): TFloriaJSEvaluator;

    { Component Type Registration }
    procedure RegisterComponentType(const ATypeName: string; AClass: TFloriaFTMLItemClass);
    function  CreateItem(const ATypeName: string): TFloriaFTMLItem;

    { Loading & Instantiation }
    function  LoadString(const AFTMLSource: string): TFloriaFTMLItem;
    function  LoadFile(const AFileName: string): TFloriaFTMLItem;

    { Item Lookup & Script Execution }
    function  FindItemById(const AId: string): TFloriaFTMLItem;
    function  Evaluate(const AScript: string): TFloriaJSValue;
    procedure ReleaseValue(const AValue: TFloriaJSValue);
    function  HasErrors(): Boolean;

    property JSContext: TFloriaJSContext read FContext;
    property BindingManager: TFloriaFTMLBindingManager read FBindingManager;
    property Root: TFloriaFTMLItem read FRootItem;
    property LastError: string read FLastError;
  end;

implementation

{ TFloriaFTMLEngine }

constructor TFloriaFTMLEngine.Create(AContext: TFloriaJSContext);
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

  FBindingManager := TFloriaFTMLBindingManager.Create(FContext.Evaluator);
  FRootItem := nil;
  FRootAST := nil;
  FRootEnv := nil;
  FLastError := '';

  FRegistry := TStringList.Create();
  FRegistry.CaseSensitive := False;

  FItemsById := TStringList.Create();
  FItemsById.CaseSensitive := True;

  FDocumentObjects := TFPList.Create();
  FEscapedObjects := TFPList.Create();
  FEscapedASTs := TFPList.Create();
  FDocumentEscaped := False;

  // Register standard built-in FTML components
  RegisterComponentType('Item', TFloriaFTMLItem);
  RegisterComponentType('Rectangle', TFloriaFTMLRectangle);
  RegisterComponentType('Text', TFloriaFTMLText);
  RegisterComponentType('Button', TFloriaFTMLButton);
  RegisterComponentType('TextInput', TFloriaFTMLTextInput);
  RegisterComponentType('Column', TFloriaFTMLColumn);
  RegisterComponentType('Row', TFloriaFTMLRow);
  RegisterComponentType('FlexBox', TFloriaFTMLFlexBox);
  RegisterComponentType('Grid', TFloriaFTMLGrid);
end;

destructor TFloriaFTMLEngine.Destroy();
begin
  { Release the live document first: bindings reference AST nodes and target
    items, so they must be destroyed while both are still valid. }
  ReleaseDocument();

  { The documents a runtime closure still refers to are kept alive until the
    engine goes away. They are released before the runtime, because their
    objects hold references to values of the runtime. }
  ReleaseEscapedDocuments();

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

  if FDocumentObjects <> nil then
    FreeAndNil(FDocumentObjects);

  if FEscapedObjects <> nil then
    FreeAndNil(FEscapedObjects);

  if FEscapedASTs <> nil then
    FreeAndNil(FEscapedASTs);

  inherited Destroy();
end;

function TFloriaFTMLEngine.GetEvaluator(): TFloriaJSEvaluator;
begin
  if FContext <> nil then
    Result := FContext.Evaluator
  else
    Result := nil;
end;

procedure TFloriaFTMLEngine.RegisterComponentType(const ATypeName: string; AClass: TFloriaFTMLItemClass);
begin
  if (ATypeName <> '') and (AClass <> nil) and (FRegistry <> nil) then
    FRegistry.AddObject(ATypeName, TObject(Pointer(AClass)));
end;

function TFloriaFTMLEngine.CreateItem(const ATypeName: string): TFloriaFTMLItem;
var
  idx: Integer;
  itemClass: TFloriaFTMLItemClass;
begin
  itemClass := TFloriaFTMLItem;
  if FRegistry <> nil then
  begin
    idx := FRegistry.IndexOf(ATypeName);
    if idx >= 0 then
      itemClass := TFloriaFTMLItemClass(Pointer(FRegistry.Objects[idx]));
  end;

  Result := itemClass.Create(ATypeName, Self);
  if FContext <> nil then
  begin
    { The item belongs to the document, not to the heap, so the heap only
      keeps track of it without ever reclaiming it on its own. }
    FContext.Heap.Track(Result, False);
    Result.RememberHeap(FContext.Heap);
  end;
  Result.BindingManager := FBindingManager;

  { The item belongs to the current document: it is released again when the
    document is unloaded instead of being retained by the shared JS heap. }
  if FDocumentObjects <> nil then
    FDocumentObjects.Add(Result);
end;

function TFloriaFTMLEngine.InstantiateItem(AAST: TFloriaFTMLComponent; AParentItem: TFloriaFTMLItem;
  AParentEnv: TFloriaJSEnvironment): TFloriaFTMLItem;
var
  item: TFloriaFTMLItem;
  itemEnv: TFloriaJSEnvironment;
  fnDecl: TFloriaJSFunctionDecl;
  fnObj: TFloriaJSFunction;
  childAST: TFloriaFTMLComponent;
  childItem: TFloriaFTMLItem;
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
  if FDocumentObjects <> nil then
    FDocumentObjects.Add(itemEnv);

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
      if FDocumentObjects <> nil then
        FDocumentObjects.Add(fnObj);
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
    if childItem = nil then { no-op };
  end;

  Result := item;
end;

procedure TFloriaFTMLEngine.SetupItemBindings(AAST: TFloriaFTMLComponent; AItem: TFloriaFTMLItem);
var
  i: Integer;
  propName: string;
  propExpr: TFloriaJSExprNode;
  litVal: TFloriaJSValue;
  binding: TFloriaFTMLBinding;
  childAST: TFloriaFTMLComponent;
  childItem: TFloriaFTMLItem;
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

procedure TFloriaFTMLEngine.TriggerCompletedSignals(AItem: TFloriaFTMLItem);
var
  i: Integer;
begin
  if AItem = nil then Exit;

  // Resolve all anchors before dispatching completed signals
  ResolveAllAnchors(AItem);

  // Trigger children first
  for i := 0 to AItem.ChildCount() - 1 do
    TriggerCompletedSignals(AItem.GetChild(i));

  // Trigger onCompleted signals (supports FTML.onCompleted, Component.onCompleted, completed)
  AItem.EmitSignal('FTML.onCompleted', []);
  AItem.EmitSignal('Component.onCompleted', []);
  AItem.EmitSignal('completed', []);
end;

procedure RelayoutAll(AItem: TFloriaFTMLItem);
var
  i: Integer;
begin
  if AItem = nil then Exit;
  for i := 0 to AItem.ChildCount() - 1 do
    RelayoutAll(AItem.GetChild(i));
  if AItem is TFloriaFTMLColumn then
    TFloriaFTMLColumn(AItem).Relayout()
  else if AItem is TFloriaFTMLRow then
    TFloriaFTMLRow(AItem).Relayout();
end;

procedure TFloriaFTMLEngine.RemoveDocumentIds();
var
  i: Integer;
  id: string;
  val: TFloriaJSValue;
begin
  if (FContext = nil) or (FItemsById = nil) then Exit;

  { Document IDs are published into the shared global environment. They must be
    withdrawn again, otherwise the global scope keeps dangling references to
    items that no longer exist. Only remove an entry that still points at our
    own item, so a second engine sharing the same context is left untouched. }
  for i := 0 to FItemsById.Count - 1 do
  begin
    id := FItemsById[i];
    if (id <> '') and FContext.GlobalEnv.HasLocal(id) and
       FContext.GlobalEnv.Get(id, val) and val.IsObject() and
       (TObject(val.ObjVal) = FItemsById.Objects[i]) then
      FContext.GlobalEnv.Undefine(id);
  end;

  FItemsById.Clear();
end;

procedure TFloriaFTMLEngine.ReleaseDocument();
var
  i: Integer;
  obj: TObject;
  item: TFloriaFTMLItem;
begin
  FDocumentEscaped := False;

  { Phase 1: unlink the anchor graph while every item is still alive, so no
    item is destroyed while a neighbour still references it. }
  if FDocumentObjects <> nil then
  begin
    for i := 0 to FDocumentObjects.Count - 1 do
    begin
      obj := TObject(FDocumentObjects[i]);
      if obj is TFloriaFTMLItem then
        TFloriaFTMLItem(obj).DetachAnchors();
    end;
  end;

  { Phase 2: drop the binding manager reference held by every item, otherwise
    the items would keep pointing at a destroyed manager. }
  if FDocumentObjects <> nil then
  begin
    for i := 0 to FDocumentObjects.Count - 1 do
    begin
      obj := TObject(FDocumentObjects[i]);
      if obj is TFloriaFTMLItem then
      begin
        item := TFloriaFTMLItem(obj);
        item.BindingManager := nil;
        item.Env := nil;
      end;
    end;
  end;

  { Phase 3: destroy the binding manager; this destroys every binding it owns
    and detaches them from the still living target items. }
  FreeAndNil(FBindingManager);

  { Phase 4: withdraw the document IDs from the shared global environment. }
  RemoveDocumentIds();

  { Phase 5: release the document owned heap objects. They are untracked first
    so the shared JS heap does not free them a second time. They are destroyed
    in the order of their dependencies: the environments give up the
    references they hold to the items and the functions of the document first,
    then the items give up theirs, and the functions are destroyed last. }
  if FDocumentObjects <> nil then
  begin
    if DocumentHasRuntimeClosure() then
    begin
      { A runtime closure that was created in the document still refers to its
        environments and to the code it was declared in. The document is
        therefore kept alive until the engine goes away. }
      FDocumentEscaped := True;
      for i := 0 to FDocumentObjects.Count - 1 do
        FEscapedObjects.Add(FDocumentObjects[i]);
      FDocumentObjects.Clear();
    end
    else
      ReleaseObjects(FDocumentObjects);
  end;

  FRootItem := nil;
  FRootEnv := nil;
end;

function TFloriaFTMLEngine.DocumentHasRuntimeClosure(): Boolean;
var
  i: Integer;
  obj: TObject;
begin
  { A closure that was created in one of the environments of the document
    keeps that environment alive, and with it the code it was declared in. }
  Result := False;
  if FDocumentObjects = nil then Exit;
  for i := 0 to FDocumentObjects.Count - 1 do
  begin
    obj := TObject(FDocumentObjects[i]);
    if obj is TFloriaJSEnvironment then
    begin
      if TFloriaJSEnvironment(obj).Captured then
        Exit(True);
    end;
  end;
end;

procedure TFloriaFTMLEngine.ReleaseObjects(AObjects: TFPList);
var
  i: Integer;
  obj: TObject;
  environments, items, others: TFPList;
begin
  if AObjects = nil then Exit;

  { The objects are sorted first, because the list still holds every object
    while the groups are destroyed. }
  environments := TFPList.Create();
  items := TFPList.Create();
  others := TFPList.Create();
  try
    for i := 0 to AObjects.Count - 1 do
    begin
      obj := TObject(AObjects[i]);
      if obj is TFloriaJSEnvironment then
        environments.Add(obj)
      else if obj is TFloriaFTMLItem then
        items.Add(obj)
      else
        others.Add(obj);
    end;

    { The environments are destroyed first, because every binding of an
      environment holds a reference to the value it stores. }
    for i := environments.Count - 1 downto 0 do
    begin
      obj := TObject(environments[i]);
      if FContext <> nil then
        FContext.Heap.Untrack(obj);
      obj.Free();
    end;

    { Then the items, because every property of an item holds a reference to
      the value it stores. }
    for i := items.Count - 1 downto 0 do
    begin
      obj := TObject(items[i]);
      if FContext <> nil then
        FContext.Heap.Untrack(obj);
      obj.Free();
    end;

    { And finally the remaining objects, which are the functions of the
      document. They are the values that the other objects refer to. }
    for i := others.Count - 1 downto 0 do
    begin
      obj := TObject(others[i]);
      if FContext <> nil then
        FContext.Heap.Untrack(obj);
      obj.Free();
    end;
  finally
    environments.Free();
    items.Free();
    others.Free();
  end;

  AObjects.Clear();
end;

procedure TFloriaFTMLEngine.ReleaseEscapedDocuments();
var
  i: Integer;
begin
  if FEscapedObjects <> nil then
  begin
    ReleaseObjects(FEscapedObjects);
    FreeAndNil(FEscapedObjects);
  end;

  if FEscapedASTs <> nil then
  begin
    { The syntax trees are freed after the objects, because the functions of a
      document point into the tree they were declared in. }
    for i := FEscapedASTs.Count - 1 downto 0 do
      TObject(FEscapedASTs[i]).Free();
    FreeAndNil(FEscapedASTs);
  end;
end;

function TFloriaFTMLEngine.LoadString(const AFTMLSource: string): TFloriaFTMLItem;
var
  parser: TFloriaJSParser;
  rootItem: TFloriaFTMLItem;
begin
  FLastError := '';

  { Release the previously loaded document: its items, environments, functions,
    bindings and identifiers must not survive a reload. }
  ReleaseDocument();

  if FBindingManager = nil then
    FBindingManager := TFloriaFTMLBindingManager.Create(FContext.Evaluator);

  if FRootAST <> nil then
  begin
    if FDocumentEscaped then
    begin
      { A runtime closure still refers to the code the document was declared
        in, so the syntax tree is kept alive. }
      FEscapedASTs.Add(FRootAST);
      FRootAST := nil;
    end
    else
      FreeAndNil(FRootAST);
  end;

  // Step 1: Parse FTML syntax
  parser := TFloriaJSParser.Create(AFTMLSource);
  try
    FRootAST := parser.ParseFTMLComponent();
    if parser.HasErrors() or (FRootAST = nil) then
    begin
      if parser.GetErrorCount() > 0 then
        FLastError := parser.GetError(0)
      else
        FLastError := 'Failed to parse FTML component';
      Exit(nil);
    end;
  finally
    parser.Free();
  end;

  // Step 2: Document root lexical environment
  FRootEnv := TFloriaJSEnvironment.Create(FContext.GlobalEnv);
  FContext.Heap.TrackEnvironment(FRootEnv);
  if FDocumentObjects <> nil then
    FDocumentObjects.Add(FRootEnv);

  // Step 3: Instantiate component tree
  rootItem := InstantiateItem(FRootAST, nil, FRootEnv);
  FRootItem := rootItem;

  // Step 4: Wire and evaluate reactive property bindings
  SetupItemBindings(FRootAST, rootItem);

  // Step 5: Relayout layout containers and resolve semantic anchors
  RelayoutAll(rootItem);
  ResolveAllAnchors(rootItem);
  RelayoutAll(rootItem);

  // Step 6: Dispatch onCompleted signals
  TriggerCompletedSignals(rootItem);

  Result := rootItem;
end;

function TFloriaFTMLEngine.LoadFile(const AFileName: string): TFloriaFTMLItem;
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

function TFloriaFTMLEngine.FindItemById(const AId: string): TFloriaFTMLItem;
var
  idx: Integer;
begin
  if (FItemsById <> nil) and (AId <> '') then
  begin
    idx := FItemsById.IndexOf(AId);
    if idx >= 0 then
      Exit(TFloriaFTMLItem(FItemsById.Objects[idx]));
  end;

  if FRootItem <> nil then
    Result := FRootItem.FindById(AId)
  else
    Result := nil;
end;

function TFloriaFTMLEngine.Evaluate(const AScript: string): TFloriaJSValue;
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
      { The caller holds on to the returned value, so the object it points at
        must stay alive for as long as the caller keeps it. }
      if Result.IsObject() and (Result.ObjVal <> nil) then
        Result.ObjVal.Pin;
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;
end;

procedure TFloriaFTMLEngine.ReleaseValue(const AValue: TFloriaJSValue);
begin
  if FContext <> nil then
    FContext.ReleaseValue(AValue);
end;

function TFloriaFTMLEngine.HasErrors(): Boolean;
begin
  Result := (FLastError <> '');
end;

end.
