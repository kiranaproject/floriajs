# Language Pipeline API

`TFloriaJSContext` is the recommended entry point. Use the lower-level units
when you need to inspect tokens or the AST, compile a script once and run it
many times, embed the VM in an existing heap, or drive FTML parsing directly.

The pipeline is:

```text
source → lexer → parser → AST → compiler → bytecode → VM
```

## End-to-end example

```pascal
program run_script;

{$mode objfpc}{$H+}

uses
  SysUtils, floria.js.lexer, floria.js.parser, floria.js.ast,
  floria.js.value, floria.js.env, floria.js.stdlib,
  floria.js.bytecode, floria.js.compiler, floria.js.vm;

var
  Heap: TFloriaJSHeap;
  Env: TFloriaJSEnvironment;
  Compiler: TFloriaJSCompiler;
  VM: TFloriaJSVM;
  Parser: TFloriaJSParser;
  Prog: TFloriaJSProgram;
  Code: TFloriaJSBytecode;
  Value: TFloriaJSValue;
begin
  Heap := TFloriaJSHeap.Create();
  try
    { The heap owns tracked environments and frees them on Clear/destruction. }
    Env := TFloriaJSEnvironment(Heap.TrackEnvironment(
      TFloriaJSEnvironment.Create(nil)));
    FloriaJSRegisterStdLib(Env, Heap, nil);

    Compiler := TFloriaJSCompiler.Create();
    VM := TFloriaJSVM.Create(Heap, Env);
    try
      Parser := TFloriaJSParser.Create('let x = 21; x * 2;');
      try
        Prog := Parser.ParseProgram();
        try
          if Parser.HasErrors() then
            raise Exception.Create(Parser.GetError(0));

          Code := Compiler.CompileProgram(Prog);
          try
            Value := VM.Execute(Code, Env);
            WriteLn(Value.ToString());   // 42
          finally
            Code.Release();
          end;
        finally
          Prog.Free();
        end;
      finally
        Parser.Free();
      end;
    finally
      VM.Free();
      Compiler.Free();
    end;
  finally
    Heap.Free();   { also frees Env; do not free Env separately }
  end;
end.
```

If you create `TFloriaJSVM.Create(nil)`, it creates and owns its own heap
(available as `VM.Heap`). In that case create/register the environment against
that heap.

## Lexer — `floria.js.lexer`

```pascal
constructor Create(const ASource: string);
destructor Destroy(); override;

function NextToken(): TFloriaJSToken;
function PeekToken(): TFloriaJSToken;
function IsAtEnd(): Boolean;
procedure Reset();

class function TokenKindToString(AKind: TFloriaJSTokenKind): string;
```

```pascal
TFloriaJSToken = record
  Kind: TFloriaJSTokenKind;
  Text: string;
  NumberValue: Double;
  Line: Integer;
  Column: Integer;
  StartPos: Integer;
  EndPos: Integer;
end;
```

- `NextToken` skips whitespace and comments and returns the next significant
  token. At the end it returns `tkEOF`.
- `PeekToken` returns the next token without consuming it.
- `Reset` rewinds to the beginning of the source.
- `TokenKindToString` is useful for diagnostics and tests.
- Regex literals are scanned as `tkRegExp`; the token text encodes the pattern
  and flags for the parser.

```pascal
Lexer := TFloriaJSLexer.Create('let total = 1_000;');
try
  repeat
    Tok := Lexer.NextToken();
    WriteLn(TFloriaJSLexer.TokenKindToString(Tok.Kind), ' ', Tok.Text);
  until Tok.Kind = tkEOF;
finally
  Lexer.Free();
end;
```

## Parser — `floria.js.parser`

```pascal
constructor Create(const ASource: string);
constructor Create(ALexer: TFloriaJSLexer);
destructor Destroy(); override;

function ParseProgram(): TFloriaJSProgram;
function ParseExpression(): TFloriaJSExprNode;
function ParseFTMLComponent(): TFloriaFTMLComponent;

function HasErrors(): Boolean;
function GetErrorCount(): Integer;
function GetError(AIndex: Integer): string;

property Errors: TStringList read FErrors;
```

- The `ASource` constructor creates and owns a lexer. The `ALexer` constructor
  borrows it; the caller keeps ownership.
- `ParseProgram` parses statements until `tkEOF`.
- `ParseExpression` parses a single expression.
- `ParseFTMLComponent` parses one FTML component and its children.
- Errors are collected, not thrown. Always check `HasErrors` before compiling
  a result. A partial tree may still be returned.
- Precedence constants are public (`PREC_COMMA`, `PREC_ASSIGNMENT`, …,
  `PREC_CALL`) if you build custom expression parsers.

## AST — `floria.js.ast`

All nodes derive from `TFloriaJSASTNode` and expose `Line` and `Column`.

### Expressions

