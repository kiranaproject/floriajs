{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Abstract Syntax Tree (AST)                      }
{                                                                          }
{   Defines AST node classes representing JavaScript expressions,          }
{   statements, and declarative FTML component hierarchies.                }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.ast;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, floria.js.lexer, floria.js.types;

type
  { Forward Declarations }
  TFloriaJSASTNode = class;
  TFloriaJSExprNode = class;
  TFloriaJSStmtNode = class;
  IFloriaJSASTVisitor = interface;

  { Base AST Node }
  TFloriaJSASTNode = class
  private
    FLine: Integer;
    FColumn: Integer;
    FRefCount: Integer;
  public
    constructor Create(ALine, AColumn: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); virtual; abstract;

    { Reference counting for nodes that can be shared between several owners.
      A node starts with a single reference, held by the node that owns it.
      Retain adds a reference, Release drops one and destroys the node once its
      last reference is gone. It is used for the body of a function, which is
      shared between the declaration and every closure created from it. }
    procedure Retain;
    procedure Release;

    property Line: Integer read FLine write FLine;
    property Column: Integer read FColumn write FColumn;
    property RefCount: Integer read FRefCount;
  end;

  { Base Expression Node }
  TFloriaJSExprNode = class(TFloriaJSASTNode)
  end;

  { Base Statement Node }
  TFloriaJSStmtNode = class(TFloriaJSASTNode)
  end;

  { ────────────────────────────────────────────────────────────────────────── }
  { Expressions                                                                }
  { ────────────────────────────────────────────────────────────────────────── }

  { Literal: numbers, strings, booleans, null, undefined }
  TFloriaJSLiteralExpr = class(TFloriaJSExprNode)
  private
    FValueType: TFloriaJSType;
    FStringVal: string;
    FNumberVal: Double;
    FBoolVal: Boolean;
  public
    constructor CreateNumber(ANum: Double; ALine, ACol: Integer);
    constructor CreateString(const AStr: string; ALine, ACol: Integer);
    constructor CreateBoolean(ABool: Boolean; ALine, ACol: Integer);
    constructor CreateNull(ALine, ACol: Integer);
    constructor CreateUndefined(ALine, ACol: Integer);

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property ValueType: TFloriaJSType read FValueType;
    property StringVal: string read FStringVal;
    property NumberVal: Double read FNumberVal;
    property BoolVal: Boolean read FBoolVal;
  end;

  { Identifier / Variable Reference }
  TFloriaJSIdentifierExpr = class(TFloriaJSExprNode)
  private
    FName: string;
  public
    constructor Create(const AName: string; ALine, ACol: Integer);

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Name: string read FName write FName;
  end;

  { Unary Expression: +x, -x, !x, ~x, ++x, --x, x++, x--, typeof x, delete x }
  TFloriaJSUnaryExpr = class(TFloriaJSExprNode)
  private
    FOperator: TFloriaJSTokenKind;
    FOperand: TFloriaJSExprNode;
    FIsPrefix: Boolean;
  public
    constructor Create(AOp: TFloriaJSTokenKind; AOperand: TFloriaJSExprNode; AIsPrefix: Boolean; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Op: TFloriaJSTokenKind read FOperator;
    property OpKind: TFloriaJSTokenKind read FOperator;
    property Operand: TFloriaJSExprNode read FOperand;
    property IsPrefix: Boolean read FIsPrefix;
  end;

  { Binary Expression: a + b, a * b, a === b, a && b, etc. }
  TFloriaJSBinaryExpr = class(TFloriaJSExprNode)
  private
    FLeft: TFloriaJSExprNode;
    FOperator: TFloriaJSTokenKind;
    FRight: TFloriaJSExprNode;
  public
    constructor Create(ALeft: TFloriaJSExprNode; AOp: TFloriaJSTokenKind; ARight: TFloriaJSExprNode; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    function  ExtractLeft(): TFloriaJSExprNode;
    function  ExtractRight(): TFloriaJSExprNode;

    property Left: TFloriaJSExprNode read FLeft;
    property Op: TFloriaJSTokenKind read FOperator;
    property OpKind: TFloriaJSTokenKind read FOperator;
    property Right: TFloriaJSExprNode read FRight;
  end;

  { Conditional / Ternary Expression: cond ? expr1 : expr2 }
  TFloriaJSConditionalExpr = class(TFloriaJSExprNode)
  private
    FCondition: TFloriaJSExprNode;
    FConsequent: TFloriaJSExprNode;
    FAlternate: TFloriaJSExprNode;
  public
    constructor Create(ACond, AConsequent, AAlternate: TFloriaJSExprNode; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Condition: TFloriaJSExprNode read FCondition;
    property Consequent: TFloriaJSExprNode read FConsequent;
    property Alternate: TFloriaJSExprNode read FAlternate;
  end;

  { Assignment Expression: a = b, a += b, etc. }
  TFloriaJSAssignExpr = class(TFloriaJSExprNode)
  private
    FTarget: TFloriaJSExprNode;
    FOperator: TFloriaJSTokenKind;
    FValue: TFloriaJSExprNode;
  public
    constructor Create(ATarget: TFloriaJSExprNode; AOp: TFloriaJSTokenKind; AValue: TFloriaJSExprNode; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    function  ExtractTarget(): TFloriaJSExprNode;
    function  ExtractValue(): TFloriaJSExprNode;

    property Target: TFloriaJSExprNode read FTarget;
    property Op: TFloriaJSTokenKind read FOperator;
    property OpKind: TFloriaJSTokenKind read FOperator;
    property Value: TFloriaJSExprNode read FValue;
  end;

  { Member Expression: obj.prop or obj[prop] }
  TFloriaJSMemberExpr = class(TFloriaJSExprNode)
  private
    FTarget: TFloriaJSExprNode;
    FPropertyExpr: TFloriaJSExprNode;
    FPropertyName: string;
    FComputed: Boolean;
    FIsOptional: Boolean;
  public
    constructor CreateNamed(ATarget: TFloriaJSExprNode; const APropName: string; ALine, ACol: Integer; AIsOptional: Boolean = False);
    constructor CreateComputed(ATarget, APropExpr: TFloriaJSExprNode; ALine, ACol: Integer; AIsOptional: Boolean = False);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Target: TFloriaJSExprNode read FTarget;
    property PropertyExpr: TFloriaJSExprNode read FPropertyExpr;
    property PropertyName: string read FPropertyName;
    property Computed: Boolean read FComputed;
    property IsOptional: Boolean read FIsOptional;
  end;

  { Call Expression: func(a, b, c) or Construction: new Func(a, b, c) }
  TFloriaJSCallExpr = class(TFloriaJSExprNode)
  private
    FCallee: TFloriaJSExprNode;
    FArguments: TFPList;
    FIsNew: Boolean;
    FIsOptional: Boolean;
  public
    constructor Create(ACallee: TFloriaJSExprNode; ALine, ACol: Integer; AIsNew: Boolean = False; AIsOptional: Boolean = False);
    destructor Destroy(); override;

    procedure AddArgument(AArg: TFloriaJSExprNode);
    function  GetArgumentCount(): Integer;
    function  GetArgument(AIndex: Integer): TFloriaJSExprNode;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Callee: TFloriaJSExprNode read FCallee;
    property Arguments: TFPList read FArguments;
    { True when the call constructs a new object with the new operator. }
    property IsNew: Boolean read FIsNew;
    property IsOptional: Boolean read FIsOptional;
  end;

  { Array Literal: [1, 2, 3] }
  TFloriaJSArrayExpr = class(TFloriaJSExprNode)
  private
    FElements: TFPList;
  public
    constructor Create(ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure AddElement(AElem: TFloriaJSExprNode);
    function  GetElementCount(): Integer;
    function  GetElement(AIndex: Integer): TFloriaJSExprNode;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Elements: TFPList read FElements;
  end;

  { Spread Expression: ...expr }
  TFloriaJSSpreadExpr = class(TFloriaJSExprNode)
  private
    FExpression: TFloriaJSExprNode;
  public
    constructor Create(AExpr: TFloriaJSExprNode; ALine, ACol: Integer);
    destructor Destroy(); override;
    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;
    function  ExtractExpression(): TFloriaJSExprNode;
    property Expression: TFloriaJSExprNode read FExpression;
  end;

  { Grouping Expression: (expr) }
  TFloriaJSGroupExpr = class(TFloriaJSExprNode)
  private
    FExpression: TFloriaJSExprNode;
  public
    constructor Create(AExpr: TFloriaJSExprNode; ALine, ACol: Integer);
    destructor Destroy(); override;
    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;
    function  ExtractExpression(): TFloriaJSExprNode;
    property Expression: TFloriaJSExprNode read FExpression;
  end;

  { Object Literal Property Kind }
  TFloriaJSPropertyKind = (fjpkNormal, fjpkComputed, fjpkSpread, fjpkGetter, fjpkSetter);

  // Object Literal Property Entry
  TFloriaJSPropertyEntry = record
    Key: string;
    KeyExpr: TFloriaJSExprNode;
    Value: TFloriaJSExprNode;
    Kind: TFloriaJSPropertyKind;
  end;

  // Object Literal: { a: 1, b: "hello" }
  TFloriaJSObjectExpr = class(TFloriaJSExprNode)
  private
    FProperties: array of TFloriaJSPropertyEntry;
    FCount: Integer;
  public
    constructor Create(ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure AddProperty(const AKey: string; AValue: TFloriaJSExprNode);
    procedure AddComputedProperty(AKeyExpr: TFloriaJSExprNode; AValue: TFloriaJSExprNode);
    procedure AddSpreadProperty(ASpreadExpr: TFloriaJSExprNode);
    procedure AddGetter(const AKey: string; AGetter: TFloriaJSExprNode; AKeyExpr: TFloriaJSExprNode = nil);
    procedure AddSetter(const AKey: string; ASetter: TFloriaJSExprNode; AKeyExpr: TFloriaJSExprNode = nil);
    function  GetPropertyCount(): Integer;
    function  GetPropertyKey(AIndex: Integer): string;
    function  GetPropertyValue(AIndex: Integer): TFloriaJSExprNode;
    function  GetPropertyKeyExpr(AIndex: Integer): TFloriaJSExprNode;
    function  GetPropertyKind(AIndex: Integer): TFloriaJSPropertyKind;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;
  end;

  // Function / Arrow Expression: function(a, b) { ... } or (a, b) => expr
  TFloriaJSFunctionExpr = class(TFloriaJSExprNode)
  private
    FName: string;
    FParameters: TStringList;
    FBody: TFloriaJSStmtNode;
    FIsArrow: Boolean;
    FIsAsync: Boolean;
  public
    constructor Create(const AName: string; AIsArrow: Boolean; ALine, ACol: Integer; AIsAsync: Boolean = False);
    destructor Destroy(); override;

    procedure AddParameter(const AParamName: string; ADefaultExpr: TFloriaJSExprNode = nil);
    procedure AddDestructParameter(APattern: TFloriaJSExprNode; ADefaultExpr: TFloriaJSExprNode = nil);
    procedure SetBody(ABody: TFloriaJSStmtNode);

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Name: string read FName write FName;
    property Parameters: TStringList read FParameters;
    property Body: TFloriaJSStmtNode read FBody;
    property IsArrow: Boolean read FIsArrow;
    property IsAsync: Boolean read FIsAsync;
  end;

  { ────────────────────────────────────────────────────────────────────────── }
  { Statements                                                                 }
  { ────────────────────────────────────────────────────────────────────────── }

  { Expression Statement: expr; }
  TFloriaJSExprStmt = class(TFloriaJSStmtNode)
  private
    FExpression: TFloriaJSExprNode;
  public
    constructor Create(AExpr: TFloriaJSExprNode; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Expression: TFloriaJSExprNode read FExpression;
  end;

  { Variable Declarator: name = init or pattern = init }
  TFloriaJSVarDeclarator = record
    Name: string;
    Pattern: TFloriaJSExprNode;
    Initializer: TFloriaJSExprNode;
  end;

  { Variable Statement: let / const / var a = 1, b = 2; }
  TFloriaJSVarStmt = class(TFloriaJSStmtNode)
  private
    FKind: TFloriaJSTokenKind; { tkLet, tkConst, tkVar }
    FDeclarators: array of TFloriaJSVarDeclarator;
    FCount: Integer;
  public
    constructor Create(AKind: TFloriaJSTokenKind; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure AddDeclarator(const AName: string; AInit: TFloriaJSExprNode);
    procedure AddDestructDeclarator(APattern: TFloriaJSExprNode; AInit: TFloriaJSExprNode);
    function  GetDeclaratorCount(): Integer;
    function  GetDeclaratorName(AIndex: Integer): string;
    function  GetDeclaratorPattern(AIndex: Integer): TFloriaJSExprNode;
    function  GetDeclaratorInit(AIndex: Integer): TFloriaJSExprNode;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Kind: TFloriaJSTokenKind read FKind;
  end;

  // Block Statement: { stmt1; stmt2; }
  TFloriaJSBlockStmt = class(TFloriaJSStmtNode)
  private
    FStatements: TFPList;
  public
    constructor Create(ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure AddStatement(AStmt: TFloriaJSStmtNode);
    function  GetStatementCount(): Integer;
    function  GetStatement(AIndex: Integer): TFloriaJSStmtNode;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Statements: TFPList read FStatements;
  end;

  { If Statement: if (cond) thenStmt else elseStmt }
  TFloriaJSIfStmt = class(TFloriaJSStmtNode)
  private
    FCondition: TFloriaJSExprNode;
    FConsequent: TFloriaJSStmtNode;
    FAlternate: TFloriaJSStmtNode;
  public
    constructor Create(ACond: TFloriaJSExprNode; AConsequent: TFloriaJSStmtNode; AAlternate: TFloriaJSStmtNode; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Condition: TFloriaJSExprNode read FCondition;
    property Consequent: TFloriaJSStmtNode read FConsequent;
    property Alternate: TFloriaJSStmtNode read FAlternate;
  end;

  { Return Statement: return expr; }
  TFloriaJSReturnStmt = class(TFloriaJSStmtNode)
  private
    FArgument: TFloriaJSExprNode;
  public
    constructor Create(AArg: TFloriaJSExprNode; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Argument: TFloriaJSExprNode read FArgument;
  end;

  { While & Do-While Loop: while (cond) stmt; or do stmt while (cond); }
  TFloriaJSWhileStmt = class(TFloriaJSStmtNode)
  private
    FCondition: TFloriaJSExprNode;
    FBody: TFloriaJSStmtNode;
    FIsDoWhile: Boolean;
    FLabel: string;
  public
    constructor Create(ACond: TFloriaJSExprNode; ABody: TFloriaJSStmtNode; AIsDoWhile: Boolean; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Condition: TFloriaJSExprNode read FCondition;
    property Body: TFloriaJSStmtNode read FBody;
    property IsDoWhile: Boolean read FIsDoWhile;
    property LabelName: string read FLabel write FLabel;
  end;

  { For Loop: for (init; test; update) body }
  TFloriaJSForStmt = class(TFloriaJSStmtNode)
  private
    FInit: TFloriaJSASTNode; { May be VarStmt or ExprStmt or nil }
    FTest: TFloriaJSExprNode;
    FUpdate: TFloriaJSExprNode;
    FBody: TFloriaJSStmtNode;
    FLabel: string;
  public
    constructor Create(AInit: TFloriaJSASTNode; ATest, AUpdate: TFloriaJSExprNode; ABody: TFloriaJSStmtNode; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Init: TFloriaJSASTNode read FInit;
    property Test: TFloriaJSExprNode read FTest;
    property Update: TFloriaJSExprNode read FUpdate;
    property Body: TFloriaJSStmtNode read FBody;
    property LabelName: string read FLabel write FLabel;
  end;

  { For-In and For-Of Loop: for (var x in obj) or for (const x of arr) }
  TFloriaJSForInOfStmt = class(TFloriaJSStmtNode)
  private
    FVarKind: TFloriaJSTokenKind;
    FVarName: string;
    FIsOf: Boolean;
    FIterable: TFloriaJSExprNode;
    FBody: TFloriaJSStmtNode;
    FLabel: string;
  public
    constructor Create(AVarKind: TFloriaJSTokenKind; const AVarName: string; AIsOf: Boolean; AIterable: TFloriaJSExprNode; ABody: TFloriaJSStmtNode; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property VarKind: TFloriaJSTokenKind read FVarKind;
    property VarName: string read FVarName;
    property IsOf: Boolean read FIsOf;
    property Iterable: TFloriaJSExprNode read FIterable;
    property Body: TFloriaJSStmtNode read FBody;
    property LabelName: string read FLabel write FLabel;
  end;

  { Switch Case Clause: case <expr>: stmts... or default: stmts... }
  TFloriaJSSwitchCase = class
  private
    FTest: TFloriaJSExprNode; { nil for the default clause }
    FBody: TFPList;
    FIsDefault: Boolean;
  public
    constructor Create(ATest: TFloriaJSExprNode; AIsDefault: Boolean);
    destructor Destroy(); override;

    procedure AddStatement(AStmt: TFloriaJSStmtNode);
    function  GetStatementCount(): Integer;
    function  GetStatement(AIndex: Integer): TFloriaJSStmtNode;

    property Test: TFloriaJSExprNode read FTest;
    property IsDefault: Boolean read FIsDefault;
    property Body: TFPList read FBody;
  end;

  { Switch Statement: switch (expr) with case and default clauses }
  TFloriaJSSwitchStmt = class(TFloriaJSStmtNode)
  private
    FDiscriminant: TFloriaJSExprNode;
    FCases: TFPList;
  public
    constructor Create(ADiscriminant: TFloriaJSExprNode; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure AddCase(ACase: TFloriaJSSwitchCase);
    function  GetCaseCount(): Integer;
    function  GetCase(AIndex: Integer): TFloriaJSSwitchCase;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Discriminant: TFloriaJSExprNode read FDiscriminant;
    property Cases: TFPList read FCases;
  end;

  { Try Statement: try block with an optional catch and finally clause }
  TFloriaJSTryStmt = class(TFloriaJSStmtNode)
  private
    FBlock: TFloriaJSBlockStmt;
    FCatchParam: string;
    FCatchBlock: TFloriaJSBlockStmt;
    FFinallyBlock: TFloriaJSBlockStmt;
  public
    constructor Create(ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure SetBlock(ABlock: TFloriaJSBlockStmt);
    procedure SetCatch(const AParam: string; ABlock: TFloriaJSBlockStmt);
    procedure SetFinally(ABlock: TFloriaJSBlockStmt);

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Block: TFloriaJSBlockStmt read FBlock;
    property CatchParam: string read FCatchParam;
    property CatchBlock: TFloriaJSBlockStmt read FCatchBlock;
    property FinallyBlock: TFloriaJSBlockStmt read FFinallyBlock;
  end;

  { Throw Statement: throw expr; }
  TFloriaJSThrowStmt = class(TFloriaJSStmtNode)
  private
    FExpression: TFloriaJSExprNode;
  public
    constructor Create(AExpr: TFloriaJSExprNode; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Expression: TFloriaJSExprNode read FExpression;
  end;

  { Debugger Statement: debugger;
    A no-op marker. Recognising it as a statement keeps the undeclared-read
    check from turning it into a ReferenceError. }
  TFloriaJSDebuggerStmt = class(TFloriaJSStmtNode)
  public
    constructor Create(ALine, ACol: Integer);
    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;
  end;

  { Break Statement: break; }
  TFloriaJSBreakStmt = class(TFloriaJSStmtNode)
  private
    FLabel: string;
  public
    constructor Create(ALine, ACol: Integer; const ALabel: string = '');
    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;
    property LabelName: string read FLabel;
  end;

  { Continue Statement: continue; }
  TFloriaJSContinueStmt = class(TFloriaJSStmtNode)
  private
    FLabel: string;
  public
    constructor Create(ALine, ACol: Integer; const ALabel: string = '');
    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;
    property LabelName: string read FLabel;
  end;

  { Labeled Statement: label: statement }
  TFloriaJSLabeledStmt = class(TFloriaJSStmtNode)
  private
    FLabel: string;
    FBody: TFloriaJSStmtNode;
  public
    constructor Create(const ALabel: string; ABody: TFloriaJSStmtNode; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property LabelName: string read FLabel;
    property Body: TFloriaJSStmtNode read FBody;
  end;

  // Function Declaration: function foo(a, b) { ... }
  TFloriaJSFunctionDecl = class(TFloriaJSStmtNode)
  private
    FName: string;
    FParameters: TStringList;
    FBody: TFloriaJSBlockStmt;
    FIsAsync: Boolean;
  public
    constructor Create(const AName: string; ALine, ACol: Integer; AIsAsync: Boolean = False);
    destructor Destroy(); override;

    procedure AddParameter(const AParamName: string; ADefaultExpr: TFloriaJSExprNode = nil);
    procedure AddDestructParameter(APattern: TFloriaJSExprNode; ADefaultExpr: TFloriaJSExprNode = nil);
    procedure SetBody(ABody: TFloriaJSBlockStmt);

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Name: string read FName;
    property Parameters: TStringList read FParameters;
    property Body: TFloriaJSBlockStmt read FBody;
    property IsAsync: Boolean read FIsAsync;
  end;

  { Program / Script Root: Collection of top-level statements }
  TFloriaJSProgram = class(TFloriaJSASTNode)
  private
    FStatements: TFPList;
  public
    constructor Create(ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure AddStatement(AStmt: TFloriaJSStmtNode);
    function  GetStatementCount(): Integer;
    function  GetStatement(AIndex: Integer): TFloriaJSStmtNode;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property Statements: TFPList read FStatements;
  end;

  { ────────────────────────────────────────────────────────────────────────── }
  { Declarative / FTML Component Node (Floria Toolkit Markup Language)         }
  { ────────────────────────────────────────────────────────────────────────── }

  { Declarative Property Binding: width: parent.width - 20 }
  TFloriaFTMLProperty = record
    Name: string;
    Expression: TFloriaJSExprNode;
  end;

  // Declarative Signal Handler: onClicked: { count += 1; }
  TFloriaFTMLSignal = record
    SignalName: string;
    Handler: TFloriaJSStmtNode;
  end;

  // Declarative Component: Rectangle { width: 100; ... }
  TFloriaFTMLComponent = class(TFloriaJSASTNode)
  private
    FComponentType: string;
    FId: string;
    FProperties: array of TFloriaFTMLProperty;
    FPropCount: Integer;
    FSignals: array of TFloriaFTMLSignal;
    FSignalCount: Integer;
    FFunctions: TFPList;
    FChildren: TFPList;
  public
    constructor Create(const AComponentType: string; ALine, ACol: Integer);
    destructor Destroy(); override;

    procedure AddProperty(const AName: string; AExpr: TFloriaJSExprNode);
    procedure AddSignal(const ASignalName: string; AHandler: TFloriaJSStmtNode);
    procedure AddFunction(AFunc: TFloriaJSFunctionDecl);
    procedure AddChild(AChild: TFloriaFTMLComponent);

    function  GetPropertyCount(): Integer;
    function  GetPropertyName(AIndex: Integer): string;
    function  GetPropertyExpr(AIndex: Integer): TFloriaJSExprNode;

    function  GetSignalCount(): Integer;
    function  GetSignalName(AIndex: Integer): string;
    function  GetSignalHandler(AIndex: Integer): TFloriaJSStmtNode;

    function  GetFunctionCount(): Integer;
    function  GetFunction(AIndex: Integer): TFloriaJSFunctionDecl;

    function  GetChildCount(): Integer;
    function  GetChild(AIndex: Integer): TFloriaFTMLComponent;

    procedure Accept(AVisitor: IFloriaJSASTVisitor); override;

    property ComponentType: string read FComponentType write FComponentType;
    property Id: string read FId write FId;
  end;

  { ────────────────────────────────────────────────────────────────────────── }
  { Visitor Interface                                                          }
  { ────────────────────────────────────────────────────────────────────────── }

  IFloriaJSASTVisitor = interface
    ['{B9D90618-97F7-410A-9EC2-8E3D78A86CA8}']
    procedure VisitLiteral(ANode: TFloriaJSLiteralExpr);
    procedure VisitIdentifier(ANode: TFloriaJSIdentifierExpr);
    procedure VisitUnary(ANode: TFloriaJSUnaryExpr);
    procedure VisitBinary(ANode: TFloriaJSBinaryExpr);
    procedure VisitConditional(ANode: TFloriaJSConditionalExpr);
    procedure VisitAssign(ANode: TFloriaJSAssignExpr);
    procedure VisitMember(ANode: TFloriaJSMemberExpr);
    procedure VisitCall(ANode: TFloriaJSCallExpr);
    procedure VisitArray(ANode: TFloriaJSArrayExpr);
    procedure VisitObject(ANode: TFloriaJSObjectExpr);
    procedure VisitGroup(ANode: TFloriaJSGroupExpr);
    procedure VisitFunctionExpr(ANode: TFloriaJSFunctionExpr);

    procedure VisitExprStmt(ANode: TFloriaJSExprStmt);
    procedure VisitVarStmt(ANode: TFloriaJSVarStmt);
    procedure VisitBlockStmt(ANode: TFloriaJSBlockStmt);
    procedure VisitIfStmt(ANode: TFloriaJSIfStmt);
    procedure VisitReturnStmt(ANode: TFloriaJSReturnStmt);
    procedure VisitWhileStmt(ANode: TFloriaJSWhileStmt);
    procedure VisitForStmt(ANode: TFloriaJSForStmt);
    procedure VisitForInOfStmt(ANode: TFloriaJSForInOfStmt);
    procedure VisitSwitchStmt(ANode: TFloriaJSSwitchStmt);
    procedure VisitTryStmt(ANode: TFloriaJSTryStmt);
    procedure VisitThrowStmt(ANode: TFloriaJSThrowStmt);
    procedure VisitDebuggerStmt(ANode: TFloriaJSDebuggerStmt);
    procedure VisitBreakStmt(ANode: TFloriaJSBreakStmt);
    procedure VisitContinueStmt(ANode: TFloriaJSContinueStmt);
    procedure VisitLabeledStmt(ANode: TFloriaJSLabeledStmt);
    procedure VisitFunctionDecl(ANode: TFloriaJSFunctionDecl);
    procedure VisitProgram(ANode: TFloriaJSProgram);
    procedure VisitFTMLComponent(ANode: TFloriaFTMLComponent);
  end;

function ContainsOptionalChain(ANode: TFloriaJSExprNode): Boolean;

implementation

{ TFloriaJSASTNode }

constructor TFloriaJSASTNode.Create(ALine, AColumn: Integer);
begin
  inherited Create();
  FLine := ALine;
  FColumn := AColumn;
  FRefCount := 1;
end;

destructor TFloriaJSASTNode.Destroy();
begin
  inherited Destroy();
end;

procedure TFloriaJSASTNode.Retain();
begin
  if Self = nil then
    Exit;
  Inc(FRefCount);
end;

procedure TFloriaJSASTNode.Release();
begin
  if Self = nil then
    Exit;
  Dec(FRefCount);
  if FRefCount <= 0 then
    Free;
end;

{ TFloriaJSLiteralExpr }

constructor TFloriaJSLiteralExpr.CreateNumber(ANum: Double; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FValueType := fjstNumber;
  FNumberVal := ANum;
  FStringVal := '';
  FBoolVal := False;
end;

constructor TFloriaJSLiteralExpr.CreateString(const AStr: string; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FValueType := fjstString;
  FStringVal := AStr;
  FNumberVal := 0.0;
  FBoolVal := False;
end;

constructor TFloriaJSLiteralExpr.CreateBoolean(ABool: Boolean; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FValueType := fjstBoolean;
  FBoolVal := ABool;
  FNumberVal := 0.0;
  FStringVal := '';
end;

constructor TFloriaJSLiteralExpr.CreateNull(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FValueType := fjstNull;
  FStringVal := '';
  FNumberVal := 0.0;
  FBoolVal := False;
end;

constructor TFloriaJSLiteralExpr.CreateUndefined(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FValueType := fjstUndefined;
  FStringVal := '';
  FNumberVal := 0.0;
  FBoolVal := False;
end;

procedure TFloriaJSLiteralExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitLiteral(Self);
end;

{ TFloriaJSIdentifierExpr }

constructor TFloriaJSIdentifierExpr.Create(const AName: string; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FName := AName;
end;

procedure TFloriaJSIdentifierExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitIdentifier(Self);
end;

{ TFloriaJSUnaryExpr }

constructor TFloriaJSUnaryExpr.Create(AOp: TFloriaJSTokenKind; AOperand: TFloriaJSExprNode; AIsPrefix: Boolean; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FOperator := AOp;
  FOperand := AOperand;
  FIsPrefix := AIsPrefix;
end;

destructor TFloriaJSUnaryExpr.Destroy();
begin
  FreeAndNil(FOperand);
  inherited Destroy();
end;

procedure TFloriaJSUnaryExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitUnary(Self);
end;

{ TFloriaJSBinaryExpr }

constructor TFloriaJSBinaryExpr.Create(ALeft: TFloriaJSExprNode; AOp: TFloriaJSTokenKind; ARight: TFloriaJSExprNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FLeft := ALeft;
  FOperator := AOp;
  FRight := ARight;
end;

destructor TFloriaJSBinaryExpr.Destroy();
begin
  FreeAndNil(FLeft);
  FreeAndNil(FRight);
  inherited Destroy();
end;

procedure TFloriaJSBinaryExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitBinary(Self);
end;

function TFloriaJSBinaryExpr.ExtractLeft(): TFloriaJSExprNode;
begin
  Result := FLeft;
  FLeft := nil;
end;

function TFloriaJSBinaryExpr.ExtractRight(): TFloriaJSExprNode;
begin
  Result := FRight;
  FRight := nil;
end;

{ TFloriaJSConditionalExpr }

constructor TFloriaJSConditionalExpr.Create(ACond, AConsequent, AAlternate: TFloriaJSExprNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FCondition := ACond;
  FConsequent := AConsequent;
  FAlternate := AAlternate;
end;

destructor TFloriaJSConditionalExpr.Destroy();
begin
  FreeAndNil(FCondition);
  FreeAndNil(FConsequent);
  FreeAndNil(FAlternate);
  inherited Destroy();
end;

procedure TFloriaJSConditionalExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitConditional(Self);
end;

{ TFloriaJSAssignExpr }

constructor TFloriaJSAssignExpr.Create(ATarget: TFloriaJSExprNode; AOp: TFloriaJSTokenKind; AValue: TFloriaJSExprNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FTarget := ATarget;
  FOperator := AOp;
  FValue := AValue;
end;

destructor TFloriaJSAssignExpr.Destroy();
begin
  FreeAndNil(FTarget);
  FreeAndNil(FValue);
  inherited Destroy();
end;

procedure TFloriaJSAssignExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitAssign(Self);
end;

function TFloriaJSAssignExpr.ExtractTarget(): TFloriaJSExprNode;
begin
  Result := FTarget;
  FTarget := nil;
end;

function TFloriaJSAssignExpr.ExtractValue(): TFloriaJSExprNode;
begin
  Result := FValue;
  FValue := nil;
end;

{ TFloriaJSMemberExpr }

constructor TFloriaJSMemberExpr.CreateNamed(ATarget: TFloriaJSExprNode; const APropName: string; ALine, ACol: Integer; AIsOptional: Boolean);
begin
  inherited Create(ALine, ACol);
  FTarget := ATarget;
  FPropertyName := APropName;
  FPropertyExpr := nil;
  FComputed := False;
  FIsOptional := AIsOptional;
end;

constructor TFloriaJSMemberExpr.CreateComputed(ATarget, APropExpr: TFloriaJSExprNode; ALine, ACol: Integer; AIsOptional: Boolean);
begin
  inherited Create(ALine, ACol);
  FTarget := ATarget;
  FPropertyName := '';
  FPropertyExpr := APropExpr;
  FComputed := True;
  FIsOptional := AIsOptional;
end;

destructor TFloriaJSMemberExpr.Destroy();
begin
  FreeAndNil(FTarget);
  FreeAndNil(FPropertyExpr);
  inherited Destroy();
end;

procedure TFloriaJSMemberExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitMember(Self);
end;

{ TFloriaJSCallExpr }

constructor TFloriaJSCallExpr.Create(ACallee: TFloriaJSExprNode; ALine, ACol: Integer; AIsNew: Boolean; AIsOptional: Boolean);
begin
  inherited Create(ALine, ACol);
  FCallee := ACallee;
  FArguments := TFPList.Create();
  FIsNew := AIsNew;
  FIsOptional := AIsOptional;
end;

destructor TFloriaJSCallExpr.Destroy();
var
  i: Integer;
begin
  FreeAndNil(FCallee);
  if FArguments <> nil then
  begin
    for i := FArguments.Count - 1 downto 0 do
      TFloriaJSExprNode(FArguments[i]).Free();
    FreeAndNil(FArguments);
  end;
  inherited Destroy();
end;

procedure TFloriaJSCallExpr.AddArgument(AArg: TFloriaJSExprNode);
begin
  if (AArg <> nil) and (FArguments <> nil) then
    FArguments.Add(AArg);
end;

function TFloriaJSCallExpr.GetArgumentCount(): Integer;
begin
  if FArguments <> nil then
    Result := FArguments.Count
  else
    Result := 0;
end;

function TFloriaJSCallExpr.GetArgument(AIndex: Integer): TFloriaJSExprNode;
begin
  if (FArguments <> nil) and (AIndex >= 0) and (AIndex < FArguments.Count) then
    Result := TFloriaJSExprNode(FArguments[AIndex])
  else
    Result := nil;
end;

procedure TFloriaJSCallExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitCall(Self);
end;

{ TFloriaJSArrayExpr }

constructor TFloriaJSArrayExpr.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FElements := TFPList.Create();
end;

destructor TFloriaJSArrayExpr.Destroy();
var
  i: Integer;
begin
  if FElements <> nil then
  begin
    for i := FElements.Count - 1 downto 0 do
      TFloriaJSExprNode(FElements[i]).Free();
    FreeAndNil(FElements);
  end;
  inherited Destroy();
end;

procedure TFloriaJSArrayExpr.AddElement(AElem: TFloriaJSExprNode);
begin
  if FElements <> nil then
    FElements.Add(AElem);
end;

function TFloriaJSArrayExpr.GetElementCount(): Integer;
begin
  if FElements <> nil then
    Result := FElements.Count
  else
    Result := 0;
end;

function TFloriaJSArrayExpr.GetElement(AIndex: Integer): TFloriaJSExprNode;
begin
  if (FElements <> nil) and (AIndex >= 0) and (AIndex < FElements.Count) then
    Result := TFloriaJSExprNode(FElements[AIndex])
  else
    Result := nil;
end;

procedure TFloriaJSArrayExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitArray(Self);
end;

{ TFloriaJSSpreadExpr }

constructor TFloriaJSSpreadExpr.Create(AExpr: TFloriaJSExprNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FExpression := AExpr;
end;

destructor TFloriaJSSpreadExpr.Destroy();
begin
  if FExpression <> nil then
    FreeAndNil(FExpression);
  inherited Destroy();
end;

procedure TFloriaJSSpreadExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if (AVisitor <> nil) and (FExpression <> nil) then
    FExpression.Accept(AVisitor);
end;

function TFloriaJSSpreadExpr.ExtractExpression(): TFloriaJSExprNode;
begin
  Result := FExpression;
  FExpression := nil;
end;

{ TFloriaJSGroupExpr }

constructor TFloriaJSGroupExpr.Create(AExpr: TFloriaJSExprNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FExpression := AExpr;
end;

destructor TFloriaJSGroupExpr.Destroy();
begin
  if FExpression <> nil then
    FreeAndNil(FExpression);
  inherited Destroy();
end;

procedure TFloriaJSGroupExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then
    AVisitor.VisitGroup(Self);
end;

function TFloriaJSGroupExpr.ExtractExpression(): TFloriaJSExprNode;
begin
  Result := FExpression;
  FExpression := nil;
end;

{ TFloriaJSObjectExpr }

constructor TFloriaJSObjectExpr.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FCount := 0;
  SetLength(FProperties, 0);
end;

destructor TFloriaJSObjectExpr.Destroy();
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
  begin
    if FProperties[i].Value <> nil then
      FreeAndNil(FProperties[i].Value);
    if FProperties[i].KeyExpr <> nil then
      FreeAndNil(FProperties[i].KeyExpr);
  end;
  SetLength(FProperties, 0);
  inherited Destroy();
end;

procedure TFloriaJSObjectExpr.AddProperty(const AKey: string; AValue: TFloriaJSExprNode);
begin
  if FCount >= Length(FProperties) then
    SetLength(FProperties, (FCount + 1) * 2);
  FProperties[FCount].Key := AKey;
  FProperties[FCount].KeyExpr := nil;
  FProperties[FCount].Value := AValue;
  FProperties[FCount].Kind := fjpkNormal;
  Inc(FCount);
end;

procedure TFloriaJSObjectExpr.AddComputedProperty(AKeyExpr: TFloriaJSExprNode; AValue: TFloriaJSExprNode);
begin
  if FCount >= Length(FProperties) then
    SetLength(FProperties, (FCount + 1) * 2);
  FProperties[FCount].Key := '';
  FProperties[FCount].KeyExpr := AKeyExpr;
  FProperties[FCount].Value := AValue;
  FProperties[FCount].Kind := fjpkComputed;
  Inc(FCount);
end;

procedure TFloriaJSObjectExpr.AddSpreadProperty(ASpreadExpr: TFloriaJSExprNode);
begin
  if FCount >= Length(FProperties) then
    SetLength(FProperties, (FCount + 1) * 2);
  FProperties[FCount].Key := '';
  FProperties[FCount].KeyExpr := nil;
  FProperties[FCount].Value := ASpreadExpr;
  FProperties[FCount].Kind := fjpkSpread;
  Inc(FCount);
end;

procedure TFloriaJSObjectExpr.AddGetter(const AKey: string; AGetter: TFloriaJSExprNode; AKeyExpr: TFloriaJSExprNode = nil);
begin
  if FCount >= Length(FProperties) then
    SetLength(FProperties, (FCount + 1) * 2);
  FProperties[FCount].Key := AKey;
  FProperties[FCount].KeyExpr := AKeyExpr;
  FProperties[FCount].Value := AGetter;
  FProperties[FCount].Kind := fjpkGetter;
  Inc(FCount);
end;

procedure TFloriaJSObjectExpr.AddSetter(const AKey: string; ASetter: TFloriaJSExprNode; AKeyExpr: TFloriaJSExprNode = nil);
begin
  if FCount >= Length(FProperties) then
    SetLength(FProperties, (FCount + 1) * 2);
  FProperties[FCount].Key := AKey;
  FProperties[FCount].KeyExpr := AKeyExpr;
  FProperties[FCount].Value := ASetter;
  FProperties[FCount].Kind := fjpkSetter;
  Inc(FCount);
end;

function TFloriaJSObjectExpr.GetPropertyCount(): Integer;
begin
  Result := FCount;
end;

function TFloriaJSObjectExpr.GetPropertyKey(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FCount) then
    Result := FProperties[AIndex].Key
  else
    Result := '';
end;

function TFloriaJSObjectExpr.GetPropertyValue(AIndex: Integer): TFloriaJSExprNode;
begin
  if (AIndex >= 0) and (AIndex < FCount) then
    Result := FProperties[AIndex].Value
  else
    Result := nil;
end;

function TFloriaJSObjectExpr.GetPropertyKeyExpr(AIndex: Integer): TFloriaJSExprNode;
begin
  if (AIndex >= 0) and (AIndex < FCount) then
    Result := FProperties[AIndex].KeyExpr
  else
    Result := nil;
end;

function TFloriaJSObjectExpr.GetPropertyKind(AIndex: Integer): TFloriaJSPropertyKind;
begin
  if (AIndex >= 0) and (AIndex < FCount) then
    Result := FProperties[AIndex].Kind
  else
    Result := fjpkNormal;
end;

procedure TFloriaJSObjectExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitObject(Self);
end;

{ TFloriaJSFunctionExpr }

constructor TFloriaJSFunctionExpr.Create(const AName: string; AIsArrow: Boolean; ALine, ACol: Integer; AIsAsync: Boolean);
begin
  inherited Create(ALine, ACol);
  FName := AName;
  FIsArrow := AIsArrow;
  FIsAsync := AIsAsync;
  FParameters := TStringList.Create();
  FBody := nil;
end;

destructor TFloriaJSFunctionExpr.Destroy();
var
  i: Integer;
begin
  if FParameters <> nil then
  begin
    for i := 0 to FParameters.Count - 1 do
      if FParameters.Objects[i] <> nil then
        TFloriaJSASTNode(FParameters.Objects[i]).Release();
    FreeAndNil(FParameters);
  end;
  { The body is shared with every closure created from this expression, so it
    is released instead of being freed: a closure keeps a valid body even
    after the script that declared it has been discarded. }
  if FBody <> nil then
  begin
    FBody.Release();
    FBody := nil;
  end;
  inherited Destroy();
end;

procedure TFloriaJSFunctionExpr.AddParameter(const AParamName: string; ADefaultExpr: TFloriaJSExprNode = nil);
begin
  if FParameters <> nil then
    FParameters.AddObject(AParamName, ADefaultExpr);
end;

procedure TFloriaJSFunctionExpr.AddDestructParameter(APattern: TFloriaJSExprNode; ADefaultExpr: TFloriaJSExprNode = nil);
begin
  if FParameters <> nil then
  begin
    if ADefaultExpr <> nil then
      FParameters.AddObject('', TFloriaJSAssignExpr.Create(APattern, tkAssign, ADefaultExpr, APattern.Line, APattern.Column))
    else
      FParameters.AddObject('', APattern);
  end;
end;

procedure TFloriaJSFunctionExpr.SetBody(ABody: TFloriaJSStmtNode);
begin
  if FBody <> nil then
  begin
    FBody.Release;
    FBody := nil;
  end;
  FBody := ABody;
end;

procedure TFloriaJSFunctionExpr.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitFunctionExpr(Self);
end;

{ TFloriaJSExprStmt }

constructor TFloriaJSExprStmt.Create(AExpr: TFloriaJSExprNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FExpression := AExpr;
end;

destructor TFloriaJSExprStmt.Destroy();
begin
  FreeAndNil(FExpression);
  inherited Destroy();
end;

procedure TFloriaJSExprStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitExprStmt(Self);
end;

{ TFloriaJSVarStmt }

constructor TFloriaJSVarStmt.Create(AKind: TFloriaJSTokenKind; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FKind := AKind;
  FCount := 0;
  SetLength(FDeclarators, 0);
end;

destructor TFloriaJSVarStmt.Destroy();
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
  begin
    if FDeclarators[i].Pattern <> nil then
      FreeAndNil(FDeclarators[i].Pattern);
    if FDeclarators[i].Initializer <> nil then
      FreeAndNil(FDeclarators[i].Initializer);
  end;
  SetLength(FDeclarators, 0);
  inherited Destroy();
end;

procedure TFloriaJSVarStmt.AddDeclarator(const AName: string; AInit: TFloriaJSExprNode);
begin
  if FCount >= Length(FDeclarators) then
    SetLength(FDeclarators, (FCount + 1) * 2);
  FDeclarators[FCount].Name := AName;
  FDeclarators[FCount].Pattern := nil;
  FDeclarators[FCount].Initializer := AInit;
  Inc(FCount);
end;

procedure TFloriaJSVarStmt.AddDestructDeclarator(APattern: TFloriaJSExprNode; AInit: TFloriaJSExprNode);
begin
  if FCount >= Length(FDeclarators) then
    SetLength(FDeclarators, (FCount + 1) * 2);
  FDeclarators[FCount].Name := '';
  FDeclarators[FCount].Pattern := APattern;
  FDeclarators[FCount].Initializer := AInit;
  Inc(FCount);
end;

function TFloriaJSVarStmt.GetDeclaratorCount(): Integer;
begin
  Result := FCount;
end;

function TFloriaJSVarStmt.GetDeclaratorName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FCount) then
    Result := FDeclarators[AIndex].Name
  else
    Result := '';
end;

function TFloriaJSVarStmt.GetDeclaratorPattern(AIndex: Integer): TFloriaJSExprNode;
begin
  if (AIndex >= 0) and (AIndex < FCount) then
    Result := FDeclarators[AIndex].Pattern
  else
    Result := nil;
end;

function TFloriaJSVarStmt.GetDeclaratorInit(AIndex: Integer): TFloriaJSExprNode;
begin
  if (AIndex >= 0) and (AIndex < FCount) then
    Result := FDeclarators[AIndex].Initializer
  else
    Result := nil;
end;

procedure TFloriaJSVarStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitVarStmt(Self);
end;

{ TFloriaJSBlockStmt }

constructor TFloriaJSBlockStmt.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FStatements := TFPList.Create();
end;

destructor TFloriaJSBlockStmt.Destroy();
var
  i: Integer;
begin
  if FStatements <> nil then
  begin
    for i := FStatements.Count - 1 downto 0 do
      TFloriaJSStmtNode(FStatements[i]).Free();
    FreeAndNil(FStatements);
  end;
  inherited Destroy();
end;

procedure TFloriaJSBlockStmt.AddStatement(AStmt: TFloriaJSStmtNode);
begin
  if (AStmt <> nil) and (FStatements <> nil) then
    FStatements.Add(AStmt);
end;

function TFloriaJSBlockStmt.GetStatementCount(): Integer;
begin
  if FStatements <> nil then
    Result := FStatements.Count
  else
    Result := 0;
end;

function TFloriaJSBlockStmt.GetStatement(AIndex: Integer): TFloriaJSStmtNode;
begin
  if (FStatements <> nil) and (AIndex >= 0) and (AIndex < FStatements.Count) then
    Result := TFloriaJSStmtNode(FStatements[AIndex])
  else
    Result := nil;
end;

procedure TFloriaJSBlockStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitBlockStmt(Self);
end;

{ TFloriaJSIfStmt }

constructor TFloriaJSIfStmt.Create(ACond: TFloriaJSExprNode; AConsequent: TFloriaJSStmtNode; AAlternate: TFloriaJSStmtNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FCondition := ACond;
  FConsequent := AConsequent;
  FAlternate := AAlternate;
end;

destructor TFloriaJSIfStmt.Destroy();
begin
  FreeAndNil(FCondition);
  FreeAndNil(FConsequent);
  FreeAndNil(FAlternate);
  inherited Destroy();
end;

procedure TFloriaJSIfStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitIfStmt(Self);
end;

{ TFloriaJSReturnStmt }

constructor TFloriaJSReturnStmt.Create(AArg: TFloriaJSExprNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FArgument := AArg;
end;

destructor TFloriaJSReturnStmt.Destroy();
begin
  FreeAndNil(FArgument);
  inherited Destroy();
end;

procedure TFloriaJSReturnStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitReturnStmt(Self);
end;

{ TFloriaJSWhileStmt }

constructor TFloriaJSWhileStmt.Create(ACond: TFloriaJSExprNode; ABody: TFloriaJSStmtNode; AIsDoWhile: Boolean; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FCondition := ACond;
  FBody := ABody;
  FIsDoWhile := AIsDoWhile;
end;

destructor TFloriaJSWhileStmt.Destroy();
begin
  FreeAndNil(FCondition);
  FreeAndNil(FBody);
  inherited Destroy();
end;

procedure TFloriaJSWhileStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitWhileStmt(Self);
end;

{ TFloriaJSForStmt }

constructor TFloriaJSForStmt.Create(AInit: TFloriaJSASTNode; ATest, AUpdate: TFloriaJSExprNode; ABody: TFloriaJSStmtNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FInit := AInit;
  FTest := ATest;
  FUpdate := AUpdate;
  FBody := ABody;
end;

destructor TFloriaJSForStmt.Destroy();
begin
  FreeAndNil(FInit);
  FreeAndNil(FTest);
  FreeAndNil(FUpdate);
  FreeAndNil(FBody);
  inherited Destroy();
end;

procedure TFloriaJSForStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitForStmt(Self);
end;

{ TFloriaJSForInOfStmt }

constructor TFloriaJSForInOfStmt.Create(AVarKind: TFloriaJSTokenKind; const AVarName: string; AIsOf: Boolean; AIterable: TFloriaJSExprNode; ABody: TFloriaJSStmtNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FVarKind := AVarKind;
  FVarName := AVarName;
  FIsOf := AIsOf;
  FIterable := AIterable;
  FBody := ABody;
end;

destructor TFloriaJSForInOfStmt.Destroy();
begin
  FreeAndNil(FIterable);
  FreeAndNil(FBody);
  inherited Destroy();
end;

procedure TFloriaJSForInOfStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitForInOfStmt(Self);
end;

{ TFloriaJSSwitchCase }

constructor TFloriaJSSwitchCase.Create(ATest: TFloriaJSExprNode; AIsDefault: Boolean);
begin
  inherited Create();
  FTest := ATest;
  FIsDefault := AIsDefault;
  FBody := TFPList.Create();
end;

destructor TFloriaJSSwitchCase.Destroy();
var
  i: Integer;
begin
  if FBody <> nil then
  begin
    for i := FBody.Count - 1 downto 0 do
      TFloriaJSStmtNode(FBody[i]).Free();
    FreeAndNil(FBody);
  end;
  FreeAndNil(FTest);
  inherited Destroy();
end;

procedure TFloriaJSSwitchCase.AddStatement(AStmt: TFloriaJSStmtNode);
begin
  if (AStmt <> nil) and (FBody <> nil) then
    FBody.Add(AStmt);
end;

function TFloriaJSSwitchCase.GetStatementCount(): Integer;
begin
  if FBody <> nil then
    Result := FBody.Count
  else
    Result := 0;
end;

function TFloriaJSSwitchCase.GetStatement(AIndex: Integer): TFloriaJSStmtNode;
begin
  if (FBody <> nil) and (AIndex >= 0) and (AIndex < FBody.Count) then
    Result := TFloriaJSStmtNode(FBody[AIndex])
  else
    Result := nil;
end;

{ TFloriaJSSwitchStmt }

constructor TFloriaJSSwitchStmt.Create(ADiscriminant: TFloriaJSExprNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FDiscriminant := ADiscriminant;
  FCases := TFPList.Create();
end;

destructor TFloriaJSSwitchStmt.Destroy();
var
  i: Integer;
begin
  if FCases <> nil then
  begin
    for i := FCases.Count - 1 downto 0 do
      TFloriaJSSwitchCase(FCases[i]).Free();
    FreeAndNil(FCases);
  end;
  FreeAndNil(FDiscriminant);
  inherited Destroy();
end;

procedure TFloriaJSSwitchStmt.AddCase(ACase: TFloriaJSSwitchCase);
begin
  if (ACase <> nil) and (FCases <> nil) then
    FCases.Add(ACase);
end;

function TFloriaJSSwitchStmt.GetCaseCount(): Integer;
begin
  if FCases <> nil then
    Result := FCases.Count
  else
    Result := 0;
end;

function TFloriaJSSwitchStmt.GetCase(AIndex: Integer): TFloriaJSSwitchCase;
begin
  if (FCases <> nil) and (AIndex >= 0) and (AIndex < FCases.Count) then
    Result := TFloriaJSSwitchCase(FCases[AIndex])
  else
    Result := nil;
end;

procedure TFloriaJSSwitchStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitSwitchStmt(Self);
end;

{ TFloriaJSTryStmt }

constructor TFloriaJSTryStmt.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FBlock := nil;
  FCatchParam := '';
  FCatchBlock := nil;
  FFinallyBlock := nil;
end;

destructor TFloriaJSTryStmt.Destroy();
begin
  FreeAndNil(FBlock);
  FreeAndNil(FCatchBlock);
  FreeAndNil(FFinallyBlock);
  inherited Destroy();
end;

procedure TFloriaJSTryStmt.SetBlock(ABlock: TFloriaJSBlockStmt);
begin
  FreeAndNil(FBlock);
  FBlock := ABlock;
end;

procedure TFloriaJSTryStmt.SetCatch(const AParam: string; ABlock: TFloriaJSBlockStmt);
begin
  FreeAndNil(FCatchBlock);
  FCatchParam := AParam;
  FCatchBlock := ABlock;
end;

procedure TFloriaJSTryStmt.SetFinally(ABlock: TFloriaJSBlockStmt);
begin
  FreeAndNil(FFinallyBlock);
  FFinallyBlock := ABlock;
end;

procedure TFloriaJSTryStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitTryStmt(Self);
end;

{ TFloriaJSThrowStmt }

constructor TFloriaJSThrowStmt.Create(AExpr: TFloriaJSExprNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FExpression := AExpr;
end;

destructor TFloriaJSThrowStmt.Destroy();
begin
  FreeAndNil(FExpression);
  inherited Destroy();
end;

procedure TFloriaJSThrowStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitThrowStmt(Self);
end;

{ TFloriaJSDebuggerStmt }

constructor TFloriaJSDebuggerStmt.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
end;

procedure TFloriaJSDebuggerStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  AVisitor.VisitDebuggerStmt(Self);
end;

{ TFloriaJSBreakStmt }

constructor TFloriaJSBreakStmt.Create(ALine, ACol: Integer; const ALabel: string = '');
begin
  inherited Create(ALine, ACol);
  FLabel := ALabel;
end;

procedure TFloriaJSBreakStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitBreakStmt(Self);
end;

{ TFloriaJSContinueStmt }

constructor TFloriaJSContinueStmt.Create(ALine, ACol: Integer; const ALabel: string = '');
begin
  inherited Create(ALine, ACol);
  FLabel := ALabel;
end;

procedure TFloriaJSContinueStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitContinueStmt(Self);
end;

{ TFloriaJSLabeledStmt }

constructor TFloriaJSLabeledStmt.Create(const ALabel: string; ABody: TFloriaJSStmtNode; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FLabel := ALabel;
  FBody := ABody;
end;

destructor TFloriaJSLabeledStmt.Destroy();
begin
  FreeAndNil(FBody);
  inherited Destroy();
end;

procedure TFloriaJSLabeledStmt.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitLabeledStmt(Self);
end;

{ TFloriaJSFunctionDecl }

constructor TFloriaJSFunctionDecl.Create(const AName: string; ALine, ACol: Integer; AIsAsync: Boolean);
begin
  inherited Create(ALine, ACol);
  FName := AName;
  FIsAsync := AIsAsync;
  FParameters := TStringList.Create();
  FBody := nil;
end;

destructor TFloriaJSFunctionDecl.Destroy();
var
  i: Integer;
begin
  if FParameters <> nil then
  begin
    for i := 0 to FParameters.Count - 1 do
      if FParameters.Objects[i] <> nil then
        TFloriaJSASTNode(FParameters.Objects[i]).Release();
    FreeAndNil(FParameters);
  end;
  { The body is shared with every closure created from this declaration, so it
    is released instead of being freed: a closure keeps a valid body even
    after the script that declared it has been discarded. }
  if FBody <> nil then
  begin
    FBody.Release();
    FBody := nil;
  end;
  inherited Destroy();
end;

procedure TFloriaJSFunctionDecl.AddParameter(const AParamName: string; ADefaultExpr: TFloriaJSExprNode = nil);
begin
  if FParameters <> nil then
    FParameters.AddObject(AParamName, ADefaultExpr);
end;

procedure TFloriaJSFunctionDecl.AddDestructParameter(APattern: TFloriaJSExprNode; ADefaultExpr: TFloriaJSExprNode = nil);
begin
  if FParameters <> nil then
  begin
    if ADefaultExpr <> nil then
      FParameters.AddObject('', TFloriaJSAssignExpr.Create(APattern, tkAssign, ADefaultExpr, APattern.Line, APattern.Column))
    else
      FParameters.AddObject('', APattern);
  end;
end;

procedure TFloriaJSFunctionDecl.SetBody(ABody: TFloriaJSBlockStmt);
begin
  if FBody <> nil then
  begin
    FBody.Release;
    FBody := nil;
  end;
  FBody := ABody;
end;

procedure TFloriaJSFunctionDecl.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitFunctionDecl(Self);
end;

{ TFloriaJSProgram }

constructor TFloriaJSProgram.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FStatements := TFPList.Create();
end;

destructor TFloriaJSProgram.Destroy();
var
  i: Integer;
begin
  if FStatements <> nil then
  begin
    for i := FStatements.Count - 1 downto 0 do
      TFloriaJSStmtNode(FStatements[i]).Free();
    FreeAndNil(FStatements);
  end;
  inherited Destroy();
end;

procedure TFloriaJSProgram.AddStatement(AStmt: TFloriaJSStmtNode);
begin
  if (AStmt <> nil) and (FStatements <> nil) then
    FStatements.Add(AStmt);
end;

function TFloriaJSProgram.GetStatementCount(): Integer;
begin
  if FStatements <> nil then
    Result := FStatements.Count
  else
    Result := 0;
end;

function TFloriaJSProgram.GetStatement(AIndex: Integer): TFloriaJSStmtNode;
begin
  if (FStatements <> nil) and (AIndex >= 0) and (AIndex < FStatements.Count) then
    Result := TFloriaJSStmtNode(FStatements[AIndex])
  else
    Result := nil;
end;

procedure TFloriaJSProgram.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then AVisitor.VisitProgram(Self);
end;

{ TFloriaFTMLComponent }

constructor TFloriaFTMLComponent.Create(const AComponentType: string; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);
  FComponentType := AComponentType;
  FId := '';
  FPropCount := 0;
  SetLength(FProperties, 0);
  FSignalCount := 0;
  SetLength(FSignals, 0);
  FFunctions := TFPList.Create();
  FChildren := TFPList.Create();
end;

destructor TFloriaFTMLComponent.Destroy();
var
  i: Integer;
begin
  for i := 0 to FPropCount - 1 do
    FProperties[i].Expression.Free();
  SetLength(FProperties, 0);

  for i := 0 to FSignalCount - 1 do
    FSignals[i].Handler.Free();
  SetLength(FSignals, 0);

  if FFunctions <> nil then
  begin
    for i := FFunctions.Count - 1 downto 0 do
      TFloriaJSFunctionDecl(FFunctions[i]).Free();
    FreeAndNil(FFunctions);
  end;

  if FChildren <> nil then
  begin
    for i := FChildren.Count - 1 downto 0 do
      TFloriaFTMLComponent(FChildren[i]).Free();
    FreeAndNil(FChildren);
  end;
  inherited Destroy();
end;

procedure TFloriaFTMLComponent.AddProperty(const AName: string; AExpr: TFloriaJSExprNode);
begin
  if FPropCount >= Length(FProperties) then
    SetLength(FProperties, (FPropCount + 1) * 2);
  FProperties[FPropCount].Name := AName;
  FProperties[FPropCount].Expression := AExpr;
  Inc(FPropCount);
end;

procedure TFloriaFTMLComponent.AddSignal(const ASignalName: string; AHandler: TFloriaJSStmtNode);
begin
  if FSignalCount >= Length(FSignals) then
    SetLength(FSignals, (FSignalCount + 1) * 2);
  FSignals[FSignalCount].SignalName := ASignalName;
  FSignals[FSignalCount].Handler := AHandler;
  Inc(FSignalCount);
end;

procedure TFloriaFTMLComponent.AddChild(AChild: TFloriaFTMLComponent);
begin
  if (AChild <> nil) and (FChildren <> nil) then
    FChildren.Add(AChild);
end;

function TFloriaFTMLComponent.GetPropertyCount(): Integer;
begin
  Result := FPropCount;
end;

function TFloriaFTMLComponent.GetPropertyName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FPropCount) then
    Result := FProperties[AIndex].Name
  else
    Result := '';
end;

function TFloriaFTMLComponent.GetPropertyExpr(AIndex: Integer): TFloriaJSExprNode;
begin
  if (AIndex >= 0) and (AIndex < FPropCount) then
    Result := FProperties[AIndex].Expression
  else
    Result := nil;
end;

function TFloriaFTMLComponent.GetSignalCount(): Integer;
begin
  Result := FSignalCount;
end;

function TFloriaFTMLComponent.GetSignalName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FSignalCount) then
    Result := FSignals[AIndex].SignalName
  else
    Result := '';
end;

function TFloriaFTMLComponent.GetSignalHandler(AIndex: Integer): TFloriaJSStmtNode;
begin
  if (AIndex >= 0) and (AIndex < FSignalCount) then
    Result := FSignals[AIndex].Handler
  else
    Result := nil;
end;

function TFloriaFTMLComponent.GetChildCount(): Integer;
begin
  if FChildren <> nil then
    Result := FChildren.Count
  else
    Result := 0;
end;

function TFloriaFTMLComponent.GetChild(AIndex: Integer): TFloriaFTMLComponent;
begin
  if (FChildren <> nil) and (AIndex >= 0) and (AIndex < FChildren.Count) then
    Result := TFloriaFTMLComponent(FChildren[AIndex])
  else
    Result := nil;
end;

procedure TFloriaFTMLComponent.AddFunction(AFunc: TFloriaJSFunctionDecl);
begin
  if (AFunc <> nil) and (FFunctions <> nil) then
    FFunctions.Add(AFunc);
end;

function TFloriaFTMLComponent.GetFunctionCount(): Integer;
begin
  if FFunctions <> nil then
    Result := FFunctions.Count
  else
    Result := 0;
end;

function TFloriaFTMLComponent.GetFunction(AIndex: Integer): TFloriaJSFunctionDecl;
begin
  if (FFunctions <> nil) and (AIndex >= 0) and (AIndex < FFunctions.Count) then
    Result := TFloriaJSFunctionDecl(FFunctions[AIndex])
  else
    Result := nil;
end;

procedure TFloriaFTMLComponent.Accept(AVisitor: IFloriaJSASTVisitor);
begin
  if AVisitor <> nil then
  begin
    AVisitor.VisitFTMLComponent(Self);
  end;
end;

function ContainsOptionalChain(ANode: TFloriaJSExprNode): Boolean;
begin
  if ANode = nil then
    Exit(False);

  if ANode is TFloriaJSGroupExpr then
    Exit(False);

  if ANode is TFloriaJSMemberExpr then
  begin
    if TFloriaJSMemberExpr(ANode).IsOptional then
      Exit(True);
    Exit(ContainsOptionalChain(TFloriaJSMemberExpr(ANode).Target));
  end;

  if ANode is TFloriaJSCallExpr then
  begin
    if TFloriaJSCallExpr(ANode).IsNew then
      Exit(False);
    if TFloriaJSCallExpr(ANode).IsOptional then
      Exit(True);
    Exit(ContainsOptionalChain(TFloriaJSCallExpr(ANode).Callee));
  end;

  Result := False;
end;

end.
