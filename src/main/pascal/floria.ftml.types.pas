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
  Classes, SysUtils, floria.js.types, floria.js.ast, floria.js.value,
  floria.js.env, floria.js.evaluator;

type
  { Forward Declarations }
  TFloriaFTMLItem = class;
  TFloriaFTMLItemClass = class of TFloriaFTMLItem;

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

    procedure SetPropertyInternal(const AName: string; const AValue: TFloriaJSValue; AFromBinding: Boolean);
    function  GetChildrenAsJSArray(): TFloriaJSValue;
    function  FindSignalIndex(const ASignalName: string): Integer;
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

  { Backward Compatibility Aliases }
  TFloriaQMLItem           = TFloriaFTMLItem;
  TFloriaQMLItemClass      = TFloriaFTMLItemClass;
  TFloriaQMLRectangle      = TFloriaFTMLRectangle;
  TFloriaQMLText           = TFloriaFTMLText;
  TFloriaQMLButton         = TFloriaFTMLButton;
  TFloriaQMLTextInput      = TFloriaFTMLTextInput;
  TFloriaQMLColumn         = TFloriaFTMLColumn;
  TFloriaQMLRow            = TFloriaFTMLRow;
  IFloriaQMLBindingManager = IFloriaFTMLBindingManager;
  IFloriaQMLEngineContext  = IFloriaFTMLEngineContext;

implementation

{ TFloriaFTMLItem }

constructor TFloriaFTMLItem.Create(const ATypeName: string; AEngine: TObject);
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

  // Initialize standard visual properties
  DefineProperty('x', JSMakeNumber(0.0));
  DefineProperty('y', JSMakeNumber(0.0));
  DefineProperty('width', JSMakeNumber(0.0));
  DefineProperty('height', JSMakeNumber(0.0));
  DefineProperty('visible', JSMakeBoolean(True));
  DefineProperty('opacity', JSMakeNumber(1.0));
  DefineProperty('clip', JSMakeBoolean(False));
  DefineProperty('enabled', JSMakeBoolean(True));
end;

destructor TFloriaFTMLItem.Destroy();
begin
  SetLength(FFTMLProperties, 0);
  SetLength(FFTMLSignals, 0);
  if FChildren <> nil then
  begin
    FChildren.Clear();
    FreeAndNil(FChildren);
  end;
  inherited Destroy();
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
    FFTMLProperties[idx].Value := ADefault;
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
  FFTMLProperties[FFTMLPropCount].HasBinding := False;
  FFTMLProperties[FFTMLPropCount].BindingRef := nil;
  idx := FFTMLPropCount;
  Inc(FFTMLPropCount);
  Result := idx;
end;

function TFloriaFTMLItem.GetChildrenAsJSArray(): TFloriaJSValue;
var
  arr: TFloriaJSArray;
  i: Integer;
begin
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
    FFTMLProperties[idx].Value := AValue;
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

  if valChanged then
  begin
    // Notify binding manager to propagate changes to dependent bindings
    if FBindingManager <> nil then
      FBindingManager.NotifyPropertyChanged(Self, AName);

    // Emit property change signal: on<PropName>Changed (e.g. onWidthChanged)
    EmitSignal(AName + 'Changed', [AValue]);
  end;
end;

function TFloriaFTMLItem.HasProperty(const AName: string): Boolean;
begin
  if (AName = 'id') or (AName = 'parent') or (AName = 'children') then
    Exit(True);

  if FindPropertyIndex(AName) >= 0 then
    Exit(True);

  Result := inherited HasProperty(AName);
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
      try
        sigEnv.DelegateObject := Self;
        if Length(AArgs) > 0 then
          sigEnv.Define('mouse', AArgs[0]);
        for i := 0 to High(AArgs) do
          sigEnv.Define('arg' + IntToStr(i), AArgs[i]);

        Result := evaluator.ExecuteStmt(FFTMLSignals[idx].HandlerStmt, sigEnv);
      finally
        sigEnv.Free();
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
end;

function TFloriaFTMLColumn.GetSpacing(): Double;
begin
  Result := GetPropertyAsNumber('spacing', 0.0);
end;

procedure TFloriaFTMLColumn.SetSpacing(AVal: Double);
begin
  SetProperty('spacing', JSMakeNumber(AVal));
  Relayout();
end;

procedure TFloriaFTMLColumn.Relayout();
var
  i: Integer;
  curY, sp: Double;
  child: TFloriaFTMLItem;
begin
  curY := 0.0;
  sp := GetSpacing();
  for i := 0 to ChildCount() - 1 do
  begin
    child := GetChild(i);
    if child.Visible then
    begin
      child.Y := curY;
      curY := curY + child.Height + sp;
    end;
  end;
end;

{ TFloriaFTMLRow }

constructor TFloriaFTMLRow.Create(const ATypeName: string; AEngine: TObject);
begin
  inherited Create(ATypeName, AEngine);
  DefineProperty('spacing', JSMakeNumber(0.0));
end;

function TFloriaFTMLRow.GetSpacing(): Double;
begin
  Result := GetPropertyAsNumber('spacing', 0.0);
end;

procedure TFloriaFTMLRow.SetSpacing(AVal: Double);
begin
  SetProperty('spacing', JSMakeNumber(AVal));
  Relayout();
end;

procedure TFloriaFTMLRow.Relayout();
var
  i: Integer;
  curX, sp: Double;
  child: TFloriaFTMLItem;
begin
  curX := 0.0;
  sp := GetSpacing();
  for i := 0 to ChildCount() - 1 do
  begin
    child := GetChild(i);
    if child.Visible then
    begin
      child.X := curX;
      curX := curX + child.Width + sp;
    end;
  end;
end;

end.
