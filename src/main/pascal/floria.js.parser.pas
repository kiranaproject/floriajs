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

    procedure Advance();
    function  Check(AKind: TFloriaJSTokenKind): Boolean;
    function  Match(AKind: TFloriaJSTokenKind): Boolean;
    function  Consume(AKind: TFloriaJSTokenKind; const AErrorMessage: string): Boolean;
    function  IsAtEnd(): Boolean;
    procedure ErrorAtCurrent(const AMessage: string);
    procedure Synchronize();

    { Expression Pratt Parsing }
    { True for any reserved word. Property names and object-literal keys accept
      keywords, so those sites must not compare the token enum by range: the
      keyword block is not contiguous with the delimiters that follow it. }
    function  IsKeywordToken(AKind: TFloriaJSTokenKind): Boolean;
    function  GetInfixPrecedence(AKind: TFloriaJSTokenKind): Integer;
    function  ParsePrecedence(APrec: Integer): TFloriaJSExprNode;
    function  ParseAssignmentExpression(): TFloriaJSExprNode;
    function  ParsePrimary(): TFloriaJSExprNode;
    function  ParseUnaryPrefix(): TFloriaJSExprNode;
    function  ParseNewExpression(ANewToken: TFloriaJSToken): TFloriaJSExprNode;
    function  ParseMemberTail(ALeft: TFloriaJSExprNode): TFloriaJSExprNode;
    function  ParseArrayLiteral(): TFloriaJSExprNode;
    function  ParseObjectLiteral(): TFloriaJSExprNode;
    function  ParseMethodBody(const AName: string): TFloriaJSFunctionExpr;
    function  ParseClassExpr(AIsDeclaration: Boolean): TFloriaJSClassNode;
    function  ParseClassDeclaration(): TFloriaJSStmtNode;
    function  ParseTaggedTemplate(ATag: TFloriaJSExprNode): TFloriaJSExprNode;
    function  ParseFunctionExpr(AIsAsync: Boolean = False): TFloriaJSExprNode;
    procedure ParseFormalParameters(AParams: TStringList);
    function  ExtractParameters(var AExpr: TFloriaJSExprNode; AParams: TStrings): Boolean;

    { Statements & Declarations }
    function  ParseStatement(): TFloriaJSStmtNode;
    function  ParseDeclaration(): TFloriaJSStmtNode;
    function  ParseVarDeclaration(AKind: TFloriaJSTokenKind): TFloriaJSVarStmt;
    function  ParseFunctionDeclaration(AIsAsync: Boolean = False): TFloriaJSFunctionDecl;
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
  Advance();
end;

constructor TFloriaJSParser.Create(ALexer: TFloriaJSLexer);
begin
  inherited Create();
  FLexer := ALexer;
  FOwnsLexer := False;
  FErrors := TStringList.Create();
  Advance();
end;

destructor TFloriaJSParser.Destroy();
begin
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

{ Precedence Table }

function TFloriaJSParser.IsKeywordToken(AKind: TFloriaJSTokenKind): Boolean;
begin
  { The keyword block is contiguous in the enum; keep the upper bound on the
    last keyword so a newly added keyword is covered automatically. }
  Result := (AKind >= tkLet) and (AKind <= tkStatic);
end;

