{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Declarative FTML Component Types & Hierarchy    }
{   (Floria Toolkit Markup Language)                                       }
{                                                                          }
{   Provides runtime component models, visual element hierarchy, property  }
{   storage, signal dispatching, and built-in FTML elements.               }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.ftml.types;

{$mode objfpc}{$H+}
{$interfaces corba}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math, floria.js.types, floria.js.ast, floria.js.value,
  floria.js.env, floria.js.evaluator;

type
  { Forward Declarations }
  TFloriaFTMLItem = class;
  TFloriaFTMLItemClass = class of TFloriaFTMLItem;
  TFloriaFTMLAnchorLine = class;

  { Semantic Anchor Edge Enumeration }
  TFloriaAnchorEdge = (
    faeNone,
    faeLeft,
    faeRight,
    faeTop,
    faeBottom,
    faeHorizontalCenter,
    faeVerticalCenter,
    faeBaseline
  );

  { Binding Manager Interface for Property Dependency Tracking }
  IFloriaFTMLBindingManager = interface
    procedure RecordPropertyRead(AItem: TObject; const APropName: string);
    procedure NotifyPropertyChanged(AItem: TObject; const APropName: string);
    procedure RemoveBindingsForTarget(ATargetItem: TObject; const ATargetProperty: string = '');
  end;

  { Engine Context Interface for Evaluator & Runtime Access }
  IFloriaFTMLEngineContext = interface
    function GetEvaluator(): TFloriaJSEvaluator;
  end;

  { Single FTML Property Record }
  TFloriaFTMLPropertyEntry = record
    Name: string;
    Value: TFloriaJSValue;
    HasBinding: Boolean;
    BindingRef: TObject;
  end;

  { Single FTML Signal Handler Record }
  TFloriaFTMLSignalEntry = record
    SignalName: string;
    HandlerStmt: TFloriaJSStmtNode;
  end;

  { Semantic Anchor Line Object (Item + Edge) }
  TFloriaFTMLAnchorLine = class(TFloriaJSObject)
  private
    FItem: TFloriaFTMLItem;
    FEdge: TFloriaAnchorEdge;
  public
    constructor Create(AItem: TFloriaFTMLItem; AEdge: TFloriaAnchorEdge);
    function  GetProperty(const AName: string): TFloriaJSValue; override;
    function  HasProperty(const AName: string): Boolean; override;

    property Item: TFloriaFTMLItem read FItem;
    property Edge: TFloriaAnchorEdge read FEdge;
  end;

  { Base Declarative FTML Item (inherits TFloriaJSObject for JS interop) }
  TFloriaFTMLItem = class(TFloriaJSObject)
  private
    FTypeName: string;
    FId: string;
    FParent: TFloriaFTMLItem;
    FChildren: TFPList;
    FEngine: TObject;
    FEnv: TFloriaJSEnvironment;
    FBindingManager: IFloriaFTMLBindingManager;
    FFTMLProperties: array of TFloriaFTMLPropertyEntry;
    FFTMLPropCount: Integer;
    FFTMLSignals: array of TFloriaFTMLSignalEntry;
    FFTMLSignalCount: Integer;
    FAnchorLines: array[TFloriaAnchorEdge] of TFloriaFTMLAnchorLine;
    FAnchorDependents: TFPList;
    FAnchorTargets: TFPList;
    FIsResolvingAnchors: Boolean;
    FHeapId: Integer;

    procedure SetPropertyInternal(const AName: string; const AValue: TFloriaJSValue; AFromBinding: Boolean);
    function  GetChildrenAsJSArray(): TFloriaJSValue;
    function  FindSignalIndex(const ASignalName: string): Integer;
    function  GetAnchorLine(AEdge: TFloriaAnchorEdge): TFloriaFTMLAnchorLine;
    procedure RegisterAnchorTarget(ATarget: TFloriaFTMLItem);
    procedure UnregisterAnchorTarget(ATarget: TFloriaFTMLItem);
    procedure AddAnchorDependent(AItem: TFloriaFTMLItem);
    procedure RemoveAnchorDependent(AItem: TFloriaFTMLItem);
    procedure NotifyAnchorDependents();
    function  GetAnchorCoord(ATarget: TFloriaFTMLItem; AEdge: TFloriaAnchorEdge; AParent: TFloriaFTMLItem): Double;
  public
    constructor Create(const ATypeName: string; AEngine: TObject = nil); virtual;
    destructor Destroy(); override;

    { Hierarchy }
    procedure AddChild(AChild: TFloriaFTMLItem);
    procedure RemoveChild(AChild: TFloriaFTMLItem);
    function  ChildCount(): Integer;
    function  GetChild(AIndex: Integer): TFloriaFTMLItem;
    function  FindById(const AId: string): TFloriaFTMLItem;
    function  FindChild(const AName: string): TFloriaFTMLItem;

    { Property Access & Reflection }
    function  GetProperty(const AName: string): TFloriaJSValue; override;
    procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); override;
    procedure SetPropertyFromBinding(const AName: string; const AValue: TFloriaJSValue);
    function  HasProperty(const AName: string): Boolean; override;

    function  DefineProperty(const AName: string; const ADefault: TFloriaJSValue): Integer;
    function  FindPropertyIndex(const AName: string): Integer;
    function  GetPropertyCount(): Integer; reintroduce;
    function  GetPropertyName(AIndex: Integer): string; reintroduce;
    function  GetPropertyValue(AIndex: Integer): TFloriaJSValue; reintroduce;

    function  GetPropertyAsNumber(const AName: string; ADefault: Double = 0.0): Double;
    function  GetPropertyAsString(const AName: string; const ADefault: string = ''): string;
    function  GetPropertyAsBoolean(const AName: string; ADefault: Boolean = False): Boolean;

    procedure AttachBinding(const AName: string; ABinding: TObject);
    procedure DetachBinding(const AName: string);
    function  HasBinding(const AName: string): Boolean;
    function  GetBinding(const AName: string): TObject;

    { Remembers which heap the values of the item belong to, so that the item
      can find out whether they are still valid when it goes away. }
    procedure RememberHeap(AHeap: TFloriaJSHeap);

    { Signal System }
    procedure AddSignalHandler(const ASignalName: string; AHandler: TFloriaJSStmtNode);
    function  EmitSignal(const ASignalName: string; const AArgs: array of TFloriaJSValue): TFloriaJSValue;
    function  EmitSignal(const ASignalName: string): TFloriaJSValue;

    { Common Visual Item Helpers }
    function  GetX(): Double;
    procedure SetX(AVal: Double);
    function  GetY(): Double;
    procedure SetY(AVal: Double);
    function  GetWidth(): Double;
    procedure SetWidth(AVal: Double);
    function  GetHeight(): Double;
    procedure SetHeight(AVal: Double);
    function  GetVisible(): Boolean;
    procedure SetVisible(AVal: Boolean);
    function  GetOpacity(): Double;
    procedure SetOpacity(AVal: Double);

    { Anchors & Constraints }
    procedure ResolveAnchors();
    function  HasAnchors(): Boolean;
    procedure DetachAnchors();

    { Flex & Grid Child Properties }
    function  GetFlexGrow(): Double;
    procedure SetFlexGrow(AVal: Double);
    function  GetFlexShrink(): Double;
    procedure SetFlexShrink(AVal: Double);
    function  GetFlexBasis(): Double;
    procedure SetFlexBasis(AVal: Double);
    function  GetAlignSelf(): string;
    procedure SetAlignSelf(const AVal: string);
    function  GetGridColumn(): Integer;
    procedure SetGridColumn(AVal: Integer);
    function  GetGridRow(): Integer;
    procedure SetGridRow(AVal: Integer);
    function  GetColSpan(): Integer;
    procedure SetColSpan(AVal: Integer);
    function  GetRowSpan(): Integer;
    procedure SetRowSpan(AVal: Integer);

    property TypeName: string read FTypeName;
    property Id: string read FId write FId;
    property Parent: TFloriaFTMLItem read FParent write FParent;
    property Engine: TObject read FEngine write FEngine;
    property Env: TFloriaJSEnvironment read FEnv write FEnv;
    property BindingManager: IFloriaFTMLBindingManager read FBindingManager write FBindingManager;

    property X: Double read GetX write SetX;
    property Y: Double read GetY write SetY;
    property Width: Double read GetWidth write SetWidth;
    property Height: Double read GetHeight write SetHeight;
    property Visible: Boolean read GetVisible write SetVisible;
    property Opacity: Double read GetOpacity write SetOpacity;

    property FlexGrow: Double read GetFlexGrow write SetFlexGrow;
    property FlexShrink: Double read GetFlexShrink write SetFlexShrink;
    property FlexBasis: Double read GetFlexBasis write SetFlexBasis;
    property AlignSelf: string read GetAlignSelf write SetAlignSelf;
    property GridColumn: Integer read GetGridColumn write SetGridColumn;
    property GridRow: Integer read GetGridRow write SetGridRow;
    property ColSpan: Integer read GetColSpan write SetColSpan;
    property RowSpan: Integer read GetRowSpan write SetRowSpan;
  end;

  { Built-in Rectangle Component }
  TFloriaFTMLRectangle = class(TFloriaFTMLItem)
  public
    constructor Create(const ATypeName: string = 'Rectangle'; AEngine: TObject = nil); override;

    function  GetColor(): string;
    procedure SetColor(const AVal: string);
    function  GetRadius(): Double;
    procedure SetRadius(AVal: Double);
    function  GetBorderWidth(): Double;
    procedure SetBorderWidth(AVal: Double);
    function  GetBorderColor(): string;
    procedure SetBorderColor(const AVal: string);

    property Color: string read GetColor write SetColor;
    property Radius: Double read GetRadius write SetRadius;
    property BorderWidth: Double read GetBorderWidth write SetBorderWidth;
    property BorderColor: string read GetBorderColor write SetBorderColor;
  end;

  { Built-in Text Component }
  TFloriaFTMLText = class(TFloriaFTMLItem)
  public
    constructor Create(const ATypeName: string = 'Text'; AEngine: TObject = nil); override;

    function  GetText(): string;
    procedure SetText(const AVal: string);
    function  GetColor(): string;
    procedure SetColor(const AVal: string);
    function  GetFontSize(): Double;
    procedure SetFontSize(AVal: Double);
    function  GetFontFamily(): string;
    procedure SetFontFamily(const AVal: string);

    property Text: string read GetText write SetText;
    property Color: string read GetColor write SetColor;
    property FontSize: Double read GetFontSize write SetFontSize;
    property FontFamily: string read GetFontFamily write SetFontFamily;
  end;

  { Built-in Button Component }
  TFloriaFTMLButton = class(TFloriaFTMLItem)
  public
    constructor Create(const ATypeName: string = 'Button'; AEngine: TObject = nil); override;

    function  GetText(): string;
    procedure SetText(const AVal: string);
    function  GetPressed(): Boolean;
    procedure SetPressed(AVal: Boolean);
    function  GetHovered(): Boolean;
    procedure SetHovered(AVal: Boolean);

    procedure Click();

    property Text: string read GetText write SetText;
    property Pressed: Boolean read GetPressed write SetPressed;
    property Hovered: Boolean read GetHovered write SetHovered;
  end;

  { Built-in TextInput Component }
  TFloriaFTMLTextInput = class(TFloriaFTMLItem)
  public
    constructor Create(const ATypeName: string = 'TextInput'; AEngine: TObject = nil); override;

    function  GetText(): string;
    procedure SetText(const AVal: string);
    function  GetPlaceholder(): string;
    procedure SetPlaceholder(const AVal: string);
    function  GetReadOnly(): Boolean;
    procedure SetReadOnly(AVal: Boolean);

    property Text: string read GetText write SetText;
    property Placeholder: string read GetPlaceholder write SetPlaceholder;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly;
  end;

  { Built-in Column Layout Component }
  TFloriaFTMLColumn = class(TFloriaFTMLItem)
  public
    constructor Create(const ATypeName: string = 'Column'; AEngine: TObject = nil); override;

    function  GetSpacing(): Double;
    procedure SetSpacing(AVal: Double);
    procedure Relayout();

    property Spacing: Double read GetSpacing write SetSpacing;
  end;

  { Built-in Row Layout Component }
  TFloriaFTMLRow = class(TFloriaFTMLItem)
  public
    constructor Create(const ATypeName: string = 'Row'; AEngine: TObject = nil); override;

    function  GetSpacing(): Double;
    procedure SetSpacing(AVal: Double);
    procedure Relayout();

    property Spacing: Double read GetSpacing write SetSpacing;
  end;

  { Built-in FlexBox Layout Component }
  TFloriaFTMLFlexBox = class(TFloriaFTMLItem)
  public
    constructor Create(const ATypeName: string = 'FlexBox'; AEngine: TObject = nil); override;

    function  GetDirection(): string;
    procedure SetDirection(const AVal: string);
    function  GetWrap(): string;
    procedure SetWrap(const AVal: string);
    function  GetJustifyContent(): string;
    procedure SetJustifyContent(const AVal: string);
    function  GetAlignItems(): string;
    procedure SetAlignItems(const AVal: string);
    function  GetGap(): Double;
    procedure SetGap(AVal: Double);
    function  GetPadding(): Double;
    procedure SetPadding(AVal: Double);

    property Direction: string read GetDirection write SetDirection;
    property Wrap: string read GetWrap write SetWrap;
    property JustifyContent: string read GetJustifyContent write SetJustifyContent;
    property AlignItems: string read GetAlignItems write SetAlignItems;
    property Gap: Double read GetGap write SetGap;
    property Padding: Double read GetPadding write SetPadding;
  end;

  { Built-in Grid Layout Component }
  TFloriaFTMLGrid = class(TFloriaFTMLItem)
  public
    constructor Create(const ATypeName: string = 'Grid'; AEngine: TObject = nil); override;

    function  GetColumns(): Integer;
    procedure SetColumns(AVal: Integer);
    function  GetRows(): Integer;
    procedure SetRows(AVal: Integer);
    function  GetGap(): Double;
    procedure SetGap(AVal: Double);
    function  GetColumnGap(): Double;
    procedure SetColumnGap(AVal: Double);
    function  GetRowGap(): Double;
    procedure SetRowGap(AVal: Double);

    property Columns: Integer read GetColumns write SetColumns;
    property Rows: Integer read GetRows write SetRows;
    property Gap: Double read GetGap write SetGap;
    property ColumnGap: Double read GetColumnGap write SetColumnGap;
    property RowGap: Double read GetRowGap write SetRowGap;
  end;

