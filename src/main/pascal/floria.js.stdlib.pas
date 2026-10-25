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
  floria.js.timers, floria.js.regexp;

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


{ `BigInt(value)` — converts a number, string, or boolean to a BigInt.

  A Number must be integral: converting 1.5 throws a RangeError, as ECMAScript
  specifies, because silently truncating would lose data. }
function JSBigIntCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  v: TFloriaJSValue;
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

function JSParseInt(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  radixVal: Double;
  radix: Integer;
  i: Integer;
  sign: Integer;
  n: Int64;
  c: Char;
  digit: Integer;
  hasDigits: Boolean;
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

  n := 0;
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

  Result := JSMakeNumber(Double(sign) * Double(n));
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
  promiseCtor, bigIntFn: TFloriaJSFunction;
  numberObj, stringObj, funcObj: TFloriaJSFunction;
  errCtor, typeErrCtor, rangeErrCtor, refErrCtor, syntaxErrCtor: TFloriaJSFunction;
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
  AEnv.Define('Math', JSMakeObject(mathObj));

  { Array iteration: `values` and `[Symbol.iterator]` both return an iterator
    over the receiver, which is what `for…of` and spread consume. The symbol
    stores under its string form, so that is the key. }
  if AHeap.GetArrayPrototype() <> nil then
  begin
    AHeap.GetArrayPrototype().SetProperty('values',
      JSMakeFunction(AHeap.NewNativeFunction('values', @JSArrayValues)));
    AHeap.GetArrayPrototype().SetProperty('Symbol(Symbol.iterator)',
      JSMakeFunction(AHeap.NewNativeFunction('[Symbol.iterator]', @JSArrayValues)));
  end;

  // 3. Promise
  { `Promise` is a constructor: `new Promise(executor)` builds a promise and
    returns it, while the statics hang off the same function object. }
  promiseCtor := AHeap.NewNativeMethod('Promise', @AHeap.PromiseConstructor);
  promiseObj := promiseCtor;
  promiseObj.SetProperty('resolve', JSMakeFunction(AHeap.NewNativeMethod('resolve', @AHeap.PromiseResolve)));
  promiseObj.SetProperty('reject', JSMakeFunction(AHeap.NewNativeMethod('reject', @AHeap.PromiseReject)));
  promiseObj.SetProperty('all', JSMakeFunction(AHeap.NewNativeMethod('all', @AHeap.PromiseAll)));
  promiseObj.SetProperty('race', JSMakeFunction(AHeap.NewNativeMethod('race', @AHeap.PromiseRace)));
  AEnv.Define('Promise', JSMakeFunction(promiseCtor));

  // 4. Error
  errCtor := AHeap.NewNativeMethod('Error', @AHeap.ErrorCtor);
  errCtor.SetProperty('prototype', JSMakeObject(AHeap.GetErrorPrototype()));
  AEnv.Define('Error', JSMakeFunction(errCtor));

  typeErrCtor := AHeap.NewNativeMethod('TypeError', @AHeap.TypeErrorCtor);
  typeErrCtor.SetProperty('prototype', JSMakeObject(AHeap.GetTypeErrorPrototype()));
  AEnv.Define('TypeError', JSMakeFunction(typeErrCtor));

  rangeErrCtor := AHeap.NewNativeMethod('RangeError', @AHeap.RangeErrorCtor);
  rangeErrCtor.SetProperty('prototype', JSMakeObject(AHeap.GetRangeErrorPrototype()));
  AEnv.Define('RangeError', JSMakeFunction(rangeErrCtor));

  refErrCtor := AHeap.NewNativeMethod('ReferenceError', @AHeap.ReferenceErrorCtor);
  refErrCtor.SetProperty('prototype', JSMakeObject(AHeap.GetReferenceErrorPrototype()));
  AEnv.Define('ReferenceError', JSMakeFunction(refErrCtor));

  syntaxErrCtor := AHeap.NewNativeMethod('SyntaxError', @AHeap.SyntaxErrorCtor);
  syntaxErrCtor.SetProperty('prototype', JSMakeObject(AHeap.GetSyntaxErrorPrototype()));
  AEnv.Define('SyntaxError', JSMakeFunction(syntaxErrCtor));

  // 4b. Function
  funcObj := AHeap.NewNativeFunction('Function', @JSFunctionCtor);
  funcObj.SetProperty('prototype', JSMakeObject(AHeap.GetFunctionPrototype()));
  AHeap.GetFunctionPrototype().SetProperty('constructor', JSMakeFunction(funcObj));
  AEnv.Define('Function', JSMakeFunction(funcObj));

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
  numberObj.SetProperty('prototype', JSMakeObject(AHeap.GetNumberPrototype()));
  AEnv.Define('Number', JSMakeFunction(numberObj));

  { BigInt is a conversion function, not a constructor: `new BigInt()` throws. }
  bigIntFn := AHeap.NewNativeFunction('BigInt', @JSBigIntCtor);
  bigIntFn.NotConstructable := True;
  AEnv.Define('BigInt', JSMakeFunction(bigIntFn));

  stringObj := AHeap.NewNativeFunction('String', @JSStringConst);
  { Publish the shared string prototype so String.prototype methods and
    prototype-chain checks see the same methods primitive strings use. }
  stringObj.SetProperty('prototype', JSMakeObject(AHeap.GetStringPrototype()));
  AEnv.Define('String', JSMakeFunction(stringObj));
  AEnv.Define('Boolean', JSMakeFunction(AHeap.NewNativeFunction('Boolean', @JSBooleanConst)));

  // 7. Advanced Globals & Collections (Priority 3)
  FloriaJSRegisterSymbol(AEnv, AHeap);
  FloriaJSRegisterDate(AEnv, AHeap);
  FloriaJSRegisterURI(AEnv, AHeap);
  FloriaJSRegisterCollections(AEnv, AHeap);
  FloriaJSRegisterTimers(AEnv, AHeap);
  FloriaJSRegisterRegExp(AEnv, AHeap);

  // 8. globalThis
  globalObj := AHeap.NewObject();
  globalObj.SetProperty('globalThis', JSMakeObject(globalObj));
  globalObj.SetProperty('NaN', JSMakeNumber(NaN));
  globalObj.SetProperty('Infinity', JSMakeNumber(Infinity));
  globalObj.SetProperty('undefined', JSMakeUndefined());
  globalObj.SetProperty('Math', JSMakeObject(mathObj));
  globalObj.SetProperty('console', JSMakeObject(consoleObj));
  globalObj.SetProperty('Array', AEnv.GetDefault('Array', JSMakeUndefined()));
  globalObj.SetProperty('Object', AEnv.GetDefault('Object', JSMakeUndefined()));
  globalObj.SetProperty('Function', JSMakeFunction(funcObj));
  globalObj.SetProperty('Number', JSMakeFunction(numberObj));
  globalObj.SetProperty('String', AEnv.GetDefault('String', JSMakeUndefined()));
  globalObj.SetProperty('Boolean', AEnv.GetDefault('Boolean', JSMakeUndefined()));
  globalObj.SetProperty('JSON', AEnv.GetDefault('JSON', JSMakeUndefined()));
  globalObj.SetProperty('Promise', JSMakeFunction(promiseCtor));
  globalObj.SetProperty('Error', JSMakeFunction(errCtor));
  globalObj.SetProperty('TypeError', JSMakeFunction(typeErrCtor));
  globalObj.SetProperty('RangeError', JSMakeFunction(rangeErrCtor));
  globalObj.SetProperty('ReferenceError', JSMakeFunction(refErrCtor));
  globalObj.SetProperty('SyntaxError', JSMakeFunction(syntaxErrCtor));
  globalObj.SetProperty('URIError', AEnv.GetDefault('URIError', JSMakeUndefined()));
  globalObj.SetProperty('Symbol', AEnv.GetDefault('Symbol', JSMakeUndefined()));
  globalObj.SetProperty('Date', AEnv.GetDefault('Date', JSMakeUndefined()));
  globalObj.SetProperty('Map', AEnv.GetDefault('Map', JSMakeUndefined()));
  globalObj.SetProperty('Set', AEnv.GetDefault('Set', JSMakeUndefined()));
  globalObj.SetProperty('RegExp', AEnv.GetDefault('RegExp', JSMakeUndefined()));
  globalObj.SetProperty('encodeURIComponent', AEnv.GetDefault('encodeURIComponent', JSMakeUndefined()));
  globalObj.SetProperty('decodeURIComponent', AEnv.GetDefault('decodeURIComponent', JSMakeUndefined()));
  globalObj.SetProperty('encodeURI', AEnv.GetDefault('encodeURI', JSMakeUndefined()));
  globalObj.SetProperty('decodeURI', AEnv.GetDefault('decodeURI', JSMakeUndefined()));
  globalObj.SetProperty('setTimeout', AEnv.GetDefault('setTimeout', JSMakeUndefined()));
  globalObj.SetProperty('clearTimeout', AEnv.GetDefault('clearTimeout', JSMakeUndefined()));
  globalObj.SetProperty('setInterval', AEnv.GetDefault('setInterval', JSMakeUndefined()));
  globalObj.SetProperty('clearInterval', AEnv.GetDefault('clearInterval', JSMakeUndefined()));
  globalObj.SetProperty('parseInt', AEnv.GetDefault('parseInt', JSMakeUndefined()));
  globalObj.SetProperty('parseFloat', AEnv.GetDefault('parseFloat', JSMakeUndefined()));
  globalObj.SetProperty('isNaN', AEnv.GetDefault('isNaN', JSMakeUndefined()));
  globalObj.SetProperty('isFinite', AEnv.GetDefault('isFinite', JSMakeUndefined()));
  AEnv.Define('globalThis', JSMakeObject(globalObj));
end;

end.
