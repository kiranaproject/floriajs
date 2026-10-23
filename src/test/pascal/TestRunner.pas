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
{$modeswitch advancedrecords}

uses
  Classes, SysUtils, Math,
  fpcunit, testregistry, consoletestrunner,
  floria.js.types, floria.js.lexer, floria.js.ast, floria.js.parser,
  floria.js.value, floria.js.env, floria.js.evaluator, floria.js.stdlib,
  floria.js.core, floria.ftml.types, floria.ftml.binding, floria.ftml.engine, floriajs;

type
  { Counts how often an AST node is destroyed, so the reference counting of a
    shared node can be observed. }
  TCountedASTNode = class(TFloriaJSBlockStmt)
  public
    DestroyCount: Integer;
    destructor Destroy(); override;
  end;

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
    procedure TestFTMLComponentASTNode();
  end;

  { Test 5: Pratt Parser Suite }
  TFloriaJSParserTest = class(TTestCase)
  published
    procedure TestArithmeticPrecedence();
    procedure TestExponentiationRightAssociative();
    procedure TestTernaryAndNullish();
    procedure TestMemberAndCallChaining();
    procedure TestNewAndThisExpressions();
    procedure TestVariableDeclarations();
    procedure TestIfElseStatement();
    procedure TestWhileAndForLoops();
    procedure TestFunctionDeclaration();
    procedure TestDeclarativeFTMLComponent();
    procedure TestParserErrorHandling();
    procedure TestArrowFunctionParsing();
  end;

  { Test 6: Value System & Heap Objects }
  TFloriaJSValueTest = class(TTestCase)
  published
    procedure TestPrimitiveValues();
    procedure TestTypeCoercion();
    procedure TestObjectProperties();
    procedure TestArrayOperations();
    procedure TestBinaryAndUnaryOps();
  end;

  { Test 7: Runtime AST Evaluator & Host Interop }
  TFloriaJSEvaluatorTest = class(TTestCase)
  published
    procedure TestArithmeticAndLogicalEval();
    procedure TestVariableScopeAndShadowing();
    procedure TestConditionalsAndLoops();
    procedure TestWhileWithBreakAndContinue();
    procedure TestUserFunctionAndRecursion();
    procedure TestClosures();
    procedure TestObjectAndArrayManipulation();
    procedure TestMathBuiltin();
    procedure TestPascalHostCallback();
    procedure TestConsoleCapture();
    procedure TestCommaOperatorAndLabeledBreak();
    procedure TestArrowFunctions();
  end;

  { Test 8: Declarative FTML Types & Built-in Elements }
  TFloriaFTMLTypesTest = class(TTestCase)
  published
    procedure TestItemCreationAndProperties();
    procedure TestHierarchyAndFindById();
    procedure TestBuiltinElements();
    procedure TestSignalDispatch();
  end;

  { Test 9: Reactive Property Bindings & Dependency Tracking }
  TFloriaFTMLBindingTest = class(TTestCase)
  published
    procedure TestDirectBinding();
    procedure TestCascadedBinding();
    procedure TestAssignmentBreaksBinding();
    procedure TestCycleGuard();
  end;

  { Test 10: FTML Engine & Full Document Runtime }
  TFloriaFTMLEngineTest = class(TTestCase)
  published
    procedure TestLoadSimpleFTML();
    procedure TestLoadNestedFTMLWithBindings();
    procedure TestIdResolutionInJS();
    procedure TestFTMLComponentFunctions();
    procedure TestFTMLSignalHandling();
    procedure TestComponentOnCompleted();
  end;

  { Test 11: Semantic Anchors, Dynamic Constraints & Layouts }
  TFloriaFTMLAnchorsAndLayoutsTest = class(TTestCase)
  published
    procedure TestSemanticAnchorLines();
    procedure TestAnchorsFillAndMargins();
    procedure TestOpposingAnchorsOverrideExplicitSize();
    procedure TestSiblingAnchoringAndReactivity();
    procedure TestFlexBoxLayoutAndProperties();
    procedure TestGridLayoutAndProperties();
    procedure TestQmlLayoutAliases();
  end;

  { Test 12: Document Lifetime & Resource Release }
  TFloriaFTMLLifecycleTest = class(TTestCase)
  published
    procedure TestReloadDoesNotGrowHeap();
    procedure TestReloadWithdrawsDocumentIds();
    procedure TestExternalContextIsRestoredOnFree();
    procedure TestFailedLoadKeepsEngineConsistent();
    procedure TestRuntimeClosureSurvivesDocumentReload();
  end;

  { Test 13: Runtime Environment Lifetime }
  TFloriaJSLifetimeTest = class(TTestCase)
  published
    procedure TestLoopDoesNotAccumulateEnvironments();
    procedure TestRecursionDoesNotAccumulateEnvironments();
    procedure TestClosureKeepsItsScopeAlive();
    procedure TestFunctionOutlivesItsScript();
    procedure TestFunctionExpressionOutlivesItsScript();
    procedure TestRecursiveFunctionOutlivesItsScript();
    procedure TestNestedFunctionDeclarationIsReusable();
    procedure TestSharedNodeReferenceCounting();
    procedure TestFunctionBodySurvivesItsDeclaration();
    procedure TestClosureEscapingItsScopeSurvives();
  end;

  { Test 14: Switch Statements }
  TFloriaJSSwitchTest = class(TTestCase)
  published
    procedure TestSwitchMatching();
    procedure TestSwitchDefaultClause();
    procedure TestSwitchFallThrough();
    procedure TestSwitchBreakAndContinue();
    procedure TestSwitchNestedAndInFunction();
    procedure TestSwitchParserErrors();
  end;

  { Test 15: Try, Catch & Throw }
  TFloriaJSTryCatchTest = class(TTestCase)
  published
    procedure TestThrowAndCatch();
    procedure TestCatchWithoutBinding();
    procedure TestCatchParameterScope();
    procedure TestFinallyAlwaysRuns();
    procedure TestFinallyWithReturn();
    procedure TestControlFlowPassesThrough();
    procedure TestNestedTry();
    procedure TestThrowFromFunction();
    procedure TestThrowInsideCatch();
    procedure TestErrorObject();
    procedure TestUncaughtThrow();
    procedure TestAsyncThrow();
    procedure TestTryParserErrors();
    procedure TestTryDoesNotLeak();
  end;

  { Test 16: Heap Reclamation }
  TFloriaJSReclamationTest = class(TTestCase)
  published
    procedure TestUnreachableObjectIsReclaimed();
    procedure TestUnreachableArrayIsReclaimed();
    procedure TestFunctionDeclarationIsReclaimed();
    procedure TestFunctionExpressionIsReclaimed();
    procedure TestObjectWithFunctionIsReclaimed();
    procedure TestReachableObjectSurvives();
    procedure TestValueHandedToTheHostSurvivesUntilReleased();
    procedure TestBlockScopedFunctionIsReclaimed();
    procedure TestFunctionDeclaredInLoopBodyIsReclaimed();
  end;

  { Test 17: Object Construction with the new Operator }
  TFloriaJSConstructionTest = class(TTestCase)
  published
    procedure TestConstructorSetsProperties();
    procedure TestConstructorArguments();
    procedure TestPrototypeMembers();
    procedure TestReturnedObjectReplacesInstance();
    procedure TestPrimitiveReturnIsIgnored();
    procedure TestConstructorThroughMember();
    procedure TestObjectConstructor();
    procedure TestNonConstructorThrows();
    procedure TestThisInObjectMethod();
    procedure TestNewDoesNotAccumulateObjects();
    procedure TestPrototypeIsReclaimedWithItsFunction();
  end;

  { Test 18: JavaScript-visible Array Methods }
  TFloriaJSArrayMethodsTest = class(TTestCase)
  published
    procedure TestPushPopShiftUnshift();
    procedure TestJoinConcatReverseSlice();
    procedure TestIndexOfLastIndexOfIncludes();
    procedure TestMapFilterReduce();
    procedure TestForEachSomeEveryFind();
    procedure TestSortAndSplice();
    procedure TestArrayStatics();
    procedure TestArrayCallbacksDoNotAccumulateObjects();
  end;

{ TFloriaJSTypesTest }

destructor TCountedASTNode.Destroy();
begin
  Inc(DestroyCount);
  inherited Destroy();
end;

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

procedure TFloriaJSASTTest.TestFTMLComponentASTNode();
var
  comp, child: TFloriaFTMLComponent;
  propExpr: TFloriaJSLiteralExpr;
  sigHandler: TFloriaJSBlockStmt;
begin
  comp := TFloriaFTMLComponent.Create('Rectangle', 1, 1);
  try
    comp.Id := 'rootRect';
    propExpr := TFloriaJSLiteralExpr.CreateNumber(200, 2, 10);
    comp.AddProperty('width', propExpr);

    sigHandler := TFloriaJSBlockStmt.Create(3, 14);
    comp.AddSignal('onClicked', sigHandler);

    child := TFloriaFTMLComponent.Create('Text', 4, 3);
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

procedure TFloriaJSParserTest.TestNewAndThisExpressions();
var
  parser: TFloriaJSParser;
  expr: TFloriaJSExprNode;
  call: TFloriaJSCallExpr;
  member: TFloriaJSMemberExpr;
begin
  parser := TFloriaJSParser.Create('new Ns.Ctor(1, this)');
  try
    expr := parser.ParseExpression();
    try
      AssertFalse('Parser should have no errors', parser.HasErrors());
      AssertTrue('Must be a call expression', expr is TFloriaJSCallExpr);
      call := TFloriaJSCallExpr(expr);
      AssertTrue('The call must be a construction', call.IsNew);
      AssertEquals('Argument count is 2', 2, call.GetArgumentCount());

      AssertTrue('Callee is a member expression', call.Callee is TFloriaJSMemberExpr);
      member := TFloriaJSMemberExpr(call.Callee);
      AssertEquals('Property name is Ctor', 'Ctor', member.PropertyName);
      AssertTrue('Target is the Ns identifier',
        (member.Target is TFloriaJSIdentifierExpr) and
        (TFloriaJSIdentifierExpr(member.Target).Name = 'Ns'));

      AssertTrue('The second argument must be this',
        (call.GetArgument(1) is TFloriaJSIdentifierExpr) and
        (TFloriaJSIdentifierExpr(call.GetArgument(1)).Name = 'this'));
    finally
      expr.Free();
    end;
  finally
    parser.Free();
  end;

  parser := TFloriaJSParser.Create('new Ctor');
  try
    expr := parser.ParseExpression();
    try
      AssertFalse('A construction without parentheses must parse', parser.HasErrors());
      AssertTrue('Must be a construction', (expr is TFloriaJSCallExpr) and
        TFloriaJSCallExpr(expr).IsNew);
      AssertEquals('It has no arguments', 0, TFloriaJSCallExpr(expr).GetArgumentCount());
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

procedure TFloriaJSParserTest.TestDeclarativeFTMLComponent();
var
  parser: TFloriaJSParser;
  comp, child: TFloriaFTMLComponent;
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
    comp := parser.ParseFTMLComponent();
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

procedure TFloriaJSParserTest.TestArrowFunctionParsing();
var
  parser: TFloriaJSParser;
  expr: TFloriaJSExprNode;
  fnExpr: TFloriaJSFunctionExpr;
begin
  parser := TFloriaJSParser.Create('x => x + 1');
  try
    expr := parser.ParseExpression();
    try
      AssertFalse('Single param arrow should have no errors', parser.HasErrors());
      AssertTrue('Must be function expr', expr is TFloriaJSFunctionExpr);
      fnExpr := TFloriaJSFunctionExpr(expr);
      AssertTrue('IsArrow must be True', fnExpr.IsArrow);
      AssertEquals('Parameter count is 1', 1, fnExpr.Parameters.Count);
      AssertEquals('Parameter name is x', 'x', fnExpr.Parameters[0]);
    finally
      expr.Free();
    end;
  finally
    parser.Free();
  end;

  parser := TFloriaJSParser.Create('(a, b) => { return a + b; }');
  try
    expr := parser.ParseExpression();
    try
      AssertFalse('Multi param arrow should have no errors', parser.HasErrors());
      AssertTrue('Must be function expr', expr is TFloriaJSFunctionExpr);
      fnExpr := TFloriaJSFunctionExpr(expr);
      AssertTrue('IsArrow must be True', fnExpr.IsArrow);
      AssertEquals('Parameter count is 2', 2, fnExpr.Parameters.Count);
      AssertEquals('Parameter 0 is a', 'a', fnExpr.Parameters[0]);
      AssertEquals('Parameter 1 is b', 'b', fnExpr.Parameters[1]);
      AssertTrue('Body must be block stmt', fnExpr.Body is TFloriaJSBlockStmt);
    finally
      expr.Free();
    end;
  finally
    parser.Free();
  end;