function TFloriaJSParser.GetInfixPrecedence(AKind: TFloriaJSTokenKind): Integer;
begin
  case AKind of
    tkComma:
      Result := PREC_COMMA;
    tkAssign, tkPlusAssign, tkMinusAssign, tkMultiplyAssign, tkDivideAssign, tkModuloAssign,
    tkPowerAssign, tkNullishAssign, tkAndAssign, tkOrAssign, tkArrow:
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
  paramName, pat, flags: string;
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
    Exit(TFloriaJSLiteralExpr.CreateNumber(tok.NumberValue, tok.Line, tok.Column));

  if Match(tkString) or Match(tkTemplateString) then
    Exit(TFloriaJSLiteralExpr.CreateString(tok.Text, tok.Line, tok.Column));

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

  { Identifier }
  if Match(tkIdentifier) then
    Exit(TFloriaJSIdentifierExpr.Create(tok.Text, tok.Line, tok.Column));

  { this — the receiver of a method or constructor call. It is bound like an
    ordinary name in the activation scope of the call. }
  if Match(tkThis) then
    Exit(TFloriaJSIdentifierExpr.Create('this', tok.Line, tok.Column));

  { super — bound like `this`, to the parent constructor inside a derived class.
    `super(...)` and `super.m()` are handled by the compiler through it. }
  if Match(tkSuper) then
    Exit(TFloriaJSIdentifierExpr.Create('super', tok.Line, tok.Column));

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
      Exit(ParseFunctionExpr(True));

    if Match(tkLParen) then
    begin
      if Match(tkRParen) then
      begin
        if Match(tkArrow) then
        begin
          fnExpr := TFloriaJSFunctionExpr.Create('', True, tok.Line, tok.Column, True);
          if Check(tkLBrace) then
            fnExpr.SetBody(ParseBlockStatement())
          else
            fnExpr.SetBody(TFloriaJSReturnStmt.Create(ParseAssignmentExpression(), FPrevious.Line, FPrevious.Column));
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
          if Check(tkLBrace) then
            fnExpr.SetBody(ParseBlockStatement())
          else
            fnExpr.SetBody(TFloriaJSReturnStmt.Create(ParseAssignmentExpression(), FPrevious.Line, FPrevious.Column));
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
      if Check(tkLBrace) then
        fnExpr.SetBody(ParseBlockStatement())
      else
        fnExpr.SetBody(TFloriaJSReturnStmt.Create(ParseAssignmentExpression(), FPrevious.Line, FPrevious.Column));
      Exit(fnExpr);
    end
    else
      Exit(TFloriaJSIdentifierExpr.Create('async', tok.Line, tok.Column));
  end;

  { Function Expression }
  if Match(tkFunction) then
    Exit(ParseFunctionExpr());

  { Parenthesized Grouping or Arrow function }
  if Match(tkLParen) then
  begin
    if Match(tkRParen) then
    begin
      if Match(tkArrow) then
      begin
        fnExpr := TFloriaJSFunctionExpr.Create('', True, tok.Line, tok.Column);
        if Check(tkLBrace) then
          fnExpr.SetBody(ParseBlockStatement())
        else
          fnExpr.SetBody(TFloriaJSReturnStmt.Create(ParseAssignmentExpression(), FPrevious.Line, FPrevious.Column));
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
      if Check(tkLBrace) then
        fnExpr.SetBody(ParseBlockStatement())
      else
        fnExpr.SetBody(TFloriaJSReturnStmt.Create(ParseAssignmentExpression(), FPrevious.Line, FPrevious.Column));
      Exit(fnExpr);
    end;
    Exit(TFloriaJSGroupExpr.Create(expr, tok.Line, tok.Column));
  end;

  ErrorAtCurrent('Expected expression');
  Advance();
  Result := TFloriaJSLiteralExpr.CreateUndefined(tok.Line, tok.Column);
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
  operand: TFloriaJSExprNode;
begin
  op := FCurrent;
  Advance();
  if op.Kind = tkEllipsis then
  begin
    operand := ParseAssignmentExpression();
    Exit(TFloriaJSSpreadExpr.Create(operand, op.Line, op.Column));
  end;
  operand := ParsePrecedence(PREC_UNARY);
  if (op.Kind in [tkPlusPlus, tkMinusMinus]) and IsOptionalChainTarget(operand) then
    ErrorAtCurrent('Invalid left-hand side in prefix operation');
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
      if Match(tkIdentifier) then
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
      arr.AddElement(TFloriaJSSpreadExpr.Create(ParseAssignmentExpression(), FPrevious.Line, FPrevious.Column))
    else
      arr.AddElement(ParseAssignmentExpression());

    if not Check(tkRBracket) then
      Consume(tkComma, 'Expected '','' or '']'' after array element');
  end;

  Consume(tkRBracket, 'Expected '']'' after array elements');
  Result := arr;
end;


{ `class [Name] [extends Base] { members }`

  Members are methods, `get`/`set` accessors, and `static` variants. Fields are
  not supported (they are a later proposal); the parser rejects them rather than
  silently ignoring the initializer. }

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
    cls.Free();
    Exit(TFloriaJSBlockStmt.Create(startLine, startCol));
  end;

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

