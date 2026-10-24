# Language Pipeline API

`TFloriaJSContext` is the recommended entry point. Use the lower-level units
when you need to inspect tokens or the AST, cache a parsed program, embed the
evaluator in an existing heap, or run FTML parsing without the FTML engine.

## End-to-end example

```pascal
program run_script;

{$mode objfpc}{$H+}

uses
  SysUtils, floria.js.lexer, floria.js.parser, floria.js.ast,
  floria.js.value, floria.js.env, floria.js.evaluator, floria.js.stdlib;

var
  Heap: TFloriaJSHeap;
  Env: TFloriaJSEnvironment;
  Evaluator: TFloriaJSEvaluator;
  Parser: TFloriaJSParser;
  Prog: TFloriaJSProgram;
  Value: TFloriaJSValue;
begin
  Heap := TFloriaJSHeap.Create();
  try
    { The heap owns tracked environments and frees them on Clear/destruction. }
    Env := TFloriaJSEnvironment(Heap.TrackEnvironment(
      TFloriaJSEnvironment.Create(nil)));
    FloriaJSRegisterStdLib(Env, Heap, nil);

    Evaluator := TFloriaJSEvaluator.Create(Heap);
    try
      Parser := TFloriaJSParser.Create('let x = 21; x * 2;');
      try
        Prog := Parser.ParseProgram();
        try
          if Parser.HasErrors() then
            raise Exception.Create(Parser.GetError(0));
          Value := Evaluator.ExecuteProgram(Prog, Env);
          WriteLn(Value.ToString());   // 42
        finally
          Prog.Free();
        end;
      finally
        Parser.Free();
      end;
    finally
      Evaluator.Free();
    end;
  finally
    Heap.Free();   { also frees Env; do not free Env separately }
  end;
end.
```

If you create the evaluator with `TFloriaJSEvaluator.Create(nil)`, it creates
and owns its own heap (available as `Evaluator.Heap`). In that case create the
environment against that heap.

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

Token kinds cover literals, keywords, delimiters, operators, and `tkError`.
The parser records `tkError` tokens as errors and continues with the next
token.

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
- `ParseExpression` parses a single expression (useful for binding
  expressions).
- `ParseFTMLComponent` parses one FTML component and its children.
- Errors are collected, not thrown. Always check `HasErrors` before using the
  result for anything important. A partial tree may still be returned.
- Precedence constants are public (`PREC_COMMA`, `PREC_ASSIGNMENT`, …,
  `PREC_CALL`) if you build custom expression parsers.

```pascal
Parser := TFloriaJSParser.Create('let value = (1, 2); value;');
try
  Prog := Parser.ParseProgram();
  if Parser.HasErrors() then
    WriteLn('Error: ', Parser.GetError(0));
finally
  Parser.Free();
end;
```

## AST — `floria.js.ast`

All nodes derive from `TFloriaJSASTNode` and expose `Line` and `Column`.

### Expressions

| Class | Represents | Key properties |
| :--- | :--- | :--- |
| `TFloriaJSLiteralExpr` | number/string/boolean/null/undefined | `ValueType`, `NumberVal`, `StringVal`, `BoolVal` |
| `TFloriaJSIdentifierExpr` | name reference | `Name` |
| `TFloriaJSUnaryExpr` | prefix/postfix unary | `Op`, `Operand`, `IsPrefix` |
| `TFloriaJSBinaryExpr` | binary operator (including comma) | `Left`, `Op`, `Right` |
| `TFloriaJSConditionalExpr` | `?:` | `Condition`, `Consequent`, `Alternate` |
| `TFloriaJSAssignExpr` | assignment/compound assignment | `Target`, `Op`, `Value` |
| `TFloriaJSMemberExpr` | `.`/`[]`/`?.` | `Target`, `PropertyName`, `PropertyExpr`, `Computed`, `IsOptional` |
| `TFloriaJSCallExpr` | call, optional call, or `new` call | `Callee`, `Arguments`, `IsNew`, `IsOptional` |
| `TFloriaJSArrayExpr` | array literal (including holes/spread) | `Elements`, `GetElement`, `GetElementCount` |
| `TFloriaJSSpreadExpr` | spread element | `Expression`, `ExtractExpression` |
| `TFloriaJSObjectExpr` | object literal | property count/key/value/kind accessors |
| `TFloriaJSFunctionExpr` | function/arrow expression | `Name`, `Parameters`, `Body`, `IsArrow`, `IsAsync` |

Object literal entries carry a `TFloriaJSPropertyKind`:
`fjpkNormal`, `fjpkComputed`, `fjpkSpread`, `fjpkGetter`, `fjpkSetter`.

### Statements

