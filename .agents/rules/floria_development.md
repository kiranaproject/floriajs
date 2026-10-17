# Floria JS (floriajs) Development Guidelines

When developing or creating modules, bindings, and extensions for Floria JS (`floriajs`):

## 1. Object Pascal System Rules & Coding Style

### Mandatory Empty Parameter Parentheses `()`
To clearly distinguish methods, procedures, and functions from variables, properties, or constants:
- **Declarations**: Any procedure, function, constructor, or destructor taking zero parameters **MUST** include empty parentheses `()`.
  ```pascal
  // Correct
  procedure Initialize(); virtual;
  procedure Reset(); virtual;
  procedure Clear();
  function  GetContext(): TFloriaJSContext; virtual;
  destructor Destroy(); override;

  // Incorrect (DO NOT USE)
  procedure Initialize; virtual;
  procedure Reset; virtual;
  function  GetContext: TFloriaJSContext;
  destructor Destroy; override;
  ```
- **Call Sites**: Any call to a zero-parameter procedure, function, or method **MUST** include empty parentheses `()`.
  ```pascal
  // Correct
  Engine.Initialize();
  Context.Reset();
  inherited Destroy();

  // Incorrect (DO NOT USE)
  Engine.Initialize;
  Context.Reset;
  inherited Destroy;
  ```
- **Properties & Variables**: Properties and variables do **not** use parentheses (`Engine.Initialized`, `Context.Name`).

### Dotted Namespaces
All units in Floria JS follow dotted Pascal namespaces (e.g., `floria.js.types`, `floria.js.core`, `floriajs`).

### Identifier Casing & Naming Conventions
| Identifier Type | Case Style | Prefix / Rule | Example |
| :--- | :--- | :--- | :--- |
| **Variables (Local)** | PascalCase | No prefix | `ScriptCount`, `ResultValue` |
| **Variables (Private Fields)** | PascalCase | Prefix with `F` (Field) | `FEngine`, `FContexts` |
| **Constants** | **ALL_CAPS** | **Separated by underscores** | `FLORIA_JS_OK`, `MAX_HEAP_SIZE` |
| **Types (Classes/Records)** | PascalCase | Prefix with `T` (Type) | `TFloriaJSEngine`, `TFloriaJSResult` |
| **Interfaces** | PascalCase | Prefix with `I` (Interface) | `IExportable`, `IEventListener` |
| **Properties** | PascalCase | No prefix; maps to an `F` field | `property Initialized: Boolean read FInitialized;` |
| **Method Parameters** | PascalCase | Frequently prefixed with `A` (Argument) | `procedure SetVariable(const AKey, AValue: string);` |

---

## 2. Build, Dependency & Packaging Workflows
- **PasBuild Descriptor Invariant (`project.xml`)**: In PasBuild, the project configuration and dependency descriptor is strictly `project.xml`. There is no `pasbuild.json` or YAML file. Never search for, reference, or attempt to generate `pasbuild.json`. All project metadata, build settings, source paths, and package dependencies must be inspected and edited in `project.xml`.
- **Installing FloriaLib Modifications**: `florialib` is consumed via PasBuild package management (`project.xml`). Whenever modifying code inside `florialib`, **always immediately run `pasbuild install` inside the `florialib` directory** before compiling or testing downstream projects (`floriajs`).

---

## 3. Tool Call Schema Invariants
- **`find_by_name` Mandatory `Pattern`**: Always supply `Pattern: "*"` when calling `find_by_name` with `Extensions` or `Type`. The tool schema strictly enforces `Pattern` as a required parameter (`required: ["SearchDirectory", "Pattern", "toolSummary", "toolAction"]`), regardless of documentation text.
- **Required Metadata**: Every tool call must include both `toolSummary` (2–5 word noun phrase) and `toolAction` (2–5 word verb phrase).

---

## 4. Automated GUI Testing & Process Lifecycles
- **No Unbounded Process Waiting**: GUI test scripts that launch Floria applications (`XCB`/`X11` windows, interactive runners) must never block indefinitely on `wait $PID`. Always ensure guaranteed termination:
  ```bash
  ./my_gui_test &
  PID=$!
  sleep 1.0
  kill -9 $PID 2>/dev/null || true
  wait $PID 2>/dev/null || true
  ```
- **Pattern Matching with `pkill -f`**: When cleaning up background test processes by command name, always specify `pkill -f` because standard Linux process name matching truncates at 15 characters.

---

## 5. Linux Windowing & Display Server Policy
- **Strictly Native X11/XCB Only (No Wayland)**:
  - All Linux windowing, event handling, clipboard management, and compositor integration strictly target native **X11/XCB** (`libxcb`, EWMH, ICCCM).
  - **Never reference, propose, design for, or insert Wayland** into code, configuration, architectural documentation, roadmaps, or README files.
  - Engineering focus is dedicated to premier native X11 desktop support, with optional non-Linux platform abstractions (WinAPI for Windows, Cocoa for macOS).

---

## 6. Desktop-First Priority & Rock-Solid ABI Stability
- **Desktop-First Ergonomics**: Prioritize desktop layouts, precise mouse interactions, keyboard navigation, and fast execution loops.
- **The Windows API Standard of Stability**: Evolution must be strictly additive (new APIs/functions added, never altered or removed).