function TFloriaJSParser.ParseClassExpr(AIsDeclaration: Boolean): TFloriaJSClassNode;
var
  cls: TFloriaJSClassNode;
  startLine, startCol: Integer;
  clsName, memberName: string;
  superClass: TFloriaJSExprNode;
  isStatic: Boolean;
  kind: TFloriaJSClassMemberKind;
  fnExpr: TFloriaJSFunctionExpr;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  clsName := '';
  if Match(tkIdentifier) then
    clsName := FPrevious.Text;

  superClass := nil;
  if Match(tkExtends) then
    superClass := ParsePrimary();

  cls := TFloriaJSClassNode.Create(clsName, superClass, startLine, startCol);
  cls.IsDeclaration := AIsDeclaration;

  Consume(tkLBrace, 'Expected ''{'' at start of class body');

  while (not Check(tkRBrace)) and (not IsAtEnd()) do
  begin
    if Match(tkSemicolon) then
      Continue;

    isStatic := False;
    if Check(tkStatic) and (FLexer.PeekToken().Kind <> tkLParen) then
    begin
      Advance();
      isStatic := True;
    end;

    kind := fjcmMethod;

    { get/set accessors, when not used as a plain method name. }
    if (FCurrent.Kind = tkIdentifier) and
       ((FCurrent.Text = 'get') or (FCurrent.Text = 'set')) and
       (FLexer.PeekToken().Kind <> tkLParen) then
    begin
      if FCurrent.Text = 'get' then kind := fjcmGetter else kind := fjcmSetter;
      Advance();
    end;

    memberName := '';
    if Match(tkIdentifier) then
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

    if not Check(tkLParen) then
    begin
      { A field declaration, which this runtime does not support. }
      ErrorAtCurrent('Class fields are not supported; use a constructor assignment');
      Break;
    end;

    fnExpr := ParseMethodBody(memberName);
    cls.AddMember(TFloriaJSClassMember.Create(memberName, kind, isStatic,
      fnExpr, startLine, startCol));
  end;

  Consume(tkRBrace, 'Expected ''}'' at end of class body');
  Result := cls;
end;

function TFloriaJSParser.ParseMethodBody(const AName: string): TFloriaJSFunctionExpr;
var
  fnExpr: TFloriaJSFunctionExpr;
  startLine, startCol: Integer;
  bodyStmt: TFloriaJSStmtNode;
begin
  startLine := FCurrent.Line;
  startCol := FCurrent.Column;

  fnExpr := TFloriaJSFunctionExpr.Create(AName, False, startLine, startCol);
  ParseFormalParameters(fnExpr.Parameters);
  bodyStmt := ParseBlockStatement();
  fnExpr.SetBody(bodyStmt);
  Result := fnExpr;
end;

function TFloriaJSParser.ParseObjectLiteral(): TFloriaJSExprNode;
var
  obj: TFloriaJSObjectExpr;
  startLine, startCol: Integer;
  propKey, realKey: string;
  propVal, keyExpr: TFloriaJSExprNode;
  methodFn: TFloriaJSFunctionExpr;
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
      keyExpr := ParseAssignmentExpression();
      Consume(tkRBracket, 'Expected '']'' after computed property name');

      if Match(tkColon) then
      begin
        propVal := ParseAssignmentExpression();
        obj.AddComputedProperty(keyExpr, propVal);
      end
      else if Check(tkLParen) then
      begin
        methodFn := ParseMethodBody('');
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
      if Match(tkLBracket) then
      begin
        keyExpr := ParseAssignmentExpression();
        Consume(tkRBracket, 'Expected '']'' after computed getter name');
        methodFn := ParseMethodBody('');
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
        methodFn := ParseMethodBody(realKey);
        obj.AddGetter(realKey, methodFn);
      end;
    end
    // Check for setter: set x(v) { ... } or set [k](v) { ... }
    else if (propKey = 'set') and (not Check(tkColon)) and (not Check(tkComma)) and (not Check(tkRBrace)) and (not Check(tkLParen)) then
    begin
      if Match(tkLBracket) then
      begin
        keyExpr := ParseAssignmentExpression();
        Consume(tkRBracket, 'Expected '']'' after computed setter name');
        methodFn := ParseMethodBody('');
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
        methodFn := ParseMethodBody(realKey);
        obj.AddSetter(realKey, methodFn);
      end;
    end
    // Method syntax: f() { ... }
    else if Check(tkLParen) then
    begin
      methodFn := ParseMethodBody(propKey);
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