end;

{ TFloriaJSValueTest }

procedure TFloriaJSValueTest.TestPrimitiveValues();
var
  u, n, b, num, s: TFloriaJSValue;
begin
  u := JSMakeUndefined();
  AssertTrue('u is undefined', u.IsUndefined());
  AssertFalse('u is not truthy', u.IsTruthy());

  n := JSMakeNull();
  AssertTrue('n is null', n.IsNull());
  AssertFalse('n is not truthy', n.IsTruthy());

  b := JSMakeBoolean(True);
  AssertTrue('b is bool', b.IsBoolean());
  AssertTrue('b is truthy', b.IsTruthy());

  num := JSMakeNumber(42.5);
  AssertTrue('num is number', num.IsNumber());
  AssertEquals('num value', 42.5, num.NumVal, 0.0001);
  AssertTrue('num is truthy', num.IsTruthy());

  num := JSMakeNumber(0.0);
  AssertFalse('0 is not truthy', num.IsTruthy());

  s := JSMakeString('hello');
  AssertTrue('s is string', s.IsString());
  AssertEquals('s text', 'hello', s.StrVal);
  AssertTrue('s is truthy', s.IsTruthy());

  s := JSMakeString('');
  AssertFalse('empty string is not truthy', s.IsTruthy());
end;

procedure TFloriaJSValueTest.TestTypeCoercion();
begin
  AssertEquals('undefined to string', 'undefined', JSMakeUndefined().ToString());
  AssertEquals('null to string', 'null', JSMakeNull().ToString());
  AssertEquals('true to string', 'true', JSMakeBoolean(True).ToString());
  AssertEquals('42 to string', '42', JSMakeNumber(42.0).ToString());

  AssertTrue('undefined to number is NaN', IsNaN(JSMakeUndefined().ToNumber()));
  AssertEquals('null to number is 0', 0.0, JSMakeNull().ToNumber(), 0.0001);
  AssertEquals('true to number is 1', 1.0, JSMakeBoolean(True).ToNumber(), 0.0001);
  AssertEquals('false to number is 0', 0.0, JSMakeBoolean(False).ToNumber(), 0.0001);
  AssertEquals('string "123.5" to number', 123.5, JSMakeString('123.5').ToNumber(), 0.0001);
  AssertEquals('empty string to number', 0.0, JSMakeString('').ToNumber(), 0.0001);
end;

procedure TFloriaJSValueTest.TestObjectProperties();
var
  heap: TFloriaJSHeap;
  proto, obj: TFloriaJSObject;
  keys: TStringList;
begin
  heap := TFloriaJSHeap.Create();
  try
    proto := heap.NewObject();
    proto.SetProperty('inheritedProp', JSMakeString('from_proto'));

    obj := heap.NewObject(proto);
    obj.SetProperty('ownProp', JSMakeNumber(100.0));

    AssertTrue('obj has ownProp', obj.HasProperty('ownProp'));
    AssertTrue('obj has inheritedProp', obj.HasProperty('inheritedProp'));
    AssertEquals('ownProp value', 100.0, obj.GetProperty('ownProp').ToNumber(), 0.0001);
    AssertEquals('inheritedProp value', 'from_proto', obj.GetProperty('inheritedProp').ToString());

    keys := TStringList.Create();
    try
      obj.GetKeys(keys);
      AssertEquals('Own keys count', 1, keys.Count);
      AssertEquals('Own key is ownProp', 'ownProp', keys[0]);
    finally
      keys.Free();
    end;

    obj.DeleteProperty('ownProp');
    AssertFalse('ownProp deleted', obj.HasProperty('ownProp'));
  finally
    heap.Free();
  end;
end;

procedure TFloriaJSValueTest.TestArrayOperations();
var
  arr: TFloriaJSArray;
  val: TFloriaJSValue;
begin
  arr := TFloriaJSArray.Create();
  try
    arr.Push(JSMakeNumber(10.0));
    arr.Push(JSMakeNumber(20.0));
    arr.Push(JSMakeNumber(30.0));
    AssertEquals('Length is 3', 3, arr.Length());
    AssertEquals('Join comma', '10,20,30', arr.Join(','));

    val := arr.Pop();
    AssertEquals('Popped 30', 30.0, val.ToNumber(), 0.0001);
    AssertEquals('Length is 2', 2, arr.Length());

    arr.Unshift(JSMakeNumber(5.0));
    AssertEquals('Length is 3 after unshift', 3, arr.Length());
    AssertEquals('Element 0 is 5', 5.0, arr.GetElement(0).ToNumber(), 0.0001);

    val := arr.Shift();
    AssertEquals('Shifted 5', 5.0, val.ToNumber(), 0.0001);
    AssertEquals('Length is 2 after shift', 2, arr.Length());
  finally
    arr.Free();
  end;
end;

procedure TFloriaJSValueTest.TestBinaryAndUnaryOps();
begin
  // Add: string concat vs number add
  AssertEquals('Number add', 15.0, JSAdd(JSMakeNumber(5), JSMakeNumber(10)).ToNumber(), 0.0001);
  AssertEquals('String concat', 'foo10', JSAdd(JSMakeString('foo'), JSMakeNumber(10)).ToString());

  // Sub, Mul, Div, Mod, Pow
  AssertEquals('Subtract', 6.0, JSSubtract(JSMakeNumber(10), JSMakeNumber(4)).ToNumber(), 0.0001);
  AssertEquals('Multiply', 20.0, JSMultiply(JSMakeNumber(4), JSMakeNumber(5)).ToNumber(), 0.0001);
  AssertEquals('Divide', 2.5, JSDivide(JSMakeNumber(5), JSMakeNumber(2)).ToNumber(), 0.0001);
  AssertEquals('Modulo', 1.0, JSModulo(JSMakeNumber(7), JSMakeNumber(3)).ToNumber(), 0.0001);
  AssertEquals('Power', 8.0, JSPower(JSMakeNumber(2), JSMakeNumber(3)).ToNumber(), 0.0001);

  // Loose & Strict Equality
  AssertTrue('Loose equal 5 == "5"', JSEqual(JSMakeNumber(5), JSMakeString('5')));
  AssertFalse('Strict equal 5 === "5"', JSStrictEqual(JSMakeNumber(5), JSMakeString('5')));
  AssertTrue('null == undefined', JSEqual(JSMakeNull(), JSMakeUndefined()));
  AssertFalse('null === undefined', JSStrictEqual(JSMakeNull(), JSMakeUndefined()));

  // Bitwise
  AssertEquals('BitAnd 5 & 3 = 1', 1.0, JSBitAnd(JSMakeNumber(5), JSMakeNumber(3)).ToNumber(), 0.0001);
  AssertEquals('BitOr 5 | 2 = 7', 7.0, JSBitOr(JSMakeNumber(5), JSMakeNumber(2)).ToNumber(), 0.0001);
  AssertEquals('BitXor 5 ^ 1 = 4', 4.0, JSBitXor(JSMakeNumber(5), JSMakeNumber(1)).ToNumber(), 0.0001);
  AssertEquals('ShiftLeft 1 << 3 = 8', 8.0, JSShiftLeft(JSMakeNumber(1), JSMakeNumber(3)).ToNumber(), 0.0001);
end;

{ TFloriaJSEvaluatorTest }

