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
  floria.js.core;

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

  { Declarative / QML Component Node }
  TFloriaJSQMLComponent    = floria.js.ast.TFloriaJSQMLComponent;

  { Parser }
  TFloriaJSParser          = floria.js.parser.TFloriaJSParser;

  { Runtime & Context }
  TFloriaJSContext         = floria.js.core.TFloriaJSContext;
  TFloriaJSEngine          = floria.js.core.TFloriaJSEngine;

const
  FLORIA_JS_VERSION_STRING = floria.js.types.FLORIA_JS_VERSION_STRING;
  FLORIA_JS_OK             = floria.js.types.FLORIA_JS_OK;
  FLORIA_JS_ERROR_GENERIC  = floria.js.types.FLORIA_JS_ERROR_GENERIC;
  FLORIA_JS_ERROR_SYNTAX   = floria.js.types.FLORIA_JS_ERROR_SYNTAX;
  FLORIA_JS_ERROR_TYPE     = floria.js.types.FLORIA_JS_ERROR_TYPE;
  FLORIA_JS_ERROR_TIMEOUT  = floria.js.types.FLORIA_JS_ERROR_TIMEOUT;

implementation

end.
