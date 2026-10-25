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
  floria.js.value, floria.js.env, floria.js.stdlib,
  floria.js.core, floria.js.bytecode, floria.js.vm, floria.js.compiler,
  floria.ftml.types, floria.ftml.binding, floria.ftml.engine, floriajs;

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
    procedure TestBytecodeVMBackendExecution();
    procedure TestContextResetLifecycle();
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
    procedure TestArrayHolePresence();
    procedure TestBinaryAndUnaryOps();
  end;

  { Test 7: VM Runtime Execution & Host Interop }
  TFloriaJSRuntimeTest = class(TTestCase)
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
    procedure TestStandardGlobalsAndArguments();
    procedure TestObjectUtilities();
    procedure TestJSONSupport();
    procedure TestTemplateLiteralInterpolation();
    procedure TestObjectAndArrayLiteralCompletion();
    procedure TestIterationStatements();
    procedure TestParameterFormsAndDestructuring();
    procedure TestErrorHandlingAndTypeErrors();
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
    procedure TestArrayMethodsOverHoles();
    procedure TestArrayLengthMutationDoesNotLeak();
    procedure TestArrayCallbacksDoNotAccumulateObjects();
  end;

  { Test 19: QML V4-Class Bytecode & VM Execution Engine }
  TFloriaJSVMTest = class(TTestCase)
  published
    procedure TestBasicBytecodeArithmetic();
    procedure TestBytecodeLocalVariables();
    procedure TestBytecodeControlFlowAndJumps();
    procedure TestBytecodeFunctionsAndCalls();
    procedure TestBytecodeObjectsAndProperties();
    procedure TestBytecodeTryCatch();
    procedure TestCompileAndRunScript();
  end;

  { Test 20: Priority 3 — Advanced Collections, Date, Symbol, RegExp & Host Globals }
  TFloriaJSPriority3Test = class(TTestCase)
  published
    procedure TestMapCollection();
    procedure TestSetCollection();
    procedure TestDateObject();
    procedure TestSymbolPrimitive();
    procedure TestRegExpAndStringMethods();
    procedure TestURIAndHostGlobals();
  end;

  { Test 21: Priority 1 — Semantic Deviations & Core Language Correctness }
  TFloriaJSPriority1Test = class(TTestCase)
  published
    procedure TestConstReassignmentRejection();
    procedure TestDuplicateLetConstRejection();
    procedure TestUndeclaredIdentifierReferenceError();
    procedure TestFunctionDeclarationHoisting();
    procedure TestArrayPrototypeToString();
    procedure TestForInArrayIndices();
    procedure TestObjectKeysValuesEntriesOnArrays();
    procedure TestArrayPropertyReflection();
    procedure TestFunctionCallApplyBind();
    procedure TestFunctionPrototypeAndConstructor();
    procedure TestNumericParsingAndFormatting();
    procedure TestCompoundAssignmentToMembers();
    procedure TestDestructuringAssignment();
    procedure TestVarHoistingAndFunctionCollisions();
    procedure TestClassicForLoopBlockScoping();
    procedure TestChainWideOptionalChaining();
    procedure TestConstructorBackReferencesLifetimeSafe();
    procedure TestDeclarationValidationAndSwitchHoisting();
    procedure TestArrayHolesAndLengthMutation();
    procedure TestNewOnBoundFunctions();
    procedure TestBoundFunctionConstructionLifetime();
    procedure TestNumberFormattingParity();
    procedure TestNumberParsingParity();
    procedure TestNumberRadixToString();
    procedure TestDeleteSemantics();
    procedure TestDebuggerAndWith();
  end;

  { Priority 2 language features. }
  TFloriaJSPriority2Test = class(TTestCase)
  published
    procedure TestVoidOperator();
    procedure TestLogicalAssignmentIdentifiers();
    procedure TestLogicalAssignmentMembers();
    procedure TestLogicalAssignmentShortCircuit();
    procedure TestBigIntLiteralRejection();
    procedure TestBigIntArithmetic();
    procedure TestBigIntComparisonAndConversion();
    procedure TestPromiseConstructor();
    procedure TestPromiseCallbacksRun();
    procedure TestPromiseAwaitIntegration();
    procedure TestJSONStringifyParity();
    procedure TestJSONParseReviver();
    procedure TestIteratorProtocol();
    procedure TestForOfOverCollections();
    procedure TestForOfDestructuring();
    procedure TestClassBasics();
    procedure TestClassInheritance();
    procedure TestClassSuper();
    procedure TestClassMemberEnumerability();
    procedure TestTaggedTemplates();
    procedure TestGeneratorBasics();
    procedure TestGeneratorSuspension();
    procedure TestGeneratorIteration();
    procedure TestYieldStar();
    procedure TestFunctionMetadata();
    procedure TestFunctionConstructor();
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

