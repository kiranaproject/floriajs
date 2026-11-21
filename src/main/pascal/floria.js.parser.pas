{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Pratt Precedence & Recursive Descent Parser     }
{                                                                          }
{   Parses token streams into an Abstract Syntax Tree (AST) for JavaScript }
{   and declarative FTML component expressions.                            }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.parser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, floria.js.types, floria.js.lexer, floria.js.ast;

const
  { Operator Precedence Levels }
  PREC_NONE           = 0;
  PREC_COMMA          = 1;  { , }
  PREC_ASSIGNMENT     = 2;  { = += -= *= /= %= **= ??= }
  PREC_CONDITIONAL    = 3;  { ? : }
  PREC_NULLISH        = 4;  { ?? }
  PREC_LOGICAL_OR     = 5;  { || }
  PREC_LOGICAL_AND    = 6;  { && }
  PREC_BIT_OR         = 7;  { | }
  PREC_BIT_XOR        = 8;  { ^ }
  PREC_BIT_AND        = 9;  { & }
  PREC_EQUALITY       = 10; { == != === !== }
  PREC_RELATIONAL     = 11; { < <= > >= in instanceof }
  PREC_SHIFT          = 12; { << >> >>> }
  PREC_ADDITIVE       = 13; { + - }
  PREC_MULTIPLICATIVE = 14; { * / % }
  PREC_EXPONENTIATION = 15; { ** }
  PREC_UNARY          = 16; { ! ~ + - typeof delete ++ -- await }
  PREC_POSTFIX        = 17; { ++ -- }
  PREC_CALL           = 18; { () [] . ?. }

type
  { TFloriaJSParser — Fast Pratt Precedence & Recursive-Descent Parser }
  TFloriaJSParser = class
  private
    FLexer: TFloriaJSLexer;
    FOwnsLexer: Boolean;
    FCurrent: TFloriaJSToken;
    FPrevious: TFloriaJSToken;
    FErrors: TStringList;
    FErrorLines: array of Integer;
    FErrorColumns: array of Integer;
    { True when the source is parsed as a module, which permits import/export
      declarations and top-level await. }
    FIsModule: Boolean;
    { True while parsing a class body, where a bare `super` is legal. }
    FSuperAllowed: Boolean;
    { How many function bodies enclose the current position. `return` is an
      early error when this is zero, regardless of block nesting. }
    FFunctionDepth: Integer;
    { Labels currently in scope. A label may not be nested inside a statement
      that already carries the same label, which is an early error. }
    FLabels: TStringList;
    { How many async function bodies enclose the current position. `await` is
      legal there, and at the top level of a module. }
    FAsyncDepth: Integer;
    { True while parsing a `static { ... }` block. `return`, `yield`, `await`,
      `arguments` as a binding, and `super(...)` are early errors there. }
    FInStaticBlock: Boolean;
    { The function depth on entering the current static block: `arguments` is
      illegal at that depth but legal inside a nested function. }
    FStaticBlockDepth: Integer;
    { How many class bodies enclose the current position. A private name is only
      meaningful inside one. }
    FClassDepth: Integer;
    { Set when parsing any `eval` source. In eval, `new.target` is illegal
      everywhere unless the eval is direct; private names are always rejected,
      because the parser cannot tell a declared one from an undeclared one. }
    FIsEvalCode: Boolean;
    { Set for a direct eval, where `new.target` evaluates to undefined. }
    FAllowEvalMeta: Boolean;
    { How many generator bodies enclose the current position. Inside one,
      `yield` is reserved and may not be an identifier reference. }
    FGeneratorDepth: Integer;
    { True while parsing the parameter list of a generator, where `yield` is
      not allowed at all. }
    FInGeneratorParams: Boolean;
    { True while parsing in a position where a YieldExpression is allowed, which
      is only the AssignmentExpression level. }
    FYieldExprAllowed: Boolean;
    { Private names declared anywhere in the current outermost class tree. A
      nested class may reach an enclosing class's private names, so validation
      waits until the outermost body has been parsed. }
    FDeclaredPrivates: TStringList;
    FPendingPrivateClasses: TFPList;
    { The classes currently being parsed, innermost last. }
    FClassStack: TFPList;
    { Class node -> its enclosing class, as an object pointer. }
    FClassParents: TStringList;
    { True while parsing the direct body of the program. Import/export
      declarations are only legal there when the source is a module. }
    FAtTopLevel: Boolean;

    procedure Advance();
    function  Check(AKind: TFloriaJSTokenKind): Boolean;
    function  Match(AKind: TFloriaJSTokenKind): Boolean;
    function  Consume(AKind: TFloriaJSTokenKind; const AErrorMessage: string): Boolean;
    function  IsAtEnd(): Boolean;
    { True when a line terminator separates the last consumed token from the
      current one. Restricted productions use this for automatic semicolon
      insertion. }
    function  HasLineBreakBeforeCurrent(): Boolean;
    { Consumes a semicolon or applies automatic semicolon insertion at a line
      break, a closing brace, or end of input. }
    procedure EndStatement(const AContext: string);
    procedure ErrorAtCurrent(const AMessage: string);
    procedure Synchronize();

    { Expression Pratt Parsing }
    { True for any reserved word. Property names and object-literal keys accept
      keywords, so those sites must not compare the token enum by range: the
      keyword block is not contiguous with the delimiters that follow it. }
    function  IsKeywordToken(AKind: TFloriaJSTokenKind): Boolean;
    { A token that can begin a class member's property name. Used to tell a
      modifier (`static`, `async`, `get`, `set`, `*`) from a member named by
      that word. }
    function  StartsPropertyName(AKind: TFloriaJSTokenKind): Boolean;
    function  GetInfixPrecedence(AKind: TFloriaJSTokenKind): Integer;
    function  ParsePrecedence(APrec: Integer): TFloriaJSExprNode;
    function  ParseAssignmentExpression(): TFloriaJSExprNode;
    function  ParsePrimary(): TFloriaJSExprNode;
    function  ParseUnaryPrefix(): TFloriaJSExprNode;
    function  ParseNewExpression(ANewToken: TFloriaJSToken): TFloriaJSExprNode;
    function  ParseMemberTail(ALeft: TFloriaJSExprNode): TFloriaJSExprNode;
    function  ParseArrayLiteral(): TFloriaJSExprNode;
    function  ParseObjectLiteral(): TFloriaJSExprNode;
    function  ParseMethodBody(const AName: string; AStartPos: Integer;
      AIsAsync: Boolean = False; AIsGenerator: Boolean = False): TFloriaJSFunctionExpr;
    { The original source text from AStartPos through the last consumed token. }
    function  SourceSlice(AStartPos, AEndPos: Integer): string;
    function  ParseClassExpr(AIsDeclaration: Boolean): TFloriaJSClassNode;
    { Rejects a `#name` used in the class body that the body never declares. }
    procedure ValidatePrivateNames(ACls: TFloriaJSClassNode);
    procedure ValidateClassMember(AMember: TFloriaJSClassMember);
    { Drops a class node from the private-name bookkeeping before it is freed on
      an error path. }
    procedure ForgetClass(ACls: TFloriaJSClassNode);
    function  ParseClassDeclaration(): TFloriaJSStmtNode;
    function  ParseTaggedTemplate(ATag: TFloriaJSExprNode): TFloriaJSExprNode;
    function  ParseFunctionExpr(AIsAsync: Boolean = False; AStartPos: Integer = -1): TFloriaJSExprNode;
    function  ParseFunctionBlockBody(): TFloriaJSStmtNode;
    function  ParseAsyncFunctionBlockBody(): TFloriaJSStmtNode;
    function  ParseGeneratorBlockBody(): TFloriaJSStmtNode;
    procedure ParseArrowBody(AAsync: Boolean; AFnExpr: TFloriaJSFunctionExpr);
    procedure ParseFormalParameters(AParams: TStringList);
    function  ExtractParameters(var AExpr: TFloriaJSExprNode; AParams: TStrings): Boolean;

    { Statements & Declarations }
    function  ParseStatement(): TFloriaJSStmtNode;
    function  ParseDeclaration(): TFloriaJSStmtNode;
    function  ParseVarDeclaration(AKind: TFloriaJSTokenKind): TFloriaJSVarStmt;
    function  ParseFunctionDeclaration(AIsAsync: Boolean = False; AIsGenerator: Boolean = False; AStartPos: Integer = -1; AAllowAnonymous: Boolean = False): TFloriaJSFunctionDecl;
    function  ParseIfStatement(): TFloriaJSIfStmt;
    function  ParseWhileStatement(): TFloriaJSWhileStmt;
    function  ParseDoWhileStatement(): TFloriaJSWhileStmt;
    function  ParseForStatement(): TFloriaJSStmtNode;
    function  ParseSwitchStatement(): TFloriaJSSwitchStmt;
    function  ParseTryStatement(): TFloriaJSTryStmt;
    function  ParseThrowStatement(): TFloriaJSThrowStmt;
    function  ParseBlockStatement(): TFloriaJSBlockStmt;
    function  ParseReturnStatement(): TFloriaJSReturnStmt;
    function  ParseBreakStatement(): TFloriaJSBreakStmt;
    function  ParseContinueStatement(): TFloriaJSContinueStmt;
    function  ParseDebuggerStatement(): TFloriaJSDebuggerStmt;
    function  ParseExpressionStatement(): TFloriaJSExprStmt;
    procedure ParseFTMLBody(AComp: TFloriaFTMLComponent);

    { Module Syntax (import / export declarations) }
    { Matches a contextual keyword (`from`, `as`) by text, since the lexer
      keeps those words as identifiers. }
    function  CheckIdentifierText(const AText: string): Boolean;
    function  ConsumeIdentifierText(const AText, AErrorMessage: string): Boolean;
    { A module declaration is only legal at the top level of a module. }
    function  CheckModuleDeclarationContext(const AKeyword: string): Boolean;
    { Reads an export/import name: an identifier, a keyword, or a string
      literal. Returns the text. }
    function  ParseModuleName(const AContext: string): string;
    { Reads a binding name: only an identifier is legal there. }
    function  ParseModuleBindingName(const AContext: string): string;
    function  ParseModuleSpecifierString(const AContext: string): string;
    procedure ParseImportAttributes(ADecl: TFloriaJSImportDecl);
    { Skips the rest of a malformed module declaration, up to its terminating
      semicolon, so one error does not cascade. }
    procedure SkipModuleDeclaration();
    function  ParseImportDeclaration(): TFloriaJSStmtNode;
    function  ParseImportClause(ADecl: TFloriaJSImportDecl): Boolean;
    function  ParseExportDeclaration(): TFloriaJSStmtNode;
    function  ParseExportDefault(ADecl: TFloriaJSExportDecl): Boolean;
    function  ParseExportClause(ANames, AAliases, AKinds: TStrings): Boolean;

  public
    constructor Create(const ASource: string);
    constructor Create(ALexer: TFloriaJSLexer);
    destructor Destroy(); override;

    function  ParseProgram(): TFloriaJSProgram;
    function  ParseExpression(): TFloriaJSExprNode;
    function  ParseFTMLComponent(): TFloriaFTMLComponent;

    function  HasErrors(): Boolean;
    function  GetErrorCount(): Integer;
    function  GetError(AIndex: Integer): string;
    function  GetErrorLine(AIndex: Integer): Integer;
    function  GetErrorColumn(AIndex: Integer): Integer;

    { Parse the program in module mode: import/export declarations and
      top-level await become legal. }
    procedure SetModuleMode(AValue: Boolean);
    property IsModule: Boolean read FIsModule;
    { Marks the source as eval code, optionally a direct eval. }
    property IsEvalCode: Boolean read FIsEvalCode write FIsEvalCode;
    property AllowEvalMeta: Boolean read FAllowEvalMeta write FAllowEvalMeta;

    property Errors: TStringList read FErrors;
  end;

implementation

{ TFloriaJSParser }

constructor TFloriaJSParser.Create(const ASource: string);
begin
  inherited Create();
  FLexer := TFloriaJSLexer.Create(ASource);
  FOwnsLexer := True;
  FErrors := TStringList.Create();
  FLabels := TStringList.Create();
  FIsModule := False;
  FAtTopLevel := False;
  FSuperAllowed := False;
  FFunctionDepth := 0;
  FAsyncDepth := 0;
  FInStaticBlock := False;
  FClassDepth := 0;
  FIsEvalCode := False;
  FAllowEvalMeta := False;
  FGeneratorDepth := 0;
  FInGeneratorParams := False;
  FYieldExprAllowed := False;
  FDeclaredPrivates := TStringList.Create();
  FDeclaredPrivates.CaseSensitive := True;
  FPendingPrivateClasses := TFPList.Create();
  FClassStack := TFPList.Create();
  FClassParents := TStringList.Create();
  FClassParents.Sorted := True;
  Advance();
end;

constructor TFloriaJSParser.Create(ALexer: TFloriaJSLexer);
begin
  inherited Create();
  FLexer := ALexer;
  FOwnsLexer := False;
  FErrors := TStringList.Create();
  FLabels := TStringList.Create();
  FIsModule := False;
  FAtTopLevel := False;
  FSuperAllowed := False;
  FFunctionDepth := 0;
  FAsyncDepth := 0;
  FInStaticBlock := False;
  FClassDepth := 0;
  FIsEvalCode := False;
  FAllowEvalMeta := False;
  FGeneratorDepth := 0;
  FInGeneratorParams := False;
  FYieldExprAllowed := False;
  FDeclaredPrivates := TStringList.Create();
  FDeclaredPrivates.CaseSensitive := True;
  FPendingPrivateClasses := TFPList.Create();
  FClassStack := TFPList.Create();
  FClassParents := TStringList.Create();
  FClassParents.Sorted := True;
  Advance();
end;

destructor TFloriaJSParser.Destroy();
begin
  FreeAndNil(FClassParents);
  FreeAndNil(FClassStack);
  FreeAndNil(FPendingPrivateClasses);
  FreeAndNil(FDeclaredPrivates);
  FreeAndNil(FLabels);
  FreeAndNil(FErrors);
  if FOwnsLexer then
    FreeAndNil(FLexer);
  inherited Destroy();
end;

procedure TFloriaJSParser.Advance();
begin
  FPrevious := FCurrent;
  while True do
  begin
    FCurrent := FLexer.NextToken();
    if FCurrent.Kind <> tkError then
      Break;
    ErrorAtCurrent(FCurrent.Text);
  end;
end;

function TFloriaJSParser.HasLineBreakBeforeCurrent(): Boolean;
begin
  Result := FCurrent.Line > FPrevious.Line;
end;

procedure TFloriaJSParser.EndStatement(const AContext: string);
begin
  if Match(tkSemicolon) then
    Exit;
  if Check(tkRBrace) or IsAtEnd() or HasLineBreakBeforeCurrent() then
    Exit;
  ErrorAtCurrent('Expected '';'' after ' + AContext);
end;

function TFloriaJSParser.Check(AKind: TFloriaJSTokenKind): Boolean;
begin
  Result := (FCurrent.Kind = AKind);
end;

function TFloriaJSParser.Match(AKind: TFloriaJSTokenKind): Boolean;
begin
  if not Check(AKind) then
    Exit(False);
  Advance();
  Result := True;
end;

function TFloriaJSParser.Consume(AKind: TFloriaJSTokenKind; const AErrorMessage: string): Boolean;
begin
  if Check(AKind) then
  begin
    Advance();
    Exit(True);
  end;
  ErrorAtCurrent(AErrorMessage);
  Result := False;
end;

function TFloriaJSParser.IsAtEnd(): Boolean;
begin
  Result := (FCurrent.Kind = tkEOF);
end;

procedure TFloriaJSParser.ErrorAtCurrent(const AMessage: string);
var
  errMsg: string;
begin
  errMsg := Format('[Line %d, Col %d] Error: %s', [FCurrent.Line, FCurrent.Column, AMessage]);
  FErrors.Add(errMsg);
  SetLength(FErrorLines, FErrors.Count);
  SetLength(FErrorColumns, FErrors.Count);
  FErrorLines[FErrors.Count - 1] := FCurrent.Line;
  FErrorColumns[FErrors.Count - 1] := FCurrent.Column;
end;

procedure TFloriaJSParser.Synchronize();
begin
  Advance();
  while not IsAtEnd() do
  begin
    if FPrevious.Kind = tkSemicolon then
      Exit;
    case FCurrent.Kind of
      tkFunction, tkVar, tkLet, tkConst, tkFor, tkIf, tkWhile, tkReturn,
      tkTry, tkThrow:
        Exit;
    else
      Advance();
    end;
  end;
end;

function TFloriaJSParser.HasErrors(): Boolean;
begin
  Result := (FErrors <> nil) and (FErrors.Count > 0);
end;

function TFloriaJSParser.GetErrorCount(): Integer;
begin
  if FErrors <> nil then
    Result := FErrors.Count
  else
    Result := 0;
end;

function TFloriaJSParser.GetError(AIndex: Integer): string;
begin
  if (FErrors <> nil) and (AIndex >= 0) and (AIndex < FErrors.Count) then
    Result := FErrors[AIndex]
  else
    Result := '';
end;

function TFloriaJSParser.GetErrorLine(AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < Length(FErrorLines)) then
    Result := FErrorLines[AIndex]
  else
    Result := 0;
end;

function TFloriaJSParser.GetErrorColumn(AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < Length(FErrorColumns)) then
    Result := FErrorColumns[AIndex]
  else
    Result := 0;
end;

{ Precedence Table }

function TFloriaJSParser.StartsPropertyName(AKind: TFloriaJSTokenKind): Boolean;
begin
  Result := (AKind in [tkIdentifier, tkString, tkNumber, tkLBracket,
    tkPrivateName, tkMultiply]) or IsKeywordToken(AKind);
end;

function TFloriaJSParser.IsKeywordToken(AKind: TFloriaJSTokenKind): Boolean;
begin
  { The keyword block is contiguous in the enum; keep the upper bound on the
    last keyword so a newly added keyword is covered automatically. That
    includes `import` and `export`, which are ordinary property names outside
    a module declaration. }
  Result := (AKind >= tkLet) and (AKind <= tkAs);
end;

