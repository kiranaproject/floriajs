{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Umbrella Unit                                   }
{                                                                          }
{   Re-exports core classes, records, and types for single-unit inclusion: }
{   `uses floriajs;`                                                       }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floriajs;

{$mode objfpc}{$H+}

interface

uses
  floria.js.types,
  floria.js.lexer,
  floria.js.ast,
  floria.js.parser,
  floria.js.value,
  floria.js.env,
  floria.js.evaluator,
  floria.js.stdlib,
  floria.js.core,
  floria.ftml.types,
  floria.ftml.binding,
  floria.ftml.engine;

type
  { Core Types & Constants }
  TFloriaJSType            = floria.js.types.TFloriaJSType;
  TFloriaJSResult          = floria.js.types.TFloriaJSResult;

  { Lexer & Tokens }
  TFloriaJSTokenKind       = floria.js.lexer.TFloriaJSTokenKind;
  TFloriaJSToken           = floria.js.lexer.TFloriaJSToken;
  TFloriaJSLexer           = floria.js.lexer.TFloriaJSLexer;

  { AST Hierarchy }
  TFloriaJSASTNode         = floria.js.ast.TFloriaJSASTNode;
  TFloriaJSExprNode        = floria.js.ast.TFloriaJSExprNode;
  TFloriaJSStmtNode        = floria.js.ast.TFloriaJSStmtNode;
  IFloriaJSASTVisitor      = floria.js.ast.IFloriaJSASTVisitor;

  { Expressions }
  TFloriaJSLiteralExpr     = floria.js.ast.TFloriaJSLiteralExpr;
  TFloriaJSIdentifierExpr  = floria.js.ast.TFloriaJSIdentifierExpr;
  TFloriaJSUnaryExpr       = floria.js.ast.TFloriaJSUnaryExpr;
  TFloriaJSBinaryExpr      = floria.js.ast.TFloriaJSBinaryExpr;
  TFloriaJSConditionalExpr = floria.js.ast.TFloriaJSConditionalExpr;
  TFloriaJSAssignExpr      = floria.js.ast.TFloriaJSAssignExpr;
  TFloriaJSMemberExpr      = floria.js.ast.TFloriaJSMemberExpr;
  TFloriaJSCallExpr        = floria.js.ast.TFloriaJSCallExpr;
  TFloriaJSArrayExpr       = floria.js.ast.TFloriaJSArrayExpr;
  TFloriaJSObjectExpr      = floria.js.ast.TFloriaJSObjectExpr;
  TFloriaJSFunctionExpr    = floria.js.ast.TFloriaJSFunctionExpr;

  { Statements }
  TFloriaJSExprStmt        = floria.js.ast.TFloriaJSExprStmt;
  TFloriaJSVarStmt         = floria.js.ast.TFloriaJSVarStmt;
  TFloriaJSBlockStmt       = floria.js.ast.TFloriaJSBlockStmt;
  TFloriaJSIfStmt          = floria.js.ast.TFloriaJSIfStmt;
  TFloriaJSReturnStmt      = floria.js.ast.TFloriaJSReturnStmt;
  TFloriaJSWhileStmt       = floria.js.ast.TFloriaJSWhileStmt;
  TFloriaJSForStmt         = floria.js.ast.TFloriaJSForStmt;
  TFloriaJSBreakStmt       = floria.js.ast.TFloriaJSBreakStmt;
  TFloriaJSContinueStmt    = floria.js.ast.TFloriaJSContinueStmt;
  TFloriaJSFunctionDecl    = floria.js.ast.TFloriaJSFunctionDecl;
  TFloriaJSProgram         = floria.js.ast.TFloriaJSProgram;

  { Declarative / FTML Component Node }
  TFloriaFTMLComponent     = floria.js.ast.TFloriaFTMLComponent;
  TFloriaJSQMLComponent    = floria.js.ast.TFloriaFTMLComponent;

  { Parser }
  TFloriaJSParser          = floria.js.parser.TFloriaJSParser;

  { Values, Objects, and Heap }
  TFloriaJSValue           = floria.js.value.TFloriaJSValue;
  TFloriaJSObject          = floria.js.value.TFloriaJSObject;
  TFloriaJSArray           = floria.js.value.TFloriaJSArray;
  TFloriaJSFunction        = floria.js.value.TFloriaJSFunction;
  TFloriaJSHeap            = floria.js.value.TFloriaJSHeap;
  TFloriaJSNativeProc      = floria.js.value.TFloriaJSNativeProc;
  TFloriaJSNativeMethod    = floria.js.value.TFloriaJSNativeMethod;

  { Environment & Evaluator }
  TFloriaJSEnvironment     = floria.js.env.TFloriaJSEnvironment;
  TFloriaJSEvaluator       = floria.js.evaluator.TFloriaJSEvaluator;

  { Runtime & Context }
  TFloriaJSContext         = floria.js.core.TFloriaJSContext;
  TFloriaJSEngine          = floria.js.core.TFloriaJSEngine;

  { Declarative FTML Framework (Floria Toolkit Markup Language) }
  TFloriaFTMLItem           = floria.ftml.types.TFloriaFTMLItem;
  TFloriaFTMLItemClass      = floria.ftml.types.TFloriaFTMLItemClass;
  TFloriaFTMLRectangle      = floria.ftml.types.TFloriaFTMLRectangle;
  TFloriaFTMLText           = floria.ftml.types.TFloriaFTMLText;
  TFloriaFTMLButton         = floria.ftml.types.TFloriaFTMLButton;
  TFloriaFTMLTextInput      = floria.ftml.types.TFloriaFTMLTextInput;
  TFloriaFTMLColumn         = floria.ftml.types.TFloriaFTMLColumn;
  TFloriaFTMLRow            = floria.ftml.types.TFloriaFTMLRow;
  IFloriaFTMLBindingManager = floria.ftml.types.IFloriaFTMLBindingManager;
  IFloriaFTMLEngineContext  = floria.ftml.types.IFloriaFTMLEngineContext;

  TFloriaFTMLBinding        = floria.ftml.binding.TFloriaFTMLBinding;
  TFloriaFTMLBindingManager = floria.ftml.binding.TFloriaFTMLBindingManager;
  TFloriaFTMLEngine         = floria.ftml.engine.TFloriaFTMLEngine;

  { Backward Compatibility Aliases }
  TFloriaQMLItem           = TFloriaFTMLItem;
  TFloriaQMLItemClass      = TFloriaFTMLItemClass;
  TFloriaQMLRectangle      = TFloriaFTMLRectangle;
  TFloriaQMLText           = TFloriaFTMLText;
  TFloriaQMLButton         = TFloriaFTMLButton;
  TFloriaQMLTextInput      = TFloriaFTMLTextInput;
  TFloriaQMLColumn         = TFloriaFTMLColumn;
  TFloriaQMLRow            = TFloriaFTMLRow;
  IFloriaQMLBindingManager = IFloriaFTMLBindingManager;
  IFloriaQMLEngineContext  = IFloriaFTMLEngineContext;
  TFloriaQMLBinding        = TFloriaFTMLBinding;
  TFloriaQMLBindingManager = TFloriaFTMLBindingManager;
  TFloriaQMLEngine         = TFloriaFTMLEngine;

