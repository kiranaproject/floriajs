{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Core Types & Constants                          }
{                                                                          }
{   Defines fundamental types, records, and constants for JavaScript       }
{   engine integration and interop within the Floria ecosystem.            }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.types;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  FLORIA_JS_VERSION_MAJOR = 0;
  FLORIA_JS_VERSION_MINOR = 0;
  FLORIA_JS_VERSION_PATCH = 1;
  FLORIA_JS_VERSION_STRING = '0.0.1-SNAPSHOT';

  { Result Codes }
  FLORIA_JS_OK            = 0;
  FLORIA_JS_ERROR_GENERIC = -1;
  FLORIA_JS_ERROR_SYNTAX  = -2;
  FLORIA_JS_ERROR_TYPE    = -3;
  FLORIA_JS_ERROR_TIMEOUT = -4;

type
  { JavaScript Value Tag / Type Enum }
  TFloriaJSType = (
    fjstUndefined,
    fjstNull,
    fjstBoolean,
    fjstNumber,
    fjstString,
    fjstObject,
    fjstArray,
    fjstFunction,
    fjstSymbol,
    fjstError,
    fjstBigInt
  );

  { Execution Result Record }
  TFloriaJSResult = record
    Success: Boolean;
    ResultType: TFloriaJSType;
    StringValue: string;
    NumberValue: Double;
    BooleanValue: Boolean;
    ErrorMessage: string;
  end;

  { Additive diagnostic classifications. These do not alter TFloriaJSResult or
    the slots of any existing class. }
  TFloriaJSDiagnosticKind = (
    fjdkSuccess,
    fjdkParseError,
    fjdkCompileError,
    { A module that could not be linked: an unresolved specifier, a missing or
      ambiguous export, or a module early error detected during linking. This
      is distinct from a parse error so a host can classify it as a resolution
      failure, which is what the specification's Link phase reports. }
    fjdkResolutionError,
    fjdkJavaScriptThrow,
    fjdkHostException
  );

  { Detailed execution information for hosts and conformance runners. All fields
    are managed values so a later heap collection cannot invalidate them. }
  TFloriaJSDiagnosticResult = record
    Result: TFloriaJSResult;
    Kind: TFloriaJSDiagnosticKind;
    ErrorName: string;
    Message: string;
    SourceName: string;
    Line: Integer;
    Column: Integer;
    HostExceptionClass: string;
  end;

function FloriaJSMakeOkResult(const AStringVal: string = ''): TFloriaJSResult;
function FloriaJSMakeErrorResult(const AErrorMsg: string): TFloriaJSResult;

implementation

function FloriaJSMakeOkResult(const AStringVal: string = ''): TFloriaJSResult;
begin
  Result.Success := True;
  Result.ResultType := fjstString;
  Result.StringValue := AStringVal;
  Result.NumberValue := 0.0;
  Result.BooleanValue := True;
  Result.ErrorMessage := '';
end;

function FloriaJSMakeErrorResult(const AErrorMsg: string): TFloriaJSResult;
begin
  Result.Success := False;
  Result.ResultType := fjstError;
  Result.StringValue := '';
  Result.NumberValue := 0.0;
  Result.BooleanValue := False;
  Result.ErrorMessage := AErrorMsg;
end;

end.
