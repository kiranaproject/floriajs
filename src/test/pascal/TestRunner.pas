{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Automated Test Suite                            }
{                                                                          }
{   Runs unit tests verifying floriajs types, engine, and lexer/tokenizer. }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

program TestRunner;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math,
  fpcunit, testregistry, consoletestrunner,
  floria.js.types, floria.js.lexer, floria.js.core, floriajs;

type
  { Test 1: Core Types & Result Helpers }
  TFloriaJSTypesTest = class(TTestCase)
  published
    procedure TestVersionConstant();
    procedure TestOkResultHelper();
    procedure TestErrorResultHelper();
  end;

  { Test 2: Engine & Context Lifecycle }
  TFloriaJSEngineTest = class(TTestCase)
  published
    procedure TestEngineCreationAndDefaults();
    procedure TestContextCreation();
    procedure TestContextVariables();
    procedure TestScriptExecution();
    procedure TestContextDestruction();
  end;

  { Test 3: Lexer & Tokenizer Suite }
  TFloriaJSLexerTest = class(TTestCase)
  published
    procedure TestIdentifiersAndKeywords();
    procedure TestNumbers();
    procedure TestStringsAndEscapes();
    procedure TestTemplateStrings();
    procedure TestOperatorsAndPunctuation();
    procedure TestComments();
    procedure TestLineAndColumnPositions();
    procedure TestPeekAndNextToken();
    procedure TestComplexScriptTokenStream();
  end;

  { Test 4: AST Hierarchy Suite }
  TFloriaJSASTTest = class(TTestCase)
  published
    procedure TestLiteralNodes();
    procedure TestBinaryAndUnaryNodes();
    procedure TestCallAndMemberNodes();
    procedure TestObjectAndArrayNodes();
    procedure TestQMLComponentASTNode();
  end;

  { Test 5: Pratt Parser Suite }
  TFloriaJSParserTest = class(TTestCase)
  published
    procedure TestArithmeticPrecedence();
    procedure TestExponentiationRightAssociative();
    procedure TestTernaryAndNullish();
    procedure TestMemberAndCallChaining();
    procedure TestVariableDeclarations();
    procedure TestIfElseStatement();
    procedure TestWhileAndForLoops();
    procedure TestFunctionDeclaration();
    procedure TestDeclarativeQMLComponent();
    procedure TestParserErrorHandling();
  end;

{ TFloriaJSTypesTest }

procedure TFloriaJSTypesTest.TestVersionConstant();
begin
  AssertEquals('Version string must match snapshot', '0.0.1-SNAPSHOT', FLORIA_JS_VERSION_STRING);
  AssertEquals('Version major must be 0', 0, FLORIA_JS_VERSION_MAJOR);
end;

procedure TFloriaJSTypesTest.TestOkResultHelper();
var
  res: TFloriaJSResult;
begin
  res := FloriaJSMakeOkResult('hello');
  AssertTrue('Result must be success', res.Success);
  AssertEquals('Result string value must match', 'hello', res.StringValue);
  AssertEquals('Result type must be string', Ord(fjstString), Ord(res.ResultType));
end;

procedure TFloriaJSTypesTest.TestErrorResultHelper();
var
  res: TFloriaJSResult;
begin
  res := FloriaJSMakeErrorResult('SyntaxError');
  AssertFalse('Result must not be success', res.Success);
  AssertEquals('Error message must match', 'SyntaxError', res.ErrorMessage);
  AssertEquals('Result type must be error', Ord(fjstError), Ord(res.ResultType));
end;

{ TFloriaJSEngineTest }

procedure TFloriaJSEngineTest.TestEngineCreationAndDefaults();
var
  engine: TFloriaJSEngine;
begin
  engine := TFloriaJSEngine.Create();
  try
    AssertTrue('Engine must be initialized', engine.Initialized);
    AssertNotNull('Engine must have default context', engine.DefaultContext);
    AssertTrue('Memory limit must be positive', engine.MemoryLimit > 0);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEngineTest.TestContextCreation();
var
  engine: TFloriaJSEngine;
  ctx: TFloriaJSContext;
begin
  engine := TFloriaJSEngine.Create();
  try
    ctx := engine.CreateContext('sandbox');
    AssertNotNull('Created context must not be nil', ctx);
    AssertEquals('Context name must match', 'sandbox', ctx.Name);
    AssertSame('Context engine must be parent engine', engine, ctx.Engine);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEngineTest.TestContextVariables();
var
  engine: TFloriaJSEngine;
  ctx: TFloriaJSContext;
begin
  engine := TFloriaJSEngine.Create();
  try
    ctx := engine.DefaultContext;
    ctx.SetVariable('app_name', 'FloriaJS');
    AssertTrue('Context must have app_name', ctx.HasVariable('app_name'));
    AssertEquals('Context variable value must match', 'FloriaJS', ctx.GetVariable('app_name'));

    ctx.Reset();
    AssertFalse('Variables must be cleared after reset', ctx.HasVariable('app_name'));
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEngineTest.TestScriptExecution();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('console.log("hello");');
    AssertTrue('Execution result must be success', res.Success);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEngineTest.TestContextDestruction();
