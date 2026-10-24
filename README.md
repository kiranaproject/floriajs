# floriajs — Floria JavaScript Runtime & Interop Engine

**floriajs** provides a modern, Object Pascal JavaScript engine and execution runtime designed for the **Floria Toolkit** ecosystem.

---

## Documentation

Full documentation lives in [`docs/`](docs/README.md):

- [Getting started](docs/getting-started.md) — build, embed, and call between Pascal and JavaScript.
- [Language support](docs/language-support.md) — implemented syntax, built-ins, and semantic differences.
- [Architecture](docs/architecture.md) — lexer, parser, AST, evaluator, values, and memory model.
- [FTML guide](docs/ftml.md) — declarative component markup, reactive bindings, anchors, and signals.
- [API reference](docs/README.md#api-reference) — engine, values, pipeline, and FTML APIs.
- [Development guide](docs/development.md) — tests, gap scan, conventions, and adding features.
- [Roadmap](docs/roadmap.md) — prioritised missing features.

---

## Architecture & Unit Hierarchy

`floriajs` follows a clean, dotted-namespace unit structure. You can import individual modules or simply use `uses floriajs;` for single-unit convenience:

| Unit | Purpose | Key Classes & Types |
| :--- | :--- | :--- |
| **`floria.js.types`** | Fundamental types, result codes, and value tags | `TFloriaJSType`, `TFloriaJSResult`, `FLORIA_JS_OK` |
| **`floria.js.lexer`** | JavaScript tokenizer | `TFloriaJSLexer`, `TFloriaJSToken` |
| **`floria.js.ast`** | Expression, statement, and FTML AST nodes | `TFloriaJSExprNode`, `TFloriaJSStmtNode` |
| **`floria.js.parser`** | Pratt expression parser and statement/FTML parser | `TFloriaJSParser` |
| **`floria.js.value`** | Values, objects, arrays, functions, errors, promises, heap | `TFloriaJSValue`, `TFloriaJSHeap` |
| **`floria.js.env`** | Lexical scopes and bindings | `TFloriaJSEnvironment` |
| **`floria.js.evaluator`** | Tree-walking interpreter | `TFloriaJSEvaluator` |
| **`floria.js.arrays` / `.strings` / `.objects` / `.json`** | Built-in prototype and static methods | Array/String/Object/JSON support |
| **`floria.js.stdlib`** | Global library registration | `console`, `Math`, `Promise`, globals |
| **`floria.js.core`** | Runtime execution engine and context management | `TFloriaJSEngine`, `TFloriaJSContext` |
| **`floria.ftml.*`** | Declarative UI runtime | `TFloriaFTMLEngine`, `TFloriaFTMLItem` |
| **`floriajs`** | Umbrella unit re-exporting the public API | Single-unit inclusion (`uses floriajs;`) |

See [Architecture](docs/architecture.md) for the execution pipeline and the memory model.

## Quickstart

```pascal
program hello_floriajs;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, floriajs;

var
  engine: TFloriaJSEngine;
  ctx: TFloriaJSContext;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    ctx := engine.DefaultContext;
    ctx.SetVariable('version', FLORIA_JS_VERSION_STRING);

    res := ctx.Evaluate('console.log("Hello from FloriaJS!");');
    if res.Success then
      WriteLn('Execution succeeded: ', res.StringValue)
    else
      WriteLn('Execution failed: ', res.ErrorMessage);
  finally
    engine.Free();
  end;
end.
```

---

## Building & Testing

`floriajs` is built with **[PasBuild](https://github.com/graemeg/pasbuild)** using `project.xml`.

### 1. Compile Library
```bash
pasbuild compile
# or
./build.sh compile
```

### 2. Run Test Suite
```bash
pasbuild test
# or
./build.sh test
```

### 3. Install to Local PasBuild Repository
```bash
pasbuild install
# or
./build.sh install
```

### 4. Clean Build Artifacts
```bash
pasbuild clean
# or
./build.sh clean
```

---

## Coding Conventions & Guidelines

All development in `floriajs` strictly follows the Floria coding guidelines:
- **`project.xml` is the only project descriptor**: `pasbuild.json` does not exist.
- **Mandatory empty parentheses `()`**: Every procedure, function, constructor, destructor, and call site with zero parameters must include `()`.
- **Dotted namespaces**: All units use dotted Pascal naming (`floria.js.*`).
- **Identifier casing**: Types prefixed with `T`, private fields with `F`, arguments with `A`, constants in `ALL_CAPS_WITH_UNDERSCORES`.
- **Display Server**: Strictly native X11/XCB desktop integration (No Wayland).

See [GEMINI.md](GEMINI.md) and [.agents/rules/floria_development.md](.agents/rules/floria_development.md) for full project rules.
