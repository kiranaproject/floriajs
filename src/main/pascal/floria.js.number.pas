{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — JavaScript Number Formatting & Parsing          }
{                                                                          }
{   ECMAScript-compatible double-to-string and string-to-double            }
{   conversion, done on exact decimal digit strings.                       }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.number;

{ JavaScript numbers are IEEE-754 doubles, and both directions of conversion
  are observable from a script (`String(x)`, `Number(s)`, and anything that
  stringifies a number). The host formatter and parser are not correctly
  rounded for every value on every target, so this unit converts through exact
  decimal digit strings instead:

  - `JSNumberToStr` produces the shortest decimal that round-trips, in the
    fixed/scientific notation ECMAScript specifies.
  - `JSTryStrToNumber` produces the nearest double, ties to even.

  All arithmetic is on digit strings, so no step can drift. }

{$mode objfpc}{$H+}
interface
uses SysUtils, Math;

{ ECMAScript Number::toString. }
function JSNumberToStr(const V: Double): string;

{ Parses a JavaScript decimal numeral ("[+-]digits[.digits][e[+-]digits]") to
  the nearest double, ties to even. Returns False when the text is not a valid
  numeral. }
function JSTryStrToNumber(const S: string; out V: Double): Boolean;

{ Number::toString(radix) for radix 2..36. The integer part is exact; the
  fractional part is expanded digit by digit until it terminates or the
  available precision is exhausted, as ECMAScript specifies. }
function JSNumberToRadixStr(const V: Double; ARadix: Integer): string;

implementation

const
  EXP_MASK = QWord($7FF0000000000000);
  MANTISSA_MASK = QWord($000FFFFFFFFFFFFF);

type
  TDoubleBits = packed record
    case Boolean of
      False: (D: Double);
      True: (Q: QWord);
  end;

  { Exact decimal: value = (-1)^Neg * Digits * 10^P, with Digits free of
    leading and trailing zeros. }
  TDecimal = record
    Neg: Boolean;
    Digits: string;
    P: Integer;
  end;

{ ---------------- digit-string helpers ---------------- }

function MulDigits(const ADigits: string; AMul: QWord): string;
var
  i: Integer;
  carry, cur: QWord;
begin
  if (ADigits = '0') or (AMul = 0) then Exit('0');
  Result := '';
  carry := 0;
  for i := Length(ADigits) downto 1 do
  begin
    cur := QWord(Ord(ADigits[i]) - Ord('0')) * AMul + carry;
    Result := Chr(Ord('0') + Integer(cur mod 10)) + Result;
    carry := cur div 10;
  end;
  while carry > 0 do
  begin
    Result := Chr(Ord('0') + Integer(carry mod 10)) + Result;
    carry := carry div 10;
  end;
end;

function StripLeadingZeros(const S: string): string;
var
  i: Integer;
begin
  i := 1;
  while (i < Length(S)) and (S[i] = '0') do
    Inc(i);
  Result := Copy(S, i, Length(S));
end;

function IncDigits(const S: string): string;
var
  i: Integer;
begin
  Result := S;
  i := Length(Result);
  while i >= 1 do
  begin
    if Result[i] = '9' then
    begin
      Result[i] := '0';
      Dec(i);
    end
    else
    begin
      Result[i] := Chr(Ord(Result[i]) + 1);
      Exit;
    end;
  end;
  Result := '1' + Result;
end;

function DecDigits(const S: string): string;
var
  i: Integer;
begin
  Result := S;
  i := Length(Result);
  while i >= 1 do
  begin
    if Result[i] = '0' then
    begin
      Result[i] := '9';
      Dec(i);
    end
    else
    begin
      Result[i] := Chr(Ord(Result[i]) - 1);
      Exit(StripLeadingZeros(Result));
    end;
  end;
  Result := '0';
end;

function Pow10Digits(AExp: Integer): string;
begin
  Result := '1' + StringOfChar('0', AExp);
end;

{ ---------------- exact decimals ---------------- }

function DecZero(): TDecimal;
begin
  Result.Neg := False;
  Result.Digits := '0';
  Result.P := 0;
end;

function DecMake(const ADigits: string; AP: Integer; ANeg: Boolean): TDecimal;
var
  shift: Integer;
