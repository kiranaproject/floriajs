---
name: floriajs-builder
description: Compiles, tests, and verifies Floria JS (floriajs) library using Pasbuild with Free Pascal.
version: 1.0.0
triggers:
  - build floriajs
  - compile floriajs
  - test floriajs
---

# Floria JS (floriajs) Build & Test Skill

Orchestrates the build pipeline for Floria JS (`floriajs`) using Pasbuild and FPC dotted unit names, runs automated test suites, and verifies JavaScript engine integrations.

## Prerequisites
- Free Pascal Compiler (`fpc` >= 3.2.0)
- Pasbuild (`pasbuild` >= 1.9.0)
- Standard build tools (`bash`, `make`, `gcc`)

## Build & Test Workflow

1. **Compile**:
   ```bash
   pasbuild compile
   # or
   ./build.sh compile
   ```
2. **Run Tests**:
   ```bash
   pasbuild test
   # or
   ./build.sh test
   ```
3. **Install to Local PasBuild Repository**:
   ```bash
   pasbuild install
   # or
   ./build.sh install
   ```
4. **Clean Artifacts**:
   ```bash
   pasbuild clean
   # or
   ./build.sh clean
   ```

## Key Invariants
- **`project.xml` is the only project descriptor**: Never create or reference `pasbuild.json`.
- **Mandatory empty parentheses `()`**: Every parameterless procedure, function, constructor, destructor, and call site must have `()`.
- **Dotted namespaces**: All units must follow dotted hierarchy (`floria.js.types`, `floria.js.core`, `floriajs`).
- **Dependencies**: `florialib:0.0.1-SNAPSHOT` is the core dependency; `fpgui-framework` is not used.
- **Strictly native X11/XCB**: Never introduce Wayland dependencies or documentation.