var
  engine: TFloriaJSEngine;
  ctx: TFloriaJSContext;
begin
  engine := TFloriaJSEngine.Create();
  try
    ctx := engine.CreateContext('temp');
    AssertNotNull('Context must exist', ctx);
    engine.DestroyContext(ctx);
  finally
    engine.Free();
  end;
end;

{ TFloriaJSLexerTest }

procedure TFloriaJSLexerTest.TestIdentifiersAndKeywords();
var
  lexer: TFloriaJSLexer;
  tok: TFloriaJSToken;
begin
  lexer := TFloriaJSLexer.Create('let const var function return if else while true false null undefined myVar _private $elem');
  try
    tok := lexer.NextToken();
    AssertEquals('Must be let', Ord(tkLet), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be const', Ord(tkConst), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be var', Ord(tkVar), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be function', Ord(tkFunction), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be return', Ord(tkReturn), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be if', Ord(tkIf), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be else', Ord(tkElse), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be while', Ord(tkWhile), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be true', Ord(tkTrue), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be false', Ord(tkFalse), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be null', Ord(tkNull), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be undefined', Ord(tkUndefined), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be myVar identifier', Ord(tkIdentifier), Ord(tok.Kind));
    AssertEquals('Identifier text must match', 'myVar', tok.Text);

    tok := lexer.NextToken();
    AssertEquals('Must be _private identifier', Ord(tkIdentifier), Ord(tok.Kind));
    AssertEquals('Identifier text must match', '_private', tok.Text);

    tok := lexer.NextToken();
    AssertEquals('Must be $elem identifier', Ord(tkIdentifier), Ord(tok.Kind));
    AssertEquals('Identifier text must match', '$elem', tok.Text);

    tok := lexer.NextToken();
    AssertEquals('Must be EOF', Ord(tkEOF), Ord(tok.Kind));
  finally
    lexer.Free();
  end;
end;

procedure TFloriaJSLexerTest.TestNumbers();
var
  lexer: TFloriaJSLexer;
  tok: TFloriaJSToken;
begin
  lexer := TFloriaJSLexer.Create('42 3.14159 .5 1e3 0xFF 0b1011 0o77');
  try
    { Integer }
    tok := lexer.NextToken();
    AssertEquals('Kind must be number', Ord(tkNumber), Ord(tok.Kind));
    AssertEquals('Number value 42', 42.0, tok.NumberValue, 0.0001);

    { Decimal Float }
    tok := lexer.NextToken();
    AssertEquals('Kind must be number', Ord(tkNumber), Ord(tok.Kind));
    AssertEquals('Number value 3.14159', 3.14159, tok.NumberValue, 0.0001);

    { Leading dot float: .5 }
    tok := lexer.NextToken();
    AssertEquals('Kind must be number', Ord(tkNumber), Ord(tok.Kind));
    AssertEquals('Number value 0.5', 0.5, tok.NumberValue, 0.0001);

    { Scientific notation: 1e3 = 1000 }
    tok := lexer.NextToken();
    AssertEquals('Kind must be number', Ord(tkNumber), Ord(tok.Kind));
    AssertEquals('Number value 1000.0', 1000.0, tok.NumberValue, 0.0001);

    { Hex: 0xFF = 255 }
    tok := lexer.NextToken();
    AssertEquals('Kind must be number', Ord(tkNumber), Ord(tok.Kind));
    AssertEquals('Number value 255.0', 255.0, tok.NumberValue, 0.0001);

    { Binary: 0b1011 = 11 }
    tok := lexer.NextToken();
    AssertEquals('Kind must be number', Ord(tkNumber), Ord(tok.Kind));
    AssertEquals('Number value 11.0', 11.0, tok.NumberValue, 0.0001);

    { Octal: 0o77 = 63 }
    tok := lexer.NextToken();
    AssertEquals('Kind must be number', Ord(tkNumber), Ord(tok.Kind));
    AssertEquals('Number value 63.0', 63.0, tok.NumberValue, 0.0001);

    tok := lexer.NextToken();
    AssertEquals('Must be EOF', Ord(tkEOF), Ord(tok.Kind));
  finally
    lexer.Free();
  end;
end;

procedure TFloriaJSLexerTest.TestStringsAndEscapes();
var
  lexer: TFloriaJSLexer;
  tok: TFloriaJSToken;