procedure TFloriaJSEvaluatorTest.TestArithmeticAndLogicalEval();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('1 + 2 * 3;');
    AssertTrue('1 + 2 * 3 success', res.Success);
    AssertEquals('1 + 2 * 3 = 7', 7.0, res.NumberValue, 0.0001);

    res := engine.Execute('(10 - 4) / 2;');
    AssertTrue('(10 - 4) / 2 success', res.Success);
    AssertEquals('(10 - 4) / 2 = 3', 3.0, res.NumberValue, 0.0001);

    res := engine.Execute('true && false;');
    AssertTrue('true && false success', res.Success);
    AssertFalse('true && false is false', res.BooleanValue);

    res := engine.Execute('null ?? 42;');
    AssertTrue('null ?? 42 success', res.Success);
    AssertEquals('null ?? 42 = 42', 42.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEvaluatorTest.TestVariableScopeAndShadowing();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let x = 10;' + LineEnding +
      '{' + LineEnding +
      '  let x = 20;' + LineEnding +
      '}' + LineEnding +
      'x;'
    );
    AssertTrue('Scope shadowing success', res.Success);
    AssertEquals('Outer x remains 10', 10.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEvaluatorTest.TestConditionalsAndLoops();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let sum = 0;' + LineEnding +
      'for (let i = 1; i <= 5; i++) {' + LineEnding +
      '  sum += i;' + LineEnding +
      '}' + LineEnding +
      'sum;'
    );
    AssertTrue('For loop sum success', res.Success);
    AssertEquals('Sum 1..5 is 15', 15.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEvaluatorTest.TestWhileWithBreakAndContinue();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let x = 0;' + LineEnding +
      'while (x < 10) {' + LineEnding +
      '  x++;' + LineEnding +
      '  if (x === 5) break;' + LineEnding +
      '}' + LineEnding +
      'x;'
    );
    AssertTrue('While break success', res.Success);
    AssertEquals('x broke at 5', 5.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEvaluatorTest.TestUserFunctionAndRecursion();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'function fib(n) {' + LineEnding +
      '  if (n <= 1) return n;' + LineEnding +
      '  return fib(n - 1) + fib(n - 2);' + LineEnding +
      '}' + LineEnding +
      'fib(8);'
    );
    AssertTrue('Fibonacci recursion success', res.Success);
    AssertEquals('fib(8) is 21', 21.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEvaluatorTest.TestClosures();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'function makeCounter() {' + LineEnding +
      '  let count = 0;' + LineEnding +
      '  return function() {' + LineEnding +
      '    count += 1;' + LineEnding +
      '    return count;' + LineEnding +
      '  };' + LineEnding +
      '}' + LineEnding +
      'let c = makeCounter();' + LineEnding +
      'c(); c(); c();'
    );
    AssertTrue('Closure counter success', res.Success);
    AssertEquals('Counter invoked 3 times is 3', 3.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEvaluatorTest.TestObjectAndArrayManipulation();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let pt = { x: 10, y: 20 };' + LineEnding +
      'pt.x + pt.y;'
    );
    AssertTrue('Object property access success', res.Success);
    AssertEquals('pt.x + pt.y = 30', 30.0, res.NumberValue, 0.0001);

    res := engine.Execute(
      'let arr = [10, 20, 30];' + LineEnding +
      'arr[0] + arr[2] + arr.length;'
    );
    AssertTrue('Array index and length success', res.Success);
    AssertEquals('10 + 30 + 3 = 43', 43.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEvaluatorTest.TestMathBuiltin();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('Math.max(10, 50, 25);');
    AssertTrue('Math.max success', res.Success);
    AssertEquals('Math.max(10, 50, 25) = 50', 50.0, res.NumberValue, 0.0001);

    res := engine.Execute('Math.sqrt(64);');
    AssertTrue('Math.sqrt success', res.Success);
    AssertEquals('Math.sqrt(64) = 8', 8.0, res.NumberValue, 0.0001);

    res := engine.Execute('Math.PI > 3.14;');
    AssertTrue('Math.PI comparison success', res.Success);
    AssertTrue('Math.PI > 3.14 is true', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

function NativeDoubleValue(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) > 0 then
    Result := JSMakeNumber(AArgs[0].ToNumber() * 2.0)
  else
    Result := JSMakeNumber(0.0);
end;

procedure TFloriaJSEvaluatorTest.TestPascalHostCallback();
var
  ctx: TFloriaJSContext;
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    ctx := engine.DefaultContext;
    ctx.RegisterFunction('doubleVal', @NativeDoubleValue);

    res := ctx.Evaluate('doubleVal(21);');
    AssertTrue('Host callback execution success', res.Success);
    AssertEquals('doubleVal(21) = 42', 42.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEvaluatorTest.TestConsoleCapture();
var
  engine: TFloriaJSEngine;
  ctx: TFloriaJSContext;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    ctx := engine.DefaultContext;
    res := ctx.Evaluate('console.log("Captured message", 123);');
    AssertTrue('console.log execution success', res.Success);
    AssertTrue('Output buffer captured log', ctx.Output.Count > 0);
    AssertEquals('Output message content', 'Captured message 123', ctx.Output[ctx.Output.Count - 1]);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEvaluatorTest.TestCommaOperatorAndLabeledBreak();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    { Comma operator in parentheses }
    res := engine.Execute('var a = (1, 2); a;');
    AssertTrue('Comma operator success', res.Success);
    AssertEquals('Comma operator returns right value', 2.0, res.NumberValue, 0.0001);

    { Multi-comma sequence }
    res := engine.Execute('(10, 20, 30);');
    AssertTrue('Multi comma success', res.Success);
    AssertEquals('Multi comma returns last value', 30.0, res.NumberValue, 0.0001);

    { Labeled break from nested loop }
    res := engine.Execute(
      'var r = 0;' + LineEnding +
      'outer: for (var i = 0; i < 3; i++) {' + LineEnding +
      '  for (var j = 0; j < 3; j++) {' + LineEnding +
      '    r = r + 1;' + LineEnding +
      '    break outer;' + LineEnding +
      '  }' + LineEnding +
      '}' + LineEnding +
      'r;'
    );
    AssertTrue('Labeled break success', res.Success);
    AssertEquals('Labeled break stops outer loop', 1.0, res.NumberValue, 0.0001);

    { Classic for with const }
    res := engine.Execute(
      'var s = 0;' + LineEnding +
      'for (const i = 0; i < 2; i++) { s = s + 1; }' + LineEnding +
      's;'
    );
    AssertTrue('For const success', res.Success);
    AssertEquals('For const runs correctly', 2.0, res.NumberValue, 0.0001);

    { Math.imul and Math.clz32 }
    res := engine.Execute('Math.imul(2, 4);');
    AssertTrue('Math.imul success', res.Success);
    AssertEquals('Math.imul(2, 4) = 8', 8.0, res.NumberValue, 0.0001);

    res := engine.Execute('Math.clz32(1);');
    AssertTrue('Math.clz32 success', res.Success);
    AssertEquals('Math.clz32(1) = 31', 31.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEvaluatorTest.TestArrowFunctions();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    { 1. Concise body with single unparenthesized parameter }
    res := engine.Execute('var f = x => x + 10; f(5);');
    AssertTrue('Concise single param arrow success', res.Success);
    AssertEquals('f(5) = 15', 15.0, res.NumberValue, 0.0001);

    { 2. Concise body with multiple parenthesized parameters }
    res := engine.Execute('var add = (a, b) => a + b; add(3, 4);');
    AssertTrue('Concise multi param arrow success', res.Success);
    AssertEquals('add(3, 4) = 7', 7.0, res.NumberValue, 0.0001);

    { 3. Zero-parameter arrow function }
    res := engine.Execute('var k = () => 42; k();');
    AssertTrue('Zero param arrow success', res.Success);
    AssertEquals('k() = 42', 42.0, res.NumberValue, 0.0001);

    { 4. Block body with return }
    res := engine.Execute('var f = (x) => { return x * 2; }; f(21);');
    AssertTrue('Block body arrow success', res.Success);
    AssertEquals('f(21) = 42', 42.0, res.NumberValue, 0.0001);

    { 5. Block body without return evaluates to undefined }
    res := engine.Execute('var f = (x) => { var y = x * 2; }; f(21);');
    AssertTrue('Block body void success', res.Success);
    AssertEquals('Void arrow returns undefined', Ord(fjstUndefined), Ord(res.ResultType));

    { 6. Chained / curried arrow functions }
    res := engine.Execute('var curried = a => b => a * b; curried(6)(7);');
    AssertTrue('Curried arrow success', res.Success);
    AssertEquals('curried(6)(7) = 42', 42.0, res.NumberValue, 0.0001);

    { 7. Array methods with arrow functions }
    res := engine.Execute('[1, 2, 3].map(x => x * 10).join(",");');
    AssertTrue('Array map with arrow success', res.Success);
    AssertEquals('Mapped array string', '10,20,30', res.StringValue);

    { 8. Lexical this binding }
    res := engine.Execute(
      'var obj = {' + LineEnding +
      '  base: 100,' + LineEnding +
      '  getAdder: function() {' + LineEnding +
      '    return (x) => this.base + x;' + LineEnding +
      '  }' + LineEnding +
      '};' + LineEnding +
      'var adder = obj.getAdder();' + LineEnding +
      'adder(23);'
    );
    AssertTrue('Lexical this arrow success', res.Success);
    AssertEquals('Lexical this resolves to obj.base (123)', 123.0, res.NumberValue, 0.0001);

    { 9. Arrow functions cannot be used as constructors }
    res := engine.Execute(
      'var caught = false;' + LineEnding +
      'try {' + LineEnding +
      '  var Arrow = () => {};' + LineEnding +
      '  new Arrow();' + LineEnding +
      '} catch (e) {' + LineEnding +
      '  caught = (e.name === "TypeError");' + LineEnding +
      '}' + LineEnding +
      'caught;'
    );
    AssertTrue('Arrow constructor TypeError test success', res.Success);
    AssertTrue('new (() => {}) throws TypeError', res.BooleanValue);

    { 10. Arrow functions do not have prototype property }
    res := engine.Execute('var f = () => {}; typeof f.prototype;');
    AssertTrue('Arrow prototype test success', res.Success);
    AssertEquals('f.prototype is undefined', 'undefined', res.StringValue);

    { 11. Async arrow function }
    res := engine.Execute('var f = async (x) => x + 1; typeof f;');
    AssertTrue('Async arrow typeof success', res.Success);
    AssertEquals('typeof async arrow is function', 'function', res.StringValue);
  finally
    engine.Free();
  end;
end;

{ TFloriaFTMLTypesTest }

procedure TFloriaFTMLTypesTest.TestItemCreationAndProperties();
var
  item: TFloriaFTMLItem;
begin
  item := TFloriaFTMLItem.Create('Item');
  try
    AssertEquals('TypeName is Item', 'Item', item.TypeName);
    AssertEquals('Default X is 0', 0.0, item.X, 0.001);
    AssertEquals('Default Y is 0', 0.0, item.Y, 0.001);
    AssertEquals('Default Width is 0', 0.0, item.Width, 0.001);
    AssertEquals('Default Height is 0', 0.0, item.Height, 0.001);
    AssertTrue('Default Visible is True', item.Visible);
    AssertEquals('Default Opacity is 1.0', 1.0, item.Opacity, 0.001);

    item.Width := 320.0;
    item.Height := 240.0;
    AssertEquals('Updated Width', 320.0, item.Width, 0.001);
    AssertEquals('Updated Height', 240.0, item.Height, 0.001);
  finally
    item.Free();
  end;
end;

procedure TFloriaFTMLTypesTest.TestHierarchyAndFindById();
var
  root, child1, child2, grandChild: TFloriaFTMLItem;
begin
  root := TFloriaFTMLItem.Create('Item');
  child1 := TFloriaFTMLItem.Create('Rectangle');
  child1.Id := 'rect1';
  child2 := TFloriaFTMLItem.Create('Button');
  child2.Id := 'btnSubmit';
  grandChild := TFloriaFTMLItem.Create('Text');
  grandChild.Id := 'txtLabel';
  try
    root.AddChild(child1);
    root.AddChild(child2);
    child1.AddChild(grandChild);

    AssertEquals('Root ChildCount', 2, root.ChildCount());
    AssertTrue('Child1 Parent is root', child1.Parent = root);
    AssertTrue('GrandChild Parent is child1', grandChild.Parent = child1);

    AssertTrue('FindById rect1', root.FindById('rect1') = child1);
    AssertTrue('FindById btnSubmit', root.FindById('btnSubmit') = child2);
    AssertTrue('FindById txtLabel', root.FindById('txtLabel') = grandChild);
    AssertNull('FindById nonExistent is nil', root.FindById('unknown'));
  finally
    grandChild.Free();
    child2.Free();
    child1.Free();
    root.Free();
  end;
end;

procedure TFloriaFTMLTypesTest.TestBuiltinElements();
var
  rect: TFloriaFTMLRectangle;
  txt: TFloriaFTMLText;
  btn: TFloriaFTMLButton;
  col: TFloriaFTMLColumn;
  r1, r2: TFloriaFTMLItem;
begin
  rect := TFloriaFTMLRectangle.Create();
  txt := TFloriaFTMLText.Create();
  btn := TFloriaFTMLButton.Create();
  col := TFloriaFTMLColumn.Create();
  r1 := TFloriaFTMLItem.Create('Item');
  r2 := TFloriaFTMLItem.Create('Item');
  try
    // Rectangle properties
    AssertEquals('Default rect color', '#ffffff', rect.Color);
    rect.Color := '#336699';
    rect.Radius := 8.0;
    AssertEquals('Updated rect color', '#336699', rect.Color);
    AssertEquals('Updated rect radius', 8.0, rect.Radius, 0.001);

    // Text properties
    txt.Text := 'Floria Toolkit';
    txt.FontSize := 18.0;
    AssertEquals('Text content', 'Floria Toolkit', txt.Text);
    AssertEquals('Text size', 18.0, txt.FontSize, 0.001);

    // Button properties
    btn.Text := 'Click';
    AssertFalse('Default not pressed', btn.Pressed);
    btn.Pressed := True;
    AssertTrue('Pressed is true', btn.Pressed);

    // Column layout
    r1.Height := 30.0;
    r2.Height := 50.0;
    col.Spacing := 10.0;
    col.AddChild(r1);
    col.AddChild(r2);
    col.Relayout();
    AssertEquals('r1 Y is 0', 0.0, r1.Y, 0.001);
    AssertEquals('r2 Y is 30 + 10 = 40', 40.0, r2.Y, 0.001);
  finally
    r2.Free();
    r1.Free();
    col.Free();
    btn.Free();
    txt.Free();
    rect.Free();
  end;
end;

procedure TFloriaFTMLTypesTest.TestSignalDispatch();
var
  engine: TFloriaFTMLEngine;
  item: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    item := engine.LoadString('Item { id: testItem; property int count: 0; onClicked: { count = count + 5; } }');
    AssertNotNull('Loaded item', item);
    AssertEquals('Initial count is 0', 0.0, item.GetPropertyAsNumber('count'), 0.001);

    item.EmitSignal('clicked');
    AssertEquals('Count after signal emission is 5', 5.0, item.GetPropertyAsNumber('count'), 0.001);

    item.EmitSignal('onClicked');
    AssertEquals('Count after second signal emission is 10', 10.0, item.GetPropertyAsNumber('count'), 0.001);
  finally
    engine.Free();
  end;
end;

{ TFloriaFTMLBindingTest }

procedure TFloriaFTMLBindingTest.TestDirectBinding();
var
  engine: TFloriaFTMLEngine;
  root, box: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString('Rectangle { id: root; width: 400; height: 300; Rectangle { id: box; width: root.width / 2; height: root.height / 2; } }');
    AssertNotNull('Loaded root', root);
    box := engine.FindItemById('box');
    AssertNotNull('Found box', box);

    AssertEquals('Initial box width (400 / 2)', 200.0, box.Width, 0.001);
    AssertEquals('Initial box height (300 / 2)', 150.0, box.Height, 0.001);

    // Modify root width -> box.width must reactively update!
    root.Width := 800.0;
    AssertEquals('Updated box width (800 / 2)', 400.0, box.Width, 0.001);

    // Modify root height -> box.height must reactively update!
    root.Height := 600.0;
    AssertEquals('Updated box height (600 / 2)', 300.0, box.Height, 0.001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLBindingTest.TestCascadedBinding();
var
  engine: TFloriaFTMLEngine;
  root, box, labelItem: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString(
      'Rectangle {' +
      '  id: root; width: 200;' +
      '  Rectangle {' +
      '    id: box; width: root.width * 2;' +
      '    Text {' +
      '      id: label; text: "W:" + box.width;' +
      '    }' +
      '  }' +
      '}');
    AssertNotNull('Loaded root', root);
    box := engine.FindItemById('box');
    labelItem := engine.FindItemById('label');
    AssertNotNull('Found box', box);
    AssertNotNull('Found label', labelItem);

    AssertEquals('Initial box width is 400', 400.0, box.Width, 0.001);
    AssertEquals('Initial label text is "W:400"', 'W:400', labelItem.GetPropertyAsString('text'));

    // Changing root cascades to box, and box cascades to label!
    root.Width := 500.0;
    AssertEquals('Updated box width is 1000', 1000.0, box.Width, 0.001);
    AssertEquals('Updated label text is "W:1000"', 'W:1000', labelItem.GetPropertyAsString('text'));
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLBindingTest.TestAssignmentBreaksBinding();
var
  engine: TFloriaFTMLEngine;
  root, box: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString('Rectangle { id: root; width: 400; Rectangle { id: box; width: root.width / 2; } }');
    box := engine.FindItemById('box');
    AssertEquals('Initial box width is 200', 200.0, box.Width, 0.001);

    // Explicit assignment directly to box.width breaks the binding
    box.Width := 999.0;
    AssertEquals('Direct assignment to box.width', 999.0, box.Width, 0.001);

    // Changing root.width should NO LONGER affect box.width
    root.Width := 600.0;
    AssertEquals('box.width remains 999 after root change', 999.0, box.Width, 0.001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLBindingTest.TestCycleGuard();
var
  engine: TFloriaFTMLEngine;
  itemA, itemB: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    // Item A depends on B, and Item B depends on A
    itemA := engine.LoadString(
      'Item {' +
      '  id: itemA; width: itemB.width + 10;' +
      '  Item { id: itemB; width: 50; }' +
      '}');
    AssertNotNull('Parsed cycle without hanging', itemA);
    itemB := engine.FindItemById('itemB');
    AssertNotNull('itemB exists', itemB);
  finally
    engine.Free();
  end;
end;

{ TFloriaFTMLEngineTest }

procedure TFloriaFTMLEngineTest.TestLoadSimpleFTML();
var
  engine: TFloriaFTMLEngine;
  root: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString('Rectangle { id: myWindow; width: 640; height: 480; color: "#222222"; }');
    AssertNotNull('Root item created', root);
    AssertTrue('Root is TFloriaFTMLRectangle', root is TFloriaFTMLRectangle);
    AssertEquals('ID is myWindow', 'myWindow', root.Id);
    AssertEquals('Width is 640', 640.0, root.Width, 0.001);
    AssertEquals('Height is 480', 480.0, root.Height, 0.001);
    AssertEquals('Color is #222222', '#222222', TFloriaFTMLRectangle(root).Color);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLEngineTest.TestLoadNestedFTMLWithBindings();
var
  engine: TFloriaFTMLEngine;
  root, btn: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString(
      'Rectangle {' +
      '  id: mainView;' +
      '  width: 500;' +
      '  height: 400;' +
      '  Button {' +
      '    id: myBtn;' +
      '    width: parent.width - 100;' +
      '    height: 50;' +
      '    text: "Click Me";' +
      '  }' +
      '}');
    AssertNotNull('Root instantiated', root);
    btn := engine.FindItemById('myBtn');
    AssertNotNull('Child button found', btn);
    AssertEquals('Button text', 'Click Me', btn.GetPropertyAsString('text'));
    AssertEquals('Button width is parent.width - 100 = 400', 400.0, btn.Width, 0.001);

    // Update parent width
    root.Width := 800.0;
    AssertEquals('Button width dynamically updated to 700', 700.0, btn.Width, 0.001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLEngineTest.TestIdResolutionInJS();
var
  engine: TFloriaFTMLEngine;
  root, txt: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString(
      'Rectangle {' +
      '  id: header;' +
      '  property string appTitle: "Floria App";' +
      '  Rectangle {' +
      '    id: body;' +
      '    Text {' +
      '      id: titleLabel;' +
      '      text: "App: " + header.appTitle;' +
      '    }' +
      '  }' +
      '}');
    txt := engine.FindItemById('titleLabel');
    AssertNotNull('Found titleLabel', txt);
    AssertEquals('Text bound to header.appTitle', 'App: Floria App', txt.GetPropertyAsString('text'));

    // Update header.appTitle from Pascal/JS
    root.SetProperty('appTitle', JSMakeString('Super App'));
    AssertEquals('Text updated to "App: Super App"', 'App: Super App', txt.GetPropertyAsString('text'));
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLEngineTest.TestFTMLComponentFunctions();
var
  engine: TFloriaFTMLEngine;
  root: TFloriaFTMLItem;
  res: TFloriaJSValue;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString(
      'Rectangle {' +
      '  id: calculator;' +
      '  width: 100;' +
      '  height: 50;' +
      '  function computeArea(scale) {' +
      '    return width * height * scale;' +
      '  }' +
      '}');
    AssertNotNull('Root item created', root);

    // Call computeArea through engine JavaScript evaluation
    res := engine.Evaluate('calculator.computeArea(2);');
    AssertTrue('Result is number', res.IsNumber());
    AssertEquals('Computed area is 100 * 50 * 2 = 10000', 10000.0, res.NumVal, 0.001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLEngineTest.TestFTMLSignalHandling();
var
  engine: TFloriaFTMLEngine;
  root, btn: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString(
      'Rectangle {' +
      '  id: rootRect;' +
      '  property int counter: 0;' +
      '  Button {' +
      '    id: incBtn;' +
      '    onClicked: {' +
      '      rootRect.counter = rootRect.counter + 1;' +
      '    }' +
      '  }' +
      '}');
    btn := engine.FindItemById('incBtn');
    AssertNotNull('Found incBtn', btn);
    AssertEquals('Initial counter is 0', 0.0, root.GetPropertyAsNumber('counter'), 0.001);

    // Trigger button click
    TFloriaFTMLButton(btn).Click();
    AssertEquals('Counter incremented to 1', 1.0, root.GetPropertyAsNumber('counter'), 0.001);

    TFloriaFTMLButton(btn).Click();
    AssertEquals('Counter incremented to 2', 2.0, root.GetPropertyAsNumber('counter'), 0.001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLEngineTest.TestComponentOnCompleted();
var
  engine: TFloriaFTMLEngine;
  root: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString(
      'Rectangle {' +
      '  id: appWindow;' +
      '  property string status: "initializing";' +
      '  Component.onCompleted: {' +
      '    status = "ready";' +
      '  }' +
      '}');
    AssertNotNull('Root loaded', root);
    AssertEquals('Status set to ready on completed', 'ready', root.GetPropertyAsString('status'));
  finally
    engine.Free();
  end;
end;

{ TFloriaFTMLAnchorsAndLayoutsTest }

procedure TFloriaFTMLAnchorsAndLayoutsTest.TestSemanticAnchorLines();
var
  item: TFloriaFTMLItem;
  vLeft, vTop, vRight, vBottom: TFloriaJSValue;
  line: TFloriaFTMLAnchorLine;
begin
  item := TFloriaFTMLItem.Create('Item');
  try
    item.Id := 'testItem';
    vLeft := item.GetProperty('left');
    AssertTrue('left returns object', vLeft.IsObject());
    AssertTrue('left is TFloriaFTMLAnchorLine', vLeft.ObjVal is TFloriaFTMLAnchorLine);
    line := TFloriaFTMLAnchorLine(vLeft.ObjVal);
    AssertTrue('line item is item', line.Item = item);
    AssertEquals('line edge is left', 'left', AnchorEdgeToString(line.Edge));
    AssertTrue('is horizontal edge', IsHorizontalAnchorEdge(line.Edge));

    vTop := item.GetProperty('top');
    line := TFloriaFTMLAnchorLine(vTop.ObjVal);
    AssertEquals('line edge is top', 'top', AnchorEdgeToString(line.Edge));
    AssertTrue('is vertical edge', IsVerticalAnchorEdge(line.Edge));

    vRight := item.GetProperty('right');
    line := TFloriaFTMLAnchorLine(vRight.ObjVal);
    AssertEquals('line edge is right', 'right', AnchorEdgeToString(line.Edge));

    vBottom := item.GetProperty('bottom');
    line := TFloriaFTMLAnchorLine(vBottom.ObjVal);
    AssertEquals('line edge is bottom', 'bottom', AnchorEdgeToString(line.Edge));
  finally
    item.Free();
  end;
end;

procedure TFloriaFTMLAnchorsAndLayoutsTest.TestAnchorsFillAndMargins();
var
  engine: TFloriaFTMLEngine;
  root, inner: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString(
      'Rectangle {' +
      '  id: root; width: 400; height: 300;' +
      '  Rectangle {' +
      '    id: inner;' +
      '    anchors.fill: parent;' +
      '    anchors.margins: 20;' +
      '  }' +
      '}');
    AssertNotNull('Root loaded', root);
    inner := engine.FindItemById('inner');
    AssertNotNull('inner found', inner);
    AssertEquals('inner X is 20', 20.0, inner.X, 0.001);
    AssertEquals('inner Y is 20', 20.0, inner.Y, 0.001);
    AssertEquals('inner Width is 360', 360.0, inner.Width, 0.001);
    AssertEquals('inner Height is 260', 260.0, inner.Height, 0.001);

    // Dynamic resize of root
    root.Width := 500.0;
    root.Height := 400.0;
    AssertEquals('inner Width updated to 460', 460.0, inner.Width, 0.001);
    AssertEquals('inner Height updated to 360', 360.0, inner.Height, 0.001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLAnchorsAndLayoutsTest.TestOpposingAnchorsOverrideExplicitSize();
var
  engine: TFloriaFTMLEngine;
  root, panel: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString(
      'Rectangle {' +
      '  id: root; width: 600; height: 400;' +
      '  Rectangle {' +
      '    id: panel;' +
      '    width: 100;' +
      '    height: 80;' +
      '    anchors.left: parent.left;' +
      '    anchors.right: parent.right;' +
      '    anchors.top: parent.top;' +
      '    anchors.bottom: parent.bottom;' +
      '    anchors.leftMargin: 10;' +
      '    anchors.rightMargin: 20;' +
      '    anchors.topMargin: 30;' +
      '    anchors.bottomMargin: 40;' +
      '  }' +
      '}');
    AssertNotNull('Root loaded', root);
    panel := engine.FindItemById('panel');
    AssertNotNull('panel found', panel);
    AssertEquals('panel X is 10', 10.0, panel.X, 0.001);
    AssertEquals('panel Y is 30', 30.0, panel.Y, 0.001);
    AssertEquals('panel Width is overridden to 570', 570.0, panel.Width, 0.001);
    AssertEquals('panel Height is overridden to 330', 330.0, panel.Height, 0.001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLAnchorsAndLayoutsTest.TestSiblingAnchoringAndReactivity();
var
  engine: TFloriaFTMLEngine;
  root, header, content: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString(
      'Rectangle {' +
      '  id: root; width: 500; height: 500;' +
      '  Rectangle {' +
      '    id: header;' +
      '    x: 10; y: 10; width: 480; height: 80;' +
      '  }' +
      '  Rectangle {' +
      '    id: content;' +
      '    anchors.top: header.bottom;' +
      '    anchors.left: parent.left;' +
      '    anchors.right: parent.right;' +
      '    anchors.topMargin: 15;' +
      '    anchors.leftMargin: 10;' +
      '    anchors.rightMargin: 10;' +
      '    height: 200;' +
      '  }' +
      '}');
    AssertNotNull('Root loaded', root);
    header := engine.FindItemById('header');
    content := engine.FindItemById('content');
    AssertNotNull('header found', header);
    AssertNotNull('content found', content);

    // Initial content bounds
    AssertEquals('content X is 10', 10.0, content.X, 0.001);
    AssertEquals('content Y is 105', 105.0, content.Y, 0.001);
    AssertEquals('content Width is 480', 480.0, content.Width, 0.001);
    AssertEquals('content Height is 200', 200.0, content.Height, 0.001);

    // Dynamically increase header height: content.Y must reactively move down
    header.Height := 120.0;
    AssertEquals('content Y reactively updated to 145', 145.0, content.Y, 0.001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLAnchorsAndLayoutsTest.TestFlexBoxLayoutAndProperties();
var
  engine: TFloriaFTMLEngine;
  root, b1, b2: TFloriaFTMLItem;
  flex: TFloriaFTMLFlexBox;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString(
      'FlexBox {' +
      '  id: flex;' +
      '  width: 400; height: 200;' +
      '  direction: "column";' +
      '  gap: 12;' +
      '  justifyContent: "space-between";' +
      '  alignItems: "center";' +
      '  Button { id: b1; flexGrow: 1.0; alignSelf: "stretch"; }' +
      '  Button { id: b2; flexGrow: 2.0; }' +
      '}');
    AssertNotNull('Root loaded', root);
    AssertTrue('root is TFloriaFTMLFlexBox', root is TFloriaFTMLFlexBox);
    flex := TFloriaFTMLFlexBox(root);
    AssertEquals('Direction is column', 'column', flex.Direction);
    AssertEquals('Gap is 12', 12.0, flex.Gap, 0.001);
    AssertEquals('JustifyContent is space-between', 'space-between', flex.JustifyContent);
    AssertEquals('AlignItems is center', 'center', flex.AlignItems);

    b1 := engine.FindItemById('b1');
    b2 := engine.FindItemById('b2');
    AssertNotNull('b1 found', b1);
    AssertNotNull('b2 found', b2);
    AssertEquals('b1 flexGrow is 1.0', 1.0, b1.FlexGrow, 0.001);
    AssertEquals('b1 alignSelf is stretch', 'stretch', b1.AlignSelf);
    AssertEquals('b2 flexGrow is 2.0', 2.0, b2.FlexGrow, 0.001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLAnchorsAndLayoutsTest.TestGridLayoutAndProperties();
var
  engine: TFloriaFTMLEngine;
  root, c1, c2: TFloriaFTMLItem;
  grid: TFloriaFTMLGrid;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString(
      'Grid {' +
      '  id: grid;' +
      '  columns: 3;' +
      '  gap: 16;' +
      '  Rectangle { id: c1; gridColumn: 0; gridRow: 0; colSpan: 2; }' +
      '  Rectangle { id: c2; gridColumn: 2; gridRow: 0; }' +
      '}');
    AssertNotNull('Root loaded', root);
    AssertTrue('root is TFloriaFTMLGrid', root is TFloriaFTMLGrid);
    grid := TFloriaFTMLGrid(root);
    AssertEquals('Columns is 3', 3, grid.Columns);
    AssertEquals('Gap is 16', 16.0, grid.Gap, 0.001);

    c1 := engine.FindItemById('c1');
    c2 := engine.FindItemById('c2');
    AssertNotNull('c1 found', c1);
    AssertNotNull('c2 found', c2);
    AssertEquals('c1 gridColumn is 0', 0, c1.GridColumn);
    AssertEquals('c1 colSpan is 2', 2, c1.ColSpan);
    AssertEquals('c2 gridColumn is 2', 2, c2.GridColumn);
    AssertEquals('c2 colSpan is 1', 1, c2.ColSpan);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLAnchorsAndLayoutsTest.TestQmlLayoutAliases();
var
  engine: TFloriaFTMLEngine;
  root, item1: TFloriaFTMLItem;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    root := engine.LoadString(
      'Item {' +
      '  Item {' +
      '    id: item1;' +
      '    Layout.fillWidth: true;' +
      '    Layout.preferredHeight: 48;' +
      '    Layout.column: 1;' +
      '    Layout.row: 2;' +
      '    Layout.columnSpan: 3;' +
      '    Layout.alignment: "center";' +
      '  }' +
      '}');
    AssertNotNull('Root loaded', root);
    item1 := engine.FindItemById('item1');
    AssertNotNull('item1 found', item1);
    AssertEquals('item1 flexGrow is 1.0 via Layout.fillWidth', 1.0, item1.FlexGrow, 0.001);
    AssertEquals('item1 height is 48 via Layout.preferredHeight', 48.0, item1.Height, 0.001);
    AssertEquals('item1 gridColumn is 1 via Layout.column', 1, item1.GridColumn);
    AssertEquals('item1 gridRow is 2 via Layout.row', 2, item1.GridRow);
    AssertEquals('item1 colSpan is 3 via Layout.columnSpan', 3, item1.ColSpan);
    AssertEquals('item1 alignSelf is center via Layout.alignment', 'center', item1.AlignSelf);
    AssertTrue('Layout.fillWidth property reads True', item1.GetProperty('Layout.fillWidth').ToBoolean());
  finally
    engine.Free();
  end;
end;

{ TFloriaFTMLLifecycleTest }

const
  LIFECYCLE_FTML =
    'Rectangle {' +
    '  id: mainWindow;' +
    '  width: 600;' +
    '  height: 400;' +
    '  Rectangle {' +
    '    id: cardView;' +
    '    width: parent.width - 40;' +
    '    Text { id: sizeLabel; text: "Card: " + cardView.width; }' +
    '  }' +
    '}';

procedure TFloriaFTMLLifecycleTest.TestReloadDoesNotGrowHeap();
var
  engine: TFloriaFTMLEngine;
  objCount, envCount, i: Integer;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    engine.LoadString(LIFECYCLE_FTML);
    objCount := engine.JSContext.Heap.GetObjectCount;
    envCount := engine.JSContext.Heap.GetEnvironmentCount;

    for i := 1 to 3 do
      engine.LoadString(LIFECYCLE_FTML);

    AssertTrue('Heap object count must not grow across reloads (' +
      IntToStr(objCount) + ' -> ' + IntToStr(engine.JSContext.Heap.GetObjectCount) + ')',
      objCount = engine.JSContext.Heap.GetObjectCount);
    AssertTrue('Heap environment count must not grow across reloads (' +
      IntToStr(envCount) + ' -> ' + IntToStr(engine.JSContext.Heap.GetEnvironmentCount) + ')',
      envCount = engine.JSContext.Heap.GetEnvironmentCount);
    AssertTrue('Bindings must not be duplicated by reloads (' +
      IntToStr(engine.BindingManager.BindingCount) + ')',
      engine.BindingManager.BindingCount = 2);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLLifecycleTest.TestReloadWithdrawsDocumentIds();
var
  engine: TFloriaFTMLEngine;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    engine.LoadString(LIFECYCLE_FTML);
    AssertNotNull('mainWindow resolves before reload', engine.FindItemById('mainWindow'));

    engine.LoadString('Rectangle { id: otherWindow; width: 300; height: 200; }');

    AssertTrue('Stale document id must not resolve after reload',
      engine.FindItemById('mainWindow') = nil);
    AssertNotNull('New document id resolves', engine.FindItemById('otherWindow'));
    AssertTrue('Global scope must not keep the stale document id',
      not engine.JSContext.GlobalEnv.HasLocal('mainWindow'));
    AssertTrue('Global scope must expose the new document id',
      engine.JSContext.GlobalEnv.HasLocal('otherWindow'));
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLLifecycleTest.TestExternalContextIsRestoredOnFree();
var
  ctx: TFloriaJSContext;
  engine: TFloriaFTMLEngine;
  baseObjects, baseEnvs: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    { A pristine context only holds the shared standard library. }
    baseObjects := ctx.Heap.GetObjectCount;
    baseEnvs := ctx.Heap.GetEnvironmentCount;

    engine := TFloriaFTMLEngine.Create(ctx);
    try
      engine.LoadString(LIFECYCLE_FTML);
      AssertTrue('Loading a document must grow the shared context',
        ctx.Heap.GetObjectCount > baseObjects);
    finally
      engine.Free();
    end;

    AssertTrue('Freeing the engine must release the document objects (' +
      IntToStr(ctx.Heap.GetObjectCount) + ' vs ' + IntToStr(baseObjects) + ')',
      ctx.Heap.GetObjectCount = baseObjects);
    AssertTrue('Freeing the engine must release the document environments (' +
      IntToStr(ctx.Heap.GetEnvironmentCount) + ' vs ' + IntToStr(baseEnvs) + ')',
      ctx.Heap.GetEnvironmentCount = baseEnvs);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaFTMLLifecycleTest.TestFailedLoadKeepsEngineConsistent();
var
  engine: TFloriaFTMLEngine;
  baselineObjects, baselineEnvs: Integer;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    { A pristine engine only holds the shared standard library. }
    baselineObjects := engine.JSContext.Heap.GetObjectCount;
    baselineEnvs := engine.JSContext.Heap.GetEnvironmentCount;

    engine.LoadString(LIFECYCLE_FTML);
    AssertTrue('Loading a document must grow the heap',
      engine.JSContext.Heap.GetObjectCount > baselineObjects);

    AssertTrue('A malformed document must fail to load',
      engine.LoadString('Rectangle { id: broken; width: ') = nil);
    AssertTrue('A failed load must report an error', engine.HasErrors());

    { The failed document must not leave the previous document behind. }
    AssertTrue('Failed load must release the previous document objects (' +
      IntToStr(engine.JSContext.Heap.GetObjectCount) + ' vs ' +
      IntToStr(baselineObjects) + ')',
      engine.JSContext.Heap.GetObjectCount = baselineObjects);
    AssertTrue('Failed load must release the previous document environments (' +
      IntToStr(engine.JSContext.Heap.GetEnvironmentCount) + ' vs ' +
      IntToStr(baselineEnvs) + ')',
      engine.JSContext.Heap.GetEnvironmentCount = baselineEnvs);
    AssertTrue('Failed load must withdraw the previous document ids',
      engine.FindItemById('mainWindow') = nil);
  finally
    engine.Free();
  end;
end;

procedure TFloriaFTMLLifecycleTest.TestRuntimeClosureSurvivesDocumentReload();
var
  engine: TFloriaFTMLEngine;
  btn: TFloriaFTMLItem;
  res: TFloriaJSResult;
begin
  engine := TFloriaFTMLEngine.Create();
  try
    { The handler publishes a closure into the global scope at runtime. That
      closure points into the document AST, which a reload discards. }
    AssertTrue('The document must load',
      engine.LoadString(
        'Button { id: btn; onClicked: { helper = function() { return 42; }; } }') <> nil);

    btn := engine.FindItemById('btn');
    AssertTrue('The button must be registered', btn <> nil);
    btn.EmitSignal('clicked');

    res := engine.JSContext.Evaluate('helper();');
    AssertEquals('The runtime closure must work while the document is loaded',
      '42', res.StringValue);

    { Reloading discards the AST the closure was declared in. }
    AssertTrue('The second document must load',
      engine.LoadString('Text { id: label; }') <> nil);

    res := engine.JSContext.Evaluate('helper();');
    AssertEquals('The runtime closure must survive a document reload', '42',
      res.StringValue);
  finally
    engine.Free();
  end;
end;

{ TFloriaJSLifetimeTest }

procedure TFloriaJSLifetimeTest.TestLoopDoesNotAccumulateEnvironments();
var
  ctx: TFloriaJSContext;
  baseline: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    baseline := ctx.Heap.GetEnvironmentCount;

    ctx.Evaluate('var total = 0;');
    ctx.Evaluate('for (var i = 0; i < 5000; i++) { total = total + 1; }');

    AssertTrue('A long running loop must not accumulate environments (' +
      IntToStr(baseline) + ' -> ' + IntToStr(ctx.Heap.GetEnvironmentCount) + ')',
      ctx.Heap.GetEnvironmentCount = baseline);
    AssertEquals('The loop must still produce the correct result', '5000',
      ctx.Evaluate('total;').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSLifetimeTest.TestRecursionDoesNotAccumulateEnvironments();
var
  ctx: TFloriaJSContext;
  baseline: Integer;
  res: TFloriaJSResult;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    baseline := ctx.Heap.GetEnvironmentCount;

    { The function is declared and called inside the same script, because the
      script AST is released when the evaluation ends. }
    res := ctx.Evaluate(
      'function rec(n) { if (n <= 0) { return 0; } return rec(n - 1) + 1; }' +
      'rec(200);');

    AssertTrue('The recursion must succeed', res.Success);
    AssertEquals('The recursion must still produce the correct result', '200',
      res.StringValue);
    AssertTrue('Deep recursion must not accumulate environments (' +
      IntToStr(baseline) + ' -> ' + IntToStr(ctx.Heap.GetEnvironmentCount) + ')',
      ctx.Heap.GetEnvironmentCount = baseline);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSLifetimeTest.TestClosureKeepsItsScopeAlive();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('A closure must keep its captured scope alive', '2',
      ctx.Evaluate(
        'function mk() { var c = 0; return function() { c = c + 1; return c; }; } ' +
        'var f = mk(); f(); f();').StringValue);

    AssertEquals('A closure created inside a loop must capture the loop scope', '2',
      ctx.Evaluate(
        'var t = 0; for (var i = 0; i < 3; i++) { var g = function() { return i; }; t = g(); } t;').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSLifetimeTest.TestFunctionOutlivesItsScript();
var
  ctx: TFloriaJSContext;
  res: TFloriaJSResult;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    res := ctx.Evaluate('function add(a, b) { return a + b; }');
    AssertTrue('The declaration must succeed', res.Success);

    { The AST of the declaring script is released when the evaluation ends:
      the function must survive it and stay callable from a later script. }
    res := ctx.Evaluate('add(2, 3);');
    AssertTrue('The function must still be callable', res.Success);
    AssertEquals('The function must still return the correct result', '5',
      res.StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSLifetimeTest.TestFunctionExpressionOutlivesItsScript();
var
  ctx: TFloriaJSContext;
  res: TFloriaJSResult;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    res := ctx.Evaluate('var twice = function(n) { return n * 2; };');
    AssertTrue('The declaration must succeed', res.Success);

    res := ctx.Evaluate('twice(21);');
    AssertTrue('The closure must still be callable', res.Success);
    AssertEquals('The closure must still return the correct result', '42',
      res.StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSLifetimeTest.TestRecursiveFunctionOutlivesItsScript();
var
  ctx: TFloriaJSContext;
  res: TFloriaJSResult;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    res := ctx.Evaluate(
      'function rec(n) { if (n <= 0) { return 0; } return rec(n - 1) + 1; }');
    AssertTrue('The declaration must succeed', res.Success);

    res := ctx.Evaluate('rec(5);');
    AssertTrue('The recursive function must still be callable', res.Success);
    AssertEquals('The recursive function must still return the correct result',
      '5', res.StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSLifetimeTest.TestNestedFunctionDeclarationIsReusable();
var
  ctx: TFloriaJSContext;
  res: TFloriaJSResult;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    { The nested declaration is executed twice: each execution creates its own
      closure, and both must keep pointing at a valid body. }
    res := ctx.Evaluate(
      'function outer() { function inner() { return 7; } return inner(); } ' +
      'outer() + outer();');
    AssertTrue('The script must succeed', res.Success);
    AssertEquals('A nested declaration must stay usable on every execution',
      '14', res.StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSLifetimeTest.TestSharedNodeReferenceCounting();
var
  node: TCountedASTNode;
begin
  node := TCountedASTNode.Create(1, 1);
  try
    AssertEquals('A new node must start with a single reference', 1,
      node.RefCount);

    node.Retain;
    AssertEquals('Retain must add a reference', 2, node.RefCount);

    node.Release;
    AssertEquals('The node must survive while a reference is left', 0,
      node.DestroyCount);
    AssertEquals('The node must still be usable after a release', 1,
      node.RefCount);

    node.Release;
    AssertEquals('The node must be destroyed with its last reference', 1,
      node.DestroyCount);
  finally
    { The last release already destroyed the node. }
    node := nil;
  end;
end;

procedure TFloriaJSLifetimeTest.TestFunctionBodySurvivesItsDeclaration();
var
  decl: TFloriaJSFunctionDecl;
  block: TFloriaJSBlockStmt;
  retStmt: TFloriaJSReturnStmt;
  fn: TFloriaJSFunction;
  evaluator: TFloriaJSEvaluator;
  env: TFloriaJSEnvironment;
  args: array of TFloriaJSValue;
  val: TFloriaJSValue;
begin
  evaluator := TFloriaJSEvaluator.Create;
  try
    env := TFloriaJSEnvironment.Create(nil);
    try
      decl := TFloriaJSFunctionDecl.Create('f', 1, 1);
      block := TFloriaJSBlockStmt.Create(1, 1);
      retStmt := TFloriaJSReturnStmt.Create(
        TFloriaJSLiteralExpr.CreateNumber(42, 1, 1), 1, 1);
      block.AddStatement(retStmt);
      decl.SetBody(block);

      fn := TFloriaJSFunction.CreateUser('f', nil, decl.Body, Pointer(env), False);

      { The declaration is discarded, exactly as it is when the script that
        created it ends: the body must stay alive for the closure. }
      decl.Free();

      val := evaluator.CallFunction(JSMakeFunction(fn), args, JSMakeUndefined());
      AssertEquals('The closure must still execute its body', '42',
        val.ToString());
    finally
      env.Free();
      fn.Free();
    end;
  finally
    evaluator.Free();
  end;
end;

procedure TFloriaJSLifetimeTest.TestClosureEscapingItsScopeSurvives();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('A closure must outlive the scope that created it', '3',
      ctx.Evaluate(
        'function mk() { var c = 0; return function () { c = c + 1; return c; }; }' +
        'var f = mk(); f(); f(); f();').StringValue);

    { A safe point reclaims the scopes that no closure can reach any more:
      the scope of the escaping closure must not be one of them. }
    ctx.Evaluate('0;');
    AssertEquals('The captured scope must survive the reclamation', '5',
      ctx.Evaluate('f(); f();').StringValue);
  finally
    ctx.Free();
  end;
end;

{ TFloriaJSSwitchTest }

procedure TFloriaJSSwitchTest.TestSwitchMatching();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let r = "";' + LineEnding +
      'switch (2) {' + LineEnding +
      '  case 1: r = "one"; break;' + LineEnding +
      '  case 2: r = "two"; break;' + LineEnding +
      '  case 3: r = "three"; break;' + LineEnding +
      '}' + LineEnding +
      'r;'
    );
    AssertTrue('Switch success', res.Success);
    AssertEquals('Only the matching case runs', 'two', res.StringValue);

    res := engine.Execute(
      'let r = "keep";' + LineEnding +
      'switch (9) { case 1: r = "one"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Switch without a match success', res.Success);
    AssertEquals('A switch without a match changes nothing', 'keep', res.StringValue);

    res := engine.Execute(
      'let r = "";' + LineEnding +
      'switch ("1") { case 1: r = "number"; break; default: r = "fallback"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Switch strict equality success', res.Success);
    AssertEquals('A string does not match a numeric case', 'fallback', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSSwitchTest.TestSwitchDefaultClause();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let r = "";' + LineEnding +
      'switch (42) { case 1: r = "one"; break; default: r = "other"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Switch default success', res.Success);
    AssertEquals('The default clause runs when no case matches', 'other', res.StringValue);

    res := engine.Execute(
      'let r = "";' + LineEnding +
      'switch (1) { default: r = "other"; break; case 1: r = "one"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Switch default placement success', res.Success);
    AssertEquals('A matching case wins over the default clause', 'one', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSSwitchTest.TestSwitchFallThrough();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let r = "";' + LineEnding +
      'switch (1) {' + LineEnding +
      '  case 1: r = r + "a";' + LineEnding +
      '  case 2: r = r + "b"; break;' + LineEnding +
      '  case 3: r = r + "c";' + LineEnding +
      '}' + LineEnding +
      'r;'
    );
    AssertTrue('Switch fall through success', res.Success);
    AssertEquals('A clause falls through to the next one', 'ab', res.StringValue);

    res := engine.Execute(
      'let r = "";' + LineEnding +
      'switch (2) { case 1: r = r + "a"; default: r = r + "d"; case 3: r = r + "c"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Switch fall through default success', res.Success);
    AssertEquals('The default clause also falls through', 'dc', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSSwitchTest.TestSwitchBreakAndContinue();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let r = "";' + LineEnding +
      'for (let i = 0; i < 3; i = i + 1) {' + LineEnding +
      '  switch (i) {' + LineEnding +
      '    case 1: r = r + "x"; break;' + LineEnding +
      '    default: r = r + "d";' + LineEnding +
      '  }' + LineEnding +
      '  r = r + ".";' + LineEnding +
      '}' + LineEnding +
      'r;'
    );
    AssertTrue('Switch break success', res.Success);
    AssertEquals('A break leaves the switch but not the loop', 'd.x.d.', res.StringValue);

    res := engine.Execute(
      'let r = "";' + LineEnding +
      'for (let i = 0; i < 4; i = i + 1) {' + LineEnding +
      '  switch (i) { case 1: continue; default: r = r + i; }' + LineEnding +
      '}' + LineEnding +
      'r;'
    );
    AssertTrue('Switch continue success', res.Success);
    AssertEquals('A continue belongs to the enclosing loop', '023', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSSwitchTest.TestSwitchNestedAndInFunction();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'function classify(v) {' + LineEnding +
      '  switch (v) {' + LineEnding +
      '    case 1: return "one";' + LineEnding +
      '    case 2: return "two";' + LineEnding +
      '    default: return "other";' + LineEnding +
      '  }' + LineEnding +
      '}' + LineEnding +
      'classify(2) + "/" + classify(7);'
    );
    AssertTrue('Switch in a function success', res.Success);
    AssertEquals('A switch returns from the function it belongs to', 'two/other', res.StringValue);

    res := engine.Execute(
      'let r = "";' + LineEnding +
      'switch (1) {' + LineEnding +
      '  case 1:' + LineEnding +
      '    switch (2) { case 2: r = "inner"; break; default: r = "inner default"; }' + LineEnding +
      '    r = r + "-outer";' + LineEnding +
      '    break;' + LineEnding +
      '}' + LineEnding +
      'r;'
    );
    AssertTrue('Nested switch success', res.Success);
    AssertEquals('Nested switches keep their own clauses', 'inner-outer', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSSwitchTest.TestSwitchParserErrors();
var
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  switchStmt: TFloriaJSSwitchStmt;
begin
  parser := TFloriaJSParser.Create('switch (1) { case 1 r = 1; }');
  try
    prog := parser.ParseProgram();
    try
      AssertTrue('A case without a colon must be rejected', parser.HasErrors());
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;

  parser := TFloriaJSParser.Create('switch (1) { case 1: r = 1; default: r = 2; }');
  try
    prog := parser.ParseProgram();
    try
      AssertFalse('A well formed switch must parse', parser.HasErrors());
      AssertTrue('The program must hold a switch statement',
        prog.GetStatement(0) is TFloriaJSSwitchStmt);
      switchStmt := TFloriaJSSwitchStmt(prog.GetStatement(0));
      AssertEquals('The switch holds two clauses', 2, switchStmt.GetCaseCount());
      AssertFalse('The first clause is not the default one',
        switchStmt.GetCase(0).IsDefault);
      AssertTrue('The second clause is the default one',
        switchStmt.GetCase(1).IsDefault);
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;
end;

{ TFloriaJSTryCatchTest }

procedure TFloriaJSTryCatchTest.TestThrowAndCatch();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let r = "";' + LineEnding +
      'try { throw "boom"; } catch (e) { r = "caught"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Try and catch success', res.Success);
    AssertEquals('The catch clause runs for a thrown value', 'caught', res.StringValue);

    res := engine.Execute('try { throw "boom"; } catch (e) { e; }');
    AssertTrue('Catch the thrown value success', res.Success);
    AssertEquals('The catch clause binds the thrown value', 'boom', res.StringValue);

    res := engine.Execute('try { throw 42; } catch (e) { e; }');
    AssertTrue('Catch a number success', res.Success);
    AssertEquals('The catch clause binds a number', '42', res.StringValue);

    res := engine.Execute(
      'let r = "none";' + LineEnding +
      'try { r = "body"; } catch (e) { r = "caught"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Try without an error success', res.Success);
    AssertEquals('The catch clause stays untouched without an error', 'body', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestCatchWithoutBinding();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let r = "";' + LineEnding +
      'try { throw "boom"; } catch { r = "caught"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Catch without a binding success', res.Success);
    AssertEquals('A catch clause without a binding still catches', 'caught', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestCatchParameterScope();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let e = "outer";' + LineEnding +
      'try { throw "inner"; } catch (e) { }' + LineEnding +
      'e;'
    );
    AssertTrue('Catch parameter scope success', res.Success);
    AssertEquals('The catch parameter is only visible inside the clause', 'outer', res.StringValue);

    res := engine.Execute(
      'try { throw "inner"; } catch (e) { e; }'
    );
    AssertTrue('Catch parameter value success', res.Success);
    AssertEquals('The catch parameter holds the thrown value', 'inner', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestFinallyAlwaysRuns();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let r = "";' + LineEnding +
      'try { r = "body"; } finally { r = r + "-finally"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Finally after a normal block success', res.Success);
    AssertEquals('The finally clause runs after a normal block', 'body-finally', res.StringValue);

    res := engine.Execute(
      'let r = "";' + LineEnding +
      'try { throw "boom"; } catch (e) { r = "caught"; } finally { r = r + "-finally"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Finally after a catch success', res.Success);
    AssertEquals('The finally clause runs after the catch clause', 'caught-finally', res.StringValue);

    res := engine.Execute(
      'let r = "";' + LineEnding +
      'try { throw "boom"; } finally { r = "finally"; }'
    );
    AssertFalse('An uncaught error must be reported', res.Success);
    AssertEquals('The finally clause runs for an uncaught error too', 'boom', res.ErrorMessage);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestFinallyWithReturn();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'function f() { try { return "value"; } finally { } }' + LineEnding +
      'f();'
    );
    AssertTrue('Return inside a try success', res.Success);
    AssertEquals('A return inside a try leaves the function', 'value', res.StringValue);

    res := engine.Execute(
      'function f() { try { return "value"; } catch (e) { return "caught"; } }' + LineEnding +
      'f();'
    );
    AssertTrue('Return inside a try with a catch success', res.Success);
    AssertEquals('The catch clause does not swallow a return', 'value', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestControlFlowPassesThrough();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let r = "";' + LineEnding +
      'for (let i = 0; i < 3; i = i + 1) {' + LineEnding +
      '  try { break; } catch (e) { r = "caught"; }' + LineEnding +
      '}' + LineEnding +
      'r + "b";'
    );
    AssertTrue('Break inside a try success', res.Success);
    AssertEquals('A break is not caught by the catch clause', 'b', res.StringValue);

    res := engine.Execute(
      'let r = "";' + LineEnding +
      'for (let i = 0; i < 3; i = i + 1) {' + LineEnding +
      '  try { continue; } catch (e) { r = "caught"; } finally { r = r + i; }' + LineEnding +
      '}' + LineEnding +
      'r;'
    );
    AssertTrue('Continue inside a try success', res.Success);
    AssertEquals('A continue belongs to the enclosing loop', '012', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestNestedTry();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let r = "";' + LineEnding +
      'try {' + LineEnding +
      '  try { throw "boom"; } catch (e) { r = "inner"; }' + LineEnding +
      '} catch (e) { r = "outer"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Nested try success', res.Success);
    AssertEquals('The innermost catch clause handles the error', 'inner', res.StringValue);

    res := engine.Execute(
      'let r = "";' + LineEnding +
      'try { try { r = "in"; } finally { r = r + "-inner"; } } finally { r = r + "-outer"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Nested finally success', res.Success);
    AssertEquals('Every finally clause runs', 'in-inner-outer', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestThrowFromFunction();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'function boom() { throw "kaboom"; }' + LineEnding +
      'let r = "";' + LineEnding +
      'try { boom(); } catch (e) { r = "caught"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Throw from a function success', res.Success);
    AssertEquals('An error of a function reaches the caller', 'caught', res.StringValue);

    res := engine.Execute(
      'function boom() { throw "kaboom"; }' + LineEnding +
      'try { boom(); } catch (e) { e; }'
    );
    AssertTrue('The thrown value reaches the caller success', res.Success);
    AssertEquals('The thrown value keeps its content', 'kaboom', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestThrowInsideCatch();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'let r = "";' + LineEnding +
      'try {' + LineEnding +
      '  try { throw "first"; } catch (e) { throw "second"; }' + LineEnding +
      '} catch (e) { r = e; }' + LineEnding +
      'r;'
    );
    AssertTrue('Throw inside a catch success', res.Success);
    AssertEquals('An error of a catch clause reaches the outer clause', 'second', res.StringValue);

    res := engine.Execute(
      'try { throw "boom"; } finally { throw "from finally"; }'
    );
    AssertFalse('An error of a finally clause must be reported', res.Success);
    AssertEquals('An error of a finally clause replaces the pending one', 'from finally', res.ErrorMessage);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestErrorObject();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('try { throw Error("boom"); } catch (e) { e; }');
    AssertTrue('Error object success', res.Success);
    AssertEquals('An error object describes itself', 'Error: boom', res.StringValue);

    res := engine.Execute('try { throw Error("boom"); } catch (e) { e.message; }');
    AssertTrue('Error message success', res.Success);
    AssertEquals('The message of an error object is readable', 'boom', res.StringValue);

    res := engine.Execute('try { throw Error("boom"); } catch (e) { e.name; }');
    AssertTrue('Error name success', res.Success);
    AssertEquals('The name of an error object is readable', 'Error', res.StringValue);

    res := engine.Execute('throw Error("boom");');
    AssertFalse('An uncaught error object must be reported', res.Success);
    AssertEquals('An uncaught error object reports its message', 'Error: boom', res.ErrorMessage);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestUncaughtThrow();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('throw "boom";');
    AssertFalse('An uncaught error must be reported', res.Success);
    AssertEquals('An uncaught error reports its value', 'boom', res.ErrorMessage);

    res := engine.Execute('let r = "before"; throw 7; r;');
    AssertFalse('An uncaught error stops the script', res.Success);
    AssertEquals('An uncaught error reports its value', '7', res.ErrorMessage);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestAsyncThrow();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'async function f() { throw "nope"; }' + LineEnding +
      'let r = "";' + LineEnding +
      'try { await f(); } catch (e) { r = "caught"; }' + LineEnding +
      'r;'
    );
    AssertTrue('Async throw success', res.Success);
    AssertEquals('An error of an async function is catchable', 'caught', res.StringValue);

    res := engine.Execute(
      'let r = "";' + LineEnding +
      'try { await Promise.reject("bad"); } catch (e) { r = e; }' + LineEnding +
      'r;'
    );
    AssertTrue('Rejected promise success', res.Success);
    AssertEquals('A rejected promise can be awaited inside a try', 'bad', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestTryParserErrors();
var
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  tryStmt: TFloriaJSTryStmt;
begin
  parser := TFloriaJSParser.Create('try { }');
  try
    prog := parser.ParseProgram();
    try
      AssertTrue('A try without a catch and without a finally must be rejected',
        parser.HasErrors());
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;

  parser := TFloriaJSParser.Create('throw;');
  try
    prog := parser.ParseProgram();
    try
      AssertTrue('A throw without a value must be rejected', parser.HasErrors());
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;

  parser := TFloriaJSParser.Create('try { throw "x"; } catch (e) { } finally { }');
  try
    prog := parser.ParseProgram();
    try
      AssertFalse('A well formed try statement must parse', parser.HasErrors());
      AssertTrue('The program must hold a try statement',
        prog.GetStatement(0) is TFloriaJSTryStmt);
      tryStmt := TFloriaJSTryStmt(prog.GetStatement(0));
      AssertTrue('The try statement holds a block', tryStmt.Block <> nil);
      AssertTrue('The try statement holds a catch clause', tryStmt.CatchBlock <> nil);
      AssertEquals('The catch clause binds a parameter', 'e', tryStmt.CatchParam);
      AssertTrue('The try statement holds a finally clause', tryStmt.FinallyBlock <> nil);
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;
end;

procedure TFloriaJSTryCatchTest.TestTryDoesNotLeak();
var
  ctx: TFloriaJSContext;
  objects, environments: Integer;
  i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    ctx.Evaluate('try { throw "x"; } catch (e) { }');
    objects := ctx.Heap.GetObjectCount;
    environments := ctx.Heap.GetEnvironmentCount;

    for i := 1 to 200 do
      ctx.Evaluate('try { throw "x"; } catch (e) { } finally { }');

    AssertTrue('Repeated try statements must not accumulate objects (' +
      IntToStr(objects) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount = objects);
    AssertTrue('Repeated try statements must not accumulate environments (' +
      IntToStr(environments) + ' -> ' + IntToStr(ctx.Heap.GetEnvironmentCount) + ')',
      ctx.Heap.GetEnvironmentCount = environments);
  finally
    ctx.Free();
  end;
end;

{ TFloriaJSReclamationTest }

procedure TFloriaJSReclamationTest.TestUnreachableObjectIsReclaimed();
var
  ctx: TFloriaJSContext;
  objects: Integer;
  i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    ctx.Evaluate('var tmp = {}; tmp = null;');
    objects := ctx.Heap.GetObjectCount;

    for i := 1 to 200 do
      ctx.Evaluate('var tmp = {}; tmp = null;');

    AssertTrue('Unreachable objects must not accumulate (' +
      IntToStr(objects) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount = objects);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSReclamationTest.TestUnreachableArrayIsReclaimed();
var
  ctx: TFloriaJSContext;
  objects: Integer;
  i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    ctx.Evaluate('var tmp = [1, 2, 3]; tmp = null;');
    objects := ctx.Heap.GetObjectCount;

    for i := 1 to 200 do
      ctx.Evaluate('var tmp = [1, 2, 3]; tmp = null;');

    AssertTrue('Unreachable arrays must not accumulate (' +
      IntToStr(objects) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount = objects);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSReclamationTest.TestFunctionDeclarationIsReclaimed();
var
  ctx: TFloriaJSContext;
  objects: Integer;
  i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    { Every declaration replaces the previous one, so the function that is
      replaced must be reclaimed. }
    ctx.Evaluate('function f() { return 1; }');
    objects := ctx.Heap.GetObjectCount;

    for i := 1 to 200 do
      ctx.Evaluate('function f() { return 1; }');

    { The reclamation happens at the next safe point, so the script that
      follows the loop gives it the chance to catch up. }
    ctx.Evaluate('0;');

    AssertTrue('Replaced function declarations must not accumulate (' +
      IntToStr(objects) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount = objects);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSReclamationTest.TestFunctionExpressionIsReclaimed();
var
  ctx: TFloriaJSContext;
  objects: Integer;
  i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    ctx.Evaluate('var f = function () { return 1; };');
    objects := ctx.Heap.GetObjectCount;

    for i := 1 to 200 do
      ctx.Evaluate('var f = function () { return 1; };');

    { The reclamation happens at the next safe point, so the script that
      follows the loop gives it the chance to catch up. }
    ctx.Evaluate('0;');

    AssertTrue('Replaced function expressions must not accumulate (' +
      IntToStr(objects) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount = objects);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSReclamationTest.TestObjectWithFunctionIsReclaimed();
var
  ctx: TFloriaJSContext;
  objects: Integer;
  i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    ctx.Evaluate('var tmp = {}; tmp.f = function () { return 1; }; tmp = null;');
    objects := ctx.Heap.GetObjectCount;

    for i := 1 to 200 do
      ctx.Evaluate('var tmp = {}; tmp.f = function () { return 1; }; tmp = null;');

    AssertTrue('Objects with a function must not accumulate (' +
      IntToStr(objects) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount = objects);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSReclamationTest.TestReachableObjectSurvives();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    ctx.Evaluate('var keep = { value: 7 };');

    { The evaluation of a script is a safe point at which the unreachable
      objects are reclaimed. The object that is still bound must survive it. }
    ctx.Evaluate('0;');

    AssertEquals('A reachable object must survive the reclamation', '7',
      ctx.Evaluate('keep.value;').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSReclamationTest.TestValueHandedToTheHostSurvivesUntilReleased();
var
  ctx: TFloriaJSContext;
  val: TFloriaJSValue;
  objects: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    val := ctx.EvaluateValue('({ value: 7 });');
    AssertTrue('The evaluated value must be an object',
      val.IsObject() and (val.ObjVal <> nil));

    { The host holds on to the value, so it must not be reclaimed. }
    objects := ctx.Heap.GetObjectCount;
    ctx.Evaluate('0;');
    AssertTrue('A value that was handed out must not be reclaimed (' +
      IntToStr(objects) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount = objects);
    AssertTrue('A value that was handed out must be pinned', val.ObjVal.Pinned);

    { The host gives the value back, so it becomes reclaimable. }
    ctx.ReleaseValue(val);
    ctx.Evaluate('0;');
    AssertTrue('A value that was given back must be reclaimable (' +
      IntToStr(objects) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount < objects);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSReclamationTest.TestBlockScopedFunctionIsReclaimed();
var
  ctx: TFloriaJSContext;
  environments: Integer;
  i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    ctx.Evaluate('{ function inner() { return 1; } }');
    ctx.Evaluate('0;');
    environments := ctx.Heap.GetEnvironmentCount;

    for i := 1 to 200 do
      ctx.Evaluate('{ function inner() { return 1; } }');

    { The reclamation happens at the next safe point, so the script that
      follows the loop gives it the chance to catch up. }
    ctx.Evaluate('0;');

    AssertTrue('Functions declared in a block must not keep its scope alive (' +
      IntToStr(environments) + ' -> ' + IntToStr(ctx.Heap.GetEnvironmentCount) + ')',
      ctx.Heap.GetEnvironmentCount = environments);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSReclamationTest.TestFunctionDeclaredInLoopBodyIsReclaimed();
var
  ctx: TFloriaJSContext;
  environments: Integer;
  i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    ctx.Evaluate(
      'for (var j = 0; j < 3; j++) { function inner() { return 1; } }');
    ctx.Evaluate('0;');
    environments := ctx.Heap.GetEnvironmentCount;

    for i := 1 to 200 do
      ctx.Evaluate(
        'for (var j = 0; j < 3; j++) { function inner() { return 1; } }');

    ctx.Evaluate('0;');

    AssertTrue('Functions declared in a loop body must not keep its scope alive (' +
      IntToStr(environments) + ' -> ' + IntToStr(ctx.Heap.GetEnvironmentCount) + ')',
      ctx.Heap.GetEnvironmentCount = environments);
  finally
    ctx.Free();
  end;
end;

{ TFloriaJSConstructionTest }

procedure TFloriaJSConstructionTest.TestConstructorSetsProperties();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('A constructor must be able to set a property on this', '7',
      ctx.Evaluate(
        'function Point(x) { this.x = x; }' +
        'var p = new Point(7); p.x;').StringValue);

    AssertEquals('The new object must be the value of the expression', 'changed',
      ctx.Evaluate(
        'function C() { this.kind = "changed"; }' +
        'var c = new C(); c.kind;').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSConstructionTest.TestConstructorArguments();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('The arguments must reach the constructor', '15',
      ctx.Evaluate(
        'function Sum(a, b) { this.v = a + b; }' +
        '(new Sum(7, 8)).v;').StringValue);

    AssertEquals('A construction without parentheses must still work', 'undefined',
      ctx.Evaluate(
        'function Empty() {}' +
        '(new Empty()).missing;').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSConstructionTest.TestPrototypeMembers();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('A method published on the prototype must be callable', '42',
      ctx.Evaluate(
        'function Acc() { this.n = 40; }' +
        'Acc.prototype.get = function () { return this.n + 2; };' +
        'var a = new Acc(); a.get();').StringValue);

    AssertEquals('A value published on the prototype must be visible', 'yes',
      ctx.Evaluate(
        'function T() {}' +
        'T.prototype.kind = "yes";' +
        '(new T()).kind;').StringValue);

    AssertEquals('Every function must expose a prototype object', 'object',
      ctx.Evaluate('function T() {} typeof T.prototype;').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSConstructionTest.TestReturnedObjectReplacesInstance();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('An object returned by the constructor must replace the instance', '9',
      ctx.Evaluate(
        'function R() { this.a = 1; return { a: 9 }; }' +
        '(new R()).a;').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSConstructionTest.TestPrimitiveReturnIsIgnored();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('A primitive return value must be ignored', '5',
      ctx.Evaluate(
        'function R() { this.a = 5; return 99; }' +
        '(new R()).a;').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSConstructionTest.TestConstructorThroughMember();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('A constructor reached through a member expression must work', '11',
      ctx.Evaluate(
        'var ns = { C: function (v) { this.v = v; } };' +
        'var o = new ns.C(11); o.v;').StringValue);

    AssertEquals('The result of a construction can be used as a receiver', '4',
      ctx.Evaluate(
        'function C() { this.v = 4; }' +
        'new C().v;').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSConstructionTest.TestObjectConstructor();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('The Object constructor must be available', 'function',
      ctx.Evaluate('typeof Object;').StringValue);

    AssertEquals('new Object() must create an object', 'object',
      ctx.Evaluate('var o = new Object(); typeof o;').StringValue);

    AssertEquals('A construction can be used as an ordinary expression', '1',
      ctx.Evaluate('var o = new Object(); 1;').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSConstructionTest.TestNonConstructorThrows();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('Constructing a non-function must throw a TypeError', 'TypeError',
      ctx.Evaluate(
        'try { new 5; } catch (e) { e.name; }').StringValue);

    AssertEquals('The TypeError must explain the failure', 'Value is not a constructor',
      ctx.Evaluate(
        'try { var x = 1; new x; } catch (e) { e.message; }').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSConstructionTest.TestThisInObjectMethod();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('A method call must bind this to its receiver', '4',
      ctx.Evaluate(
        'var o = { n: 4, m: function () { return this.n; } };' +
        'o.m();').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSConstructionTest.TestNewDoesNotAccumulateObjects();
var
  ctx: TFloriaJSContext;
  objects, environments: Integer;
  i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    { The prototype object is created on first use, so let it exist before the
      baseline is measured. }
    ctx.Evaluate('function C() { this.v = 1; } var obj = new C(); obj = null;');
    ctx.Evaluate('0;');
    objects := ctx.Heap.GetObjectCount;
    environments := ctx.Heap.GetEnvironmentCount;

    for i := 1 to 200 do
      ctx.Evaluate('var obj = new C(); obj = null;');

    ctx.Evaluate('0;');

    AssertTrue('Constructed objects must not accumulate (' +
      IntToStr(objects) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount = objects);
    AssertTrue('Constructor calls must not accumulate environments (' +
      IntToStr(environments) + ' -> ' + IntToStr(ctx.Heap.GetEnvironmentCount) + ')',
      ctx.Heap.GetEnvironmentCount = environments);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSConstructionTest.TestPrototypeIsReclaimedWithItsFunction();
var
  ctx: TFloriaJSContext;
  objects: Integer;
  i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    { The prototype belongs to the function; when the function becomes
      unreachable, the prototype must go with it. }
    ctx.Evaluate(
      'function C() { this.v = 1; }' +
      'C.prototype.m = function () { return this.v; };' +
      'C = null;');
    ctx.Evaluate('0;');
    objects := ctx.Heap.GetObjectCount;

    for i := 1 to 300 do
      ctx.Evaluate(
        'function C() { this.v = 1; }' +
        'C.prototype.m = function () { return this.v; };' +
        'C = null;');

    ctx.Evaluate('0;');

    AssertTrue('Prototypes must be reclaimed with their function (' +
      IntToStr(objects) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount = objects);
  finally
    ctx.Free();
  end;
end;

{ TFloriaJSArrayMethodsTest }

procedure TFloriaJSArrayMethodsTest.TestPushPopShiftUnshift();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('push must append and return the new length', '4',
      ctx.Evaluate(
        'var a = [1, 2]; a.push(3, 4);').StringValue);

    AssertEquals('push must keep the appended elements', '1,2,3,4',
      ctx.Evaluate('a.join(",");').StringValue);

    AssertEquals('pop must return the last element', '4',
      ctx.Evaluate('a.pop();').StringValue);

    AssertEquals('shift must return the first element', '1',
      ctx.Evaluate('a.shift();').StringValue);

    AssertEquals('unshift must insert at the front and return the length', '3',
      ctx.Evaluate('a.unshift(0);').StringValue);

    AssertEquals('the mutation order must be reflected in the array', '0-2-3',
      ctx.Evaluate('a.join("-");').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSArrayMethodsTest.TestJoinConcatReverseSlice();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('join must use the separator', '1-2-3',
      ctx.Evaluate('[1, 2, 3].join("-");').StringValue);

    AssertEquals('join without an argument must use a comma', '1,2,3',
      ctx.Evaluate('[1, 2, 3].join();').StringValue);

    AssertEquals('concat must flatten array arguments once', '1,2,3,4,5',
      ctx.Evaluate('[1, 2].concat([3, 4], 5).join(",");').StringValue);

    AssertEquals('slice must copy the selected range', '2,3',
      ctx.Evaluate('[1, 2, 3].slice(1).join(",");').StringValue);

    AssertEquals('slice must accept negative indices', '2',
      ctx.Evaluate('[1, 2, 3].slice(-2, -1).join(",");').StringValue);

    AssertEquals('reverse must reverse the array in place', '3,2,1',
      ctx.Evaluate('[1, 2, 3].reverse().join(",");').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSArrayMethodsTest.TestIndexOfLastIndexOfIncludes();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('indexOf must find the first match', '1',
      ctx.Evaluate('[1, 2, 3, 2].indexOf(2);').StringValue);

    AssertEquals('lastIndexOf must find the last match', '3',
      ctx.Evaluate('[1, 2, 3, 2].lastIndexOf(2);').StringValue);

    AssertEquals('indexOf must return -1 when the value is absent', '-1',
      ctx.Evaluate('[1, 2, 3].indexOf(9);').StringValue);

    AssertEquals('includes must report a present value', 'true',
      ctx.Evaluate('[1, 2, 3].includes(2);').StringValue);

    AssertEquals('includes must find NaN', 'true',
      ctx.Evaluate('[1, NaN].includes(NaN);').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSArrayMethodsTest.TestMapFilterReduce();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('map must transform every element', '2,4,6',
      ctx.Evaluate('[1, 2, 3].map(function (x) { return x * 2; }).join(",");').StringValue);

    AssertEquals('map must pass the index to the callback', '0:1,1:2',
      ctx.Evaluate(
        '[1, 2].map(function (x, i) { return i + ":" + x; }).join(",");').StringValue);

    AssertEquals('filter must keep the matching elements', '2,4',
      ctx.Evaluate(
        '[1, 2, 3, 4].filter(function (x) { return x % 2 === 0; }).join(",");').StringValue);

    AssertEquals('reduce must combine with an initial value', '16',
      ctx.Evaluate(
        '[1, 2, 3].reduce(function (a, b) { return a + b; }, 10);').StringValue);

    AssertEquals('reduce must use the first element without an initial value', '6',
      ctx.Evaluate(
        '[1, 2, 3].reduce(function (a, b) { return a + b; });').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSArrayMethodsTest.TestForEachSomeEveryFind();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('forEach must visit every element', '6',
      ctx.Evaluate(
        'var total = 0;' +
        '[1, 2, 3].forEach(function (x) { total += x; });' +
        'total;').StringValue);

    AssertEquals('some must find a matching element', 'true',
      ctx.Evaluate('[1, 2, 3].some(function (x) { return x > 2; });').StringValue);

    AssertEquals('some must report false when nothing matches', 'false',
      ctx.Evaluate('[1, 2, 3].some(function (x) { return x > 9; });').StringValue);

    AssertEquals('every must report true when all elements match', 'true',
      ctx.Evaluate('[1, 2, 3].every(function (x) { return x > 0; });').StringValue);

    AssertEquals('every must report false when an element fails', 'false',
      ctx.Evaluate('[1, 2, 3].every(function (x) { return x > 1; });').StringValue);

    AssertEquals('find must return the element', '2',
      ctx.Evaluate('[1, 2, 3].find(function (x) { return x > 1; });').StringValue);

    AssertEquals('findIndex must return the position', '1',
      ctx.Evaluate('[1, 2, 3].findIndex(function (x) { return x > 1; });').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSArrayMethodsTest.TestSortAndSplice();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('sort without a comparator must compare string forms', '1,2,3',
      ctx.Evaluate('[3, 1, 2].sort().join(",");').StringValue);

    AssertEquals('sort must use a comparator when one is given', '3,2,1',
      ctx.Evaluate(
        '[3, 1, 2].sort(function (a, b) { return b - a; }).join(",");').StringValue);

    AssertEquals('splice must return the removed elements', '2,3',
      ctx.Evaluate(
        'var a = [1, 2, 3, 4];' +
        'var removed = a.splice(1, 2, 9, 8);' +
        'removed.join(",");').StringValue);

    AssertEquals('splice must insert the replacement elements in place', '1,9,8,4',
      ctx.Evaluate('a.join(",");').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSArrayMethodsTest.TestArrayStatics();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('Array.isArray must accept an array', 'true',
      ctx.Evaluate('Array.isArray([1, 2]);').StringValue);

    AssertEquals('Array.isArray must reject a non-array', 'false',
      ctx.Evaluate('Array.isArray("abc");').StringValue);

    AssertEquals('Array.from must split a string into characters', 'a-b-c',
      ctx.Evaluate('Array.from("abc").join("-");').StringValue);

    AssertEquals('Array.from must apply the mapping function', '2,3',
      ctx.Evaluate(
        'Array.from([1, 2], function (x) { return x + 1; }).join(",");').StringValue);

    AssertEquals('Array.of must collect its arguments', '1,2,3',
      ctx.Evaluate('Array.of(1, 2, 3).join(",");').StringValue);

    AssertEquals('new Array(n) must create a sparse array of that length', '3',
      ctx.Evaluate('(new Array(3)).length;').StringValue);

    AssertEquals('Array(a, b) must collect its arguments', '2',
      ctx.Evaluate('Array(1, 2).length;').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSArrayMethodsTest.TestArrayCallbacksDoNotAccumulateObjects();
var
  ctx: TFloriaJSContext;
  objects, environments: Integer;
  i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    { The shared array and string prototypes are created on first use, so let
      them exist before the baseline is measured. }
    ctx.Evaluate(
      'var a = [1, 2, 3];' +
      'var f = function (x) { return x * 2; };' +
      'a.map(f);');
    ctx.Evaluate('0;');
    objects := ctx.Heap.GetObjectCount;
    environments := ctx.Heap.GetEnvironmentCount;

    for i := 1 to 200 do
      ctx.Evaluate('a.map(f).join(",");');

    ctx.Evaluate('0;');

    AssertTrue('Array callbacks must not accumulate objects (' +
      IntToStr(objects) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount = objects);
    AssertTrue('Array callbacks must not accumulate environments (' +
      IntToStr(environments) + ' -> ' + IntToStr(ctx.Heap.GetEnvironmentCount) + ')',
      ctx.Heap.GetEnvironmentCount = environments);
  finally
    ctx.Free();
  end;
end;

var
  Application: TTestRunner;

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);

  RegisterTest(TFloriaJSTypesTest);
  RegisterTest(TFloriaJSEngineTest);
  RegisterTest(TFloriaJSLexerTest);
  RegisterTest(TFloriaJSASTTest);
  RegisterTest(TFloriaJSParserTest);
  RegisterTest(TFloriaJSValueTest);
  RegisterTest(TFloriaJSEvaluatorTest);
  RegisterTest(TFloriaFTMLTypesTest);
  RegisterTest(TFloriaFTMLBindingTest);
  RegisterTest(TFloriaFTMLEngineTest);
  RegisterTest(TFloriaFTMLAnchorsAndLayoutsTest);
  RegisterTest(TFloriaFTMLLifecycleTest);
  RegisterTest(TFloriaJSLifetimeTest);
  RegisterTest(TFloriaJSSwitchTest);
  RegisterTest(TFloriaJSTryCatchTest);
  RegisterTest(TFloriaJSReclamationTest);
  RegisterTest(TFloriaJSConstructionTest);
  RegisterTest(TFloriaJSArrayMethodsTest);

  Application := TTestRunner.Create(nil);
  try
    Application.Initialize();
    Application.Title := 'Floria JS Test Runner';
    Application.Run();
  finally
    Application.Free();
  end;
end.
