# FTML Guide

FTML (Floria Toolkit Markup Language) is a declarative component syntax parsed
and executed by the same JavaScript runtime. It provides:

- a component hierarchy with typed items,
- reactive property bindings,
- semantic anchors and simple layouts,
- signal handlers written in JavaScript,
- document-scoped IDs and environments.

FTML produces a **runtime object model**, not pixels. Creating windows,
widgets, or draw calls is the host application's job.

## A minimal document

```text
Rectangle {
  id: mainWindow
  width: 600;
  height: 400;
  color: "#1e1e2e";

  Component.onCompleted: {
    console.log("ready");
  }

  Text {
    id: label
    text: "Size: " + mainWindow.width + " x " + mainWindow.height;
    color: "#cdd6f4";
    fontSize: 16;
  }

  Button {
    id: expand
    x: 20;
    y: 40;
    text: "Expand";
    onClicked: {
      mainWindow.width = mainWindow.width + 100;
    }
  }
}
```

Load it from Pascal:

```pascal
Engine := TFloriaFTMLEngine.Create();
try
  Root := Engine.LoadString(Source);
  if Root = nil then
  begin
    WriteLn('FTML error: ', Engine.LastError);
    Exit;
  end;

  Expand := Engine.FindItemById('expand');
  Expand.EmitSignal('clicked');

  WriteLn(Root.Width);   // 700
finally
  Engine.Free();
end;
```

## Syntax

An FTML document is one component:

```text
ComponentType {
  <members>
}
```

Members are separated by semicolons and/or newlines. Inside a component:

| Form | Meaning |
| :--- | :--- |
| `name: expression` | Property. The expression is evaluated in the item's scope. |
| `name: { statements }` | Signal handler, when `name` starts with `on` or contains `.on`. |
| `ChildType { … }` | Child component. |
| `id: someName` | Sets the item's ID. The value may be an identifier or a string. |
| `property TYPE name: expression` | Typed property declaration. `TYPE` is currently ignored; `name` is the property. |
| `function f(args) { … }` | Function bound to the item and its scope. |

Examples:

```text
Item {
  property int clickCount: 0;
  property string label: "Ready";
}
```

Property names may contain dots. This is used for namespaced properties and
signals such as `anchors.fill` and `Component.onCompleted`.

### Expressions and scope

Property expressions are ordinary JavaScript expressions. Each item has a
lexical environment whose delegate object is the item itself, so:

- unqualified identifiers resolve to the item's own properties first,
- `parent` refers to the parent item,
- document IDs are visible from anywhere in the document,
- the global JavaScript environment is the outermost parent.

```text
Rectangle {
  id: card
  width: 300;

  Text {
    text: width;                 // own property
    x: parent.width / 2;         // parent property
    y: card.height - 20;         // root-scope ID
  }
}
```

## Reactive bindings

A property whose expression is a **literal** is compiled and evaluated once
during load. Any other expression becomes a reactive binding. Each binding
expression is compiled to a `TFloriaJSBytecode` chunk once, when the binding is
created, and that chunk is re-used on every dependency update; this is what
keeps reactive evaluation on the bytecode VM instead of re-walking the AST.

```text
Rectangle {
  id: root
  width: 400;
  height: 300;

  Rectangle {
    id: card
    width: root.width - 40;          // binding
    height: root.height / 2;         // binding
    color: "#313244";                // literal: evaluated once
  }

  Text {
    text: "Card: " + card.width + " x " + card.height;  // binding
  }
}
```

When `root.width` changes:

1. The binding manager finds every binding that recorded a read of that
   property.
2. Each dependant is re-evaluated; writes to other properties cascade through
   the same mechanism until the graph settles.
3. Values are written with `SetPropertyFromBinding`, so the bindings stay
   active.

The manager prevents direct self-recursion and stops runaway cascades after
**100** nested updates (`MaxCascadeDepth`).

Reading a property during binding evaluation records a dependency. This
includes reads made through `parent`, through IDs, and through implicit item
scope. Cleanup happens when a binding re-evaluates: its old dependencies are
dropped and the new reads are recorded.

### Assignments break bindings

Assigning a bound property from JavaScript or Pascal detaches the binding:

```pascal
Card.Width := 500;   // the "root.width - 40" binding is removed
```

From JavaScript the same applies:

```text
onClicked: {
  card.width = 500;  // detaches card's width binding
}
```

Use direct assignment when the host or a user action should take ownership of
a value.

## Signals

A member whose name starts with `on` (or contains `.on`) and has a block or
statement body is registered as a signal handler:

```text
Button {
  text: "Save";
  onClicked: {
    saveDocument();
  }
}

Rectangle {
  Component.onCompleted: {
    console.log("loaded");
  }

  onWidthChanged: {
    console.log("width is now " + width);
  }
}
```