begin
  lexer := TFloriaJSLexer.Create('''hello'' "world" ''hello\nworld'' "tab\there" ''quote\''''');
  try
    { Single quote string }
    tok := lexer.NextToken();
    AssertEquals('Kind must be string', Ord(tkString), Ord(tok.Kind));
    AssertEquals('String text must match', 'hello', tok.Text);

    { Double quote string }
    tok := lexer.NextToken();
    AssertEquals('Kind must be string', Ord(tkString), Ord(tok.Kind));
    AssertEquals('String text must match', 'world', tok.Text);

    { Escape newline \n }
    tok := lexer.NextToken();
    AssertEquals('Kind must be string', Ord(tkString), Ord(tok.Kind));
    AssertEquals('String text with newline', 'hello'#10'world', tok.Text);

    { Escape tab \t }
    tok := lexer.NextToken();
    AssertEquals('Kind must be string', Ord(tkString), Ord(tok.Kind));
    AssertEquals('String text with tab', 'tab'#9'here', tok.Text);

    { Escaped quote \' }
    tok := lexer.NextToken();
    AssertEquals('Kind must be string', Ord(tkString), Ord(tok.Kind));
    AssertEquals('String text with quote', 'quote''', tok.Text);

    tok := lexer.NextToken();
    AssertEquals('Must be EOF', Ord(tkEOF), Ord(tok.Kind));
  finally
    lexer.Free();
  end;
end;

procedure TFloriaJSLexerTest.TestTemplateStrings();
var
  lexer: TFloriaJSLexer;
  tok: TFloriaJSToken;
begin
  lexer := TFloriaJSLexer.Create('`template string with newline'#10'and spaces`');
  try
    tok := lexer.NextToken();
    AssertEquals('Kind must be template string', Ord(tkTemplateString), Ord(tok.Kind));
    AssertEquals('Template string content matches', 'template string with newline'#10'and spaces', tok.Text);

    tok := lexer.NextToken();
    AssertEquals('Must be EOF', Ord(tkEOF), Ord(tok.Kind));
  finally
    lexer.Free();
  end;
end;

procedure TFloriaJSLexerTest.TestOperatorsAndPunctuation();
var
  lexer: TFloriaJSLexer;
  tok: TFloriaJSToken;
begin
  lexer := TFloriaJSLexer.Create('=== !== == != <= >= < > && || ?? ++ -- += -= *= /= ** => { } ( ) [ ] ; , : . ?');
  try
    tok := lexer.NextToken();
    AssertEquals('===', Ord(tkStrictEqual), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('!==', Ord(tkStrictNotEqual), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('==', Ord(tkEqual), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('!=', Ord(tkNotEqual), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('<=', Ord(tkLessEqual), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('>=', Ord(tkGreaterEqual), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('<', Ord(tkLessThan), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('>', Ord(tkGreaterThan), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('&&', Ord(tkAnd), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('||', Ord(tkOr), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('??', Ord(tkNullish), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('++', Ord(tkPlusPlus), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('--', Ord(tkMinusMinus), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('+=', Ord(tkPlusAssign), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('-=', Ord(tkMinusAssign), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('*=', Ord(tkMultiplyAssign), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('/=', Ord(tkDivideAssign), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('**', Ord(tkPower), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('=>', Ord(tkArrow), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('{', Ord(tkLBrace), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('}', Ord(tkRBrace), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('(', Ord(tkLParen), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals(')', Ord(tkRParen), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('[', Ord(tkLBracket), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals(']', Ord(tkRBracket), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals(';', Ord(tkSemicolon), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals(',', Ord(tkComma), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals(':', Ord(tkColon), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('.', Ord(tkDot), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('?', Ord(tkQuestion), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be EOF', Ord(tkEOF), Ord(tok.Kind));
  finally
    lexer.Free();
  end;
end;

procedure TFloriaJSLexerTest.TestComments();
var
  lexer: TFloriaJSLexer;
  tok: TFloriaJSToken;
begin
  lexer := TFloriaJSLexer.Create('let a = 1; // single line comment'#10'/* multi-line'#10'comment */ let b = 2;');
  try
    tok := lexer.NextToken();
    AssertEquals('let', Ord(tkLet), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('a', Ord(tkIdentifier), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('=', Ord(tkAssign), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('1', Ord(tkNumber), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals(';', Ord(tkSemicolon), Ord(tok.Kind));

    { Comments should be transparently skipped by NextToken }
    tok := lexer.NextToken();
    AssertEquals('let b', Ord(tkLet), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('b', Ord(tkIdentifier), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('=', Ord(tkAssign), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('2', Ord(tkNumber), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals(';', Ord(tkSemicolon), Ord(tok.Kind));

    tok := lexer.NextToken();
    AssertEquals('Must be EOF', Ord(tkEOF), Ord(tok.Kind));
  finally
    lexer.Free();
  end;
end;

procedure TFloriaJSLexerTest.TestLineAndColumnPositions();
var
  lexer: TFloriaJSLexer;
  tok: TFloriaJSToken;
begin
  lexer := TFloriaJSLexer.Create('let x = 10;'#10'let y = 20;');
  try
    { Line 1: let }
    tok := lexer.NextToken();
    AssertEquals('Line 1', 1, tok.Line);
    AssertEquals('Column 1', 1, tok.Column);

    { Line 1: x }
    tok := lexer.NextToken();
    AssertEquals('Line 1', 1, tok.Line);
    AssertEquals('Column 5', 5, tok.Column);

    { Line 1: = }
    tok := lexer.NextToken();
    AssertEquals('Line 1', 1, tok.Line);
    AssertEquals('Column 7', 7, tok.Column);

    { Line 1: 10 }
    tok := lexer.NextToken();
    AssertEquals('Line 1', 1, tok.Line);
    AssertEquals('Column 9', 9, tok.Column);

    { Line 1: ; }
    tok := lexer.NextToken();
    AssertEquals('Line 1', 1, tok.Line);
    AssertEquals('Column 11', 11, tok.Column);

    { Line 2: let }
    tok := lexer.NextToken();
    AssertEquals('Line 2', 2, tok.Line);
    AssertEquals('Column 1', 1, tok.Column);
  finally
    lexer.Free();
  end;
end;

procedure TFloriaJSLexerTest.TestPeekAndNextToken();
var
  lexer: TFloriaJSLexer;
  peekTok, nextTok: TFloriaJSToken;
begin
  lexer := TFloriaJSLexer.Create('count = 100');
  try
    peekTok := lexer.PeekToken();
    AssertEquals('Peeked token must be count', 'count', peekTok.Text);
    AssertEquals('Peeked token kind must be identifier', Ord(tkIdentifier), Ord(peekTok.Kind));

    { Peeking again returns same token without advancing }
    peekTok := lexer.PeekToken();
    AssertEquals('Second peek must still be count', 'count', peekTok.Text);

    { NextToken consumes peeked token }
    nextTok := lexer.NextToken();
    AssertEquals('Next token matches peeked count', 'count', nextTok.Text);

    { Following token is '=' }
    nextTok := lexer.NextToken();
    AssertEquals('Next token is =', '=', nextTok.Text);
  finally
    lexer.Free();
  end;
end;

procedure TFloriaJSLexerTest.TestComplexScriptTokenStream();
var
  lexer: TFloriaJSLexer;
  tok: TFloriaJSToken;
  tokenCount: Integer;
begin
  lexer := TFloriaJSLexer.Create(
    'function calculateArea(w, h) {' + LineEnding +
    '  if (w <= 0 || h <= 0) return 0;' + LineEnding +
    '  const factor = 1.25;' + LineEnding +
    '  return (w * h) * factor;' + LineEnding +
    '}'
  );
  try
    tokenCount := 0;
    repeat
      tok := lexer.NextToken();
      if tok.Kind <> tkEOF then
        Inc(tokenCount);
    until (tok.Kind = tkEOF) or (tok.Kind = tkError);

    AssertTrue('Must have tokenized multiple tokens (> 20)', tokenCount > 20);
    AssertEquals('Last token must be EOF with no errors', Ord(tkEOF), Ord(tok.Kind));
  finally
    lexer.Free();
  end;
end;

{ TFloriaJSASTTest }

procedure TFloriaJSASTTest.TestLiteralNodes();
var
  numLit: TFloriaJSLiteralExpr;
  strLit: TFloriaJSLiteralExpr;
  boolLit: TFloriaJSLiteralExpr;
  nullLit: TFloriaJSLiteralExpr;
  undefLit: TFloriaJSLiteralExpr;
begin
  numLit := TFloriaJSLiteralExpr.CreateNumber(123.456, 1, 1);
  try
    AssertEquals('ValueType must be number', Ord(fjstNumber), Ord(numLit.ValueType));
    AssertEquals('NumberVal must match', 123.456, numLit.NumberVal, 0.0001);
    AssertEquals('Line must be 1', 1, numLit.Line);
    AssertEquals('Column must be 1', 1, numLit.Column);
  finally
    numLit.Free();
  end;

  strLit := TFloriaJSLiteralExpr.CreateString('Floria', 2, 5);
  try
    AssertEquals('ValueType must be string', Ord(fjstString), Ord(strLit.ValueType));
    AssertEquals('StringVal must match', 'Floria', strLit.StringVal);
  finally
    strLit.Free();
  end;

  boolLit := TFloriaJSLiteralExpr.CreateBoolean(True, 3, 1);
  try
    AssertEquals('ValueType must be bool', Ord(fjstBoolean), Ord(boolLit.ValueType));
    AssertTrue('BoolVal must be true', boolLit.BoolVal);
  finally
    boolLit.Free();
  end;

  nullLit := TFloriaJSLiteralExpr.CreateNull(4, 1);
  try
    AssertEquals('ValueType must be null', Ord(fjstNull), Ord(nullLit.ValueType));
  finally
    nullLit.Free();
  end;

  undefLit := TFloriaJSLiteralExpr.CreateUndefined(5, 1);
  try
    AssertEquals('ValueType must be undefined', Ord(fjstUndefined), Ord(undefLit.ValueType));
  finally
    undefLit.Free();
  end;
end;

procedure TFloriaJSASTTest.TestBinaryAndUnaryNodes();
var
  unary: TFloriaJSUnaryExpr;
  bin: TFloriaJSBinaryExpr;
  leftLit, rightLit, operandLit: TFloriaJSLiteralExpr;
begin
  operandLit := TFloriaJSLiteralExpr.CreateNumber(42, 1, 2);
  unary := TFloriaJSUnaryExpr.Create(tkMinus, operandLit, True, 1, 1);
  try
    AssertEquals('Op must be tkMinus', Ord(tkMinus), Ord(unary.Op));
    AssertTrue('IsPrefix must be True', unary.IsPrefix);
    AssertNotNull('Operand must not be nil', unary.Operand);
  finally
    unary.Free();
  end;

  leftLit := TFloriaJSLiteralExpr.CreateNumber(10, 1, 1);
  rightLit := TFloriaJSLiteralExpr.CreateNumber(20, 1, 5);
  bin := TFloriaJSBinaryExpr.Create(leftLit, tkPlus, rightLit, 1, 3);
  try
    AssertEquals('Op must be tkPlus', Ord(tkPlus), Ord(bin.Op));
    AssertSame('Left must match', leftLit, bin.Left);
    AssertSame('Right must match', rightLit, bin.Right);
  finally
    bin.Free();
  end;
end;

procedure TFloriaJSASTTest.TestCallAndMemberNodes();
var
  targetId: TFloriaJSIdentifierExpr;
  member: TFloriaJSMemberExpr;
  call: TFloriaJSCallExpr;
  arg1, arg2: TFloriaJSLiteralExpr;
begin
  targetId := TFloriaJSIdentifierExpr.Create('console', 1, 1);
  member := TFloriaJSMemberExpr.CreateNamed(targetId, 'log', 1, 8);
  call := TFloriaJSCallExpr.Create(member, 1, 12);
  try
    arg1 := TFloriaJSLiteralExpr.CreateString('hello', 1, 13);
    arg2 := TFloriaJSLiteralExpr.CreateNumber(100, 1, 20);
    call.AddArgument(arg1);
    call.AddArgument(arg2);

    AssertEquals('Arg count must be 2', 2, call.GetArgumentCount());
    AssertSame('Arg 0 matches arg1', arg1, call.GetArgument(0));
    AssertSame('Arg 1 matches arg2', arg2, call.GetArgument(1));
    AssertSame('Callee matches member', member, call.Callee);
  finally
    call.Free();
  end;
end;

procedure TFloriaJSASTTest.TestObjectAndArrayNodes();
var
  arr: TFloriaJSArrayExpr;
  obj: TFloriaJSObjectExpr;
  lit1, lit2: TFloriaJSLiteralExpr;
begin
  arr := TFloriaJSArrayExpr.Create(1, 1);
  try
    lit1 := TFloriaJSLiteralExpr.CreateNumber(1, 1, 2);
    lit2 := TFloriaJSLiteralExpr.CreateNumber(2, 1, 5);
    arr.AddElement(lit1);
    arr.AddElement(lit2);
    AssertEquals('Array element count', 2, arr.GetElementCount());
    AssertSame('Element 0', lit1, arr.GetElement(0));
    AssertSame('Element 1', lit2, arr.GetElement(1));
  finally
    arr.Free();
  end;

  obj := TFloriaJSObjectExpr.Create(1, 1);
  try
    lit1 := TFloriaJSLiteralExpr.CreateNumber(800, 1, 9);
    lit2 := TFloriaJSLiteralExpr.CreateNumber(600, 1, 22);
    obj.AddProperty('width', lit1);
    obj.AddProperty('height', lit2);
    AssertEquals('Object property count', 2, obj.GetPropertyCount());
    AssertEquals('Key 0', 'width', obj.GetPropertyKey(0));
    AssertSame('Value 0', lit1, obj.GetPropertyValue(0));
    AssertEquals('Key 1', 'height', obj.GetPropertyKey(1));
    AssertSame('Value 1', lit2, obj.GetPropertyValue(1));
  finally
    obj.Free();
  end;
end;

procedure TFloriaJSASTTest.TestQMLComponentASTNode();
var
  comp, child: TFloriaJSQMLComponent;
  propExpr: TFloriaJSLiteralExpr;
  sigHandler: TFloriaJSBlockStmt;
begin
  comp := TFloriaJSQMLComponent.Create('Rectangle', 1, 1);
  try
    comp.Id := 'rootRect';
    propExpr := TFloriaJSLiteralExpr.CreateNumber(200, 2, 10);
    comp.AddProperty('width', propExpr);

    sigHandler := TFloriaJSBlockStmt.Create(3, 14);
    comp.AddSignal('onClicked', sigHandler);

    child := TFloriaJSQMLComponent.Create('Text', 4, 3);
    child.Id := 'label';
    comp.AddChild(child);

    AssertEquals('Component type', 'Rectangle', comp.ComponentType);
    AssertEquals('Component ID', 'rootRect', comp.Id);
    AssertEquals('Prop count', 1, comp.GetPropertyCount());
    AssertEquals('Prop 0 name', 'width', comp.GetPropertyName(0));
    AssertSame('Prop 0 expr', propExpr, comp.GetPropertyExpr(0));
    AssertEquals('Signal count', 1, comp.GetSignalCount());
    AssertEquals('Signal 0 name', 'onClicked', comp.GetSignalName(0));
    AssertSame('Signal 0 handler', sigHandler, comp.GetSignalHandler(0));
    AssertEquals('Child count', 1, comp.GetChildCount());
    AssertSame('Child 0', child, comp.GetChild(0));
    AssertEquals('Child ID', 'label', comp.GetChild(0).Id);
  finally
    comp.Free();
  end;
end;

{ TFloriaJSParserTest }

procedure TFloriaJSParserTest.TestArithmeticPrecedence();
var
  parser: TFloriaJSParser;
  expr: TFloriaJSExprNode;
  bin, mul: TFloriaJSBinaryExpr;
begin
  parser := TFloriaJSParser.Create('2 + 3 * 4');
  try
    expr := parser.ParseExpression();
    try
      AssertFalse('Parser should have no errors', parser.HasErrors());
      AssertTrue('Must be binary expr', expr is TFloriaJSBinaryExpr);
      bin := TFloriaJSBinaryExpr(expr);
      AssertEquals('Top op must be plus', Ord(tkPlus), Ord(bin.Op));
      AssertTrue('Left must be literal', bin.Left is TFloriaJSLiteralExpr);
      AssertEquals('Left value is 2', 2.0, TFloriaJSLiteralExpr(bin.Left).NumberVal, 0.0001);

      AssertTrue('Right must be binary expr', bin.Right is TFloriaJSBinaryExpr);
      mul := TFloriaJSBinaryExpr(bin.Right);
      AssertEquals('Sub op must be multiply', Ord(tkMultiply), Ord(mul.Op));
      AssertEquals('Mul left is 3', 3.0, TFloriaJSLiteralExpr(mul.Left).NumberVal, 0.0001);
      AssertEquals('Mul right is 4', 4.0, TFloriaJSLiteralExpr(mul.Right).NumberVal, 0.0001);
    finally
      expr.Free();
    end;
  finally
    parser.Free();
  end;
end;

procedure TFloriaJSParserTest.TestExponentiationRightAssociative();
var
  parser: TFloriaJSParser;
  expr: TFloriaJSExprNode;
  topPower, subPower: TFloriaJSBinaryExpr;
begin
  parser := TFloriaJSParser.Create('2 ** 3 ** 4');
  try
    expr := parser.ParseExpression();
    try
      AssertFalse('Parser should have no errors', parser.HasErrors());
      AssertTrue('Must be binary expr', expr is TFloriaJSBinaryExpr);
      topPower := TFloriaJSBinaryExpr(expr);
      AssertEquals('Top op is power', Ord(tkPower), Ord(topPower.Op));
      AssertTrue('Top left is 2', (topPower.Left is TFloriaJSLiteralExpr) and (TFloriaJSLiteralExpr(topPower.Left).NumberVal = 2.0));

      AssertTrue('Right is also power (right-associative)', topPower.Right is TFloriaJSBinaryExpr);
      subPower := TFloriaJSBinaryExpr(topPower.Right);
      AssertEquals('Sub op is power', Ord(tkPower), Ord(subPower.Op));
      AssertEquals('Sub left is 3', 3.0, TFloriaJSLiteralExpr(subPower.Left).NumberVal, 0.0001);
      AssertEquals('Sub right is 4', 4.0, TFloriaJSLiteralExpr(subPower.Right).NumberVal, 0.0001);
    finally
      expr.Free();
    end;
  finally
    parser.Free();
  end;
end;

procedure TFloriaJSParserTest.TestTernaryAndNullish();
var
  parser: TFloriaJSParser;
  expr: TFloriaJSExprNode;
  cond: TFloriaJSConditionalExpr;
  nullish: TFloriaJSBinaryExpr;
begin
  // Ternary: isEnabled ? 10 : 20
  parser := TFloriaJSParser.Create('isEnabled ? 10 : 20');
  try
    expr := parser.ParseExpression();
    try
      AssertFalse('Ternary parse should have no errors', parser.HasErrors());
      AssertTrue('Must be conditional expr', expr is TFloriaJSConditionalExpr);
      cond := TFloriaJSConditionalExpr(expr);
      AssertTrue('Condition is identifier', cond.Condition is TFloriaJSIdentifierExpr);
      AssertEquals('Identifier name', 'isEnabled', TFloriaJSIdentifierExpr(cond.Condition).Name);
      AssertTrue('Consequent is 10', (cond.Consequent is TFloriaJSLiteralExpr) and (TFloriaJSLiteralExpr(cond.Consequent).NumberVal = 10.0));
      AssertTrue('Alternate is 20', (cond.Alternate is TFloriaJSLiteralExpr) and (TFloriaJSLiteralExpr(cond.Alternate).NumberVal = 20.0));
    finally
      expr.Free();
    end;
  finally
    parser.Free();
  end;

  // Nullish coalescing: val ?? 42
  parser := TFloriaJSParser.Create('val ?? 42');
  try
    expr := parser.ParseExpression();
    try
      AssertFalse('Nullish parse should have no errors', parser.HasErrors());
      AssertTrue('Must be binary expr', expr is TFloriaJSBinaryExpr);
      nullish := TFloriaJSBinaryExpr(expr);
      AssertEquals('Op is nullish', Ord(tkNullish), Ord(nullish.Op));
      AssertTrue('Left is identifier val', (nullish.Left is TFloriaJSIdentifierExpr) and (TFloriaJSIdentifierExpr(nullish.Left).Name = 'val'));
      AssertTrue('Right is 42', (nullish.Right is TFloriaJSLiteralExpr) and (TFloriaJSLiteralExpr(nullish.Right).NumberVal = 42.0));
    finally
      expr.Free();
    end;
  finally
    parser.Free();
  end;
end;

procedure TFloriaJSParserTest.TestMemberAndCallChaining();
var
  parser: TFloriaJSParser;
  expr: TFloriaJSExprNode;
  call: TFloriaJSCallExpr;
  member: TFloriaJSMemberExpr;
begin
  parser := TFloriaJSParser.Create('Math.sin(3.14)');
  try
    expr := parser.ParseExpression();
    try
      AssertFalse('Parser should have no errors', parser.HasErrors());
      AssertTrue('Must be call expr', expr is TFloriaJSCallExpr);
      call := TFloriaJSCallExpr(expr);
      AssertEquals('Argument count is 1', 1, call.GetArgumentCount());

      AssertTrue('Callee is member expr', call.Callee is TFloriaJSMemberExpr);
      member := TFloriaJSMemberExpr(call.Callee);
      AssertEquals('Property name is sin', 'sin', member.PropertyName);
      AssertFalse('Not computed', member.Computed);
      AssertTrue('Target is Math', (member.Target is TFloriaJSIdentifierExpr) and (TFloriaJSIdentifierExpr(member.Target).Name = 'Math'));
    finally
      expr.Free();
    end;
  finally
    parser.Free();
  end;
end;

procedure TFloriaJSParserTest.TestVariableDeclarations();
var
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  stmt: TFloriaJSStmtNode;
  varStmt: TFloriaJSVarStmt;
begin
  parser := TFloriaJSParser.Create('let x = 10, y = 20; const PI = 3.14159;');
  try
    prog := parser.ParseProgram();
    try
      AssertFalse('Parser should have no errors', parser.HasErrors());
      AssertEquals('Program statement count', 2, prog.GetStatementCount());

      stmt := prog.GetStatement(0);
      AssertTrue('Stmt 0 is var stmt', stmt is TFloriaJSVarStmt);
      varStmt := TFloriaJSVarStmt(stmt);
      AssertEquals('Kind is tkLet', Ord(tkLet), Ord(varStmt.Kind));
      AssertEquals('Declarators count is 2', 2, varStmt.GetDeclaratorCount());
      AssertEquals('Decl 0 name is x', 'x', varStmt.GetDeclaratorName(0));
      AssertNotNull('Decl 0 init is not nil', varStmt.GetDeclaratorInit(0));
      AssertEquals('Decl 1 name is y', 'y', varStmt.GetDeclaratorName(1));

      stmt := prog.GetStatement(1);
      AssertTrue('Stmt 1 is var stmt', stmt is TFloriaJSVarStmt);
      varStmt := TFloriaJSVarStmt(stmt);
      AssertEquals('Kind is tkConst', Ord(tkConst), Ord(varStmt.Kind));
      AssertEquals('Declarators count is 1', 1, varStmt.GetDeclaratorCount());
      AssertEquals('Decl name is PI', 'PI', varStmt.GetDeclaratorName(0));
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;
end;

procedure TFloriaJSParserTest.TestIfElseStatement();
var
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  ifStmt: TFloriaJSIfStmt;
begin
  parser := TFloriaJSParser.Create('if (x > 0) return 1; else return 0;');
  try
    prog := parser.ParseProgram();
    try
      AssertFalse('Parser should have no errors', parser.HasErrors());
      AssertEquals('Program statement count is 1', 1, prog.GetStatementCount());

      AssertTrue('Statement is if stmt', prog.GetStatement(0) is TFloriaJSIfStmt);
      ifStmt := TFloriaJSIfStmt(prog.GetStatement(0));
      AssertTrue('Condition is binary', ifStmt.Condition is TFloriaJSBinaryExpr);
      AssertEquals('Condition op is >', Ord(tkGreaterThan), Ord(TFloriaJSBinaryExpr(ifStmt.Condition).Op));
      AssertTrue('Consequent is return stmt', ifStmt.Consequent is TFloriaJSReturnStmt);
      AssertNotNull('Alternate is present', ifStmt.Alternate);
      AssertTrue('Alternate is return stmt', ifStmt.Alternate is TFloriaJSReturnStmt);
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;
end;

procedure TFloriaJSParserTest.TestWhileAndForLoops();
var
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  whileStmt: TFloriaJSWhileStmt;
  forStmt: TFloriaJSForStmt;
begin
  parser := TFloriaJSParser.Create('while (x < 10) x++; for (let i = 0; i < 5; i++) sum += i;');
  try
    prog := parser.ParseProgram();
    try
      AssertFalse('Parser should have no errors', parser.HasErrors());
      AssertEquals('Program has 2 statements', 2, prog.GetStatementCount());

      AssertTrue('Stmt 0 is while', prog.GetStatement(0) is TFloriaJSWhileStmt);
      whileStmt := TFloriaJSWhileStmt(prog.GetStatement(0));
      AssertFalse('Is not do-while', whileStmt.IsDoWhile);
      AssertNotNull('While condition exists', whileStmt.Condition);
      AssertNotNull('While body exists', whileStmt.Body);

      AssertTrue('Stmt 1 is for', prog.GetStatement(1) is TFloriaJSForStmt);
      forStmt := TFloriaJSForStmt(prog.GetStatement(1));
      AssertNotNull('For init exists', forStmt.Init);
      AssertTrue('For init is var stmt', forStmt.Init is TFloriaJSVarStmt);
      AssertNotNull('For test exists', forStmt.Test);
      AssertNotNull('For update exists', forStmt.Update);
      AssertNotNull('For body exists', forStmt.Body);
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;
end;

procedure TFloriaJSParserTest.TestFunctionDeclaration();
var
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  fnDecl: TFloriaJSFunctionDecl;
begin
  parser := TFloriaJSParser.Create('function multiply(a, b) { return a * b; }');
  try
    prog := parser.ParseProgram();
    try
      AssertFalse('Parser should have no errors', parser.HasErrors());
      AssertEquals('Program has 1 statement', 1, prog.GetStatementCount());

      AssertTrue('Stmt is function decl', prog.GetStatement(0) is TFloriaJSFunctionDecl);
      fnDecl := TFloriaJSFunctionDecl(prog.GetStatement(0));
      AssertEquals('Function name is multiply', 'multiply', fnDecl.Name);
      AssertEquals('Parameter count is 2', 2, fnDecl.Parameters.Count);
      AssertEquals('Param 0 is a', 'a', fnDecl.Parameters[0]);
      AssertEquals('Param 1 is b', 'b', fnDecl.Parameters[1]);
      AssertNotNull('Body block exists', fnDecl.Body);
      AssertEquals('Body has 1 statement', 1, fnDecl.Body.GetStatementCount());
      AssertTrue('Body stmt is return', fnDecl.Body.GetStatement(0) is TFloriaJSReturnStmt);
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;
end;

procedure TFloriaJSParserTest.TestDeclarativeQMLComponent();
var
  parser: TFloriaJSParser;
  comp, child: TFloriaJSQMLComponent;
  source: string;
begin
  source :=
    'Rectangle {' + LineEnding +
    '  id: root' + LineEnding +
    '  width: 320;' + LineEnding +
    '  height: 240;' + LineEnding +
    '  color: "navy";' + LineEnding +
    '  onClicked: {' + LineEnding +
    '    counter += 1;' + LineEnding +
    '  }' + LineEnding +
    '  Text {' + LineEnding +
    '    id: label' + LineEnding +
    '    text: "Welcome Floria";' + LineEnding +
    '  }' + LineEnding +
    '}';
  parser := TFloriaJSParser.Create(source);
  try
    comp := parser.ParseQMLComponent();
    try
      AssertFalse('Parser should have no errors', parser.HasErrors());
      AssertNotNull('Component should not be nil', comp);
      AssertEquals('Component type is Rectangle', 'Rectangle', comp.ComponentType);
      AssertEquals('Component ID is root', 'root', comp.Id);
      AssertEquals('Property count is 3', 3, comp.GetPropertyCount());
      AssertEquals('Prop 0 name is width', 'width', comp.GetPropertyName(0));
      AssertEquals('Prop 1 name is height', 'height', comp.GetPropertyName(1));
      AssertEquals('Prop 2 name is color', 'color', comp.GetPropertyName(2));
      AssertEquals('Signal count is 1', 1, comp.GetSignalCount());
      AssertEquals('Signal 0 name is onClicked', 'onClicked', comp.GetSignalName(0));
      AssertEquals('Child count is 1', 1, comp.GetChildCount());

      child := comp.GetChild(0);
      AssertNotNull('Child should not be nil', child);
      AssertEquals('Child type is Text', 'Text', child.ComponentType);
      AssertEquals('Child ID is label', 'label', child.Id);
      AssertEquals('Child prop count is 1', 1, child.GetPropertyCount());
      AssertEquals('Child prop 0 is text', 'text', child.GetPropertyName(0));
    finally
      comp.Free();
    end;
  finally
    parser.Free();
  end;
end;

procedure TFloriaJSParserTest.TestParserErrorHandling();
var
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
begin
  parser := TFloriaJSParser.Create('let = 100;');
  try
    prog := parser.ParseProgram();
    try
      AssertTrue('Parser should record error on invalid var statement', parser.HasErrors());
      AssertTrue('Error count should be >= 1', parser.GetErrorCount() >= 1);
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;
end;

var
  Application: TTestRunner;

begin
  RegisterTest(TFloriaJSTypesTest);
  RegisterTest(TFloriaJSEngineTest);
  RegisterTest(TFloriaJSLexerTest);
  RegisterTest(TFloriaJSASTTest);
  RegisterTest(TFloriaJSParserTest);

  Application := TTestRunner.Create(nil);
  try
    Application.Initialize();
    Application.Title := 'Floria JS Test Runner';
    Application.Run();
  finally
    Application.Free();
  end;
end.