function TFloriaJSParser.ParseFunctionExpr(AIsAsync: Boolean = False): TFloriaJSExprNode;
var
  fnName: string;
  fnExpr: TFloriaJSFunctionExpr;
  startLine, startCol: Integer;
  bodyStmt: TFloriaJSStmtNode;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  if Match(tkIdentifier) then
    fnName := FPrevious.Text
  else
    fnName := '';

  fnExpr := TFloriaJSFunctionExpr.Create(fnName, False, startLine, startCol, AIsAsync);
  ParseFormalParameters(fnExpr.Parameters);
  bodyStmt := ParseBlockStatement();
  fnExpr.SetBody(bodyStmt);
  Result := fnExpr;
end;

procedure TFloriaJSParser.ParseFormalParameters(AParams: TStringList);
var
  paramName: string;
  defaultExpr, pat: TFloriaJSExprNode;
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
        AParams.Add(paramName);
        Break; // Rest parameter must be last
      end;

      // 2. Destructuring pattern: [a, b] or { a, b }
      if Check(tkLBracket) then
      begin
        Advance();
        pat := ParseArrayLiteral();
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
    until not Match(tkComma);
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
begin
  { Prefix parsing }
  if FCurrent.Kind = tkNew then
  begin
    op := FCurrent;
    Advance();
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
          if Match(tkIdentifier) then
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
          left := TFloriaJSMemberExpr.CreateNamed(left, memberPropName,
            op.Line, op.Column, op.Kind = tkQuestionDot);
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
      tkPowerAssign, tkNullishAssign, tkAndAssign, tkOrAssign:
      begin
        if IsOptionalChainTarget(left) then
          ErrorAtCurrent('Invalid left-hand side in assignment');
        right := ParsePrecedence(PREC_ASSIGNMENT);
        left := TFloriaJSAssignExpr.Create(left, op.Kind, right, op.Line, op.Column);
      end;

      { Arrow Function: x => expr or x => { statements } }
      tkArrow:
      begin
        if left is TFloriaJSIdentifierExpr then
        begin
          fnExpr := TFloriaJSFunctionExpr.Create('', True, left.Line, left.Column);
          fnExpr.AddParameter(TFloriaJSIdentifierExpr(left).Name);
          left.Free();
          if Check(tkLBrace) then
            fnExpr.SetBody(ParseBlockStatement())
          else
            fnExpr.SetBody(TFloriaJSReturnStmt.Create(ParseAssignmentExpression(), op.Line, op.Column));
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
        left := TFloriaJSUnaryExpr.Create(op.Kind, left, False, op.Line, op.Column);
      end;

    else
      { Standard Binary Infix Operators }
      if op.Kind = tkPower then
        nextPrec := prec { Exponentiation is right-associative }
      else
        nextPrec := prec + 1;

      right := ParsePrecedence(nextPrec);
      left := TFloriaJSBinaryExpr.Create(left, op.Kind, right, op.Line, op.Column);
    end;
  end;

  Result := left;
end;

function TFloriaJSParser.ParseAssignmentExpression(): TFloriaJSExprNode;
begin
  Result := ParsePrecedence(PREC_ASSIGNMENT);
end;

function TFloriaJSParser.ParseExpression(): TFloriaJSExprNode;
begin
  Result := ParsePrecedence(PREC_COMMA);
end;

{ Statement Parsing }

function TFloriaJSParser.ParseDeclaration(): TFloriaJSStmtNode;
begin
  if Match(tkLet) then
    Result := ParseVarDeclaration(tkLet)
  else if Match(tkConst) then
    Result := ParseVarDeclaration(tkConst)
  else if Match(tkVar) then
    Result := ParseVarDeclaration(tkVar)
  else if (FCurrent.Kind = tkAsync) and (FLexer.PeekToken().Kind = tkFunction) then
  begin
    Advance(); { Consume tkAsync }
    Advance(); { Consume tkFunction }
    Result := ParseFunctionDeclaration(True);
  end
  else if Match(tkFunction) then
    Result := ParseFunctionDeclaration()
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

  Match(tkSemicolon); { Optional semicolon }
  Result := varStmt;
end;