### Emitting signals

From Pascal:

```pascal
Button.EmitSignal('clicked');
Button.EmitSignal('clicked', [JSMakeNumber(42)]);
```

Signal names are normalised both ways: `clicked` and `onClicked` refer to the
same handler. Handler arguments are exposed as `arg0`, `arg1`, …; the first
argument is also bound as `mouse` for pointer-style signals.

A handler body is compiled to bytecode lazily on first dispatch and the chunk
is cached on the signal entry, so repeated clicks or property-change events do
not re-parse or re-walk the handler AST.

### Automatic signals

- Property changes emit `<propertyName>Changed` after the value actually
  changes, for example `widthChanged`.
- `LoadString` triggers completion handlers after bindings and anchors have
  been applied. The engine emits `FTML.onCompleted`, `Component.onCompleted`,
  and `completed`; markup handlers are normally written as
  `Component.onCompleted`, because the parser only treats names starting with
  `on` (or containing `.on`) as signals.
- `TFloriaFTMLButton.Click` emits `clicked`.

### Handler scope

A handler runs in a fresh child environment of the item scope with the item as
its delegate. It can read and assign item properties without qualification and
can call component functions or globals.

## Components and properties

The engine registers these built-in component types:

| Type | Extra properties (defaults) |
| :--- | :--- |
| `Item` | Base item. |
| `Rectangle` | `color` (`#ffffff`), `radius` (0), `borderWidth` (0), `borderColor` (`#000000`). |
| `Text` | `text` (`""`), `color` (`#000000`), `fontSize` (14), `fontFamily` (`sans-serif`), `alignment` (`left`). |
| `Button` | `text` (`""`), `pressed` (false), `hovered` (false). |
| `TextInput` | `text` (`""`), `placeholder` (`""`), `readOnly` (false). |
| `Column` | `spacing`/`gap` (0); simple vertical `Relayout`. |
| `Row` | `spacing`/`gap` (0); simple horizontal `Relayout`. |
| `FlexBox` | `direction` (`row`), `wrap` (`nowrap`), `justifyContent` (`flex-start`), `alignItems` (`stretch`), `gap`, `spacing`, `padding`. |
| `Grid` | `columns` (2), `rows` (0), `gap`, `spacing`, `columnGap`, `rowGap`, `columnsTemplate`, `rowsTemplate`. |

All items define:

| Property | Default | Notes |
| :--- | :--- | :--- |
| `x`, `y` | 0 | Position. |
| `width`, `height` | 0 (varies by type) | `Button` 120×38, `TextInput` 200×36, `Text` height 24. |
| `visible` | true | Hidden items are skipped by Column/Row layout. |
| `opacity` | 1 | Host-defined semantics. |
| `clip` | false | Host-defined semantics. |
| `enabled` | true | Host-defined semantics. |
| `flexGrow` | 0 | Flex child constraint. |
| `flexShrink` | 1 | Flex child constraint. |
| `flexBasis` | 0 | Flex child constraint. |
| `alignSelf` | `auto` | Flex child constraint. |
| `gridColumn`, `gridRow` | 0 | Grid child placement. |
| `colSpan`, `rowSpan` | 1 | Grid child span. |

`Layout.*` aliases are accepted for QML-style code:

| Alias | Maps to |
| :--- | :--- |
| `Layout.fillWidth`, `Layout.fillHeight` | `flexGrow` (0 or 1) |
| `Layout.preferredWidth`, `Layout.preferredHeight` | `width`, `height` |
| `Layout.column`, `Layout.row` | `gridColumn`, `gridRow` |
| `Layout.columnSpan`, `Layout.colSpan`, `Layout.rowSpan` | spans |
| `Layout.alignment` | `alignSelf` |

### Custom component types

Register a subclass of `TFloriaFTMLItem` under a type name:

```pascal
type
  TMyGauge = class(TFloriaFTMLItem)
  public
    constructor Create(const ATypeName: string = 'Gauge';
      AEngine: TObject = nil); override;
  end;

Engine.RegisterComponentType('Gauge', TMyGauge);
```

`LoadString` then instantiates `TMyGauge` for `Gauge { … }`. Instantiating an
unregistered type falls back to `TFloriaFTMLItem` (with the type name retained).

## Anchors

Anchors are properties named `anchors.*`:

```text
Rectangle {
  id: panel
  width: 400;
  height: 300;

  Text {
    anchors.fill: parent;
    anchors.margins: 12;
  }

  Rectangle {
    width: 80;
    height: 40;
    anchors.right: panel.right;
    anchors.top: panel.top;
    anchors.topMargin: 8;
    anchors.rightMargin: 8;
  }

  Rectangle {
    width: 120;
    height: 60;
    anchors.centerIn: parent;
  }
}
```

