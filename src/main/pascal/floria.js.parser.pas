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
    function  GetInfixPrecedence(AKind: TFloriaJSTokenKind): Integer;
    function  ParsePrecedence(APrec: Integer): TFloriaJSExprNode;
    function  ParseAssignmentExpression(): TFloriaJSExprNode;
    function  ParsePrimary(): TFloriaJSExprNode;
    function  ParseUnaryPrefix(): TFloriaJSExprNode;
    function  ParseNewExpression(ANewToken: TFloriaJSToken): TFloriaJSExprNode;
    function  ParseMemberTail(ALeft: TFloriaJSExprNode): TFloriaJSExprNode;
    function  ParseArrayLiteral(): TFloriaJSExprNode;
    function  ParseObjectLiteral(): TFloriaJSExprNode;
    function  ParseFunctionExpr(AIsAsync: Boolean = False): TFloriaJSExprNode;
    function  ExtractParameters(AExpr: TFloriaJSExprNode; AParams: TStrings): Boolean;

    { Statements & Declarations }
    function  ParseStatement(): TFloriaJSStmtNode;
    function  ParseDeclaration(): TFloriaJSStmtNode;
    function  ParseVarDeclaration(AKind: TFloriaJSTokenKind): TFloriaJSVarStmt;
    function  ParseFunctionDeclaration(AIsAsync: Boolean = False): TFloriaJSFunctionDecl;
    function  ParseIfStatement(): TFloriaJSIfStmt;
    function  ParseWhileStatement(): TFloriaJSWhileStmt;
    function  ParseDoWhileStatement(): TFloriaJSWhileStmt;
    function  ParseForStatement(): TFloriaJSForStmt;
    function  ParseSwitchStatement(): TFloriaJSSwitchStmt;
    function  ParseTryStatement(): TFloriaJSTryStmt;
    function  ParseThrowStatement(): TFloriaJSThrowStmt;
    function  ParseBlockStatement(): TFloriaJSBlockStmt;
    function  ParseReturnStatement(): TFloriaJSReturnStmt;
    function  ParseBreakStatement(): TFloriaJSBreakStmt;
    function  ParseContinueStatement(): TFloriaJSContinueStmt;
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

function TFloriaJSParser.GetInfixPrecedence(AKind: TFloriaJSTokenKind): Integer;
begin
  case AKind of
    tkComma:
      Result := PREC_COMMA;
    tkAssign, tkPlusAssign, tkMinusAssign, tkMultiplyAssign, tkDivideAssign, tkModuloAssign,
    tkPowerAssign, tkNullishAssign, tkArrow:
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
    tkLParen, tkDot, tkLBracket, tkQuestionDot:
      Result := PREC_CALL;
  else
    Result := PREC_NONE;
  end;
end;

{ Expression Parsing }

function TFloriaJSParser.ParsePrimary(): TFloriaJSExprNode;
var
  tok: TFloriaJSToken;
  expr: TFloriaJSExprNode;
  fnExpr: TFloriaJSFunctionExpr;
  callExpr: TFloriaJSCallExpr;
  paramName: string;
begin
  tok := FCurrent;

  { Literals }
  if Match(tkNumber) then
    Exit(TFloriaJSLiteralExpr.CreateNumber(tok.NumberValue, tok.Line, tok.Column));

  if Match(tkString) or Match(tkTemplateString) then
    Exit(TFloriaJSLiteralExpr.CreateString(tok.Text, tok.Line, tok.Column));

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
      expr.Free();
      if Check(tkLBrace) then
        fnExpr.SetBody(ParseBlockStatement())
      else
        fnExpr.SetBody(TFloriaJSReturnStmt.Create(ParseAssignmentExpression(), FPrevious.Line, FPrevious.Column));
      Exit(fnExpr);
    end;
    Exit(expr);
  end;

  ErrorAtCurrent('Expected expression');
  Advance();
  Result := TFloriaJSLiteralExpr.CreateUndefined(tok.Line, tok.Column);
