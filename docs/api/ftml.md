# FTML API Reference

The FTML layer spans three units:

| Unit | Contents |
| :--- | :--- |
| `floria.ftml.types` | Item hierarchy, properties, anchors, signals, anchor-line objects, binding interfaces. |
| `floria.ftml.binding` | `TFloriaFTMLBinding`, `TFloriaFTMLBindingManager`. |
| `floria.ftml.engine` | `TFloriaFTMLEngine` (parse, instantiate, document lifecycle). |

All are re-exported by `floriajs`. See the [FTML guide](../ftml.md) for the
markup syntax and reactive semantics.

## `TFloriaFTMLEngine`

```pascal
constructor Create(AContext: TFloriaJSContext = nil);
destructor Destroy(); override;

function  GetEvaluator(): TFloriaJSEvaluator;

procedure RegisterComponentType(const ATypeName: string; AClass: TFloriaFTMLItemClass);
function  CreateItem(const ATypeName: string): TFloriaFTMLItem;

function  LoadString(const AFTMLSource: string): TFloriaFTMLItem;
function  LoadFile(const AFileName: string): TFloriaFTMLItem;

function  FindItemById(const AId: string): TFloriaFTMLItem;
function  Evaluate(const AScript: string): TFloriaJSValue;
procedure ReleaseValue(const AValue: TFloriaJSValue);
function  HasErrors(): Boolean;

property JSContext: TFloriaJSContext read FContext;
property BindingManager: TFloriaFTMLBindingManager read FBindingManager;
property Root: TFloriaFTMLItem read FRootItem;
property LastError: string read FLastError;
```

- `Create(nil)` creates and owns a private `TFloriaJSContext`. Pass a context
  to share globals and native functions with the rest of the host.
- The engine registers these component types: `Item`, `Rectangle`, `Text`,
  `Button`, `TextInput`, `Column`, `Row`, `FlexBox`, `Grid`.
- `RegisterComponentType` maps a markup type name to a `TFloriaFTMLItem`
  subclass. Names are matched case-insensitively. Register types before
  loading; if the same name is registered twice, the first mapping wins.
- `CreateItem` instantiates the registered class, or `TFloriaFTMLItem` when the
  name is not registered. The item is tracked by the context heap as
  `HeapOwned = False` and belongs to the current document.
- `LoadString` releases the previous document, parses, instantiates, wires
  bindings, runs layout/anchor resolution, and fires completion signals. It
  returns `nil` and sets `LastError` on a syntax/instantiation failure.
- `LoadFile` returns `nil` with `LastError = 'File not found: …'` when the file
  is missing; otherwise it loads the text and calls `LoadString`.
- `FindItemById` checks the ID registry first, then walks the live tree.
  Returns `nil` when the ID is unknown.
