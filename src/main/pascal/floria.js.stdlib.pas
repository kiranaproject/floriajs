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
  floria.js.arrays, floria.js.strings, floria.js.objects, floria.js.json,
  floria.js.symbol, floria.js.date, floria.js.uri, floria.js.collections,
  floria.js.number, floria.js.lexer, floria.js.ast, floria.js.parser,
  floria.js.bytecode, floria.js.compiler,
  floria.js.timers, floria.js.regexp, floria.js.utf16, floria.js.binary;

var
  { The heap the standard library was registered against. Native functions are
    called with a primitive receiver that carries no heap of its own, so the
    few that must allocate (such as the `Function` constructor) use this. }
  GSharedStdLibHeap: TFloriaJSHeap = nil;

type
  { Output Logging Callback }
  TFloriaJSLogHandler = procedure(const AMessage: string) of object;

procedure FloriaJSRegisterStdLib(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap; ALogOutput: TStrings = nil);

implementation

var
  GLogOutput: TStrings = nil;

{ Registers a global built-in function: not a constructor, no `prototype`
  property, a fixed `length`, and a non-enumerable global property. }
function RegisterGlobalFunction(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap;
  const AName: string; AProc: TFloriaJSNativeProc; ALength: Integer): TFloriaJSFunction;
begin
  Result := AHeap.NewNativeFunction(AName, AProc);
  Result.NotConstructable := True;
  Result.SuppressPrototype := True;
  Result.LengthOverride := ALength;
  AEnv.DefineBuiltin(AName, JSMakeFunction(Result));
end;

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

{ Registers a Math function: not a constructor, no `prototype`, length 1. }
procedure RegisterMathMethod(AHeap: TFloriaJSHeap; AObj: TFloriaJSObject;
  const AName: string; AProc: TFloriaJSNativeProc);
var
  fn: TFloriaJSFunction;
begin
  fn := AHeap.NewNativeFunction(AName, AProc);
  fn.NotConstructable := True;
  fn.SuppressPrototype := True;
  fn.LengthOverride := 1;
  AObj.DefineDataProperty(AName, JSMakeFunction(fn), True, False, True);
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
    Result := JSMakeString(JSToString(AArgs[0]));
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