procedure TFloriaJSEngineTest.TestBytecodeVMBackendExecution();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('var a = 20, b = 22; a + b;');
    AssertTrue('Execute arithmetic success', res.Success);
    AssertEquals('Execute arithmetic result', 42.0, res.NumberValue, 0.0001);

    res := engine.Execute('function fib(n) { if (n <= 1) return n; return fib(n - 1) + fib(n - 2); } fib(8);');
    AssertTrue('VM backend recursive fib success', res.Success);
    AssertEquals('VM backend fib(8) == 21', 21.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSEngineTest.TestContextResetLifecycle();
var
  engine: TFloriaJSEngine;
  ctx: TFloriaJSContext;
  res: TFloriaJSResult;
  i, initialObjCount: Integer;
begin
  engine := TFloriaJSEngine.Create();
  try
    ctx := engine.DefaultContext;

    // 1. Before reset
    res := ctx.Evaluate('(1.5).toString() === "1.5";');
    AssertTrue('Pre-reset (1.5).toString() succeeds', res.Success);
    AssertTrue('Pre-reset (1.5).toString() is true', res.BooleanValue);

    initialObjCount := ctx.Heap.GetObjectCount();

    // 2. Perform Reset
    ctx.Reset();

    // 3. After reset: number prototype methods must still work (P0-01)
    res := ctx.Evaluate('(1.5).toString() === "1.5";');
    AssertTrue('Post-reset (1.5).toString() succeeds', res.Success);
    AssertTrue('Post-reset (1.5).toString() is true', res.BooleanValue);

    // 4. After reset: catchable const assignment must not fail at host level (P0-01)
    res := ctx.Evaluate('let caughtName = ""; try { const c = 1; c = 2; } catch (e) { caughtName = e.name; } caughtName === "TypeError";');
    AssertTrue('Post-reset catchable const error succeeds', res.Success);
    AssertTrue('Post-reset catchable const error caught TypeError', res.BooleanValue);

    // 5. Repeated Reset stability
    for i := 1 to 10 do
    begin
      ctx.Evaluate('const tmp = { a: 1 }; (2.5).toString();');
      ctx.Reset();
    end;
    AssertTrue('Repeated reset keeps stable heap object baseline', ctx.Heap.GetObjectCount() <= initialObjCount + 5);
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

procedure TFloriaJSValueTest.TestArrayHolePresence();
var
  arr: TFloriaJSArray;
begin
  arr := TFloriaJSArray.Create();
  try
    arr.Push(JSMakeUndefined());
    AssertTrue('Explicit undefined is a real element', arr.HasElement(0));
    AssertEquals('Explicit undefined counts toward length', 1, arr.Length());

    arr.PushHole();
    AssertEquals('A hole extends the length', 2, arr.Length());
    AssertFalse('A hole is not a present element', arr.HasElement(1));
    AssertTrue('A hole reads as undefined', arr.GetElement(1).IsUndefined());

    arr.SetElement(3, JSMakeNumber(7));
    AssertEquals('Assigning past the end extends the length', 4, arr.Length());
    AssertFalse('The skipped slot is a hole', arr.HasElement(2));
    AssertTrue('The assigned slot is present', arr.HasElement(3));

    arr.MarkHole(3);
    AssertFalse('MarkHole removes the element', arr.HasElement(3));
    AssertTrue('MarkHole leaves undefined behind', arr.GetElement(3).IsUndefined());
    AssertEquals('MarkHole keeps the length', 4, arr.Length());

    arr.SetLengthTo(6);
    AssertEquals('SetLengthTo grows the length', 6, arr.Length());
    AssertFalse('A grown slot is a hole', arr.HasElement(5));

    arr.SetLengthTo(1);
    AssertEquals('SetLengthTo truncates the length', 1, arr.Length());
    AssertTrue('Truncation keeps the surviving element', arr.HasElement(0));

    AssertTrue('Deleting a missing index succeeds', arr.DeleteElement(9));
    arr.DeleteElement(0);
    AssertFalse('DeleteElement turns the slot into a hole', arr.HasElement(0));
    AssertEquals('DeleteElement keeps the length', 1, arr.Length());
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

{ TFloriaJSRuntimeTest }

procedure TFloriaJSRuntimeTest.TestArithmeticAndLogicalEval();
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

procedure TFloriaJSRuntimeTest.TestVariableScopeAndShadowing();
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

procedure TFloriaJSRuntimeTest.TestConditionalsAndLoops();
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

procedure TFloriaJSRuntimeTest.TestWhileWithBreakAndContinue();
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

procedure TFloriaJSRuntimeTest.TestUserFunctionAndRecursion();
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

procedure TFloriaJSRuntimeTest.TestClosures();
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

procedure TFloriaJSRuntimeTest.TestObjectAndArrayManipulation();
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

procedure TFloriaJSRuntimeTest.TestMathBuiltin();
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

procedure TFloriaJSRuntimeTest.TestPascalHostCallback();
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

procedure TFloriaJSRuntimeTest.TestConsoleCapture();
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

procedure TFloriaJSRuntimeTest.TestCommaOperatorAndLabeledBreak();
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

    { Classic for with let }
    res := engine.Execute(
      'var s = 0;' + LineEnding +
      'for (let i = 0; i < 2; i++) { s = s + 1; }' + LineEnding +
      's;'
    );
    AssertTrue('For let success', res.Success);
    AssertEquals('For let runs correctly', 2.0, res.NumberValue, 0.0001);

    { Classic for with const fails on update }
    res := engine.Execute(
      'var s = 0;' + LineEnding +
      'for (const i = 0; i < 2; i++) { s = s + 1; }' + LineEnding +
      's;'
    );
    AssertFalse('For const fails on update', res.Success);

    { Math.imul and Math.clz32 }
    res := engine.Execute('Math.imul(2, 4);');
    AssertTrue('Math.imul success', res.Success);
    AssertEquals('Math.imul(2, 4) = 8', 8.0, res.NumberValue, 0.0001);

    res := engine.Execute('Math.clz32(1);');
    AssertTrue('Math.clz32 success', res.Success);
    AssertEquals('Math.clz32(1) = 31', 31.0, res.NumberValue, 0.0001);

    { Empty statements are accepted and keep the completion value }
    res := engine.Execute(';;; 1;');
    AssertTrue('Empty statement success', res.Success);
    AssertEquals('Empty statements do not change the result', 1.0, res.NumberValue, 0.0001);

    res := engine.Execute('function f() { return 1; }; f();');
    AssertTrue('Semicolon after function declaration success', res.Success);
    AssertEquals('Semicolon after function declaration is accepted', 1.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSRuntimeTest.TestArrowFunctions();
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

    { 12. Async functions return a promise and await resolves it }
    res := engine.Execute('async function f() { return 1; } typeof f();');
    AssertTrue('Async function result success', res.Success);
    AssertEquals('Async function returns an object', 'object', res.StringValue);

    res := engine.Execute(
      'var r = 0;' + LineEnding +
      'async function f() { return 42; }' + LineEnding +
      '(async function () { r = await f(); })();' + LineEnding +
      'r;'
    );
    AssertTrue('Async await success', res.Success);
    AssertEquals('Await resolves the async result', 42.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSRuntimeTest.TestStandardGlobalsAndArguments();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    { Number static methods }
    res := engine.Execute('Number.isNaN(NaN);');
    AssertTrue('Number.isNaN(NaN)', res.BooleanValue);

    res := engine.Execute('Number.isNaN("NaN");');
    AssertFalse('Number.isNaN("NaN") is false', res.BooleanValue);

    res := engine.Execute('Number.isNaN(42);');
    AssertFalse('Number.isNaN(42) is false', res.BooleanValue);

    res := engine.Execute('Number.isFinite(42);');
    AssertTrue('Number.isFinite(42)', res.BooleanValue);

    res := engine.Execute('Number.isFinite(Infinity);');
    AssertFalse('Number.isFinite(Infinity) is false', res.BooleanValue);

    res := engine.Execute('Number.isFinite("42");');
    AssertFalse('Number.isFinite("42") is false', res.BooleanValue);

    res := engine.Execute('Number.isInteger(42);');
    AssertTrue('Number.isInteger(42)', res.BooleanValue);

    res := engine.Execute('Number.isInteger(42.5);');
    AssertFalse('Number.isInteger(42.5) is false', res.BooleanValue);

    res := engine.Execute('Number.parseInt("101", 2);');
    AssertEquals('Number.parseInt binary', 5.0, res.NumberValue, 0.0001);

    res := engine.Execute('Number.parseFloat("3.14px");');
    AssertEquals('Number.parseFloat prefix', 3.14, res.NumberValue, 0.0001);

    { Number constants }
    res := engine.Execute('Number.MAX_SAFE_INTEGER === 9007199254740991;');
    AssertTrue('Number.MAX_SAFE_INTEGER', res.BooleanValue);

    { globalThis self-reference and globals access }
    res := engine.Execute('globalThis.globalThis === globalThis;');
    AssertTrue('globalThis.globalThis === globalThis', res.BooleanValue);

    { String.prototype exposes the shared primitive-string methods }
    res := engine.Execute('String.prototype.charAt === "".charAt;');
    AssertTrue('String.prototype shares the string methods', res.BooleanValue);

    res := engine.Execute('globalThis.Math.abs(-42);');
    AssertEquals('globalThis.Math.abs(-42) = 42', 42.0, res.NumberValue, 0.0001);

    { arguments object inside normal function }
    res := engine.Execute(
      'function countArgs() {' + LineEnding +
      '  return arguments.length;' + LineEnding +
      '}' + LineEnding +
      'countArgs(10, 20, 30);'
    );
    AssertTrue('arguments.length success', res.Success);
    AssertEquals('arguments.length = 3', 3.0, res.NumberValue, 0.0001);

    res := engine.Execute(
      'function firstArg() {' + LineEnding +
      '  return arguments[0] + arguments[1];' + LineEnding +
      '}' + LineEnding +
      'firstArg("hello ", "world");'
    );
    AssertTrue('arguments indexing success', res.Success);
    AssertEquals('arguments indexed sum', 'hello world', res.StringValue);

    { Arrow function captures outer arguments }
    res := engine.Execute(
      'function outer() {' + LineEnding +
      '  var arrow = () => arguments[0];' + LineEnding +
      '  return arrow();' + LineEnding +
      '}' + LineEnding +
      'outer(99);'
    );
    AssertTrue('arrow uses outer arguments', res.Success);
    AssertEquals('arrow arguments[0] = 99', 99.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSRuntimeTest.TestObjectUtilities();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    { Object.keys }
    res := engine.Execute('var obj = { a: 1, b: 2 }; Object.keys(obj).join(",");');
    AssertTrue('Object.keys success', res.Success);
    AssertEquals('Object.keys = a,b', 'a,b', res.StringValue);

    { Object.values }
    res := engine.Execute('var obj = { a: 10, b: 20 }; Object.values(obj).join(",");');
    AssertTrue('Object.values success', res.Success);
    AssertEquals('Object.values = 10,20', '10,20', res.StringValue);

    { Object.entries }
    res := engine.Execute('var obj = { a: 1 }; Object.entries(obj)[0].join(":");');
    AssertTrue('Object.entries success', res.Success);
    AssertEquals('Object.entries = a:1', 'a:1', res.StringValue);

    { Object.assign }
    res := engine.Execute('var target = { a: 1 }; Object.assign(target, { b: 2 }, { c: 3 }); target.a + target.b + target.c;');
    AssertTrue('Object.assign success', res.Success);
    AssertEquals('Object.assign combined sum', 6.0, res.NumberValue, 0.0001);

    { Object.create with prototype inheritance }
    res := engine.Execute(
      'var proto = { greet: "hi" };' + LineEnding +
      'var child = Object.create(proto);' + LineEnding +
      'child.greet;'
    );
    AssertTrue('Object.create prototype inheritance success', res.Success);
    AssertEquals('child.greet = hi', 'hi', res.StringValue);

    { Object.create(null) has no prototype }
    res := engine.Execute(
      'var bare = Object.create(null);' + LineEnding +
      'Object.getPrototypeOf(bare) === null;'
    );
    AssertTrue('Object.create(null) success', res.Success);
    AssertTrue('bare prototype is null', res.BooleanValue);

    { Object.getPrototypeOf }
    res := engine.Execute(
      'var proto = { x: 1 };' + LineEnding +
      'var child = Object.create(proto);' + LineEnding +
      'Object.getPrototypeOf(child) === proto;'
    );
    AssertTrue('Object.getPrototypeOf match success', res.Success);
    AssertTrue('getPrototypeOf matches proto', res.BooleanValue);

    { hasOwnProperty }
    res := engine.Execute(
      'var proto = { inherited: true };' + LineEnding +
      'var obj = Object.create(proto);' + LineEnding +
      'obj.own = true;' + LineEnding +
      'obj.hasOwnProperty("own") && !obj.hasOwnProperty("inherited") && !obj.hasOwnProperty("toString");'
    );
    AssertTrue('hasOwnProperty test success', res.Success);
    AssertTrue('hasOwnProperty checks own only', res.BooleanValue);

    { Object.prototype.toString }
    res := engine.Execute('({}).toString();');
    AssertTrue('({}).toString() success', res.Success);
    AssertEquals('({}).toString()', '[object Object]', res.StringValue);

    res := engine.Execute('[1, 2].toString();');
    AssertTrue('[1, 2].toString() success', res.Success);
    AssertEquals('[1, 2].toString()', '1,2', res.StringValue);

    { Function.prototype.toString }
    res := engine.Execute('function f() {} f.toString();');
    AssertTrue('f.toString() success', res.Success);
    AssertEquals('f.toString()', 'function f() { [native code] }', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSRuntimeTest.TestJSONSupport();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    { 1. JSON.stringify primitives }
    res := engine.Execute('JSON.stringify(42);');
    AssertTrue('JSON.stringify number success', res.Success);
    AssertEquals('JSON.stringify(42)', '42', res.StringValue);

    res := engine.Execute('JSON.stringify("hello \"world\"");');
    AssertTrue('JSON.stringify string success', res.Success);
    AssertEquals('JSON.stringify string', '"hello \"world\""', res.StringValue);

    res := engine.Execute('JSON.stringify(true);');
    AssertTrue('JSON.stringify boolean success', res.Success);
    AssertEquals('JSON.stringify(true)', 'true', res.StringValue);

    res := engine.Execute('JSON.stringify(null);');
    AssertTrue('JSON.stringify null success', res.Success);
    AssertEquals('JSON.stringify(null)', 'null', res.StringValue);

    { 2. Top-level undefined produces undefined }
    res := engine.Execute('typeof JSON.stringify(undefined);');
    AssertTrue('JSON.stringify(undefined) typeof success', res.Success);
    AssertEquals('typeof JSON.stringify(undefined)', 'undefined', res.StringValue);

    { 3. JSON.stringify arrays and objects }
    res := engine.Execute('JSON.stringify([1, "a", true, null]);');
    AssertTrue('JSON.stringify array success', res.Success);
    AssertEquals('JSON.stringify array', '[1,"a",true,null]', res.StringValue);

    res := engine.Execute('JSON.stringify({ a: 1, b: "x" });');
    AssertTrue('JSON.stringify object success', res.Success);
    AssertEquals('JSON.stringify object', '{"a":1,"b":"x"}', res.StringValue);

    { 4. Omission of undefined / function in object, conversion to null in array }
    res := engine.Execute('JSON.stringify({ a: 1, u: undefined, f: function() {} });');
    AssertTrue('JSON.stringify omits undefined/func in obj', res.Success);
    AssertEquals('omits undefined/func', '{"a":1}', res.StringValue);

    res := engine.Execute('JSON.stringify([1, undefined, function() {}, 4]);');
    AssertTrue('JSON.stringify nulls undefined/func in arr', res.Success);
    AssertEquals('nulls undefined/func in arr', '[1,null,null,4]', res.StringValue);

    { 5. Indentation with space }
    res := engine.Execute('JSON.stringify({ a: 1 }, null, 2);');
    AssertTrue('JSON.stringify with indent success', res.Success);
    AssertTrue('contains newline and spaces', (Pos(#10, res.StringValue) > 0) and (Pos('  "a": 1', res.StringValue) > 0));

    { 6. Circular structure throws TypeError }
    res := engine.Execute(
      'var circular = { x: 1 };' + LineEnding +
      'circular.self = circular;' + LineEnding +
      'var caught = false;' + LineEnding +
      'try {' + LineEnding +
      '  JSON.stringify(circular);' + LineEnding +
      '} catch (e) {' + LineEnding +
      '  caught = (e.name === "TypeError");' + LineEnding +
      '}' + LineEnding +
      'caught;'
    );
    AssertTrue('JSON.stringify circular detection success', res.Success);
    AssertTrue('JSON.stringify throws TypeError on circular reference', res.BooleanValue);

    { 7. JSON.parse primitives, arrays, nested objects }
    res := engine.Execute('JSON.parse("42");');
    AssertTrue('JSON.parse number success', res.Success);
    AssertEquals('parsed number = 42', 42.0, res.NumberValue, 0.0001);

    res := engine.Execute('JSON.parse("\"hello\\nworld\"");');
    AssertTrue('JSON.parse string with escape success', res.Success);
    AssertEquals('parsed string with newline', 'hello'#10'world', res.StringValue);

    res := engine.Execute('var data = JSON.parse("{\"nums\":[10,20],\"flag\":true,\"nil\":null}"); data.nums[1] + (data.flag ? 1 : 0);');
    AssertTrue('JSON.parse nested data success', res.Success);
    AssertEquals('parsed nested data evaluated', 21.0, res.NumberValue, 0.0001);

    { 8. JSON.parse throws SyntaxError on invalid JSON }
    res := engine.Execute(
      'var caught = false;' + LineEnding +
      'try {' + LineEnding +
      '  JSON.parse("[1, 2, ]");' + LineEnding +
      '} catch (e) {' + LineEnding +
      '  caught = (e.name === "SyntaxError");' + LineEnding +
      '}' + LineEnding +
      'caught;'
    );
    AssertTrue('JSON.parse invalid syntax detection success', res.Success);
    AssertTrue('JSON.parse throws SyntaxError on trailing comma', res.BooleanValue);

    { 9. Round-trip serialization/parsing }
    res := engine.Execute(
      'var original = { title: "FloriaJS", version: 1, active: true };' + LineEnding +
      'var roundTrip = JSON.parse(JSON.stringify(original));' + LineEnding +
      'roundTrip.title === original.title && roundTrip.version === original.version && roundTrip.active === original.active;'
    );
    AssertTrue('JSON round trip success', res.Success);
    AssertTrue('JSON round trip equality', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSRuntimeTest.TestTemplateLiteralInterpolation();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    { 1. Plain template string without interpolation }
    res := engine.Execute('`hello world`;');
    AssertTrue('Plain template success', res.Success);
    AssertEquals('Plain template value', 'hello world', res.StringValue);

    { 2. Single embedded expression }
    res := engine.Execute('var n = 41; `v=${n + 1}`;');
    AssertTrue('Single interp success', res.Success);
    AssertEquals('v=${n + 1}', 'v=42', res.StringValue);

    { 3. Multiple embedded expressions }
    res := engine.Execute('var a = 2, b = 3; `${a} + ${b} = ${a + b}`;');
    AssertTrue('Multi interp success', res.Success);
    AssertEquals('Multi interp value', '2 + 3 = 5', res.StringValue);

    { 4. Leading / trailing interpolations }
    res := engine.Execute('var x = 100; `${x}`;');
    AssertTrue('Standalone interp success', res.Success);
    AssertEquals('Standalone interp value', '100', res.StringValue);

    { 5. Embedded expression with object literal }
    res := engine.Execute('`val: ${ { x: 99 }.x }`;');
    AssertTrue('Interp with object literal success', res.Success);
    AssertEquals('Interp with object literal', 'val: 99', res.StringValue);

    { 6. Nested template literals }
    res := engine.Execute('`outer ${ `inner ${ 10 * 2 }` }`;');
    AssertTrue('Nested template success', res.Success);
    AssertEquals('Nested template value', 'outer inner 20', res.StringValue);

    { 7. Method and array call inside template }
    res := engine.Execute('`count: ${[1, 2, 3].length}`;');
    AssertTrue('Template with property call success', res.Success);
    AssertEquals('Template property value', 'count: 3', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSRuntimeTest.TestObjectAndArrayLiteralCompletion();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    { 1. Object shorthand }
    res := engine.Execute('var x = 10, y = 20; var o = { x, y }; o.x + o.y;');
    AssertTrue('Object shorthand success', res.Success);
    AssertEquals('Object shorthand sum', 30.0, res.NumberValue, 0.0001);

    { 2. Computed property keys }
    res := engine.Execute('var k = "foo"; var o = { [k]: 42, [k + "Bar"]: 100 }; o.foo + o.fooBar;');
    AssertTrue('Computed keys success', res.Success);
    AssertEquals('Computed keys sum', 142.0, res.NumberValue, 0.0001);

    { 3. Object spread }
    res := engine.Execute('var a = { x: 1, y: 2 }; var b = { ...a, z: 3, x: 99 }; b.x + b.y + b.z;');
    AssertTrue('Object spread success', res.Success);
    AssertEquals('Object spread sum', 104.0, res.NumberValue, 0.0001);

    { 4. Array spread }
    res := engine.Execute('var a = [2, 3]; var b = [1, ...a, 4]; b.join(",");');
    AssertTrue('Array spread success', res.Success);
    AssertEquals('Array spread joined', '1,2,3,4', res.StringValue);

    { 5. Array holes }
    res := engine.Execute('var a = [1, , 3]; a.length;');
    AssertTrue('Array holes length success', res.Success);
    AssertEquals('Array holes length = 3', 3.0, res.NumberValue, 0.0001);

    res := engine.Execute('var a = [1, , 3]; a[1] === undefined;');
    AssertTrue('Array hole index 1 is undefined', res.BooleanValue);

    { 6. Object methods }
    res := engine.Execute('var calc = { add(a, b) { return a + b; }, mult(a, b) { return a * b; } }; calc.mult(calc.add(2, 3), 4);');
    AssertTrue('Object methods success', res.Success);
    AssertEquals('Object methods result', 20.0, res.NumberValue, 0.0001);

    { 7. Object getters and setters }
    res := engine.Execute(
      'var o = {' + LineEnding +
      '  _val: 0,' + LineEnding +
      '  get val() { return this._val; },' + LineEnding +
      '  set val(v) { this._val = v * 2; }' + LineEnding +
      '};' + LineEnding +
      'o.val = 21;' + LineEnding +
      'o.val;'
    );
    AssertTrue('Getters/setters success', res.Success);
    AssertEquals('Getter returned modified value', 42.0, res.NumberValue, 0.0001);

    { 8. Spread call arguments }
    res := engine.Execute('function sum(a, b, c) { return a + b + c; } sum(...[10, 20, 30]);');
    AssertTrue('Spread call arguments success', res.Success);
    AssertEquals('Spread call sum', 60.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSRuntimeTest.TestIterationStatements();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    { 1. for..of over array }
    res := engine.Execute(
      'var sum = 0;' + LineEnding +
      'for (const x of [10, 20, 30]) {' + LineEnding +
      '  sum += x;' + LineEnding +
      '}' + LineEnding +
      'sum;'
    );
    AssertTrue('for..of array success', res.Success);
    AssertEquals('for..of array sum = 60', 60.0, res.NumberValue, 0.0001);

    { 2. for..of over string }
    res := engine.Execute(
      'var rev = "";' + LineEnding +
      'for (var ch of "abc") {' + LineEnding +
      '  rev = ch + rev;' + LineEnding +
      '}' + LineEnding +
      'rev;'
    );
    AssertTrue('for..of string success', res.Success);
    AssertEquals('for..of string reversed', 'cba', res.StringValue);

    { 3. for..in over object own keys }
    res := engine.Execute(
      'var obj = { a: 1, b: 2 };' + LineEnding +
      'var keys = [];' + LineEnding +
      'for (const k in obj) {' + LineEnding +
      '  keys.push(k);' + LineEnding +
      '}' + LineEnding +
      'keys.sort().join(",");'
    );
    AssertTrue('for..in object success', res.Success);
    AssertEquals('for..in keys = a,b', 'a,b', res.StringValue);

    { 4. for..in traverses prototype chain }
    res := engine.Execute(
      'var proto = { inherited: 99 };' + LineEnding +
      'var child = Object.create(proto);' + LineEnding +
      'child.own = 1;' + LineEnding +
      'var keys = [];' + LineEnding +
      'for (var k in child) {' + LineEnding +
      '  keys.push(k);' + LineEnding +
      '}' + LineEnding +
      'keys.sort().join(",");'
    );
    AssertTrue('for..in prototype chain success', res.Success);
    AssertEquals('for..in includes inherited keys', 'inherited,own', res.StringValue);

    { 5. break and continue in for..of }
    res := engine.Execute(
      'var sum = 0;' + LineEnding +
      'for (const x of [1, 2, 3, 4, 5]) {' + LineEnding +
      '  if (x === 2) continue;' + LineEnding +
      '  if (x === 4) break;' + LineEnding +
      '  sum += x;' + LineEnding +
      '}' + LineEnding +
      'sum;'
    );
    AssertTrue('for..of break/continue success', res.Success);
    AssertEquals('for..of filtered sum = 4 (1 + 3)', 4.0, res.NumberValue, 0.0001);

    { 6. Per-iteration environment captured by closures in for..of }
    res := engine.Execute(
      'var funcs = [];' + LineEnding +
      'for (const x of [10, 20, 30]) {' + LineEnding +
      '  funcs.push(() => x);' + LineEnding +
      '}' + LineEnding +
      'funcs[0]() + funcs[1]() + funcs[2]();'
    );
    AssertTrue('for..of closure capture success', res.Success);
    AssertEquals('closures capture separate iteration bindings', 60.0, res.NumberValue, 0.0001);

    { 7. Labeled continue from a nested for..of }
    res := engine.Execute(
      'var sum = 0;' + LineEnding +
      'outer: for (const x of [1, 2, 3]) {' + LineEnding +
      '  for (const y of [1, 2, 3]) {' + LineEnding +
      '    if (y === 2) continue outer;' + LineEnding +
      '    sum += 1;' + LineEnding +
      '  }' + LineEnding +
      '}' + LineEnding +
      'sum;'
    );
    AssertTrue('for..of labeled continue success', res.Success);
    AssertEquals('labeled continue skips the rest of the outer iteration', 3.0, res.NumberValue, 0.0001);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSRuntimeTest.TestParameterFormsAndDestructuring();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    { 1. Default parameters with earlier parameter reference }
    res := engine.Execute(
      'function f(a = 3, b = a * 2) { return a + b; }' + LineEnding +
      '[f(), f(5), f(2, 3)].join(",");'
    );
    AssertTrue('Default parameters success', res.Success);
    AssertEquals('Default parameter evaluation', '9,15,5', res.StringValue);

    { 2. Default parameter triggered by undefined }
    res := engine.Execute('function f(a = 10) { return a; } f(undefined);');
    AssertTrue('Default param with undefined success', res.Success);
    AssertEquals('Default parameter triggered by undefined', 10.0, res.NumberValue, 0.0001);

    { 3. Rest parameters in function declaration }
    res := engine.Execute(
      'function sum(first, ...rest) {' + LineEnding +
      '  return first + rest.reduce((a, b) => a + b, 0);' + LineEnding +
      '}' + LineEnding +
      'sum(10, 1, 2, 3);'
    );
    AssertTrue('Rest parameters success', res.Success);
    AssertEquals('Rest parameter sum', 16.0, res.NumberValue, 0.0001);

    res := engine.Execute('function f(...items) { return items.length; } f();');
    AssertTrue('Empty rest param success', res.Success);
    AssertEquals('Empty rest param produces empty array', 0.0, res.NumberValue, 0.0001);

    { 4. Object destructuring in variable declaration }
    res := engine.Execute('var { a, b } = { a: 1, b: 2 }; a + b;');
    AssertTrue('Object destructuring success', res.Success);
    AssertEquals('Object destructuring sum', 3.0, res.NumberValue, 0.0001);

    { 5. Object rename and default value }
    res := engine.Execute('var { a: x = 10, b: y = 20 } = { a: 5 }; x + y;');
    AssertTrue('Object rename and default success', res.Success);
    AssertEquals('Object rename and default sum', 25.0, res.NumberValue, 0.0001);

    { 6. Object rest property }
    res := engine.Execute('var { a, ...rest } = { a: 1, b: 2, c: 3 }; [a, rest.b, rest.c].join(",");');
    AssertTrue('Object rest success', res.Success);
    AssertEquals('Object rest extraction', '1,2,3', res.StringValue);

    { 7. Array destructuring in variable declaration }
    res := engine.Execute('var [a, b, c] = [10, 20, 30]; a + b + c;');
    AssertTrue('Array destructuring success', res.Success);
    AssertEquals('Array destructuring sum', 60.0, res.NumberValue, 0.0001);

    { 8. Array destructuring with default and elision / hole }
    res := engine.Execute('var [a = 1, , c = 3] = [undefined, 99]; a + c;');
    AssertTrue('Array default and hole success', res.Success);
    AssertEquals('Array default and hole sum', 4.0, res.NumberValue, 0.0001);

    { 9. Array rest element }
    res := engine.Execute('var [head, ...tail] = [1, 2, 3]; head + ":" + tail.join(",");');
    AssertTrue('Array rest element success', res.Success);
    AssertEquals('Array rest elements', '1:2,3', res.StringValue);

    { 10. Nested destructuring }
    res := engine.Execute('var { x: [y, { z }] } = { x: [10, { z: 20 }] }; y + z;');
    AssertTrue('Nested destructuring success', res.Success);
    AssertEquals('Nested destructuring sum', 30.0, res.NumberValue, 0.0001);

    { 11. Destructuring in function parameters }
    res := engine.Execute(
      'function add({ a, b = 0 }) { return a + b; }' + LineEnding +
      'add({ a: 7, b: 3 }) + add({ a: 5 });'
    );
    AssertTrue('Destructuring in function parameter success', res.Success);
    AssertEquals('Destructuring parameter sum', 15.0, res.NumberValue, 0.0001);

    res := engine.Execute('function pair([a, b]) { return a * b; } pair([6, 7]);');
    AssertTrue('Array destructuring in parameter success', res.Success);
    AssertEquals('Array destructuring parameter product', 42.0, res.NumberValue, 0.0001);

    { 12. Arrow function parameter forms }
    res := engine.Execute(
      'const f1 = ({ a, b }) => a + b;' + LineEnding +
      'const f2 = ([head, ...tail]) => head + tail.length;' + LineEnding +
      'const f3 = (a = 5, b = 10) => a * b;' + LineEnding +
      'const f4 = (...args) => args.join("-");' + LineEnding +
      '[f1({ a: 10, b: 20 }), f2([100, 2, 3, 4]), f3(), f4("x", "y", "z")].join(";");'
    );
    AssertTrue('Arrow function parameter forms success', res.Success);
    AssertEquals('Arrow function parameter forms values', '30;103;50;x-y-z', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSRuntimeTest.TestErrorHandlingAndTypeErrors();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    { 1. Error constructors and properties }
    res := engine.Execute(
      'var e1 = new Error("msg1");' + LineEnding +
      'var e2 = new TypeError("msg2");' + LineEnding +
      'var e3 = new RangeError("msg3");' + LineEnding +
      'var e4 = new ReferenceError("msg4");' + LineEnding +
      'var e5 = new SyntaxError("msg5");' + LineEnding +
      '[e1.name + ":" + e1.message, e2.name + ":" + e2.message, e3.name + ":" + e3.message, e4.name + ":" + e4.message, e5.name + ":" + e5.message].join(";");'
    );
    AssertTrue('Error constructors success', res.Success);
    AssertEquals('Error constructors names and messages', 'Error:msg1;TypeError:msg2;RangeError:msg3;ReferenceError:msg4;SyntaxError:msg5', res.StringValue);

    { 2. Error toString() behaviour }
    res := engine.Execute(
      'var e1 = new Error("err");' + LineEnding +
      'var e2 = new TypeError("type_err");' + LineEnding +
      'var e3 = new Error();' + LineEnding +
      '[e1.toString(), e2.toString(), e3.toString(), Error.prototype.toString()].join(";");'
    );
    AssertTrue('Error toString success', res.Success);
    AssertEquals('Error toString matches standard formatting', 'Error: err;TypeError: type_err;Error;Error', res.StringValue);

    { 3. Error inheritance and instanceof }
    res := engine.Execute(
      'var te = new TypeError("bad");' + LineEnding +
      'var er = new Error("normal");' + LineEnding +
      '[te instanceof TypeError, te instanceof Error, te instanceof Object, er instanceof TypeError, er instanceof Error].join(",");'
    );
    AssertTrue('Error instanceof success', res.Success);
    AssertEquals('Error inheritance hierarchy', 'true,true,true,false,true', res.StringValue);

    { 4. Global constructors published on globalThis }
    res := engine.Execute(
      '[globalThis.Error === Error, globalThis.TypeError === TypeError, globalThis.RangeError === RangeError, globalThis.ReferenceError === ReferenceError, globalThis.SyntaxError === SyntaxError].join(",");'
    );
    AssertTrue('Global error constructors success', res.Success);
    AssertEquals('Error constructors available on globalThis', 'true,true,true,true,true', res.StringValue);

    { 5. Calling non-function throws TypeError }
    res := engine.Execute('var o = {}; o.nope();');
    AssertFalse('Calling missing method throws error', res.Success);
    AssertTrue('Calling missing method reports TypeError', Pos('TypeError', res.ErrorMessage) > 0);

    res := engine.Execute('(42)();');
    AssertFalse('Calling number throws error', res.Success);
    AssertTrue('Calling number reports TypeError', Pos('TypeError', res.ErrorMessage) > 0);

    res := engine.Execute('try { var o = {}; o.nope(); } catch (e) { [e instanceof TypeError, e.name].join(","); }');
    AssertTrue('Catch calling non-function success', res.Success);
    AssertEquals('Caught TypeError object for non-function call', 'true,TypeError', res.StringValue);

    { 6. Reading property of null / undefined throws TypeError }
    res := engine.Execute('null.foo;');
    AssertFalse('Reading property on null throws error', res.Success);
    AssertTrue('Reading property on null reports TypeError', Pos('TypeError', res.ErrorMessage) > 0);

    res := engine.Execute('undefined["bar"];');
    AssertFalse('Reading property on undefined throws error', res.Success);
    AssertTrue('Reading property on undefined reports TypeError', Pos('TypeError', res.ErrorMessage) > 0);

    res := engine.Execute('try { null.foo; } catch (e) { [e instanceof TypeError, e.name].join(","); }');
    AssertTrue('Catch null property access success', res.Success);
    AssertEquals('Caught TypeError for null property access', 'true,TypeError', res.StringValue);

    { 7. Optional chaining suppresses TypeError on null / undefined }
    res := engine.Execute(
      'var o = null;' + LineEnding +
      'var u = undefined;' + LineEnding +
      '[o?.foo === undefined, u?.["bar"] === undefined, o?.() === undefined, u?.() === undefined].join(",");'
    );
    AssertTrue('Optional chaining on null/undefined success', res.Success);
    AssertEquals('Optional chaining returns undefined without throwing', 'true,true,true,true', res.StringValue);

    { 8. Setting property on null / undefined throws TypeError }
    res := engine.Execute('null.foo = 1;');
    AssertFalse('Setting property on null throws error', res.Success);
    AssertTrue('Setting property on null reports TypeError', Pos('TypeError', res.ErrorMessage) > 0);

    res := engine.Execute('undefined["bar"] = 2;');
    AssertFalse('Setting property on undefined throws error', res.Success);
    AssertTrue('Setting property on undefined reports TypeError', Pos('TypeError', res.ErrorMessage) > 0);

    res := engine.Execute('try { null.foo = 10; } catch (e) { [e instanceof TypeError, e.name].join(","); }');
    AssertTrue('Catch setting property on null success', res.Success);
    AssertEquals('Caught TypeError for setting property on null', 'true,TypeError', res.StringValue);

    { 9. "in" operator throws TypeError on non-object }
    res := engine.Execute('"a" in null;');
    AssertFalse('"in" on null throws error', res.Success);
    AssertTrue('"in" on null reports TypeError', Pos('TypeError', res.ErrorMessage) > 0);

    res := engine.Execute('try { "a" in 123; } catch (e) { [e instanceof TypeError, e.name].join(","); }');
    AssertTrue('Catch "in" on number success', res.Success);
    AssertEquals('Caught TypeError for "in" on non-object', 'true,TypeError', res.StringValue);

    { 10. "instanceof" operator throws TypeError on non-callable RHS }
    res := engine.Execute('({}) instanceof null;');
    AssertFalse('"instanceof" with null RHS throws error', res.Success);
    AssertTrue('"instanceof" with null RHS reports TypeError', Pos('TypeError', res.ErrorMessage) > 0);

    res := engine.Execute('try { ({}) instanceof ({}); } catch (e) { [e instanceof TypeError, e.name].join(","); }');
    AssertTrue('Catch "instanceof" on non-callable RHS success', res.Success);
    AssertEquals('Caught TypeError for non-callable instanceof RHS', 'true,TypeError', res.StringValue);

    { 11. Stack overflow throws RangeError }
    res := engine.Execute('function recurse() { return recurse(); } recurse();');
    AssertFalse('Deep recursion throws error', res.Success);
    AssertTrue('Deep recursion reports RangeError', Pos('RangeError', res.ErrorMessage) > 0);

    res := engine.Execute('try { function recurse() { return recurse(); } recurse(); } catch (e) { [e instanceof RangeError, e.name].join(","); }');
    AssertTrue('Catch deep recursion success', res.Success);
    AssertEquals('Caught RangeError for stack overflow', 'true,RangeError', res.StringValue);
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

    { A classic for-loop with a block-scoped binding creates a fresh
      per-iteration environment; it must release those environments when no
      closure captures them. }
    ctx.Evaluate('for (let j = 0; j < 5000; j++) { total = total + 1; }');

    AssertTrue('A classic for-let loop must not accumulate environments (' +
      IntToStr(baseline) + ' -> ' + IntToStr(ctx.Heap.GetEnvironmentCount) + ')',
      ctx.Heap.GetEnvironmentCount = baseline);
    AssertEquals('The for-let loop must still produce the correct result', '10000',
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
  vm: TFloriaJSVM;
  compiler: TFloriaJSCompiler;
  code: TFloriaJSBytecode;
  env: TFloriaJSEnvironment;
  args: array of TFloriaJSValue;
  val: TFloriaJSValue;
begin
  vm := TFloriaJSVM.Create(nil);
  compiler := TFloriaJSCompiler.Create();
  try
    env := TFloriaJSEnvironment.Create(nil);
    try
      decl := TFloriaJSFunctionDecl.Create('f', 1, 1);
      block := TFloriaJSBlockStmt.Create(1, 1);
      retStmt := TFloriaJSReturnStmt.Create(
        TFloriaJSLiteralExpr.CreateNumber(42, 1, 1), 1, 1);
      block.AddStatement(retStmt);
      decl.SetBody(block);

      code := compiler.CompileFunctionBody('f', nil, decl.Body);
      fn := TFloriaJSFunction.CreateBytecode('f', code, Pointer(env), False, False);
      code.Release();

      { The declaration is discarded, exactly as it is when the script that
        created it ends: the bytecode must stay alive for the closure. }
      decl.Free();

      val := vm.CallFunction(JSMakeFunction(fn), args, JSMakeUndefined());
      AssertEquals('The closure must still execute its body', '42',
        val.ToString());
    finally
      env.Free();
      fn.Free();
    end;
  finally
    compiler.Free();
    vm.Free();
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

    AssertEquals('Arrays must be instances of Array', 'true',
      ctx.Evaluate('[] instanceof Array;').StringValue);

    AssertEquals('Array.prototype must expose the shared methods', 'true',
      ctx.Evaluate('typeof Array.prototype.join === "function";').StringValue);

    AssertEquals('new Array(n) must create a sparse array of that length', '3',
      ctx.Evaluate('(new Array(3)).length;').StringValue);

    AssertEquals('Array(a, b) must collect its arguments', '2',
      ctx.Evaluate('Array(1, 2).length;').StringValue);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSArrayMethodsTest.TestArrayMethodsOverHoles();
var
  ctx: TFloriaJSContext;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    AssertEquals('new Array(n) must create holes, not elements', '0',
      ctx.Evaluate('Object.keys(new Array(3)).length;').StringValue);
    AssertEquals('new Array(n) keeps the requested length', '3',
      ctx.Evaluate('(new Array(3)).length;').StringValue);

    AssertEquals('forEach/map skip holes and map preserves them', 'true',
      ctx.Evaluate(
        'var a = [1, , 3];' +
        'var seen = "";' +
        'a.forEach(function (v, i) { seen += i; });' +
        'var mapped = a.map(function (v) { return v * 2; });' +
        'seen === "02" && mapped.length === 3 && Object.keys(mapped).join(",") === "0,2" && mapped[1] === undefined;'
      ).StringValue);

    AssertEquals('filter/reduce skip holes', 'true',
      ctx.Evaluate(
        'var a = [ , 1, , 3];' +
        'var filtered = a.filter(function (v) { return v > 0; });' +
        'var total = a.reduce(function (acc, v) { return acc + v; }, 0);' +
        'var noInit = a.reduce(function (acc, v) { return acc + v; });' +
        'filtered.join(",") === "1,3" && total === 4 && noInit === 4;'
      ).StringValue);

    AssertEquals('sort moves holes to the end', 'true',
      ctx.Evaluate(
        'var a = [3, , 1];' +
        'a.sort();' +
        'a.join(",") === "1,3," && Object.keys(a).join(",") === "0,1";'
      ).StringValue);

    AssertEquals('reverse keeps holes at the mirrored positions', 'true',
      ctx.Evaluate(
        'var a = [1, , 3];' +
        'a.reverse();' +
        'Object.keys(a).join(",") === "0,2" && a[1] === undefined && a[0] === 3;'
      ).StringValue);

    AssertEquals('slice/concat/splice preserve holes', 'true',
      ctx.Evaluate(
        'var a = [1, , 3];' +
        'var sliced = a.slice(0);' +
        'var concatenated = a.concat([4]);' +
        'var removed = a.splice(0, 3);' +
        'Object.keys(sliced).join(",") === "0,2" && ' +
        'Object.keys(concatenated).join(",") === "0,2,3" && ' +
        'Object.keys(removed).join(",") === "0,2";'
      ).StringValue);

    AssertEquals('indexOf skips holes while includes sees undefined', 'true',
      ctx.Evaluate(
        'var a = [1, , 3];' +
        'a.indexOf(undefined) === -1 && a.includes(undefined) && a.lastIndexOf(undefined) === -1;'
      ).StringValue);

    AssertEquals('join/JSON/string conversion render holes as empty or null', 'true',
      ctx.Evaluate(
        'var a = [1, , 3];' +
        'JSON.stringify(a) === "[1,null,3]" && String(a) === "1,,3" && a.join("-") === "1--3";'
      ).StringValue);

    AssertEquals('spread materialises holes as undefined elements', 'true',
      ctx.Evaluate(
        'var a = [1, , 3];' +
        'var spread = [...a];' +
        'Object.keys(spread).join(",") === "0,1,2" && spread[1] === undefined;'
      ).StringValue);

    AssertTrue('reduce over an empty array must throw',
      Pos('TypeError', ctx.Evaluate('[,].reduce(function (acc, v) { return acc + v; });').ErrorMessage) > 0);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSArrayMethodsTest.TestArrayLengthMutationDoesNotLeak();
var
  ctx: TFloriaJSContext;
  objectsBaseline, objectsWithElements, i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    ctx.Evaluate('var a = [1, 2, 3, 4];');
    ctx.Evaluate('0;');
    objectsBaseline := ctx.Heap.GetObjectCount;

    { Repeated growth and truncation must not accumulate objects. }
    for i := 1 to 200 do
      ctx.Evaluate('a.length = 5; a.length = 1; a.length = 0; a.length = 3; a.length = 1;');
    ctx.Evaluate('0;');

    AssertTrue('Length mutation must not accumulate objects (' +
      IntToStr(objectsBaseline) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount = objectsBaseline);

    { Truncation releases the elements the array owned. }
    ctx.Evaluate(
      'var boxed = [];' +
      'for (var i = 0; i < 10; i++) { boxed.push({ n: i }); }');
    ctx.Evaluate('0;');
    objectsWithElements := ctx.Heap.GetObjectCount;

    ctx.Evaluate('boxed.length = 0;');
    ctx.Evaluate('0;');
    AssertTrue('Truncating length must release the dropped elements (' +
      IntToStr(objectsWithElements) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount < objectsWithElements);
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

{ TFloriaJSVMTest }

procedure TFloriaJSVMTest.TestBasicBytecodeArithmetic();
var
  code: TFloriaJSBytecode;
  vm: TFloriaJSVM;
  res: TFloriaJSValue;
begin
  code := TFloriaJSBytecode.Create('arithmetic');
  vm := TFloriaJSVM.Create();
  try
    // (10 + 20) * 5 = 150
    code.Emit(opConst, code.AddNumberConstant(10.0));
    code.Emit(opConst, code.AddNumberConstant(20.0));
    code.Emit(opAdd);
    code.Emit(opConst, code.AddNumberConstant(5.0));
    code.Emit(opMul);
    code.Emit(opReturn);

    res := vm.Execute(code);
    AssertTrue('Arithmetic result is number', res.IsNumber());
    AssertEquals('Arithmetic calculation matches expected', 150.0, res.NumVal, 0.0001);

    // String concatenation: "hello " + "world"
    code.Free();
    code := TFloriaJSBytecode.Create('str_concat');
    code.Emit(opConst, code.AddStringConstant('hello '));
    code.Emit(opConst, code.AddStringConstant('world'));
    code.Emit(opAdd);
    code.Emit(opReturn);

    res := vm.Execute(code);
    AssertTrue('Concat result is string', res.IsString());
    AssertEquals('Concat value matches expected', 'hello world', res.StrVal);
  finally
    code.Free();
    vm.Free();
  end;
end;

procedure TFloriaJSVMTest.TestBytecodeLocalVariables();
var
  code: TFloriaJSBytecode;
  vm: TFloriaJSVM;
  res: TFloriaJSValue;
  aIdx, bIdx, cIdx: Integer;
begin
  code := TFloriaJSBytecode.Create('locals');
  vm := TFloriaJSVM.Create();
  try
    aIdx := code.AddLocal('a');
    bIdx := code.AddLocal('b');
    cIdx := code.AddLocal('c');

    // a = 42; b = 8; c = a - b; return c;
    code.Emit(opConst, code.AddNumberConstant(42.0));
    code.Emit(opSetLoc, aIdx);

    code.Emit(opConst, code.AddNumberConstant(8.0));
    code.Emit(opSetLoc, bIdx);

    code.Emit(opLoadLoc, aIdx);
    code.Emit(opLoadLoc, bIdx);
    code.Emit(opSub);
    code.Emit(opSetLoc, cIdx);

    code.Emit(opLoadLoc, cIdx);
    code.Emit(opReturn);

    res := vm.Execute(code);
    AssertTrue('Locals result is number', res.IsNumber());
    AssertEquals('Locals subtraction result', 34.0, res.NumVal, 0.0001);
  finally
    code.Free();
    vm.Free();
  end;
end;

procedure TFloriaJSVMTest.TestBytecodeControlFlowAndJumps();
var
  code: TFloriaJSBytecode;
  vm: TFloriaJSVM;
  res: TFloriaJSValue;
  iIdx: Integer;
  loopStart, jumpIfFalseIdx: Integer;
begin
  code := TFloriaJSBytecode.Create('loop');
  vm := TFloriaJSVM.Create();
  try
    iIdx := code.AddLocal('i');

    // i = 0;
    code.Emit(opZero);
    code.Emit(opSetLoc, iIdx);

    // while (i < 5) i = i + 1;
    loopStart := code.CurrentIP();
    code.Emit(opLoadLoc, iIdx);
    code.Emit(opConst, code.AddNumberConstant(5.0));
    code.Emit(opLt);
    jumpIfFalseIdx := code.Emit(opJumpIfFalse, 0);

    code.Emit(opLoadLoc, iIdx);
    code.Emit(opOne);
    code.Emit(opAdd);
    code.Emit(opSetLoc, iIdx);
    code.Emit(opJump, loopStart);

    code.PatchJump(jumpIfFalseIdx, code.CurrentIP());
    code.Emit(opLoadLoc, iIdx);
    code.Emit(opReturn);

    res := vm.Execute(code);
    AssertTrue('Loop counter result is number', res.IsNumber());
    AssertEquals('Loop counter reached 5', 5.0, res.NumVal, 0.0001);
  finally
    code.Free();
    vm.Free();
  end;
end;

procedure TFloriaJSVMTest.TestBytecodeFunctionsAndCalls();
var
  mainCode, subCode: TFloriaJSBytecode;
  vm: TFloriaJSVM;
  res: TFloriaJSValue;
  fnIdx: Integer;
begin
  mainCode := TFloriaJSBytecode.Create('main');
  subCode := TFloriaJSBytecode.Create('add');
  vm := TFloriaJSVM.Create();
  try
    // sub function add(x, y) { return x + y; }
    subCode.AddArgument('x');
    subCode.AddArgument('y');
    subCode.Emit(opLoadLoc, 0);
    subCode.Emit(opLoadLoc, 1);
    subCode.Emit(opAdd);
    subCode.Emit(opReturn);

    fnIdx := mainCode.AddSubFunction(subCode);
    mainCode.AddLocal('fn');

    // var fn = add; return fn(100, 200);
    mainCode.Emit(opClosure, fnIdx);
    mainCode.Emit(opSetLoc, 0);

    mainCode.Emit(opLoadLoc, 0);      // Callee
    mainCode.Emit(opUndefined);        // This
    mainCode.Emit(opConst, mainCode.AddNumberConstant(100.0));
    mainCode.Emit(opConst, mainCode.AddNumberConstant(200.0));
    mainCode.Emit(opCall, 2);
    mainCode.Emit(opReturn);

    res := vm.Execute(mainCode);
    AssertTrue('Function call result is number', res.IsNumber());
    AssertEquals('Function call returned 300', 300.0, res.NumVal, 0.0001);
  finally
    mainCode.Free();
    vm.Free();
  end;
end;

procedure TFloriaJSVMTest.TestBytecodeObjectsAndProperties();
var
  code: TFloriaJSBytecode;
  vm: TFloriaJSVM;
  res: TFloriaJSValue;
begin
  code := TFloriaJSBytecode.Create('objects');
  vm := TFloriaJSVM.Create();
  try
    // var o = {}; o.foo = 99; return o.foo;
    code.Emit(opNewObject);
    code.Emit(opDup);
    code.Emit(opConst, code.AddNumberConstant(99.0));
    code.Emit(opSetPropNamed, code.AddStringConstant('foo'));
    code.Emit(opPop); // pop the assigned 99

    code.Emit(opGetPropNamed, code.AddStringConstant('foo'));
    code.Emit(opReturn);

    res := vm.Execute(code);
    AssertTrue('Object property is number', res.IsNumber());
    AssertEquals('Object property read matches 99', 99.0, res.NumVal, 0.0001);
  finally
    code.Free();
    vm.Free();
  end;
end;

procedure TFloriaJSVMTest.TestBytecodeTryCatch();
var
  code: TFloriaJSBytecode;
  vm: TFloriaJSVM;
  res: TFloriaJSValue;
  tryIdx, catchTarget: Integer;
begin
  code := TFloriaJSBytecode.Create('try_catch');
  vm := TFloriaJSVM.Create();
  try
    // try { throw "error_msg"; } catch (e) { return "caught: " + e; }
    tryIdx := code.Emit(opPushTry, 0);
    code.Emit(opConst, code.AddStringConstant('error_msg'));
    code.Emit(opThrow);
    code.Emit(opPopTry);
    code.Emit(opConst, code.AddStringConstant('not_caught'));
    code.Emit(opReturn);

    catchTarget := code.CurrentIP();
    code.PatchJump(tryIdx, catchTarget);
    // On catch, the thrown value is on top of stack
    code.Emit(opConst, code.AddStringConstant('caught: '));
    code.Emit(opSwap);
    code.Emit(opAdd);
    code.Emit(opReturn);

    res := vm.Execute(code);
    AssertTrue('Catch returned string', res.IsString());
    AssertEquals('Caught error string matches', 'caught: error_msg', res.StrVal);
  finally
    code.Free();
    vm.Free();
  end;
end;

procedure TFloriaJSVMTest.TestCompileAndRunScript();
var
  vm: TFloriaJSVM;
  compiler: TFloriaJSCompiler;
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  code: TFloriaJSBytecode;
  env: TFloriaJSEnvironment;
  res: TFloriaJSValue;

  function Run(const AScript: string): TFloriaJSValue;
  begin
    parser := TFloriaJSParser.Create(AScript);
    try
      prog := parser.ParseProgram();
      try
        code := compiler.CompileProgram(prog);
        try
          Result := vm.Execute(code, env);
        finally
          code.Release();
        end;
      finally
        prog.Free();
      end;
    finally
      parser.Free();
    end;
  end;

begin
  vm := TFloriaJSVM.Create();
  compiler := TFloriaJSCompiler.Create();
  env := TFloriaJSEnvironment.Create(nil);
  vm.GlobalEnv := env;
  try
    // 1. Basic Arithmetic via compiler
    res := Run('var a = 10, b = 25; a + b;');
    AssertTrue('Compiled script result is number', res.IsNumber());
    AssertEquals('Compiled arithmetic sum', 35.0, res.NumVal, 0.0001);

    // 2. Loop & Accumulator
    res := Run('var sum = 0; for (var i = 1; i <= 10; i = i + 1) sum = sum + i; sum;');
    AssertTrue('Compiled loop result is number', res.IsNumber());
    AssertEquals('Compiled loop sum 1..10', 55.0, res.NumVal, 0.0001);

    // 3. User Function & Recursion (Factorial)
    res := Run('function factorial(n) { if (n <= 1) return 1; return n * factorial(n - 1); } factorial(5);');
    AssertTrue('Compiled factorial result is number', res.IsNumber());
    AssertEquals('Compiled factorial(5) == 120', 120.0, res.NumVal, 0.0001);

    // 4. Object Literal & Property Access
    res := Run('var o = { x: 10, y: 20 }; o.x + o.y;');
    AssertTrue('Compiled object sum is number', res.IsNumber());
    AssertEquals('Compiled object property sum', 30.0, res.NumVal, 0.0001);

    // 5. Arrow Function
    res := Run('var mult = (x, y) => x * y; mult(6, 7);');
    AssertTrue('Compiled arrow function result is number', res.IsNumber());
    AssertEquals('Compiled arrow function product', 42.0, res.NumVal, 0.0001);

    // 6. Try / Catch
    res := Run('try { throw "boom"; } catch (e) { "caught:" + e; }');
    AssertTrue('Compiled try/catch result is string', res.IsString());
    AssertEquals('Compiled try/catch caught message', 'caught:boom', res.StrVal);

    // 7. Switch Statement
    res := Run('var x = 2, out = ""; switch (x) { case 1: out = "one"; break; case 2: out = "two"; break; default: out = "def"; } out;');
    AssertTrue('Compiled switch result is string', res.IsString());
    AssertEquals('Compiled switch matched case', 'two', res.StrVal);

    res := Run('var x = 99, out = ""; switch (x) { case 1: out = "one"; break; default: out = "def"; } out;');
    AssertEquals('Compiled switch default case', 'def', res.StrVal);

    // 8. For..of Statement
    res := Run('var sum = 0; for (const x of [10, 20, 30]) sum = sum + x; sum;');
    AssertTrue('Compiled for..of array result is number', res.IsNumber());
    AssertEquals('Compiled for..of array sum', 60.0, res.NumVal, 0.0001);

    res := Run('var chars = ""; for (const ch of "abc") chars = chars + ch + "-"; chars;');
    AssertEquals('Compiled for..of string result', 'a-b-c-', res.StrVal);

    // 9. For..in Statement
    res := Run('var o = { a: 1, b: 2 }, keys = ""; for (var k in o) keys = keys + k + ";"; keys;');
    AssertTrue('Compiled for..in result is string', res.IsString());
    AssertEquals('Compiled for..in keys', 'a;b;', res.StrVal);

    // 10. Labeled Break Statement
    res := Run('var hit = 0; outer: for (var i = 0; i < 5; i = i + 1) { for (var j = 0; j < 5; j = j + 1) { if (i == 2 && j == 1) break outer; hit = hit + 1; } } hit;');
    AssertTrue('Compiled labeled break result is number', res.IsNumber());
    AssertEquals('Compiled labeled break count', 11.0, res.NumVal, 0.0001);
  finally
    env.Free();
    compiler.Free();
    vm.Free();
  end;
end;

{ TFloriaJSPriority3Test }

procedure TFloriaJSPriority3Test.TestMapCollection();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'const m = new Map();' +
      'm.set("k1", 100);' +
      'm.set("k2", 200);' +
      'm.size === 2 && m.get("k1") === 100 && m.has("k2") && !m.has("k3");'
    );
    AssertTrue('Map set, get, has, size success', res.Success);
    AssertTrue('Map operations evaluate to true', res.BooleanValue);

    res := engine.Execute(
      'const m = new Map();' +
      'm.set("a", 1); m.delete("a");' +
      'm.size === 0 && !m.has("a");'
    );
    AssertTrue('Map delete and size decrease', res.BooleanValue);

    // SameValueZero: NaN key & Object key
    res := engine.Execute(
      'const m = new Map();' +
      'm.set(NaN, "not a number");' +
      'const objKey = { id: 42 };' +
      'm.set(objKey, "object val");' +
      'm.get(NaN) === "not a number" && m.get(objKey) === "object val";'
    );
    AssertTrue('Map NaN and Object keys match', res.BooleanValue);

    // Iteration & forEach
    res := engine.Execute(
      'const m = new Map();' +
      'm.set("x", 10); m.set("y", 20);' +
      'let sum = 0;' +
      'm.forEach((val, key) => { sum = sum + val; });' +
      'let keys = 0, vals = 0;' +
      'for (const k of m.keys()) { keys = keys + 1; }' +
      'for (const v of m.values()) { vals = vals + v; }' +
      'sum === 30 && keys === 2 && vals === 30;'
    );
    AssertTrue('Map forEach and keys/values iteration', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority3Test.TestSetCollection();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'const s = new Set();' +
      's.add(10); s.add(20); s.add(10);' +
      's.size === 2 && s.has(10) && s.has(20) && !s.has(30);'
    );
    AssertTrue('Set deduplication, has, size success', res.Success);
    AssertTrue('Set operations evaluate to true', res.BooleanValue);

    res := engine.Execute(
      'const s = new Set();' +
      's.add("hello");' +
      'const deleted = s.delete("hello");' +
      'deleted && s.size === 0 && !s.has("hello");'
    );
    AssertTrue('Set delete works', res.BooleanValue);

    // forEach
    res := engine.Execute(
      'const s = new Set();' +
      's.add(1); s.add(2); s.add(3);' +
      'let total = 0;' +
      's.forEach((v) => { total = total + v; });' +
      'let seen = 0;' +
      'for (const v of s.values()) { seen = seen + 1; }' +
      'total === 6 && seen === 3;'
    );
    AssertTrue('Set forEach iteration', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority3Test.TestDateObject();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // Epoch 0 is 1970-01-01T00:00:00.000Z
    res := engine.Execute(
      'const d = new Date(0);' +
      'd.getTime() === 0 && d.getUTCFullYear() === 1970 && d.getUTCMonth() === 0 && d.getUTCDate() === 1;'
    );
    AssertTrue('Date epoch 0 UTC accessors', res.Success);
    AssertTrue('Date epoch 0 is 1970-01-01', res.BooleanValue);

    // ISO string
    res := engine.Execute(
      'const d = new Date(0);' +
      'd.toISOString() === "1970-01-01T00:00:00.000Z";'
    );
    AssertTrue('Date toISOString output', res.BooleanValue);

    // Date.now() & Date.UTC
    res := engine.Execute(
      'Date.now() > 0 && Date.UTC(1970, 0, 1) === 0;'
    );
    AssertTrue('Date.now and Date.UTC', res.BooleanValue);

    // Date.parse
    res := engine.Execute(
      'Date.parse("1970-01-01T00:00:00.000Z") === 0;'
    );
    AssertTrue('Date.parse ISO string', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority3Test.TestSymbolPrimitive();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'const s1 = Symbol("myDesc");' +
      'typeof s1 === "symbol" && s1.description === "myDesc";'
    );
    AssertTrue('Symbol creation and description', res.Success);
    AssertTrue('Symbol typeof and description match', res.BooleanValue);

    // Unique symbols
    res := engine.Execute(
      'const a = Symbol("x"); const b = Symbol("x");' +
      'a !== b;'
    );
    AssertTrue('Symbols with same description are not equal', res.BooleanValue);

    // Symbol.for and Symbol.keyFor
    res := engine.Execute(
      'const s = Symbol.for("shared");' +
      'Symbol.for("shared") === s && Symbol.keyFor(s) === "shared";'
    );
    AssertTrue('Symbol.for and Symbol.keyFor', res.BooleanValue);

    // Well-known symbols
    res := engine.Execute(
      'typeof Symbol.iterator === "symbol" && typeof Symbol.toStringTag === "symbol";'
    );
    AssertTrue('Well-known symbols exist', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority3Test.TestRegExpAndStringMethods();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // Constructor and test()
    res := engine.Execute(
      'const re = new RegExp("abc", "i");' +
      're.test("ABC") && !re.test("xyz") && re.source === "abc" && re.ignoreCase;'
    );
    AssertTrue('RegExp constructor and test()', res.Success);
    AssertTrue('RegExp test() matching', res.BooleanValue);

    // Regex literal syntax /pattern/flags
    res := engine.Execute(
      'const lit = /hello/i;' +
      'lit.test("HELLO World");'
    );
    AssertTrue('RegExp literal syntax works', res.BooleanValue);

    // exec()
    res := engine.Execute(
      'const re = /([a-z]+)-(\d+)/;' +
      'const m = re.exec("item-123");' +
      'm !== null && m[0] === "item-123" && m[1] === "item" && m[2] === "123" && m.index === 0;'
    );
    AssertTrue('RegExp exec() matches with captures', res.BooleanValue);

    // String.prototype.match
    res := engine.Execute(
      'const matches = "a1b2c3".match(/\d/g);' +
      'matches.length === 3 && matches[0] === "1" && matches[1] === "2" && matches[2] === "3";'
    );
    AssertTrue('String.prototype.match with global regex', res.BooleanValue);

    // String.prototype.search
    res := engine.Execute(
      '"hello world".search(/world/) === 6 && "hello world".search(/xyz/) === -1;'
    );
    AssertTrue('String.prototype.search regex', res.BooleanValue);

    // String.prototype.replace with regex
    res := engine.Execute(
      '"foo bar foo".replace(/foo/g, "baz") === "baz bar baz";'
    );
    AssertTrue('String.prototype.replace with global regex', res.BooleanValue);

    // String.prototype.split with regex
    res := engine.Execute(
      'const parts = "apple,banana;cherry".split(/[,;]/);' +
      'parts.length === 3 && parts[0] === "apple" && parts[1] === "banana" && parts[2] === "cherry";'
    );
    AssertTrue('String.prototype.split with regex separator', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority3Test.TestURIAndHostGlobals();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // encodeURIComponent / decodeURIComponent
    res := engine.Execute(
      'const enc = encodeURIComponent("hello world&foo=bar/baz");' +
      'enc === "hello%20world%26foo%3Dbar%2Fbaz" && decodeURIComponent(enc) === "hello world&foo=bar/baz";'
    );
    AssertTrue('encodeURIComponent and decodeURIComponent roundtrip', res.Success);
    AssertTrue('URI component encode/decode matches', res.BooleanValue);

    // encodeURI / decodeURI
    res := engine.Execute(
      'const uri = encodeURI("https://example.com/search?q=hello world");' +
      'uri === "https://example.com/search?q=hello%20world" && decodeURI(uri) === "https://example.com/search?q=hello world";'
    );
    AssertTrue('encodeURI and decodeURI roundtrip', res.BooleanValue);

    // setTimeout and clearTimeout
    res := engine.Execute(
      'typeof setTimeout === "function" && typeof clearTimeout === "function" && ' +
      'typeof setInterval === "function" && typeof clearInterval === "function";'
    );
    AssertTrue('Host timer functions exist on global scope', res.BooleanValue);

    res := engine.Execute(
      'let called = false;' +
      'const id = setTimeout(() => { called = true; }, 0);' +
      'clearTimeout(id);' +
      'id > 0;'
    );
    AssertTrue('setTimeout returns id and clearTimeout cancels', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

{ TFloriaJSPriority1Test }

procedure TFloriaJSPriority1Test.TestConstReassignmentRejection();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('const a = 10; a = 20;');
    AssertFalse('const assignment should fail', res.Success);
    AssertTrue('Error message mentions constant variable', Pos('constant variable', res.ErrorMessage) > 0);

    res := engine.Execute('const x = 5; x++;');
    AssertFalse('const increment should fail', res.Success);
    AssertTrue('Error message mentions constant variable', Pos('constant variable', res.ErrorMessage) > 0);

    res := engine.Execute('const { v } = { v: 1 }; v = 2;');
    AssertFalse('const destructuring assignment should fail', res.Success);

    res := engine.Execute('let sum = 0; for (const x of [1, 2, 3]) { sum = sum + x; } sum === 6;');
    AssertTrue('for...of with const variable succeeds', res.Success);
    AssertTrue('for...of with const computes sum', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestDuplicateLetConstRejection();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('let x = 1; let x = 2;');
    AssertFalse('Duplicate let in same script must fail', res.Success);
    AssertTrue('Error contains SyntaxError', Pos('SyntaxError', res.ErrorMessage) > 0);

    res := engine.Execute('const y = 1; const y = 2;');
    AssertFalse('Duplicate const in same script must fail', res.Success);
    AssertTrue('Error contains SyntaxError', Pos('SyntaxError', res.ErrorMessage) > 0);

    res := engine.Execute('var z = 1; let z = 2;');
    AssertFalse('var and let collision must fail', res.Success);
    AssertTrue('Error contains SyntaxError', Pos('SyntaxError', res.ErrorMessage) > 0);

    res := engine.Execute('{ let b = 1; let b = 2; }');
    AssertFalse('Duplicate let in block must fail', res.Success);
    AssertTrue('Error contains SyntaxError', Pos('SyntaxError', res.ErrorMessage) > 0);

    res := engine.Execute('function f() { let a = 1; let a = 2; } f();');
    AssertFalse('Duplicate let in function must fail', res.Success);
    AssertTrue('Error contains SyntaxError', Pos('SyntaxError', res.ErrorMessage) > 0);

    res := engine.Execute('let val = 1; { let val = 2; if (val !== 2) throw "err"; } val === 1;');
    AssertTrue('Nested block shadowing is valid', res.Success);
    AssertTrue('Shadowed variable restores outside block', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestUndeclaredIdentifierReferenceError();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('undeclaredVar123 + 1;');
    AssertFalse('Undeclared read must fail', res.Success);
    AssertTrue('Error is ReferenceError', Pos('ReferenceError', res.ErrorMessage) > 0);

    res := engine.Execute('nonExistentFunc();');
    AssertFalse('Undeclared call must fail', res.Success);
    AssertTrue('Error is ReferenceError', Pos('ReferenceError', res.ErrorMessage) > 0);

    res := engine.Execute('typeof completelyUndeclaredIdentifier === "undefined";');
    AssertTrue('typeof undeclared identifier must succeed', res.Success);
    AssertTrue('typeof undeclared returns true', res.BooleanValue);

    res := engine.Execute('const num = 42; typeof num === "number";');
    AssertTrue('typeof defined variable succeeds', res.Success);
    AssertTrue('typeof num returns number', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestFunctionDeclarationHoisting();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('const res = calc(10, 5); function calc(a, b) { return a * b; } res === 50;');
    AssertTrue('Top level function hoisting succeeds', res.Success);
    AssertTrue('Hoisted function returns expected value', res.BooleanValue);

    res := engine.Execute(
      'function outer() {' +
      '  return inner();' +
      '  function inner() { return 42; }' +
      '}' +
      'outer() === 42;'
    );
    AssertTrue('Function hoisting in function body succeeds', res.Success);
    AssertTrue('Hoisted inner function returns expected value', res.BooleanValue);

    res := engine.Execute(
      'function isEven(n) { if (n === 0) return true; return isOdd(n - 1); }' +
      'function isOdd(n) { if (n === 0) return false; return isEven(n - 1); }' +
      'isEven(10) && !isOdd(10) && isOdd(7);'
    );
    AssertTrue('Mutually recursive hoisted functions succeed', res.Success);
    AssertTrue('Mutual recursion yields true', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestArrayPrototypeToString();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('[1, 2, 3].toString() === "1,2,3";');
    AssertTrue('[1, 2, 3].toString()', res.Success);
    AssertTrue('[1, 2, 3].toString() === "1,2,3"', res.BooleanValue);

    res := engine.Execute('[].toString() === "";');
    AssertTrue('[].toString()', res.Success);
    AssertTrue('[].toString() === ""', res.BooleanValue);

    res := engine.Execute('["a", "b"].toString() === "a,b";');
    AssertTrue('["a", "b"].toString()', res.Success);
    AssertTrue('["a", "b"].toString() === "a,b"', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestForInArrayIndices();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'const arr = ["x", "y", "z"];' +
      'const keys = [];' +
      'for (const k in arr) {' +
      '  keys.push(k);' +
      '}' +
      'keys.join(",") === "0,1,2";'
    );
    AssertTrue('for...in on array succeeds', res.Success);
    AssertTrue('for...in iterates numeric indices', res.BooleanValue);

    res := engine.Execute(
      'const empty = [];' +
      'let count = 0;' +
      'for (const k in empty) { count = count + 1; }' +
      'count === 0;'
    );
    AssertTrue('for...in on empty array produces 0 iterations', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestObjectKeysValuesEntriesOnArrays();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('Object.keys([10, 20, 30]).join(",") === "0,1,2";');
    AssertTrue('Object.keys on array', res.Success);
    AssertTrue('Object.keys returns ["0", "1", "2"]', res.BooleanValue);

    res := engine.Execute('Object.values([10, 20, 30]).join(",") === "10,20,30";');
    AssertTrue('Object.values on array', res.Success);
    AssertTrue('Object.values returns elements', res.BooleanValue);

    res := engine.Execute('const e = Object.entries(["a", "b"]); e.length === 2 && e[0][0] === "0" && e[0][1] === "a";');
    AssertTrue('Object.entries on array', res.Success);
    AssertTrue('Object.entries returns key-value pairs', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestArrayPropertyReflection();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'const arr = ["first", "second"];' +
      '0 in arr && 1 in arr && !(2 in arr) && "length" in arr;'
    );
    AssertTrue('in operator on array', res.Success);
    AssertTrue('in operator checks element existence', res.BooleanValue);

    res := engine.Execute(
      'const arr = ["first", "second"];' +
      'arr.hasOwnProperty("0") && arr.hasOwnProperty(1) && !arr.hasOwnProperty("2") && arr.hasOwnProperty("length");'
    );
    AssertTrue('hasOwnProperty on array', res.Success);
    AssertTrue('hasOwnProperty checks elements and length', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestFunctionCallApplyBind();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'function greet(prefix, suffix) { return prefix + " " + this.name + suffix; }' +
      'greet.call({ name: "Alice" }, "Hello", "!") === "Hello Alice!";'
    );
    AssertTrue('Function.prototype.call succeeds', res.Success);
    AssertTrue('Function.prototype.call sets this and passes args', res.BooleanValue);

    res := engine.Execute(
      'function add(a, b, c) { return this.offset + a + b + c; }' +
      'add.apply({ offset: 100 }, [10, 20, 30]) === 160;'
    );
    AssertTrue('Function.prototype.apply succeeds', res.Success);
    AssertTrue('Function.prototype.apply unpacks array args', res.BooleanValue);

    res := engine.Execute(
      'function multiply(a, b) { return this.scale * a * b; }' +
      'const scaledByTen = multiply.bind({ scale: 10 }, 5);' +
      'scaledByTen(4) === 200;'
    );
    AssertTrue('Function.prototype.bind succeeds', res.Success);
    AssertTrue('Function.prototype.bind curries arguments and sets this', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestFunctionPrototypeAndConstructor();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'function Foo() {}' +
      'Foo.prototype.constructor === Foo;'
    );
    AssertTrue('Foo.prototype.constructor === Foo', res.Success);
    AssertTrue('Constructor back-reference matches function', res.BooleanValue);

    res := engine.Execute(
      'function Bar(x) { this.x = x; }' +
      'const b = new Bar(42);' +
      'b.constructor === Bar && b instanceof Bar && b.x === 42;'
    );
    AssertTrue('new Bar().constructor === Bar', res.Success);
    AssertTrue('Instance constructor and instanceof match', res.BooleanValue);

    res := engine.Execute(
      'typeof Function === "function" && ' +
      'typeof Function.prototype.call === "function" && ' +
      'typeof Function.prototype.apply === "function" && ' +
      'typeof Function.prototype.bind === "function";'
    );
    AssertTrue('Global Function and methods exist', res.Success);
    AssertTrue('Function prototype methods exist', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestNumericParsingAndFormatting();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('Number("0x10") === 16 && Number("0b101") === 5 && Number("0o17") === 15;');
    AssertTrue('Number hex/bin/oct parsing succeeds', res.Success);
    AssertTrue('Number hex/bin/oct parsing correct', res.BooleanValue);

    res := engine.Execute(
      'parseInt("010") === 10 && ' +
      'parseInt("0x10") === 16 && ' +
      'parseInt("10", 2) === 2 && ' +
      'parseInt("10", 8) === 8 && ' +
      'parseInt("10", 16) === 16 && ' +
      'parseInt("  123px") === 123;'
    );
    AssertTrue('parseInt with various radices succeeds', res.Success);
    AssertTrue('parseInt with various radices correct', res.BooleanValue);

    res := engine.Execute('(1e20).toString().indexOf("1") === 0;');
    AssertTrue('Large number toString succeeds without overflow', res.Success);
    AssertTrue('Large number toString starts with 1', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestCompoundAssignmentToMembers();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // Named member compound assignment
    res := engine.Execute(
      'var o = { x: 1, y: 2 };' +
      'o.x += 2;' +
      'var r1 = (o.x *= 3);' +
      'o.x -= 4;' +
      'o.x /= 2.5;' +
      'o.x %= 1.5;' +
      'o.y **= 3;' +
      'o.x === 0.5 && r1 === 9 && o.y === 8;'
    );
    AssertTrue('Named member compound assignment succeeds', res.Success);
    AssertTrue('Named member compound assignment values correct', res.BooleanValue);

    // Computed member and array compound assignment
    res := engine.Execute(
      'var a = [10, 20];' +
      'a[0] += 5;' +
      'var rArr = (a[0] *= 2);' +
      'a[1] -= 5;' +
      'var obj = { k: 10 };' +
      'obj["k"] += 5;' +
      'obj["k"] **= 2;' +
      'a[0] === 30 && rArr === 30 && a[1] === 15 && obj.k === 225;'
    );
    AssertTrue('Computed member and array compound assignment succeeds', res.Success);
    AssertTrue('Computed member and array compound assignment values correct', res.BooleanValue);

    // Single evaluation of target and computed property key
    res := engine.Execute(
      'var targetCalls = 0;' +
      'var propCalls = 0;' +
      'var host = { val: 10 };' +
      'function getHost() { targetCalls += 1; return host; }' +
      'function getProp() { propCalls += 1; return "val"; }' +
      'getHost()[getProp()] += 5;' +
      'targetCalls === 1 && propCalls === 1 && host.val === 15;'
    );
    AssertTrue('Side effects in member target and property evaluated once', res.Success);
    AssertTrue('Target and prop calls exactly 1 each', res.BooleanValue);

    // Nullish assignment ??= for named, computed, and identifier
    res := engine.Execute(
      'var nObj = { a: null, b: 42, c: undefined };' +
      'var rN1 = (nObj.a ??= 100);' +
      'var rhsCalls = 0;' +
      'var rN2 = (nObj.b ??= (rhsCalls += 1, 999));' +
      'nObj["c"] ??= "default";' +
      'var idNull = null;' +
      'idNull ??= "assigned";' +
      'var idVal = "keep";' +
      'idVal ??= "replaced";' +
      'rN1 === 100 && nObj.a === 100 && ' +
      'rN2 === 42 && nObj.b === 42 && rhsCalls === 0 && ' +
      'nObj.c === "default" && ' +
      'idNull === "assigned" && idVal === "keep";'
    );
    AssertTrue('Nullish assignment ??= succeeds', res.Success);
    AssertTrue('Nullish assignment ??= semantics correct', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestDestructuringAssignment();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // 1. Array destructuring assignment & expression result (RHS)
    res := engine.Execute(
      'var a, b;' +
      'var rArr = ([a, b] = [1, 2]);' +
      'a === 1 && b === 2 && rArr[0] === 1 && rArr[1] === 2;'
    );
    AssertTrue('Array destructuring assignment succeeds', res.Success);
    AssertTrue('Array destructuring assignment values and RHS correct', res.BooleanValue);

    // 2. Object destructuring assignment & expression result (RHS)
    res := engine.Execute(
      'var x, y;' +
      'var rObj = ({ x, y } = { x: 10, y: 20 });' +
      'x === 10 && y === 20 && rObj.x === 10 && rObj.y === 20;'
    );
    AssertTrue('Object destructuring assignment succeeds', res.Success);
    AssertTrue('Object destructuring assignment values and RHS correct', res.BooleanValue);

    // 3. Defaults in destructuring assignment
    res := engine.Execute(
      'var d1, d2, o1, o2;' +
      '[d1 = 10, d2 = 20] = [5];' +
      '({ o1 = 100, o2 = 200 } = { o1: 50 });' +
      'd1 === 5 && d2 === 20 && o1 === 50 && o2 === 200;'
    );
    AssertTrue('Defaults in destructuring assignment succeed', res.Success);
    AssertTrue('Defaults in destructuring assignment values correct', res.BooleanValue);

    // 4. Member targets
    res := engine.Execute(
      'var objTarget = { a: 0, b: 0 };' +
      '[objTarget.a, objTarget["b"]] = [7, 8];' +
      'objTarget.a === 7 && objTarget.b === 8;'
    );
    AssertTrue('Member targets in destructuring assignment succeed', res.Success);
    AssertTrue('Member targets in destructuring assignment values correct', res.BooleanValue);

    // 5. Computed keys in object destructuring assignment
    res := engine.Execute(
      'var cVal;' +
      'var cKey = "myKey";' +
      '({ [cKey]: cVal } = { myKey: 99 });' +
      'cVal === 99;'
    );
    AssertTrue('Computed keys in destructuring assignment succeed', res.Success);
    AssertTrue('Computed keys in destructuring assignment value correct', res.BooleanValue);

    // 6. Array holes / skipped elements
    res := engine.Execute(
      'var first, third;' +
      '[first, , third] = [11, 22, 33];' +
      'first === 11 && third === 33;'
    );
    AssertTrue('Array holes in destructuring assignment succeed', res.Success);
    AssertTrue('Array holes in destructuring assignment values correct', res.BooleanValue);

    // 7. Rest patterns in destructuring assignment
    res := engine.Execute(
      'var head, tail, rA, rRest;' +
      '[head, ...tail] = [1, 2, 3, 4];' +
      '({ rA, ...rRest } = { rA: 10, rB: 20, rC: 30 });' +
      'head === 1 && tail.length === 3 && tail[0] === 2 && tail[1] === 3 && tail[2] === 4 && ' +
      'rA === 10 && rRest.rB === 20 && rRest.rC === 30;'
    );
    AssertTrue('Rest patterns in destructuring assignment succeed', res.Success);
    AssertTrue('Rest patterns in destructuring assignment values correct', res.BooleanValue);

    // 8. Nested destructuring assignment
    res := engine.Execute(
      'var n1, n2, n3;' +
      '[ [n1, n2], { n3 } ] = [ [1, 2], { n3: 3 } ];' +
      'n1 === 1 && n2 === 2 && n3 === 3;'
    );
    AssertTrue('Nested destructuring assignment succeeds', res.Success);
    AssertTrue('Nested destructuring assignment values correct', res.BooleanValue);

    // 9. Const target rejection
    res := engine.Execute(
      'const cVal = 42;' +
      'var caughtConstName = "";' +
      'try { [cVal] = [99]; } catch (e) { caughtConstName = e.name; }' +
      'caughtConstName === "TypeError";'
    );
    AssertTrue('Const target rejection in destructuring assignment succeeds', res.Success);
    AssertTrue('Const target rejection threw TypeError', res.BooleanValue);

    // 10. Non-iterable array destructuring rejection (P0-03)
    // [a] = 5 throws TypeError
    res := engine.Execute(
      'var caught = "";' +
      'try { var a; [a] = 5; } catch (e) { caught = e.name; }' +
      'caught === "TypeError";'
    );
    AssertTrue('[a] = 5 must throw TypeError', res.Success and res.BooleanValue);

    // [a] = { 0: 7, length: 1 } throws TypeError
    res := engine.Execute(
      'var caught = "";' +
      'try { var a; [a] = { 0: 7, length: 1 }; } catch (e) { caught = e.name; }' +
      'caught === "TypeError";'
    );
    AssertTrue('[a] = {0:7, length:1} must throw TypeError', res.Success and res.BooleanValue);

    // P2-05 added the iteration protocol, so a Set can now be destructured.
    res := engine.Execute('var a; [a] = new Set([1]); a;');
    AssertTrue('[a] = new Set([1]) succeeds', res.Success);
    AssertEquals('a Set destructures through its iterator', '1', res.StringValue);

    // A Map entry destructures to its [key, value] pair.
    res := engine.Execute('var a; [a] = new Map([[1, 2]]); a[0] + ":" + a[1];');
    AssertTrue('[a] = new Map(...) succeeds', res.Success);
    AssertEquals('a Map entry destructures to a pair', '1:2', res.StringValue);

    // A non-iterable is still rejected.
    res := engine.Execute(
      'var caught = "";' +
      'try { var b; [b] = 5; } catch (e) { caught = e.name; }' +
      'caught === "TypeError";'
    );
    AssertTrue('[b] = 5 must throw TypeError', res.Success and res.BooleanValue);

    // [x, y] = "ab" assigns x="a", y="b"
    res := engine.Execute(
      'var x, y;' +
      '[x, y] = "ab";' +
      'x === "a" && y === "b";'
    );
    AssertTrue('String array destructuring assigns characters', res.Success and res.BooleanValue);

    // [a, b] = [1] -> b === undefined
    res := engine.Execute(
      'var a, b;' +
      '[a, b] = [1];' +
      'a === 1 && b === undefined;'
    );
    AssertTrue('Missing elements are undefined', res.Success and res.BooleanValue);

    // [a=7, b=8] = [undefined] defaults correctly
    res := engine.Execute(
      'var a, b;' +
      '[a = 7, b = 8] = [undefined];' +
      'a === 7 && b === 8;'
    );
    AssertTrue('Explicit undefined triggers default', res.Success and res.BooleanValue);

    // RHS evaluated once and is expression result
    res := engine.Execute(
      'var count = 0; var a;' +
      'var r = ([a] = (++count, [42]));' +
      'r[0] === 42 && count === 1 && a === 42;'
    );
    AssertTrue('RHS evaluated once and returned as result', res.Success and res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestVarHoistingAndFunctionCollisions();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // 1. var hoisting before initializer inside function
    res := engine.Execute('function f1() { return a; var a = 1; } f1() === undefined;');
    AssertTrue('var hoisting returns undefined before init', res.Success);
    AssertTrue('var hoisting returns undefined before init is true', res.BooleanValue);

    // 2. bare var declaration after assignment does not overwrite value
    res := engine.Execute('function f2() { a = 5; var a; return a; } f2() === 5;');
    AssertTrue('bare var does not overwrite existing value', res.Success);
    AssertTrue('bare var does not overwrite existing value is true', res.BooleanValue);

    // 3. function declaration wins over bare var collision
    res := engine.Execute('function a() { return 1; } var a; a() === 1;');
    AssertTrue('function declaration wins over bare var', res.Success);
    AssertTrue('function declaration wins over bare var is true', res.BooleanValue);

    // 4. bare var before function declaration
    res := engine.Execute('var b; function b() { return 2; } b() === 2;');
    AssertTrue('bare var before function does not overwrite function', res.Success);
    AssertTrue('bare var before function does not overwrite function is true', res.BooleanValue);

    // 5. typeof before var declaration evaluates to undefined
    res := engine.Execute('var rType = (typeof myHVar === "undefined"); var myHVar = 42; rType && myHVar === 42;');
    AssertTrue('typeof before var declaration evaluates to undefined', res.Success);
    AssertTrue('typeof before var declaration is true', res.BooleanValue);

    // 6. var hoisting out of nested blocks into enclosing function
    res := engine.Execute('function fBlock() { if (true) { var insideIf = 100; } return insideIf; } fBlock() === 100;');
    AssertTrue('var inside if block is accessible in function', res.Success);
    AssertTrue('var inside if block value is 100', res.BooleanValue);

    // 7. var inside loop accessible outside loop
    res := engine.Execute('function fLoop() { for (var idx = 0; idx < 3; idx++) {} return idx; } fLoop() === 3;');
    AssertTrue('var in loop accessible in function', res.Success);
    AssertTrue('var in loop value is 3', res.BooleanValue);

    // 8. nested function var does not hoist to outer function
    res := engine.Execute('function fOuter() { function fInner() { var hidden = 99; } return typeof hidden; } fOuter() === "undefined";');
    AssertTrue('nested function var does not hoist to outer', res.Success);
    AssertTrue('nested function var is undefined in outer', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestClassicForLoopBlockScoping();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // Each iteration captures its own binding.
    res := engine.Execute(
      'var f = [];' +
      'for (let i = 0; i < 3; i++) f.push(() => i);' +
      'f[0]() === 0 && f[1]() === 1 && f[2]() === 2;'
    );
    AssertTrue('Classic for-loop closures capture per-iteration let bindings',
      res.Success and res.BooleanValue);

    // The loop binding is not visible after the loop.
    res := engine.Execute(
      'var n = 0; for (let i = 0; i < 2; i++) n++; typeof i === "undefined";'
    );
    AssertTrue('Classic for-loop let binding does not leak',
      res.Success and res.BooleanValue);

    // Several loop bindings are copied per iteration.
    res := engine.Execute(
      'var f = [];' +
      'for (let i = 0, j = 10; i < 2; i++, j++) f.push(() => i + j);' +
      'f[0]() === 10 && f[1]() === 12;'
    );
    AssertTrue('Multiple classic for-loop let bindings are per-iteration',
      res.Success and res.BooleanValue);

    // continue still advances the loop and captures the right binding.
    res := engine.Execute(
      'var f = [];' +
      'for (let i = 0; i < 4; i++) {' +
      '  if (i === 1) continue;' +
      '  if (i === 3) break;' +
      '  f.push(() => i);' +
      '}' +
      'f.length === 2 && f[0]() === 0 && f[1]() === 2;'
    );
    AssertTrue('continue and break preserve per-iteration bindings',
      res.Success and res.BooleanValue);

    // return from inside the loop still tears down all loop environments.
    res := engine.Execute(
      'function g() {' +
      '  var f = [];' +
      '  for (let i = 0; i < 3; i++) {' +
      '    f.push(() => i);' +
      '    if (i === 1) return f[0]() + f[1]();' +
      '  }' +
      '}' +
      'g() === 1;'
    );
    AssertTrue('return preserves captured values and exits the loop',
      res.Success and res.BooleanValue);

    // Labeled continue from a nested loop keeps the outer iteration binding.
    res := engine.Execute(
      'var f = [];' +
      'outer: for (let i = 0; i < 3; i++) {' +
      '  for (let j = 0; j < 3; j++) {' +
      '    if (j === 1) continue outer;' +
      '    f.push(() => i * 10 + j);' +
      '  }' +
      '}' +
      'f.length === 3 && f[0]() === 0 && f[1]() === 10 && f[2]() === 20;'
    );
    AssertTrue('Labeled continue preserves the outer per-iteration binding',
      res.Success and res.BooleanValue);

    // Labeled break from a nested loop exits through the outer cleanup path.
    res := engine.Execute(
      'var f = [];' +
      'outer: for (let i = 0; i < 3; i++) {' +
      '  for (let j = 0; j < 3; j++) {' +
      '    if (i === 1) break outer;' +
      '    f.push(() => i * 10 + j);' +
      '  }' +
      '}' +
      'f.length === 3 && f[0]() === 0 && f[1]() === 1 && f[2]() === 2;'
    );
    AssertTrue('Labeled break preserves captured bindings and cleans up',
      res.Success and res.BooleanValue);

    // throw unwinds the loop scope and is catchable outside it.
    res := engine.Execute(
      'var caught = 0;' +
      'try {' +
      '  for (let i = 0; i < 3; i++) {' +
      '    if (i === 1) throw 7;' +
      '  }' +
      '} catch (e) { caught = e; }' +
      'caught === 7 && typeof i === "undefined";'
    );
    AssertTrue('throw unwinds classic for-loop let scope',
      res.Success and res.BooleanValue);

    // var loop bindings remain function/script scoped, not per-iteration.
    res := engine.Execute(
      'var f = [];' +
      'for (var i = 0; i < 3; i++) f.push(() => i);' +
      'f[0]() === 3 && f[1]() === 3 && f[2]() === 3 && i === 3;'
    );
    AssertTrue('Classic for-loop var bindings keep shared semantics',
      res.Success and res.BooleanValue);

    // A const loop with no update and an immediate break still works.
    res := engine.Execute(
      'var r = 0; for (const i = 5; ; ) { r = i; break; } r === 5;'
    );
    AssertTrue('const classic for-loop binding works without update',
      res.Success and res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestChainWideOptionalChaining();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // 1. Chain-wide short-circuit on null/undefined base: a?.b.c
    res := engine.Execute('var a = null; (a?.b.c === undefined) && (a?.b() === undefined);');
    AssertTrue('a?.b.c and a?.b() evaluate to undefined without TypeError', res.Success);
    AssertTrue('a?.b.c and a?.b() are undefined', res.BooleanValue);

    // 2. Call argument evaluation skipped when base is nullish
    res := engine.Execute(
      'var sideEffectCount = 0;' +
      'function runSideEffect() { sideEffectCount += 1; return 1; }' +
      'var a = null;' +
      'var r = a?.b(runSideEffect());' +
      'r === undefined && sideEffectCount === 0;'
    );
    AssertTrue('Arguments not evaluated when base is nullish', res.Success);
    AssertTrue('sideEffectCount remains 0', res.BooleanValue);

    // 3. Computed property key evaluation skipped when base is nullish
    res := engine.Execute(
      'var keyCallCount = 0;' +
      'function runKey() { keyCallCount += 1; return "prop"; }' +
      'var a = undefined;' +
      'var r = a?.[runKey()].nested;' +
      'r === undefined && keyCallCount === 0;'
    );
    AssertTrue('Computed key not evaluated when base is nullish', res.Success);
    AssertTrue('keyCallCount remains 0', res.BooleanValue);

    // 4. Direct optional call a?.() on nullish
    res := engine.Execute('var fn = null; fn?.() === undefined;');
    AssertTrue('Direct optional call on null returns undefined', res.Success);
    AssertTrue('Direct optional call on null is undefined', res.BooleanValue);

    // 5. Non-nullish chain behaves normally
    res := engine.Execute(
      'var obj = { x: { y: { fn: function(k) { return k * 2; } } } };' +
      'obj?.x.y.fn(21) === 42 && obj?.x?.y?.fn(10) === 20 && obj?.x["y"].fn(5) === 10;'
    );
    AssertTrue('Non-nullish optional chain behaves normally', res.Success);
    AssertTrue('Non-nullish optional chain result is correct', res.BooleanValue);

    // 6. Optional chain assignment rejection (SyntaxError)
    res := engine.Execute('var a = { b: 1 }; a?.b = 2;');
    AssertFalse('Optional chain assignment must be rejected', res.Success);
    res := engine.Execute('var a = { b: 1 }; a?.[0] = 2;');
    AssertFalse('Optional chain computed assignment must be rejected', res.Success);
    res := engine.Execute('var a = { b: 1 }; a?.b++;');
    AssertFalse('Optional chain postfix ++ must be rejected', res.Success);
    res := engine.Execute('var a = { b: 1 }; ++a?.b;');
    AssertFalse('Optional chain prefix ++ must be rejected', res.Success);

    // 7. Method call this-binding in optional chain
    res := engine.Execute('var o = { x: 10, m: function(y) { return this.x + y; } }; o?.m(5) === 15;');
    AssertTrue('Method call preserves this in optional chain', res.Success);
    AssertTrue('Method call preserves this value', res.BooleanValue);

    // 8. Optional method invocation when method is nullish
    res := engine.Execute('var o = { m: null }; o?.m?.() === undefined;');
    AssertTrue('Optional method on null method evaluates to undefined', res.Success);
    AssertTrue('Optional method on null method is undefined', res.BooleanValue);

    // 9. Nested optional calls
    res := engine.Execute('var o = { x: { y: null } }; o?.x?.y?.() === undefined;');
    AssertTrue('Nested optional call evaluates to undefined', res.Success);
    AssertTrue('Nested optional call is undefined', res.BooleanValue);

    // 10. Optional chaining grouping boundaries & new rejection (P0-05)
    // (a?.b).c with a = null throws TypeError
    res := engine.Execute(
      'var caught = "";' +
      'try { var a = null; (a?.b).c; } catch (e) { caught = e.name; }' +
      'caught === "TypeError";'
    );
    AssertTrue('(a?.b).c with null a throws TypeError', res.Success and res.BooleanValue);

    // (a?.b)() with a = null throws TypeError
    res := engine.Execute(
      'var caught = "";' +
      'try { var a = null; (a?.b)(); } catch (e) { caught = e.name; }' +
      'caught === "TypeError";'
    );
    AssertTrue('(a?.b)() with null a throws TypeError', res.Success and res.BooleanValue);

    // (a?.b)?.c with a = null is undefined (new optional chain)
    res := engine.Execute('var a = null; (a?.b)?.c === undefined;');
    AssertTrue('(a?.b)?.c with null a evaluates to undefined', res.Success and res.BooleanValue);

    // (a?.())() with a = null throws TypeError
    res := engine.Execute(
      'var caught = "";' +
      'try { var a = null; (a?.())(); } catch (e) { caught = e.name; }' +
      'caught === "TypeError";'
    );
    AssertTrue('(a?.())() with null a throws TypeError', res.Success and res.BooleanValue);

    // new a?.b() is a SyntaxError / parse error
    res := engine.Execute('var a = { b: function() {} }; new a?.b();');
    AssertFalse('new a?.b() must be rejected', res.Success);
    AssertTrue('new a?.b() must fail in the parser',
      Pos('Cannot use new with optional chaining', res.ErrorMessage) > 0);

    res := engine.Execute('var a = { b: function() {} }; new a?.b;');
    AssertFalse('new a?.b must be rejected', res.Success);
    AssertTrue('new a?.b must fail in the parser',
      Pos('Cannot use new with optional chaining', res.ErrorMessage) > 0);

    res := engine.Execute('var a = { b: function() {} }; new a?.[0]();');
    AssertFalse('new a?.[0]() must be rejected', res.Success);
    AssertTrue('new a?.[0]() must fail in the parser',
      Pos('Cannot use new with optional chaining', res.ErrorMessage) > 0);

    res := engine.Execute('var a = function() {}; new a?.();');
    AssertFalse('new a?.() must be rejected', res.Success);
    AssertTrue('new a?.() must fail in the parser',
      Pos('Cannot use new with optional chaining', res.ErrorMessage) > 0);

    // Parentheses around an optional chain do not make it a valid update target.
    res := engine.Execute('var a = { b: 1 }; (a?.b)++;');
    AssertFalse('Grouped optional-chain postfix ++ must be rejected', res.Success);
    AssertTrue('Grouped optional-chain postfix ++ must fail in the parser',
      Pos('Invalid left-hand side in postfix operation', res.ErrorMessage) > 0);

    res := engine.Execute('var a = { b: 1 }; ++(a?.b);');
    AssertFalse('Grouped optional-chain prefix ++ must be rejected', res.Success);
    AssertTrue('Grouped optional-chain prefix ++ must fail in the parser',
      Pos('Invalid left-hand side in prefix operation', res.ErrorMessage) > 0);

    res := engine.Execute('var a = { b: 1 }; ((a?.b))++;');
    AssertFalse('Nested grouped optional-chain postfix ++ must be rejected', res.Success);
    AssertTrue('Nested grouped optional-chain postfix ++ must fail in the parser',
      Pos('Invalid left-hand side in postfix operation', res.ErrorMessage) > 0);

    res := engine.Execute('var a = { b: 1 }; (a?.b) += 1;');
    AssertFalse('Grouped optional-chain compound assignment must be rejected', res.Success);
    AssertTrue('Grouped optional-chain compound assignment must fail in the parser',
      Pos('Invalid left-hand side in assignment', res.ErrorMessage) > 0);

    // Parentheses must remain transparent for valid unary targets.
    res := engine.Execute('var a = 1; (a)++; a === 2;');
    AssertTrue('Grouped identifier postfix update works', res.Success and res.BooleanValue);

    res := engine.Execute('var a = { b: 1 }; (a.b)++; a.b === 2;');
    AssertTrue('Grouped member postfix update works', res.Success and res.BooleanValue);

    res := engine.Execute('var a = { b: 1 }; ++(a["b"]); a.b === 2;');
    AssertTrue('Grouped computed prefix update works', res.Success and res.BooleanValue);

    res := engine.Execute('var a = { b: 1 }; delete (a.b); !("b" in a);');
    AssertTrue('Grouped delete removes a property', res.Success and res.BooleanValue);

    res := engine.Execute('var a = { b: 1 }; delete (a?.b); !("b" in a);');
    AssertTrue('Grouped optional-chain delete removes a property', res.Success and res.BooleanValue);

    // Parentheses around an optional chain are valid as a new callee.
    res := engine.Execute(
      'var a = { b: function() { this.x = 7; } };' +
      'var o = new (a?.b)(); o.x === 7;'
    );
    AssertTrue('new (a?.b)() is valid', res.Success and res.BooleanValue);

    // (a?.b).c with non-null a works normally
    res := engine.Execute('var a = { b: { c: 10 } }; (a?.b).c === 10;');
    AssertTrue('(a?.b).c with non-null a works normally', res.Success and res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestConstructorBackReferencesLifetimeSafe();
var
  ctx: TFloriaJSContext;
  res: TFloriaJSResult;
  initCount, i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    // 1. Prototype replaced with new object, function collected, old prototype accessed
    ctx.Evaluate(
      'function F() {}' +
      'var p1 = F.prototype;' +
      'F.prototype = {};' +
      'F = null;'
    );
    ctx.Heap.Collect();
    res := ctx.Evaluate('p1.constructor === Object;');
    AssertTrue('Detached prototype constructor delegates safely to Object after GC', res.Success and res.BooleanValue);

    // 2. Prototype deleted, function collected, old prototype accessed
    ctx.Evaluate(
      'function G() {}' +
      'var p2 = G.prototype;' +
      'delete G.prototype;' +
      'G = null;'
    );
    ctx.Heap.Collect();
    res := ctx.Evaluate('p2.constructor === Object;');
    AssertTrue('Deleted prototype constructor delegates safely to Object after GC', res.Success and res.BooleanValue);

    // 3. Function collected without prototype replacement (prototype held by user var)
    ctx.Evaluate(
      'function H() {}' +
      'var p3 = H.prototype;' +
      'H = null;'
    );
    ctx.Heap.Collect();
    res := ctx.Evaluate('p3.constructor === Object;');
    AssertTrue('Orphaned prototype constructor delegates safely to Object after function GC', res.Success and res.BooleanValue);

    // 4. Repeated detachment and reclamation does not leak memory or crash
    initCount := ctx.Heap.GetObjectCount();
    for i := 1 to 200 do
    begin
      ctx.Evaluate(
        'function Temp() {}' +
        'var oldP = Temp.prototype;' +
        'Temp.prototype = {};' +
        'Temp = null;' +
        'oldP = null;'
      );
    end;
    ctx.Heap.Collect();
    AssertTrue('Detached prototypes are reclaimed without leak (' +
      IntToStr(initCount) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount()) + ')',
      ctx.Heap.GetObjectCount() <= initCount + 5);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestDeclarationValidationAndSwitchHoisting();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // 1. Function parameter vs body let/const collision is SyntaxError
    res := engine.Execute('function f(a) { let a = 1; return a; }');
    AssertFalse('Parameter redeclaration with let must be rejected', res.Success);
    res := engine.Execute('function f(a) { const a = 1; return a; }');
    AssertFalse('Parameter redeclaration with const must be rejected', res.Success);

    // 2. For loop let duplicate declaration is SyntaxError
    res := engine.Execute('for (let i = 0, i = 1; i < 2; i++) {}');
    AssertFalse('Duplicate let in for loop header must be rejected', res.Success);

    // 3. Catch parameter vs catch block let/const collision is SyntaxError
    res := engine.Execute('try { throw 1; } catch (e) { let e = 2; }');
    AssertFalse('Catch parameter redeclaration with let must be rejected', res.Success);
    res := engine.Execute('try { throw 1; } catch (e) { const e = 2; }');
    AssertFalse('Catch parameter redeclaration with const must be rejected', res.Success);

    // 4. Duplicate let across switch case clauses is SyntaxError
    res := engine.Execute('switch (1) { case 1: let x = 1; break; case 2: let x = 2; break; }');
    AssertFalse('Duplicate let across switch cases must be rejected', res.Success);

    // 5. Switch-case function declaration hoisting before textual declaration
    res := engine.Execute(
      'var r = 0;' +
      'switch (1) {' +
      '  case 1:' +
      '    r = f();' +
      '    break;' +
      '  function f() { return 42; }' +
      '}' +
      'r === 42;'
    );
    AssertTrue('Function declared in switch body is hoisted and callable before declaration', res.Success and res.BooleanValue);

    // 6. Valid shadowing cases that must continue to work
    // Parameter vs var
    res := engine.Execute('function f(a) { var a = 10; return a; } f(5) === 10;');
    AssertTrue('Parameter shadowed by var is valid', res.Success and res.BooleanValue);

    // Parameter vs inner block let
    res := engine.Execute('function f(a) { { let a = 20; } return a; } f(5) === 5;');
    AssertTrue('Parameter shadowed in inner block let is valid', res.Success and res.BooleanValue);

    // Catch param vs inner block let
    res := engine.Execute('var r = 0; try { throw 1; } catch (e) { { let e = 99; r = e; } } r === 99;');
    AssertTrue('Catch param shadowed in inner block let is valid', res.Success and res.BooleanValue);

    // For loop init let vs inner block let
    res := engine.Execute('var sum = 0; for (let i = 0; i < 2; i++) { let i = 10; sum += i; } sum === 20;');
    AssertTrue('For loop let shadowed in inner block let is valid', res.Success and res.BooleanValue);

    // 7. Cross-scope var/let conflicts (P0-04 / P0-07)
    // Function let + nested var
    res := engine.Execute('function f() { let x = 1; { var x = 2; } return x; } f();');
    AssertFalse('Function let + nested var must be rejected as SyntaxError', res.Success);

    // Function const + nested var
    res := engine.Execute('function f() { const x = 1; { var x = 2; } } f();');
    AssertFalse('Function const + nested var must be rejected as SyntaxError', res.Success);

    // Top-level let + block var
    res := engine.Execute('let x = 1; { var x = 2; }');
    AssertFalse('Top-level let + block var must be rejected as SyntaxError', res.Success);

    // Top-level const + block var
    res := engine.Execute('const x = 1; { var x = 2; }');
    AssertFalse('Top-level const + block var must be rejected as SyntaxError', res.Success);

    // Switch case var vs outer let
    res := engine.Execute('let x = 1; switch (1) { case 1: var x = 2; }');
    AssertFalse('Switch case var vs outer let must be rejected as SyntaxError', res.Success);

    // Switch case let vs switch case var
    res := engine.Execute('switch (1) { case 1: let x = 1; case 2: var x = 2; }');
    AssertFalse('Switch case let vs switch case var must be rejected as SyntaxError', res.Success);

    // Switch case var vs switch case let
    res := engine.Execute('switch (1) { case 1: var x = 1; case 2: let x = 2; }');
    AssertFalse('Switch case var vs switch case let must be rejected as SyntaxError', res.Success);

    // For loop let vs body var
    res := engine.Execute('for (let i = 0; i < 1; i++) { var i; }');
    AssertFalse('For loop let vs body var must be rejected as SyntaxError', res.Success);

    // For-in loop let vs body var
    res := engine.Execute('for (let x in {a:1}) { var x; }');
    AssertFalse('For-in loop let vs body var must be rejected as SyntaxError', res.Success);

    // For-of loop let vs body var
    res := engine.Execute('for (let x of [1]) { var x; }');
    AssertFalse('For-of loop let vs body var must be rejected as SyntaxError', res.Success);

    // 8. Cross-scope valid shadowing cases
    res := engine.Execute('function f(){ var x = 1; { let x = 2; } return x; } f() === 1;');
    AssertTrue('Outer var shadowed by inner block let is valid', res.Success and res.BooleanValue);

    res := engine.Execute('function f(){ { let x = 1; } var x = 2; return x; } f() === 2;');
    AssertTrue('Preceding block let followed by outer var is valid', res.Success and res.BooleanValue);

    res := engine.Execute('var r = 0; try { throw 1; } catch (e) { var e = 2; r = e; } r === 2;');
    AssertTrue('Catch parameter allows var of same name', res.Success and res.BooleanValue);

    res := engine.Execute('function f(a){ var a = 2; return a; } f(1) === 2;');
    AssertTrue('Parameter allows var of same name', res.Success and res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestArrayHolesAndLengthMutation();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // 1. An explicit undefined element is an own numeric property.
    res := engine.Execute(
      'var a = [undefined];' +
      'Object.keys(a).join(",") === "0" && a.hasOwnProperty(0) && (0 in a) && a[0] === undefined;'
    );
    AssertTrue('explicit undefined element', res.Success);
    AssertTrue('Explicit undefined is enumerated and present', res.BooleanValue);

    // 2. A hole is not an own property, even though it reads as undefined.
    res := engine.Execute(
      'var b = [1, , 3];' +
      'b.length === 3 && !(1 in b) && !b.hasOwnProperty(1) && b[1] === undefined && ' +
      'Object.keys(b).join(",") === "0,2";'
    );
    AssertTrue('array hole', res.Success);
    AssertTrue('Holes are skipped while reading as undefined', res.BooleanValue);

    // 3. A hole created by an array literal survives Object.values/entries.
    res := engine.Execute(
      'var c = [1, , 3];' +
      'Object.values(c).join(",") === "1,3" && Object.entries(c).length === 2;'
    );
    AssertTrue('holes in Object.values/entries', res.Success);
    AssertTrue('Object.values/entries skip holes', res.BooleanValue);

    // 4. Growing length extends with holes; shrinking drops elements.
    res := engine.Execute(
      'var d = [1, 2];' +
      'd.length = 5;' +
      'd.length === 5 && !(2 in d) && d[4] === undefined && Object.keys(d).join(",") === "0,1";'
    );
    AssertTrue('length grow', res.Success);
    AssertTrue('Extending length creates holes', res.BooleanValue);

    res := engine.Execute(
      'var e = [1, 2, 3];' +
      'e.length = 1;' +
      'e.length === 1 && e[1] === undefined && Object.keys(e).join(",") === "0";'
    );
    AssertTrue('length shrink', res.Success);
    AssertTrue('Shrinking length drops elements', res.BooleanValue);

    // 5. Assigning past the end creates holes in the gap.
    res := engine.Execute(
      'var f = [1];' +
      'f[3] = 4;' +
      'f.length === 4 && Object.keys(f).join(",") === "0,3";'
    );
    AssertTrue('index assignment past the end', res.Success);
    AssertTrue('Intermediate indices are holes', res.BooleanValue);

    // 6. delete leaves a hole and keeps the length.
    res := engine.Execute(
      'var g = [1, 2];' +
      'delete g[0];' +
      'g.length === 2 && !(0 in g) && Object.keys(g).join(",") === "1";'
    );
    AssertTrue('delete on an element', res.Success);
    AssertTrue('delete creates a hole', res.BooleanValue);

    // 7. for...in enumerates present indices only.
    res := engine.Execute(
      'var h = [1, , 3];' +
      'var hk = [];' +
      'for (var k in h) { hk.push(k); }' +
      'hk.join(",") === "0,2";'
    );
    AssertTrue('for...in over holes', res.Success);
    AssertTrue('for...in skips hole indices', res.BooleanValue);

    res := engine.Execute(
      'var i2 = [undefined];' +
      'var ik = [];' +
      'for (var k in i2) { ik.push(k); }' +
      'ik.join(",") === "0";'
    );
    AssertTrue('for...in over explicit undefined', res.Success);
    AssertTrue('for...in includes the explicit undefined index', res.BooleanValue);

    // 8. The Array length constructor creates a sparse array.
    res := engine.Execute(
      'var j = new Array(3);' +
      'j.length === 3 && Object.keys(j).length === 0 && !(0 in j);'
    );
    AssertTrue('new Array(n)', res.Success);
    AssertTrue('new Array(n) creates holes', res.BooleanValue);

    // 9. Invalid lengths are rejected the way ECMAScript does.
    res := engine.Execute('var k = [1, 2]; k.length = 1.5;');
    AssertFalse('fractional length', res.Success);
    AssertTrue('Fractional length raises RangeError', Pos('RangeError', res.ErrorMessage) > 0);

    res := engine.Execute('var l = [1, 2]; l.length = -1;');
    AssertFalse('negative length', res.Success);
    AssertTrue('Negative length raises RangeError', Pos('RangeError', res.ErrorMessage) > 0);

    // 10. Array.callbacks and JSON conversion over holes.
    res := engine.Execute(
      'var m = [1, , 3];' +
      'JSON.stringify(m) === "[1,null,3]" && String(m) === "1,,3";'
    );
    AssertTrue('hole string conversion', res.Success);
    AssertTrue('Holes render as empty text and null JSON', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestNewOnBoundFunctions();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // 1. The reported failure: new on a partially applied bound function.
    res := engine.Execute(
      'function C(x) { this.x = x; }' +
      'var B = C.bind(null, 7);' +
      '(new B()).x === 7;'
    );
    AssertTrue('new on a bound function succeeds', res.Success);
    AssertTrue('new ignores the bound this and passes the bound arguments', res.BooleanValue);

    // 2. Bound arguments come before the call arguments.
    res := engine.Execute(
      'function Sum(a, b) { this.v = a + b; }' +
      'var B = Sum.bind(null, 7);' +
      '(new B(3)).v === 10;'
    );
    AssertTrue('bound arguments are combined with call arguments', res.Success and res.BooleanValue);

    // 3. The instance inherits the target's prototype, not the bound function's.
    res := engine.Execute(
      'function C() {}' +
      'C.prototype.kind = "target";' +
      'var B = C.bind(null);' +
      'var o = new B();' +
      'o.kind === "target" && o.constructor === C;'
    );
    AssertTrue('new installs the target prototype', res.Success);
    AssertTrue('The instance inherits from the target prototype', res.BooleanValue);

    // 4. instanceof resolves through the target, for both names.
    res := engine.Execute(
      'function C(x) { this.x = x; }' +
      'var B = C.bind(null, 1);' +
      'var o = new B();' +
      '(o instanceof C) && (o instanceof B) && (o instanceof Object);'
    );
    AssertTrue('instanceof traverses the target prototype chain', res.Success and res.BooleanValue);

    // 5. Bound functions expose no own prototype, per ECMAScript.
    res := engine.Execute(
      'function C() {}' +
      'var B = C.bind(null);' +
      '!(B.hasOwnProperty("prototype")) && !("prototype" in B) &&' +
      'typeof B === "function" && Object.keys(B).length === 0;'
    );
    AssertTrue('bound functions have no own prototype', res.Success and res.BooleanValue);

    // 6. Calling a bound function still works, including through call/apply.
    res := engine.Execute(
      'function f(a, b) { return this.v + a + b; }' +
      'var g = f.bind({ v: 10 }, 1);' +
      '(g(2) === 13) && (g.call({ v: 100 }, 2) === 13) && (g.apply({ v: 100 }, [2]) === 13);'
    );
    AssertTrue('calls of bound functions ignore the receiver', res.Success and res.BooleanValue);

    // 7. Chained binds keep the first bound this and prepend every argument set.
    res := engine.Execute(
      'function f(a, b, c) { return this.v + a + b + c; }' +
      'var g = f.bind({ v: 1 }, 2).bind({ v: 100 }, 3);' +
      'g(4) === 10;'
    );
    AssertTrue('chained binds compose', res.Success and res.BooleanValue);

    // 8. An object returned by the target replaces the instance.
    res := engine.Execute(
      'function C() { return { z: 3 }; }' +
      'var B = C.bind(null);' +
      '(new B()).z === 3;'
    );
    AssertTrue('an object return value replaces the bound instance', res.Success and res.BooleanValue);

    // 9. Native constructors can be bound too.
    res := engine.Execute(
      'var B = Array.bind(null);' +
      'new B(3).length === 3;'
    );
    AssertTrue('native constructors can be bound', res.Success and res.BooleanValue);

    // 10. Arrow targets are not constructable, so neither is the bound function.
    res := engine.Execute(
      'var B = (() => 1).bind(null);' +
      'var caught = "";' +
      'try { new B(); } catch (e) { caught = e.name; }' +
      'caught === "TypeError";'
    );
    AssertTrue('an arrow target is not constructable', res.Success and res.BooleanValue);

    // 11. Non-function values cannot be bound at all.
    res := engine.Execute(
      'var caught = "";' +
      'try { var B = (5).bind(null); } catch (e) { caught = e.name; }' +
      'caught === "TypeError";'
    );
    AssertTrue('binding a non-function throws TypeError', res.Success and res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestBoundFunctionConstructionLifetime();
var
  ctx: TFloriaJSContext;
  objects, environments, i: Integer;
begin
  ctx := TFloriaJSContext.Create(nil);
  try
    { A bound function owns its target, the bound this, and every bound
      argument, so repeated binding and construction must not accumulate
      objects or environments. }
    ctx.Evaluate(
      'function C(x) { this.x = x; }' +
      'var B = C.bind(null, 7);' +
      'var o = new B();' +
      'B = null; o = null; C = null;');
    ctx.Evaluate('0;');
    objects := ctx.Heap.GetObjectCount;
    environments := ctx.Heap.GetEnvironmentCount;

    for i := 1 to 200 do
      ctx.Evaluate(
        'function C(x) { this.x = x; }' +
        'var B = C.bind(null, 7);' +
        'var o = new B();' +
        'B = null; o = null; C = null;');
    ctx.Evaluate('0;');

    AssertTrue('Bound functions must not accumulate objects (' +
      IntToStr(objects) + ' -> ' + IntToStr(ctx.Heap.GetObjectCount) + ')',
      ctx.Heap.GetObjectCount = objects);
    AssertTrue('Bound construction must not accumulate environments (' +
      IntToStr(environments) + ' -> ' + IntToStr(ctx.Heap.GetEnvironmentCount) + ')',
      ctx.Heap.GetEnvironmentCount = environments);
  finally
    ctx.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestNumberFormattingParity();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // 1. The three reported failures.
    res := engine.Execute('String(1e20) === "100000000000000000000";');
    AssertTrue('String(1e20) succeeds', res.Success);
    AssertTrue('1e20 prints in fixed notation', res.BooleanValue);

    res := engine.Execute('String(1e-7) === "1e-7";');
    AssertTrue('String(1e-7) succeeds', res.Success);
    AssertTrue('1e-7 uses lowercase exponent without a plus', res.BooleanValue);

    res := engine.Execute('(0.1 + 0.2).toString() === "0.30000000000000004";');
    AssertTrue('0.1 + 0.2 succeeds', res.Success);
    AssertTrue('Shortest round-tripping digits are preserved', res.BooleanValue);

    // 2. Exponent thresholds: fixed for 1e-6, scientific from 1e-7.
    res := engine.Execute(
      'String(1e-6) === "0.000001" && String(1e-7) === "1e-7" && ' +
      'String(1e20) === "100000000000000000000" && String(1e21) === "1e+21";'
    );
    AssertTrue('Exponent thresholds succeed', res.Success);
    AssertTrue('Fixed/scientific switch matches ECMAScript', res.BooleanValue);

    // 3. Positive exponents carry an explicit plus sign.
    res := engine.Execute('String(1e21) === "1e+21" && String(1.5e300).indexOf("e+300") > 0;');
    AssertTrue('Positive exponent notation', res.Success and res.BooleanValue);

    // 4. Integers below the safe range print without an exponent or a fraction.
    res := engine.Execute(
      'String(9007199254740991) === "9007199254740991" && ' +
      'String(0) === "0" && String(-42) === "-42" && String(1.5) === "1.5";'
    );
    AssertTrue('Integers print exactly', res.Success and res.BooleanValue);

    // 5. Zero, NaN, and the infinities.
    res := engine.Execute(
      'String(-0) === "0" && String(NaN) === "NaN" && ' +
      'String(Infinity) === "Infinity" && String(-Infinity) === "-Infinity";'
    );
    AssertTrue('Special values print as ECMAScript specifies', res.Success and res.BooleanValue);

    // 6. The extremes of the double range round-trip through their own text.
    res := engine.Execute(
      'String(5e-324) === "5e-324" && ' +
      'String(1.7976931348623157e308) === "1.7976931348623157e+308";'
    );
    AssertTrue('Extreme doubles print shortest form', res.Success and res.BooleanValue);

    // 7. A value whose shortest form needs all 17 digits.
    res := engine.Execute('String(0.1 + 0.7) === "0.7999999999999999";');
    AssertTrue('17 significant digits when required', res.Success and res.BooleanValue);

    // 8. JSON uses the same number form.
    res := engine.Execute(
      'JSON.stringify(1e20) === "100000000000000000000" && ' +
      'JSON.stringify([1e21, 1e-7]) === "[1e+21,1e-7]";'
    );
    AssertTrue('JSON number serialisation matches String()', res.Success and res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestNumberParsingParity();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // 1. Round trip through String() for awkward values.
    res := engine.Execute(
      'var xs = [0.1 + 0.2, 1e20, 1e-7, 1 / 3, 5e-324, 1.7976931348623157e308];' +
      'var ok = true;' +
      'for (var i = 0; i < xs.length; i++) { if (Number(String(xs[i])) !== xs[i]) ok = false; }' +
      'ok;'
    );
    AssertTrue('Number(String(x)) round trip succeeds', res.Success);
    AssertTrue('Every value round-trips exactly', res.BooleanValue);

    // 2. Values the host parser rounds incorrectly must still parse correctly.
    res := engine.Execute(
      'Number("1e126") === 1e126 && ' +
      'Number("2.2250738585072014e-308") === 2.2250738585072014e-308;'
    );
    AssertTrue('Correctly rounded parsing', res.Success and res.BooleanValue);

    // 3. Subnormal boundaries.
    res := engine.Execute('Number("5e-324") === 5e-324 && Number("1e-400") === 0;');
    AssertTrue('Subnormal and underflow parsing', res.Success and res.BooleanValue);

    // 4. Overflow saturates to Infinity.
    res := engine.Execute('Number("1e309") === Infinity;');
    AssertTrue('Overflow saturates to Infinity', res.Success and res.BooleanValue);

    // 5. Existing forms still work.
    res := engine.Execute(
      'Number("0x10") === 16 && Number("0b101") === 5 && Number("0o17") === 15 && ' +
      'Number("  12  ") === 12 && Number("") === 0 && ' +
      'isNaN(Number("abc")) && isNaN(Number("1e"));'
    );
    AssertTrue('Other Number() forms still parse', res.Success and res.BooleanValue);

    // 6. Trailing junk is rejected, leading/trailing space is not.
    res := engine.Execute('isNaN(Number("12px")) && Number(" 1.5 ") === 1.5;');
    AssertTrue('Whitespace and junk handling', res.Success and res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestNumberRadixToString();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('(255).toString(16) === "ff" && (255).toString(2) === "11111111";');
    AssertTrue('Integer radix conversion', res.Success and res.BooleanValue);

    res := engine.Execute('(35).toString(36) === "z" && (0).toString(2) === "0";');
    AssertTrue('Radix 36 and zero', res.Success and res.BooleanValue);

    res := engine.Execute('(1.5).toString(2) === "1.1" && (0.5).toString(16) === "0.8";');
    AssertTrue('Fractional radix conversion', res.Success and res.BooleanValue);

    res := engine.Execute('(-255).toString(16) === "-ff";');
    AssertTrue('Negative radix conversion', res.Success and res.BooleanValue);

    res := engine.Execute('(255).toString() === "255" && (255).toString(10) === "255";');
    AssertTrue('Default radix is ten', res.Success and res.BooleanValue);

    res := engine.Execute(
      'var caught = "";' +
      'try { (255).toString(1); } catch (e) { caught = e.name; }' +
      'caught === "RangeError";'
    );
    AssertTrue('Out-of-range radix throws RangeError', res.Success and res.BooleanValue);

    res := engine.Execute(
      'var caught = "";' +
      'try { (255).toString(37); } catch (e) { caught = e.name; }' +
      'caught === "RangeError";'
    );
    AssertTrue('Radix above 36 throws RangeError', res.Success and res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestDeleteSemantics();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // 1. The reported failure: deleting an undeclared name is not an error.
    res := engine.Execute('delete undeclaredName;');
    AssertTrue('delete of an undeclared name succeeds', res.Success);
    AssertTrue('delete of an undeclared name is true', res.BooleanValue);

    // 2. It must not create a binding either.
    res := engine.Execute(
      'delete undeclaredName;' +
      'typeof undeclaredName === "undefined";'
    );
    AssertTrue('delete does not create a binding', res.Success and res.BooleanValue);

    // 3. A declared var is non-deletable: false, and the binding survives.
    res := engine.Execute(
      'var x = 1;' +
      'var r = delete x;' +
      'r === false && x === 1;'
    );
    AssertTrue('delete of a declared var is false and keeps it', res.Success and res.BooleanValue);

    // 4. let and const bindings behave the same way.
    res := engine.Execute(
      'let a = 1; const b = 2;' +
      '(delete a) === false && (delete b) === false && a === 1 && b === 2;'
    );
    AssertTrue('delete of let/const is false and keeps them', res.Success and res.BooleanValue);

    // 5. Function parameters are declared bindings too.
    res := engine.Execute('function f(p) { return delete p; } f(1) === false;');
    AssertTrue('delete of a parameter is false', res.Success and res.BooleanValue);

    // 6. A local variable inside a function.
    res := engine.Execute(
      'function f() { var y = 1; return (delete y) === false && y === 1; } f();'
    );
    AssertTrue('delete of a function local is false', res.Success and res.BooleanValue);

    // 7. Grouping does not change the target.
    res := engine.Execute(
      'var g = 1; (delete (g)) === false && (delete (undeclaredOther)) === true;'
    );
    AssertTrue('grouped delete targets the same binding', res.Success and res.BooleanValue);

    // 8. Non-reference operands are evaluated and yield true.
    res := engine.Execute('(delete 1) === true && (delete "s") === true && (delete null) === true;');
    AssertTrue('delete of a non-reference is true', res.Success and res.BooleanValue);

    // 9. Object and array properties still delete.
    res := engine.Execute(
      'var o = { a: 1 };' +
      'var d = delete o.a;' +
      'd === true && !("a" in o) && o.a === undefined;'
    );
    AssertTrue('delete removes an own property', res.Success and res.BooleanValue);

    res := engine.Execute(
      'var arr = [1, 2, 3];' +
      'var d = delete arr[1];' +
      'd === true && arr.length === 3 && !(1 in arr) && arr[1] === undefined;'
    );
    AssertTrue('delete leaves an array hole', res.Success and res.BooleanValue);

    // 10. Deleting a missing property is true.
    res := engine.Execute('var o = {}; (delete o.missing) === true;');
    AssertTrue('delete of a missing property is true', res.Success and res.BooleanValue);

    // 11. A member expression on null/undefined fails while being evaluated.
    res := engine.Execute(
      'var caught = "";' +
      'try { delete null.x; } catch (e) { caught = e.name; }' +
      'caught === "TypeError";'
    );
    AssertTrue('delete on null throws TypeError', res.Success and res.BooleanValue);

    res := engine.Execute(
      'var caught = "";' +
      'try { delete undefined.x; } catch (e) { caught = e.name; }' +
      'caught === "TypeError";'
    );
    AssertTrue('delete on undefined throws TypeError', res.Success and res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority1Test.TestDebuggerAndWith();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // 1. The reported failure: `debugger` must not be an undeclared read.
    res := engine.Execute('debugger;');
    AssertTrue('debugger is accepted', res.Success);

    // 2. It is a no-op that does not disturb the surrounding program.
    res := engine.Execute('debugger; 1;');
    AssertTrue('debugger is a no-op', res.Success);
    AssertEquals('Execution continues after debugger', '1', res.StringValue);

    res := engine.Execute('function g() { debugger; return 5; } g();');
    AssertTrue('debugger inside a function', res.Success);
    AssertEquals('debugger does not change the result', '5', res.StringValue);

    res := engine.Execute('{ debugger; } 1;');
    AssertTrue('debugger inside a block', res.Success);

    // 3. It is a statement, not an identifier, so it cannot be used as one.
    res := engine.Execute('var debugger = 1;');
    AssertFalse('debugger is a reserved word', res.Success);

    // 4. `with` is unsupported and must fail at parse time, not at run time as
    //    an undeclared name.
    res := engine.Execute('with ({}) { }');
    AssertFalse('with is rejected', res.Success);
    AssertTrue('with fails as a parse error, not a ReferenceError',
      (Pos('not supported', res.ErrorMessage) > 0) and
      (Pos('ReferenceError', res.ErrorMessage) = 0));
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestVoidOperator();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // 1. `void` is an operator, not an identifier.
    res := engine.Execute('void 0;');
    AssertTrue('void 0 succeeds', res.Success);
    AssertEquals('void 0 is undefined', 'undefined', res.StringValue);

    res := engine.Execute('typeof void 0 === "undefined";');
    AssertTrue('typeof void 0', res.Success and res.BooleanValue);

    res := engine.Execute('(void 0) === undefined;');
    AssertTrue('void yields undefined', res.Success and res.BooleanValue);

    // 2. The operand is evaluated for its side effects and then discarded.
    res := engine.Execute('var n = 0; void (n = 1); n;');
    AssertTrue('void evaluates its operand', res.Success);
    AssertEquals('void keeps the side effect', '1', res.StringValue);

    res := engine.Execute('var n = 0; void n; n;');
    AssertTrue('void of a plain read', res.Success);
    AssertEquals('void does not change the variable', '0', res.StringValue);

    // 3. `void` binds tighter than a binary operator, so `void 1 + 2` is
    //    `undefined + 2`, which is NaN.
    res := engine.Execute('isNaN(void 1 + 2);');
    AssertTrue('void binds tighter than +', res.Success and res.BooleanValue);

    // 4. It is an operator in expression position, including arguments and
    //    property values.
    res := engine.Execute('function f(x) { return typeof x; } f(void 0) === "undefined";');
    AssertTrue('void as an argument', res.Success and res.BooleanValue);

    res := engine.Execute('var o = {a: void 0}; typeof o.a === "undefined";');
    AssertTrue('void as a property value', res.Success and res.BooleanValue);

    // 5. A missing operand is a syntax error, as in ECMAScript.
    res := engine.Execute('void;');
    AssertFalse('void without an operand is rejected', res.Success);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestLogicalAssignmentIdentifiers();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // &&= assigns only when the current value is truthy.
    res := engine.Execute('var a = 1; a &&= 2; a;');
    AssertTrue('&&= on a truthy value', res.Success);
    AssertEquals('&&= assigns', '2', res.StringValue);

    res := engine.Execute('var a = 0; a &&= 2; a;');
    AssertTrue('&&= on a falsy value', res.Success);
    AssertEquals('&&= keeps a falsy value', '0', res.StringValue);

    // ||= assigns only when the current value is falsy.
    res := engine.Execute('var a = 0; a ||= 5; a;');
    AssertTrue('||= on a falsy value', res.Success);
    AssertEquals('||= assigns', '5', res.StringValue);

    res := engine.Execute('var a = 1; a ||= 5; a;');
    AssertTrue('||= on a truthy value', res.Success);
    AssertEquals('||= keeps a truthy value', '1', res.StringValue);

    // ??= assigns only when the current value is null or undefined.
    res := engine.Execute('var a = null; a ??= 4; a;');
    AssertTrue('??= on null', res.Success);
    AssertEquals('??= assigns on null', '4', res.StringValue);

    res := engine.Execute('var a = 0; a ??= 4; a;');
    AssertTrue('??= on zero', res.Success);
    AssertEquals('??= keeps a non-nullish falsy value', '0', res.StringValue);

    // The expression value is the assigned or retained value.
    res := engine.Execute('var a = 1; var b = (a &&= 5); b === 5 && a === 5;');
    AssertTrue('&&= yields the new value', res.Success and res.BooleanValue);

    res := engine.Execute('var a = 0; var b = (a ||= 5); b === 5 && a === 5;');
    AssertTrue('||= yields the new value', res.Success and res.BooleanValue);

    // Truthiness follows JavaScript rules, not just zero/non-zero.
    res := engine.Execute('var a = ""; a ||= "d"; a;');
    AssertTrue('||= on an empty string', res.Success);
    AssertEquals('||= treats "" as falsy', 'd', res.StringValue);

    res := engine.Execute('var a = NaN; a ||= 3; a;');
    AssertTrue('||= on NaN', res.Success);
    AssertEquals('||= treats NaN as falsy', '3', res.StringValue);

    // No spaces are required around the operator.
    res := engine.Execute('var a = 1; a&&=2; a;');
    AssertTrue('&&= without spaces', res.Success);
    AssertEquals('&&= lexes without spaces', '2', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestLogicalAssignmentMembers();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('var o = {a: 1}; o.a &&= 2; o.a;');
    AssertTrue('named member &&=', res.Success);
    AssertEquals('named member &&= assigns', '2', res.StringValue);

    res := engine.Execute('var o = {a: 0}; o.a &&= 2; o.a;');
    AssertTrue('named member &&= skips', res.Success);
    AssertEquals('named member &&= keeps falsy', '0', res.StringValue);

    res := engine.Execute('var o = {a: 0}; o.a ||= 7; o.a;');
    AssertTrue('named member ||=', res.Success);
    AssertEquals('named member ||= assigns', '7', res.StringValue);

    res := engine.Execute('var o = {a: 1}; o.a ||= 7; o.a;');
    AssertTrue('named member ||= skips', res.Success);
    AssertEquals('named member ||= keeps truthy', '1', res.StringValue);

    res := engine.Execute('var o = {}; o.a ??= 9; o.a;');
    AssertTrue('named member ??=', res.Success);
    AssertEquals('named member ??= assigns on undefined', '9', res.StringValue);

    // Computed members take the same path.
    res := engine.Execute('var o = {a: 1}; o["a"] &&= 3; o.a;');
    AssertTrue('computed member &&=', res.Success);
    AssertEquals('computed member &&= assigns', '3', res.StringValue);

    res := engine.Execute('var o = {a: 0}; o["a"] ||= 3; o.a;');
    AssertTrue('computed member ||=', res.Success);
    AssertEquals('computed member ||= assigns', '3', res.StringValue);

    // The base expression is evaluated once.
    res := engine.Execute(
      'var n = 0;' +
      'var o = {a: 1};' +
      'function base() { n++; return o; }' +
      'base().a &&= 2;' +
      'n === 1 && o.a === 2;'
    );
    AssertTrue('member base is evaluated once', res.Success and res.BooleanValue);

    // A member of null still throws, as the reference evaluation requires.
    res := engine.Execute(
      'var caught = "";' +
      'try { var o = null; o.a &&= 1; } catch (e) { caught = e.name; }' +
      'caught === "TypeError";'
    );
    AssertTrue('member &&= on null throws TypeError', res.Success and res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestLogicalAssignmentShortCircuit();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // The right-hand side must not be evaluated when the assignment is
    // skipped; a side effect makes that observable.
    res := engine.Execute('var n = 0; var a = 0; a &&= (n = 1); n;');
    AssertTrue('&&= short-circuits', res.Success);
    AssertEquals('&&= does not evaluate the RHS', '0', res.StringValue);

    res := engine.Execute('var n = 0; var a = 1; a ||= (n = 1); n;');
    AssertTrue('||= short-circuits', res.Success);
    AssertEquals('||= does not evaluate the RHS', '0', res.StringValue);

    res := engine.Execute('var n = 0; var a = 5; a ??= (n = 1); n;');
    AssertTrue('??= short-circuits', res.Success);
    AssertEquals('??= does not evaluate the RHS', '0', res.StringValue);

    // When it does assign, the RHS runs exactly once.
    res := engine.Execute('var n = 0; var a = 1; a &&= (n = n + 1); n;');
    AssertTrue('&&= evaluates the RHS when assigning', res.Success);
    AssertEquals('&&= evaluates the RHS once', '1', res.StringValue);

    res := engine.Execute('var n = 0; var a = 0; a ||= (n = n + 1); n;');
    AssertTrue('||= evaluates the RHS when assigning', res.Success);
    AssertEquals('||= evaluates the RHS once', '1', res.StringValue);

    // A throwing RHS proves it is not evaluated when skipped.
    res := engine.Execute(
      'var a = 0;' +
      'var ok = true;' +
      'try { a &&= (function() { throw new Error("boom"); })(); } catch (e) { ok = false; }' +
      'ok === true && a === 0;'
    );
    AssertTrue('&&= never runs a skipped throwing RHS', res.Success and res.BooleanValue);

    // Member targets short-circuit the same way.
    res := engine.Execute('var n = 0; var o = {a: 0}; o.a &&= (n = 1); n;');
    AssertTrue('member &&= short-circuits', res.Success);
    AssertEquals('member &&= does not evaluate the RHS', '0', res.StringValue);

    res := engine.Execute('var n = 0; var o = {a: 1}; o.a ||= (n = 1); n;');
    AssertTrue('member ||= short-circuits', res.Success);
    AssertEquals('member ||= does not evaluate the RHS', '0', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestBigIntLiteralRejection();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  { P2-09 replaced the rejection with real BigInt support; these assertions
    cover the literal forms that used to be refused. }
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('typeof 10n;');
    AssertTrue('BigInt literal', res.Success);
    AssertEquals('a suffixed literal is a bigint', 'bigint', res.StringValue);

    res := engine.Execute('var n = 0; var b = 10n; b;');
    AssertTrue('BigInt literal with an n in scope', res.Success);
    AssertEquals('the suffix is not an identifier', '10', res.StringValue);

    res := engine.Execute('0x10n;');
    AssertTrue('hex BigInt', res.Success);
    AssertEquals('hex converts to decimal', '16', res.StringValue);

    res := engine.Execute('0b101n;');
    AssertTrue('binary BigInt', res.Success);
    AssertEquals('binary converts to decimal', '5', res.StringValue);

    res := engine.Execute('0o17n;');
    AssertTrue('octal BigInt', res.Success);
    AssertEquals('octal converts to decimal', '15', res.StringValue);

    // A fractional or exponent BigInt literal is invalid.
    res := engine.Execute('var b = 1.5n;');
    AssertFalse('fractional BigInt literal is rejected', res.Success);

    // A plain `n` in identifier position is still ordinary.
    res := engine.Execute('var n = 5; n;');
    AssertTrue('a variable named n still works', res.Success);
    AssertEquals('a variable named n keeps its value', '5', res.StringValue);

    res := engine.Execute('var name = 1; name + 1;');
    AssertTrue('an identifier starting with n still works', res.Success);
    AssertEquals('identifiers starting with n are unaffected', '2', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestBigIntArithmetic();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('1n + 2n;');
    AssertTrue('addition', res.Success);
    AssertEquals('1n + 2n', '3', res.StringValue);

    res := engine.Execute('10n - 3n;');
    AssertTrue('subtraction', res.Success);
    AssertEquals('10n - 3n', '7', res.StringValue);

    res := engine.Execute('6n * 7n;');
    AssertTrue('multiplication', res.Success);
    AssertEquals('6n * 7n', '42', res.StringValue);

    // Division truncates toward zero.
    res := engine.Execute('100n / 7n;');
    AssertTrue('division', res.Success);
    AssertEquals('100n / 7n truncates', '14', res.StringValue);

    res := engine.Execute('-7n / 2n;');
    AssertTrue('negative division', res.Success);
    AssertEquals('division truncates toward zero', '-3', res.StringValue);

    // The remainder takes the dividend's sign.
    res := engine.Execute('100n % 7n;');
    AssertTrue('remainder', res.Success);
    AssertEquals('100n % 7n', '2', res.StringValue);

    res := engine.Execute('7n % -2n;');
    AssertTrue('remainder sign', res.Success);
    AssertEquals('the remainder keeps the dividend sign', '1', res.StringValue);

    res := engine.Execute('5n ** 2n;');
    AssertTrue('exponentiation', res.Success);
    AssertEquals('5n ** 2n', '25', res.StringValue);

    res := engine.Execute('-5n;');
    AssertTrue('negation', res.Success);
    AssertEquals('unary minus', '-5', res.StringValue);

    // Precision is arbitrary: this exceeds a double's exact range.
    res := engine.Execute('99999999999999999999n + 1n;');
    AssertTrue('arbitrary precision', res.Success);
    AssertEquals('large addition is exact', '100000000000000000000', res.StringValue);

    res := engine.Execute('123456789012345678901234567890n * 2n;');
    AssertTrue('large multiplication', res.Success);
    AssertEquals('large multiplication is exact', '246913578024691357802469135780', res.StringValue);

    // Division by zero is a RangeError.
    res := engine.Execute('1n / 0n;');
    AssertFalse('division by zero', res.Success);
    AssertTrue('division by zero is a RangeError', Pos('RangeError', res.ErrorMessage) > 0);

    // Mixing with a Number is a TypeError.
    res := engine.Execute('1n + 1;');
    AssertFalse('mixed arithmetic is rejected', res.Success);
    AssertTrue('mixing is a TypeError', Pos('TypeError', res.ErrorMessage) > 0);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestBigIntComparisonAndConversion();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('1n < 2n;');
    AssertTrue('relational', res.Success and res.BooleanValue);

    res := engine.Execute('2n < 1n;');
    AssertTrue('relational false', res.Success);
    AssertFalse('2n < 1n is false', res.BooleanValue);

    res := engine.Execute('1n === 1n;');
    AssertTrue('strict equality', res.Success and res.BooleanValue);

    res := engine.Execute('1n === 1;');
    AssertTrue('strict equality across kinds', res.Success);
    AssertFalse('1n === 1 is false', res.BooleanValue);

    // Loose equality coerces, so a BigInt equals an equal Number.
    res := engine.Execute('1n == 1;');
    AssertTrue('loose equality', res.Success and res.BooleanValue);

    res := engine.Execute('2n == 2.5;');
    AssertTrue('loose equality with a fraction', res.Success);
    AssertFalse('2n == 2.5 is false', res.BooleanValue);

    res := engine.Execute('1n == "1";');
    AssertTrue('loose equality with a string', res.Success and res.BooleanValue);

    // Conversion.
    res := engine.Execute('BigInt(5);');
    AssertTrue('BigInt from number', res.Success);
    AssertEquals('BigInt(5)', '5', res.StringValue);

    res := engine.Execute('BigInt("42");');
    AssertTrue('BigInt from string', res.Success);
    AssertEquals('BigInt("42")', '42', res.StringValue);

    res := engine.Execute('BigInt(true);');
    AssertTrue('BigInt from boolean', res.Success);
    AssertEquals('BigInt(true)', '1', res.StringValue);

    res := engine.Execute('BigInt(1.5);');
    AssertFalse('BigInt from a fraction is rejected', res.Success);
    AssertTrue('a fractional conversion is a RangeError', Pos('RangeError', res.ErrorMessage) > 0);

    // String conversion prints the digits exactly.
    res := engine.Execute('String(99999999999999999999n);');
    AssertTrue('toString', res.Success);
    AssertEquals('the digits are exact', '99999999999999999999', res.StringValue);

    res := engine.Execute('"" + 1n;');
    AssertTrue('string concatenation', res.Success);
    AssertEquals('concatenation converts to digits', '1', res.StringValue);

    // BigInt is a conversion function, not a constructor.
    res := engine.Execute('new BigInt(5);');
    AssertFalse('new BigInt is rejected', res.Success);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestPromiseConstructor();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // `Promise` is a constructor function, not a plain object.
    res := engine.Execute('typeof Promise;');
    AssertTrue('Promise is a function', res.Success);
    AssertEquals('typeof Promise', 'function', res.StringValue);

    res := engine.Execute('new Promise(function(r){ r(1); }) instanceof Object;');
    AssertTrue('new Promise builds an object', res.Success and res.BooleanValue);

    // The executor runs synchronously and receives two functions.
    res := engine.Execute(
      'var seen = "";' +
      'new Promise(function(res, rej){ seen = typeof res + "/" + typeof rej; });' +
      'seen;'
    );
    AssertTrue('executor receives resolve/reject', res.Success);
    AssertEquals('both callbacks are functions', 'function/function', res.StringValue);

    res := engine.Execute('var n = 0; new Promise(function(r){ n = 5; r(); }); n;');
    AssertTrue('executor runs synchronously', res.Success);
    AssertEquals('executor side effect is visible immediately', '5', res.StringValue);

    // A non-callable executor is a TypeError.
    res := engine.Execute('new Promise();');
    AssertFalse('missing executor is rejected', res.Success);
    AssertTrue('missing executor is a TypeError', Pos('TypeError', res.ErrorMessage) > 0);

    res := engine.Execute('new Promise(1);');
    AssertFalse('non-function executor is rejected', res.Success);

    // The statics still work and still hang off the same object.
    res := engine.Execute(
      'typeof Promise.resolve === "function" && typeof Promise.reject === "function" && ' +
      'typeof Promise.all === "function" && typeof Promise.race === "function";'
    );
    AssertTrue('Promise statics are present', res.Success and res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestPromiseCallbacksRun();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // The job runner used to be missing, so no callback ever ran. These assert
    // the observable result of each reaction kind.
    res := engine.Execute(
      'var out = "";' +
      'new Promise(function(r){ r(42); }).then(function(v){ out = "got " + v; });'
    );
    AssertTrue('then registers', res.Success);
    res := engine.Execute('out;');
    AssertEquals('then callback runs', 'got 42', res.StringValue);

    res := engine.Execute(
      'var o = "";' +
      'new Promise(function(_, j){ j("no"); }).catch(function(e){ o = "err " + e; });'
    );
    AssertTrue('catch registers', res.Success);
    res := engine.Execute('o;');
    AssertEquals('catch callback runs', 'err no', res.StringValue);

    // A throwing executor rejects rather than propagating.
    res := engine.Execute(
      'var o = "";' +
      'new Promise(function(){ throw new Error("boom"); })' +
      '.catch(function(e){ o = e.message; });'
    );
    AssertTrue('throwing executor is caught', res.Success);
    res := engine.Execute('o;');
    AssertEquals('a throw rejects the promise', 'boom', res.StringValue);

    // First settlement wins.
    res := engine.Execute(
      'var o = "";' +
      'new Promise(function(r){ r(1); r(2); }).then(function(v){ o = v; });'
    );
    AssertTrue('double resolve', res.Success);
    res := engine.Execute('o;');
    AssertEquals('the first settlement wins', '1', res.StringValue);

    res := engine.Execute(
      'var o = "";' +
      'new Promise(function(r, j){ r(1); j(2); }).then(function(v){ o = "ok" + v; });'
    );
    AssertTrue('resolve then reject', res.Success);
    res := engine.Execute('o;');
    AssertEquals('reject after resolve is ignored', 'ok1', res.StringValue);

    // Chains, pass-through, and adoption.
    res := engine.Execute(
      'var o = "";' +
      'Promise.resolve(1).then(function(v){ return v + 1; }).then(function(v){ o = v; });'
    );
    AssertTrue('chained then', res.Success);
    res := engine.Execute('o;');
    AssertEquals('values flow through the chain', '2', res.StringValue);

    res := engine.Execute(
      'var o = ""; Promise.resolve(6).then(null).then(function(v){ o = v; });'
    );
    AssertTrue('missing handler', res.Success);
    res := engine.Execute('o;');
    AssertEquals('a missing handler passes the value through', '6', res.StringValue);

    res := engine.Execute(
      'var o = "";' +
      'new Promise(function(r){ r(Promise.resolve(4)); }).then(function(v){ o = v; });'
    );
    AssertTrue('resolving with a promise', res.Success);
    res := engine.Execute('o;');
    AssertEquals('resolving with a promise adopts it', '4', res.StringValue);

    // A throw inside a handler rejects the child.
    res := engine.Execute(
      'var o = "";' +
      'Promise.resolve(1).then(function(){ throw new Error("t"); })' +
      '.catch(function(e){ o = e.message; });'
    );
    AssertTrue('throw inside then', res.Success);
    res := engine.Execute('o;');
    AssertEquals('a throw in a handler rejects the child', 't', res.StringValue);

    // finally runs and forwards the original settlement.
    res := engine.Execute(
      'var o = ""; Promise.resolve(2).finally(function(){ o = "fin"; });'
    );
    AssertTrue('finally registers', res.Success);
    res := engine.Execute('o;');
    AssertEquals('finally callback runs', 'fin', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestPromiseAwaitIntegration();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // `await` depends on the same job queue, so it is a good end-to-end check.
    res := engine.Execute(
      'var out = "";' +
      'async function f() { var v = await Promise.resolve(3); out = "a" + v; }' +
      'f();'
    );
    AssertTrue('await on Promise.resolve', res.Success);
    res := engine.Execute('out;');
    AssertEquals('await resumes with the value', 'a3', res.StringValue);

    res := engine.Execute(
      'var o = "";' +
      'async function g() { o = await new Promise(function(r){ r(8); }); }' +
      'g();'
    );
    AssertTrue('await on new Promise', res.Success);
    res := engine.Execute('o;');
    AssertEquals('await resolves a constructed promise', '8', res.StringValue);

    res := engine.Execute(
      'var o = "";' +
      'async function h() { try { await Promise.reject("bad"); } catch (e) { o = "caught " + e; } }' +
      'h();'
    );
    AssertTrue('await on a rejection', res.Success);
    res := engine.Execute('o;');
    AssertEquals('await throws the rejection', 'caught bad', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestJSONStringifyParity();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // Getters are invoked, as ECMAScript property access requires.
    res := engine.Execute('JSON.stringify({get x(){ return 1; }});');
    AssertTrue('getter is invoked', res.Success);
    AssertEquals('getter value is serialised', '{"x":1}', res.StringValue);

    // toJSON is called, with the property key.
    res := engine.Execute('JSON.stringify({toJSON: function(){ return 5; }});');
    AssertTrue('toJSON on the root', res.Success);
    AssertEquals('toJSON result replaces the value', '5', res.StringValue);

    res := engine.Execute('JSON.stringify({a: {toJSON: function(k){ return "k:" + k; }}});');
    AssertTrue('toJSON receives the key', res.Success);
    AssertEquals('toJSON is passed the property name', '{"a":"k:a"}', res.StringValue);

    res := engine.Execute('JSON.stringify({x: {toJSON: function(){ return [1, 2]; }}});');
    AssertTrue('toJSON may return a structure', res.Success);
    AssertEquals('toJSON result is serialised recursively', '{"x":[1,2]}', res.StringValue);

    // A function replacer replaces every value, starting from the root.
    res := engine.Execute('JSON.stringify({a: 1}, function(k, v){ return 9; });');
    AssertTrue('replacer runs', res.Success);
    AssertEquals('replacer result replaces the value', '9', res.StringValue);

    res := engine.Execute(
      'JSON.stringify({a: 1}, function(k, v){ return k === "" ? v : undefined; });'
    );
    AssertTrue('replacer can drop members', res.Success);
    AssertEquals('returning undefined omits the member', '{}', res.StringValue);

    res := engine.Execute(
      'JSON.stringify([1, 2], function(k, v){ return typeof v === "number" ? v * 2 : v; });'
    );
    AssertTrue('replacer on arrays', res.Success);
    AssertEquals('replacer applies to elements', '[2,4]', res.StringValue);

    // A key-array replacer filters object properties.
    res := engine.Execute('JSON.stringify({a: 1, b: 2}, ["b"]);');
    AssertTrue('key-array replacer', res.Success);
    AssertEquals('only listed keys are emitted', '{"b":2}', res.StringValue);

    // undefined and functions are omitted from objects but become null in arrays.
    res := engine.Execute('JSON.stringify({a: undefined, b: function(){}, c: 1});');
    AssertTrue('undefined/function members', res.Success);
    AssertEquals('undefined and functions are omitted', '{"c":1}', res.StringValue);

    res := engine.Execute('JSON.stringify([undefined, function(){}, 1]);');
    AssertTrue('undefined/function elements', res.Success);
    AssertEquals('array holes serialise as null', '[null,null,1]', res.StringValue);

    // toJSON returning undefined drops the member.
    res := engine.Execute('JSON.stringify({toJSON: function(){ return undefined; }});');
    AssertTrue('toJSON returning undefined', res.Success);
    AssertEquals('toJSON undefined yields undefined', 'undefined', res.StringValue);

    // Indentation still works with a replacer.
    res := engine.Execute('JSON.stringify({a: 1}, ["a"], 2);');
    AssertTrue('indent with replacer', res.Success);
    AssertEquals('indentation is preserved', '{' + #10 + '  "a": 1' + #10 + '}', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestJSONParseReviver();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // The reviver runs bottom-up on every member.
    res := engine.Execute(
      'JSON.parse(''{"a": 1}'', function(k, v){ return typeof v === "number" ? v * 2 : v; }).a;'
    );
    AssertTrue('reviver runs', res.Success);
    AssertEquals('reviver transforms a number', '2', res.StringValue);

    // Returning undefined deletes the property.
    res := engine.Execute(
      'JSON.parse(''{"a": 1}'', function(k, v){ return k === "a" ? undefined : v; }).a;'
    );
    AssertTrue('reviver deletes', res.Success);
    AssertEquals('undefined deletes the property', 'undefined', res.StringValue);

    // Arrays are revived element by element.
    res := engine.Execute(
      'JSON.parse(''[1, 2]'', function(k, v){ return typeof v === "number" ? v + 1 : v; }).join(",");'
    );
    AssertTrue('reviver on arrays', res.Success);
    AssertEquals('reviver applies to elements', '2,3', res.StringValue);

    // Nested objects are walked before their parent.
    res := engine.Execute(
      'var seen = [];' +
      'JSON.parse(''{"a": {"b": 1}}'', function(k, v){ if (k !== "") { seen.push(k); } return v; });' +
      'seen.join(",");'
    );
    AssertTrue('reviver walks nested objects', res.Success);
    AssertEquals('children are revived before parents', 'b,a', res.StringValue);

    // A primitive root still goes through the reviver with the empty key.
    res := engine.Execute(
      'var rootKey = "unset";' +
      'JSON.parse("5", function(k, v){ rootKey = k; return v; });' +
      'rootKey;'
    );
    AssertTrue('reviver sees the root', res.Success);
    AssertEquals('the root key is the empty string', '', res.StringValue);

    // Without a reviver the tree is returned unchanged.
    res := engine.Execute('JSON.parse(''{"a": 1}'').a;');
    AssertTrue('parse without reviver', res.Success);
    AssertEquals('no reviver leaves the value alone', '1', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestIteratorProtocol();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // Arrays expose Symbol.iterator and values(), both returning an iterator.
    res := engine.Execute('typeof [1, 2][Symbol.iterator];');
    AssertTrue('arrays have Symbol.iterator', res.Success);
    AssertEquals('Symbol.iterator is a function', 'function', res.StringValue);

    res := engine.Execute('typeof [1, 2].values().next;');
    AssertTrue('values() returns an iterator', res.Success);
    AssertEquals('the iterator has next()', 'function', res.StringValue);

    // next() yields {value, done}.
    res := engine.Execute('var it = [7, 8].values(); it.next().value;');
    AssertTrue('first step', res.Success);
    AssertEquals('the first value', '7', res.StringValue);

    res := engine.Execute('var it = [7, 8].values(); it.next(); it.next().value;');
    AssertTrue('second step', res.Success);
    AssertEquals('the second value', '8', res.StringValue);

    res := engine.Execute('var it = [1].values(); it.next(); it.next().done;');
    AssertTrue('exhausted', res.Success);
    AssertEquals('done is true when exhausted', 'true', res.StringValue);

    res := engine.Execute('var it = [].values(); it.next().done;');
    AssertTrue('empty iterator', res.Success);
    AssertEquals('an empty iterator is done immediately', 'true', res.StringValue);

    // An iterator is itself iterable.
    res := engine.Execute('var it = [1, 2].values(); typeof it[Symbol.iterator];');
    AssertTrue('iterators are iterable', res.Success);
    AssertEquals('an iterator has Symbol.iterator', 'function', res.StringValue);

    res := engine.Execute('var r = ""; for (var x of [1, 2].values()) { r += x; } r;');
    AssertTrue('for-of over an iterator', res.Success);
    AssertEquals('an iterator can be iterated directly', '12', res.StringValue);

    // Collection helpers return iterators, not arrays.
    res := engine.Execute('Array.isArray(new Map([[1, 2]]).keys());');
    AssertTrue('Map keys()', res.Success);
    AssertEquals('Map keys() is not an array', 'false', res.StringValue);

    res := engine.Execute('var it = new Map([[1, "a"]]).entries(); it.next().value[1];');
    AssertTrue('Map entries()', res.Success);
    AssertEquals('entries() yields a pair', 'a', res.StringValue);

    res := engine.Execute('var it = new Set([5]).keys(); it.next().value;');
    AssertTrue('Set keys()', res.Success);
    AssertEquals('Set keys() yields the value', '5', res.StringValue);

    // Set entries() yields [value, value].
    res := engine.Execute('var e = new Set([5]).entries().next().value; e[0] + ":" + e[1];');
    AssertTrue('Set entries()', res.Success);
    AssertEquals('Set entries duplicates the value', '5:5', res.StringValue);

    // Array.from and spread consume iterators.
    res := engine.Execute('Array.from(new Set([1, 2])).join(",");');
    AssertTrue('Array.from over a Set', res.Success);
    AssertEquals('Array.from consumes the iterator', '1,2', res.StringValue);

    res := engine.Execute('[...new Map([[1, 2]]).keys()].join(",");');
    AssertTrue('spread over an iterator', res.Success);
    AssertEquals('spread consumes the iterator', '1', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestForOfOverCollections();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // Map and Set used to throw TypeError; they are now iterable directly.
    res := engine.Execute('var r = ""; for (var v of new Set([1, 2, 3])) { r += v; } r;');
    AssertTrue('for-of over a Set', res.Success);
    AssertEquals('a Set iterates its values', '123', res.StringValue);

    res := engine.Execute(
      'var r = "";' +
      'for (var pair of new Map([[1, "a"], [2, "b"]])) { r += pair[0] + pair[1]; }' +
      'r;'
    );
    AssertTrue('for-of over a Map', res.Success);
    AssertEquals('a Map iterates [key, value] pairs', '1a2b', res.StringValue);

    // Arrays and strings still iterate, and in order.
    res := engine.Execute('var r = ""; for (var x of [3, 1, 2]) { r += x; } r;');
    AssertTrue('for-of over an array', res.Success);
    AssertEquals('an array iterates in index order', '312', res.StringValue);

    res := engine.Execute('var r = ""; for (var c of "abc") { r += c; } r;');
    AssertTrue('for-of over a string', res.Success);
    AssertEquals('a string iterates by character', 'abc', res.StringValue);

    // break and continue still work with the iterator loop.
    res := engine.Execute('var r = ""; for (var x of [1, 2, 3]) { if (x === 2) break; r += x; } r;');
    AssertTrue('break in for-of', res.Success);
    AssertEquals('break stops the loop', '1', res.StringValue);

    res := engine.Execute('var r = ""; for (var x of [1, 2, 3]) { if (x === 2) continue; r += x; } r;');
    AssertTrue('continue in for-of', res.Success);
    AssertEquals('continue skips one iteration', '13', res.StringValue);

    // A non-iterable still throws.
    res := engine.Execute('for (var x of 5) { }');
    AssertFalse('non-iterable is rejected', res.Success);
    AssertTrue('non-iterable is a TypeError', Pos('not iterable', res.ErrorMessage) > 0);

    res := engine.Execute('for (var x of null) { }');
    AssertFalse('null is not iterable', res.Success);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestForOfDestructuring();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute(
      'var r = "";' +
      'for (const [k, v] of new Map([[1, "a"], [2, "b"]])) { r += k + v; }' +
      'r;'
    );
    AssertTrue('destructuring a Map in for-of', res.Success);
    AssertEquals('keys and values are bound', '1a2b', res.StringValue);

    res := engine.Execute(
      'var r = ""; for (var [a, b] of [[1, 2], [3, 4]]) { r += a + b; } r;'
    );
    AssertTrue('destructuring an array of arrays', res.Success);
    AssertEquals('both elements are bound', '37', res.StringValue);

    res := engine.Execute(
      'var r = ""; for (var [a, b, c] of [[1, 2, 3]]) { r += a + b + c; } r;'
    );
    AssertTrue('three-element pattern', res.Success);
    AssertEquals('three names are bound', '6', res.StringValue);

    // A Set of primitives cannot be destructured, as in ECMAScript.
    res := engine.Execute('for (var [x] of new Set([9])) { }');
    AssertFalse('destructuring a primitive element is rejected', res.Success);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestClassBasics();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // A class is a constructor function.
    res := engine.Execute('class A {} typeof A;');
    AssertTrue('class declaration', res.Success);
    AssertEquals('a class is a function', 'function', res.StringValue);

    res := engine.Execute('class A {} A.name;');
    AssertTrue('class name', res.Success);
    AssertEquals('the class name is set', 'A', res.StringValue);

    res := engine.Execute('class A {} new A() instanceof A;');
    AssertTrue('instanceof own class', res.Success and res.BooleanValue);

    // The constructor runs on construction.
    res := engine.Execute('class A { constructor(x) { this.x = x; } } new A(5).x;');
    AssertTrue('constructor runs', res.Success);
    AssertEquals('constructor sets a field', '5', res.StringValue);

    // An implicit constructor leaves the instance empty but constructable.
    res := engine.Execute('class A {} typeof new A();');
    AssertTrue('implicit constructor', res.Success);
    AssertEquals('an instance is an object', 'object', res.StringValue);

    // Methods live on the prototype and are shared.
    res := engine.Execute('class A { m() { return 5; } } new A().m();');
    AssertTrue('method call', res.Success);
    AssertEquals('a method returns its value', '5', res.StringValue);

    res := engine.Execute('class A { m() { return 1; } } A.prototype.m === new A().m;');
    AssertTrue('methods are on the prototype', res.Success and res.BooleanValue);

    // Methods are not own properties of the instance.
    res := engine.Execute('class A { m() { return 1; } } new A().hasOwnProperty("m");');
    AssertTrue('method ownership', res.Success);
    AssertEquals('a method is not an own property', 'false', res.StringValue);

    // Static members live on the class.
    res := engine.Execute('class A { static s() { return 9; } } A.s();');
    AssertTrue('static method', res.Success);
    AssertEquals('a static method is called on the class', '9', res.StringValue);

    res := engine.Execute('class A { static s() { return 9; } } new A().s;');
    AssertTrue('statics are not on instances', res.Success);
    AssertEquals('an instance does not see statics', 'undefined', res.StringValue);

    // A class expression assigns like any expression.
    res := engine.Execute('var B = class { m() { return 2; } }; new B().m();');
    AssertTrue('class expression', res.Success);
    AssertEquals('a class expression is constructable', '2', res.StringValue);

    // Accessors.
    res := engine.Execute('class A { get v() { return 42; } } new A().v;');
    AssertTrue('getter', res.Success);
    AssertEquals('a getter is read as a property', '42', res.StringValue);

    res := engine.Execute(
      'class A { get v() { return this._v; } set v(x) { this._v = x * 2; } }' +
      'var a = new A(); a.v = 3; a.v;'
    );
    AssertTrue('setter', res.Success);
    AssertEquals('a setter runs on assignment', '6', res.StringValue);

    // Methods can be chained through `this`.
    res := engine.Execute(
      'class A { constructor() { this.n = 0; } inc() { this.n = this.n + 1; return this; } }' +
      'new A().inc().inc().n;'
    );
    AssertTrue('this in methods', res.Success);
    AssertEquals('methods chain through this', '2', res.StringValue);

    // Class fields are rejected rather than silently ignored.
    res := engine.Execute('class A { x = 1; }');
    AssertFalse('class fields are rejected', res.Success);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestClassInheritance();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('class A {} class B extends A {} (new B()) instanceof A;');
    AssertTrue('instanceof base', res.Success and res.BooleanValue);

    res := engine.Execute('class A {} class B extends A {} (new B()) instanceof B;');
    AssertTrue('instanceof derived', res.Success and res.BooleanValue);

    res := engine.Execute('class A {} class B extends A {} (new A()) instanceof B;');
    AssertTrue('base is not an instance of derived', res.Success);
    AssertEquals('the relation is one-way', 'false', res.StringValue);

    // Inherited methods resolve through the chain.
    res := engine.Execute('class A { m() { return 1; } } class B extends A {} new B().m();');
    AssertTrue('inherited method', res.Success);
    AssertEquals('a derived class inherits methods', '1', res.StringValue);

    // Overriding replaces the method without touching the base.
    res := engine.Execute(
      'class A { m() { return 1; } }' +
      'class B extends A { m() { return 2; } }' +
      'new A().m() + ":" + new B().m();'
    );
    AssertTrue('override', res.Success);
    AssertEquals('an override leaves the base alone', '1:2', res.StringValue);

    // Statics are inherited through the function prototype chain.
    res := engine.Execute('class A { static s() { return 9; } } class B extends A {} B.s();');
    AssertTrue('static inheritance', res.Success);
    AssertEquals('statics are inherited', '9', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestClassSuper();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // super(...) runs the base constructor against the same receiver.
    res := engine.Execute(
      'class A { constructor() { this.x = 1; } }' +
      'class B extends A { constructor() { super(); } }' +
      'new B().x;'
    );
    AssertTrue('super() runs the base constructor', res.Success);
    AssertEquals('the base initialises the instance', '1', res.StringValue);

    res := engine.Execute(
      'class A { constructor(x) { this.x = x; } }' +
      'class B extends A { constructor(x) { super(x); } }' +
      'new B(7).x;'
    );
    AssertTrue('super(args)', res.Success);
    AssertEquals('arguments are forwarded to the base', '7', res.StringValue);

    // super.m() calls the base implementation.
    res := engine.Execute(
      'class A { m() { return 1; } }' +
      'class B extends A { m() { return super.m() + 1; } }' +
      'new B().m();'
    );
    AssertTrue('super.method()', res.Success);
    AssertEquals('super calls the base method', '2', res.StringValue);

    // A derived class with no constructor inherits the base behaviour.
    res := engine.Execute(
      'class A { constructor(x) { this.x = x; } }' +
      'class B extends A {}' +
      'new B(3).x;'
    );
    AssertTrue('implicit derived constructor', res.Success);
    AssertEquals('an implicit constructor leaves the base to initialise', 'undefined', res.StringValue);

    // super resolves to undefined in a base class rather than throwing.
    res := engine.Execute('class A { m() { return typeof super; } } new A().m();');
    AssertTrue('super in a base class', res.Success);
    AssertEquals('super is undefined without a base', 'undefined', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestClassMemberEnumerability();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // Class methods are non-enumerable, so they do not leak into reflection.
    res := engine.Execute('class A { m() { return 1; } } Object.keys(new A()).length;');
    AssertTrue('Object.keys on an instance', res.Success);
    AssertEquals('methods are not enumerable own keys', '0', res.StringValue);

    res := engine.Execute(
      'class A { constructor() { this.x = 1; } m() { return 1; } }' +
      'Object.keys(new A()).join(",");'
    );
    AssertTrue('only own fields are keys', res.Success);
    AssertEquals('the constructor field is the only key', 'x', res.StringValue);

    res := engine.Execute(
      'class A { m() { return 1; } }' +
      'var a = new A(); var k = []; for (var p in a) { k.push(p); } k.length;'
    );
    AssertTrue('for-in over an instance', res.Success);
    AssertEquals('for-in skips prototype methods', '0', res.StringValue);

    res := engine.Execute(
      'class A { constructor() { this.x = 1; } m() { return 1; } }' +
      'var a = new A(); var k = []; for (var p in a) { k.push(p); } k.join(",");'
    );
    AssertTrue('for-in with a field', res.Success);
    AssertEquals('for-in sees the own field only', 'x', res.StringValue);

    // JSON serialisation follows the same rule.
    res := engine.Execute(
      'class A { constructor() { this.x = 1; } m() { return 1; } }' +
      'JSON.stringify(new A());'
    );
    AssertTrue('JSON on an instance', res.Success);
    AssertEquals('JSON emits own enumerable fields only', '{"x":1}', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestTaggedTemplates();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // The tag is called, and receives an array of cooked strings.
    res := engine.Execute('function t(s) { return typeof s; } t`x`;');
    AssertTrue('tag is called', res.Success);
    AssertEquals('the tag receives an object', 'object', res.StringValue);

    res := engine.Execute('function t(s) { return Array.isArray(s); } t`x`;');
    AssertTrue('the tag receives an array', res.Success and res.BooleanValue);

    res := engine.Execute('function t(s) { return s[0]; } t`abc`;');
    AssertTrue('cooked string', res.Success);
    AssertEquals('the cooked string is passed', 'abc', res.StringValue);

    // A template with no substitutions has exactly one string.
    res := engine.Execute('function t(s) { return s.length; } t`x`;');
    AssertTrue('single part', res.Success);
    AssertEquals('one string, no expressions', '1', res.StringValue);

    res := engine.Execute('function t(s) { return s.length; } t``;');
    AssertTrue('empty template', res.Success);
    AssertEquals('an empty template still has one part', '1', res.StringValue);

    // Substitutions are passed as additional arguments, and split the strings.
    res := engine.Execute('function t(s) { return s.length; } t`a${1}b${2}c`;');
    AssertTrue('three parts', res.Success);
    AssertEquals('n+1 strings for n substitutions', '3', res.StringValue);

    res := engine.Execute(
      'function t(s, a, b) { return s[0] + a + s[1] + b + s[2]; } t`x${1}y${2}z`;'
    );
    AssertTrue('interleaving', res.Success);
    AssertEquals('strings and values interleave', 'x1y2z', res.StringValue);

    res := engine.Execute('function t(s, v) { return s[0] + v + s[1]; } t`hi ${42}!`;');
    AssertTrue('value substitution', res.Success);
    AssertEquals('the substituted value is passed', 'hi 42!', res.StringValue);

    // `raw` holds the unprocessed text.
    res := engine.Execute('function t(s) { return s.raw[0]; } t`ab`;');
    AssertTrue('raw property', res.Success);
    AssertEquals('raw is available on the strings array', 'ab', res.StringValue);

    res := engine.Execute('function t(s) { return s.raw.length; } t`a${1}b`;');
    AssertTrue('raw has one entry per part', res.Success);
    AssertEquals('raw is parallel to the cooked array', '2', res.StringValue);

    // The tag is invoked once, and its return value is the expression value.
    res := engine.Execute('var n = 0; function t(s) { n++; return "r"; } var v = t`x`; n + ":" + v;');
    AssertTrue('tag return value', res.Success);
    AssertEquals('the tag runs once and its value is used', '1:r', res.StringValue);

    // A tagged template can be applied to a member expression.
    res := engine.Execute('var o = { t: function(s) { return s[0]; } }; o.t`hi`;');
    AssertTrue('member tag', res.Success);
    AssertEquals('a member expression can be a tag', 'hi', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestGeneratorBasics();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // A generator function returns an iterator object, not the body's value.
    res := engine.Execute('function* g() { yield 1; } typeof g();');
    AssertTrue('generator function', res.Success);
    AssertEquals('calling it returns an object', 'object', res.StringValue);

    res := engine.Execute('function* g() { yield 1; } typeof g().next;');
    AssertTrue('generator has next', res.Success);
    AssertEquals('the object has next()', 'function', res.StringValue);

    // The body does not run until the first next().
    res := engine.Execute('var ran = 0; function* g() { ran = 1; } var it = g(); ran;');
    AssertTrue('lazy start', res.Success);
    AssertEquals('the body has not run yet', '0', res.StringValue);

    res := engine.Execute('var ran = 0; function* g() { ran = 1; } g().next(); ran;');
    AssertTrue('runs on next', res.Success);
    AssertEquals('the body runs on the first next()', '1', res.StringValue);

    // next() yields {value, done}.
    res := engine.Execute('function* g() { yield 1; } g().next().value;');
    AssertTrue('first value', res.Success);
    AssertEquals('the yielded value', '1', res.StringValue);

    res := engine.Execute('function* g() { yield 1; } g().next().done;');
    AssertTrue('not done', res.Success);
    AssertEquals('a yield is not done', 'false', res.StringValue);

    // A generator with no yield is done immediately.
    res := engine.Execute('function* g() { } var it = g(); it.next().done;');
    AssertTrue('empty generator', res.Success);
    AssertEquals('an empty body is done at once', 'true', res.StringValue);

    // Parameters are bound.
    res := engine.Execute('function* g(a, b) { yield a + b; } g(2, 3).next().value;');
    AssertTrue('generator parameters', res.Success);
    AssertEquals('parameters are visible in the body', '5', res.StringValue);

    // `yield` is only valid inside a generator.
    res := engine.Execute('function f() { yield 1; } f();');
    AssertFalse('yield outside a generator is rejected', res.Success);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestGeneratorSuspension();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // Each next() resumes where the previous yield stopped.
    res := engine.Execute(
      'function* g() { yield 1; yield 2; }' +
      'var it = g(); var a = it.next(); var b = it.next();' +
      'a.value + ":" + b.value;'
    );
    AssertTrue('two yields', res.Success);
    AssertEquals('each next resumes the body', '1:2', res.StringValue);

    res := engine.Execute(
      'function* g() { yield 1; } var it = g(); it.next(); it.next().done;'
    );
    AssertTrue('exhaustion', res.Success);
    AssertTrue('the generator is done after the last yield', res.BooleanValue);

    // A return value completes the generator.
    res := engine.Execute(
      'function* g() { yield 1; return 99; }' +
      'var it = g(); it.next(); var r = it.next();' +
      'r.value + ":" + r.done;'
    );
    AssertTrue('return value', res.Success);
    AssertEquals('the return value completes it', '99:true', res.StringValue);

    // A value sent into next() becomes the result of the yield expression.
    res := engine.Execute(
      'function* g() { var x = yield 1; yield x + 10; }' +
      'var it = g(); it.next(); it.next(5).value;'
    );
    AssertTrue('sent value', res.Success);
    AssertEquals('the sent value replaces the yield result', '15', res.StringValue);

    // Local variables survive suspension.
    res := engine.Execute(
      'function* g() { var n = 0; while (true) { yield n; n++; } }' +
      'var it = g(); var a = it.next().value; var b = it.next().value; var c = it.next().value;' +
      '"" + a + b + c;'
    );
    AssertTrue('locals survive suspension', res.Success);
    AssertEquals('the loop counter persists across yields', '012', res.StringValue);

    // Resuming after the creating script has finished is not supported: the
    // activation environment is released with the script. Recorded as a known
    // limitation in docs/language-support.md rather than asserted here.
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestGeneratorIteration();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // A generator is iterable, so for...of drains it.
    res := engine.Execute('function* g() { yield 1; yield 2; yield 3; } var s = 0; for (var v of g()) { s += v; } s;');
    AssertTrue('for-of over a generator', res.Success);
    AssertEquals('for-of sums every yielded value', '6', res.StringValue);

    res := engine.Execute(
      'function* g() { for (var i = 0; i < 3; i++) { yield i; } }' +
      'var s = ""; for (var v of g()) { s += v; } s;'
    );
    AssertTrue('generator with a loop', res.Success);
    AssertEquals('the loop yields in order', '012', res.StringValue);

    // A generator is iterable more than once per loop iteration, i.e. the
    // enclosing loop is not destroyed by the first suspension.
    res := engine.Execute(
      'function* g() { yield 1; yield 2; }' +
      'var total = 0; for (var v of g()) { total += v; }' +
      'var count = 0; for (var w of g()) { count++; }' +
      'total + ":" + count;'
    );
    AssertTrue('two separate iterations', res.Success);
    AssertEquals('each call makes a fresh generator', '3:2', res.StringValue);

    // Driving it manually with a while loop works too.
    res := engine.Execute(
      'function* g() { yield 1; yield 2; }' +
      'var it = g(); var total = 0; var r = it.next();' +
      'while (!r.done) { total += r.value; r = it.next(); } total;'
    );
    AssertTrue('manual iteration', res.Success);
    AssertEquals('a while loop drains it', '3', res.StringValue);

    // return() finishes the generator early.
    res := engine.Execute('function* g() { yield 1; yield 2; } var it = g(); it.return(9).value;');
    AssertTrue('return()', res.Success);
    AssertEquals('return() completes it with the value', '9', res.StringValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestYieldStar();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    res := engine.Execute('function* g() { yield* [1, 2]; } var s = 0; for (var v of g()) { s += v; } s;');
    AssertTrue('yield* over an array', res.Success);
    AssertEquals('delegation yields each element', '3', res.StringValue);

    res := engine.Execute(
      'function* g() { yield 0; yield* [1, 2]; yield 3; }' +
      'var s = ""; for (var v of g()) { s += v; } s;'
    );
    AssertTrue('yield* between yields', res.Success);
    AssertEquals('delegation composes with plain yields', '0123', res.StringValue);

    res := engine.Execute('function* g() { yield* "ab"; } var s = ""; for (var v of g()) { s += v; } s;');
    AssertTrue('yield* over a string', res.Success);
    AssertEquals('delegation works for any iterable', 'ab', res.StringValue);

    res := engine.Execute('function* g() { yield* []; } var it = g(); it.next().done;');
    AssertTrue('yield* over an empty iterable', res.Success);
    AssertTrue('delegating nothing is done immediately', res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestFunctionMetadata();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // `length` is the declared parameter count.
    res := engine.Execute('function f(a, b) {} f.length;');
    AssertTrue('declared length', res.Success);
    AssertEquals('two parameters', '2', res.StringValue);

    res := engine.Execute('function f() {} f.length;');
    AssertTrue('zero parameters', res.Success);
    AssertEquals('no parameters is 0', '0', res.StringValue);

    res := engine.Execute('var g = function(a) {}; g.length;');
    AssertTrue('function expression length', res.Success);
    AssertEquals('one parameter', '1', res.StringValue);

    res := engine.Execute('var h = (a, b) => 1; h.length;');
    AssertTrue('arrow length', res.Success);
    AssertEquals('arrow parameters count', '2', res.StringValue);

    // `name` is the declared name.
    res := engine.Execute('function foo() {} foo.name;');
    AssertTrue('declared name', res.Success);
    AssertEquals('the function name', 'foo', res.StringValue);

    res := engine.Execute('var g = function named() {}; g.name;');
    AssertTrue('expression name', res.Success);
    AssertEquals('the expression name', 'named', res.StringValue);

    // An anonymous function takes the name of the property it is assigned to.
    res := engine.Execute('var o = {m: function() {}}; o.m.name;');
    AssertTrue('inferred name', res.Success);
    AssertEquals('the property name is inferred', 'm', res.StringValue);

    res := engine.Execute('var o = {m() {}}; o.m.name;');
    AssertTrue('method name', res.Success);
    AssertEquals('a shorthand method is named', 'm', res.StringValue);

    // An explicit name is not overridden by the property.
    res := engine.Execute('var o = {m: function named() {}}; o.m.name;');
    AssertTrue('explicit name wins', res.Success);
    AssertEquals('the declared name is kept', 'named', res.StringValue);

    // Both are non-enumerable, so reflection does not see them.
    res := engine.Execute('function f(a) {} Object.keys(f).length;');
    AssertTrue('metadata is non-enumerable', res.Success);
    AssertEquals('neither name nor length is an own key', '0', res.StringValue);

    res := engine.Execute('function f(a) {} f.hasOwnProperty("name") && f.hasOwnProperty("length");');
    AssertTrue('metadata is an own property', res.Success and res.BooleanValue);
  finally
    engine.Free();
  end;
end;

procedure TFloriaJSPriority2Test.TestFunctionConstructor();
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
begin
  engine := TFloriaJSEngine.Create();
  try
    // The body is compiled at run time.
    res := engine.Execute('Function("return 1")();');
    AssertTrue('empty parameter list', res.Success);
    AssertEquals('the body runs', '1', res.StringValue);

    res := engine.Execute('var f = Function("a", "b", "return a + b"); f(2, 3);');
    AssertTrue('named parameters', res.Success);
    AssertEquals('parameters are bound', '5', res.StringValue);

    res := engine.Execute('Function("a", "return a * 2")(21);');
    AssertTrue('single parameter', res.Success);
    AssertEquals('the argument is used', '42', res.StringValue);

    res := engine.Execute('typeof Function("return 1");');
    AssertTrue('produces a function', res.Success);
    AssertEquals('the result is callable', 'function', res.StringValue);

    // It works with `new` too, as ECMAScript allows.
    res := engine.Execute('new Function("return 7")();');
    AssertTrue('new Function', res.Success);
    AssertEquals('construction also yields the function', '7', res.StringValue);

    // A bare `return` is valid: it returns undefined.
    res := engine.Execute('Function("return")();');
    AssertTrue('bare return', res.Success);
    AssertEquals('a bare return yields undefined', 'undefined', res.StringValue);

    // A genuinely malformed body is a SyntaxError.
    res := engine.Execute('Function("return 1 +");');
    AssertFalse('syntax error in the body', res.Success);
    AssertTrue('a bad body is a SyntaxError', Pos('SyntaxError', res.ErrorMessage) > 0);

    res := engine.Execute('Function("this is not javascript ((");');
    AssertFalse('unparseable body is rejected', res.Success);

    // Each call produces an independent function.
    res := engine.Execute(
      'var a = Function("return 1"); var b = Function("return 2"); a() + b();'
    );
    AssertTrue('independent functions', res.Success);
    AssertEquals('two constructed functions', '3', res.StringValue);

    // A constructed function closes over globals, not the caller's locals.
    res := engine.Execute(
      'var g = 10; function mk() { var local = 1; return Function("return g"); } mk()();'
    );
    AssertTrue('global scope', res.Success);
    AssertEquals('the body sees globals', '10', res.StringValue);
  finally
    engine.Free();
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
  RegisterTest(TFloriaJSRuntimeTest);
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
  RegisterTest(TFloriaJSVMTest);
  RegisterTest(TFloriaJSPriority3Test);
  RegisterTest(TFloriaJSPriority1Test);
  RegisterTest(TFloriaJSPriority2Test);

  Application := TTestRunner.Create(nil);
  try
    Application.Initialize();
    Application.Title := 'Floria JS Test Runner';
    Application.Run();
  finally
    Application.Free();
  end;
end.