{ Helper Functions for Semantic Anchors & Layouts }
function AnchorEdgeToString(AEdge: TFloriaAnchorEdge): string;
function StringToAnchorEdge(const S: string): TFloriaAnchorEdge;
function IsHorizontalAnchorEdge(AEdge: TFloriaAnchorEdge): Boolean;
function IsVerticalAnchorEdge(AEdge: TFloriaAnchorEdge): Boolean;
function IsLayoutContainer(AItem: TFloriaFTMLItem): Boolean;
procedure ResolveAllAnchors(AItem: TFloriaFTMLItem);

implementation

{ Helper Functions for Semantic Anchors & Layouts }

function AnchorEdgeToString(AEdge: TFloriaAnchorEdge): string;
begin
  case AEdge of
    faeLeft: Result := 'left';
    faeRight: Result := 'right';
    faeTop: Result := 'top';
    faeBottom: Result := 'bottom';
    faeHorizontalCenter: Result := 'horizontalCenter';
    faeVerticalCenter: Result := 'verticalCenter';
    faeBaseline: Result := 'baseline';
  else
    Result := 'none';
  end;
end;

function StringToAnchorEdge(const S: string): TFloriaAnchorEdge;
begin
  if SameText(S, 'left') then Result := faeLeft
  else if SameText(S, 'right') then Result := faeRight
  else if SameText(S, 'top') then Result := faeTop
  else if SameText(S, 'bottom') then Result := faeBottom
  else if SameText(S, 'horizontalCenter') then Result := faeHorizontalCenter
  else if SameText(S, 'verticalCenter') then Result := faeVerticalCenter
  else if SameText(S, 'baseline') then Result := faeBaseline
  else Result := faeNone;
end;

function IsHorizontalAnchorEdge(AEdge: TFloriaAnchorEdge): Boolean;
begin
  Result := AEdge in [faeLeft, faeRight, faeHorizontalCenter];
end;

function IsVerticalAnchorEdge(AEdge: TFloriaAnchorEdge): Boolean;
begin
  Result := AEdge in [faeTop, faeBottom, faeVerticalCenter, faeBaseline];
end;

function IsLayoutContainer(AItem: TFloriaFTMLItem): Boolean;
begin
  if AItem = nil then Exit(False);
  Result := (AItem is TFloriaFTMLRow) or (AItem is TFloriaFTMLColumn) or
            (AItem is TFloriaFTMLFlexBox) or (AItem is TFloriaFTMLGrid) or
            (AItem.TypeName = 'Row') or (AItem.TypeName = 'Column') or
            (AItem.TypeName = 'FlexBox') or (AItem.TypeName = 'Grid');
end;

procedure ResolveAllAnchors(AItem: TFloriaFTMLItem);
var
  i: Integer;
begin
  if AItem = nil then Exit;
  AItem.ResolveAnchors();
  for i := 0 to AItem.ChildCount() - 1 do
    ResolveAllAnchors(AItem.GetChild(i));
end;

{ TFloriaFTMLAnchorLine }

constructor TFloriaFTMLAnchorLine.Create(AItem: TFloriaFTMLItem; AEdge: TFloriaAnchorEdge);
begin
  inherited Create(nil);
  FItem := AItem;
  FEdge := AEdge;
end;

function TFloriaFTMLAnchorLine.GetProperty(const AName: string): TFloriaJSValue;
begin
  if AName = 'item' then
  begin
    if FItem <> nil then
      Exit(JSMakeObject(FItem))
    else
      Exit(JSMakeNull());
  end;
  if AName = 'edge' then
    Exit(JSMakeString(AnchorEdgeToString(FEdge)));

  Result := inherited GetProperty(AName);
end;

function TFloriaFTMLAnchorLine.HasProperty(const AName: string): Boolean;
begin
  if (AName = 'item') or (AName = 'edge') then
    Exit(True);
  Result := inherited HasProperty(AName);
end;