function JSNumberIsSafeInteger(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if (Length(AArgs) = 0) or (not AArgs[0].IsNumber()) then
    Exit(JSMakeBoolean(False));
  if IsNaN(AArgs[0].NumVal) or IsInfinite(AArgs[0].NumVal) then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean((Frac(AArgs[0].NumVal) = 0.0) and
    (Abs(AArgs[0].NumVal) <= 9007199254740991.0));
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
var
  v: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  v := AArgs[0].ToNumber();
  { Pascal's Round uses banker's rounding, so 2.5 becomes 2; JavaScript rounds
    halves toward +Infinity. Floor(x + 0.5) is the specified behaviour. }
  Result := JSMakeNumber(Floor(v + 0.5));
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

{ Rounds to the nearest IEEE-754 single-precision value. }
function JSMathFround(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  d: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  d := AArgs[0].ToNumber();
  if IsNaN(d) or IsInfinite(d) then
    Exit(JSMakeNumber(d));
  Result := JSMakeNumber(Single(d));
end;

function JSMathExpm1(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  d: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  d := AArgs[0].ToNumber();
  if IsNaN(d) then Exit(JSMakeNumber(NaN));
  { expm1 preserves the sign of zero and the infinities. }
  if d = 0.0 then Exit(JSMakeNumber(d));
  if IsInfinite(d) then
  begin
    if d > 0 then Exit(JSMakeNumber(Infinity));
    Exit(JSMakeNumber(-1));
  end;
  Result := JSMakeNumber(Exp(d) - 1.0);
end;

function JSMathLog1p(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  d: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  d := AArgs[0].ToNumber();
  if IsNaN(d) or (d < -1.0) then Exit(JSMakeNumber(NaN));
  if d = -1.0 then Exit(JSMakeNumber(-Infinity));
  if d = 0.0 then Exit(JSMakeNumber(d));
  if IsInfinite(d) then Exit(JSMakeNumber(Infinity));
  Result := JSMakeNumber(Ln(1.0 + d));
end;

function JSMathSinh(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  d: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  d := AArgs[0].ToNumber();
  if IsNaN(d) or IsInfinite(d) then Exit(JSMakeNumber(d));
  if d = 0.0 then Exit(JSMakeNumber(d));
  Result := JSMakeNumber(Sinh(d));
end;

function JSMathCosh(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  d: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  d := AArgs[0].ToNumber();
  if IsNaN(d) then Exit(JSMakeNumber(NaN));
  if IsInfinite(d) then Exit(JSMakeNumber(Infinity));
  Result := JSMakeNumber(Cosh(d));
end;

function JSMathTanh(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  d: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  d := AArgs[0].ToNumber();
  if IsNaN(d) then Exit(JSMakeNumber(NaN));
  if IsInfinite(d) then
  begin
    if d > 0 then Exit(JSMakeNumber(1));
    Exit(JSMakeNumber(-1));
  end;
  if d = 0.0 then Exit(JSMakeNumber(d));
  Result := JSMakeNumber(Tanh(d));
end;

function JSMathAsinh(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  d: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  d := AArgs[0].ToNumber();
  if IsNaN(d) or IsInfinite(d) then Exit(JSMakeNumber(d));
  if d = 0.0 then Exit(JSMakeNumber(d));
  { Sign-symmetric form avoids cancellation for large negative values. }
  if d > 0 then
    Result := JSMakeNumber(Ln(d + Sqrt(d * d + 1.0)))
  else
    Result := JSMakeNumber(-Ln(-d + Sqrt(d * d + 1.0)));
end;

function JSMathAcosh(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  d: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  d := AArgs[0].ToNumber();
  if IsNaN(d) or (d < 1.0) then Exit(JSMakeNumber(NaN));
  if IsInfinite(d) then Exit(JSMakeNumber(Infinity));
  Result := JSMakeNumber(Ln(d + Sqrt(d * d - 1.0)));
end;

function JSMathAtanh(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  d: Double;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  d := AArgs[0].ToNumber();
  if IsNaN(d) or (d < -1.0) or (d > 1.0) then Exit(JSMakeNumber(NaN));
  if d = 1.0 then Exit(JSMakeNumber(Infinity));
  if d = -1.0 then Exit(JSMakeNumber(-Infinity));
  if d = 0.0 then Exit(JSMakeNumber(d));
  Result := JSMakeNumber(0.5 * Ln((1.0 + d) / (1.0 - d)));
end;


{ Global Helper Functions }


{ `BigInt(value)` — converts a number, string, or boolean to a BigInt.

  A Number must be integral: converting 1.5 throws a RangeError, as ECMAScript
  specifies, because silently truncating would lose data. }
function JSBigIntCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  v, fn, converted: TFloriaJSValue;
  text: string;
  d: Double;
  i, start: Integer;
begin
  if Length(AArgs) = 0 then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError',
      'Cannot convert undefined to a BigInt')));
  v := AArgs[0];

  if v.IsBigInt() then
    Exit(v);

  if v.IsBoolean() then
  begin
    if v.BoolVal then Exit(JSMakeBigInt('1')) else Exit(JSMakeBigInt('0'));
  end;

  if v.IsNumber() then
  begin
    d := v.NumVal;
    if IsNaN(d) or IsInfinite(d) then
      raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('RangeError',
        'The number ' + JSNumberToStr(d) + ' cannot be converted to a BigInt because it is not an integer')));
    if Frac(d) <> 0.0 then
      raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('RangeError',
        'The number ' + JSNumberToStr(d) + ' cannot be converted to a BigInt because it is not an integer')));
    Exit(JSMakeBigInt(BigIntNormalize(FloatToStrF(d, ffFixed, 0, 0))));
  end;

  if v.IsObject() then
  begin
    fn := v.AsObject().GetProperty('valueOf');
    if fn.IsFunction() and (v.ObjVal.Heap <> nil) then
    begin
      converted := v.ObjVal.Heap.InvokeFunction(fn, [], v);
      if not converted.IsObject() then
        Exit(JSBigIntCtor([converted], AThis));
    end;
    fn := v.AsObject().GetProperty('toString');
    if fn.IsFunction() and (v.ObjVal.Heap <> nil) then
    begin
      converted := v.ObjVal.Heap.InvokeFunction(fn, [], v);
      if not converted.IsObject() then
        Exit(JSBigIntCtor([converted], AThis));
    end;
  end;

  if v.IsString() then
  begin
    { Accept an optional sign followed by decimal digits; anything else is a
      SyntaxError, as ECMAScript specifies. }
    text := Trim(v.StrVal);
    if text = '' then
      Exit(JSMakeBigInt('0'));
    i := 1;
    if text[1] in ['+', '-'] then
      Inc(i);
    start := i;
    while (i <= Length(text)) and (text[i] in ['0'..'9']) do
      Inc(i);
    if i = start then
      raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('SyntaxError',
        'Cannot convert ' + text + ' to a BigInt')));
    Exit(JSMakeBigInt(BigIntNormalize(Copy(text, 1, i - 1))));
  end;

  raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError',
    'Cannot convert ' + v.ToString() + ' to a BigInt')));
