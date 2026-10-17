# floriajs — Project Rules

## Build & Test Workflow

1. **Compile library**: `pasbuild compile` or `./build.sh compile`
2. **Run tests**: `pasbuild test` or `./build.sh test`
3. **Install to local Pasbuild cache**: `pasbuild install` or `./build.sh install`
4. **Clean artifacts**: `pasbuild clean` or `./build.sh clean`

## Dependencies

- **`florialib:0.0.1-SNAPSHOT`**: Floria core library (CSS, SVG, HTML, Image, Canvas, XCB, HarfBuzz, BiDi).
- **`fpgui-framework` is not used**. Do not add `fpgui-framework` as a dependency.

## Pasbuild Configuration File

- **`project.xml`** is the only project descriptor configuration file used by Pasbuild.
- **`pasbuild.json` does not exist**. Never look for, reference, create, or expect `pasbuild.json`.

## Tool Call Schema Invariants

- **`find_by_name` Requires `Pattern`**: In `find_by_name`, the `Pattern` property is strictly required by the tool validator schema (`required: ["SearchDirectory", "Pattern", "toolSummary", "toolAction"]`). Never omit `Pattern`, even when specifying `Extensions` or `Type`. When searching by extension or listing directory contents, always explicitly set `Pattern: "*"`.
- **Required Metadata**: Every tool call must include both `toolSummary` (2–5 word noun phrase) and `toolAction` (2–5 word verb phrase).

## GUI Test Execution & Process Lifecycles

- **Guaranteed Termination for Subprocesses**: Never issue a bare `wait $PID` when running interactive GUI programs, X11 apps, or modal dialogs in background subshells. Always ensure guaranteed termination:
  1. Follow interactions/screenshots immediately with `kill -9 $PID 2>/dev/null || true` before issuing `wait $PID 2>/dev/null || true`.
  2. Or wrap commands in `timeout <N>s`.
- **Process Pattern Matching (`pkill -f`)**: Standard `pkill <name>` limits process name matching to 15 characters, causing hard failures on longer binary or script names. Always use `pkill -f <pattern>` when terminating test scripts or binaries by name.

## Linux Windowing & Display Server Policy

- **Strictly X11/XCB Only (No Wayland)**:
  - All Linux windowing, event handling, clipboard management, and compositor integration strictly target native **X11/XCB** (`libxcb`, EWMH, ICCCM).
  - **Never reference, propose, design for, or insert Wayland** into code, configuration, architectural documentation, roadmaps, or README files.
  - Engineering focus is dedicated to premier native X11 desktop support, with optional non-Linux platform abstractions (WinAPI for Windows, Cocoa for macOS).

## Pascal Coding Conventions

### 1. Mandatory Empty Parameter Parentheses `()`
- **Declarations**: Any procedure, function, constructor, or destructor taking zero parameters **MUST** include empty parentheses `()`.
  ```pascal
  procedure Initialize(); virtual;
  procedure Reset(); virtual;
  destructor Destroy(); override;
  ```
- **Call Sites**: Any call to a zero-parameter procedure, function, or method **MUST** include empty parentheses `()`.
  ```pascal
  Engine.Initialize();
  Context.Reset();
  inherited Destroy();
  ```
- **Properties & Fields**: Property and field accesses do **not** use parentheses (`Engine.Initialized`, `Context.Name`).

### 2. Dotted Namespaces
All units follow dotted Pascal namespaces (e.g., `floria.js.types`, `floria.js.core`, `floriajs`).

### 3. Identifier Casing & Prefixes
- **Variables**: PascalCase (no prefix)
- **Private Fields**: Prefix with `F` (`FEngine`, `FContexts`)
- **Types / Classes**: Prefix with `T` (`TFloriaJSEngine`, `TFloriaJSContext`)
- **Interfaces**: Prefix with `I` (`IExportable`)
- **Method Parameters**: Prefix with `A` (`const AScript: string`)
- **Constants**: `ALL_CAPS_WITH_UNDERSCORES` (`FLORIA_JS_OK`, `MAX_BUFFER_SIZE`)