begin
  Result.Neg := ANeg;
  Result.P := AP;
  Result.Digits := StripLeadingZeros(ADigits);
  if (Result.Digits = '') or (Result.Digits = '0') then Exit(DecZero());
  shift := 0;
  while (Length(Result.Digits) > 1) and (Result.Digits[Length(Result.Digits)] = '0') do
  begin
    Delete(Result.Digits, Length(Result.Digits), 1);
    Inc(shift);
  end;
  Inc(Result.P, shift);
end;

{ Exact decimal of a positive finite double. }
function DecFromDouble(const V: Double): TDecimal;
var
  b: TDoubleBits;
  biased: Integer;
  m: QWord;
  e, k: Integer;
  d: TDecimal;
begin
  Result := DecZero();
  if IsNaN(V) or IsInfinite(V) or (V = 0) then Exit;

  b.D := Abs(V);
  biased := Integer((b.Q and EXP_MASK) shr 52);
  m := b.Q and MANTISSA_MASK;
  if biased = 0 then
    e := -1074                     { subnormal: no implicit leading bit }
  else
  begin
    m := m or (QWord(1) shl 52);   { implicit leading bit }
    e := biased - 1075;
  end;
  if m = 0 then Exit;

  d := DecMake(UIntToStr(m), 0, False);
  if e >= 0 then
  begin
    while e >= 31 do
    begin
      d := DecMake(MulDigits(d.Digits, QWord(1) shl 31), d.P, False);
      Dec(e, 31);
    end;
    if e > 0 then
      d := DecMake(MulDigits(d.Digits, QWord(1) shl e), d.P, False);
    Exit(d);
  end;

  { m / 2^k = m * 5^k / 10^k. }
  k := -e;
  while k >= 13 do
  begin
    d := DecMake(MulDigits(d.Digits, 1220703125), d.P, False); { 5^13 }
    Dec(k, 13);
  end;
  if k > 0 then
    d := DecMake(MulDigits(d.Digits, QWord(Trunc(Power(5, k)))), d.P, False);
  Result := DecMake(d.Digits, d.P - (-e), False);
end;

function CompareAbs(const A, B: TDecimal): Integer;
var
  da, db: string;
  i, len, ea, eb: Integer;
begin
  if A.Digits = '0' then
  begin
    if B.Digits = '0' then Exit(0);
    Exit(-1);
  end;
  if B.Digits = '0' then Exit(1);

  ea := A.P + Length(A.Digits) - 1;
  eb := B.P + Length(B.Digits) - 1;
  if ea <> eb then
  begin
    if ea > eb then Exit(1) else Exit(-1);
  end;

  len := Max(Length(A.Digits), Length(B.Digits));
  da := A.Digits + StringOfChar('0', len - Length(A.Digits));
  db := B.Digits + StringOfChar('0', len - Length(B.Digits));
  for i := 1 to len do
    if da[i] <> db[i] then
    begin
      if da[i] > db[i] then Exit(1) else Exit(-1);
    end;
  Result := 0;
end;

function AddAbs(const A, B: TDecimal): TDecimal;
var
  da, db, sum: string;
  p, i, len, s, carry: Integer;
begin
  if A.Digits = '0' then Exit(B);
  if B.Digits = '0' then Exit(A);

  p := Min(A.P, B.P);
  da := A.Digits + StringOfChar('0', A.P - p);
  db := B.Digits + StringOfChar('0', B.P - p);
  len := Max(Length(da), Length(db));
  da := StringOfChar('0', len - Length(da)) + da;
  db := StringOfChar('0', len - Length(db)) + db;

  sum := '';
  carry := 0;
  for i := len downto 1 do
  begin
    s := Ord(da[i]) - Ord('0') + Ord(db[i]) - Ord('0') + carry;
    carry := s div 10;
    sum := Chr(Ord('0') + (s mod 10)) + sum;
  end;
  if carry > 0 then
    sum := Chr(Ord('0') + carry) + sum;
  Result := DecMake(sum, p, False);
end;

{ |A| - |B|; requires |A| >= |B|. }
function SubAbs(const A, B: TDecimal): TDecimal;
var
  da, db, diff: string;
  p, i, len, s, borrow: Integer;
begin
  if B.Digits = '0' then Exit(A);
  p := Min(A.P, B.P);
  da := A.Digits + StringOfChar('0', A.P - p);
  db := B.Digits + StringOfChar('0', B.P - p);
  len := Max(Length(da), Length(db));
  da := StringOfChar('0', len - Length(da)) + da;
  db := StringOfChar('0', len - Length(db)) + db;
  diff := '';
  borrow := 0;
  for i := len downto 1 do
  begin
    s := Ord(da[i]) - Ord('0') - (Ord(db[i]) - Ord('0')) - borrow;
    if s < 0 then
    begin
      Inc(s, 10);
      borrow := 1;
    end
    else
      borrow := 0;
    diff := Chr(Ord('0') + s) + diff;
  end;
  Result := DecMake(diff, p, False);