- `Evaluate` parses and executes a script in the document root environment
  (`Root`'s parent), or the context global environment when no document is
  loaded. Object results are pinned; call `ReleaseValue` when finished.
- `HasErrors` is true when `LastError` is non-empty.
- `Root` is the current document root, or `nil`.

### Ownership

- If the engine created the context, it frees it in its destructor.
- The engine owns the live document: items, environments, AST, bindings, and
  functions. `LoadString` and destruction release them.
- A runtime closure that captures document state can keep the previous
  document alive across a reload. The engine tracks those escaped documents and
  releases them when it is destroyed.
- IDs are registered in the document environment and in the context global
  environment. Reload removes them from both, but only when the binding still
  points at this document's item.

## `TFloriaFTMLItem`

```pascal
constructor Create(const ATypeName: string; AEngine: TObject = nil); virtual;
destructor Destroy(); override;
```

### Hierarchy

```pascal
procedure AddChild(AChild: TFloriaFTMLItem);
procedure RemoveChild(AChild: TFloriaFTMLItem);
function  ChildCount(): Integer;
function  GetChild(AIndex: Integer): TFloriaFTMLItem;
function  FindById(const AId: string): TFloriaFTMLItem;
function  FindChild(const AName: string): TFloriaFTMLItem;
```

`FindById` searches this item and its descendants. `FindChild` looks only at
the immediate children and returns the first whose ID **or** type name equals
the argument.

### Properties

```pascal
function  GetProperty(const AName: string): TFloriaJSValue; override;
procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); override;
procedure SetPropertyFromBinding(const AName: string; const AValue: TFloriaJSValue);
function  HasProperty(const AName: string): Boolean; override;

function  DefineProperty(const AName: string; const ADefault: TFloriaJSValue): Integer;
function  FindPropertyIndex(const AName: string): Integer;
function  GetPropertyCount(): Integer;
function  GetPropertyName(AIndex: Integer): string;
function  GetPropertyValue(AIndex: Integer): TFloriaJSValue;

function  GetPropertyAsNumber(const AName: string; ADefault: Double = 0.0): Double;
function  GetPropertyAsString(const AName: string; const ADefault: string = ''): string;
function  GetPropertyAsBoolean(const AName: string; ADefault: Boolean = False): Boolean;
```

- `SetProperty` detaches an existing binding on that property. Use
  `SetPropertyFromBinding` only from the binding layer.
- A property value change emits `<name>Changed` and notifies the binding
  manager. Anchor-related changes also trigger anchor resolution.
- `DefineProperty` adds a property if it does not exist and returns its index.
- `GetProperty` recognises the meta-properties `id`, `parent`, `children`, and
  the anchor-line names (`left`, `right`, `top`, `bottom`,
  `horizontalCenter`, `verticalCenter`, `baseline`). It also translates the
  `Layout.*` aliases before falling back to stored properties and the base
  object.

### Bindings

```pascal
procedure AttachBinding(const AName: string; ABinding: TObject);
procedure DetachBinding(const AName: string);
function  HasBinding(const AName: string): Boolean;
function  GetBinding(const AName: string): TObject;
```

These are bookkeeping helpers used by the binding manager. Host code rarely
calls them.

### Signals

```pascal
procedure AddSignalHandler(const ASignalName: string; AHandler: TFloriaJSStmtNode);
function  EmitSignal(const ASignalName: string;
  const AArgs: array of TFloriaJSValue): TFloriaJSValue;
function  EmitSignal(const ASignalName: string): TFloriaJSValue;
```

`EmitSignal` normalises `clicked` ↔ `onClicked`, finds the handler, and
executes it in a child environment of the item scope. Arguments are bound as
`arg0…argN`; the first is also bound as `mouse`. Unknown signals return
`undefined`.

### Common visual accessors

```pascal
function  GetX(): Double;              procedure SetX(AVal: Double);
function  GetY(): Double;              procedure SetY(AVal: Double);
function  GetWidth(): Double;          procedure SetWidth(AVal: Double);
function  GetHeight(): Double;         procedure SetHeight(AVal: Double);
function  GetVisible(): Boolean;       procedure SetVisible(AVal: Boolean);
function  GetOpacity(): Double;        procedure SetOpacity(AVal: Double);
```

Exposed as properties: `X`, `Y`, `Width`, `Height`, `Visible`, `Opacity` with
defaults `0, 0, 0, 0, True, 1`.

### Anchors

```pascal
procedure ResolveAnchors();
function  HasAnchors(): Boolean;
procedure DetachAnchors();
```

`HasAnchors` is true when any `anchors.*` property is defined. `ResolveAnchors`
computes positions from the configured edges, margins, and offsets.
`DetachAnchors` unlinks the item from other items' anchor graphs.

### Flex/grid child accessors

```pascal
function  GetFlexGrow(): Double;       procedure SetFlexGrow(AVal: Double);
function  GetFlexShrink(): Double;     procedure SetFlexShrink(AVal: Double);
function  GetFlexBasis(): Double;      procedure SetFlexBasis(AVal: Double);
function  GetAlignSelf(): string;      procedure SetAlignSelf(const AVal: string);
function  GetGridColumn(): Integer;    procedure SetGridColumn(AVal: Integer);
function  GetGridRow(): Integer;       procedure SetGridRow(AVal: Integer);
function  GetColSpan(): Integer;       procedure SetColSpan(AVal: Integer);
function  GetRowSpan(): Integer;       procedure SetRowSpan(AVal: Integer);
```

Exposed as `FlexGrow`, `FlexShrink`, `FlexBasis`, `AlignSelf`, `GridColumn`,
`GridRow`, `ColSpan`, `RowSpan`.

### Fields and properties

```pascal
property TypeName: string read FTypeName;
property Id: string read FId write FId;
property Parent: TFloriaFTMLItem read FParent write FParent;
property Engine: TObject read FEngine write FEngine;
property Env: TFloriaJSEnvironment read FEnv write FEnv;
property BindingManager: IFloriaFTMLBindingManager read FBindingManager write FBindingManager;
```

`Engine` is the owning `TFloriaFTMLEngine`, stored as `TObject` to avoid a unit
cycle. It is queried through `IFloriaFTMLEngineContext` when a signal handler
needs the evaluator.

## Anchor lines

```pascal
TFloriaFTMLAnchorLine = class(TFloriaJSObject)
  property Item: TFloriaFTMLItem read FItem;
  property Edge: TFloriaAnchorEdge read FEdge;
end;

TFloriaAnchorEdge = (
  faeNone, faeLeft, faeRight, faeTop, faeBottom,
  faeHorizontalCenter, faeVerticalCenter, faeBaseline
);
```

Anchor lines are JavaScript object values owned by the item; each item frees
its own anchor-line objects in its destructor. Reading `item.left`,
`item.right`, and similar properties returns one. Assigning it to an
`anchors.*` property registers the source item as an anchor target.

## Built-in item classes

| Class | Public accessors |
| :--- | :--- |
| `TFloriaFTMLRectangle` | `Color`, `Radius`, `BorderWidth`, `BorderColor` |
| `TFloriaFTMLText` | `Text`, `Color`, `FontSize`, `FontFamily` |
| `TFloriaFTMLButton` | `Text`, `Pressed`, `Hovered`; `Click()` |
| `TFloriaFTMLTextInput` | `Text`, `Placeholder`, `ReadOnly` |
| `TFloriaFTMLColumn` | `Spacing`; `Relayout()` |
| `TFloriaFTMLRow` | `Spacing`; `Relayout()` |
| `TFloriaFTMLFlexBox` | `Direction`, `Wrap`, `JustifyContent`, `AlignItems`, `Gap`, `Padding` |
| `TFloriaFTMLGrid` | `Columns`, `Rows`, `Gap`, `ColumnGap`, `RowGap` |

All subclass constructors default the type name (`Rectangle`, `Text`, …) and
accept an optional engine pointer.

### Writing a custom component

```pascal
type
  TGauge = class(TFloriaFTMLItem)
  private
    function GetValue(): Double;
    procedure SetValue(AValue: Double);
  public
    constructor Create(const ATypeName: string = 'Gauge';
      AEngine: TObject = nil); override;
    property Value: Double read GetValue write SetValue;
  end;

constructor TGauge.Create(const ATypeName: string; AEngine: TObject);
begin
  inherited Create(ATypeName, AEngine);
  DefineProperty('value', JSMakeNumber(0.0));
  DefineProperty('max', JSMakeNumber(100.0));
end;

function TGauge.GetValue(): Double;
begin
  Result := GetPropertyAsNumber('value', 0.0);
end;

procedure TGauge.SetValue(AValue: Double);
begin
  SetProperty('value', JSMakeNumber(AValue));
end;

Engine.RegisterComponentType('Gauge', TGauge);
```

Then `Gauge { value: 42; max: 100; }` instantiates `TGauge`. The host renderer
can cast `FindItemById` results to `TGauge` and read `Value`.

## `TFloriaFTMLBinding`

```pascal
constructor Create(AManager: TFloriaFTMLBindingManager;
  ATargetItem: TFloriaFTMLItem; const ATargetProperty: string;
  AExpr: TFloriaJSExprNode; AEnv: TFloriaJSEnvironment);
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
```

A binding owns no AST; the document AST outlives it. `Evaluate` clears previous
dependencies, evaluates the expression in its environment, records reads
through the manager's active-binding stack, and writes the result with
`SetPropertyFromBinding`. Recursive evaluation of the same binding returns the
current target property value instead of looping.

## `TFloriaFTMLBindingManager`

```pascal
constructor Create(AEvaluator: TFloriaJSEvaluator);
destructor Destroy(); override;

procedure RecordPropertyRead(AItem: TObject; const APropName: string);
procedure NotifyPropertyChanged(AItem: TObject; const APropName: string);
procedure RemoveBindingsForTarget(ATargetItem: TObject;
  const ATargetProperty: string = '');

procedure PushActiveBinding(ABinding: TFloriaFTMLBinding);
procedure PopActiveBinding();
function  CurrentActiveBinding(): TFloriaFTMLBinding;

function  CreateBinding(ATargetItem: TFloriaFTMLItem;
  const ATargetProperty: string; AExpr: TFloriaJSExprNode;
  AEnv: TFloriaJSEnvironment): TFloriaFTMLBinding;
procedure RemoveBinding(ABinding: TFloriaFTMLBinding);

property Evaluator: TFloriaJSEvaluator read FEvaluator write FEvaluator;
property BindingCount: Integer read GetBindingCount;
property MaxCascadeDepth: Integer read FMaxCascadeDepth write FMaxCascadeDepth;
```

- Implements `IFloriaFTMLBindingManager`, which items use for dependency
  notifications.
- `RecordPropertyRead` adds a dependency only while a binding is active.
- `NotifyPropertyChanged` re-evaluates all enabled, non-reentrant bindings that
  depend on the changed property. Cascades are capped by `MaxCascadeDepth`
  (default 100).
- `RemoveBindingsForTarget` is called when a property is assigned normally, so
  the binding is detached.
- `CreateBinding` registers the binding with the manager. `RemoveBinding`
  unregisters and frees it.
- The manager does not own the evaluator; the engine owns both.

## Interfaces

```pascal
IFloriaFTMLBindingManager = interface
  procedure RecordPropertyRead(AItem: TObject; const APropName: string);
  procedure NotifyPropertyChanged(AItem: TObject; const APropName: string);
  procedure RemoveBindingsForTarget(ATargetItem: TObject;
    const ATargetProperty: string = '');
end;

IFloriaFTMLEngineContext = interface
  function GetEvaluator(): TFloriaJSEvaluator;
end;
```

`TFloriaFTMLItem.BindingManager` and `Engine` are typed as interfaces/`TObject`
so the types unit does not depend on the binding or engine units. A custom item
implementation that wants signal execution must ensure `Engine` implements
`IFloriaFTMLEngineContext`.

## Lifetime notes

- Items are owned by the document, not by the heap. The heap tracks them with
  `HeapOwned = False` so `Collect` never frees them.
- Item property values are released when the item is destroyed, but only when
  the originating heap is still alive (`JSHeapIsAlive`). This prevents touching
  values after the runtime has been torn down.
- Bindings must be destroyed before their AST expression and target item.
  `TFloriaFTMLEngine` enforces this order during reload and destruction.
- The document AST is freed on reload unless a runtime closure escaped; escaped
  ASTs are released with the engine.