{ TFloriaFTMLItem }

constructor TFloriaFTMLItem.Create(const ATypeName: string; AEngine: TObject);
var
  edge: TFloriaAnchorEdge;
begin
  inherited Create(nil);
  FTypeName := ATypeName;
  FId := '';
  FParent := nil;
  FChildren := TFPList.Create();
  FEngine := AEngine;
  FEnv := nil;
  FBindingManager := nil;
  SetLength(FFTMLProperties, 0);
  FFTMLPropCount := 0;
  SetLength(FFTMLSignals, 0);
  FFTMLSignalCount := 0;

  for edge := Low(TFloriaAnchorEdge) to High(TFloriaAnchorEdge) do
    FAnchorLines[edge] := nil;
  FAnchorDependents := TFPList.Create();
  FAnchorTargets := TFPList.Create();
  FIsResolvingAnchors := False;

  // Initialize standard visual properties
  DefineProperty('x', JSMakeNumber(0.0));
  DefineProperty('y', JSMakeNumber(0.0));
  if (ATypeName = 'Button') then
  begin
    DefineProperty('width', JSMakeNumber(120.0));
    DefineProperty('height', JSMakeNumber(38.0));
  end
  else if (ATypeName = 'TextInput') or (ATypeName = 'Entry') then
  begin
    DefineProperty('width', JSMakeNumber(200.0));
    DefineProperty('height', JSMakeNumber(36.0));
  end
  else if (ATypeName = 'Switch') then
  begin
    DefineProperty('width', JSMakeNumber(120.0));
    DefineProperty('height', JSMakeNumber(32.0));
  end
  else if (ATypeName = 'CheckBox') then
  begin
    DefineProperty('width', JSMakeNumber(160.0));
    DefineProperty('height', JSMakeNumber(28.0));
  end
  else if (ATypeName = 'Slider') then
  begin
    DefineProperty('width', JSMakeNumber(160.0));
    DefineProperty('height', JSMakeNumber(24.0));
  end
  else if (ATypeName = 'ProgressBar') then
  begin
    DefineProperty('width', JSMakeNumber(200.0));
    DefineProperty('height', JSMakeNumber(20.0));
  end
  else
  begin
    DefineProperty('width', JSMakeNumber(0.0));
    if (ATypeName = 'Text') or (ATypeName = 'Label') then
      DefineProperty('height', JSMakeNumber(24.0))
    else
      DefineProperty('height', JSMakeNumber(0.0));
  end;
  DefineProperty('visible', JSMakeBoolean(True));
  DefineProperty('opacity', JSMakeNumber(1.0));
  DefineProperty('clip', JSMakeBoolean(False));
  DefineProperty('enabled', JSMakeBoolean(True));

  // Child layout constraints
  DefineProperty('flexGrow', JSMakeNumber(0.0));
  DefineProperty('flexShrink', JSMakeNumber(1.0));
  DefineProperty('flexBasis', JSMakeNumber(0.0));
  DefineProperty('alignSelf', JSMakeString('auto'));
  DefineProperty('gridColumn', JSMakeNumber(0.0));
  DefineProperty('gridRow', JSMakeNumber(0.0));
  DefineProperty('colSpan', JSMakeNumber(1.0));
  DefineProperty('rowSpan', JSMakeNumber(1.0));
end;

destructor TFloriaFTMLItem.Destroy();
var
  edge: TFloriaAnchorEdge;
  i: Integer;
begin
  { Every property holds a reference to the value it stores. The references are
    only given up when the heap that produced the values is still alive,
    because the values would not be valid any more otherwise. }
  if JSHeapIsAlive(Heap, FHeapId) then
    for i := 0 to FFTMLPropCount - 1 do
      JSReleaseValue(FFTMLProperties[i].Value);
  FFTMLPropCount := 0;
  SetLength(FFTMLProperties, 0);
  SetLength(FFTMLSignals, 0);

  // Unlink from the anchor graph. During a bulk document teardown this has
  // already been performed for every item, so the lists are empty here and
  // no cross-item call is made against a possibly destroyed neighbour.
  DetachAnchors();

  if FAnchorTargets <> nil then
    FreeAndNil(FAnchorTargets);

  if FAnchorDependents <> nil then
    FreeAndNil(FAnchorDependents);

  // Free anchor lines
  for edge := Low(TFloriaAnchorEdge) to High(TFloriaAnchorEdge) do
  begin
    if FAnchorLines[edge] <> nil then
    begin
      FAnchorLines[edge].Free();
      FAnchorLines[edge] := nil;
    end;
  end;

  if FChildren <> nil then
  begin
    FChildren.Clear();
    FreeAndNil(FChildren);
  end;
  inherited Destroy();
end;

procedure TFloriaFTMLItem.DetachAnchors();
var
  i: Integer;
begin
  // Unregister self from all anchor targets
  if FAnchorTargets <> nil then
  begin
    for i := 0 to FAnchorTargets.Count - 1 do
      TFloriaFTMLItem(FAnchorTargets[i]).RemoveAnchorDependent(Self);
    FAnchorTargets.Clear();
  end;

  // Clear dependents targeting self
  if FAnchorDependents <> nil then
  begin
    for i := 0 to FAnchorDependents.Count - 1 do
      TFloriaFTMLItem(FAnchorDependents[i]).UnregisterAnchorTarget(Self);
    FAnchorDependents.Clear();
  end;
end;

procedure TFloriaFTMLItem.AddChild(AChild: TFloriaFTMLItem);
begin
  if (AChild <> nil) and (FChildren <> nil) then
  begin
    if FChildren.IndexOf(AChild) < 0 then
    begin
      FChildren.Add(AChild);
      AChild.Parent := Self;
      if (AChild.BindingManager = nil) and (FBindingManager <> nil) then
        AChild.BindingManager := FBindingManager;
      if (AChild.Engine = nil) and (FEngine <> nil) then
        AChild.Engine := FEngine;
    end;
  end;
end;

procedure TFloriaFTMLItem.RemoveChild(AChild: TFloriaFTMLItem);
begin
  if (AChild <> nil) and (FChildren <> nil) then
  begin
    FChildren.Remove(AChild);
    if AChild.Parent = Self then
      AChild.Parent := nil;
  end;
end;

function TFloriaFTMLItem.ChildCount(): Integer;
begin
  if FChildren <> nil then
    Result := FChildren.Count
  else
    Result := 0;
end;

function TFloriaFTMLItem.GetChild(AIndex: Integer): TFloriaFTMLItem;
begin
  if (FChildren <> nil) and (AIndex >= 0) and (AIndex < FChildren.Count) then
    Result := TFloriaFTMLItem(FChildren[AIndex])
  else
    Result := nil;
end;

function TFloriaFTMLItem.FindById(const AId: string): TFloriaFTMLItem;
var
  i: Integer;
  child, found: TFloriaFTMLItem;
begin
  if (AId <> '') and (FId = AId) then
    Exit(Self);

  if FChildren <> nil then
  begin
    for i := 0 to FChildren.Count - 1 do
    begin
      child := TFloriaFTMLItem(FChildren[i]);
      found := child.FindById(AId);
      if found <> nil then
        Exit(found);
    end;
  end;

  Result := nil;
end;

function TFloriaFTMLItem.FindChild(const AName: string): TFloriaFTMLItem;
var
  i: Integer;
  child: TFloriaFTMLItem;
begin
  if FChildren <> nil then
  begin
    for i := 0 to FChildren.Count - 1 do
    begin
      child := TFloriaFTMLItem(FChildren[i]);
      if (child.Id = AName) or (child.TypeName = AName) then
        Exit(child);
    end;
  end;
  Result := nil;
end;