| Class | Represents | Key properties |
| :--- | :--- | :--- |
| `TFloriaJSLiteralExpr` | number/string/boolean/null/undefined/regex | value fields |
| `TFloriaJSIdentifierExpr` | name reference | `Name` |
| `TFloriaJSUnaryExpr` | prefix/postfix unary | `Op`, `Operand`, `IsPrefix` |
| `TFloriaJSBinaryExpr` | binary operator (including comma) | `Left`, `Op`, `Right` |
| `TFloriaJSConditionalExpr` | `?:` | `Condition`, `Consequent`, `Alternate` |
| `TFloriaJSAssignExpr` | assignment/compound assignment | `Target`, `Op`, `Value` |
| `TFloriaJSMemberExpr` | `.`/`[]`/`?.` | `Target`, `PropertyName`, `PropertyExpr`, `Computed`, `IsOptional` |
| `TFloriaJSCallExpr` | call, optional call, or `new` call | `Callee`, `Arguments`, `IsNew`, `IsOptional` |
| `TFloriaJSArrayExpr` | array literal (including holes/spread) | `Elements` |
| `TFloriaJSSpreadExpr` | spread element | `Expression`, `ExtractExpression` |
| `TFloriaJSObjectExpr` | object literal | property key/value/kind accessors |
| `TFloriaJSFunctionExpr` | function/arrow expression | `Name`, `Parameters`, `Body`, `IsArrow`, `IsAsync` |

Object literal entries carry a `TFloriaJSPropertyKind`:
`fjpkNormal`, `fjpkComputed`, `fjpkSpread`, `fjpkGetter`, `fjpkSetter`.

### Statements

| Class | Represents | Key properties |
| :--- | :--- | :--- |
| `TFloriaJSExprStmt` | expression statement | `Expression` |
| `TFloriaJSVarStmt` | `var`/`let`/`const` | `Kind`, declarator name/pattern/init |
| `TFloriaJSBlockStmt` | block | `Statements` |
| `TFloriaJSIfStmt` | `if` | `Condition`, `Consequent`, `Alternate` |
| `TFloriaJSReturnStmt` | `return` | `Argument` |
| `TFloriaJSWhileStmt` | `while`/`do…while` | `Condition`, `Body`, `IsDoWhile` |
| `TFloriaJSForStmt` | classic `for` | `Init`, `Test`, `Update`, `Body`, `LabelName` |
| `TFloriaJSForInOfStmt` | `for…in` / `for…of` | `VarKind`, `VarName`, `IsOf`, `Iterable`, `Body`, `LabelName` |
| `TFloriaJSSwitchStmt` | `switch` | `Discriminant`, `Cases` |
| `TFloriaJSTryStmt` | `try`/`catch`/`finally` | `Block`, `CatchParam`, `CatchBlock`, `FinallyBlock` |
| `TFloriaJSThrowStmt` | `throw` | `Expression` |
| `TFloriaJSBreakStmt` | `break` | `LabelName` |
| `TFloriaJSContinueStmt` | `continue` | `LabelName` |
| `TFloriaJSLabeledStmt` | `label:` | `LabelName`, `Body` |
| `TFloriaJSFunctionDecl` | function declaration | `Name`, `Parameters`, `Body`, `IsAsync` |
| `TFloriaJSProgram` | program root | `Statements` |
| `TFloriaFTMLComponent` | FTML component | `ComponentType`, `Id`, properties, signals, functions, children |

### Ownership

- A node owns its children and frees them in its destructor.
- Function bodies are shared with bytecode-created closures; AST owners use
  `Release`, and functions retain them.
- `Accept(AVisitor)` dispatches to `IFloriaJSASTVisitor` for tooling.

## Compiler — `floria.js.compiler`

```pascal
constructor Create();
destructor Destroy(); override;

function CompileProgram(AProgram: TFloriaJSProgram): TFloriaJSBytecode;
function CompileExpression(AExpr: TFloriaJSExprNode): TFloriaJSBytecode;
function CompileFunctionBody(const AName: string; AParams: TStringList;
  ABody: TFloriaJSStmtNode; AIsAsync: Boolean = False;
  AIsArrow: Boolean = False): TFloriaJSBytecode;
```

- `CompileProgram` returns a chunk with top-level code and hidden `$result`
  local for completion values.
- `CompileExpression` returns a chunk that evaluates one expression. FTML
  bindings use this during creation.
- `CompileFunctionBody` compiles a function body into a reusable prototype
  chunk. The VM uses it for lazy compilation of AST-backed user functions and
  signal handlers.
- The returned chunk has reference count 1. Call `Release` when you are done
  unless you hand it to a function/binding that retains it.

## Bytecode — `floria.js.bytecode`

```pascal
constructor Create(const AName: string = '');
destructor Destroy(); override;

procedure Retain();
procedure Release();

function  Emit(AOp: TFloriaJSOpcode; AImm: Int32 = 0; ALine: Int32 = 0): Integer;
procedure PatchJump(AIndex: Integer; ATarget: Integer);
function  CurrentIP(): Integer;

function  AddConstant(const AValue: TFloriaJSValue): Integer;
function  AddStringConstant(const AStr: string): Integer;
function  AddNumberConstant(ANum: Double): Integer;
function  GetConstant(AIndex: Integer): TFloriaJSValue;

function  AddLocal(const AName: string): Integer;
function  FindLocal(const AName: string): Integer;
function  AddArgument(const AName: string): Integer;
function  AddSubFunction(AFunc: TFloriaJSBytecode): Integer;
function  GetSubFunction(AIndex: Integer): TFloriaJSBytecode;

function  Disassemble(): string;
```