end;

function HalfDec(const A: TDecimal): TDecimal;
begin
  if A.Digits = '0' then Exit(DecZero());
  Result := DecMake(MulDigits(A.Digits, 5), A.P - 1, False);
end;

function MantissaIsEven(const V: Double): Boolean;
var
  b: TDoubleBits;
begin
  b.D := V;
  Result := (b.Q and 1) = 0;
end;

function NextUp(const V: Double): Double;
var
  b: TDoubleBits;
begin
  b.D := V;
  if (b.Q and EXP_MASK) = EXP_MASK then Exit(V);
  if b.Q = 0 then b.Q := 1 else Inc(b.Q);
  Result := b.D;
end;

function NextDown(const V: Double): Double;
var
  b: TDoubleBits;
begin
  b.D := V;
  if (b.Q = 0) or ((b.Q and EXP_MASK) = EXP_MASK) then Exit(V);
  Dec(b.Q);
  Result := b.D;
end;

{ ---------------- scaling helpers ---------------- }

{ Integer floor of value * 10^AScale. }
function ScaledFloor(const A: TDecimal; AScale: Integer): string;
var
  p: Integer;
begin
  p := A.P + AScale;
  if p >= 0 then
    Result := A.Digits + StringOfChar('0', p)
  else if Length(A.Digits) + p <= 0 then
    Result := '0'
  else
    Result := Copy(A.Digits, 1, Length(A.Digits) + p);
  Result := StripLeadingZeros(Result);
end;

{ True when value * 10^AScale is an exact integer. }
function IsExactInteger(const A: TDecimal; AScale: Integer): Boolean;
var
  p, i: Integer;
begin
  p := A.P + AScale;
  if p >= 0 then Exit(True);
  if Length(A.Digits) + p <= 0 then Exit(A.Digits = '0');
  for i := Length(A.Digits) + p + 1 to Length(A.Digits) do
    if A.Digits[i] <> '0' then Exit(False);
  Result := True;
end;

{ Rounds a positive exact decimal to the nearest integer, ties to even. }
function RoundToInteger(const A: TDecimal): string;
var
  pointPos, i: Integer;
  intPart, fracPart: string;
  firstFrac: Char;
  restNonZero, roundUp: Boolean;
begin
  { Number of digits before the decimal point. }
  pointPos := Length(A.Digits) + A.P;

  if pointPos >= Length(A.Digits) then
    Exit(A.Digits + StringOfChar('0', pointPos - Length(A.Digits)));

  if pointPos <= 0 then
  begin
    { The value is below one. Compare it with a half. }
    if pointPos < 0 then Exit('0');
    if A.Digits[1] > '5' then Exit('1');
    if A.Digits[1] < '5' then Exit('0');
    for i := 2 to Length(A.Digits) do
      if A.Digits[i] <> '0' then Exit('1');
    Exit('0');  { exactly one half, and zero is the even neighbour }
  end;

  intPart := Copy(A.Digits, 1, pointPos);
  fracPart := Copy(A.Digits, pointPos + 1, Length(A.Digits));
  firstFrac := fracPart[1];
  restNonZero := False;
  for i := 2 to Length(fracPart) do
    if fracPart[i] <> '0' then
    begin
      restNonZero := True;
      Break;
    end;

  if (firstFrac = '5') and (not restNonZero) then
    roundUp := ((Ord(intPart[Length(intPart)]) - Ord('0')) mod 2) = 1
  else
    roundUp := (firstFrac > '5') or ((firstFrac = '5') and restNonZero);

  if roundUp then
    Result := IncDigits(intPart)
  else
    Result := intPart;
end;

{ ---------------- shortest round-tripping decimal ---------------- }

{ True when the k-digit integer AM, in units of 10^(-AScale), lies inside the
  rounding interval of V. }
function CandidateRoundsTo(const AM: string; AScale: Integer;
  const AMidLow, AMidHigh: TDecimal; AEvenMantissa: Boolean): Boolean;
var
  cand: TDecimal;
  cmpLow, cmpHigh: Integer;