const
  FLORIA_JS_VERSION_STRING = floria.js.types.FLORIA_JS_VERSION_STRING;
  FLORIA_JS_OK             = floria.js.types.FLORIA_JS_OK;
  FLORIA_JS_ERROR_GENERIC  = floria.js.types.FLORIA_JS_ERROR_GENERIC;
  FLORIA_JS_ERROR_SYNTAX   = floria.js.types.FLORIA_JS_ERROR_SYNTAX;
  FLORIA_JS_ERROR_TYPE     = floria.js.types.FLORIA_JS_ERROR_TYPE;
  FLORIA_JS_ERROR_TIMEOUT  = floria.js.types.FLORIA_JS_ERROR_TIMEOUT;

{ Value Factory Helpers }
function JSMakeUndefined(): TFloriaJSValue;
function JSMakeNull(): TFloriaJSValue;
function JSMakeBoolean(ABool: Boolean): TFloriaJSValue;
function JSMakeNumber(ANum: Double): TFloriaJSValue;
function JSMakeString(const AStr: string): TFloriaJSValue;
function JSMakeObject(AObj: TFloriaJSObject): TFloriaJSValue;
function JSMakeArray(AArr: TFloriaJSArray): TFloriaJSValue;
function JSMakeFunction(AFunc: TFloriaJSFunction): TFloriaJSValue;

implementation

function JSMakeUndefined(): TFloriaJSValue;
begin
  Result := floria.js.value.JSMakeUndefined();
end;

function JSMakeNull(): TFloriaJSValue;
begin
  Result := floria.js.value.JSMakeNull();
end;

function JSMakeBoolean(ABool: Boolean): TFloriaJSValue;
begin
  Result := floria.js.value.JSMakeBoolean(ABool);
end;

function JSMakeNumber(ANum: Double): TFloriaJSValue;
begin
  Result := floria.js.value.JSMakeNumber(ANum);
end;

function JSMakeString(const AStr: string): TFloriaJSValue;
begin
  Result := floria.js.value.JSMakeString(AStr);
end;

function JSMakeObject(AObj: TFloriaJSObject): TFloriaJSValue;
begin
  Result := floria.js.value.JSMakeObject(AObj);
end;

function JSMakeArray(AArr: TFloriaJSArray): TFloriaJSValue;
begin
  Result := floria.js.value.JSMakeArray(AArr);
end;

function JSMakeFunction(AFunc: TFloriaJSFunction): TFloriaJSValue;
begin
  Result := floria.js.value.JSMakeFunction(AFunc);
end;

end.
