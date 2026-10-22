{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Built-in Standard Library                       }
{                                                                          }
{   Provides standard JavaScript global objects (console, Math) and        }
{   built-in functions (parseInt, parseFloat, isNaN, isFinite).            }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.stdlib;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, floria.js.types, floria.js.value, floria.js.env;

type
  { Output Logging Callback }
  TFloriaJSLogHandler = procedure(const AMessage: string) of object;

procedure FloriaJSRegisterStdLib(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap; ALogOutput: TStrings = nil);

implementation

var
  GLogOutput: TStrings = nil;

function JoinArgs(const AArgs: array of TFloriaJSValue): string;
var
  sb: TStringBuilder;
  i: Integer;
begin
  if Length(AArgs) = 0 then Exit('');
  sb := TStringBuilder.Create();
  try
    for i := 0 to High(AArgs) do
    begin
      if i > 0 then sb.Append(' ');
      sb.Append(AArgs[i].ToString());
    end;
    Result := sb.ToString();
  finally
    sb.Free();
  end;
end;

{ Console Methods }

function JSConsoleLog(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  msg: string;
begin
  msg := JoinArgs(AArgs);
  if GLogOutput <> nil then
    GLogOutput.Add(msg)
  else
    WriteLn(msg);
  Result := JSMakeUndefined();
end;

function JSConsoleError(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  msg: string;
begin
  msg := '[ERROR] ' + JoinArgs(AArgs);
  if GLogOutput <> nil then
    GLogOutput.Add(msg)
  else
    WriteLn(StdErr, msg);
  Result := JSMakeUndefined();
end;

function JSConsoleWarn(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  msg: string;
begin
  msg := '[WARN] ' + JoinArgs(AArgs);
  if GLogOutput <> nil then
    GLogOutput.Add(msg)
  else
    WriteLn(msg);
  Result := JSMakeUndefined();
end;

{ Math Methods }

function JSMathAbs(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Abs(AArgs[0].ToNumber()));
end;

function JSMathAcos(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(ArcCos(AArgs[0].ToNumber()));
end;

function JSMathAsin(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(ArcSin(AArgs[0].ToNumber()));
end;

function JSMathAtan(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(ArcTan(AArgs[0].ToNumber()));
end;

function JSMathAtan2(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) < 2 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(ArcTan2(AArgs[0].ToNumber(), AArgs[1].ToNumber()));
end;

function JSMathCeil(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Ceil(AArgs[0].ToNumber()));
end;

function JSMathCos(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Cos(AArgs[0].ToNumber()));
end;

function JSMathExp(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Exp(AArgs[0].ToNumber()));
end;

function JSMathFloor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Floor(AArgs[0].ToNumber()));
end;

function JSMathLog(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Ln(AArgs[0].ToNumber()));
end;

function JSMathMax(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  i: Integer;
  m, v: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(-Infinity));
  m := AArgs[0].ToNumber();
  for i := 1 to High(AArgs) do
  begin
    v := AArgs[i].ToNumber();
    if IsNaN(v) then Exit(JSMakeNumber(NaN));
    if v > m then m := v;
  end;
  Result := JSMakeNumber(m);
end;

function JSMathMin(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  i: Integer;
  m, v: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(Infinity));
  m := AArgs[0].ToNumber();
  for i := 1 to High(AArgs) do
  begin
    v := AArgs[i].ToNumber();
    if IsNaN(v) then Exit(JSMakeNumber(NaN));
    if v < m then m := v;
  end;
  Result := JSMakeNumber(m);
end;

function JSMathPow(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) < 2 then Exit(JSMakeNumber(NaN));
  Result := JSPower(AArgs[0], AArgs[1]);
end;

function JSMathRandom(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(Random());
end;

function JSMathRound(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Round(AArgs[0].ToNumber()));
end;

function JSMathSin(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Sin(AArgs[0].ToNumber()));
end;

function JSMathSqrt(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Sqrt(AArgs[0].ToNumber()));
end;

function JSMathTan(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Tan(AArgs[0].ToNumber()));
end;

function JSMathTrunc(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Trunc(AArgs[0].ToNumber()));
end;

{ Global Helper Functions }

function JSParseInt(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  n: Int64;
  code: Integer;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  s := Trim(AArgs[0].ToString());
  Val(s, n, code);
  if code = 0 then
    Result := JSMakeNumber(Double(n))
  else
    Result := JSMakeNumber(NaN);
end;

function JSParseFloat(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  d: Double;
  code: Integer;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  s := Trim(AArgs[0].ToString());
  Val(s, d, code);
  if code = 0 then
    Result := JSMakeNumber(d)
  else
    Result := JSMakeNumber(NaN);
end;

function JSIsNaN(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeBoolean(True));
  Result := JSMakeBoolean(IsNaN(AArgs[0].ToNumber()));
end;

function JSIsFinite(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  d: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeBoolean(False));
  d := AArgs[0].ToNumber();
  Result := JSMakeBoolean((not IsNaN(d)) and (not IsInfinite(d)));
end;

procedure FloriaJSRegisterStdLib(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap; ALogOutput: TStrings);
var
  consoleObj, mathObj, promiseObj: TFloriaJSObject;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;

  GLogOutput := ALogOutput;

  // 1. console
  consoleObj := AHeap.NewObject();
  consoleObj.SetProperty('log', JSMakeFunction(AHeap.NewNativeFunction('log', @JSConsoleLog)));
  consoleObj.SetProperty('error', JSMakeFunction(AHeap.NewNativeFunction('error', @JSConsoleError)));
  consoleObj.SetProperty('warn', JSMakeFunction(AHeap.NewNativeFunction('warn', @JSConsoleWarn)));
  AEnv.Define('console', JSMakeObject(consoleObj));

  // 2. Math
  mathObj := AHeap.NewObject();
  mathObj.SetProperty('E', JSMakeNumber(2.718281828459045));
  mathObj.SetProperty('LN10', JSMakeNumber(2.302585092994046));
  mathObj.SetProperty('LN2', JSMakeNumber(0.6931471805599453));
  mathObj.SetProperty('LOG2E', JSMakeNumber(1.4426950408889634));
  mathObj.SetProperty('LOG10E', JSMakeNumber(0.4342944819032518));
  mathObj.SetProperty('PI', JSMakeNumber(3.141592653589793));
  mathObj.SetProperty('SQRT1_2', JSMakeNumber(0.7071067811865476));
  mathObj.SetProperty('SQRT2', JSMakeNumber(1.4142135623730951));

  mathObj.SetProperty('abs', JSMakeFunction(AHeap.NewNativeFunction('abs', @JSMathAbs)));
  mathObj.SetProperty('acos', JSMakeFunction(AHeap.NewNativeFunction('acos', @JSMathAcos)));
  mathObj.SetProperty('asin', JSMakeFunction(AHeap.NewNativeFunction('asin', @JSMathAsin)));
  mathObj.SetProperty('atan', JSMakeFunction(AHeap.NewNativeFunction('atan', @JSMathAtan)));
  mathObj.SetProperty('atan2', JSMakeFunction(AHeap.NewNativeFunction('atan2', @JSMathAtan2)));
  mathObj.SetProperty('ceil', JSMakeFunction(AHeap.NewNativeFunction('ceil', @JSMathCeil)));
  mathObj.SetProperty('cos', JSMakeFunction(AHeap.NewNativeFunction('cos', @JSMathCos)));
  mathObj.SetProperty('exp', JSMakeFunction(AHeap.NewNativeFunction('exp', @JSMathExp)));
  mathObj.SetProperty('floor', JSMakeFunction(AHeap.NewNativeFunction('floor', @JSMathFloor)));
  mathObj.SetProperty('log', JSMakeFunction(AHeap.NewNativeFunction('log', @JSMathLog)));
  mathObj.SetProperty('max', JSMakeFunction(AHeap.NewNativeFunction('max', @JSMathMax)));
  mathObj.SetProperty('min', JSMakeFunction(AHeap.NewNativeFunction('min', @JSMathMin)));
  mathObj.SetProperty('pow', JSMakeFunction(AHeap.NewNativeFunction('pow', @JSMathPow)));
  mathObj.SetProperty('random', JSMakeFunction(AHeap.NewNativeFunction('random', @JSMathRandom)));
  mathObj.SetProperty('round', JSMakeFunction(AHeap.NewNativeFunction('round', @JSMathRound)));
  mathObj.SetProperty('sin', JSMakeFunction(AHeap.NewNativeFunction('sin', @JSMathSin)));
  mathObj.SetProperty('sqrt', JSMakeFunction(AHeap.NewNativeFunction('sqrt', @JSMathSqrt)));
  mathObj.SetProperty('tan', JSMakeFunction(AHeap.NewNativeFunction('tan', @JSMathTan)));
  mathObj.SetProperty('trunc', JSMakeFunction(AHeap.NewNativeFunction('trunc', @JSMathTrunc)));
  AEnv.Define('Math', JSMakeObject(mathObj));

  // 3. Promise
  promiseObj := AHeap.NewObject();
  promiseObj.SetProperty('resolve', JSMakeFunction(AHeap.NewNativeMethod('resolve', @AHeap.PromiseResolve)));
  promiseObj.SetProperty('reject', JSMakeFunction(AHeap.NewNativeMethod('reject', @AHeap.PromiseReject)));
  promiseObj.SetProperty('all', JSMakeFunction(AHeap.NewNativeMethod('all', @AHeap.PromiseAll)));
  promiseObj.SetProperty('race', JSMakeFunction(AHeap.NewNativeMethod('race', @AHeap.PromiseRace)));
  AEnv.Define('Promise', JSMakeObject(promiseObj));

  // 4. Error
  AEnv.Define('Error', JSMakeFunction(AHeap.NewNativeMethod('Error', @AHeap.ErrorCtor)));

  // 5. Global Functions
  AEnv.Define('parseInt', JSMakeFunction(AHeap.NewNativeFunction('parseInt', @JSParseInt)));
  AEnv.Define('parseFloat', JSMakeFunction(AHeap.NewNativeFunction('parseFloat', @JSParseFloat)));
  AEnv.Define('isNaN', JSMakeFunction(AHeap.NewNativeFunction('isNaN', @JSIsNaN)));
  AEnv.Define('isFinite', JSMakeFunction(AHeap.NewNativeFunction('isFinite', @JSIsFinite)));
end;

end.