function TFloriaJSParser.GetInfixPrecedence(AKind: TFloriaJSTokenKind): Integer;
begin
  case AKind of
    tkComma:
      Result := PREC_COMMA;
    tkAssign, tkPlusAssign, tkMinusAssign, tkMultiplyAssign, tkDivideAssign, tkModuloAssign,
    tkPowerAssign, tkNullishAssign, tkAndAssign, tkOrAssign,
    tkBitAndAssign, tkBitOrAssign, tkBitXorAssign,
    tkShiftLeftAssign, tkShiftRightAssign, tkShiftRightUnsignedAssign, tkArrow:
      Result := PREC_ASSIGNMENT;
    tkQuestion:
      Result := PREC_CONDITIONAL;
    tkNullish:
      Result := PREC_NULLISH;
    tkOr:
      Result := PREC_LOGICAL_OR;
    tkAnd:
      Result := PREC_LOGICAL_AND;
    tkBitOr:
      Result := PREC_BIT_OR;
    tkBitXor:
      Result := PREC_BIT_XOR;
    tkBitAnd:
      Result := PREC_BIT_AND;
    tkEqual, tkStrictEqual, tkNotEqual, tkStrictNotEqual:
      Result := PREC_EQUALITY;
    tkLessThan, tkLessEqual, tkGreaterThan, tkGreaterEqual, tkIn, tkInstanceof:
      Result := PREC_RELATIONAL;
    tkShiftLeft, tkShiftRight, tkShiftRightUnsigned:
      Result := PREC_SHIFT;
    tkPlus, tkMinus:
      Result := PREC_ADDITIVE;
    tkMultiply, tkDivide, tkModulo:
      Result := PREC_MULTIPLICATIVE;
    tkPower:
      Result := PREC_EXPONENTIATION;
    tkPlusPlus, tkMinusMinus:
      Result := PREC_POSTFIX;
    tkLParen, tkDot, tkLBracket, tkQuestionDot,
    tkTemplateString, tkTemplateHead:
      Result := PREC_CALL;
  else
    Result := PREC_NONE;
  end;
end;

{ Expression Parsing }

function TFloriaJSParser.ParsePrimary(): TFloriaJSExprNode;
var
  tok: TFloriaJSToken;
  expr, cur: TFloriaJSExprNode;
  fnExpr: TFloriaJSFunctionExpr;
  callExpr: TFloriaJSCallExpr;
  brandExpr: TFloriaJSExprNode;
  paramName, pat, flags: string;
  fnStartPos: Integer;
  nullPos: Integer;