begin
  cand := DecMake(AM, -AScale, False);
  cmpLow := CompareAbs(cand, AMidLow);
  cmpHigh := CompareAbs(cand, AMidHigh);
  if (cmpLow < 0) or (cmpHigh > 0) then Exit(False);
  { An endpoint is inclusive only for an even mantissa. }
  if (cmpLow = 0) or (cmpHigh = 0) then Exit(AEvenMantissa);
  Result := True;
end;

{ Shortest decimal that rounds back to V.

  For each digit count k the exact value is rounded to k significant digits,
  and that candidate together with its two neighbours is tested against the
  exact rounding interval of V. The first candidate that round-trips is the
  shortest representation, preferring the rounded one because it is nearest. }
function ShortestDecimal(const V: Double; out ADigits: string; out AN: Integer): Boolean;
var
  exact, midLow, midHigh, scaled: TDecimal;
  evenMantissa: Boolean;
  k, scale, n, candScale: Integer;
  upperUnbounded: Boolean;
  rounded, best: string;
  hasBest: Boolean;
  bestDist: TDecimal;

  { Records AM when it is a valid k-digit candidate, keeping the nearest. }
  procedure Consider(const AM: string);
  var
    c, dist: TDecimal;
    cmpLow, cmpHigh: Integer;
  begin
    if (AM = '') or (AM = '0') or (Length(AM) > k + 1) then Exit;
    { The candidate is m * 10^candScale. }
    c := DecMake(AM, candScale, False);
    cmpLow := CompareAbs(c, midLow);
    if cmpLow < 0 then Exit;
    cmpHigh := CompareAbs(c, midHigh);
    if cmpHigh > 0 then Exit;
    { An endpoint belongs to the interval only for an even mantissa. }
    if ((cmpLow = 0) or (cmpHigh = 0)) and (not evenMantissa) then Exit;

    if CompareAbs(c, exact) >= 0 then
      dist := SubAbs(c, exact)
    else
      dist := SubAbs(exact, c);
    if (not hasBest) or (CompareAbs(dist, bestDist) < 0) then
    begin
      hasBest := True;
      best := AM;
      bestDist := dist;
    end;
  end;

begin
  Result := False;
  ADigits := '';
  AN := 0;

  exact := DecFromDouble(V);
  if exact.Digits = '0' then Exit;

  midLow := HalfDec(AddAbs(exact, DecFromDouble(NextDown(V))));
  { The largest finite double has no finite upper neighbour. Its rounding
    interval still ends at the overflow threshold, which is 2^1024 - 2^970
    (halfway between the max double and 2^1024), so that midpoint is used
    instead of a neighbour-derived one. }
  upperUnbounded := IsInfinite(NextUp(V));
  if upperUnbounded then
  begin
    { The interval ends at the overflow threshold, halfway between the max
      double and 2^1024. Since V is that max double, the threshold is
      exact + 2^970. }
    midHigh := AddAbs(exact, DecFromDouble(Power(2.0, 970)));
  end
  else
    midHigh := HalfDec(AddAbs(exact, DecFromDouble(NextUp(V))));
  evenMantissa := MantissaIsEven(V);

  { V = 0.Digits * 10^n, so a k-significant-digit candidate is an integer in
    units of 10^(n-k). }
  n := exact.P + Length(exact.Digits);

  for k := 1 to 17 do
  begin
    scale := n - k;
    scaled := exact;
    Inc(scaled.P, -scale);
    rounded := RoundToInteger(scaled);

    { Rounding can carry into an extra digit (9.9 -> 10), in which case the
      k-digit form is 10^(k-1) one decade higher. }
    candScale := scale;
    if Length(rounded) = k + 1 then
    begin
      rounded := '1' + StringOfChar('0', k - 1);
      Inc(candScale);
    end;

    hasBest := False;
    best := '';
    Consider(rounded);
    if rounded <> '0' then
    begin
      Consider(DecDigits(rounded));
      Consider(IncDigits(rounded));
    end;

    if hasBest then
    begin
      ADigits := best;
      AN := Length(best) + candScale;
      Exit(True);
    end
    else if GetEnvironmentVariable('NUMFMT_DEBUG') = '1' then
      WriteLn('k=', k, ' scale=', candScale, ' rounded=', Copy(rounded,1,20),
        ' midLowLen=', Length(midLow.Digits), ' midHighLen=', Length(midHigh.Digits));
  end;

  ADigits := exact.Digits;
  AN := n;
  Result := True;
end;


{ ---------------- correctly rounded string -> double ---------------- }

