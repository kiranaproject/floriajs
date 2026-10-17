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

var
  Application: TTestRunner;

begin
  RegisterTest(TFloriaJSTypesTest);
  RegisterTest(TFloriaJSEngineTest);
  RegisterTest(TFloriaJSLexerTest);

  Application := TTestRunner.Create(nil);
  try
    Application.Initialize();
    Application.Title := 'Floria JS Test Runner';
    Application.Run();
  finally
    Application.Free();
  end;
end.
