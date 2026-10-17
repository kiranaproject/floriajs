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
  floria.js.core;

type
  { Core Types & Constants }
  TFloriaJSType      = floria.js.types.TFloriaJSType;
  TFloriaJSResult    = floria.js.types.TFloriaJSResult;

  { Lexer & Tokens }
  TFloriaJSTokenKind = floria.js.lexer.TFloriaJSTokenKind;
  TFloriaJSToken     = floria.js.lexer.TFloriaJSToken;
  TFloriaJSLexer     = floria.js.lexer.TFloriaJSLexer;

  { Runtime & Context }
  TFloriaJSContext   = floria.js.core.TFloriaJSContext;
  TFloriaJSEngine    = floria.js.core.TFloriaJSEngine;

const
  FLORIA_JS_VERSION_STRING = floria.js.types.FLORIA_JS_VERSION_STRING;
  FLORIA_JS_OK             = floria.js.types.FLORIA_JS_OK;
  FLORIA_JS_ERROR_GENERIC  = floria.js.types.FLORIA_JS_ERROR_GENERIC;
  FLORIA_JS_ERROR_SYNTAX   = floria.js.types.FLORIA_JS_ERROR_SYNTAX;
  FLORIA_JS_ERROR_TYPE     = floria.js.types.FLORIA_JS_ERROR_TYPE;
  FLORIA_JS_ERROR_TIMEOUT  = floria.js.types.FLORIA_JS_ERROR_TIMEOUT;

implementation

end.