{ Rounds a positive exact decimal to the nearest double, ties to even. The host
  parser supplies a seed; the exact rounding interval of that seed then decides
  whether to keep it or step to a neighbour. This corrects the host parser,
  which is not correctly rounded for every input. }
function DecToDoubleAbs(const A: TDecimal; out V: Double): Boolean;
var
  target, exact, midLow, midHigh: TDecimal;
  d, next: Double;
  code, guard: Integer;
  cmpLow, cmpHigh: Integer;
begin
  Result := False;
  V := 0;
  if A.Digits = '0' then
  begin
    Result := True;
    Exit;
  end;

  target := A;
  target.Neg := False;

  { Seed from the host. Only its neighbourhood is used, so an off-by-one seed
    is corrected by the loop below. The host parser overflows where a correct
    parse would too, so an overflow seed is an overflow result. }
  d := 0;
  code := 0;
  try
    Val('0.' + target.Digits + 'E' + IntToStr(target.P + Length(target.Digits)), d, code);
  except
    { The host parser raises on overflow. JavaScript saturates to Infinity. }
    V := Infinity;
    Result := True;
    Exit;
  end;
  if code <> 0 then Exit;
  if IsNaN(d) then Exit;
  if IsInfinite(d) then
  begin
    V := Infinity;
    Result := True;
    Exit;
  end;
  if d < 0 then Exit;
  if d = 0 then
  begin
    { Underflow: the nearest double is zero when below half the smallest
      subnormal, and the smallest subnormal otherwise. The seed is already the
      correctly rounded result in both cases. }
    V := 0;
    Result := True;
    Exit;
  end;

  guard := 0;
  repeat
    Inc(guard);
    if guard > 12 then Exit;

    exact := DecFromDouble(d);
    midLow := HalfDec(AddAbs(exact, DecFromDouble(NextDown(d))));

    if IsInfinite(NextUp(d)) then
    begin
      { The top double's interval ends at the overflow threshold, halfway
        between the max double and 2^1024. }
      midHigh := AddAbs(exact, DecFromDouble(Power(2.0, 970)));
    end
    else
      midHigh := HalfDec(AddAbs(exact, DecFromDouble(NextUp(d))));

    cmpLow := CompareAbs(target, midLow);
    cmpHigh := CompareAbs(target, midHigh);

    if cmpHigh > 0 then
    begin
      next := NextUp(d);
      if IsInfinite(next) then
      begin
        { Above the overflow threshold the result saturates. }
        V := Infinity;
        Result := True;
        Exit;
      end;
      d := next;
      Continue;
    end;
    if cmpLow < 0 then
    begin
      next := NextDown(d);
      if next = 0 then Exit;
      d := next;
      Continue;
    end;

    { Exactly on a midpoint: keep the even mantissa. }
    if (cmpHigh = 0) and (not MantissaIsEven(d)) then
    begin
      next := NextUp(d);
      if IsInfinite(next) then
      begin
        V := Infinity;
        Result := True;
        Exit;
      end;
      d := next;
      Continue;
    end;
    if (cmpLow = 0) and (not MantissaIsEven(d)) then
    begin
      next := NextDown(d);
      if next = 0 then Exit;
      d := next;
      Continue;
    end;

    V := d;
    Result := True;
    Exit;
  until False;
end;

function JSTryStrToNumber(const S: string; out V: Double): Boolean;
var
  i, n: Integer;
  neg: Boolean;
  intPart, fracPart, expPart: string;
  expVal: Integer;
  magnitude: TDecimal;
  mag: Double;
begin
  Result := False;
  V := 0;
  n := Length(S);
  if n = 0 then Exit;

  i := 1;
  neg := False;
  if S[i] = '+' then
    Inc(i)
  else if S[i] = '-' then
  begin
    neg := True;
    Inc(i);
  end;

  intPart := '';
  while (i <= n) and (S[i] >= '0') and (S[i] <= '9') do
  begin
    intPart := intPart + S[i];
    Inc(i);
  end;
  fracPart := '';
  if (i <= n) and (S[i] = '.') then
  begin
    Inc(i);
    while (i <= n) and (S[i] >= '0') and (S[i] <= '9') do
    begin
      fracPart := fracPart + S[i];
      Inc(i);
    end;
  end;
  if (intPart = '') and (fracPart = '') then Exit;

  expVal := 0;
  if (i <= n) and ((S[i] = 'e') or (S[i] = 'E')) then
  begin
    Inc(i);
    expPart := '';
    if (i <= n) and ((S[i] = '+') or (S[i] = '-')) then
    begin
      expPart := S[i];
      Inc(i);
    end;
    while (i <= n) and (S[i] >= '0') and (S[i] <= '9') do
    begin
      expPart := expPart + S[i];
      Inc(i);
    end;
    if (expPart = '') or (expPart = '+') or (expPart = '-') then Exit;
    if not TryStrToInt(expPart, expVal) then Exit;
  end;
  if i <= n then Exit;  { trailing junk }

  { The digits are an integer scaled by the fraction length and the exponent. }
  magnitude := DecMake(intPart + fracPart, expVal - Length(fracPart), False);
  if magnitude.Digits = '0' then
  begin
    V := 0;
    Result := True;
    Exit;
  end;

  if not DecToDoubleAbs(magnitude, mag) then Exit;

  if neg then
    V := -mag
  else
    V := mag;
  Result := True;