```pascal
TFloriaJSInstruction = packed record
  Op: TFloriaJSOpcode;
  Imm: Int32;
  Line: Int32;
end;
```

See [Bytecode VM](../bytecode-vm.md) for the instruction set and execution
model.

## VM — `floria.js.vm`

```pascal
constructor Create(AHeap: TFloriaJSHeap = nil;
  AGlobalEnv: TFloriaJSEnvironment = nil);
destructor Destroy(); override;

function Execute(ABytecode: TFloriaJSBytecode;
  AEnv: TFloriaJSEnvironment = nil): TFloriaJSValue;
function Execute(ABytecode: TFloriaJSBytecode;
  AEnv: TFloriaJSEnvironment; const AThis: TFloriaJSValue): TFloriaJSValue;
function CallFunction(const AFuncVal: TFloriaJSValue;
  const AArgs: array of TFloriaJSValue): TFloriaJSValue;
function CallFunction(const AFuncVal: TFloriaJSValue;
  const AArgs: array of TFloriaJSValue;
  const AThisVal: TFloriaJSValue): TFloriaJSValue;
function ConstructObject(const AFuncVal: TFloriaJSValue;
  const AArgs: array of TFloriaJSValue): TFloriaJSValue;

procedure Push(const AVal: TFloriaJSValue);
function  Pop(): TFloriaJSValue;
function  Peek(ADepth: Integer = 0): TFloriaJSValue;
function  GetStackDepth(): Integer;
procedure ResetStack();

property Heap: TFloriaJSHeap read FHeap;
property GlobalEnv: TFloriaJSEnvironment read FGlobalEnv write FGlobalEnv;
property MaxCallDepth: Integer read FMaxCallDepth write FMaxCallDepth;
```

- `Create(nil)` creates and owns a heap; `Create(AHeap, AEnv)` borrows both.
  When you create a VM without an environment, set `GlobalEnv` or pass an
  environment to `Execute`.
- `Execute` reserves local slots, pushes a call frame, runs the chunk, then
  unwinds frames and stack entries it created.
- `CallFunction` accepts native functions, bytecode functions, and AST-backed
  user functions (which are compiled lazily).
- `ConstructObject` implements `new`.
- `MaxCallDepth` defaults to 512.
- The VM wires itself as the heap's function invoker, so array/string methods
  can call JavaScript callbacks without depending on the VM unit.
- The VM is not re-entrant across threads; use one VM per context/thread.

## Standard-library registration

```pascal
procedure FloriaJSRegisterStdLib(AEnv: TFloriaJSEnvironment;
  AHeap: TFloriaJSHeap; ALogOutput: TStrings = nil);

procedure FloriaJSRegisterArray(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
procedure FloriaJSRegisterString(AHeap: TFloriaJSHeap);
procedure FloriaJSRegisterObjects(AEnv: TFloriaJSEnvironment;
  AHeap: TFloriaJSHeap; AObjectCtor: TFloriaJSNativeMethod);
procedure FloriaJSRegisterJSON(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
procedure FloriaJSRegisterCollections(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
procedure FloriaJSRegisterDate(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
procedure FloriaJSRegisterSymbol(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
procedure FloriaJSRegisterRegExp(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
procedure FloriaJSRegisterURI(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
procedure FloriaJSRegisterTimers(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);

procedure FloriaJSProcessTimers(AHeap: TFloriaJSHeap);
```

- `FloriaJSRegisterStdLib` is the complete installation used by
  `TFloriaJSContext`. It calls the specific registrars and adds `console`,
  `Math`, `Number`, `String`, `Boolean`, errors, `Promise`, and `globalThis`.
- The specific registrars are exposed for hosts that want a reduced global
  environment. Do not combine them with `FloriaJSRegisterStdLib` for the same
  environment.
- `ALogOutput` is the list that receives `console` output. Passing `nil` makes
  `console` write to standard output/error. The sink is process-wide.
- `FloriaJSRegisterString` installs methods on the shared string prototype.
- Timers are queued process-wide. The host event loop must call
  `FloriaJSProcessTimers` periodically for delayed/repeating callbacks to run.

## Engine integration

`TFloriaJSContext` exposes `VM` and `Compiler` and uses them for `Evaluate`,
`EvaluateValue`, and FTML. `TFloriaJSExecutionBackend` still contains
`fjbInterpreter` for source compatibility, but the tree-walking evaluator is
gone; both enum values currently execute bytecode. Use `EvaluateBytecode` (or
`TFloriaJSEngine.ExecuteBytecode`) when you want to make the VM choice explicit.