begin
  tok := FCurrent;

  { Literals }
  if Match(tkRegExp) then
  begin
    nullPos := Pos(#0, tok.Text);
    if nullPos > 0 then
    begin
      pat := Copy(tok.Text, 1, nullPos - 1);
      flags := Copy(tok.Text, nullPos + 1, Length(tok.Text) - nullPos);
    end
    else
    begin
      pat := tok.Text;
      flags := '';
    end;
    callExpr := TFloriaJSCallExpr.Create(
      TFloriaJSIdentifierExpr.Create('RegExp', tok.Line, tok.Column),
      tok.Line, tok.Column, True);
    callExpr.AddArgument(TFloriaJSLiteralExpr.CreateString(pat, tok.Line, tok.Column));
    callExpr.AddArgument(TFloriaJSLiteralExpr.CreateString(flags, tok.Line, tok.Column));
    Exit(callExpr);
  end;

  if Match(tkNumber) then
  begin
    if FPrevious.IsBigInt then
      Exit(TFloriaJSLiteralExpr.CreateBigInt(FPrevious.BigIntValue, tok.Line, tok.Column));
    begin
      expr := TFloriaJSLiteralExpr.CreateNumber(tok.NumberValue, tok.Line, tok.Column);
      TFloriaJSLiteralExpr(expr).IsLegacyOctal := tok.IsLegacyOctal;
      Exit(expr);
    end;
  end;

  if Match(tkString) or Match(tkTemplateString) then
    begin
      expr := TFloriaJSLiteralExpr.CreateString(tok.Text, tok.Line, tok.Column);
      TFloriaJSLiteralExpr(expr).IsLegacyOctalEscape := tok.IsLegacyOctalEscape;
      Exit(expr);
    end;

  if Match(tkTemplateHead) then
  begin
    cur := TFloriaJSLiteralExpr.CreateString(FPrevious.Text, FPrevious.Line, FPrevious.Column);
    expr := ParseExpression();
    cur := TFloriaJSBinaryExpr.Create(cur, tkPlus, expr, FPrevious.Line, FPrevious.Column);

    while Match(tkTemplateMiddle) do
    begin
      cur := TFloriaJSBinaryExpr.Create(cur, tkPlus,
        TFloriaJSLiteralExpr.CreateString(FPrevious.Text, FPrevious.Line, FPrevious.Column),
        FPrevious.Line, FPrevious.Column);
      expr := ParseExpression();
      cur := TFloriaJSBinaryExpr.Create(cur, tkPlus, expr, FPrevious.Line, FPrevious.Column);
    end;

    Consume(tkTemplateTail, 'Expected template literal tail');
    if FPrevious.Text <> '' then
      cur := TFloriaJSBinaryExpr.Create(cur, tkPlus,
        TFloriaJSLiteralExpr.CreateString(FPrevious.Text, FPrevious.Line, FPrevious.Column),
        FPrevious.Line, FPrevious.Column);

    Exit(cur);
  end;

  if Match(tkTrue) then
    Exit(TFloriaJSLiteralExpr.CreateBoolean(True, tok.Line, tok.Column));

  if Match(tkFalse) then
    Exit(TFloriaJSLiteralExpr.CreateBoolean(False, tok.Line, tok.Column));

  if Match(tkNull) then
    Exit(TFloriaJSLiteralExpr.CreateNull(tok.Line, tok.Column));

  if Match(tkUndefined) then
    Exit(TFloriaJSLiteralExpr.CreateUndefined(tok.Line, tok.Column));

  { import.meta and the dynamic import() expression. }
  if Check(tkImport) then
  begin
    Advance();
    if Match(tkDot) then
    begin
      { import.meta is only meaningful in a module, but it is an expression,
        so it is legal in any nested position. }
      if not FIsModule then
      begin
        ErrorAtCurrent('Cannot use ''import.meta'' outside a module');
        Result := TFloriaJSLiteralExpr.CreateUndefined(tok.Line, tok.Column);
        Exit;
      end;
      if (FCurrent.Kind = tkIdentifier) and (FCurrent.Text = 'meta') then
      begin
        Advance();
        expr := TFloriaJSIdentifierExpr.Create('import.meta', tok.Line, tok.Column);
        expr.SourceStart := tok.StartPos;
        expr.SourceEnd := FPrevious.EndPos;
        Exit(expr);
      end;
      ErrorAtCurrent('Expected `meta` after `import.`');
    end;
    if Check(tkLParen) then
    begin
      Advance();
      callExpr := TFloriaJSCallExpr.Create(
        TFloriaJSIdentifierExpr.Create('import', tok.Line, tok.Column),
        tok.Line, tok.Column);
      callExpr.AddArgument(ParseAssignmentExpression());
      { A second argument carries import attributes. }
      if Match(tkComma) then
      begin
        callExpr.AddArgument(ParseAssignmentExpression());
        if Match(tkComma) then
          callExpr.AddArgument(ParseAssignmentExpression());
      end;
      Consume(tkRParen, 'Expected '')'' after the import options');
      Exit(callExpr);
    end;
    ErrorAtCurrent('Expected `(` or `.meta` after `import`');
  end;

  { `#x in obj` — a private-name brand check. }
  if Match(tkPrivateName) then
  begin
    brandExpr := TFloriaJSIdentifierExpr.Create(FPrevious.Text, tok.Line, tok.Column);
    Exit(brandExpr);
  end;

  { Identifier }
  if Match(tkIdentifier) then
  begin
    { A `static { ... }` block has no `arguments`; only a nested function in it
      does. }
    if FInStaticBlock and (FFunctionDepth = FStaticBlockDepth) and
       (FPrevious.Text = 'arguments') then
      ErrorAtCurrent('''arguments'' is not allowed in a static block');
    expr := TFloriaJSIdentifierExpr.Create(tok.Text, tok.Line, tok.Column);
    expr.SourceStart := tok.StartPos;
    expr.SourceEnd := FPrevious.EndPos;
    Exit(expr);
  end;

  { this — the receiver of a method or constructor call. It is bound like an
    ordinary name in the activation scope of the call. }
  if Match(tkThis) then
    Exit(TFloriaJSIdentifierExpr.Create('this', tok.Line, tok.Column));

  { yield — only meaningful inside a generator body. Module code at the top
    level is not one, so `yield;` there is an early SyntaxError. }
  if Match(tkYield) then
  begin
    { `yield` is legal only inside a generator body. A module's top level and a
      static block are not one. }
    if (FIsModule or FInStaticBlock) and (FFunctionDepth = 0) then
      ErrorAtCurrent('Unexpected reserved word');
    { In a generator body `yield` is reserved, so outside a position that
      admits a YieldExpression it can only be an identifier reference, which is
      an early SyntaxError. This is what makes `void yield;` illegal. }
    if (FGeneratorDepth > 0) and (not FYieldExprAllowed) then
      ErrorAtCurrent('Unexpected reserved word');
    { A generator's parameters are evaluated outside its body, so `yield` may
      not appear there. }
    if FInGeneratorParams then
      ErrorAtCurrent('Unexpected reserved word in generator parameters');
    { `yield` may not be followed by a line terminator before `*`: the
      delegation form is a restricted production. }
    if (FCurrent.Line > FPrevious.Line) and Check(tkMultiply) then
      ErrorAtCurrent('Unexpected token after a line terminator in ''yield''');
    { A line terminator after `yield` ends the expression, so `yield\n1` yields
      undefined and then evaluates `1` as a separate statement. }
    if FCurrent.Line > FPrevious.Line then
      Exit(TFloriaJSUnaryExpr.Create(tkYield,
        TFloriaJSLiteralExpr.CreateUndefined(tok.Line, tok.Column),
        True, tok.Line, tok.Column));
    { `yield* expr` delegates to another iterable; the compiler lowers it to a
      loop that re-yields each value. A second unary node marks the delegation. }
    if Match(tkMultiply) then
      Exit(TFloriaJSUnaryExpr.Create(tkYield,
        TFloriaJSUnaryExpr.Create(tkMultiply, ParseAssignmentExpression(), True, tok.Line, tok.Column),
        True, tok.Line, tok.Column));
    if Check(tkSemicolon) or Check(tkRParen) or Check(tkRBrace) or
       Check(tkRBracket) or Check(tkComma) or Check(tkColon) or IsAtEnd() then
      Exit(TFloriaJSUnaryExpr.Create(tkYield, TFloriaJSLiteralExpr.CreateUndefined(tok.Line, tok.Column), True, tok.Line, tok.Column));
    Exit(TFloriaJSUnaryExpr.Create(tkYield, ParseAssignmentExpression(), True, tok.Line, tok.Column));
  end;

  { super — bound like `this`, to the parent constructor inside a derived class.
    `super(...)` and `super.m()` are handled by the compiler through it. A bare
    `super` outside a method is an early SyntaxError, which module tests cover
    directly. }
  if Match(tkSuper) then
  begin
    if not FSuperAllowed then
      ErrorAtCurrent('''super'' keyword unexpected here');
    { `super(...)` constructs the base class and is legal only in a derived
      constructor, never in a static block. }
    if FInStaticBlock and (FCurrent.Kind = tkLParen) then
      ErrorAtCurrent('''super'' keyword unexpected here');
    Exit(TFloriaJSIdentifierExpr.Create('super', tok.Line, tok.Column));
  end;

  { class expression }
  if Match(tkClass) then
    Exit(ParseClassExpr(False));

  { Array Literal }
  if Match(tkLBracket) then
    Exit(ParseArrayLiteral());

  { Object Literal }
  if Match(tkLBrace) then
    Exit(ParseObjectLiteral());

  { Async Function Expression or Async Arrow Function }
  if Match(tkAsync) then
  begin
    if Match(tkFunction) then
    begin
      { The source spelling starts at `async`, not at `function` or `*`. }
      fnStartPos := tok.StartPos;
      if Match(tkMultiply) then
      begin
        expr := ParseFunctionExpr(True, fnStartPos);
        if expr is TFloriaJSFunctionExpr then
          TFloriaJSFunctionExpr(expr).IsGenerator := True;
        Exit(expr);
      end;
      Exit(ParseFunctionExpr(True, fnStartPos));
    end;

    if Match(tkLParen) then
    begin
      if Match(tkRParen) then
      begin
        if Match(tkArrow) then
        begin
          fnExpr := TFloriaJSFunctionExpr.Create('', True, tok.Line, tok.Column, True);
          ParseArrowBody(True, fnExpr);
          fnExpr.SourceText := SourceSlice(tok.StartPos, FPrevious.EndPos);
          Exit(fnExpr);
        end
        else
        begin
          callExpr := TFloriaJSCallExpr.Create(TFloriaJSIdentifierExpr.Create('async', tok.Line, tok.Column), tok.Line, tok.Column);
          Exit(callExpr);
        end;
      end
      else
      begin
        expr := ParseExpression();
        Consume(tkRParen, 'Expected '')'' after expression');
        if Match(tkArrow) then
        begin
          fnExpr := TFloriaJSFunctionExpr.Create('', True, tok.Line, tok.Column, True);
          if not ExtractParameters(expr, fnExpr.Parameters) then
            ErrorAtCurrent('Invalid arrow function parameter');
          if expr <> nil then
            expr.Free();
          ParseArrowBody(True, fnExpr);
          fnExpr.SourceText := SourceSlice(tok.StartPos, FPrevious.EndPos);
          Exit(fnExpr);
        end
        else
        begin
          callExpr := TFloriaJSCallExpr.Create(TFloriaJSIdentifierExpr.Create('async', tok.Line, tok.Column), tok.Line, tok.Column);
          callExpr.AddArgument(expr);
          Exit(callExpr);
        end;
      end;
    end
    else if (FCurrent.Kind = tkIdentifier) and (FLexer.PeekToken().Kind = tkArrow) then
    begin
      Advance();
      paramName := FPrevious.Text;
      Consume(tkArrow, 'Expected ''=>'' after async parameter');
      fnExpr := TFloriaJSFunctionExpr.Create('', True, tok.Line, tok.Column, True);
      fnExpr.AddParameter(paramName);
      ParseArrowBody(True, fnExpr);
      fnExpr.SourceText := SourceSlice(tok.StartPos, FPrevious.EndPos);
      Exit(fnExpr);
    end
    else
      Exit(TFloriaJSIdentifierExpr.Create('async', tok.Line, tok.Column));
  end;

  { Function Expression }
  if Match(tkFunction) then
  begin
    fnStartPos := FPrevious.StartPos;
    if Match(tkMultiply) then
    begin
      expr := ParseFunctionExpr(False, fnStartPos);
      if expr is TFloriaJSFunctionExpr then
        TFloriaJSFunctionExpr(expr).IsGenerator := True;
      Exit(expr);
    end;
    Exit(ParseFunctionExpr(False, fnStartPos));
  end;

  { Parenthesized Grouping or Arrow function }
  if Match(tkLParen) then
  begin
    if Match(tkRParen) then
    begin
      if Match(tkArrow) then
      begin
        fnExpr := TFloriaJSFunctionExpr.Create('', True, tok.Line, tok.Column);
        ParseArrowBody(False, fnExpr);
        fnExpr.SourceText := SourceSlice(tok.StartPos, FPrevious.EndPos);
        Exit(fnExpr);
      end;
      ErrorAtCurrent('Expected expression');
      Exit(TFloriaJSLiteralExpr.CreateUndefined(tok.Line, tok.Column));
    end;

    expr := ParseExpression();
    Consume(tkRParen, 'Expected '')'' after expression');
    if Match(tkArrow) then
    begin
      fnExpr := TFloriaJSFunctionExpr.Create('', True, tok.Line, tok.Column);
      if not ExtractParameters(expr, fnExpr.Parameters) then
        ErrorAtCurrent('Invalid arrow function parameter');
      if expr <> nil then
        expr.Free();
      ParseArrowBody(False, fnExpr);
      fnExpr.SourceText := SourceSlice(tok.StartPos, FPrevious.EndPos);
      Exit(fnExpr);
    end;
    Exit(TFloriaJSGroupExpr.Create(expr, tok.Line, tok.Column));
  end;

  ErrorAtCurrent('Expected expression');
  Advance();
  Result := TFloriaJSLiteralExpr.CreateUndefined(tok.Line, tok.Column);
end;

{ A simple assignment target is an identifier or a member access. `0 = 1` and
  `0++` are early errors, so the parser rejects them rather than letting the
  compiler emit a store that fails at run time. }
function IsSimpleAssignmentTarget(ANode: TFloriaJSExprNode): Boolean;
begin
  while ANode is TFloriaJSGroupExpr do
    ANode := TFloriaJSGroupExpr(ANode).Expression;
  Result := (ANode is TFloriaJSIdentifierExpr) or
            (ANode is TFloriaJSMemberExpr);
end;

function IsOptionalChainTarget(ANode: TFloriaJSExprNode): Boolean;
begin
  while ANode is TFloriaJSGroupExpr do
    ANode := TFloriaJSGroupExpr(ANode).Expression;
  Result := ContainsOptionalChain(ANode);
end;

function TFloriaJSParser.ParseUnaryPrefix(): TFloriaJSExprNode;
var
  op: TFloriaJSToken;
  operand, deleteTarget: TFloriaJSExprNode;
  savedYield: Boolean;
begin
  op := FCurrent;
  Advance();
  if op.Kind = tkEllipsis then
  begin
    operand := ParseAssignmentExpression();
    Exit(TFloriaJSSpreadExpr.Create(operand, op.Line, op.Column));
  end;
  { `await` is an early error outside an async function body and outside the
    top level of a module. }
  if op.Kind = tkAwait then
  begin
    if (FAsyncDepth = 0) and not (FIsModule and (FFunctionDepth = 0)) then
      ErrorAtCurrent('Unexpected reserved word');
  end;

  savedYield := FYieldExprAllowed;
  FYieldExprAllowed := False;
  try
    operand := ParsePrecedence(PREC_UNARY);
  finally
    FYieldExprAllowed := savedYield;
  end;

  { `delete` of a private member is an early SyntaxError: a private name has no
    [[Delete]] and can never be removed. }
  if op.Kind = tkDelete then
  begin
    deleteTarget := operand;
    while deleteTarget is TFloriaJSGroupExpr do
      deleteTarget := TFloriaJSGroupExpr(deleteTarget).Expression;
    if (deleteTarget is TFloriaJSMemberExpr) and
       TFloriaJSMemberExpr(deleteTarget).IsPrivate then
      ErrorAtCurrent('Private fields can not be deleted');
  end;

  if op.Kind in [tkPlusPlus, tkMinusMinus] then
  begin
    if IsOptionalChainTarget(operand) then
      ErrorAtCurrent('Invalid left-hand side in prefix operation');
    if not IsSimpleAssignmentTarget(operand) then
      ErrorAtCurrent('Invalid left-hand side in prefix operation');
  end;
  Result := TFloriaJSUnaryExpr.Create(op.Kind, operand, True, op.Line, op.Column);
end;

function TFloriaJSParser.ParseMemberTail(ALeft: TFloriaJSExprNode): TFloriaJSExprNode;
var
  op: TFloriaJSToken;
  memberPropName: string;
  computedProp: TFloriaJSExprNode;
begin
  Result := ALeft;
  while (FCurrent.Kind = tkDot) or (FCurrent.Kind = tkLBracket) or
        (FCurrent.Kind = tkQuestionDot) do
  begin
    op := FCurrent;
    if op.Kind = tkQuestionDot then
    begin
      ErrorAtCurrent('Cannot use new with optional chaining');
      Break;
    end;
    Advance();

    if op.Kind = tkDot then
    begin
      if Match(tkPrivateName) then
      begin
        memberPropName := FPrevious.Text;
        if FClassDepth = 0 then
          ErrorAtCurrent('Private field must be declared in an enclosing class');
      end
      else if Match(tkIdentifier) then
        memberPropName := FPrevious.Text
      else if IsKeywordToken(FCurrent.Kind) then
      begin
        memberPropName := FCurrent.Text;
        Advance();
      end
      else
      begin
        ErrorAtCurrent('Expected property name after ''.''');
        memberPropName := '';
      end;
      Result := TFloriaJSMemberExpr.CreateNamed(Result, memberPropName, op.Line, op.Column);
    end
    else
    begin
      computedProp := ParseExpression();
      Consume(tkRBracket, 'Expected '']'' after computed property accessor');
      Result := TFloriaJSMemberExpr.CreateComputed(Result, computedProp, op.Line, op.Column);
    end;
  end;

  { A template literal directly after an expression is a tagged template, not a
    separate expression: `tag`x`` calls tag. }
  if FCurrent.Kind in [tkTemplateString, tkTemplateHead] then
    Result := ParseTaggedTemplate(Result);
end;

function TFloriaJSParser.ParseNewExpression(ANewToken: TFloriaJSToken): TFloriaJSExprNode;
var
  callee: TFloriaJSExprNode;
  callExpr: TFloriaJSCallExpr;
  nested: TFloriaJSToken;
begin
  { The callee of new is a member expression. An argument list that follows it
    belongs to the construction, not to a call of the callee, so only the
    property access suffixes are taken here. }
  if FCurrent.Kind = tkNew then
  begin
    nested := FCurrent;
    Advance();
    callee := ParseNewExpression(nested);
  end
  else
    callee := ParsePrimary();

  callee := ParseMemberTail(callee);

  if ContainsOptionalChain(callee) then
    ErrorAtCurrent('Cannot use new with optional chaining');

  callExpr := TFloriaJSCallExpr.Create(callee, ANewToken.Line, ANewToken.Column, True);

  { The argument list is optional: new Foo is the same as new Foo(). }
  if Match(tkLParen) then
  begin
    if not Check(tkRParen) then
    begin
      repeat
        if Check(tkRParen) then
          Break;
        if Match(tkEllipsis) then
          callExpr.AddArgument(TFloriaJSSpreadExpr.Create(ParseAssignmentExpression(), FPrevious.Line, FPrevious.Column))
        else
          callExpr.AddArgument(ParseAssignmentExpression());
      until not Match(tkComma);
    end;
    Consume(tkRParen, 'Expected '')'' after argument list');
  end;

  Result := callExpr;
end;

function TFloriaJSParser.ParseArrayLiteral(): TFloriaJSExprNode;
var
  arr: TFloriaJSArrayExpr;
  spreadElement: TFloriaJSExprNode;
  startLine, startCol: Integer;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  arr := TFloriaJSArrayExpr.Create(startLine, startCol);

  while (not Check(tkRBracket)) and (not IsAtEnd()) do
  begin
    if Match(tkComma) then
    begin
      arr.AddElement(nil); // Array hole
      Continue;
    end;

    if Match(tkEllipsis) then
    begin
      { A rest element takes no initializer. `[...[x] = []]` puts one on the
        inner rest target, which is an early SyntaxError. }
      spreadElement := ParseAssignmentExpression();
      if (spreadElement is TFloriaJSAssignExpr) and
         (TFloriaJSAssignExpr(spreadElement).Target is TFloriaJSArrayExpr) then
        ErrorAtCurrent('A rest element may not have a default initializer');
      arr.AddElement(TFloriaJSSpreadExpr.Create(spreadElement, FPrevious.Line, FPrevious.Column));
    end
    else
      arr.AddElement(ParseAssignmentExpression());

    if not Check(tkRBracket) then
      Consume(tkComma, 'Expected '','' or '']'' after array element');
  end;

  Consume(tkRBracket, 'Expected '']'' after array elements');
  Result := arr;
end;


{ `class [Name] [extends Base] { members }`

  Members are methods, `get`/`set` accessors, fields, private names, and static
  blocks. The decorator-era `accessor x = ...` field form is not implemented and
  is rejected with a message the diagnostic adapter reports as a parser
  limitation rather than as a specification early error. }

{ `class Name ... { }` as a statement.

  Lowered to a `let` declaration whose initializer is the class expression, so
  the class binding is block-scoped and behaves like any other declaration. }
function TFloriaJSParser.ParseClassDeclaration(): TFloriaJSStmtNode;
var
  cls: TFloriaJSClassNode;
  varStmt: TFloriaJSVarStmt;
  startLine, startCol: Integer;
begin
  startLine := FCurrent.Line;
  startCol := FCurrent.Column;
  Advance(); { consume `class` }

  cls := ParseClassExpr(True);
  if cls.Name = '' then
  begin
    ErrorAtCurrent('A class declaration needs a name');
    ForgetClass(cls);
    cls.Free();
    Exit(TFloriaJSBlockStmt.Create(startLine, startCol));
  end;

  { A class declaration is a declaration, not a statement: it never needs a
    terminating semicolon. }
  Match(tkSemicolon);
  varStmt := TFloriaJSVarStmt.Create(tkLet, startLine, startCol);
  varStmt.AddDeclarator(cls.Name, cls);
  Result := varStmt;
end;


{ Parses the template part of a tagged template, keeping the cooked and raw
  strings and the substitution expressions separate instead of flattening them
  into a `+` chain. }
function TFloriaJSParser.ParseTaggedTemplate(ATag: TFloriaJSExprNode): TFloriaJSExprNode;
var
  node: TFloriaJSTaggedTemplateExpr;
  startLine, startCol: Integer;
begin
  startLine := FCurrent.Line;
  startCol := FCurrent.Column;
  node := TFloriaJSTaggedTemplateExpr.Create(ATag, startLine, startCol);

  if Match(tkTemplateString) then
  begin
    { A template with no substitutions has one string and no expressions. }
    node.AddPart(FPrevious.Text, FPrevious.Text);
    Exit(node);
  end;

  Consume(tkTemplateHead, 'Expected a template literal after the tag');
  node.AddPart(FPrevious.Text, FPrevious.Text);
  node.AddExpression(ParseExpression());

  while Match(tkTemplateMiddle) do
  begin
    node.AddPart(FPrevious.Text, FPrevious.Text);
    node.AddExpression(ParseExpression());
  end;

  Consume(tkTemplateTail, 'Expected template literal tail');
  node.AddPart(FPrevious.Text, FPrevious.Text);

  Result := node;
end;

{ The `ContainsArguments` and `ContainsSuperCall` early errors for a class field
  initializer. An arrow body is a statement whose expression may hold another
  arrow, so each pair recurses through the other; an ordinary function body is
  a fresh scope and stops the walk. }
function ExprContainsSuperCall(AExpr: TFloriaJSExprNode): Boolean; forward;
function StmtContainsSuperCall(AStmt: TFloriaJSStmtNode): Boolean; forward;
function ExprContainsArguments(AExpr: TFloriaJSExprNode): Boolean; forward;
function StmtContainsArguments(AStmt: TFloriaJSStmtNode): Boolean; forward;

function ExprContainsSuperCall(AExpr: TFloriaJSExprNode): Boolean;
var
  i: Integer;
  target: TFloriaJSExprNode;
begin
  Result := False;
  if AExpr = nil then Exit;
  target := AExpr;
  while target is TFloriaJSGroupExpr do
    target := TFloriaJSGroupExpr(target).Expression;

  if target is TFloriaJSCallExpr then
  begin
    if (TFloriaJSCallExpr(target).Callee is TFloriaJSIdentifierExpr) and
       (TFloriaJSIdentifierExpr(TFloriaJSCallExpr(target).Callee).Name = 'super') then
      Exit(True);
    if ExprContainsSuperCall(TFloriaJSCallExpr(target).Callee) then Exit(True);
    for i := 0 to TFloriaJSCallExpr(target).GetArgumentCount() - 1 do
      if ExprContainsSuperCall(TFloriaJSCallExpr(target).GetArgument(i)) then
        Exit(True);
    Exit(False);
  end;
  if target is TFloriaJSBinaryExpr then
    Exit(ExprContainsSuperCall(TFloriaJSBinaryExpr(target).Left) or
         ExprContainsSuperCall(TFloriaJSBinaryExpr(target).Right));
  if target is TFloriaJSUnaryExpr then
    Exit(ExprContainsSuperCall(TFloriaJSUnaryExpr(target).Operand));
  if target is TFloriaJSAssignExpr then
    Exit(ExprContainsSuperCall(TFloriaJSAssignExpr(target).Value));
  if target is TFloriaJSMemberExpr then
  begin
    if ExprContainsSuperCall(TFloriaJSMemberExpr(target).Target) then Exit(True);
    if TFloriaJSMemberExpr(target).Computed then
      Exit(ExprContainsSuperCall(TFloriaJSMemberExpr(target).PropertyExpr));
    Exit(False);
  end;
  if target is TFloriaJSArrayExpr then
  begin
    for i := 0 to TFloriaJSArrayExpr(target).GetElementCount() - 1 do
      if ExprContainsSuperCall(TFloriaJSArrayExpr(target).GetElement(i)) then
        Exit(True);
    Exit(False);
  end;
  if target is TFloriaJSConditionalExpr then
    Exit(ExprContainsSuperCall(TFloriaJSConditionalExpr(target).Condition) or
         ExprContainsSuperCall(TFloriaJSConditionalExpr(target).Consequent) or
         ExprContainsSuperCall(TFloriaJSConditionalExpr(target).Alternate));
  if target is TFloriaJSFunctionExpr then
  begin
    if not TFloriaJSFunctionExpr(target).IsArrow then
      Exit(False);
    Exit(StmtContainsSuperCall(TFloriaJSFunctionExpr(target).Body));
  end;
end;

function StmtContainsSuperCall(AStmt: TFloriaJSStmtNode): Boolean;
var
  i: Integer;
  block: TFloriaJSBlockStmt;
begin
  Result := False;
  if AStmt = nil then Exit;
  if AStmt is TFloriaJSBlockStmt then
  begin
    block := TFloriaJSBlockStmt(AStmt);
    for i := 0 to block.GetStatementCount() - 1 do
      if StmtContainsSuperCall(block.GetStatement(i)) then Exit(True);
    Exit(False);
  end;
  if AStmt is TFloriaJSReturnStmt then
    Exit(ExprContainsSuperCall(TFloriaJSReturnStmt(AStmt).Argument));
  if AStmt is TFloriaJSExprStmt then
    Exit(ExprContainsSuperCall(TFloriaJSExprStmt(AStmt).Expression));
end;

function ExprContainsArguments(AExpr: TFloriaJSExprNode): Boolean;
var
  i: Integer;
begin
  Result := False;
  if AExpr = nil then Exit;
  if AExpr is TFloriaJSIdentifierExpr then
    Exit(TFloriaJSIdentifierExpr(AExpr).Name = 'arguments');
  if AExpr is TFloriaJSGroupExpr then
    Exit(ExprContainsArguments(TFloriaJSGroupExpr(AExpr).Expression));
  if AExpr is TFloriaJSBinaryExpr then
    Exit(ExprContainsArguments(TFloriaJSBinaryExpr(AExpr).Left) or
         ExprContainsArguments(TFloriaJSBinaryExpr(AExpr).Right));
  if AExpr is TFloriaJSUnaryExpr then
    Exit(ExprContainsArguments(TFloriaJSUnaryExpr(AExpr).Operand));
  if AExpr is TFloriaJSAssignExpr then
    Exit(ExprContainsArguments(TFloriaJSAssignExpr(AExpr).Value));
  if AExpr is TFloriaJSCallExpr then
  begin
    if ExprContainsArguments(TFloriaJSCallExpr(AExpr).Callee) then Exit(True);
    for i := 0 to TFloriaJSCallExpr(AExpr).GetArgumentCount() - 1 do
      if ExprContainsArguments(TFloriaJSCallExpr(AExpr).GetArgument(i)) then
        Exit(True);
    Exit(False);
  end;
  if AExpr is TFloriaJSMemberExpr then
  begin
    if ExprContainsArguments(TFloriaJSMemberExpr(AExpr).Target) then Exit(True);
    if TFloriaJSMemberExpr(AExpr).Computed then
      Exit(ExprContainsArguments(TFloriaJSMemberExpr(AExpr).PropertyExpr));
    Exit(False);
  end;
  if AExpr is TFloriaJSArrayExpr then
  begin
    for i := 0 to TFloriaJSArrayExpr(AExpr).GetElementCount() - 1 do
      if ExprContainsArguments(TFloriaJSArrayExpr(AExpr).GetElement(i)) then
        Exit(True);
    Exit(False);
  end;
  if AExpr is TFloriaJSConditionalExpr then
    Exit(ExprContainsArguments(TFloriaJSConditionalExpr(AExpr).Condition) or
         ExprContainsArguments(TFloriaJSConditionalExpr(AExpr).Consequent) or
         ExprContainsArguments(TFloriaJSConditionalExpr(AExpr).Alternate));
  if AExpr is TFloriaJSTaggedTemplateExpr then
    Exit(ExprContainsArguments(TFloriaJSTaggedTemplateExpr(AExpr).Tag));
  if AExpr is TFloriaJSSpreadExpr then
    Exit(ExprContainsArguments(TFloriaJSSpreadExpr(AExpr).Expression));
  if AExpr is TFloriaJSFunctionExpr then
  begin
    if not TFloriaJSFunctionExpr(AExpr).IsArrow then
      Exit(False);
    Exit(StmtContainsArguments(TFloriaJSFunctionExpr(AExpr).Body));
  end;
end;

function StmtContainsArguments(AStmt: TFloriaJSStmtNode): Boolean;
var
  i: Integer;
  block: TFloriaJSBlockStmt;
begin
  Result := False;
  if AStmt = nil then Exit;
  if AStmt is TFloriaJSBlockStmt then
  begin
    block := TFloriaJSBlockStmt(AStmt);
    for i := 0 to block.GetStatementCount() - 1 do
      if StmtContainsArguments(block.GetStatement(i)) then Exit(True);
    Exit(False);
  end;
  if AStmt is TFloriaJSReturnStmt then
    Exit(ExprContainsArguments(TFloriaJSReturnStmt(AStmt).Argument));
  if AStmt is TFloriaJSExprStmt then
    Exit(ExprContainsArguments(TFloriaJSExprStmt(AStmt).Expression));
end;

{ Collects the `#name` of every private member access in an expression. Used to
  reject a private name that the class body never declares. }
procedure CollectPrivateRefs(AExpr: TFloriaJSExprNode; AInto: TStrings);
var
  i: Integer;
begin
  if (AExpr = nil) or (AInto = nil) then Exit;
  if AExpr is TFloriaJSIdentifierExpr then
  begin
    if (Length(TFloriaJSIdentifierExpr(AExpr).Name) > 0) and
       (TFloriaJSIdentifierExpr(AExpr).Name[1] = '#') then
      AInto.Add(TFloriaJSIdentifierExpr(AExpr).Name);
    Exit;
  end;
  if AExpr is TFloriaJSMemberExpr then
  begin
    if TFloriaJSMemberExpr(AExpr).IsPrivate then
      AInto.Add(TFloriaJSMemberExpr(AExpr).PropertyName);
    CollectPrivateRefs(TFloriaJSMemberExpr(AExpr).Target, AInto);
    if TFloriaJSMemberExpr(AExpr).Computed then
      CollectPrivateRefs(TFloriaJSMemberExpr(AExpr).PropertyExpr, AInto);
    Exit;
  end;
  if AExpr is TFloriaJSGroupExpr then
  begin
    CollectPrivateRefs(TFloriaJSGroupExpr(AExpr).Expression, AInto); Exit;
  end;
  if AExpr is TFloriaJSBinaryExpr then
  begin
    CollectPrivateRefs(TFloriaJSBinaryExpr(AExpr).Left, AInto);
    CollectPrivateRefs(TFloriaJSBinaryExpr(AExpr).Right, AInto); Exit;
  end;
  if AExpr is TFloriaJSUnaryExpr then
  begin
    CollectPrivateRefs(TFloriaJSUnaryExpr(AExpr).Operand, AInto); Exit;
  end;
  if AExpr is TFloriaJSAssignExpr then
  begin
    CollectPrivateRefs(TFloriaJSAssignExpr(AExpr).Target, AInto);
    CollectPrivateRefs(TFloriaJSAssignExpr(AExpr).Value, AInto); Exit;
  end;
  if AExpr is TFloriaJSCallExpr then
  begin
    CollectPrivateRefs(TFloriaJSCallExpr(AExpr).Callee, AInto);
    for i := 0 to TFloriaJSCallExpr(AExpr).GetArgumentCount() - 1 do
      CollectPrivateRefs(TFloriaJSCallExpr(AExpr).GetArgument(i), AInto);
    Exit;
  end;
  if AExpr is TFloriaJSArrayExpr then
  begin
    for i := 0 to TFloriaJSArrayExpr(AExpr).GetElementCount() - 1 do
      CollectPrivateRefs(TFloriaJSArrayExpr(AExpr).GetElement(i), AInto);
    Exit;
  end;
  if AExpr is TFloriaJSConditionalExpr then
  begin
    CollectPrivateRefs(TFloriaJSConditionalExpr(AExpr).Condition, AInto);
    CollectPrivateRefs(TFloriaJSConditionalExpr(AExpr).Consequent, AInto);
    CollectPrivateRefs(TFloriaJSConditionalExpr(AExpr).Alternate, AInto);
    Exit;
  end;
  if AExpr is TFloriaJSSpreadExpr then
    CollectPrivateRefs(TFloriaJSSpreadExpr(AExpr).Expression, AInto);
end;

{ A `#name` used in a class member must be declared by that class body. }
{ Statement-level private-reference collection, so a `this.#x` inside a method
  body is checked against the class's declared names as well. }
procedure CollectPrivateRefsStmt(AStmt: TFloriaJSStmtNode; AInto: TStrings);
var
  i: Integer;
  block: TFloriaJSBlockStmt;
  ifStmt: TFloriaJSIfStmt;
  varStmt: TFloriaJSVarStmt;
  whileStmt: TFloriaJSWhileStmt;
  forStmt: TFloriaJSForStmt;
  tryStmt: TFloriaJSTryStmt;
  labelStmt: TFloriaJSLabeledStmt;
  switchStmt: TFloriaJSSwitchStmt;
  switchCase: TFloriaJSSwitchCase;
  fnDecl: TFloriaJSFunctionDecl;

  procedure CaseBody(ACase: TFloriaJSSwitchCase);
  var k: Integer;
  begin
    if ACase = nil then Exit;
    CollectPrivateRefs(ACase.Test, AInto);
    for k := 0 to ACase.GetStatementCount() - 1 do
      CollectPrivateRefsStmt(ACase.GetStatement(k), AInto);
  end;

begin
  if (AStmt = nil) or (AInto = nil) then Exit;
  if AStmt is TFloriaJSBlockStmt then
  begin
    block := TFloriaJSBlockStmt(AStmt);
    for i := 0 to block.GetStatementCount() - 1 do
      CollectPrivateRefsStmt(block.GetStatement(i), AInto);
    Exit;
  end;
  if AStmt is TFloriaJSExprStmt then
  begin
    CollectPrivateRefs(TFloriaJSExprStmt(AStmt).Expression, AInto);
    Exit;
  end;
  if AStmt is TFloriaJSReturnStmt then
  begin
    CollectPrivateRefs(TFloriaJSReturnStmt(AStmt).Argument, AInto);
    Exit;
  end;
  if AStmt is TFloriaJSThrowStmt then
  begin
    CollectPrivateRefs(TFloriaJSThrowStmt(AStmt).Expression, AInto);
    Exit;
  end;
  if AStmt is TFloriaJSVarStmt then
  begin
    varStmt := TFloriaJSVarStmt(AStmt);
    for i := 0 to varStmt.GetDeclaratorCount() - 1 do
      CollectPrivateRefs(varStmt.GetDeclaratorInit(i), AInto);
    Exit;
  end;
  if AStmt is TFloriaJSIfStmt then
  begin
    ifStmt := TFloriaJSIfStmt(AStmt);
    CollectPrivateRefs(ifStmt.Condition, AInto);
    CollectPrivateRefsStmt(ifStmt.Consequent, AInto);
    CollectPrivateRefsStmt(ifStmt.Alternate, AInto);
    Exit;
  end;
  if AStmt is TFloriaJSWhileStmt then
  begin
    whileStmt := TFloriaJSWhileStmt(AStmt);
    CollectPrivateRefs(whileStmt.Condition, AInto);
    CollectPrivateRefsStmt(whileStmt.Body, AInto);
    Exit;
  end;
  if AStmt is TFloriaJSForStmt then
  begin
    forStmt := TFloriaJSForStmt(AStmt);
    if forStmt.Init is TFloriaJSStmtNode then
      CollectPrivateRefsStmt(TFloriaJSStmtNode(forStmt.Init), AInto);
    CollectPrivateRefs(forStmt.Test, AInto);
    CollectPrivateRefs(forStmt.Update, AInto);
    CollectPrivateRefsStmt(forStmt.Body, AInto);
    Exit;
  end;
  if AStmt is TFloriaJSTryStmt then
  begin
    tryStmt := TFloriaJSTryStmt(AStmt);
    CollectPrivateRefsStmt(tryStmt.Block, AInto);
    CollectPrivateRefsStmt(tryStmt.CatchBlock, AInto);
    CollectPrivateRefsStmt(tryStmt.FinallyBlock, AInto);
    Exit;
  end;
  if AStmt is TFloriaJSLabeledStmt then
  begin
    labelStmt := TFloriaJSLabeledStmt(AStmt);
    CollectPrivateRefsStmt(labelStmt.Body, AInto);
    Exit;
  end;
  if AStmt is TFloriaJSSwitchStmt then
  begin
    switchStmt := TFloriaJSSwitchStmt(AStmt);
    CollectPrivateRefs(switchStmt.Discriminant, AInto);
    for i := 0 to switchStmt.GetCaseCount() - 1 do
      CaseBody(switchStmt.GetCase(i));
    Exit;
  end;
  if AStmt is TFloriaJSFunctionDecl then
  begin
    fnDecl := TFloriaJSFunctionDecl(AStmt);
    CollectPrivateRefsStmt(fnDecl.Body, AInto);
  end;
end;

procedure TFloriaJSParser.ForgetClass(ACls: TFloriaJSClassNode);
var
  idx, i: Integer;
begin
  if ACls = nil then Exit;
  if FClassStack <> nil then
    for i := FClassStack.Count - 1 downto 0 do
      if TFloriaJSClassNode(FClassStack[i]) = ACls then
        FClassStack.Delete(i);
  if FPendingPrivateClasses <> nil then
  begin
    idx := FPendingPrivateClasses.IndexOf(ACls);
    if idx >= 0 then
      FPendingPrivateClasses.Delete(idx);
  end;
  if FClassParents <> nil then
  begin
    idx := FClassParents.IndexOf(IntToStr(PtrInt(ACls)));
    if idx >= 0 then
      FClassParents.Delete(idx);
  end;
end;

procedure TFloriaJSParser.ValidatePrivateNames(ACls: TFloriaJSClassNode);
var
  i, j, idx: Integer;
  refs, visible: TStringList;
  member: TFloriaJSClassMember;
  node, parent: TFloriaJSClassNode;
begin
  if ACls = nil then Exit;
  refs := TStringList.Create();
  visible := TStringList.Create();
  try
    refs.CaseSensitive := True;
    visible.CaseSensitive := True;

    { A private name is visible in its own class and in the classes that
      enclose it, never in a class nested inside it. }
    node := ACls;
    while node <> nil do
    begin
      for i := 0 to node.GetMemberCount() - 1 do
        if node.GetMember(i).IsPrivate then
          if visible.IndexOf(node.GetMember(i).Name) < 0 then
            visible.Add(node.GetMember(i).Name);
      idx := FClassParents.IndexOf(IntToStr(PtrInt(node)));
      parent := nil;
      if (idx >= 0) and (FClassParents.Objects[idx] <> nil) then
        parent := TFloriaJSClassNode(FClassParents.Objects[idx]);
      node := parent;
    end;

    for i := 0 to ACls.GetMemberCount() - 1 do
    begin
      member := ACls.GetMember(i);
      if member.Kind <> fjcmStaticBlock then
      begin
        if member.Computed then
          CollectPrivateRefs(member.NameExpr, refs);
        CollectPrivateRefs(member.Initializer, refs);
      end;
      if member.Function_ <> nil then
        CollectPrivateRefsStmt(member.Function_.Body, refs);
    end;
    for j := 0 to refs.Count - 1 do
      if visible.IndexOf(refs[j]) < 0 then
        ErrorAtCurrent('Private field ' + Chr(39) + refs[j] +
          Chr(39) + ' must be declared in an enclosing class');
  finally
    visible.Free();
    refs.Free();
  end;
end;

{ The class-element early errors that depend only on a single member: a
  `constructor` may not be a generator or async method, a non-constructor or
  static method may not call `super()`, a static element may not be named
  `prototype`, and a private name may not be `#constructor`. }
procedure TFloriaJSParser.ValidateClassMember(AMember: TFloriaJSClassMember);
var
  body: TFloriaJSStmtNode;
begin
  if AMember = nil then Exit;

  if AMember.IsPrivate and (AMember.Name = '#constructor') then
  begin
    ErrorAtCurrent('Classes may not have a private element named #constructor');
    Exit;
  end;

  if AMember.IsStatic and (not AMember.IsPrivate) and
     (AMember.Name = 'prototype') then
  begin
    ErrorAtCurrent('Classes may not have a static property named prototype');
    Exit;
  end;

  if (AMember.Kind = fjcmMethod) and (not AMember.IsStatic) and
     (AMember.Name = 'constructor') then
  begin
    if (AMember.Function_ <> nil) and
       (AMember.Function_.IsAsync or AMember.Function_.IsGenerator) then
      ErrorAtCurrent('Class constructor may not be an async or generator method');
    Exit;
  end;

  { `super()` constructs the base class and is legal only in a derived
    constructor. A static method may never call it, and neither may an ordinary
    method, including a generator or async one. An arrow inside such a method is
    transparent for `super`. }
  if (AMember.Function_ <> nil) and (AMember.Kind = fjcmMethod) then
  begin
    body := AMember.Function_.Body;
    if StmtContainsSuperCall(body) then
      ErrorAtCurrent('''super'' keyword unexpected here');
  end;
end;

function TFloriaJSParser.ParseClassExpr(AIsDeclaration: Boolean): TFloriaJSClassNode;
var
  cls: TFloriaJSClassNode;
  startLine, startCol, classStartPos: Integer;
  clsName, memberName: string;
  superClass: TFloriaJSExprNode;
  isStatic: Boolean;
  kind: TFloriaJSClassMemberKind;
  memberStartPos: Integer;
  fnExpr: TFloriaJSFunctionExpr;
  member: TFloriaJSClassMember;
  fieldInit: TFloriaJSExprNode;
  memberIsPrivate, memberIsAsync, memberIsGenerator: Boolean;
  computedNameExpr: TFloriaJSExprNode;
  wasSuperAllowed, wasInStaticBlock: Boolean;
  savedStaticDepth: Integer;
  i, j: Integer;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  classStartPos := FPrevious.StartPos;

  clsName := '';
  if Match(tkIdentifier) then
    clsName := FPrevious.Text;

  superClass := nil;
  if Match(tkExtends) then
    { ClassHeritage is a LeftHandSideExpression, so the heritage may be a
      call, a member access, or `new`. Parsing it at primary precedence stopped
      at `fn(await foo)` and reported a missing class body. }
    superClass := ParsePrecedence(PREC_UNARY);

  cls := TFloriaJSClassNode.Create(clsName, superClass, startLine, startCol);
  cls.IsDeclaration := AIsDeclaration;
  FClassStack.Add(cls);

  Consume(tkLBrace, 'Expected ''{'' at start of class body');

  { A bare `super` is only meaningful in a class. }
  wasSuperAllowed := FSuperAllowed;
  FSuperAllowed := True;
  Inc(FClassDepth);
  { A fresh outermost class starts a fresh private-name scope. }
  if FClassDepth = 1 then
  begin
    FDeclaredPrivates.Clear();
    FPendingPrivateClasses.Clear();
    FClassParents.Clear();
  end;

  while (not Check(tkRBrace)) and (not IsAtEnd()) do
  begin
    if Match(tkSemicolon) then
      Continue;

    { `static { ... }` is an initializer block, not a member. }
    if Check(tkStatic) and (FLexer.PeekToken().Kind = tkLBrace) then
    begin
      Advance(); { consume `static` }
      fnExpr := TFloriaJSFunctionExpr.Create('#static-block', False,
        FCurrent.Line, FCurrent.Column);
      { `return` and `yield` are illegal in a static block, and `await` is only
        legal as a binding name, so the body is parsed as a plain block whose
        function depth stays at the enclosing level. }
      wasInStaticBlock := FInStaticBlock;
      savedStaticDepth := FStaticBlockDepth;
      FInStaticBlock := True;
      FStaticBlockDepth := FFunctionDepth;
      try
        fnExpr.SetBody(ParseBlockStatement());
      finally
        FInStaticBlock := wasInStaticBlock;
        FStaticBlockDepth := savedStaticDepth;
      end;
      fnExpr.SourceText := SourceSlice(memberStartPos, FPrevious.EndPos);
      cls.AddMember(TFloriaJSClassMember.Create('#static-block',
        fjcmStaticBlock, True, fnExpr, startLine, startCol));
      Continue;
    end;

    { A class member is `[static] [async] [*] PropertyName`, or a `get`/`set`
      accessor. Each modifier is only a modifier when a property name follows
      it, so `static()`, `async = 1`, and `get() {}` still name members. }
    isStatic := False;
    if Check(tkStatic) and StartsPropertyName(FLexer.PeekToken().Kind) then
    begin
      Advance();
      isStatic := True;
    end;

    kind := fjcmMethod;
    memberStartPos := FCurrent.StartPos;
    memberIsAsync := False;
    memberIsGenerator := False;

    { get/set accessors, when a property name follows. }
    if (FCurrent.Kind = tkIdentifier) and
       ((FCurrent.Text = 'get') or (FCurrent.Text = 'set')) and
       StartsPropertyName(FLexer.PeekToken().Kind) and
       (FLexer.PeekToken().Kind <> tkMultiply) and
       (FLexer.PeekToken().Line = FCurrent.Line) then
    begin
      if FCurrent.Text = 'get' then kind := fjcmGetter else kind := fjcmSetter;
      Advance();
    end
    else if (FCurrent.Kind = tkIdentifier) and (FCurrent.Text = 'accessor') and
            StartsPropertyName(FLexer.PeekToken().Kind) and
            (FLexer.PeekToken().Kind <> tkMultiply) and
            (FLexer.PeekToken().Line = FCurrent.Line) then
    begin
      { `accessor x` declares a getter/setter pair with a backing field. The
        syntax is accepted and the member is treated as a plain field; the
        accessor semantics themselves are not implemented. }
      Advance();
    end
    else if (FCurrent.Kind = tkAsync) and
            StartsPropertyName(FLexer.PeekToken().Kind) and
            (FLexer.PeekToken().Kind <> tkAssign) and
            (FLexer.PeekToken().Kind <> tkSemicolon) and
            (FLexer.PeekToken().Line = FCurrent.Line) then
    begin
      { An async method or async generator method. }
      Advance();
      memberIsAsync := True;
      if Match(tkMultiply) then
        memberIsGenerator := True;
    end
    else if Check(tkMultiply) then
    begin
      { A generator method: `*m() {}`. }
      Advance();
      memberIsGenerator := True;
    end;

    memberIsPrivate := False;
    memberName := '';
    computedNameExpr := nil;
    if Match(tkLBracket) then
    begin
      { A computed member name: `[expr]() {}` or `[expr] = value`. The key is
        evaluated at class-definition time, in source order. }
      computedNameExpr := ParseAssignmentExpression();
      Consume(tkRBracket, 'Expected '']'' after a computed member name');
      memberName := '';
    end
    else if Match(tkPrivateName) then
    begin
      memberName := FPrevious.Text;
      memberIsPrivate := True;
    end
    else if Match(tkIdentifier) then
      memberName := FPrevious.Text
    else if IsKeywordToken(FCurrent.Kind) then
    begin
      { Keywords are legal member names: `class A { delete() {} }`. }
      memberName := FCurrent.Text;
      Advance();
    end
    else if Match(tkString) then
      memberName := FPrevious.Text
    else if Match(tkNumber) then
      memberName := FPrevious.Text
    else
    begin
      ErrorAtCurrent('Expected a method name in class body');
      Break;
    end;

    if Check(tkLParen) then
    begin
      fnExpr := ParseMethodBody(memberName, memberStartPos, memberIsAsync,
        memberIsGenerator);
      member := TFloriaJSClassMember.Create(memberName, kind, isStatic,
        fnExpr, startLine, startCol);
      member.IsPrivate := memberIsPrivate;
      if computedNameExpr <> nil then
      begin
        member.Computed := True;
        member.NameExpr := computedNameExpr;
      end;
      ValidateClassMember(member);
      cls.AddMember(member);
      Continue;
    end;

    { A field: an optional initializer followed by `;` or the next member. }
    fieldInit := nil;
    if Match(tkAssign) then
    begin
      fieldInit := ParseAssignmentExpression();
      { A field initializer is not a function body, so it may not reference
        `arguments`. }
      if ExprContainsArguments(fieldInit) then
        ErrorAtCurrent('''arguments'' is not allowed in a class field initializer');
      if ExprContainsSuperCall(fieldInit) then
        ErrorAtCurrent('''super'' is not allowed in a class field initializer');
    end;
    member := TFloriaJSClassMember.Create(memberName, fjcmField, isStatic,
      nil, startLine, startCol);
    member.IsPrivate := memberIsPrivate;
    if computedNameExpr <> nil then
    begin
      member.Computed := True;
      member.NameExpr := computedNameExpr;
    end;
    member.Initializer := fieldInit;
    ValidateClassMember(member);
    cls.AddMember(member);
    { A field declaration ends at a semicolon, the class body's close, or a line
      terminator (ASI). Anything else is a syntax error, which is what makes
      `\u0061sync* m(){}` invalid rather than two members. }
    if (not Match(tkSemicolon)) and (not Check(tkRBrace)) and
       (not IsAtEnd()) and (not HasLineBreakBeforeCurrent()) then
      ErrorAtCurrent('Expected '';'' after a class field');
  end;

  Consume(tkRBrace, 'Expected ''}'' at end of class body');
  { A private name may be declared once per class body, except for one getter
    and one setter with the same name. Nested classes have their own scope, so
    the check only looks at this body's own members. }
  for i := 0 to cls.GetMemberCount() - 1 do
  begin
    if not cls.GetMember(i).IsPrivate then Continue;
    for j := 0 to i - 1 do
    begin
      if (not cls.GetMember(j).IsPrivate) or
         (cls.GetMember(j).Name <> cls.GetMember(i).Name) then
        Continue;
      { A getter and a setter may share a name; anything else may not. }
      if (cls.GetMember(j).Kind in [fjcmGetter, fjcmSetter]) and
         (cls.GetMember(i).Kind in [fjcmGetter, fjcmSetter]) and
         (cls.GetMember(j).Kind <> cls.GetMember(i).Kind) then
        Continue;
      ErrorAtCurrent('Duplicate private name ''' + cls.GetMember(i).Name + '''');
      Break;
    end;
  end;
  for i := 0 to cls.GetMemberCount() - 1 do
    if cls.GetMember(i).IsPrivate then
      FDeclaredPrivates.Add(cls.GetMember(i).Name);
  { Record this class and the class that encloses it. }
  if FClassStack.Count > 0 then
    FClassStack.Delete(FClassStack.Count - 1);
  if FClassStack.Count > 0 then
    FClassParents.AddObject(IntToStr(PtrInt(cls)),
      TObject(FClassStack[FClassStack.Count - 1]))
  else
    FClassParents.AddObject(IntToStr(PtrInt(cls)), nil);
  FPendingPrivateClasses.Add(cls);
  Dec(FClassDepth);
  FSuperAllowed := wasSuperAllowed;
  cls.SourceText := SourceSlice(classStartPos, FPrevious.EndPos);
  { Validate only once the outermost class body is complete: a nested class may
    refer to a private name its enclosing class declares later in the source. }
  if FClassDepth = 0 then
  begin
    for i := 0 to FPendingPrivateClasses.Count - 1 do
      ValidatePrivateNames(TFloriaJSClassNode(FPendingPrivateClasses[i]));
    FPendingPrivateClasses.Clear();
  end;
  Result := cls;
end;

function TFloriaJSParser.SourceSlice(AStartPos, AEndPos: Integer): string;
begin
  if (AStartPos >= 1) and (AEndPos >= AStartPos) then
    Result := Copy(FLexer.Source, AStartPos, AEndPos - AStartPos + 1)
  else
    Result := '';
end;

function TFloriaJSParser.ParseMethodBody(const AName: string; AStartPos: Integer;
  AIsAsync: Boolean = False; AIsGenerator: Boolean = False): TFloriaJSFunctionExpr;
var
  fnExpr: TFloriaJSFunctionExpr;
  startLine, startCol: Integer;
  bodyStmt: TFloriaJSStmtNode;
  savedGenParams: Boolean;
begin
  startLine := FCurrent.Line;
  startCol := FCurrent.Column;

  fnExpr := TFloriaJSFunctionExpr.Create(AName, False, startLine, startCol);
  fnExpr.IsAsync := AIsAsync;
  fnExpr.IsGenerator := AIsGenerator;
  savedGenParams := FInGeneratorParams;
  if AIsGenerator then FInGeneratorParams := True;
  try
    ParseFormalParameters(fnExpr.Parameters);
  finally
    FInGeneratorParams := savedGenParams;
  end;
  if AIsAsync and AIsGenerator then
  begin
    Inc(FGeneratorDepth);
    try
      bodyStmt := ParseAsyncFunctionBlockBody();
    finally
      Dec(FGeneratorDepth);
    end;
  end
  else if AIsGenerator then
    bodyStmt := ParseGeneratorBlockBody()
  else if AIsAsync then
    bodyStmt := ParseAsyncFunctionBlockBody()
  else
    bodyStmt := ParseFunctionBlockBody();
  fnExpr.SetBody(bodyStmt);
  fnExpr.SourceText := SourceSlice(AStartPos, FPrevious.EndPos);
  Result := fnExpr;
end;

function TFloriaJSParser.ParseObjectLiteral(): TFloriaJSExprNode;
var
  obj: TFloriaJSObjectExpr;
  startLine, startCol: Integer;
  propKey, realKey: string;
  propVal, keyExpr: TFloriaJSExprNode;
  methodFn: TFloriaJSFunctionExpr;
  memberStartPos: Integer;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  obj := TFloriaJSObjectExpr.Create(startLine, startCol);

  while (not Check(tkRBrace)) and (not IsAtEnd()) do
  begin
    // 1. Spread: ...expr
    if Match(tkEllipsis) then
    begin
      obj.AddSpreadProperty(ParseAssignmentExpression());
      if not Check(tkRBrace) then
        Consume(tkComma, 'Expected '','' or ''}'' after spread property');
      Continue;
    end;

    // 2. Computed property: [expr]: val, or [expr]() { ... }
    if Match(tkLBracket) then
    begin
      memberStartPos := FPrevious.StartPos;
      keyExpr := ParseAssignmentExpression();
      Consume(tkRBracket, 'Expected '']'' after computed property name');

      if Match(tkColon) then
      begin
        propVal := ParseAssignmentExpression();
        obj.AddComputedProperty(keyExpr, propVal);
      end
      else if Check(tkLParen) then
      begin
        methodFn := ParseMethodBody('', memberStartPos);
        obj.AddComputedProperty(keyExpr, methodFn);
      end
      else
        ErrorAtCurrent('Expected '':'' or ''('' after computed property name');

      if not Check(tkRBrace) then
        Consume(tkComma, 'Expected '','' or ''}'' after property');
      Continue;
    end;

    // 3. Identifier / Keyword / String / Number key
    if Match(tkIdentifier) or Match(tkString) or Match(tkNumber) then
      propKey := FPrevious.Text
    else if IsKeywordToken(FCurrent.Kind) then
    begin
      propKey := FCurrent.Text;
      Advance();
    end
    else
    begin
      ErrorAtCurrent('Expected property key in object literal');
      Break;
    end;

    // Check for getter: get x() { ... } or get [k]() { ... }
    if (propKey = 'get') and (not Check(tkColon)) and (not Check(tkComma)) and (not Check(tkRBrace)) and (not Check(tkLParen)) then
    begin
      memberStartPos := FPrevious.StartPos;
      if Match(tkLBracket) then
      begin
        keyExpr := ParseAssignmentExpression();
        Consume(tkRBracket, 'Expected '']'' after computed getter name');
        methodFn := ParseMethodBody('', memberStartPos);
        obj.AddGetter('', methodFn, keyExpr);
      end
      else
      begin
        if Match(tkIdentifier) or Match(tkString) then
          realKey := FPrevious.Text
        else if IsKeywordToken(FCurrent.Kind) then
        begin
          realKey := FCurrent.Text;
          Advance();
        end
        else
        begin
          ErrorAtCurrent('Expected getter name');
          realKey := '';
        end;
        methodFn := ParseMethodBody(realKey, memberStartPos);
        obj.AddGetter(realKey, methodFn);
      end;
    end
    // Check for setter: set x(v) { ... } or set [k](v) { ... }
    else if (propKey = 'set') and (not Check(tkColon)) and (not Check(tkComma)) and (not Check(tkRBrace)) and (not Check(tkLParen)) then
    begin
      memberStartPos := FPrevious.StartPos;
      if Match(tkLBracket) then
      begin
        keyExpr := ParseAssignmentExpression();
        Consume(tkRBracket, 'Expected '']'' after computed setter name');
        methodFn := ParseMethodBody('', memberStartPos);
        obj.AddSetter('', methodFn, keyExpr);
      end
      else
      begin
        if Match(tkIdentifier) or Match(tkString) then
          realKey := FPrevious.Text
        else if IsKeywordToken(FCurrent.Kind) then
        begin
          realKey := FCurrent.Text;
          Advance();
        end
        else
        begin
          ErrorAtCurrent('Expected setter name');
          realKey := '';
        end;
        methodFn := ParseMethodBody(realKey, memberStartPos);
        obj.AddSetter(realKey, methodFn);
      end;
    end
    // Method syntax: f() { ... }
    else if Check(tkLParen) then
    begin
      methodFn := ParseMethodBody(propKey, FPrevious.StartPos);
      obj.AddProperty(propKey, methodFn);
    end
    // Shorthand syntax: { x }
    else if Check(tkComma) or Check(tkRBrace) then
    begin
      obj.AddProperty(propKey, TFloriaJSIdentifierExpr.Create(propKey, startLine, startCol));
    end
    // Destructuring default shorthand: { x = expr }
    else if Match(tkAssign) then
    begin
      propVal := ParseAssignmentExpression();
      obj.AddProperty(propKey, TFloriaJSAssignExpr.Create(
        TFloriaJSIdentifierExpr.Create(propKey, startLine, startCol),
        tkAssign,
        propVal,
        startLine, startCol
      ));
    end
    // Standard property: key: value
    else
    begin
      Consume(tkColon, 'Expected '':'' after object property key');
      propVal := ParseAssignmentExpression();
      obj.AddProperty(propKey, propVal);
    end;

    if not Check(tkRBrace) then
      Consume(tkComma, 'Expected '','' or ''}'' after property');
  end;

  Consume(tkRBrace, 'Expected ''}'' after object literal');
  Result := obj;
end;

{ Parses an arrow body. A block body may contain `return`; an expression body
  is a concise return. An async arrow makes `await` legal in either form. }
procedure TFloriaJSParser.ParseArrowBody(AAsync: Boolean;
  AFnExpr: TFloriaJSFunctionExpr);
begin
  Inc(FFunctionDepth);
  if AAsync then Inc(FAsyncDepth);
  try
    if Check(tkLBrace) then
      AFnExpr.SetBody(ParseBlockStatement())
    else
      AFnExpr.SetBody(TFloriaJSReturnStmt.Create(ParseAssignmentExpression(),
        FPrevious.Line, FPrevious.Column));
  finally
    if AAsync then Dec(FAsyncDepth);
    Dec(FFunctionDepth);
  end;
end;

{ Parses a block that is a function body, counting the function so `return`
  is legal inside it and an early error outside. An async body additionally
  makes `await` legal. }
{ Parses a function body, marking it as a generator body while it is parsed so
  `yield` is reserved inside. }
function TFloriaJSParser.ParseGeneratorBlockBody(): TFloriaJSStmtNode;
begin
  Inc(FFunctionDepth);
  Inc(FGeneratorDepth);
  try
    Result := ParseBlockStatement();
  finally
    Dec(FGeneratorDepth);
    Dec(FFunctionDepth);
  end;
end;

function TFloriaJSParser.ParseFunctionBlockBody(): TFloriaJSStmtNode;
begin
  Inc(FFunctionDepth);
  try
    Result := ParseBlockStatement();
  finally
    Dec(FFunctionDepth);
  end;
end;

{ The same, for an async function or generator whose body may await. }
function TFloriaJSParser.ParseAsyncFunctionBlockBody(): TFloriaJSStmtNode;
begin
  Inc(FFunctionDepth);
  Inc(FAsyncDepth);
  try
    Result := ParseBlockStatement();
  finally
    Dec(FAsyncDepth);
    Dec(FFunctionDepth);
  end;
end;

function TFloriaJSParser.ParseFunctionExpr(AIsAsync: Boolean = False; AStartPos: Integer = -1): TFloriaJSExprNode;
var
  fnName: string;
  fnExpr: TFloriaJSFunctionExpr;
  startLine, startCol, startPos: Integer;
  bodyStmt: TFloriaJSStmtNode;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  if AStartPos >= 0 then
    startPos := AStartPos
  else
    startPos := FPrevious.StartPos;

  if Match(tkIdentifier) then
    fnName := FPrevious.Text
  else
    fnName := '';

  fnExpr := TFloriaJSFunctionExpr.Create(fnName, False, startLine, startCol, AIsAsync);
  ParseFormalParameters(fnExpr.Parameters);
  if AIsAsync then
    bodyStmt := ParseAsyncFunctionBlockBody()
  else
    bodyStmt := ParseFunctionBlockBody();
  fnExpr.SetBody(bodyStmt);
  fnExpr.SourceText := SourceSlice(startPos, FPrevious.EndPos);
  Result := fnExpr;
end;

{ Early errors for a binding pattern: a rest element must be last and may not
  have an initializer. Applies to formal parameters, not to an array literal
  used as an expression. }
procedure ValidateBindingPattern(AExpr: TFloriaJSExprNode;
  const AContext: string; var AError: string);
var
  i: Integer;
  arr: TFloriaJSArrayExpr;
  obj: TFloriaJSObjectExpr;
  elem: TFloriaJSExprNode;
begin
  if (AExpr = nil) or (AError <> '') then Exit;
  if AExpr is TFloriaJSGroupExpr then
  begin
    ValidateBindingPattern(TFloriaJSGroupExpr(AExpr).Expression, AContext, AError);
    Exit;
  end;
  if AExpr is TFloriaJSAssignExpr then
  begin
    ValidateBindingPattern(TFloriaJSAssignExpr(AExpr).Target, AContext, AError);
    Exit;
  end;
  if AExpr is TFloriaJSSpreadExpr then
  begin
    elem := TFloriaJSSpreadExpr(AExpr).Expression;
    if elem is TFloriaJSAssignExpr then
      AError := 'A rest element may not have an initializer in ' + AContext;
    Exit;
  end;
  if AExpr is TFloriaJSArrayExpr then
  begin
    arr := TFloriaJSArrayExpr(AExpr);
    for i := 0 to arr.GetElementCount() - 1 do
    begin
      elem := arr.GetElement(i);
      if elem is TFloriaJSSpreadExpr then
      begin
        if i <> arr.GetElementCount() - 1 then
          AError := 'A rest element must be last in ' + AContext;
        ValidateBindingPattern(elem, AContext, AError);
        Exit;
      end;
      ValidateBindingPattern(elem, AContext, AError);
    end;
    Exit;
  end;
  if AExpr is TFloriaJSObjectExpr then
  begin
    obj := TFloriaJSObjectExpr(AExpr);
    for i := 0 to obj.GetPropertyCount() - 1 do
      ValidateBindingPattern(obj.GetPropertyValue(i), AContext, AError);
  end;
end;

procedure TFloriaJSParser.ParseFormalParameters(AParams: TStringList);
var
  paramName: string;
  defaultExpr, pat: TFloriaJSExprNode;
  patternError: string;
begin
  Consume(tkLParen, 'Expected ''('' before parameter list');
  if not Check(tkRParen) then
  begin
    repeat
      // 1. Rest parameter: ...name
      if Match(tkEllipsis) then
      begin
        if Match(tkIdentifier) then
          paramName := '...' + FPrevious.Text
        else
        begin
          ErrorAtCurrent('Expected parameter name after ''...''');
          paramName := '...args';
        end;
        { A rest parameter may not carry an initializer. }
        if Check(tkAssign) then
          ErrorAtCurrent('A rest parameter may not have an initializer');
        AParams.Add(paramName);
        Break; // Rest parameter must be last
      end;

      // 2. Destructuring pattern: [a, b] or { a, b }
      if Check(tkLBracket) then
      begin
        Advance();
        pat := ParseArrayLiteral();
        patternError := '';
        ValidateBindingPattern(pat, 'a parameter list', patternError);
        if patternError <> '' then
          ErrorAtCurrent(patternError);
        if Match(tkAssign) then
          defaultExpr := ParseAssignmentExpression()
        else
          defaultExpr := nil;
        if defaultExpr <> nil then
          AParams.AddObject('', TFloriaJSAssignExpr.Create(pat, tkAssign, defaultExpr, pat.Line, pat.Column))
        else
          AParams.AddObject('', pat);
      end
      else if Check(tkLBrace) then
      begin
        Advance();
        pat := ParseObjectLiteral();
        patternError := '';
        ValidateBindingPattern(pat, 'a parameter list', patternError);
        if patternError <> '' then
          ErrorAtCurrent(patternError);
        if Match(tkAssign) then
          defaultExpr := ParseAssignmentExpression()
        else
          defaultExpr := nil;
        if defaultExpr <> nil then
          AParams.AddObject('', TFloriaJSAssignExpr.Create(pat, tkAssign, defaultExpr, pat.Line, pat.Column))
        else
          AParams.AddObject('', pat);
      end
      // 3. Normal parameter: identifier [ = default ]
      else if Match(tkIdentifier) then
      begin
        paramName := FPrevious.Text;
        if Match(tkAssign) then
          defaultExpr := ParseAssignmentExpression()
        else
          defaultExpr := nil;
        AParams.AddObject(paramName, defaultExpr);
      end
      else
      begin
        ErrorAtCurrent('Expected parameter name');
        Break;
      end;
      if not Match(tkComma) then
        Break;
      if Check(tkRParen) then
        Break;
    until False;
  end;
  Consume(tkRParen, 'Expected '')'' after function parameter list');
end;

function TFloriaJSParser.ExtractParameters(var AExpr: TFloriaJSExprNode; AParams: TStrings): Boolean;
var
  bin: TFloriaJSBinaryExpr;
  leftNode, rightNode, innerNode, targetNode, valNode: TFloriaJSExprNode;
  assignNode: TFloriaJSAssignExpr;
  spreadNode: TFloriaJSSpreadExpr;
begin
  if AExpr = nil then
    Exit(True);

  if AExpr is TFloriaJSIdentifierExpr then
  begin
    AParams.Add(TFloriaJSIdentifierExpr(AExpr).Name);
    Exit(True);
  end;

  if AExpr is TFloriaJSGroupExpr then
  begin
    innerNode := TFloriaJSGroupExpr(AExpr).ExtractExpression();
    Result := ExtractParameters(innerNode, AParams);
    if innerNode <> nil then innerNode.Free();
    Exit;
  end;

  if (AExpr is TFloriaJSBinaryExpr) and (TFloriaJSBinaryExpr(AExpr).Op = tkComma) then
  begin
    bin := TFloriaJSBinaryExpr(AExpr);
    leftNode := bin.ExtractLeft();
    rightNode := bin.ExtractRight();
    Result := ExtractParameters(leftNode, AParams) and
              ExtractParameters(rightNode, AParams);
    if leftNode <> nil then leftNode.Free();
    if rightNode <> nil then rightNode.Free();
    Exit;
  end;

  if AExpr is TFloriaJSSpreadExpr then
  begin
    spreadNode := TFloriaJSSpreadExpr(AExpr);
    innerNode := spreadNode.ExtractExpression();
    if innerNode is TFloriaJSIdentifierExpr then
    begin
      AParams.Add('...' + TFloriaJSIdentifierExpr(innerNode).Name);
      innerNode.Free();
      Result := True;
    end
    else
    begin
      if innerNode <> nil then innerNode.Free();
      Result := False;
    end;
    Exit;
  end;

  if AExpr is TFloriaJSAssignExpr then
  begin
    assignNode := TFloriaJSAssignExpr(AExpr);
    targetNode := assignNode.ExtractTarget();
    valNode := assignNode.ExtractValue();
    if targetNode is TFloriaJSIdentifierExpr then
    begin
      AParams.AddObject(TFloriaJSIdentifierExpr(targetNode).Name, valNode);
      targetNode.Free();
      Result := True;
    end
    else if (targetNode is TFloriaJSObjectExpr) or (targetNode is TFloriaJSArrayExpr) then
    begin
      AParams.AddObject('', TFloriaJSAssignExpr.Create(targetNode, tkAssign, valNode, targetNode.Line, targetNode.Column));
      Result := True;
    end
    else
    begin
      if targetNode <> nil then targetNode.Free();
      if valNode <> nil then valNode.Free();
      Result := False;
    end;
    Exit;
  end;

  if (AExpr is TFloriaJSObjectExpr) or (AExpr is TFloriaJSArrayExpr) then
  begin
    AParams.AddObject('', AExpr);
    AExpr := nil;
    Exit(True);
  end;

  Result := False;
end;

function TFloriaJSParser.ParsePrecedence(APrec: Integer): TFloriaJSExprNode;
var
  left: TFloriaJSExprNode;
  op: TFloriaJSToken;
  prec, nextPrec: Integer;
  right: TFloriaJSExprNode;
  consequent, alternate: TFloriaJSExprNode;
  callExpr: TFloriaJSCallExpr;
  fnExpr: TFloriaJSFunctionExpr;
  memberPropName: string;
  computedProp: TFloriaJSExprNode;
  memberExpr: TFloriaJSMemberExpr;
  memberIsPrivate: Boolean;
  savedYield: Boolean;
  startPos: Integer;
begin
  { Prefix parsing }
  if FCurrent.Kind = tkNew then
  begin
    op := FCurrent;
    Advance();
    { `new.target` is a meta-property, not a construction. }
    if Check(tkDot) and (FLexer.PeekToken().Kind = tkIdentifier) and
       (FLexer.PeekToken().Text = 'target') then
    begin
      Advance(); { consume '.' }
      Advance(); { consume 'target' }
      { `new.target` is legal in a function body, a class field initializer,
        and a static block, but not at the top level of a script or module. }
      { In eval code `new.target` is illegal everywhere unless it is a direct
        eval; outside eval it depends on the enclosing context. }
      if (FIsEvalCode and (not FAllowEvalMeta)) or
         ((not FIsEvalCode) and (FFunctionDepth = 0) and (FClassDepth = 0)
          and (not FInStaticBlock)) then
        ErrorAtCurrent('''new.target'' expression is only allowed within functions or class bodies');
      left := TFloriaJSIdentifierExpr.Create('new.target', op.Line, op.Column);
    end
    else
      left := ParseNewExpression(op);
  end
  else if FCurrent.Kind in [tkNot, tkBitNot, tkMinus, tkPlus, tkPlusPlus, tkMinusMinus, tkTypeof, tkDelete, tkVoid, tkAwait, tkEllipsis] then
    left := ParseUnaryPrefix()
  else
    left := ParsePrimary();

  { Infix parsing }
  while not IsAtEnd() do
  begin
    prec := GetInfixPrecedence(FCurrent.Kind);
    if prec < APrec then
      Break;

    { A template literal after an expression is a tagged template; the token
      is consumed by ParseTaggedTemplate. }
    if FCurrent.Kind in [tkTemplateString, tkTemplateHead] then
    begin
      left := ParseTaggedTemplate(left);
      Continue;
    end;

    { Postfix ++/-- is a restricted production: a line terminator before the
      operator ends the previous statement instead of applying the operator. }
    if (FCurrent.Kind in [tkPlusPlus, tkMinusMinus]) and HasLineBreakBeforeCurrent() then
      Break;

    op := FCurrent;
    Advance();

    case op.Kind of
      { Function Call: (arg1, arg2) }
      tkLParen:
      begin
        callExpr := TFloriaJSCallExpr.Create(left, op.Line, op.Column);
        if not Check(tkRParen) then
        begin
          repeat
            if Check(tkRParen) then
              Break;
            if Match(tkEllipsis) then
          callExpr.AddArgument(TFloriaJSSpreadExpr.Create(ParseAssignmentExpression(), FPrevious.Line, FPrevious.Column))
        else
          callExpr.AddArgument(ParseAssignmentExpression());
          until not Match(tkComma);
        end;
        Consume(tkRParen, 'Expected '')'' after argument list');
        left := callExpr;
      end;

      { Member Access: obj.prop, obj?.prop, obj?.[expr], obj?.() }
      tkDot, tkQuestionDot:
      begin
        if (op.Kind = tkQuestionDot) and (FCurrent.Kind = tkLParen) then
        begin
          Advance(); { Consume '(' }
          callExpr := TFloriaJSCallExpr.Create(left, op.Line, op.Column, False, True);
          if not Check(tkRParen) then
          begin
            repeat
              if Check(tkRParen) then
                Break;
              if Match(tkEllipsis) then
          callExpr.AddArgument(TFloriaJSSpreadExpr.Create(ParseAssignmentExpression(), FPrevious.Line, FPrevious.Column))
        else
          callExpr.AddArgument(ParseAssignmentExpression());
            until not Match(tkComma);
          end;
          Consume(tkRParen, 'Expected '')'' after optional call arguments');
          left := callExpr;
        end
        else if FCurrent.Kind = tkLBracket then
        begin
          Advance(); { Consume '[' }
          computedProp := ParseExpression();
          Consume(tkRBracket, 'Expected '']'' after computed property accessor');
          left := TFloriaJSMemberExpr.CreateComputed(left, computedProp,
            op.Line, op.Column, op.Kind = tkQuestionDot);
        end
        else
        begin
          memberIsPrivate := False;
          if Match(tkPrivateName) then
          begin
            memberPropName := FPrevious.Text;
            memberIsPrivate := True;
            if FClassDepth = 0 then
              ErrorAtCurrent('Private field must be declared in an enclosing class');
          end
          else if Match(tkIdentifier) then
            memberPropName := FPrevious.Text
          else if IsKeywordToken(FCurrent.Kind) then
          begin
            memberPropName := FCurrent.Text;
            Advance();
          end
          else
          begin
            ErrorAtCurrent('Expected property name after ''.''');
            memberPropName := '';
          end;
          memberExpr := TFloriaJSMemberExpr.CreateNamed(left, memberPropName,
            op.Line, op.Column, op.Kind = tkQuestionDot);
          memberExpr.IsPrivate := memberIsPrivate;
          left := memberExpr;
        end;
      end;

      { Computed Member: obj[expr] }
      tkLBracket:
      begin
        computedProp := ParseExpression();
        Consume(tkRBracket, 'Expected '']'' after computed property accessor');
        left := TFloriaJSMemberExpr.CreateComputed(left, computedProp, op.Line, op.Column);
      end;

      { Conditional Ternary: cond ? consequent : alternate }
      tkQuestion:
      begin
        consequent := ParseAssignmentExpression();
        Consume(tkColon, 'Expected '':'' in ternary conditional expression');
        alternate := ParseAssignmentExpression();
        left := TFloriaJSConditionalExpr.Create(left, consequent, alternate, op.Line, op.Column);
      end;

      { Assignment Operators: =, +=, -=, *=, /=, %=, **=, ??=, &&=, ||= }
      tkAssign, tkPlusAssign, tkMinusAssign, tkMultiplyAssign, tkDivideAssign, tkModuloAssign,
      tkPowerAssign, tkNullishAssign, tkAndAssign, tkOrAssign,
      tkBitAndAssign, tkBitOrAssign, tkBitXorAssign,
      tkShiftLeftAssign, tkShiftRightAssign, tkShiftRightUnsignedAssign:
      begin
        if IsOptionalChainTarget(left) then
          ErrorAtCurrent('Invalid left-hand side in assignment');
        if (op.Kind <> tkAssign) and (not IsSimpleAssignmentTarget(left)) then
          ErrorAtCurrent('Invalid left-hand side in assignment');
        right := ParsePrecedence(PREC_ASSIGNMENT);
        left := TFloriaJSAssignExpr.Create(left, op.Kind, right, op.Line, op.Column);
      end;

      { Arrow Function: x => expr or x => { statements } }
      tkArrow:
      begin
        if left is TFloriaJSIdentifierExpr then
        begin
          startPos := left.SourceStart;
          fnExpr := TFloriaJSFunctionExpr.Create('', True, left.Line, left.Column);
          fnExpr.AddParameter(TFloriaJSIdentifierExpr(left).Name);
          left.Free();
          if Check(tkLBrace) then
            fnExpr.SetBody(ParseFunctionBlockBody())
          else
            fnExpr.SetBody(TFloriaJSReturnStmt.Create(ParseAssignmentExpression(), op.Line, op.Column));
          fnExpr.SourceText := SourceSlice(startPos, FPrevious.EndPos);
          left := fnExpr;
        end
        else
        begin
          ErrorAtCurrent('Invalid arrow function parameter');
        end;
      end;

      { Postfix Increment / Decrement: x++, x-- }
      tkPlusPlus, tkMinusMinus:
      begin
        if IsOptionalChainTarget(left) then
          ErrorAtCurrent('Invalid left-hand side in postfix operation');
        if not IsSimpleAssignmentTarget(left) then
          ErrorAtCurrent('Invalid left-hand side in postfix operation');
        left := TFloriaJSUnaryExpr.Create(op.Kind, left, False, op.Line, op.Column);
      end;

    else
      { Standard Binary Infix Operators }
      if op.Kind = tkPower then
        nextPrec := prec { Exponentiation is right-associative }
      else
        nextPrec := prec + 1;

      { A binary operand is not an AssignmentExpression position, so a
        YieldExpression may not start it: `yield 3 + yield 4` is an early
        error. The comma operator is exempt: its right operand *is* an
        AssignmentExpression, so `yield 1, yield 2` is legal. }
      if op.Kind = tkComma then
        right := ParsePrecedence(nextPrec)
      else
      begin
        savedYield := FYieldExprAllowed;
        FYieldExprAllowed := False;
        try
          right := ParsePrecedence(nextPrec);
        finally
          FYieldExprAllowed := savedYield;
        end;
      end;
      left := TFloriaJSBinaryExpr.Create(left, op.Kind, right, op.Line, op.Column);
    end;
  end;

  Result := left;
end;

function TFloriaJSParser.ParseAssignmentExpression(): TFloriaJSExprNode;
var
  savedYield: Boolean;
begin
  { A YieldExpression is only legal at the AssignmentExpression level. }
  savedYield := FYieldExprAllowed;
  FYieldExprAllowed := True;
  try
    Result := ParsePrecedence(PREC_ASSIGNMENT);
  finally
    FYieldExprAllowed := savedYield;
  end;
end;

function TFloriaJSParser.ParseExpression(): TFloriaJSExprNode;
var
  savedYield: Boolean;
begin
  { An Expression contains AssignmentExpressions, so a YieldExpression is legal
    here; a unary operand clears the flag again. }
  savedYield := FYieldExprAllowed;
  FYieldExprAllowed := True;
  try
    Result := ParsePrecedence(PREC_COMMA);
  finally
    FYieldExprAllowed := savedYield;
  end;
end;

{ Statement Parsing }

function TFloriaJSParser.ParseDeclaration(): TFloriaJSStmtNode;
var
  fnStartPos: Integer;
begin
  { Module declarations are only meaningful in a module. The context check
    inside the two parsers reports the SyntaxError for a script. A dynamic
    `import(` is an expression statement, not a declaration. }
  if Check(tkImport) and (FLexer.PeekToken().Kind <> tkLParen) and
     (FLexer.PeekToken().Kind <> tkDot) then
    Exit(ParseImportDeclaration());
  if Check(tkExport) and (FLexer.PeekToken().Kind <> tkLParen) and
     (FLexer.PeekToken().Kind <> tkDot) then
    Exit(ParseExportDeclaration());

  { Module code is strict, so a future reserved word can never be a binding or
    a statement at its top level. }
  if FIsModule and (FCurrent.Kind = tkReserved) then
    ErrorAtCurrent('Unexpected reserved word');

  if Match(tkLet) then
    Result := ParseVarDeclaration(tkLet)
  else if Match(tkConst) then
    Result := ParseVarDeclaration(tkConst)
  else if Match(tkVar) then
    Result := ParseVarDeclaration(tkVar)
  else if (FCurrent.Kind = tkAsync) and (FLexer.PeekToken().Kind = tkFunction) then
  begin
    fnStartPos := FCurrent.StartPos;
    Advance(); { Consume tkAsync }
    Advance(); { Consume tkFunction }
    if Match(tkMultiply) then
      Result := ParseFunctionDeclaration(True, True, fnStartPos)
    else
      Result := ParseFunctionDeclaration(True, False, fnStartPos);
  end
  else if Match(tkFunction) then
  begin
    fnStartPos := FPrevious.StartPos;
    if Match(tkMultiply) then
      Result := ParseFunctionDeclaration(False, True, fnStartPos)
    else
      Result := ParseFunctionDeclaration(False, False, fnStartPos);
  end
  else if Check(tkClass) then
    Result := ParseClassDeclaration()
  else
    Result := ParseStatement();
end;

function TFloriaJSParser.ParseVarDeclaration(AKind: TFloriaJSTokenKind): TFloriaJSVarStmt;
var
  varStmt: TFloriaJSVarStmt;
  startLine, startCol: Integer;
  declName: string;
  declPattern: TFloriaJSExprNode;
  declInit: TFloriaJSExprNode;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  varStmt := TFloriaJSVarStmt.Create(AKind, startLine, startCol);

  repeat
    declPattern := nil;
    declName := '';

    if Match(tkIdentifier) then
    begin
      declName := FPrevious.Text;
      { `arguments` may not be declared inside a static block. }
      if FInStaticBlock and (declName = 'arguments') then
        ErrorAtCurrent('Unexpected ''arguments'' in a static block');
    end
    else if Match(tkStatic) then
      declName := FPrevious.Text
    else if Match(tkLBracket) then
      declPattern := ParseArrayLiteral()
    else if Match(tkLBrace) then
      declPattern := ParseObjectLiteral()
    else
    begin
      ErrorAtCurrent('Expected variable name');
      Break;
    end;

    if Match(tkAssign) then
      declInit := ParseAssignmentExpression()
    else
      declInit := nil;

    if declPattern <> nil then
      varStmt.AddDestructDeclarator(declPattern, declInit)
    else
      varStmt.AddDeclarator(declName, declInit);
  until not Match(tkComma);

  EndStatement('variable declaration');
  Result := varStmt;
end;

function TFloriaJSParser.ParseFunctionDeclaration(AIsAsync: Boolean = False; AIsGenerator: Boolean = False; AStartPos: Integer = -1; AAllowAnonymous: Boolean = False): TFloriaJSFunctionDecl;
var
  fnName: string;
  fnDecl: TFloriaJSFunctionDecl;
  startLine, startCol, startPos: Integer;
  bodyBlock: TFloriaJSBlockStmt;
  savedGenParams: Boolean;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  if AStartPos >= 0 then
    startPos := AStartPos
  else
    startPos := FPrevious.StartPos;

  if Match(tkIdentifier) then
  begin
    fnName := FPrevious.Text;
    {  is a reserved word inside a static block, so it may not name a
      function there. }
    if FInStaticBlock and (fnName = 'await') then
      ErrorAtCurrent('Unexpected reserved word');
  end
  else if AAllowAnonymous then
    { An anonymous default-exported function is legal. It has no local binding;
      the default export is recorded on the export declaration, so the
      declaration itself stays anonymous. }
    fnName := ''
  else
  begin
    ErrorAtCurrent('Expected function name');
    fnName := 'anonymous';
  end;

  fnDecl := TFloriaJSFunctionDecl.Create(fnName, startLine, startCol, AIsAsync);
  fnDecl.IsGenerator := AIsGenerator;
  savedGenParams := FInGeneratorParams;
  if AIsGenerator then FInGeneratorParams := True;
  try
    ParseFormalParameters(fnDecl.Parameters);
  finally
    FInGeneratorParams := savedGenParams;
  end;
  if AIsAsync then
    bodyBlock := TFloriaJSBlockStmt(ParseAsyncFunctionBlockBody())
  else
    bodyBlock := TFloriaJSBlockStmt(ParseFunctionBlockBody());
  fnDecl.SetBody(bodyBlock);
  fnDecl.SourceText := SourceSlice(startPos, FPrevious.EndPos);
  Result := fnDecl;
end;

function TFloriaJSParser.ParseStatement(): TFloriaJSStmtNode;
var
  lbl: string;
  stmt: TFloriaJSStmtNode;
  objExpr: TFloriaJSExprNode;
  startLine, startCol: Integer;
  wasTopLevel: Boolean;
begin
  { A statement nested anywhere (if body, loop body, label) is not at the top
    level of the program, so a module declaration there is rejected. }
  wasTopLevel := FAtTopLevel;
  FAtTopLevel := False;
  try
    if FCurrent.Kind = tkReserved then
      ErrorAtCurrent('Unexpected reserved word');
    { A nested import/export declaration is recognised so the error names the
      actual restriction instead of "Expected expression". A dynamic
      `import(` is an expression, not a declaration. }
    if Check(tkImport) and (FLexer.PeekToken().Kind <> tkLParen) and
       (FLexer.PeekToken().Kind <> tkDot) then
      Exit(ParseImportDeclaration());
    if Check(tkExport) and (FLexer.PeekToken().Kind <> tkLParen) and
       (FLexer.PeekToken().Kind <> tkDot) then
      Exit(ParseExportDeclaration());
    { Empty statement: an empty block has the same effect and keeps the
      completion value unchanged. }
    if Match(tkSemicolon) then
      Exit(TFloriaJSBlockStmt.Create(FPrevious.Line, FPrevious.Column));

    if (FCurrent.Kind = tkIdentifier) and (FLexer.PeekToken().Kind = tkColon) then
    begin
      startLine := FCurrent.Line;
      startCol := FCurrent.Column;
      lbl := FCurrent.Text;
      { A label may not be nested inside a statement already carrying it. }
      if FLabels.IndexOf(lbl) >= 0 then
        ErrorAtCurrent('Label ''' + lbl + ''' has already been declared');
      Advance(); { Consume identifier }
      Advance(); { Consume ':' }
      FLabels.Add(lbl);
      try
        stmt := ParseStatement();
      finally
        FLabels.Delete(FLabels.IndexOf(lbl));
      end;
      if stmt is TFloriaJSForStmt then
        TFloriaJSForStmt(stmt).LabelName := lbl
      else if stmt is TFloriaJSWhileStmt then
        TFloriaJSWhileStmt(stmt).LabelName := lbl
      else if stmt is TFloriaJSForInOfStmt then
        TFloriaJSForInOfStmt(stmt).LabelName := lbl;
      Exit(TFloriaJSLabeledStmt.Create(lbl, stmt, startLine, startCol));
    end;

    if Match(tkIf) then
      Result := ParseIfStatement()
    else if Match(tkWhile) then
      Result := ParseWhileStatement()
    else if Match(tkDo) then
      Result := ParseDoWhileStatement()
    else if Match(tkFor) then
      Result := ParseForStatement()
    else if Match(tkSwitch) then
      Result := ParseSwitchStatement()
    else if Match(tkTry) then
      Result := ParseTryStatement()
    else if Match(tkThrow) then
      Result := ParseThrowStatement()
    else if Match(tkReturn) then
      Result := ParseReturnStatement()
    else if Match(tkBreak) then
      Result := ParseBreakStatement()
    else if Match(tkContinue) then
      Result := ParseContinueStatement()
    else if Match(tkDebugger) then
      Result := ParseDebuggerStatement()
    else if Match(tkWith) then
    begin
      startLine := FPrevious.Line;
      startCol := FPrevious.Column;
      Consume(tkLParen, 'Expected ''('' after ''with''');
      objExpr := ParseExpression();
      Consume(tkRParen, 'Expected '')'' after with object');
      stmt := ParseStatement();
      Result := TFloriaJSWithStmt.Create(objExpr, stmt, startLine, startCol);
    end
    else if Check(tkLBrace) then
      Result := ParseBlockStatement()
    else
      Result := ParseExpressionStatement();
  finally
    FAtTopLevel := wasTopLevel;
  end;
end;

function TFloriaJSParser.ParseIfStatement(): TFloriaJSIfStmt;
var
  cond: TFloriaJSExprNode;
  consequent, alternate: TFloriaJSStmtNode;
  startLine, startCol: Integer;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  Consume(tkLParen, 'Expected ''('' after ''if''');
  cond := ParseExpression();
  Consume(tkRParen, 'Expected '')'' after if condition');

  consequent := ParseStatement();
  if Match(tkElse) then
    alternate := ParseStatement()
  else
    alternate := nil;

  Result := TFloriaJSIfStmt.Create(cond, consequent, alternate, startLine, startCol);
end;

function TFloriaJSParser.ParseWhileStatement(): TFloriaJSWhileStmt;
var
  cond: TFloriaJSExprNode;
  body: TFloriaJSStmtNode;
  startLine, startCol: Integer;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  Consume(tkLParen, 'Expected ''('' after ''while''');
  cond := ParseExpression();
  Consume(tkRParen, 'Expected '')'' after while condition');

  body := ParseStatement();
  Result := TFloriaJSWhileStmt.Create(cond, body, False, startLine, startCol);
end;

function TFloriaJSParser.ParseDoWhileStatement(): TFloriaJSWhileStmt;
var
  body: TFloriaJSStmtNode;
  cond: TFloriaJSExprNode;
  startLine, startCol: Integer;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  body := ParseStatement();
  Consume(tkWhile, 'Expected ''while'' after ''do'' statement body');
  Consume(tkLParen, 'Expected ''('' after ''while''');
  cond := ParseExpression();
  Consume(tkRParen, 'Expected '')'' after do-while condition');
  EndStatement('do-while statement');

  Result := TFloriaJSWhileStmt.Create(cond, body, True, startLine, startCol);
end;

function TFloriaJSParser.ParseForStatement(): TFloriaJSStmtNode;
var
  init: TFloriaJSASTNode;
  test, update, iterable: TFloriaJSExprNode;
  body: TFloriaJSStmtNode;
  startLine, startCol: Integer;
  varKind: TFloriaJSTokenKind;
  varName, declName: string;
  isOf, isAwait: Boolean;
  varStmt: TFloriaJSVarStmt;
  declInit: TFloriaJSExprNode;
  pattern: TFloriaJSExprNode;
  forInOf: TFloriaJSForInOfStmt;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  isAwait := Match(tkAwait);
  Consume(tkLParen, 'Expected ''('' after ''for''');

  // 1. Check for 'var', 'let', 'const'
  if (FCurrent.Kind in [tkVar, tkLet, tkConst]) and
     (FLexer.PeekToken().Kind in [tkIdentifier, tkLBracket, tkLBrace]) then
  begin
    varKind := FCurrent.Kind;
    Advance(); // consume var / let / const

    { A destructuring target: `for (const [k, v] of map)`. The pattern is parsed
      as an expression and bound by the compiler. }
    if FCurrent.Kind in [tkLBracket, tkLBrace] then
    begin
      pattern := ParsePrimary();
      if (FCurrent.Kind = tkIn) or (FCurrent.Kind = tkOf) then
      begin
        isOf := (FCurrent.Kind = tkOf);
        Advance();
        iterable := ParseExpression();
        Consume(tkRParen, 'Expected '')'' after for loop iterable');
        body := ParseStatement();
        forInOf := TFloriaJSForInOfStmt.Create(varKind, '', isOf, iterable, body, startLine, startCol);
        forInOf.Pattern := pattern;
        forInOf.IsAwait := isAwait;
        if isAwait and not isOf then
          ErrorAtCurrent('for await requires of');
        Exit(forInOf);
      end;
      { Not a for-in/of target after all: report it rather than mis-parsing. }
      ErrorAtCurrent('Expected ''in'' or ''of'' after destructuring target');
      pattern.Free();
      Exit(TFloriaJSForInOfStmt.Create(varKind, '', False,
        TFloriaJSLiteralExpr.CreateUndefined(startLine, startCol), nil, startLine, startCol));
    end;

    Advance(); // consume identifier
    varName := FPrevious.Text;

    if (FCurrent.Kind = tkIn) or (FCurrent.Kind = tkOf) then
    begin
      isOf := (FCurrent.Kind = tkOf);
      Advance(); // consume 'in' or 'of'
      iterable := ParseExpression();
      Consume(tkRParen, 'Expected '')'' after for loop iterable');
      body := ParseStatement();
      begin
        forInOf := TFloriaJSForInOfStmt.Create(varKind, varName, isOf, iterable, body, startLine, startCol);
        forInOf.IsAwait := isAwait;
        if isAwait and not isOf then
          ErrorAtCurrent('for await requires of');
        Exit(forInOf);
      end;
    end;

    // Classic for loop variable declaration
    varStmt := TFloriaJSVarStmt.Create(varKind, startLine, startCol);
    if Match(tkAssign) then
      declInit := ParseAssignmentExpression()
    else
      declInit := nil;
    varStmt.AddDeclarator(varName, declInit);

    while Match(tkComma) do
    begin
      if Match(tkIdentifier) then
        declName := FPrevious.Text
      else
      begin
        ErrorAtCurrent('Expected variable name');
        Break;
      end;
      if Match(tkAssign) then
        declInit := ParseAssignmentExpression()
      else
        declInit := nil;
      varStmt.AddDeclarator(declName, declInit);
    end;

    Consume(tkSemicolon, 'Expected '';'' after for loop initializer');
    init := varStmt;
  end
  // 2. Check for existing identifier: for (x in y) or for (x of y)
  else if (FCurrent.Kind = tkIdentifier) and (FLexer.PeekToken().Kind in [tkIn, tkOf]) then
  begin
    Advance(); // consume identifier
    varName := FPrevious.Text;
    isOf := (FCurrent.Kind = tkOf);
    Advance(); // consume 'in' or 'of'
    iterable := ParseExpression();
    Consume(tkRParen, 'Expected '')'' after for loop iterable');
    body := ParseStatement();
    begin
      forInOf := TFloriaJSForInOfStmt.Create(tkEOF, varName, isOf, iterable, body, startLine, startCol);
      forInOf.IsAwait := isAwait;
      if isAwait and not isOf then
        ErrorAtCurrent('for await requires of');
      Exit(forInOf);
    end;
  end
  // 3. Classic for loop with empty init
  else if Match(tkSemicolon) then
    init := nil
  // 4. Classic for loop with expression statement init
  else
    init := ParseExpressionStatement();

  // Classic for loop condition
  if Match(tkSemicolon) then
    test := nil
  else
  begin
    test := ParseExpression();
    Consume(tkSemicolon, 'Expected '';'' after for loop condition');
  end;

  // Classic for loop update
  if Match(tkRParen) then
    update := nil
  else
  begin
    update := ParseExpression();
    Consume(tkRParen, 'Expected '')'' after for loop update clause');
  end;

  body := ParseStatement();
  Result := TFloriaJSForStmt.Create(init, test, update, body, startLine, startCol);
end;

function TFloriaJSParser.ParseSwitchStatement(): TFloriaJSSwitchStmt;
var
  discriminant, testExpr: TFloriaJSExprNode;
  switchStmt: TFloriaJSSwitchStmt;
  caseClause: TFloriaJSSwitchCase;
  startLine, startCol: Integer;
  wasTopLevel: Boolean;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  Consume(tkLParen, 'Expected ''('' after ''switch''');
  discriminant := ParseExpression();
  Consume(tkRParen, 'Expected '')'' after switch discriminant');
  Consume(tkLBrace, 'Expected ''{'' at start of switch body');

  switchStmt := TFloriaJSSwitchStmt.Create(discriminant, startLine, startCol);

  { Statements in a switch body are nested, never the program's top level. }
  wasTopLevel := FAtTopLevel;
  FAtTopLevel := False;
  try
    while (not Check(tkRBrace)) and (not IsAtEnd()) do
    begin
      if Match(tkCase) then
      begin
        testExpr := ParseExpression();
        Consume(tkColon, 'Expected '':'' after case expression');
        caseClause := TFloriaJSSwitchCase.Create(testExpr, False);
      end
      else if Match(tkDefault) then
      begin
        Consume(tkColon, 'Expected '':'' after ''default''');
        caseClause := TFloriaJSSwitchCase.Create(nil, True);
      end
      else
      begin
        ErrorAtCurrent('Expected ''case'' or ''default'' in switch body');
        Break;
      end;

      { The statements of a clause run until the next case/default label. }
      while (not Check(tkCase)) and (not Check(tkDefault)) and
            (not Check(tkRBrace)) and (not IsAtEnd()) do
      begin
        caseClause.AddStatement(ParseDeclaration());
      end;

      switchStmt.AddCase(caseClause);
    end;
  finally
    FAtTopLevel := wasTopLevel;
  end;

  Consume(tkRBrace, 'Expected ''}'' after switch body');
  Result := switchStmt;
end;

function TFloriaJSParser.ParseTryStatement(): TFloriaJSTryStmt;
var
  tryStmt: TFloriaJSTryStmt;
  catchParam: string;
  catchBlock, finallyBlock: TFloriaJSBlockStmt;
  hasCatch, hasFinally: Boolean;
  startLine, startCol: Integer;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  tryStmt := TFloriaJSTryStmt.Create(startLine, startCol);
  tryStmt.SetBlock(ParseBlockStatement());

  hasCatch := False;
  hasFinally := False;
  catchParam := '';

  { The catch clause binds the thrown value to a parameter of its own. The
    parameter is optional, a catch clause without one is allowed. }
  if Match(tkCatch) then
  begin
    hasCatch := True;
    if Match(tkLParen) then
    begin
      if Match(tkIdentifier) then
        catchParam := FPrevious.Text
      else
        ErrorAtCurrent('Expected catch parameter name');
      Consume(tkRParen, 'Expected '')'' after catch parameter');
    end;

    catchBlock := ParseBlockStatement();
    tryStmt.SetCatch(catchParam, catchBlock);
  end;

  if Match(tkFinally) then
  begin
    hasFinally := True;
    finallyBlock := ParseBlockStatement();
    tryStmt.SetFinally(finallyBlock);
  end;

  { A try statement without a catch and without a finally clause would have
    no effect at all, so it is rejected. }
  if (not hasCatch) and (not hasFinally) then
    ErrorAtCurrent('Missing catch or finally after try block');

  Result := tryStmt;
end;

function TFloriaJSParser.ParseThrowStatement(): TFloriaJSThrowStmt;
var
  expr: TFloriaJSExprNode;
  startLine, startCol: Integer;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  { A line terminator is not allowed between throw and its expression. }
  if HasLineBreakBeforeCurrent() then
  begin
    ErrorAtCurrent('Illegal newline after throw');
    expr := TFloriaJSLiteralExpr.CreateUndefined(startLine, startCol);
  end
  else
    expr := ParseExpression();
  EndStatement('throw statement');
  Result := TFloriaJSThrowStmt.Create(expr, startLine, startCol);
end;

function TFloriaJSParser.ParseBlockStatement(): TFloriaJSBlockStmt;
var
  block: TFloriaJSBlockStmt;
  startLine, startCol: Integer;
  wasTopLevel: Boolean;
begin
  Consume(tkLBrace, 'Expected ''{'' at start of block');
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  block := TFloriaJSBlockStmt.Create(startLine, startCol);

  { A block body is never the top level of the program. }
  wasTopLevel := FAtTopLevel;
  FAtTopLevel := False;
  try
    while (not Check(tkRBrace)) and (not IsAtEnd()) do
    begin
      block.AddStatement(ParseDeclaration());
    end;
  finally
    FAtTopLevel := wasTopLevel;
  end;

  Consume(tkRBrace, 'Expected ''}'' after block');
  Result := block;
end;

function TFloriaJSParser.ParseReturnStatement(): TFloriaJSReturnStmt;
var
  arg: TFloriaJSExprNode;
  startLine, startCol: Integer;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  { `return` is only legal inside a function body. A module's top level is not
    one, so this is an early SyntaxError rather than a no-op. }
  if FFunctionDepth = 0 then
    ErrorAtCurrent('Illegal return statement');

  if (not HasLineBreakBeforeCurrent()) and
     (not Check(tkSemicolon)) and (not Check(tkRBrace)) and (not IsAtEnd()) then
    arg := ParseExpression()
  else
    arg := nil;

  EndStatement('return statement');
  Result := TFloriaJSReturnStmt.Create(arg, startLine, startCol);
end;

function TFloriaJSParser.ParseDebuggerStatement(): TFloriaJSDebuggerStmt;
var
  startLine, startCol: Integer;
begin
  { A no-op statement. Recognising it here means the undeclared-read check
    never sees `debugger` as an identifier. }
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  EndStatement('debugger statement');
  Result := TFloriaJSDebuggerStmt.Create(startLine, startCol);
end;

function TFloriaJSParser.ParseBreakStatement(): TFloriaJSBreakStmt;
var
  startLine, startCol: Integer;
  lbl: string;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  lbl := '';
  if (not HasLineBreakBeforeCurrent()) and Match(tkIdentifier) then
    lbl := FPrevious.Text;
  EndStatement('break statement');
  Result := TFloriaJSBreakStmt.Create(startLine, startCol, lbl);
end;

function TFloriaJSParser.ParseContinueStatement(): TFloriaJSContinueStmt;
var
  startLine, startCol: Integer;
  lbl: string;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  lbl := '';
  if (not HasLineBreakBeforeCurrent()) and Match(tkIdentifier) then
    lbl := FPrevious.Text;
  EndStatement('continue statement');
  Result := TFloriaJSContinueStmt.Create(startLine, startCol, lbl);
end;

function TFloriaJSParser.ParseExpressionStatement(): TFloriaJSExprStmt;
var
  expr: TFloriaJSExprNode;
  startLine, startCol: Integer;
begin
  startLine := FCurrent.Line;
  startCol := FCurrent.Column;
  expr := ParseExpression();
  EndStatement('expression statement');
  Result := TFloriaJSExprStmt.Create(expr, startLine, startCol);
end;

{ Module Syntax (import / export declarations) }

function TFloriaJSParser.CheckIdentifierText(const AText: string): Boolean;
begin
  { `from` and `as` are contextual: the lexer keeps them as identifiers, so the
    parser compares their text instead of their token kind. }
  Result := (FCurrent.Kind = tkIdentifier) and (FCurrent.Text = AText);
end;

function TFloriaJSParser.ConsumeIdentifierText(const AText, AErrorMessage: string): Boolean;
begin
  if CheckIdentifierText(AText) then
  begin
    Advance();
    Exit(True);
  end;
  ErrorAtCurrent(AErrorMessage);
  Result := False;
end;

function TFloriaJSParser.CheckModuleDeclarationContext(const AKeyword: string): Boolean;
begin
  if not FIsModule then
  begin
    ErrorAtCurrent('Cannot use ''' + AKeyword + ''' outside a module');
    Exit(False);
  end;
  if not FAtTopLevel then
  begin
    ErrorAtCurrent('''' + AKeyword + ''' declarations are only allowed at the top level of a module');
    Exit(False);
  end;
  Result := True;
end;

function TFloriaJSParser.ParseModuleName(const AContext: string): string;
begin
  if Match(tkIdentifier) or Match(tkString) then
    Exit(FPrevious.Text);
  if IsKeywordToken(FCurrent.Kind) then
  begin
    { Keywords may be imported and exported under their own spelling. }
    Result := FCurrent.Text;
    Advance();
    Exit;
  end;
  ErrorAtCurrent('Expected ' + AContext);
  Result := '';
end;

function TFloriaJSParser.ParseModuleBindingName(const AContext: string): string;
begin
  { A local binding must be an identifier; only the imported/exported name may
    be a string literal. Module code is strict, so `eval` and `arguments` may
    not be bound. }
  if Match(tkIdentifier) then
  begin
    Result := FPrevious.Text;
    if (Result = 'eval') or (Result = 'arguments') then
    begin
      ErrorAtCurrent('Unexpected ' + Result + ' in strict mode');
      Exit('');
    end;
    { `arguments` may not be declared in a static block. }
    if FInStaticBlock and (Result = 'arguments') then
      ErrorAtCurrent('Unexpected ''arguments'' in a static block');
    Exit(Result);
  end;
  ErrorAtCurrent('Expected ' + AContext);
  Result := '';
end;

function TFloriaJSParser.ParseModuleSpecifierString(const AContext: string): string;
begin
  if Match(tkString) then
    Exit(FPrevious.Text);
  ErrorAtCurrent('Expected a module specifier string in ' + AContext);
  Result := '';
end;

{ An import attributes clause: `with { type: "json" }` or the legacy
  `assert { ... }`. The clause is validated only to the extent that it is
  balanced; the loader decides how to interpret it. }
procedure TFloriaJSParser.ParseImportAttributes(ADecl: TFloriaJSImportDecl);
var
  key: string;
  hadEntry: Boolean;
begin
  { `with` is a keyword token; `assert` is the legacy spelling and an
    identifier. The clause is `{ key: "value", ... }` with an optional trailing
    comma; only the keys are kept, because the loader decides whether the
    representation it names is one it can provide. }
  if Check(tkWith) then
    Advance()
  else if CheckIdentifierText('assert') then
    Advance()
  else
    Exit;
  if not Check(tkLBrace) then
    Exit;
  Advance();

  hadEntry := False;
  while (not Check(tkRBrace)) and (not IsAtEnd()) do
  begin
    { AttributeKey is an IdentifierName or a StringLiteral. }
    if Check(tkString) then
    begin
      key := FPrevious.Text;
      Advance();
    end
    else if (FCurrent.Kind = tkIdentifier) or (FCurrent.Kind = tkReserved) or
            IsKeywordToken(FCurrent.Kind) then
    begin
      { AttributeKey is an IdentifierName, so any keyword spelling works. }
      key := FCurrent.Text;
      Advance();
    end
    else
    begin
      ErrorAtCurrent('Expected an import attribute key');
      Exit;
    end;
    if ADecl <> nil then
      ADecl.AddAttributeKey(key);
    Consume(tkColon, 'Expected '':'' after an import attribute key');
    if not Check(tkString) then
    begin
      ErrorAtCurrent('Expected a string import attribute value');
      Exit;
    end;
    Advance();

    hadEntry := True;
    if Match(tkComma) then
      Continue;
    Break;
  end;

  if Check(tkRBrace) then
    Advance()
  else
    ErrorAtCurrent('Expected ''}'' after import attributes');
end;

procedure TFloriaJSParser.SkipModuleDeclaration();
begin
  { Consume up to and including the terminating semicolon, or stop at a closing
    brace or end of input. This keeps one malformed module declaration from
    cascading into a stream of errors. }
  while (not IsAtEnd()) and (not Check(tkSemicolon)) and (not Check(tkRBrace)) do
    Advance();
  Match(tkSemicolon);
end;

function TFloriaJSParser.ParseImportClause(ADecl: TFloriaJSImportDecl): Boolean;
var
  importedName, localName: string;
  importedIsString, hadDefault: Boolean;
begin
  Result := False;
  hadDefault := False;

  { Optional default binding: import x ... }
  if Match(tkIdentifier) then
  begin
    localName := FPrevious.Text;
    if FIsModule and ((localName = 'eval') or (localName = 'arguments')) then
      ErrorAtCurrent('Unexpected ' + localName + ' in strict mode');
    ADecl.AddEntry('default', localName, fjikDefault);
    Result := True;
    hadDefault := True;
    if not Match(tkComma) then
      Exit(True);
  end;

  { Namespace binding: import * as ns from "m" }
  if Match(tkMultiply) then
  begin
    ConsumeIdentifierText('as', 'Expected ''as'' after ''*'' in import declaration');
    localName := ParseModuleBindingName('a namespace binding name');
    ADecl.AddEntry('*', localName, fjikNamespace);
    Exit(True);
  end;

  { Named bindings: an import clause listing individual names }
  if Match(tkLBrace) then
  begin
    if not Check(tkRBrace) then
      repeat
        importedIsString := Check(tkString);
        importedName := ParseModuleName('an imported name');
        if CheckIdentifierText('as') then
        begin
          Advance();
          { A string import name must be given an identifier binding with `as`. }
          localName := ParseModuleBindingName('a local binding name');
        end
        else
        begin
          { A string literal only names the imported binding; it cannot also be
            the local name, which must be an identifier. }
          if importedIsString or (importedName = '') then
            ErrorAtCurrent('A string import name requires ''as'' with a local binding name');
          { The imported name doubles as the local binding here, so it is held
            to the same strict-mode restriction as an explicit binding. }
          localName := importedName;
          if FIsModule and ((localName = 'eval') or (localName = 'arguments')) then
            ErrorAtCurrent('Unexpected ' + localName + ' in strict mode');
        end;
        ADecl.AddEntry(importedName, localName, fjikNamed);
      until (not Match(tkComma)) or Check(tkRBrace);
    Consume(tkRBrace, 'Expected ''}'' after import bindings');
    Exit(True);
  end;

  if hadDefault then
  begin
    { After `import d,` only a namespace or a named clause may follow. }
    ErrorAtCurrent('Expected ''*'' or ''{'' after the default import binding');
    Exit(False);
  end;

  if not Result then
    ErrorAtCurrent('Expected an import clause');
end;

function TFloriaJSParser.ParseImportDeclaration(): TFloriaJSStmtNode;
var
  startLine, startCol, startPos: Integer;
  decl: TFloriaJSImportDecl;
  spec: string;
begin
  startLine := FCurrent.Line;
  startCol := FCurrent.Column;
  startPos := FCurrent.StartPos;

  { Source-phase (`import source x from "m"`) and deferred (`import defer * as
    ns from "m"`) imports are later proposals this engine does not implement.
    They are reported as a parser limitation rather than as a specification
    error, so a diagnostic adapter can classify them honestly. }
  if (FLexer.PeekToken().Kind = tkIdentifier) and
     ((FLexer.PeekToken().Text = 'source') or (FLexer.PeekToken().Text = 'defer')) then
  begin
    Advance(); { consume `import` }
    ErrorAtCurrent('Source-phase and deferred imports are not supported');
    SkipModuleDeclaration();
    decl := TFloriaJSImportDecl.Create('', startLine, startCol);
    decl.SourceStart := startPos;
    decl.SourceEnd := FPrevious.EndPos;
    Exit(decl);
  end;

  { Report the restriction at the keyword, before it is consumed. }
  if not CheckModuleDeclarationContext('import') then
  begin
    decl := TFloriaJSImportDecl.Create('', startLine, startCol);
    decl.SourceStart := startPos;
    Advance(); { consume `import` }
    SkipModuleDeclaration();
    decl.SourceEnd := FPrevious.EndPos;
    Exit(decl);
  end;

  Advance(); { consume `import` }
  decl := TFloriaJSImportDecl.Create('', startLine, startCol);
  decl.SourceStart := startPos;

  spec := '';
  if Match(tkString) then
  begin
    { Bare import: import "m"; }
    spec := FPrevious.Text;
    decl.IsBare := True;
  end
  else
  begin
    ParseImportClause(decl);
    if CheckIdentifierText('from') then
    begin
      Advance();
      spec := ParseModuleSpecifierString('import declaration');
    end
    else
      ErrorAtCurrent('Expected ''from'' in import declaration');
  end;

  decl.ModuleSpecifier := spec;
  ParseImportAttributes(decl);
  EndStatement('import declaration');
  decl.SourceEnd := FPrevious.EndPos;
  Result := decl;
end;

function TFloriaJSParser.ParseExportClause(ANames, AAliases, AKinds: TStrings): Boolean;
var
  localName, exportName: string;
  localKind: Char;
begin
  { Parses a clause of local or imported names, with optional aliases. Each
    name may be an identifier, a keyword spelling, or a string literal. AKinds
    records how the left side was spelled ('i' identifier, 's' string,
    'k' keyword), because only an identifier can name a local binding when
    there is no `from`. }
  Consume(tkLBrace, 'Expected ''{'' in export declaration');
  Result := True;
  if not Check(tkRBrace) then
    repeat
      if Match(tkIdentifier) then
      begin
        localName := FPrevious.Text;
        localKind := 'i';
      end
      else if Match(tkString) then
      begin
        localName := FPrevious.Text;
        localKind := 's';
      end
      else if IsKeywordToken(FCurrent.Kind) then
      begin
        localName := FCurrent.Text;
        localKind := 'k';
        Advance();
      end
      else
      begin
        ErrorAtCurrent('Expected an export name');
        localName := '';
        localKind := '?';
        Result := False;
      end;

      if CheckIdentifierText('as') then
      begin
        Advance();
        exportName := ParseModuleName('an export alias');
      end
      else
        exportName := localName;

      ANames.Add(localName);
      AAliases.Add(exportName);
      AKinds.Add(localKind);
    until (not Match(tkComma)) or Check(tkRBrace);
  Consume(tkRBrace, 'Expected ''}'' in export declaration');
end;

function TFloriaJSParser.ParseExportDefault(ADecl: TFloriaJSExportDecl): Boolean;
var
  startPos, fnStartPos: Integer;
  cls: TFloriaJSClassNode;
  varStmt: TFloriaJSVarStmt;
  expr: TFloriaJSExprNode;
begin
  { export default function ... / export default async function ... }
  if (FCurrent.Kind = tkAsync) and (FLexer.PeekToken().Kind = tkFunction) then
  begin
    fnStartPos := FCurrent.StartPos;
    Advance(); { consume `async` }
    Advance(); { consume `function` }
    if Match(tkMultiply) then
      ADecl.SetDeclaration(ParseFunctionDeclaration(True, True, fnStartPos, True))
    else
      ADecl.SetDeclaration(ParseFunctionDeclaration(True, False, fnStartPos, True));
    Exit(True);
  end;

  if Check(tkFunction) then
  begin
    fnStartPos := FCurrent.StartPos;
    Advance(); { consume `function` }
    if Match(tkMultiply) then
      ADecl.SetDeclaration(ParseFunctionDeclaration(False, True, fnStartPos, True))
    else
      ADecl.SetDeclaration(ParseFunctionDeclaration(False, False, fnStartPos, True));
    Exit(True);
  end;

  { export default class [Name] ... }
  if Check(tkClass) then
  begin
    startPos := FCurrent.StartPos;
    Advance(); { consume `class` }
    cls := ParseClassExpr(True);
    cls.SourceText := SourceSlice(startPos, FPrevious.EndPos);
    if cls.Name = '' then
      { An anonymous default class has no local binding. }
      ADecl.SetExpression(cls)
    else
    begin
      { A named one also creates a block-scoped binding in the module, exactly
        like a class declaration. }
      varStmt := TFloriaJSVarStmt.Create(tkLet, cls.Line, cls.Column);
      varStmt.AddDeclarator(cls.Name, cls);
      ADecl.SetDeclaration(varStmt);
    end;
    Match(tkSemicolon);
    Exit(True);
  end;

  { export default <expression>; }
  expr := ParseAssignmentExpression();
  ADecl.SetExpression(expr);
  EndStatement('export default expression');
  Result := True;
end;

function TFloriaJSParser.ParseExportDeclaration(): TFloriaJSStmtNode;
var
  startLine, startCol, startPos: Integer;
  decl: TFloriaJSExportDecl;
  spec: string;
  names, aliases, kinds: TStringList;
  i: Integer;
  fnStartPos: Integer;
begin
  startLine := FCurrent.Line;
  startCol := FCurrent.Column;
  startPos := FCurrent.StartPos;

  { Report the restriction at the keyword, before it is consumed. }
  if not CheckModuleDeclarationContext('export') then
  begin
    decl := TFloriaJSExportDecl.Create(startLine, startCol);
    decl.SourceStart := startPos;
    Advance(); { consume `export` }
    SkipModuleDeclaration();
    decl.SourceEnd := FPrevious.EndPos;
    Exit(decl);
  end;

  Advance(); { consume `export` }
  decl := TFloriaJSExportDecl.Create(startLine, startCol);
  decl.SourceStart := startPos;

  if Match(tkDefault) then
  begin
    decl.IsDefault := True;
    ParseExportDefault(decl);
  end
  else if Check(tkMultiply) then
  begin
    { export * from "m"; export * as ns from "m"; }
    Advance();
    if CheckIdentifierText('as') then
    begin
      Advance();
      spec := ParseModuleName('a namespace name');
      ConsumeIdentifierText('from', 'Expected ''from'' after export namespace name');
      decl.AddStarExport(ParseModuleSpecifierString('export declaration'), spec);
      ParseImportAttributes(nil);
    end
    else
    begin
      ConsumeIdentifierText('from', 'Expected ''from'' in export declaration');
      decl.AddStarExport(ParseModuleSpecifierString('export declaration'));
    end;
    { A re-export may carry an attribute clause too. }
    ParseImportAttributes(nil);
    EndStatement('export declaration');
  end
  else if Check(tkLBrace) then
  begin
    { Local export clause, or a re-export clause when `from` follows. }
    names := TStringList.Create();
    aliases := TStringList.Create();
    kinds := TStringList.Create();
    try
      ParseExportClause(names, aliases, kinds);
      if CheckIdentifierText('from') then
      begin
        Advance();
        spec := ParseModuleSpecifierString('export declaration');
        for i := 0 to names.Count - 1 do
          { In a re-export both sides name module export names, so either may
            be a string literal or a keyword spelling. }
          decl.AddIndirectExport(aliases[i], names[i], spec);
        ParseImportAttributes(nil);
      end
      else
      begin
        for i := 0 to names.Count - 1 do
        begin
          { Without `from` the left side names a local binding, which must be an
            ordinary identifier. The published name may be any export name,
            including a string literal. }
          if kinds[i] <> 'i' then
            ErrorAtCurrent('A local export name must be an identifier');
          decl.AddLocalExport(names[i], aliases[i]);
        end;
      end;
    finally
      names.Free();
      aliases.Free();
      kinds.Free();
    end;
    EndStatement('export declaration');
  end
  else if Check(tkConst) or Check(tkLet) or Check(tkVar) then
  begin
    { export const/let/var ...; }
    if Match(tkConst) then
      decl.SetDeclaration(ParseVarDeclaration(tkConst))
    else if Match(tkLet) then
      decl.SetDeclaration(ParseVarDeclaration(tkLet))
    else
    begin
      Advance();
      decl.SetDeclaration(ParseVarDeclaration(tkVar));
    end;
  end
  else if (FCurrent.Kind = tkAsync) and (FLexer.PeekToken().Kind = tkFunction) then
  begin
    { export async function ... }
    fnStartPos := FCurrent.StartPos;
    Advance(); { consume `async` }
    Advance(); { consume `function` }
    if Match(tkMultiply) then
      decl.SetDeclaration(ParseFunctionDeclaration(True, True, fnStartPos))
    else
      decl.SetDeclaration(ParseFunctionDeclaration(True, False, fnStartPos));
  end
  else if Check(tkFunction) then
  begin
    { export function ... / export function* ... }
    fnStartPos := FCurrent.StartPos;
    Advance(); { consume `function` }
    if Match(tkMultiply) then
      decl.SetDeclaration(ParseFunctionDeclaration(False, True, fnStartPos))
    else
      decl.SetDeclaration(ParseFunctionDeclaration(False, False, fnStartPos));
  end
  else if Check(tkClass) then
  begin
    { export class ... }
    decl.SetDeclaration(ParseClassDeclaration());
  end
  else
  begin
    ErrorAtCurrent('Expected a declaration after ''export''');
    SkipModuleDeclaration();
  end;

  decl.SourceEnd := FPrevious.EndPos;
  Result := decl;
end;

function TFloriaJSParser.ParseProgram(): TFloriaJSProgram;
var
  prog: TFloriaJSProgram;
begin
  prog := TFloriaJSProgram.Create(FCurrent.Line, FCurrent.Column);
  FAtTopLevel := True;
  try
    while not IsAtEnd() do
    begin
      prog.AddStatement(ParseDeclaration());
    end;
  finally
    FAtTopLevel := False;
  end;
  Result := prog;
end;

procedure TFloriaJSParser.SetModuleMode(AValue: Boolean);
begin
  FIsModule := AValue;
end;

{ Declarative FTML Component Parsing (Floria Toolkit Markup Language) }

procedure TFloriaJSParser.ParseFTMLBody(AComp: TFloriaFTMLComponent);
var
  propName, sigName: string;
  propExpr: TFloriaJSExprNode;
  sigHandler: TFloriaJSStmtNode;
  childComp: TFloriaFTMLComponent;
  fnDecl: TFloriaJSFunctionDecl;
begin
  while (not Check(tkRBrace)) and (not IsAtEnd()) do
  begin
    while Match(tkSemicolon) do ;
    if Check(tkRBrace) or IsAtEnd() then Break;

    // Component Function: function myFunc(...) { ... }
    if Match(tkFunction) then
    begin
      fnDecl := ParseFunctionDeclaration();
      AComp.AddFunction(fnDecl);
      Continue;
    end;

    if Match(tkIdentifier) then
    begin
      propName := FPrevious.Text;

      // Check for typed property: property <type> <name>: <expr>
      if (propName = 'property') and Check(tkIdentifier) then
      begin
        Advance(); // consume type (e.g. 'int', 'string', 'real', 'var', 'bool')
        if Match(tkIdentifier) then
          propName := FPrevious.Text;
      end;

      // Allow dotted property / signal names: Component.onCompleted, FTML.onCompleted, anchors.fill
      while Match(tkDot) do
      begin
        if Match(tkIdentifier) then
          propName := propName + '.' + FPrevious.Text;
      end;

      // Check if it is a child component definition: ChildType { ... }
      if Check(tkLBrace) then
      begin
        childComp := TFloriaFTMLComponent.Create(propName, FPrevious.Line, FPrevious.Column);
        Advance(); // Consume '{'
        ParseFTMLBody(childComp);
        Consume(tkRBrace, 'Expected closing brace for child component');
        AComp.AddChild(childComp);
        Continue;
      end;

      // Signal handler: onClicked: { count += 1; } or Component.onCompleted: { ... }
      if (Length(propName) > 2) and ((Copy(propName, 1, 2) = 'on') or (Pos('.on', propName) > 0)) and Check(tkColon) then
      begin
        Advance(); // Consume ':'
        sigName := propName;
        if Check(tkLBrace) then
          sigHandler := ParseBlockStatement()
        else
          sigHandler := ParseStatement();
        AComp.AddSignal(sigName, sigHandler);
        Match(tkSemicolon);
        Continue;
      end;

      // Regular property binding: prop: expr;
      Consume(tkColon, 'Expected '':'' after property name');
      propExpr := ParseExpression();
      Match(tkSemicolon);

      if propName = 'id' then
      begin
        if propExpr is TFloriaJSIdentifierExpr then
          AComp.Id := TFloriaJSIdentifierExpr(propExpr).Name
        else if propExpr is TFloriaJSLiteralExpr then
          AComp.Id := TFloriaJSLiteralExpr(propExpr).StringVal;
        propExpr.Free();
      end
      else
        AComp.AddProperty(propName, propExpr);
    end
    else
    begin
      ErrorAtCurrent('Expected property, signal, or child component inside ' + AComp.ComponentType);
      Advance();
    end;
  end;
end;

function TFloriaJSParser.ParseFTMLComponent(): TFloriaFTMLComponent;
var
  compName: string;
  comp: TFloriaFTMLComponent;
  startLine, startCol: Integer;
begin
  startLine := FCurrent.Line;
  startCol := FCurrent.Column;

  if not Match(tkIdentifier) then
  begin
    ErrorAtCurrent('Expected FTML component type name (e.g. Rectangle, Item, Button)');
    Exit(nil);
  end;

  compName := FPrevious.Text;
  comp := TFloriaFTMLComponent.Create(compName, startLine, startCol);

  Consume(tkLBrace, 'Expected ''{'' after component name');
  ParseFTMLBody(comp);
  Consume(tkRBrace, 'Expected ''}'' closing component');

  Result := comp;
end;

end.