Supported anchor properties:

| Property | Effect |
| :--- | :--- |
| `anchors.fill` | Match the target's x/y/width/height. |
| `anchors.centerIn` | Center in the target. |
| `anchors.left`, `right`, `top`, `bottom` | Align one edge to the target edge. |
| `anchors.horizontalCenter`, `verticalCenter` | Center on one axis. |
| `anchors.margins` | All-edge margin for fill/edges. |
| `anchors.leftMargin`, `rightMargin`, `topMargin`, `bottomMargin` | Per-edge margins. |
| `anchors.horizontalCenterOffset`, `verticalCenterOffset` | Center offsets. |

Targets may be items (`parent`, an ID) or anchor lines read from an item:

- `item.left`, `item.right`, `item.top`, `item.bottom`
- `item.horizontalCenter`, `item.verticalCenter`, `item.baseline`

Anchor lines are live objects: when the source item's `x`, `y`, `width`, or
`height` changes, dependent anchors are resolved again.

## Layout helpers

- `Column.Relayout` stacks visible children vertically, sets their `y`, applies
  `spacing`/`gap`, and grows the column's `height`/`width` when they were zero.
- `Row.Relayout` does the same horizontally.
- `LoadString` runs relayout and anchor resolution after bindings, then again
  after anchor resolution.
- `FlexBox` and `Grid` expose the properties a host layout engine needs
  (`flexGrow`, `gridColumn`, spans, gaps, templates). The core runtime does not
  compute flex/grid positions; the host or a higher layer must do so.

## IDs and environments

- `id:` registers an item in the document root environment and in the global
  context environment. Scripts can therefore refer to an ID anywhere in the
  document (and from `Engine.Evaluate`).
- Each item gets a scoped environment whose parent is its parent item's
  environment; the root's parent is the document environment, whose parent is
  the context global environment.
- IDs are withdrawn on reload or destruction, but only if the global binding
  still points at that document's item.
- Nested items have their own environment, but can read ancestor properties
  through `parent` or by explicit IDs.

## Lifecycle

`TFloriaFTMLEngine` supports one document at a time:

```pascal
Root := Engine.LoadString(Source);
if Engine.HasErrors() then
  WriteLn(Engine.LastError);

Item := Engine.FindItemById('someId');
Engine.Evaluate('someId.width = 900;');   // runs in the document scope
```

- `LoadString` first releases the previous document, then parses, instantiates,
  compiles binding expressions, resolves layout/anchors, and triggers
  completion signals.
- On failure it returns `nil`, leaves `LastError` set, and leaves the engine in
  a consistent empty state.
- `LoadFile` reads a file (using `TStringList`) and forwards to `LoadString`.
- `FindItemById` searches the ID registry, then the tree.
- `Evaluate` parses, compiles, and executes a script in the document root
  environment. It does not perform `LoadString`-style error checking; use
  `HasErrors` after loading and keep scripts trusted.
- Object values returned by `Evaluate` are pinned; hand them back with
  `Engine.ReleaseValue` when done.
- If a runtime closure captures a document environment, the document's AST and
  objects are kept alive across reloads until that closure is unreachable.
  Without escaping closures, reload frees the previous document eagerly.

Destroying the engine releases the live document, then escaped documents, then
bindings, then (if it owns it) the JavaScript context.

## Host integration example

```pascal
var
  Engine: TFloriaFTMLEngine;
  Root, Card, Button: TFloriaFTMLItem;
begin
  Engine := TFloriaFTMLEngine.Create();
  try
    Root := Engine.LoadString(Source);
    if Root = nil then
      raise Exception.Create(Engine.LastError);

    Card := Engine.FindItemById('card');
    Button := Engine.FindItemById('expand');

    // A native host action
    Button.EmitSignal('clicked');

    // Direct property update
    Root.Width := 1000;

    // Read reactive results
    WriteLn(Card.Width);
    WriteLn(Card.GetPropertyAsString('text'));
  finally
    Engine.Free();
  end;
end;
```

Pass an existing `TFloriaJSContext` to `TFloriaFTMLEngine.Create` to share
globals with the rest of your application. Pass `nil` to let the engine create
and own a private context.

## Limitations

- No renderer, event loop, input handling, focus system, or accessibility
  layer. Those belong to the host adapter.
- No animation, transitions, states, or bindings other than property
  expressions.
- `FlexBox`/`Grid` are data models; only `Column`/`Row` include a simple layout
  pass.
- The markup parser accepts one root component per document.
- JavaScript limitations apply to expressions and handlers; see
  [language support](language-support.md).
- `Evaluate` on a document with syntax errors may execute a partial AST; check
  `HasErrors` after loading.