end;

function TFloriaJSParser.ParseUnaryPrefix(): TFloriaJSExprNode;
var
  op: TFloriaJSToken;
  operand: TFloriaJSExprNode;
begin
  op := FCurrent;
  Advance();
  operand := ParsePrecedence(PREC_UNARY);
  Result := TFloriaJSUnaryExpr.Create(op.Kind, operand, True, op.Line, op.Column);
end;

function TFloriaJSParser.ParseMemberTail(ALeft: TFloriaJSExprNode): TFloriaJSExprNode;
var
  op: TFloriaJSToken;
  memberPropName: string;
  computedProp: TFloriaJSExprNode;
begin
  Result := ALeft;
  while (FCurrent.Kind = tkDot) or (FCurrent.Kind = tkLBracket) do
  begin
    op := FCurrent;
    Advance();

    if op.Kind = tkDot then
    begin
      if Match(tkIdentifier) then
        memberPropName := FPrevious.Text
      else if FCurrent.Kind in [tkCatch, tkFinally, tkFunction, tkAsync, tkAwait, tkNew, tkDelete, tkTypeof, tkInstanceof, tkIn, tkThis, tkConst, tkLet, tkVar, tkIf, tkElse, tkFor, tkWhile, tkDo, tkBreak, tkContinue, tkSwitch, tkCase, tkDefault, tkTry, tkThrow, tkReturn, tkTrue, tkFalse, tkNull, tkUndefined] then
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

  callExpr := TFloriaJSCallExpr.Create(callee, ANewToken.Line, ANewToken.Column, True);

  { The argument list is optional: new Foo is the same as new Foo(). }
  if Match(tkLParen) then
  begin
    if not Check(tkRParen) then
    begin
      repeat
        if Check(tkRParen) then
          Break;
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

  if not Check(tkRBracket) then
  begin
    repeat
      if Check(tkRBracket) then
        Break;
      arr.AddElement(ParseAssignmentExpression());
    until not Match(tkComma);
  end;

  Consume(tkRBracket, 'Expected '']'' after array elements');
  Result := arr;
end;

function TFloriaJSParser.ParseObjectLiteral(): TFloriaJSExprNode;
var
  obj: TFloriaJSObjectExpr;
  startLine, startCol: Integer;
  propKey: string;
  propVal: TFloriaJSExprNode;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  obj := TFloriaJSObjectExpr.Create(startLine, startCol);

  if not Check(tkRBrace) then
  begin
    repeat
      if Check(tkRBrace) then
        Break;

      if Match(tkIdentifier) or Match(tkString) then
        propKey := FPrevious.Text
      else
      begin
        ErrorAtCurrent('Expected property key identifier or string literal in object literal');
        Break;
      end;

      Consume(tkColon, 'Expected '':'' after object property key');
      propVal := ParseAssignmentExpression();
      obj.AddProperty(propKey, propVal);
    until not Match(tkComma);
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
  Consume(tkLParen, 'Expected ''('' after function name/keyword');

  if not Check(tkRParen) then
  begin
    repeat
      if Match(tkIdentifier) then
        fnExpr.AddParameter(FPrevious.Text)
      else
      begin
        ErrorAtCurrent('Expected parameter name');
        Break;
      end;
    until not Match(tkComma);
  end;

  Consume(tkRParen, 'Expected '')'' after parameters');
  bodyStmt := ParseBlockStatement();
  fnExpr.SetBody(bodyStmt);
  Result := fnExpr;
end;