function TFloriaJSParser.ParseFunctionDeclaration(AIsAsync: Boolean = False): TFloriaJSFunctionDecl;
var
  fnName: string;
  fnDecl: TFloriaJSFunctionDecl;
  startLine, startCol: Integer;
  bodyBlock: TFloriaJSBlockStmt;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  if Match(tkIdentifier) then
    fnName := FPrevious.Text
  else
  begin
    ErrorAtCurrent('Expected function name');
    fnName := 'anonymous';
  end;

  fnDecl := TFloriaJSFunctionDecl.Create(fnName, startLine, startCol, AIsAsync);
  ParseFormalParameters(fnDecl.Parameters);
  bodyBlock := ParseBlockStatement();
  fnDecl.SetBody(bodyBlock);
  Result := fnDecl;
end;

function TFloriaJSParser.ParseStatement(): TFloriaJSStmtNode;
var
  lbl: string;
  stmt: TFloriaJSStmtNode;
  startLine, startCol: Integer;
begin
  { Empty statement: an empty block has the same effect and keeps the
    completion value unchanged. }
  if Match(tkSemicolon) then
    Exit(TFloriaJSBlockStmt.Create(FPrevious.Line, FPrevious.Column));

  if (FCurrent.Kind = tkIdentifier) and (FLexer.PeekToken().Kind = tkColon) then
  begin
    startLine := FCurrent.Line;
    startCol := FCurrent.Column;
    lbl := FCurrent.Text;
    Advance(); { Consume identifier }
    Advance(); { Consume ':' }
    stmt := ParseStatement();
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
  else if Check(tkWith) then
  begin
    { Unsupported syntax fails at parse time rather than surfacing as an
      undeclared-name ReferenceError at run time. }
    ErrorAtCurrent('''with'' statements are not supported');
    Advance();
    Result := TFloriaJSBlockStmt.Create(FPrevious.Line, FPrevious.Column);
  end
  else if Check(tkLBrace) then
    Result := ParseBlockStatement()
  else
    Result := ParseExpressionStatement();
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
  Match(tkSemicolon);

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
  isOf: Boolean;
  varStmt: TFloriaJSVarStmt;
  declInit: TFloriaJSExprNode;
  pattern: TFloriaJSExprNode;
  forInOf: TFloriaJSForInOfStmt;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

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
      Exit(TFloriaJSForInOfStmt.Create(varKind, varName, isOf, iterable, body, startLine, startCol));
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
    Exit(TFloriaJSForInOfStmt.Create(tkEOF, varName, isOf, iterable, body, startLine, startCol));
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
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  Consume(tkLParen, 'Expected ''('' after ''switch''');
  discriminant := ParseExpression();
  Consume(tkRParen, 'Expected '')'' after switch discriminant');
  Consume(tkLBrace, 'Expected ''{'' at start of switch body');

  switchStmt := TFloriaJSSwitchStmt.Create(discriminant, startLine, startCol);

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

  { A throw statement always carries the value that is thrown. }
  expr := ParseExpression();
  Match(tkSemicolon);
  Result := TFloriaJSThrowStmt.Create(expr, startLine, startCol);
end;

function TFloriaJSParser.ParseBlockStatement(): TFloriaJSBlockStmt;
var
  block: TFloriaJSBlockStmt;
  startLine, startCol: Integer;
begin
  Consume(tkLBrace, 'Expected ''{'' at start of block');
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  block := TFloriaJSBlockStmt.Create(startLine, startCol);

  while (not Check(tkRBrace)) and (not IsAtEnd()) do
  begin
    block.AddStatement(ParseDeclaration());
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

  if (not Check(tkSemicolon)) and (not Check(tkRBrace)) and (not IsAtEnd()) then
    arg := ParseExpression()
  else
    arg := nil;

  Match(tkSemicolon);
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
  Match(tkSemicolon);
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
  if Match(tkIdentifier) then
    lbl := FPrevious.Text;
  Match(tkSemicolon);
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
  if Match(tkIdentifier) then
    lbl := FPrevious.Text;
  Match(tkSemicolon);
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
  Match(tkSemicolon);
  Result := TFloriaJSExprStmt.Create(expr, startLine, startCol);
end;

function TFloriaJSParser.ParseProgram(): TFloriaJSProgram;
var
  prog: TFloriaJSProgram;
begin
  prog := TFloriaJSProgram.Create(FCurrent.Line, FCurrent.Column);
  while not IsAtEnd() do
  begin
    prog.AddStatement(ParseDeclaration());
  end;
  Result := prog;
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