| Class | Represents | Key properties |
| :--- | :--- | :--- |
| `TFloriaJSExprStmt` | expression statement | `Expression` |
| `TFloriaJSVarStmt` | `var`/`let`/`const` | `Kind`, `GetDeclaratorName/Pattern/Init` |
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

### Ownership and visitors

- A node owns its children and frees them in its destructor.
- Function bodies are reference-counted because closures share them:
  `Retain` / `Release`. Script owners `Release`; function objects `Retain`.
- `Accept(AVisitor)` dispatches to `IFloriaJSASTVisitor`. Implementing the full
  interface lets you traverse or transform a tree. The interpreter does not use
  the visitor; it dispatches with `is` checks.

## Evaluator — `floria.js.evaluator`

```pascal
constructor Create(AHeap: TFloriaJSHeap = nil);
destructor Destroy(); override;

function EvaluateExpr(AExpr: TFloriaJSExprNode;
  AEnv: TFloriaJSEnvironment): TFloriaJSValue;
function ExecuteStmt(AStmt: TFloriaJSStmtNode;
  AEnv: TFloriaJSEnvironment): TFloriaJSValue;
function ExecuteProgram(AProg: TFloriaJSProgram;
  AEnv: TFloriaJSEnvironment): TFloriaJSValue;

function CallFunction(const AFuncVal: TFloriaJSValue;
  const AArgs: array of TFloriaJSValue;
  const AThis: TFloriaJSValue): TFloriaJSValue;

procedure DrainMicrotasks();

procedure RetainEnv(AEnv: TFloriaJSEnvironment);
procedure OrphanEnv(AEnv: TFloriaJSEnvironment);
function GetClosureCount(): Integer;

property Heap: TFloriaJSHeap read FHeap;
property MaxCallDepth: Integer read FMaxCallDepth write FMaxCallDepth;
```

- `Create(nil)` creates and owns a heap; `Create(APHeap)` borrows it.
- The evaluator wires itself as the heap's function invoker and promise job
  runner, so built-ins can call back into JavaScript and deferred reactions
  can run.
- `ExecuteProgram` is a safe point: it reclaims orphaned environments, runs
  `Heap.Collect`, executes the statements, then drains pending promise jobs
  until the queue is empty.
- `MaxCallDepth` defaults to 1024. Exceeding it raises a runtime error.
- Control-flow exceptions (`EFloriaJSReturn`, `EFloriaJSBreak`,
  `EFloriaJSContinue`) are part of the evaluator API. `EFloriaJSThrow` carries
  a JavaScript value.
- `RetainEnv` / `OrphanEnv` are used by the runtime when scopes are captured by
  closures. Host code should not need them unless it implements its own
  statement execution.

## Standard-library registration

```pascal
procedure FloriaJSRegisterStdLib(AEnv: TFloriaJSEnvironment;
  AHeap: TFloriaJSHeap; ALogOutput: TStrings = nil);

procedure FloriaJSRegisterArray(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
procedure FloriaJSRegisterString(AHeap: TFloriaJSHeap);
procedure FloriaJSRegisterObjects(AEnv: TFloriaJSEnvironment;
  AHeap: TFloriaJSHeap; AObjectCtor: TFloriaJSNativeMethod);
procedure FloriaJSRegisterJSON(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
```

- `FloriaJSRegisterStdLib` is the complete installation used by
  `TFloriaJSContext`. It calls the four specific registrars and adds
  `console`, `Math`, `Number`, `String`, `Boolean`, errors, `Promise`, and
  `globalThis`.
- The specific registrars are exposed for hosts that want a reduced global
  environment. Do not call them and then call `FloriaJSRegisterStdLib` as well;
  registration is not guarded against duplicate installation.
- `ALogOutput` is the list that receives `console` output. Passing `nil` makes
  `console` write to standard output/error. The sink is process-wide.
- `FloriaJSRegisterString` takes only the heap because string methods are
  installed on the shared string prototype, not on the global environment.
- `FloriaJSRegisterObjects` defines the `Object` global and installs
  `hasOwnProperty`, `toString`, and the static helpers on
  `Object.prototype`/`Object`.

## Custom globals without the context

```pascal
Heap := TFloriaJSHeap.Create();
Env := TFloriaJSEnvironment(Heap.TrackEnvironment(TFloriaJSEnvironment.Create(nil)));
FloriaJSRegisterStdLib(Env, Heap, MyLogList);

Env.Define('hostLimit', JSMakeNumber(10));

// Add a property to an object the host owns
Cfg := Heap.NewObject();
Cfg.SetProperty('name', JSMakeString('demo'));
Env.Define('config', JSMakeObject(Cfg));
```

Remember that the environment binding retains the value, so `Cfg` stays alive
even if the host drops its pointer. If the host keeps the pointer, pin the
object or keep the environment/binding alive.