function TFloriaJSParser.ExtractParameters(AExpr: TFloriaJSExprNode; AParams: TStrings): Boolean;
begin
  if AExpr = nil then
    Exit(True);

  if AExpr is TFloriaJSIdentifierExpr then
  begin
    AParams.Add(TFloriaJSIdentifierExpr(AExpr).Name);
    Exit(True);
  end;

  if (AExpr is TFloriaJSBinaryExpr) and (TFloriaJSBinaryExpr(AExpr).Op = tkComma) then
  begin
    Result := ExtractParameters(TFloriaJSBinaryExpr(AExpr).Left, AParams) and
              ExtractParameters(TFloriaJSBinaryExpr(AExpr).Right, AParams);
    Exit;
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
  else if FCurrent.Kind in [tkNot, tkBitNot, tkMinus, tkPlus, tkPlusPlus, tkMinusMinus, tkTypeof, tkDelete, tkAwait] then
    left := ParseUnaryPrefix()
  else
    left := ParsePrimary();

  { Infix parsing }
  while not IsAtEnd() do
  begin
    prec := GetInfixPrecedence(FCurrent.Kind);
    if prec < APrec then
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
            callExpr.AddArgument(ParseAssignmentExpression());
          until not Match(tkComma);
        end;
        Consume(tkRParen, 'Expected '')'' after argument list');
        left := callExpr;
      end;

      { Member Access: obj.prop }
      tkDot:
      begin
        if Match(tkIdentifier) then
          memberPropName := FPrevious.Text
        else if FCurrent.Kind in [tkCatch, tkFinally, tkFunction, tkAsync, tkAwait, tkNew, tkDelete, tkTypeof, tkInstanceof, tkIn, tkThis, tkConst, tkLet, tkVar, tkIf, tkElse, tkFor, tkWhile, tkDo, tkBreak, tkContinue, tkSwitch, tkCase, tkDefault, tkTry, tkThrow, tkReturn, tkTrue, tkFalse, tkNull, tkUndefined] then
        begin
          memberPropName := FCurrent.Text;
          Advance();
        end
        else
        begin
          ErrorAtCurrent('Expected property name after ''.''');
          memberPropName := '';
        end;
        left := TFloriaJSMemberExpr.CreateNamed(left, memberPropName, op.Line, op.Column);
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

      { Assignment Operators: =, +=, -=, etc. }
      tkAssign, tkPlusAssign, tkMinusAssign, tkMultiplyAssign, tkDivideAssign, tkModuloAssign:
      begin
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
  else
    Result := ParseStatement();
end;

function TFloriaJSParser.ParseVarDeclaration(AKind: TFloriaJSTokenKind): TFloriaJSVarStmt;
var
  varStmt: TFloriaJSVarStmt;
  startLine, startCol: Integer;
  declName: string;
  declInit: TFloriaJSExprNode;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;
  varStmt := TFloriaJSVarStmt.Create(AKind, startLine, startCol);

  repeat
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
  Consume(tkLParen, 'Expected ''('' after function name');

  if not Check(tkRParen) then
  begin
    repeat
      if Match(tkIdentifier) then
        fnDecl.AddParameter(FPrevious.Text)
      else
      begin
        ErrorAtCurrent('Expected parameter name');
        Break;
      end;
    until not Match(tkComma);
  end;

  Consume(tkRParen, 'Expected '')'' after function parameter list');
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
      TFloriaJSWhileStmt(stmt).LabelName := lbl;
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

function TFloriaJSParser.ParseForStatement(): TFloriaJSForStmt;
var
  init: TFloriaJSASTNode;
  test, update: TFloriaJSExprNode;
  body: TFloriaJSStmtNode;
  startLine, startCol: Integer;
begin
  startLine := FPrevious.Line;
  startCol := FPrevious.Column;

  Consume(tkLParen, 'Expected ''('' after ''for''');

  { Initializer }
  if Match(tkSemicolon) then
    init := nil
  else if Match(tkLet) then
    init := ParseVarDeclaration(tkLet)
  else if Match(tkConst) then
    init := ParseVarDeclaration(tkConst)
  else if Match(tkVar) then
    init := ParseVarDeclaration(tkVar)
  else
  begin
    init := ParseExpressionStatement();
  end;

  { Condition }
  if Match(tkSemicolon) then
    test := nil
  else
  begin
    test := ParseExpression();
    Consume(tkSemicolon, 'Expected '';'' after for loop condition');
  end;

  { Update }
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