function TFloriaFTMLItem.FindPropertyIndex(const AName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to FFTMLPropCount - 1 do
  begin
    if FFTMLProperties[i].Name = AName then
      Exit(i);
  end;
  Result := -1;
end;

function TFloriaFTMLItem.DefineProperty(const AName: string; const ADefault: TFloriaJSValue): Integer;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx >= 0 then
  begin
    { The property owns the value it stores: the value that is replaced gives
      up its reference and the new value takes a reference over. }
    JSReleaseValue(FFTMLProperties[idx].Value);
    FFTMLProperties[idx].Value := ADefault;
    JSRetainValue(ADefault);
    Exit(idx);
  end;

  if FFTMLPropCount >= Length(FFTMLProperties) then
  begin
    if Length(FFTMLProperties) = 0 then
      SetLength(FFTMLProperties, 8)
    else
      SetLength(FFTMLProperties, Length(FFTMLProperties) * 2);
  end;

  FFTMLProperties[FFTMLPropCount].Name := AName;
  FFTMLProperties[FFTMLPropCount].Value := ADefault;
  JSRetainValue(ADefault);
  FFTMLProperties[FFTMLPropCount].HasBinding := False;
  FFTMLProperties[FFTMLPropCount].BindingRef := nil;
  idx := FFTMLPropCount;
  Inc(FFTMLPropCount);
  Result := idx;
end;

procedure TFloriaFTMLItem.RememberHeap(AHeap: TFloriaJSHeap);
begin
  { The identifier of the heap tells it apart from a heap that reuses the
    memory of a dead one. }
  if AHeap <> nil then
    FHeapId := AHeap.Id
  else
    FHeapId := 0;
end;

function TFloriaFTMLItem.GetChildrenAsJSArray(): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  i: Integer;
begin
  { The array is created by the heap when the item belongs to one, so that it
    can be reclaimed once nothing refers to it any more. }
  if Heap <> nil then
    arr := Heap.NewArray()
  else
    arr := TFloriaJSArray.Create();
  if FChildren <> nil then
  begin
    for i := 0 to FChildren.Count - 1 do
      arr.Push(JSMakeObject(TFloriaFTMLItem(FChildren[i])));
  end;
  Result := JSMakeObject(arr);
end;

function TFloriaFTMLItem.GetProperty(const AName: string): TFloriaJSValue;
var
  idx: Integer;
begin
  // Special meta-properties
  if AName = 'id' then
    Exit(JSMakeString(FId));
  if AName = 'parent' then
  begin
    if FParent <> nil then
      Exit(JSMakeObject(FParent))
    else
      Exit(JSMakeNull());
  end;
  if AName = 'children' then
    Exit(GetChildrenAsJSArray());

  // Semantic anchor line getters
  if AName = 'left' then
  begin
    if FBindingManager <> nil then
      FBindingManager.RecordPropertyRead(Self, 'x');
    Exit(JSMakeObject(GetAnchorLine(faeLeft)));
  end;
  if AName = 'right' then
  begin
    if FBindingManager <> nil then
    begin
      FBindingManager.RecordPropertyRead(Self, 'x');
      FBindingManager.RecordPropertyRead(Self, 'width');
    end;
    Exit(JSMakeObject(GetAnchorLine(faeRight)));
  end;
  if AName = 'top' then
  begin
    if FBindingManager <> nil then
      FBindingManager.RecordPropertyRead(Self, 'y');
    Exit(JSMakeObject(GetAnchorLine(faeTop)));
  end;
  if AName = 'bottom' then
  begin
    if FBindingManager <> nil then
    begin
      FBindingManager.RecordPropertyRead(Self, 'y');
      FBindingManager.RecordPropertyRead(Self, 'height');
    end;
    Exit(JSMakeObject(GetAnchorLine(faeBottom)));
  end;
  if AName = 'horizontalCenter' then
  begin
    if FBindingManager <> nil then
    begin
      FBindingManager.RecordPropertyRead(Self, 'x');
      FBindingManager.RecordPropertyRead(Self, 'width');
    end;
    Exit(JSMakeObject(GetAnchorLine(faeHorizontalCenter)));
  end;
  if AName = 'verticalCenter' then
  begin
    if FBindingManager <> nil then
    begin
      FBindingManager.RecordPropertyRead(Self, 'y');
      FBindingManager.RecordPropertyRead(Self, 'height');
    end;
    Exit(JSMakeObject(GetAnchorLine(faeVerticalCenter)));
  end;
  if AName = 'baseline' then
  begin
    if FBindingManager <> nil then
    begin
      FBindingManager.RecordPropertyRead(Self, 'y');
      FBindingManager.RecordPropertyRead(Self, 'height');
    end;
    Exit(JSMakeObject(GetAnchorLine(faeBaseline)));
  end;

  // QML Layout.* compatibility aliases
  if AName = 'Layout.fillWidth' then
    Exit(JSMakeBoolean(GetFlexGrow() > 0.0));
  if AName = 'Layout.fillHeight' then
    Exit(JSMakeBoolean(GetFlexGrow() > 0.0));
  if AName = 'Layout.preferredWidth' then
    Exit(JSMakeNumber(GetWidth()));
  if AName = 'Layout.preferredHeight' then
    Exit(JSMakeNumber(GetHeight()));
  if AName = 'Layout.column' then
    Exit(JSMakeNumber(GetGridColumn()));
  if AName = 'Layout.row' then
    Exit(JSMakeNumber(GetGridRow()));
  if (AName = 'Layout.columnSpan') or (AName = 'Layout.colSpan') then
    Exit(JSMakeNumber(GetColSpan()));
  if AName = 'Layout.rowSpan' then
    Exit(JSMakeNumber(GetRowSpan()));
  if AName = 'Layout.alignment' then
    Exit(JSMakeString(GetAlignSelf()));

  // Record reactive property dependency if binding evaluation is active
  if FBindingManager <> nil then
    FBindingManager.RecordPropertyRead(Self, AName);

  idx := FindPropertyIndex(AName);
  if idx >= 0 then
    Exit(FFTMLProperties[idx].Value);

  // Fallback to base object property (e.g. attached methods or prototypes)
  Result := inherited GetProperty(AName);
end;

procedure TFloriaFTMLItem.SetProperty(const AName: string; const AValue: TFloriaJSValue);
begin
  SetPropertyInternal(AName, AValue, False);
end;

procedure TFloriaFTMLItem.SetPropertyFromBinding(const AName: string; const AValue: TFloriaJSValue);
begin
  SetPropertyInternal(AName, AValue, True);
end;

procedure TFloriaFTMLItem.SetPropertyInternal(const AName: string; const AValue: TFloriaJSValue; AFromBinding: Boolean);
var
  idx: Integer;
  oldVal: TFloriaJSValue;
  valChanged: Boolean;
begin
  if AName = 'id' then
  begin
    FId := AValue.ToString();
    Exit;
  end;

  // Handle Layout.* aliases
  if AName = 'Layout.fillWidth' then
  begin
    if AValue.ToBoolean() then
      SetPropertyInternal('flexGrow', JSMakeNumber(1.0), AFromBinding)
    else
      SetPropertyInternal('flexGrow', JSMakeNumber(0.0), AFromBinding);
  end
  else if AName = 'Layout.fillHeight' then
  begin
    if AValue.ToBoolean() then
      SetPropertyInternal('flexGrow', JSMakeNumber(1.0), AFromBinding)
    else
      SetPropertyInternal('flexGrow', JSMakeNumber(0.0), AFromBinding);
  end
  else if AName = 'Layout.preferredWidth' then
  begin
    SetPropertyInternal('width', JSMakeNumber(AValue.ToNumber()), AFromBinding);
  end
  else if AName = 'Layout.preferredHeight' then
  begin
    SetPropertyInternal('height', JSMakeNumber(AValue.ToNumber()), AFromBinding);
  end
  else if AName = 'Layout.column' then
  begin
    SetPropertyInternal('gridColumn', JSMakeNumber(Round(AValue.ToNumber())), AFromBinding);
  end
  else if AName = 'Layout.row' then
  begin
    SetPropertyInternal('gridRow', JSMakeNumber(Round(AValue.ToNumber())), AFromBinding);
  end
  else if (AName = 'Layout.columnSpan') or (AName = 'Layout.colSpan') then
  begin
    SetPropertyInternal('colSpan', JSMakeNumber(Round(AValue.ToNumber())), AFromBinding);
  end
  else if AName = 'Layout.rowSpan' then
  begin
    SetPropertyInternal('rowSpan', JSMakeNumber(Round(AValue.ToNumber())), AFromBinding);
  end
  else if AName = 'Layout.alignment' then
  begin
    SetPropertyInternal('alignSelf', JSMakeString(AValue.ToString()), AFromBinding);
  end;

  idx := FindPropertyIndex(AName);
  if idx < 0 then
  begin
    idx := DefineProperty(AName, AValue);
    valChanged := True;
  end
  else
  begin
    oldVal := FFTMLProperties[idx].Value;
    valChanged := not JSStrictEqual(oldVal, AValue);
    { The property owns the value it stores: the value that is replaced gives
      up its reference and the new value takes a reference over. }
    JSReleaseValue(oldVal);
    FFTMLProperties[idx].Value := AValue;
    JSRetainValue(AValue);
  end;

  // Assignment from script or host explicitly breaks existing binding
  if not AFromBinding then
  begin
    if FFTMLProperties[idx].HasBinding then
    begin
      FFTMLProperties[idx].HasBinding := False;
      FFTMLProperties[idx].BindingRef := nil;
      if FBindingManager <> nil then
        FBindingManager.RemoveBindingsForTarget(Self, AName);
    end;
  end;

  // Anchors target tracking and resolution
  if (Copy(AName, 1, 8) = 'anchors.') or (AName = 'anchors') then
  begin
    if AValue.IsObject() then
    begin
      if AValue.ObjVal is TFloriaFTMLAnchorLine then
        RegisterAnchorTarget(TFloriaFTMLAnchorLine(AValue.ObjVal).Item)
      else if AValue.ObjVal is TFloriaFTMLItem then
        RegisterAnchorTarget(TFloriaFTMLItem(AValue.ObjVal));
    end;
    ResolveAnchors();
  end;

  if valChanged then
  begin
    // Notify binding manager to propagate changes to dependent bindings
    if FBindingManager <> nil then
      FBindingManager.NotifyPropertyChanged(Self, AName);

    // Emit property change signal: on<PropName>Changed (e.g. onWidthChanged)
    EmitSignal(AName + 'Changed', [AValue]);

    if (AName = 'x') or (AName = 'y') or (AName = 'width') or (AName = 'height') then
    begin
      NotifyAnchorDependents();
      if ((AName = 'width') or (AName = 'height')) and HasAnchors() then
        ResolveAnchors();
    end;
  end;
end;

function TFloriaFTMLItem.HasProperty(const AName: string): Boolean;
begin
  if (AName = 'id') or (AName = 'parent') or (AName = 'children') then
    Exit(True);

  if (AName = 'left') or (AName = 'right') or (AName = 'top') or (AName = 'bottom') or
     (AName = 'horizontalCenter') or (AName = 'verticalCenter') or (AName = 'baseline') then
    Exit(True);

  if Copy(AName, 1, 7) = 'Layout.' then
    Exit(True);

  if FindPropertyIndex(AName) >= 0 then
    Exit(True);

  Result := inherited HasProperty(AName);
end;

function TFloriaFTMLItem.GetAnchorLine(AEdge: TFloriaAnchorEdge): TFloriaFTMLAnchorLine;
begin
  if FAnchorLines[AEdge] = nil then
    FAnchorLines[AEdge] := TFloriaFTMLAnchorLine.Create(Self, AEdge);
  Result := FAnchorLines[AEdge];
end;

procedure TFloriaFTMLItem.RegisterAnchorTarget(ATarget: TFloriaFTMLItem);
begin
  if (ATarget = nil) or (ATarget = Self) then Exit;
  if FAnchorTargets.IndexOf(ATarget) < 0 then
  begin
    FAnchorTargets.Add(ATarget);
    ATarget.AddAnchorDependent(Self);
  end;
end;

procedure TFloriaFTMLItem.UnregisterAnchorTarget(ATarget: TFloriaFTMLItem);
begin
  if (ATarget = nil) or (FAnchorTargets = nil) then Exit;
  FAnchorTargets.Remove(ATarget);
end;

procedure TFloriaFTMLItem.AddAnchorDependent(AItem: TFloriaFTMLItem);
begin
  if (AItem = nil) or (AItem = Self) then Exit;
  if (FAnchorDependents <> nil) and (FAnchorDependents.IndexOf(AItem) < 0) then
    FAnchorDependents.Add(AItem);
end;

procedure TFloriaFTMLItem.RemoveAnchorDependent(AItem: TFloriaFTMLItem);
begin
  if (AItem = nil) or (FAnchorDependents = nil) then Exit;
  FAnchorDependents.Remove(AItem);
end;

procedure TFloriaFTMLItem.NotifyAnchorDependents();
var
  i: Integer;
  dep: TFloriaFTMLItem;
begin
  if FAnchorDependents <> nil then
  begin
    for i := 0 to FAnchorDependents.Count - 1 do
    begin
      dep := TFloriaFTMLItem(FAnchorDependents[i]);
      if dep <> nil then
        dep.ResolveAnchors();
    end;
  end;
end;

function TFloriaFTMLItem.GetAnchorCoord(ATarget: TFloriaFTMLItem; AEdge: TFloriaAnchorEdge; AParent: TFloriaFTMLItem): Double;
var
  cur: TFloriaFTMLItem;
  relX, relY: Double;
begin
  if ATarget = nil then Exit(0.0);

  relX := 0.0;
  relY := 0.0;
  cur := ATarget;
  while (cur <> nil) and (cur <> AParent) do
  begin
    relX := relX + cur.X;
    relY := relY + cur.Y;
    cur := cur.Parent;
  end;

  case AEdge of
    faeLeft: Result := relX;
    faeRight: Result := relX + ATarget.Width;
    faeHorizontalCenter: Result := relX + (ATarget.Width / 2.0);
    faeTop: Result := relY;
    faeBottom: Result := relY + ATarget.Height;
    faeVerticalCenter: Result := relY + (ATarget.Height / 2.0);
    faeBaseline: Result := relY + ATarget.Height;
  else
    Result := 0.0;
  end;
end;

function TFloriaFTMLItem.HasAnchors(): Boolean;
begin
  Result := (FindPropertyIndex('anchors.left') >= 0) or
            (FindPropertyIndex('anchors.right') >= 0) or
            (FindPropertyIndex('anchors.top') >= 0) or
            (FindPropertyIndex('anchors.bottom') >= 0) or
            (FindPropertyIndex('anchors.fill') >= 0) or
            (FindPropertyIndex('anchors.centerIn') >= 0) or
            (FindPropertyIndex('anchors.horizontalCenter') >= 0) or
            (FindPropertyIndex('anchors.verticalCenter') >= 0);
end;

procedure TFloriaFTMLItem.ResolveAnchors();
var
  v: TFloriaJSValue;
  hasLeft, hasRight, hasTop, hasBottom: Boolean;
  hasHCenter, hasVCenter: Boolean;
  hasFill, hasCenterIn: Boolean;
  leftLine, rightLine, topLine, bottomLine: TFloriaFTMLAnchorLine;
  hCenterLine, vCenterLine: TFloriaFTMLAnchorLine;
  fillItem, centerInItem: TFloriaFTMLItem;
  mAll, mLeft, mRight, mTop, mBottom: Double;
  hOffset, vOffset: Double;
  leftCoord, rightCoord, topCoord, bottomCoord: Double;
  hCenterCoord, vCenterCoord: Double;
  newX, newY, newW, newH: Double;
  geomChanged: Boolean;
begin
  if FIsResolvingAnchors then Exit;
  if (FParent <> nil) and IsLayoutContainer(FParent) then
    Exit; // Layout container governs positioning

  FIsResolvingAnchors := True;
  try
    leftLine := nil;
    rightLine := nil;
    topLine := nil;
    bottomLine := nil;
    hCenterLine := nil;
    vCenterLine := nil;
    fillItem := nil;
    centerInItem := nil;

    v := GetProperty('anchors.fill');
    hasFill := v.IsObject() and (v.ObjVal is TFloriaFTMLItem);
    if hasFill then
      fillItem := TFloriaFTMLItem(v.ObjVal);

    v := GetProperty('anchors.centerIn');
    hasCenterIn := v.IsObject() and (v.ObjVal is TFloriaFTMLItem);
    if hasCenterIn then
      centerInItem := TFloriaFTMLItem(v.ObjVal);

    v := GetProperty('anchors.left');
    hasLeft := v.IsObject() and (v.ObjVal is TFloriaFTMLAnchorLine) and
               IsHorizontalAnchorEdge(TFloriaFTMLAnchorLine(v.ObjVal).Edge);
    if hasLeft then leftLine := TFloriaFTMLAnchorLine(v.ObjVal);

    v := GetProperty('anchors.right');
    hasRight := v.IsObject() and (v.ObjVal is TFloriaFTMLAnchorLine) and
                IsHorizontalAnchorEdge(TFloriaFTMLAnchorLine(v.ObjVal).Edge);
    if hasRight then rightLine := TFloriaFTMLAnchorLine(v.ObjVal);

    v := GetProperty('anchors.top');
    hasTop := v.IsObject() and (v.ObjVal is TFloriaFTMLAnchorLine) and
              IsVerticalAnchorEdge(TFloriaFTMLAnchorLine(v.ObjVal).Edge);
    if hasTop then topLine := TFloriaFTMLAnchorLine(v.ObjVal);

    v := GetProperty('anchors.bottom');
    hasBottom := v.IsObject() and (v.ObjVal is TFloriaFTMLAnchorLine) and
                 IsVerticalAnchorEdge(TFloriaFTMLAnchorLine(v.ObjVal).Edge);
    if hasBottom then bottomLine := TFloriaFTMLAnchorLine(v.ObjVal);

    v := GetProperty('anchors.horizontalCenter');
    hasHCenter := v.IsObject() and (v.ObjVal is TFloriaFTMLAnchorLine) and
                  IsHorizontalAnchorEdge(TFloriaFTMLAnchorLine(v.ObjVal).Edge);
    if hasHCenter then hCenterLine := TFloriaFTMLAnchorLine(v.ObjVal);

    v := GetProperty('anchors.verticalCenter');
    hasVCenter := v.IsObject() and (v.ObjVal is TFloriaFTMLAnchorLine) and
                  IsVerticalAnchorEdge(TFloriaFTMLAnchorLine(v.ObjVal).Edge);
    if hasVCenter then vCenterLine := TFloriaFTMLAnchorLine(v.ObjVal);

    if not (hasFill or hasCenterIn or hasLeft or hasRight or hasTop or hasBottom or hasHCenter or hasVCenter) then
      Exit;

    mAll := GetPropertyAsNumber('anchors.margins', 0.0);
    mLeft := GetPropertyAsNumber('anchors.leftMargin', mAll);
    mRight := GetPropertyAsNumber('anchors.rightMargin', mAll);
    mTop := GetPropertyAsNumber('anchors.topMargin', mAll);
    mBottom := GetPropertyAsNumber('anchors.bottomMargin', mAll);
    hOffset := GetPropertyAsNumber('anchors.horizontalCenterOffset', 0.0);
    vOffset := GetPropertyAsNumber('anchors.verticalCenterOffset', 0.0);

    newX := X;
    newW := Width;
    newY := Y;
    newH := Height;

    // Horizontal resolution
    if hasFill and (fillItem <> nil) then
    begin
      leftCoord := GetAnchorCoord(fillItem, faeLeft, FParent) + mLeft;
      rightCoord := GetAnchorCoord(fillItem, faeRight, FParent) - mRight;
      newX := leftCoord;
      newW := Max(0.0, rightCoord - leftCoord);
    end
    else if hasLeft and hasRight then
    begin
      leftCoord := GetAnchorCoord(leftLine.Item, leftLine.Edge, FParent) + mLeft;
      rightCoord := GetAnchorCoord(rightLine.Item, rightLine.Edge, FParent) - mRight;
      newX := leftCoord;
      newW := Max(0.0, rightCoord - leftCoord);
    end
    else if hasLeft then
    begin
      leftCoord := GetAnchorCoord(leftLine.Item, leftLine.Edge, FParent) + mLeft;
      newX := leftCoord;
    end
    else if hasRight then
    begin
      rightCoord := GetAnchorCoord(rightLine.Item, rightLine.Edge, FParent) - mRight;
      newX := rightCoord - newW;
    end
    else if hasCenterIn and (centerInItem <> nil) then
    begin
      hCenterCoord := GetAnchorCoord(centerInItem, faeHorizontalCenter, FParent) + hOffset;
      newX := hCenterCoord - (newW / 2.0);
    end
    else if hasHCenter then
    begin
      hCenterCoord := GetAnchorCoord(hCenterLine.Item, hCenterLine.Edge, FParent) + hOffset;
      newX := hCenterCoord - (newW / 2.0);
    end;

    // Vertical resolution
    if hasFill and (fillItem <> nil) then
    begin
      topCoord := GetAnchorCoord(fillItem, faeTop, FParent) + mTop;
      bottomCoord := GetAnchorCoord(fillItem, faeBottom, FParent) - mBottom;
      newY := topCoord;
      newH := Max(0.0, bottomCoord - topCoord);
    end
    else if hasTop and hasBottom then
    begin
      topCoord := GetAnchorCoord(topLine.Item, topLine.Edge, FParent) + mTop;
      bottomCoord := GetAnchorCoord(bottomLine.Item, bottomLine.Edge, FParent) - mBottom;
      newY := topCoord;
      newH := Max(0.0, bottomCoord - topCoord);
    end
    else if hasTop then
    begin
      topCoord := GetAnchorCoord(topLine.Item, topLine.Edge, FParent) + mTop;
      newY := topCoord;
    end
    else if hasBottom then
    begin
      bottomCoord := GetAnchorCoord(bottomLine.Item, bottomLine.Edge, FParent) - mBottom;
      newY := bottomCoord - newH;
    end
    else if hasCenterIn and (centerInItem <> nil) then
    begin
      vCenterCoord := GetAnchorCoord(centerInItem, faeVerticalCenter, FParent) + vOffset;
      newY := vCenterCoord - (newH / 2.0);
    end
    else if hasVCenter then
    begin
      vCenterCoord := GetAnchorCoord(vCenterLine.Item, vCenterLine.Edge, FParent) + vOffset;
      newY := vCenterCoord - (newH / 2.0);
    end;

    geomChanged := False;
    if Abs(newX - X) > 0.001 then
    begin
      SetPropertyInternal('x', JSMakeNumber(newX), True);
      geomChanged := True;
    end;
    if Abs(newY - Y) > 0.001 then
    begin
      SetPropertyInternal('y', JSMakeNumber(newY), True);
      geomChanged := True;
    end;
    if Abs(newW - Width) > 0.001 then
    begin
      SetPropertyInternal('width', JSMakeNumber(newW), True);
      geomChanged := True;
    end;
    if Abs(newH - Height) > 0.001 then
    begin
      SetPropertyInternal('height', JSMakeNumber(newH), True);
      geomChanged := True;
    end;

    if geomChanged then
      NotifyAnchorDependents();
  finally
    FIsResolvingAnchors := False;
  end;
end;

function TFloriaFTMLItem.GetFlexGrow(): Double;
begin
  Result := GetPropertyAsNumber('flexGrow', 0.0);
end;

procedure TFloriaFTMLItem.SetFlexGrow(AVal: Double);
begin
  SetProperty('flexGrow', JSMakeNumber(AVal));
end;

function TFloriaFTMLItem.GetFlexShrink(): Double;
begin
  Result := GetPropertyAsNumber('flexShrink', 1.0);
end;

procedure TFloriaFTMLItem.SetFlexShrink(AVal: Double);
begin
  SetProperty('flexShrink', JSMakeNumber(AVal));
end;

function TFloriaFTMLItem.GetFlexBasis(): Double;
begin
  Result := GetPropertyAsNumber('flexBasis', 0.0);
end;

procedure TFloriaFTMLItem.SetFlexBasis(AVal: Double);
begin
  SetProperty('flexBasis', JSMakeNumber(AVal));
end;

function TFloriaFTMLItem.GetAlignSelf(): string;
begin
  Result := GetPropertyAsString('alignSelf', 'auto');
end;

procedure TFloriaFTMLItem.SetAlignSelf(const AVal: string);
begin
  SetProperty('alignSelf', JSMakeString(AVal));
end;

function TFloriaFTMLItem.GetGridColumn(): Integer;
begin
  Result := Round(GetPropertyAsNumber('gridColumn', 0.0));
end;

procedure TFloriaFTMLItem.SetGridColumn(AVal: Integer);
begin
  SetProperty('gridColumn', JSMakeNumber(AVal));
end;

function TFloriaFTMLItem.GetGridRow(): Integer;
begin
  Result := Round(GetPropertyAsNumber('gridRow', 0.0));
end;

procedure TFloriaFTMLItem.SetGridRow(AVal: Integer);
begin
  SetProperty('gridRow', JSMakeNumber(AVal));
end;

function TFloriaFTMLItem.GetColSpan(): Integer;
begin
  Result := Round(GetPropertyAsNumber('colSpan', 1.0));
end;

procedure TFloriaFTMLItem.SetColSpan(AVal: Integer);
begin
  SetProperty('colSpan', JSMakeNumber(AVal));
end;

function TFloriaFTMLItem.GetRowSpan(): Integer;
begin
  Result := Round(GetPropertyAsNumber('rowSpan', 1.0));
end;

procedure TFloriaFTMLItem.SetRowSpan(AVal: Integer);
begin
  SetProperty('rowSpan', JSMakeNumber(AVal));
end;

function TFloriaFTMLItem.GetPropertyCount(): Integer;
begin
  Result := FFTMLPropCount;
end;

function TFloriaFTMLItem.GetPropertyName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FFTMLPropCount) then
    Result := FFTMLProperties[AIndex].Name
  else
    Result := '';
