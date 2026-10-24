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
  Classes, SysUtils, Math, floria.js.types, floria.js.value, floria.js.env,
  floria.js.arrays, floria.js.strings, floria.js.objects, floria.js.json;

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

{ Global Constants and Conversions }

function JSGlobalNaN(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(NaN);
end;

function JSGlobalInfinity(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(Infinity);
end;

function JSNumberConst(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then
    Result := JSMakeNumber(0)
  else
    Result := JSMakeNumber(AArgs[0].ToNumber());
end;

function JSStringConst(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then
    Result := JSMakeString('')
  else
    Result := JSMakeString(AArgs[0].ToString());
end;

function JSBooleanConst(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then
    Result := JSMakeBoolean(False)
  else
    Result := JSMakeBoolean(AArgs[0].ToBoolean());
end;

function JSNumberIsNaN(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if (Length(AArgs) = 0) or (not AArgs[0].IsNumber()) then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(IsNaN(AArgs[0].NumVal));
end;

function JSNumberIsFinite(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if (Length(AArgs) = 0) or (not AArgs[0].IsNumber()) then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean((not IsNaN(AArgs[0].NumVal)) and (not IsInfinite(AArgs[0].NumVal)));
end;

function JSNumberIsInteger(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if (Length(AArgs) = 0) or (not AArgs[0].IsNumber()) then
    Exit(JSMakeBoolean(False));
  if IsNaN(AArgs[0].NumVal) or IsInfinite(AArgs[0].NumVal) then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(Frac(AArgs[0].NumVal) = 0.0);
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
var
  d: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  d := AArgs[0].ToNumber();
  if IsNaN(d) or IsInfinite(d) then
    Exit(JSMakeNumber(d));
  if d >= 0 then
    Result := JSMakeNumber(Trunc(d))
  else
    Result := JSMakeNumber(-Trunc(-d));
end;

function JSMathLog2(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Log2(AArgs[0].ToNumber()));
end;

function JSMathLog10(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Log10(AArgs[0].ToNumber()));
end;

function JSMathSign(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  d: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  d := AArgs[0].ToNumber();
  if IsNaN(d) then Exit(JSMakeNumber(NaN));
  if d > 0 then Exit(JSMakeNumber(1));
  if d < 0 then Exit(JSMakeNumber(-1));
  Exit(JSMakeNumber(0));
end;

function JSMathCbrt(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(Power(AArgs[0].ToNumber(), 1.0 / 3.0));
end;

function JSMathHypot(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  i: Integer;
  d, s: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(0));
  s := 0;
  for i := 0 to High(AArgs) do
  begin
    d := AArgs[i].ToNumber();
    s := s + d * d;
  end;
  Result := JSMakeNumber(Sqrt(s));
end;

function JSMathImul(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  da, db: Double;
  a, b: LongInt;
begin
  if Length(AArgs) < 2 then Exit(JSMakeNumber(0));
  da := AArgs[0].ToNumber();
  db := AArgs[1].ToNumber();
  if IsNaN(da) or IsInfinite(da) then da := 0;
  if IsNaN(db) or IsInfinite(db) then db := 0;
  a := LongInt(Cardinal(Trunc(da)));
  b := LongInt(Cardinal(Trunc(db)));
  Result := JSMakeNumber(LongInt(a * b));
end;

function JSMathClz32(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  d: Double;
  u: Cardinal;
  n: Integer;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(32));
  d := AArgs[0].ToNumber();
  if IsNaN(d) or IsInfinite(d) then d := 0;
  u := Cardinal(LongInt(Trunc(d)));
  if u = 0 then Exit(JSMakeNumber(32));
  n := 0;
  if (u and $FFFF0000) = 0 then begin Inc(n, 16); u := u shl 16; end;
  if (u and $FF000000) = 0 then begin Inc(n, 8); u := u shl 8; end;
  if (u and $F0000000) = 0 then begin Inc(n, 4); u := u shl 4; end;
  if (u and $C0000000) = 0 then begin Inc(n, 2); u := u shl 2; end;
  if (u and $80000000) = 0 then begin Inc(n, 1); end;
  Result := JSMakeNumber(n);
end;


{ Global Helper Functions }

function JSParseInt(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, part: string;
  radixVal: Double;
  radix: Integer;
  i: Integer;
  sign: Integer;
  n: Int64;
  c: Char;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  s := Trim(AArgs[0].ToString());
  if s = '' then Exit(JSMakeNumber(NaN));

  sign := 1;
  i := 1;
  if s[1] = '+' then
    Inc(i)
  else if s[1] = '-' then
  begin
    sign := -1;
    Inc(i);
  end;

  if i + 1 <= Length(s) then
  begin
    if (s[i] = '0') and ((s[i + 1] = 'x') or (s[i + 1] = 'X')) then
    begin
      radix := 16;
      i := i + 2;
    end
    else if (s[i] = '0') and ((s[i + 1] = 'o') or (s[i + 1] = 'O')) then
    begin
      radix := 8;
      i := i + 2;
    end
    else if (s[i] = '0') and ((s[i + 1] = 'b') or (s[i + 1] = 'B')) then
    begin
      radix := 2;
      i := i + 2;
    end;
  end;

  radixVal := 0;
  if Length(AArgs) >= 2 then
  begin
    radixVal := AArgs[1].ToNumber();
    radix := Trunc(radixVal);
    if (radix = 0) and ((i + 1 <= Length(s)) and (s[i] = '0') and ((s[i + 1] = 'x') or (s[i + 1] = 'X'))) then
      radix := 16;
  end;

  if (radix < 2) or (radix > 36) then
    Exit(JSMakeNumber(NaN));

  if radix = 16 then
  begin
    part := '';
    while i <= Length(s) do
    begin
      c := UpCase(s[i]);
      if (c >= '0') and (c <= '9') then
        part := part + s[i]
      else if (c >= 'A') and (c <= 'F') then
        part := part + s[i]
      else
        Break;
      Inc(i);
    end;
    if part = '' then Exit(JSMakeNumber(NaN));
    val('$' + part, n, i);
    if i = 0 then
      Result := JSMakeNumber(Double(sign) * Double(n))
    else
      Result := JSMakeNumber(NaN);
    Exit;
  end;

  if radix = 8 then
  begin
    part := '';
    while i <= Length(s) do
    begin
      c := s[i];
      if (c >= '0') and (c <= '7') then
        part := part + c
      else
        Break;
      Inc(i);
    end;
    if part = '' then Exit(JSMakeNumber(NaN));
    val('&' + part, n, i);
    if i = 0 then
      Result := JSMakeNumber(Double(sign) * Double(n))
    else
      Result := JSMakeNumber(NaN);
    Exit;
  end;

  if radix = 2 then
  begin
    part := '';
    while i <= Length(s) do
    begin
      c := s[i];
      if (c >= '0') and (c <= '1') then
        part := part + c
      else
        Break;
      Inc(i);
    end;
    if part = '' then Exit(JSMakeNumber(NaN));
    val('%' + part, n, i);
    if i = 0 then
      Result := JSMakeNumber(Double(sign) * Double(n))
    else
      Result := JSMakeNumber(NaN);
    Exit;
  end;

  part := '';
  while i <= Length(s) do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') and ((Ord(c) - Ord('0')) < radix) then
      part := part + c
    else
      Break;
    Inc(i);
  end;
  if part = '' then Exit(JSMakeNumber(NaN));
  val(part, n, i);
  if i = 0 then
    Result := JSMakeNumber(Double(sign) * Double(n))
  else
    Result := JSMakeNumber(NaN);
end;

function JSParseFloat(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, part: string;
  d: Double;
  code: Integer;
  i: Integer;
  c: Char;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  s := Trim(AArgs[0].ToString());
  if s = '' then Exit(JSMakeNumber(NaN));
  if (s = 'Infinity') or (s = '+Infinity') then Exit(JSMakeNumber(Infinity));
  if s = '-Infinity' then Exit(JSMakeNumber(-Infinity));
  if (s = 'NaN') or (s = '+NaN') or (s = '-NaN') then Exit(JSMakeNumber(NaN));

  part := '';
  i := 1;
  if s[1] = '+' then
    Inc(i)
  else if s[1] = '-' then
  begin
    part := '-';
    Inc(i);
  end;

  while i <= Length(s) do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') then
    begin
      part := part + c;
      Inc(i);
      Continue;
    end;
    if (c = '.') then
    begin
      part := part + c;
      Inc(i);
      Continue;
    end;
    if ((c = 'e') or (c = 'E')) then
    begin
      part := part + c;
      Inc(i);
      if (i <= Length(s)) and ((s[i] = '+') or (s[i] = '-')) then
      begin
        part := part + s[i];
        Inc(i);
      end;
      Continue;
    end;
    Break;
  end;

  if (part = '') or (part = '-') or (part = '.') or (part = '-.') then
    Exit(JSMakeNumber(NaN));
  if (part[Length(part)] = '.') then
  begin
    { keep as is? or strip? try to parse }
  end;

  try
    Val(part, d, code);
    if code = 0 then
      Result := JSMakeNumber(d)
    else
      Result := JSMakeNumber(NaN);
  except
    Result := JSMakeNumber(NaN);
  end;
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
  consoleObj, mathObj, promiseObj, globalObj: TFloriaJSObject;
  numberObj, stringObj: TFloriaJSFunction;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;

  GLogOutput := ALogOutput;

  // 0. Built-in prototypes and global objects
  FloriaJSRegisterArray(AEnv, AHeap);
  FloriaJSRegisterString(AHeap);
  FloriaJSRegisterObjects(AEnv, AHeap, @AHeap.ObjectCtor);
  FloriaJSRegisterJSON(AEnv, AHeap);

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
  mathObj.SetProperty('log2', JSMakeFunction(AHeap.NewNativeFunction('log2', @JSMathLog2)));
  mathObj.SetProperty('log10', JSMakeFunction(AHeap.NewNativeFunction('log10', @JSMathLog10)));
  mathObj.SetProperty('sign', JSMakeFunction(AHeap.NewNativeFunction('sign', @JSMathSign)));
  mathObj.SetProperty('cbrt', JSMakeFunction(AHeap.NewNativeFunction('cbrt', @JSMathCbrt)));
  mathObj.SetProperty('hypot', JSMakeFunction(AHeap.NewNativeFunction('hypot', @JSMathHypot)));
  mathObj.SetProperty('imul', JSMakeFunction(AHeap.NewNativeFunction('imul', @JSMathImul)));
  mathObj.SetProperty('clz32', JSMakeFunction(AHeap.NewNativeFunction('clz32', @JSMathClz32)));
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
  AEnv.Define('TypeError', JSMakeFunction(AHeap.NewNativeMethod('TypeError', @AHeap.TypeErrorCtor)));
  AEnv.Define('RangeError', JSMakeFunction(AHeap.NewNativeMethod('RangeError', @AHeap.RangeErrorCtor)));
  AEnv.Define('ReferenceError', JSMakeFunction(AHeap.NewNativeMethod('ReferenceError', @AHeap.ReferenceErrorCtor)));

  // 5. Global Functions
  AEnv.Define('parseInt', JSMakeFunction(AHeap.NewNativeFunction('parseInt', @JSParseInt)));
  AEnv.Define('parseFloat', JSMakeFunction(AHeap.NewNativeFunction('parseFloat', @JSParseFloat)));
  AEnv.Define('isNaN', JSMakeFunction(AHeap.NewNativeFunction('isNaN', @JSIsNaN)));
  AEnv.Define('isFinite', JSMakeFunction(AHeap.NewNativeFunction('isFinite', @JSIsFinite)));
  AEnv.Define('NaN', JSMakeNumber(NaN));
  AEnv.Define('Infinity', JSMakeNumber(Infinity));
  AEnv.Define('undefined', JSMakeUndefined());

  // 6. Number constructor and static methods
  numberObj := AHeap.NewNativeFunction('Number', @JSNumberConst);
  numberObj.SetProperty('isNaN', JSMakeFunction(AHeap.NewNativeFunction('isNaN', @JSNumberIsNaN)));
  numberObj.SetProperty('isFinite', JSMakeFunction(AHeap.NewNativeFunction('isFinite', @JSNumberIsFinite)));
  numberObj.SetProperty('isInteger', JSMakeFunction(AHeap.NewNativeFunction('isInteger', @JSNumberIsInteger)));
  numberObj.SetProperty('parseInt', JSMakeFunction(AHeap.NewNativeFunction('parseInt', @JSParseInt)));
  numberObj.SetProperty('parseFloat', JSMakeFunction(AHeap.NewNativeFunction('parseFloat', @JSParseFloat)));
  numberObj.SetProperty('NaN', JSMakeNumber(NaN));
  numberObj.SetProperty('POSITIVE_INFINITY', JSMakeNumber(Infinity));
  numberObj.SetProperty('NEGATIVE_INFINITY', JSMakeNumber(-Infinity));
  numberObj.SetProperty('MAX_VALUE', JSMakeNumber(1.7976931348623157e+308));
  numberObj.SetProperty('MIN_VALUE', JSMakeNumber(5e-324));
  numberObj.SetProperty('MAX_SAFE_INTEGER', JSMakeNumber(9007199254740991.0));
  numberObj.SetProperty('MIN_SAFE_INTEGER', JSMakeNumber(-9007199254740991.0));
  numberObj.SetProperty('EPSILON', JSMakeNumber(2.220446049250313e-16));
  AEnv.Define('Number', JSMakeFunction(numberObj));

  stringObj := AHeap.NewNativeFunction('String', @JSStringConst);
  { Publish the shared string prototype so String.prototype methods and
    prototype-chain checks see the same methods primitive strings use. }
  stringObj.SetProperty('prototype', JSMakeObject(AHeap.GetStringPrototype()));
  AEnv.Define('String', JSMakeFunction(stringObj));
  AEnv.Define('Boolean', JSMakeFunction(AHeap.NewNativeFunction('Boolean', @JSBooleanConst)));

  // 7. globalThis
  globalObj := AHeap.NewObject();
  globalObj.SetProperty('globalThis', JSMakeObject(globalObj));
  globalObj.SetProperty('NaN', JSMakeNumber(NaN));
  globalObj.SetProperty('Infinity', JSMakeNumber(Infinity));
  globalObj.SetProperty('undefined', JSMakeUndefined());
  globalObj.SetProperty('Math', JSMakeObject(mathObj));
  globalObj.SetProperty('console', JSMakeObject(consoleObj));
  globalObj.SetProperty('Array', AEnv.GetDefault('Array', JSMakeUndefined()));
  globalObj.SetProperty('Object', AEnv.GetDefault('Object', JSMakeUndefined()));
  globalObj.SetProperty('Number', JSMakeFunction(numberObj));
  globalObj.SetProperty('String', AEnv.GetDefault('String', JSMakeUndefined()));
  globalObj.SetProperty('Boolean', AEnv.GetDefault('Boolean', JSMakeUndefined()));
  globalObj.SetProperty('JSON', AEnv.GetDefault('JSON', JSMakeUndefined()));
  globalObj.SetProperty('Promise', JSMakeObject(promiseObj));
  globalObj.SetProperty('Error', AEnv.GetDefault('Error', JSMakeUndefined()));
  globalObj.SetProperty('TypeError', AEnv.GetDefault('TypeError', JSMakeUndefined()));
  globalObj.SetProperty('RangeError', AEnv.GetDefault('RangeError', JSMakeUndefined()));
  globalObj.SetProperty('ReferenceError', AEnv.GetDefault('ReferenceError', JSMakeUndefined()));
  globalObj.SetProperty('parseInt', AEnv.GetDefault('parseInt', JSMakeUndefined()));
  globalObj.SetProperty('parseFloat', AEnv.GetDefault('parseFloat', JSMakeUndefined()));
  globalObj.SetProperty('isNaN', AEnv.GetDefault('isNaN', JSMakeUndefined()));
  globalObj.SetProperty('isFinite', AEnv.GetDefault('isFinite', JSMakeUndefined()));
  AEnv.Define('globalThis', JSMakeObject(globalObj));
end;

end.