end;


{ ---------------- radix conversion ---------------- }

function DigitChar(ADigit: Integer): Char;
begin
  if ADigit < 10 then
    Result := Chr(Ord('0') + ADigit)
  else
    Result := Chr(Ord('a') + ADigit - 10);
end;

function JSNumberToRadixStr(const V: Double; ARadix: Integer): string;
var
  neg: Boolean;
  value, intPart, fracPart: Double;
  intDigits, fracDigits: string;
  d: Integer;
  guard: Integer;
begin
  if (ARadix < 2) or (ARadix > 36) then
    raise EConvertError.Create('radix out of range');
  if IsNaN(V) then Exit('NaN');
  if IsInfinite(V) then
  begin
    if V > 0 then Exit('Infinity');
    Exit('-Infinity');
  end;
  if V = 0 then Exit('0');
  if ARadix = 10 then Exit(JSNumberToStr(V));

  neg := V < 0;
  value := Abs(V);

  { Integer part, built from the exact double. }
  intPart := Int(value);
  if intPart = 0 then
    intDigits := '0'
  else
  begin
    intDigits := '';
    while intPart >= 1 do
    begin
      d := Trunc(FMod(intPart, ARadix));
      intDigits := DigitChar(d) + intDigits;
      intPart := Int(intPart / ARadix);
    end;
  end;

  { Fractional part: multiply by the radix and take the leading digit. The
    loop is bounded because a double's expansion terminates in every radix that
    divides a power of two; other radices stop at the available precision. }
  fracPart := value - Int(value);
  fracDigits := '';
  guard := 0;
  while (fracPart > 0) and (guard < 1100) do
  begin
    fracPart := fracPart * ARadix;
    d := Trunc(fracPart);
    if d >= ARadix then d := ARadix - 1;
    fracDigits := fracDigits + DigitChar(d);
    fracPart := fracPart - d;
    Inc(guard);
  end;

  Result := intDigits;
  if fracDigits <> '' then
    Result := Result + '.' + fracDigits;
  if neg then
    Result := '-' + Result;
end;

{ ---------------- formatting ---------------- }

function FormatFixed(const ADigits: string; AN: Integer): string;
begin
  if AN <= 0 then
    Result := '0.' + StringOfChar('0', -AN) + ADigits
  else if AN >= Length(ADigits) then
    Result := ADigits + StringOfChar('0', AN - Length(ADigits))
  else
    Result := Copy(ADigits, 1, AN) + '.' + Copy(ADigits, AN + 1, Length(ADigits));
end;

function FormatExponential(const ADigits: string; AN: Integer): string;
var
  e: Integer;
begin
  e := AN - 1;
  Result := ADigits[1];
  if Length(ADigits) > 1 then
    Result := Result + '.' + Copy(ADigits, 2, Length(ADigits));
  if e >= 0 then
    Result := Result + 'e+' + IntToStr(e)
  else
    Result := Result + 'e-' + IntToStr(-e);
end;

function JSNumberToStr(const V: Double): string;
var
  digits: string;
  n: Integer;
begin
  if IsNaN(V) then Exit('NaN');
  if IsInfinite(V) then
  begin
    if V > 0 then Exit('Infinity');
    Exit('-Infinity');
  end;
  if V = 0 then Exit('0');

  if not ShortestDecimal(Abs(V), digits, n) then Exit('0');

  if (n > 21) or (n <= -6) then
    Result := FormatExponential(digits, n)
  else
    Result := FormatFixed(digits, n);

  if V < 0 then
    Result := '-' + Result;
end;

end.