end;

function TFloriaFTMLItem.GetPropertyValue(AIndex: Integer): TFloriaJSValue;
begin
  if (AIndex >= 0) and (AIndex < FFTMLPropCount) then
    Result := FFTMLProperties[AIndex].Value
  else
    Result := JSMakeUndefined();
end;

function TFloriaFTMLItem.GetPropertyAsNumber(const AName: string; ADefault: Double): Double;
var
  val: TFloriaJSValue;
begin
  val := GetProperty(AName);
  if val.IsNumber() then
    Result := val.NumVal
  else if val.IsString() and TryStrToFloat(val.StrVal, Result) then
    { converted }
  else
    Result := ADefault;
end;

function TFloriaFTMLItem.GetPropertyAsString(const AName: string; const ADefault: string): string;
var
  val: TFloriaJSValue;
begin
  val := GetProperty(AName);
  if val.IsUndefined() or val.IsNull() then
    Result := ADefault
  else
    Result := val.ToString();
end;

function TFloriaFTMLItem.GetPropertyAsBoolean(const AName: string; ADefault: Boolean): Boolean;
var
  val: TFloriaJSValue;
begin
  val := GetProperty(AName);
  if val.IsBoolean() then
    Result := val.BoolVal
  else
    Result := ADefault;
end;