end;


{ `Function(arg1, ..., argN, body)` — builds a function from source text.

  The body is compiled the same way any script is: the arguments and body are
  joined into a function expression, parsed, and compiled into a fresh
  bytecode chunk. A syntax error in the body surfaces as a SyntaxError. }
function JSFunctionCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  params, body, source: string;
  i: Integer;
  lexer: TFloriaJSLexer;
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  comp: TFloriaJSCompiler;
  code: TFloriaJSBytecode;
  heap: TFloriaJSHeap;
  fn: TFloriaJSFunction;
  subCode: TFloriaJSBytecode;
begin
  heap := GSharedStdLibHeap;
  if heap = nil then
    Exit(JSMakeUndefined());

  { All but the last argument are parameter names; the last is the body. }
  params := '';
  body := '';
  if Length(AArgs) > 0 then
  begin
    for i := 0 to Length(AArgs) - 2 do
    begin
      if i > 0 then
        params := params + ',';
      params := params + AArgs[i].ToString();
    end;
    body := AArgs[High(AArgs)].ToString();
  end;

  source := 'function anonymous(' + params + ') {' + #10 + body + #10 + '}';

  lexer := TFloriaJSLexer.Create(source);
  parser := TFloriaJSParser.Create(lexer);
  comp := nil;
  code := nil;
  try
    prog := parser.ParseProgram();
    try
      if parser.HasErrors() then
        raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('SyntaxError',
          parser.GetError(0))));

      comp := TFloriaJSCompiler.Create();
      code := comp.CompileProgram(prog);
      try
        { The chunk's first subfunction is the function expression itself. }
        if code.GetSubFunctionCount() = 0 then
          Exit(JSMakeUndefined());
        subCode := code.GetSubFunction(0);
        subCode.Retain();
        fn := heap.NewBytecodeFunction('anonymous', subCode, nil, False, False);
        Result := JSMakeFunction(fn);
      finally
        code.Release();
      end;
    finally
      prog.Free();
    end;
  finally
    comp.Free();
    parser.Free();
    lexer.Free();
  end;
end;


{ `String.fromCharCode(...codes)` — builds a string from UTF-16 code units. }
function JSStringFromCharCode(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  i, code: Integer;
  units: UnicodeString;
begin
  { Build the whole UTF-16 sequence before encoding, so an adjacent
    high/low surrogate pair becomes one astral code point. Encoding each
    unit separately would drop both halves. }
  SetLength(units, Length(AArgs));
  for i := 0 to Length(AArgs) - 1 do
  begin
    code := Trunc(AArgs[i].ToNumber()) and $FFFF;
    units[i + 1] := WideChar(code);
  end;
  Result := JSMakeString(UTF8Encode(units));
end;

{ `String.fromCodePoint(...points)` — builds a string from Unicode code points,
  encoding anything above the BMP as a surrogate pair. }
function JSStringFromCodePoint(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  i: Integer;
  cp: Int64;
  sb: string;
begin
  sb := '';
  for i := 0 to Length(AArgs) - 1 do
  begin
    cp := Trunc(AArgs[i].ToNumber());
    if (cp < 0) or (cp > $10FFFF) then
      raise EFloriaJSThrow.Create(JSMakeString('RangeError: Invalid code point ' + IntToStr(cp)));
    sb := sb + JSUTF16FromCodePoint(LongWord(cp));
  end;
  Result := JSMakeString(sb);
end;

function JSParseInt(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  radixVal: Double;
  radix: Integer;
  i: Integer;
  sign: Integer;
  n: Double;
  c: Char;
  digit: Integer;
  hasDigits: Boolean;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  s := JSTrimWhitespace(JSToString(AArgs[0]));
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

  radix := 0;
  if (Length(AArgs) >= 2) and not AArgs[1].IsUndefined() then
  begin
    radixVal := AArgs[1].ToNumber();
    if not IsNaN(radixVal) then
      radix := Trunc(radixVal);
  end;

  if (radix = 0) or (radix = 16) then
  begin
    if (i + 1 <= Length(s)) and (s[i] = '0') and ((s[i + 1] = 'x') or (s[i + 1] = 'X')) then
    begin
      radix := 16;
      i := i + 2;
    end
    else if radix = 0 then
      radix := 10;
  end;

  if (radix < 2) or (radix > 36) then
    Exit(JSMakeNumber(NaN));

  { Accumulate as a Double: an Int64 overflows past 2^63, and the result is a
    Number anyway. Integers up to 2^53 stay exact. }
  n := 0.0;
  hasDigits := False;
  while i <= Length(s) do
  begin
    c := UpCase(s[i]);
    if (c >= '0') and (c <= '9') then
      digit := Ord(c) - Ord('0')
    else if (c >= 'A') and (c <= 'Z') then
      digit := Ord(c) - Ord('A') + 10
    else
      Break;

    if digit >= radix then
      Break;

    hasDigits := True;
    n := n * radix + digit;
    Inc(i);
  end;

  if not hasDigits then
    Exit(JSMakeNumber(NaN));

  Result := JSMakeNumber(sign * n);
end;

function JSParseFloat(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, part: string;
  d: Double;
  i, j: Integer;
  hasInt, hasFrac: Boolean;
begin
  if Length(AArgs) = 0 then Exit(JSMakeNumber(NaN));
  s := JSTrimWhitespace(JSToString(AArgs[0]));
  if s = '' then Exit(JSMakeNumber(NaN));

  i := 1;
  if (i <= Length(s)) and ((s[i] = '+') or (s[i] = '-')) then
    Inc(i);

  { Infinity is a complete StrDecimalLiteral. }
  if Copy(s, i, 8) = 'Infinity' then
  begin
    if s[1] = '-' then
      Exit(JSMakeNumber(-Infinity));
    Exit(JSMakeNumber(Infinity));
  end;

  { Scan the longest prefix that is a StrDecimalLiteral: digits, an optional
    fraction, and an optional exponent whose digits are present. }
  hasInt := False;
  while (i <= Length(s)) and (s[i] >= '0') and (s[i] <= '9') do
  begin
    hasInt := True;
    Inc(i);
  end;

  hasFrac := False;
  if (i <= Length(s)) and (s[i] = '.') then
  begin
    Inc(i);
    while (i <= Length(s)) and (s[i] >= '0') and (s[i] <= '9') do
    begin
      hasFrac := True;
      Inc(i);
    end;
  end;

  if not (hasInt or hasFrac) then
    Exit(JSMakeNumber(NaN));

  if (i <= Length(s)) and ((s[i] = 'e') or (s[i] = 'E')) then
  begin
    j := i + 1;
    if (j <= Length(s)) and ((s[j] = '+') or (s[j] = '-')) then
      Inc(j);
    if (j <= Length(s)) and (s[j] >= '0') and (s[j] <= '9') then
    begin
      while (j <= Length(s)) and (s[j] >= '0') and (s[j] <= '9') do
        Inc(j);
      i := j;
    end;
  end;

  part := Copy(s, 1, i - 1);
  if JSTryStrToNumber(part, d) then
    Result := JSMakeNumber(d)
  else
    Result := JSMakeNumber(NaN);
end;

function JSQueueMicrotask(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
  job: TFloriaJSPromiseJob;
begin
  heap := JSActiveRealmHeap();
  if heap = nil then
    Exit(JSMakeUndefined());
  if (Length(AArgs) = 0) or not AArgs[0].IsFunction() then
    raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
      'queueMicrotask requires a callable argument')));
  job.Kind := pjkMicrotask;
  job.OnFulfilled := AArgs[0];
  job.OnRejected := JSMakeUndefined();
  job.OnFinally := JSMakeUndefined();
  job.IsFinally := False;
  job.IsRejection := False;
  job.Value := JSMakeUndefined();
  job.Child := nil;
  job.Target := nil;
  heap.EnqueuePromiseJob(job);
  Result := JSMakeUndefined();
end;

type
  TCloneEntry = record
    Orig: TFloriaJSObject;
    Clone: TFloriaJSValue;
  end;

function CloneValue(AHeap: TFloriaJSHeap; const AValue: TFloriaJSValue;
  var ASeen: array of TCloneEntry; var ACount: Integer): TFloriaJSValue;
var
  obj, cloneObj: TFloriaJSObject;
  arr, cloneArr: TFloriaJSArray;
  map, cloneMap: TFloriaJSMap;
  setObj, cloneSet: TFloriaJSSet;
  re, cloneRe: TFloriaJSRegExp;
  i: Integer;
  dateMs: TFloriaJSValue;
begin
  if not AValue.IsObject() then
    Exit(AValue);
  obj := AValue.AsObject();
  if obj = nil then
    Exit(AValue);

  { A cycle resolves to the clone that is already under construction. }
  for i := 0 to ACount - 1 do
    if ASeen[i].Orig = obj then
      Exit(ASeen[i].Clone);

  if obj is TFloriaJSArray then
  begin
    arr := TFloriaJSArray(obj);
    cloneArr := AHeap.NewArray();
    Result := JSMakeArray(cloneArr);
    ASeen[ACount].Orig := obj;
    ASeen[ACount].Clone := Result;
    Inc(ACount);
    for i := 0 to arr.Length() - 1 do
      if arr.HasElement(i) then
        cloneArr.Push(CloneValue(AHeap, arr.GetElement(i), ASeen, ACount))
      else
        cloneArr.PushHole();
    Exit;
  end;

  if obj is TFloriaJSMap then
  begin
    map := TFloriaJSMap(obj);
    cloneMap := TFloriaJSMap(AHeap.Track(TFloriaJSMap.Create(map.Prototype)));
    Result := JSMakeObject(cloneMap);
    ASeen[ACount].Orig := obj;
    ASeen[ACount].Clone := Result;
    Inc(ACount);
    for i := 0 to map.Size - 1 do
      cloneMap.SetItem(
        CloneValue(AHeap, map.Entries[i].Key, ASeen, ACount),
        CloneValue(AHeap, map.Entries[i].Value, ASeen, ACount));
    Exit;
  end;

  if obj is TFloriaJSSet then
  begin
    setObj := TFloriaJSSet(obj);
    cloneSet := TFloriaJSSet(AHeap.Track(TFloriaJSSet.Create(setObj.Prototype)));
    Result := JSMakeObject(cloneSet);
    ASeen[ACount].Orig := obj;
    ASeen[ACount].Clone := Result;
    Inc(ACount);
    for i := 0 to setObj.Size - 1 do
      cloneSet.AddItem(CloneValue(AHeap, setObj.GetItem(i), ASeen, ACount));
    Exit;
  end;

  if obj is TFloriaJSRegExp then
  begin
    re := TFloriaJSRegExp(obj);
    cloneRe := FloriaJSNewRegExp(re.Pattern, re.Flags, AHeap);
    cloneRe.LastIndex := re.LastIndex;
    Result := JSMakeObject(cloneRe);
    ASeen[ACount].Orig := obj;
    ASeen[ACount].Clone := Result;
    Inc(ACount);
    Exit;
  end;

  { Date objects carry their time in a hidden property. }
  if obj.HasProperty('__date_ms__') then
  begin
    dateMs := obj.GetProperty('__date_ms__');
    cloneObj := AHeap.NewObject(obj.Prototype);
    cloneObj.SetProperty('__date_ms__', dateMs);
    Result := JSMakeObject(cloneObj);
    ASeen[ACount].Orig := obj;
    ASeen[ACount].Clone := Result;
    Inc(ACount);
    Exit;
  end;

  cloneObj := AHeap.NewObject(AHeap.GetObjectPrototype());
  Result := JSMakeObject(cloneObj);
  ASeen[ACount].Orig := obj;
  ASeen[ACount].Clone := Result;
  Inc(ACount);
  for i := 0 to obj.GetEnumerablePropertyCount() - 1 do
    cloneObj.SetProperty(obj.GetEnumerablePropertyKey(i),
      CloneValue(AHeap, obj.GetProperty(obj.GetEnumerablePropertyKey(i)), ASeen, ACount));
end;

function JSStructuredClone(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
  seen: array of TCloneEntry;
  count: Integer;
begin
  heap := JSActiveRealmHeap();
  if heap = nil then
    Exit(JSMakeUndefined());
  if Length(AArgs) = 0 then
    Exit(JSMakeUndefined());
  SetLength(seen, 64);
  count := 0;
  Result := CloneValue(heap, AArgs[0], seen, count);
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

function JSEvalGlobal(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  heap: TFloriaJSHeap;
begin
  { The direct-eval path is handled by the VM with the caller's environment.
    This function is the intrinsic value for indirect calls and for code that
    reads `eval` as a value. }
  if Length(AArgs) = 0 then
    Exit(JSMakeUndefined());
  if not AArgs[0].IsString() then
    Exit(AArgs[0]);
  heap := JSActiveRealmHeap();
  if (heap = nil) or (not heap.HasEvalInvoker()) then
    raise EFloriaJSThrow.Create(JSMakeString(
      'TypeError: eval is not available in this context'));
  Result := heap.EvaluateSource(AArgs[0].StrVal);
end;

procedure FloriaJSRegisterStdLib(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap; ALogOutput: TStrings);
var
  consoleObj, mathObj, promiseObj, globalObj: TFloriaJSObject;
  promiseCtor, bigIntFn, methodFn, booleanObj, aggErrCtor: TFloriaJSFunction;
  numberObj, stringObj, funcObj, evalObj: TFloriaJSFunction;
  errCtor, typeErrCtor, rangeErrCtor, refErrCtor, syntaxErrCtor: TFloriaJSFunction;
  i: Integer;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;

  GLogOutput := ALogOutput;
  GSharedStdLibHeap := AHeap;

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
  RegisterMathMethod(AHeap, mathObj, 'fround', @JSMathFround);
  RegisterMathMethod(AHeap, mathObj, 'expm1', @JSMathExpm1);
  RegisterMathMethod(AHeap, mathObj, 'log1p', @JSMathLog1p);
  RegisterMathMethod(AHeap, mathObj, 'sinh', @JSMathSinh);
  RegisterMathMethod(AHeap, mathObj, 'cosh', @JSMathCosh);
  RegisterMathMethod(AHeap, mathObj, 'tanh', @JSMathTanh);
  RegisterMathMethod(AHeap, mathObj, 'asinh', @JSMathAsinh);
  RegisterMathMethod(AHeap, mathObj, 'acosh', @JSMathAcosh);
  RegisterMathMethod(AHeap, mathObj, 'atanh', @JSMathAtanh);
  AEnv.Define('Math', JSMakeObject(mathObj));

  { Array iteration: `values` and `[Symbol.iterator]` both return an iterator
    over the receiver, which is what `for…of` and spread consume. The symbol
    stores under its string form, so that is the key. }
  if AHeap.GetArrayPrototype() <> nil then
  begin
    AHeap.GetArrayPrototype().SetProperty('values',
      JSMakeFunction(AHeap.NewNativeFunction('values', @JSArrayValues)));
    methodFn := AHeap.NewNativeFunction('keys', @JSArrayKeys);
    methodFn.NotConstructable := True;
    methodFn.SuppressPrototype := True;
    AHeap.GetArrayPrototype().DefineDataProperty('keys',
      JSMakeFunction(methodFn), True, False, True);
    methodFn := AHeap.NewNativeFunction('entries', @JSArrayEntries);
    methodFn.NotConstructable := True;
    methodFn.SuppressPrototype := True;
    AHeap.GetArrayPrototype().DefineDataProperty('entries',
      JSMakeFunction(methodFn), True, False, True);
    { Symbol.iterator is also reachable by its description, so a computed
      symbol key finds it however the id was allocated. }
    AHeap.GetArrayPrototype().SetProperty('Symbol(Symbol.iterator)',
      JSMakeFunction(AHeap.NewNativeFunction('[Symbol.iterator]', @JSArrayValues)));
  end;

  // 3. Promise
  { `Promise` is a constructor: `new Promise(executor)` builds a promise and
    returns it, while the statics hang off the same function object. }
  promiseCtor := AHeap.NewNativeMethod('Promise', @AHeap.PromiseConstructor);
  promiseCtor.IntrinsicName := 'Promise';
  promiseCtor.SetProperty('prototype', JSMakeObject(AHeap.GetPromisePrototype()));
  AHeap.GetPromisePrototype().SetProperty('constructor', JSMakeFunction(promiseCtor));
  promiseObj := promiseCtor;
  promiseObj.SetProperty('resolve', JSMakeFunction(AHeap.NewNativeMethod('resolve', @AHeap.PromiseResolve)));
  promiseObj.SetProperty('reject', JSMakeFunction(AHeap.NewNativeMethod('reject', @AHeap.PromiseReject)));
  promiseObj.SetProperty('all', JSMakeFunction(AHeap.NewNativeMethod('all', @AHeap.PromiseAll)));
  promiseObj.SetProperty('race', JSMakeFunction(AHeap.NewNativeMethod('race', @AHeap.PromiseRace)));
  methodFn := AHeap.NewNativeMethod('allSettled', @AHeap.PromiseAllSettled);
  methodFn.NotConstructable := True;
  methodFn.SuppressPrototype := True;
  methodFn.LengthOverride := 1;
  promiseObj.DefineDataProperty('allSettled', JSMakeFunction(methodFn), True, False, True);
  methodFn := AHeap.NewNativeMethod('any', @AHeap.PromiseAny);
  methodFn.NotConstructable := True;
  methodFn.SuppressPrototype := True;
  methodFn.LengthOverride := 1;
  promiseObj.DefineDataProperty('any', JSMakeFunction(methodFn), True, False, True);
  AEnv.Define('Promise', JSMakeFunction(promiseCtor));

  // 4. Error
  errCtor := AHeap.NewNativeMethod('Error', @AHeap.ErrorCtor);
  errCtor.LengthOverride := 1;
  errCtor.IntrinsicName := 'Error';
  errCtor.DefineDataProperty('prototype', JSMakeObject(AHeap.GetErrorPrototype()), False, False, False);
  AHeap.GetErrorPrototype().SetProperty('constructor', JSMakeFunction(errCtor));
  AEnv.DefineBuiltin('Error', JSMakeFunction(errCtor));

  typeErrCtor := AHeap.NewNativeMethod('TypeError', @AHeap.TypeErrorCtor);
  typeErrCtor.LengthOverride := 1;
  typeErrCtor.IntrinsicName := 'TypeError';
  typeErrCtor.DefineDataProperty('prototype', JSMakeObject(AHeap.GetTypeErrorPrototype()), False, False, False);
  AHeap.GetTypeErrorPrototype().SetProperty('constructor', JSMakeFunction(typeErrCtor));
  AEnv.DefineBuiltin('TypeError', JSMakeFunction(typeErrCtor));

  rangeErrCtor := AHeap.NewNativeMethod('RangeError', @AHeap.RangeErrorCtor);
  rangeErrCtor.LengthOverride := 1;
  rangeErrCtor.IntrinsicName := 'RangeError';
  rangeErrCtor.DefineDataProperty('prototype', JSMakeObject(AHeap.GetRangeErrorPrototype()), False, False, False);
  AHeap.GetRangeErrorPrototype().SetProperty('constructor', JSMakeFunction(rangeErrCtor));
  AEnv.DefineBuiltin('RangeError', JSMakeFunction(rangeErrCtor));

  refErrCtor := AHeap.NewNativeMethod('ReferenceError', @AHeap.ReferenceErrorCtor);
  refErrCtor.LengthOverride := 1;
  refErrCtor.IntrinsicName := 'ReferenceError';
  refErrCtor.DefineDataProperty('prototype', JSMakeObject(AHeap.GetReferenceErrorPrototype()), False, False, False);
  AHeap.GetReferenceErrorPrototype().SetProperty('constructor', JSMakeFunction(refErrCtor));
  AEnv.DefineBuiltin('ReferenceError', JSMakeFunction(refErrCtor));

  aggErrCtor := AHeap.NewNativeMethod('AggregateError', @AHeap.AggregateErrorCtor);
  aggErrCtor.IntrinsicName := 'AggregateError';
  aggErrCtor.LengthOverride := 2;
  aggErrCtor.DefineDataProperty('prototype', JSMakeObject(AHeap.GetAggregateErrorPrototype()), False, False, False);
  AHeap.GetAggregateErrorPrototype().SetProperty('constructor', JSMakeFunction(aggErrCtor));
  AEnv.DefineBuiltin('AggregateError', JSMakeFunction(aggErrCtor));

  syntaxErrCtor := AHeap.NewNativeMethod('SyntaxError', @AHeap.SyntaxErrorCtor);
  syntaxErrCtor.LengthOverride := 1;
  syntaxErrCtor.IntrinsicName := 'SyntaxError';
  syntaxErrCtor.DefineDataProperty('prototype', JSMakeObject(AHeap.GetSyntaxErrorPrototype()), False, False, False);
  AHeap.GetSyntaxErrorPrototype().SetProperty('constructor', JSMakeFunction(syntaxErrCtor));
  AEnv.DefineBuiltin('SyntaxError', JSMakeFunction(syntaxErrCtor));

  // 4b. Function
  funcObj := AHeap.NewNativeFunction('Function', @JSFunctionCtor);
  funcObj.IntrinsicName := 'Function';
  funcObj.LengthOverride := 1;
  funcObj.SetProperty('prototype', JSMakeObject(AHeap.GetFunctionPrototype()));
  AHeap.GetFunctionPrototype().SetProperty('constructor', JSMakeFunction(funcObj));
  AEnv.Define('Function', JSMakeFunction(funcObj));

  evalObj := AHeap.NewNativeFunction('eval', @JSEvalGlobal);
  evalObj.IntrinsicName := 'eval';
  AEnv.Define('eval', JSMakeFunction(evalObj));

  // 5. Global Functions
  RegisterGlobalFunction(AEnv, AHeap, 'parseInt', @JSParseInt, 2);
  RegisterGlobalFunction(AEnv, AHeap, 'parseFloat', @JSParseFloat, 1);
  AEnv.Define('isNaN', JSMakeFunction(AHeap.NewNativeFunction('isNaN', @JSIsNaN)));
  AEnv.Define('isFinite', JSMakeFunction(AHeap.NewNativeFunction('isFinite', @JSIsFinite)));
  RegisterGlobalFunction(AEnv, AHeap, 'queueMicrotask', @JSQueueMicrotask, 1);
  RegisterGlobalFunction(AEnv, AHeap, 'structuredClone', @JSStructuredClone, 1);
  AEnv.Define('NaN', JSMakeNumber(NaN));
  AEnv.Define('Infinity', JSMakeNumber(Infinity));
  AEnv.Define('undefined', JSMakeUndefined());

  // 6. Number constructor and static methods
  numberObj := AHeap.NewNativeFunction('Number', @JSNumberConst);
  numberObj.IntrinsicName := 'Number';
  numberObj.SetProperty('isNaN', JSMakeFunction(AHeap.NewNativeFunction('isNaN', @JSNumberIsNaN)));
  numberObj.SetProperty('isFinite', JSMakeFunction(AHeap.NewNativeFunction('isFinite', @JSNumberIsFinite)));
  numberObj.SetProperty('isInteger', JSMakeFunction(AHeap.NewNativeFunction('isInteger', @JSNumberIsInteger)));
  methodFn := AHeap.NewNativeFunction('isSafeInteger', @JSNumberIsSafeInteger);
  methodFn.NotConstructable := True;
  methodFn.SuppressPrototype := True;
  methodFn.LengthOverride := 1;
  numberObj.DefineDataProperty('isSafeInteger', JSMakeFunction(methodFn), True, False, True);
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
  numberObj.SetProperty('prototype', JSMakeObject(AHeap.GetNumberPrototype()));
  AEnv.Define('Number', JSMakeFunction(numberObj));

  { BigInt is a conversion function, not a constructor: `new BigInt()` throws. }
  bigIntFn := AHeap.NewNativeFunction('BigInt', @JSBigIntCtor);
  bigIntFn.NotConstructable := True;
  AEnv.Define('BigInt', JSMakeFunction(bigIntFn));

  stringObj := AHeap.NewNativeFunction('String', @JSStringConst);
  stringObj.IntrinsicName := 'String';
  { Publish the shared string prototype so String.prototype methods and
    prototype-chain checks see the same methods primitive strings use. }
  stringObj.SetProperty('prototype', JSMakeObject(AHeap.GetStringPrototype()));
  AHeap.GetStringPrototype().DefineDataProperty('constructor',
    JSMakeFunction(stringObj), True, False, True);
  stringObj.SetProperty('fromCharCode', JSMakeFunction(AHeap.NewNativeFunction('fromCharCode', @JSStringFromCharCode)));
  stringObj.SetProperty('fromCodePoint', JSMakeFunction(AHeap.NewNativeFunction('fromCodePoint', @JSStringFromCodePoint)));
  AEnv.Define('String', JSMakeFunction(stringObj));
  booleanObj := AHeap.NewNativeFunction('Boolean', @JSBooleanConst);
  booleanObj.IntrinsicName := 'Boolean';
  booleanObj.LengthOverride := 1;
  booleanObj.SetProperty('prototype', JSMakeObject(AHeap.GetBooleanPrototype()));
  AHeap.GetBooleanPrototype().SetProperty('constructor', JSMakeFunction(booleanObj));
  AEnv.DefineBuiltin('Boolean', JSMakeFunction(booleanObj));

  // 7. Advanced Globals & Collections (Priority 3)
  FloriaJSRegisterSymbol(AEnv, AHeap);
  FloriaJSRegisterDate(AEnv, AHeap);
  FloriaJSRegisterURI(AEnv, AHeap);
  FloriaJSRegisterCollections(AEnv, AHeap);
  FloriaJSRegisterBinary(AEnv, AHeap);
  { WeakMap/WeakSet currently use the Map/Set storage model: keys are strong
    and primitives are accepted. The API surface is available; true weakness is
    future work. }
  AEnv.Define('WeakMap', AEnv.GetDefault('Map', JSMakeUndefined()));
  AEnv.Define('WeakSet', AEnv.GetDefault('Set', JSMakeUndefined()));
  FloriaJSRegisterTimers(AEnv, AHeap);
  FloriaJSRegisterRegExp(AEnv, AHeap);
  FloriaJSRegisterRegExpMatchAll(AHeap, FloriaJSGetRegExpPrototype());

  // 8. globalThis
  if AEnv.DelegateObject <> nil then
  begin
    { The live global object is the environment's delegate. It already holds
      every var/function and built-in binding as an own property. }
    AEnv.DelegateObject.SetPropertyNonEnumerable('globalThis',
      JSMakeObject(AEnv.DelegateObject));
  end
  else
  begin
    { Compatibility for callers that register the standard library into an
      environment without a global-object delegate. }
    globalObj := AHeap.NewObject();
    for i := 0 to AEnv.GetBindingCount() - 1 do
      globalObj.SetProperty(AEnv.GetBindingName(i), AEnv.GetBindingValue(i));
    globalObj.SetProperty('globalThis', JSMakeObject(globalObj));
    AEnv.Define('globalThis', JSMakeObject(globalObj));
  end;
end;

end.