procedure TFloriaFTMLItem.AttachBinding(const AName: string; ABinding: TObject);
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if idx < 0 then
    idx := DefineProperty(AName, JSMakeUndefined());

  FFTMLProperties[idx].HasBinding := True;
  FFTMLProperties[idx].BindingRef := ABinding;
end;

procedure TFloriaFTMLItem.DetachBinding(const AName: string);
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if (idx >= 0) and FFTMLProperties[idx].HasBinding then
  begin
    FFTMLProperties[idx].HasBinding := False;
    FFTMLProperties[idx].BindingRef := nil;
  end;
end;

function TFloriaFTMLItem.HasBinding(const AName: string): Boolean;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  Result := (idx >= 0) and FFTMLProperties[idx].HasBinding;
end;

function TFloriaFTMLItem.GetBinding(const AName: string): TObject;
var
  idx: Integer;
begin
  idx := FindPropertyIndex(AName);
  if (idx >= 0) and FFTMLProperties[idx].HasBinding then
    Result := FFTMLProperties[idx].BindingRef
  else
    Result := nil;
end;

function TFloriaFTMLItem.FindSignalIndex(const ASignalName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to FFTMLSignalCount - 1 do
  begin
    if SameText(FFTMLSignals[i].SignalName, ASignalName) then
      Exit(i);
  end;
  Result := -1;
end;

procedure TFloriaFTMLItem.AddSignalHandler(const ASignalName: string; AHandler: TFloriaJSStmtNode);
var
  idx: Integer;
begin
  idx := FindSignalIndex(ASignalName);
  if idx >= 0 then
  begin
    FFTMLSignals[idx].HandlerStmt := AHandler;
    Exit;
  end;

  if FFTMLSignalCount >= Length(FFTMLSignals) then
  begin
    if Length(FFTMLSignals) = 0 then
      SetLength(FFTMLSignals, 4)
    else
      SetLength(FFTMLSignals, Length(FFTMLSignals) * 2);
  end;

  FFTMLSignals[FFTMLSignalCount].SignalName := ASignalName;
  FFTMLSignals[FFTMLSignalCount].HandlerStmt := AHandler;
  Inc(FFTMLSignalCount);
end;

function TFloriaFTMLItem.EmitSignal(const ASignalName: string; const AArgs: array of TFloriaJSValue): TFloriaJSValue;
var
  normName, onName: string;
  idx: Integer;
  evaluator: TFloriaJSEvaluator;
  sigEnv: TFloriaJSEnvironment;
  closureMark: Integer;
  i: Integer;
begin
  Result := JSMakeUndefined();

  normName := ASignalName;
  if (Length(normName) > 2) and (Copy(normName, 1, 2) = 'on') then
  begin
    onName := normName;
    normName := LowerCase(Copy(normName, 3, 1)) + Copy(normName, 4, Length(normName) - 3);
  end
  else
  begin
    onName := 'on' + UpCase(Copy(normName, 1, 1)) + Copy(normName, 2, Length(normName) - 1);
  end;

  idx := FindSignalIndex(onName);
  if idx < 0 then
    idx := FindSignalIndex(normName);

  if (idx >= 0) and (FFTMLSignals[idx].HandlerStmt <> nil) then
  begin
    evaluator := nil;
    if (FEngine <> nil) and (FEngine is IFloriaFTMLEngineContext) then
      evaluator := (FEngine as IFloriaFTMLEngineContext).GetEvaluator();

    if evaluator <> nil then
    begin
      sigEnv := TFloriaJSEnvironment.Create(FEnv);
      closureMark := evaluator.GetClosureCount();
      try
        sigEnv.DelegateObject := Self;
        if Length(AArgs) > 0 then
          sigEnv.Define('mouse', AArgs[0]);
        for i := 0 to High(AArgs) do
          sigEnv.Define('arg' + IntToStr(i), AArgs[i]);

        Result := evaluator.ExecuteStmt(FFTMLSignals[idx].HandlerStmt, sigEnv);
      finally
        { The signal scope may only outlive the handler when a closure captured
          it. In that case the scope is handed over to the runtime instead of
          being released, so the closure keeps a valid scope chain. }
        if evaluator.GetClosureCount() = closureMark then
          sigEnv.Free()
        else
          evaluator.RetainEnv(sigEnv);
      end;
    end;
  end;
end;

function TFloriaFTMLItem.EmitSignal(const ASignalName: string): TFloriaJSValue;
begin
  Result := EmitSignal(ASignalName, []);
end;

function TFloriaFTMLItem.GetX(): Double;
begin
  Result := GetPropertyAsNumber('x', 0.0);
end;

procedure TFloriaFTMLItem.SetX(AVal: Double);
begin
  SetProperty('x', JSMakeNumber(AVal));
end;

function TFloriaFTMLItem.GetY(): Double;
begin
  Result := GetPropertyAsNumber('y', 0.0);
end;

procedure TFloriaFTMLItem.SetY(AVal: Double);
begin
  SetProperty('y', JSMakeNumber(AVal));
end;

function TFloriaFTMLItem.GetWidth(): Double;
begin
  Result := GetPropertyAsNumber('width', 0.0);
end;

procedure TFloriaFTMLItem.SetWidth(AVal: Double);
begin
  SetProperty('width', JSMakeNumber(AVal));
end;

function TFloriaFTMLItem.GetHeight(): Double;
begin
  Result := GetPropertyAsNumber('height', 0.0);
end;

procedure TFloriaFTMLItem.SetHeight(AVal: Double);
begin
  SetProperty('height', JSMakeNumber(AVal));
end;

function TFloriaFTMLItem.GetVisible(): Boolean;
begin
  Result := GetPropertyAsBoolean('visible', True);
end;

procedure TFloriaFTMLItem.SetVisible(AVal: Boolean);
begin
  SetProperty('visible', JSMakeBoolean(AVal));
end;

function TFloriaFTMLItem.GetOpacity(): Double;
begin
  Result := GetPropertyAsNumber('opacity', 1.0);
end;

procedure TFloriaFTMLItem.SetOpacity(AVal: Double);
begin
  SetProperty('opacity', JSMakeNumber(AVal));
end;

{ TFloriaFTMLRectangle }

constructor TFloriaFTMLRectangle.Create(const ATypeName: string; AEngine: TObject);
begin
  inherited Create(ATypeName, AEngine);
  DefineProperty('color', JSMakeString('#ffffff'));
  DefineProperty('radius', JSMakeNumber(0.0));
  DefineProperty('borderWidth', JSMakeNumber(0.0));
  DefineProperty('borderColor', JSMakeString('#000000'));
end;

function TFloriaFTMLRectangle.GetColor(): string;
begin
  Result := GetPropertyAsString('color', '#ffffff');
end;

procedure TFloriaFTMLRectangle.SetColor(const AVal: string);
begin
  SetProperty('color', JSMakeString(AVal));
end;

function TFloriaFTMLRectangle.GetRadius(): Double;
begin
  Result := GetPropertyAsNumber('radius', 0.0);
end;

procedure TFloriaFTMLRectangle.SetRadius(AVal: Double);
begin
  SetProperty('radius', JSMakeNumber(AVal));
end;

function TFloriaFTMLRectangle.GetBorderWidth(): Double;
begin
  Result := GetPropertyAsNumber('borderWidth', 0.0);
end;

procedure TFloriaFTMLRectangle.SetBorderWidth(AVal: Double);
begin
  SetProperty('borderWidth', JSMakeNumber(AVal));
end;

function TFloriaFTMLRectangle.GetBorderColor(): string;
begin
  Result := GetPropertyAsString('borderColor', '#000000');
end;

procedure TFloriaFTMLRectangle.SetBorderColor(const AVal: string);
begin
  SetProperty('borderColor', JSMakeString(AVal));
end;

{ TFloriaFTMLText }

constructor TFloriaFTMLText.Create(const ATypeName: string; AEngine: TObject);
begin
  inherited Create(ATypeName, AEngine);
  DefineProperty('text', JSMakeString(''));
  DefineProperty('color', JSMakeString('#000000'));
  DefineProperty('fontSize', JSMakeNumber(14.0));
  DefineProperty('fontFamily', JSMakeString('sans-serif'));
  DefineProperty('alignment', JSMakeString('left'));
end;

function TFloriaFTMLText.GetText(): string;
begin
  Result := GetPropertyAsString('text', '');
end;

procedure TFloriaFTMLText.SetText(const AVal: string);
begin
  SetProperty('text', JSMakeString(AVal));
end;

function TFloriaFTMLText.GetColor(): string;
begin
  Result := GetPropertyAsString('color', '#000000');
end;

procedure TFloriaFTMLText.SetColor(const AVal: string);
begin
  SetProperty('color', JSMakeString(AVal));
end;

function TFloriaFTMLText.GetFontSize(): Double;
begin
  Result := GetPropertyAsNumber('fontSize', 14.0);
end;

procedure TFloriaFTMLText.SetFontSize(AVal: Double);
begin
  SetProperty('fontSize', JSMakeNumber(AVal));
end;

function TFloriaFTMLText.GetFontFamily(): string;
begin
  Result := GetPropertyAsString('fontFamily', 'sans-serif');
end;

procedure TFloriaFTMLText.SetFontFamily(const AVal: string);
begin
  SetProperty('fontFamily', JSMakeString(AVal));
end;

{ TFloriaFTMLButton }

constructor TFloriaFTMLButton.Create(const ATypeName: string; AEngine: TObject);
begin
  inherited Create(ATypeName, AEngine);
  DefineProperty('text', JSMakeString(''));
  DefineProperty('pressed', JSMakeBoolean(False));
  DefineProperty('hovered', JSMakeBoolean(False));
end;

function TFloriaFTMLButton.GetText(): string;
begin
  Result := GetPropertyAsString('text', '');
end;

procedure TFloriaFTMLButton.SetText(const AVal: string);
begin
  SetProperty('text', JSMakeString(AVal));
end;

function TFloriaFTMLButton.GetPressed(): Boolean;
begin
  Result := GetPropertyAsBoolean('pressed', False);
end;

procedure TFloriaFTMLButton.SetPressed(AVal: Boolean);
begin
  SetProperty('pressed', JSMakeBoolean(AVal));
end;

function TFloriaFTMLButton.GetHovered(): Boolean;
begin
  Result := GetPropertyAsBoolean('hovered', False);
end;

procedure TFloriaFTMLButton.SetHovered(AVal: Boolean);
begin
  SetProperty('hovered', JSMakeBoolean(AVal));
end;

procedure TFloriaFTMLButton.Click();
begin
  EmitSignal('clicked', []);
end;

{ TFloriaFTMLTextInput }

constructor TFloriaFTMLTextInput.Create(const ATypeName: string; AEngine: TObject);
begin
  inherited Create(ATypeName, AEngine);
  DefineProperty('text', JSMakeString(''));
  DefineProperty('placeholder', JSMakeString(''));
  DefineProperty('readOnly', JSMakeBoolean(False));
end;

function TFloriaFTMLTextInput.GetText(): string;
begin
  Result := GetPropertyAsString('text', '');
end;

procedure TFloriaFTMLTextInput.SetText(const AVal: string);
begin
  SetProperty('text', JSMakeString(AVal));
end;

function TFloriaFTMLTextInput.GetPlaceholder(): string;
begin
  Result := GetPropertyAsString('placeholder', '');
end;

procedure TFloriaFTMLTextInput.SetPlaceholder(const AVal: string);
begin
  SetProperty('placeholder', JSMakeString(AVal));
end;

function TFloriaFTMLTextInput.GetReadOnly(): Boolean;
begin
  Result := GetPropertyAsBoolean('readOnly', False);
end;

procedure TFloriaFTMLTextInput.SetReadOnly(AVal: Boolean);
begin
  SetProperty('readOnly', JSMakeBoolean(AVal));
end;

{ TFloriaFTMLColumn }

constructor TFloriaFTMLColumn.Create(const ATypeName: string; AEngine: TObject);
begin
  inherited Create(ATypeName, AEngine);
  DefineProperty('spacing', JSMakeNumber(0.0));
  DefineProperty('gap', JSMakeNumber(0.0));
end;

function TFloriaFTMLColumn.GetSpacing(): Double;
var
  g: Double;
begin
  g := GetPropertyAsNumber('gap', -1.0);
  if g >= 0.0 then
    Result := g
  else
    Result := GetPropertyAsNumber('spacing', 0.0);
end;

procedure TFloriaFTMLColumn.SetSpacing(AVal: Double);
begin
  SetProperty('spacing', JSMakeNumber(AVal));
  SetProperty('gap', JSMakeNumber(AVal));
  Relayout();
end;

procedure TFloriaFTMLColumn.Relayout();
var
  i: Integer;
  curY, sp, maxW: Double;
  child: TFloriaFTMLItem;
begin
  curY := 0.0;
  maxW := 0.0;
  sp := GetSpacing();
  for i := 0 to ChildCount() - 1 do
  begin
    child := GetChild(i);
    if child.Visible then
    begin
      child.Y := curY;
      curY := curY + child.Height + sp;
      if child.Width > maxW then
        maxW := child.Width;
    end;
  end;
  if (Height <= 0.0) and (curY > 0.0) then
    Height := curY - sp;
  if (Width <= 0.0) and (maxW > 0.0) then
    Width := maxW;
end;

{ TFloriaFTMLRow }

constructor TFloriaFTMLRow.Create(const ATypeName: string; AEngine: TObject);
begin
  inherited Create(ATypeName, AEngine);
  DefineProperty('spacing', JSMakeNumber(0.0));
  DefineProperty('gap', JSMakeNumber(0.0));
end;

function TFloriaFTMLRow.GetSpacing(): Double;
var
  g: Double;
begin
  g := GetPropertyAsNumber('gap', -1.0);
  if g >= 0.0 then
    Result := g
  else
    Result := GetPropertyAsNumber('spacing', 0.0);
end;

procedure TFloriaFTMLRow.SetSpacing(AVal: Double);
begin
  SetProperty('spacing', JSMakeNumber(AVal));
  SetProperty('gap', JSMakeNumber(AVal));
  Relayout();
end;

procedure TFloriaFTMLRow.Relayout();
var
  i: Integer;
  curX, sp, maxH: Double;
  child: TFloriaFTMLItem;
begin
  curX := 0.0;
  maxH := 0.0;
  sp := GetSpacing();
  for i := 0 to ChildCount() - 1 do
  begin
    child := GetChild(i);
    if child.Visible then
    begin
      child.X := curX;
      curX := curX + child.Width + sp;
      if child.Height > maxH then
        maxH := child.Height;
    end;
  end;
  if (Width <= 0.0) and (curX > 0.0) then
    Width := curX - sp;
  if (Height <= 0.0) and (maxH > 0.0) then
    Height := maxH;
end;

{ TFloriaFTMLFlexBox }

constructor TFloriaFTMLFlexBox.Create(const ATypeName: string; AEngine: TObject);
begin
  inherited Create(ATypeName, AEngine);
  DefineProperty('direction', JSMakeString('row'));
  DefineProperty('wrap', JSMakeString('nowrap'));
  DefineProperty('justifyContent', JSMakeString('flex-start'));
  DefineProperty('alignItems', JSMakeString('stretch'));
  DefineProperty('gap', JSMakeNumber(0.0));
  DefineProperty('spacing', JSMakeNumber(0.0));
  DefineProperty('padding', JSMakeNumber(0.0));
end;

function TFloriaFTMLFlexBox.GetDirection(): string;
begin
  Result := GetPropertyAsString('direction', 'row');
end;

procedure TFloriaFTMLFlexBox.SetDirection(const AVal: string);
begin
  SetProperty('direction', JSMakeString(AVal));
end;

function TFloriaFTMLFlexBox.GetWrap(): string;
begin
  Result := GetPropertyAsString('wrap', 'nowrap');
end;

procedure TFloriaFTMLFlexBox.SetWrap(const AVal: string);
begin
  SetProperty('wrap', JSMakeString(AVal));
end;

function TFloriaFTMLFlexBox.GetJustifyContent(): string;
begin
  Result := GetPropertyAsString('justifyContent', 'flex-start');
end;

procedure TFloriaFTMLFlexBox.SetJustifyContent(const AVal: string);
begin
  SetProperty('justifyContent', JSMakeString(AVal));
end;

function TFloriaFTMLFlexBox.GetAlignItems(): string;
begin
  Result := GetPropertyAsString('alignItems', 'stretch');
end;

procedure TFloriaFTMLFlexBox.SetAlignItems(const AVal: string);
begin
  SetProperty('alignItems', JSMakeString(AVal));
end;

function TFloriaFTMLFlexBox.GetGap(): Double;
var
  g: Double;
begin
  g := GetPropertyAsNumber('gap', -1.0);
  if g >= 0.0 then
    Result := g
  else
    Result := GetPropertyAsNumber('spacing', 0.0);
end;

procedure TFloriaFTMLFlexBox.SetGap(AVal: Double);
begin
  SetProperty('gap', JSMakeNumber(AVal));
  SetProperty('spacing', JSMakeNumber(AVal));
end;

function TFloriaFTMLFlexBox.GetPadding(): Double;
begin
  Result := GetPropertyAsNumber('padding', 0.0);
end;

procedure TFloriaFTMLFlexBox.SetPadding(AVal: Double);
begin
  SetProperty('padding', JSMakeNumber(AVal));
end;

{ TFloriaFTMLGrid }

constructor TFloriaFTMLGrid.Create(const ATypeName: string; AEngine: TObject);
begin
  inherited Create(ATypeName, AEngine);
  DefineProperty('columns', JSMakeNumber(2.0));
  DefineProperty('rows', JSMakeNumber(0.0));
  DefineProperty('gap', JSMakeNumber(0.0));
  DefineProperty('spacing', JSMakeNumber(0.0));
  DefineProperty('columnGap', JSMakeNumber(0.0));
  DefineProperty('rowGap', JSMakeNumber(0.0));
  DefineProperty('columnsTemplate', JSMakeString(''));
  DefineProperty('rowsTemplate', JSMakeString(''));
end;

function TFloriaFTMLGrid.GetColumns(): Integer;
begin
  Result := Round(GetPropertyAsNumber('columns', 2.0));
end;

procedure TFloriaFTMLGrid.SetColumns(AVal: Integer);
begin
  SetProperty('columns', JSMakeNumber(AVal));
end;

function TFloriaFTMLGrid.GetRows(): Integer;
begin
  Result := Round(GetPropertyAsNumber('rows', 0.0));
end;

procedure TFloriaFTMLGrid.SetRows(AVal: Integer);
begin
  SetProperty('rows', JSMakeNumber(AVal));
end;

function TFloriaFTMLGrid.GetGap(): Double;
var
  g: Double;
begin
  g := GetPropertyAsNumber('gap', -1.0);
  if g >= 0.0 then
    Result := g
  else
    Result := GetPropertyAsNumber('spacing', 0.0);
end;

procedure TFloriaFTMLGrid.SetGap(AVal: Double);
begin
  SetProperty('gap', JSMakeNumber(AVal));
  SetProperty('spacing', JSMakeNumber(AVal));
end;

function TFloriaFTMLGrid.GetColumnGap(): Double;
var
  cg: Double;
begin
  cg := GetPropertyAsNumber('columnGap', -1.0);
  if cg >= 0.0 then
    Result := cg
  else
    Result := GetGap();
end;

procedure TFloriaFTMLGrid.SetColumnGap(AVal: Double);
begin
  SetProperty('columnGap', JSMakeNumber(AVal));
end;

function TFloriaFTMLGrid.GetRowGap(): Double;
var
  rg: Double;
begin
  rg := GetPropertyAsNumber('rowGap', -1.0);
  if rg >= 0.0 then
    Result := rg
  else
    Result := GetGap();
end;

procedure TFloriaFTMLGrid.SetRowGap(AVal: Double);
begin
  SetProperty('rowGap', JSMakeNumber(AVal));
end;

end.
