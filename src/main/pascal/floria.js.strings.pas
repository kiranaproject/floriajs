{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Built-in String Methods                         }
{                                                                          }
{   Implements the JavaScript-visible methods of string primitives. The     }
{   methods live on a shared prototype owned by the heap, so accessing      }
{   "text".slice(1) works without boxing the primitive.                     }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.strings;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, floria.js.types, floria.js.value,
  floria.js.regexp, floria.js.utf16, floria.js.unicode, floria.js.collections,
  floria.js.symbol;

procedure FloriaJSRegisterString(AHeap: TFloriaJSHeap);
{ Adds RegExp.prototype[Symbol.matchAll], which needs the iterator type. }
procedure FloriaJSRegisterRegExpMatchAll(AHeap: TFloriaJSHeap; AProto: TFloriaJSObject);

implementation

type
  { The heap owns one instance of this helper for the lifetime of the string
    prototype. It provides the methods that need to allocate values or invoke
    user callbacks. }
  TFloriaJSStringHelper = class
  private
    FHeap: TFloriaJSHeap;
    function ReplacementText(const AWhole, AMatch: string; AIndex: Integer;
      const AReplacement: TFloriaJSValue): string;
    function ArgString(const AValue: TFloriaJSValue): string;
  public
    constructor Create(AHeap: TFloriaJSHeap);

    function At(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function CharAt(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function CharCodeAt(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function IndexOf(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function LastIndexOf(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function Includes(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function StartsWith(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function EndsWith(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function Slice(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function Substring(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function Substr(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function ToUpperCase(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function ToLowerCase(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function Trim(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function TrimStart(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function TrimEnd(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function Split(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function Replace(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function ReplaceAll(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function Match(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function MatchAll(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function RegExpMatchAll(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function Search(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function Concat(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function RepeatString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function PadStart(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function PadEnd(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function ToStringValue(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function Normalize(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function LocaleCompare(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
  end;

function ThisString(const AThis: TFloriaJSValue): string;
begin
  if AThis.IsString() then
    Result := AThis.StrVal
  else
    Result := AThis.ToString();
end;

function StringArg(const AArgs: array of TFloriaJSValue; AIndex: Integer;
  const ADefault: string): string;
begin
  if (AIndex > High(AArgs)) or AArgs[AIndex].IsUndefined() then
    Result := ADefault
  else
    Result := AArgs[AIndex].ToString();
end;

function NumberToInt(const AValue: TFloriaJSValue): Integer;
var
  d: Double;
begin
  d := AValue.ToNumber();
  if IsNaN(d) then
    Exit(0);
  if d >= 2147483647.0 then
    Exit(2147483647);
  if d <= -2147483648.0 then
    Exit(-2147483648);
  Result := Trunc(d);
end;

function IntArg(const AArgs: array of TFloriaJSValue; AIndex, ADefault: Integer): Integer;
begin
  if AIndex > High(AArgs) then
    Exit(ADefault);
  if AArgs[AIndex].IsUndefined() then
    Exit(ADefault);
  Result := NumberToInt(AArgs[AIndex]);
end;

function NormalizeIndex(AIndex, ALen: Integer): Integer;
begin
  if AIndex < 0 then
  begin
    Result := ALen + AIndex;
    if Result < 0 then Result := 0;
  end
  else if AIndex > ALen then
    Result := ALen
  else
    Result := AIndex;
end;

constructor TFloriaJSStringHelper.Create(AHeap: TFloriaJSHeap);
begin
  inherited Create();
  FHeap := AHeap;
end;

function TFloriaJSStringHelper.At(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  len, idx: Integer;
  d: Double;
begin
  if AThis.IsNull() or AThis.IsUndefined() or AThis.IsSymbol() then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError',
      'String.prototype.at requires that this be coercible to a string')));
  if (Length(AArgs) > 0) and AArgs[0].IsSymbol() then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError',
      'Cannot convert a Symbol value to a number')));
  s := ThisString(AThis);
  len := JSUTF16Length(s);
  d := 0;
  if Length(AArgs) > 0 then
    d := AArgs[0].ToNumber();
  if IsNaN(d) then
    d := 0;
  if IsInfinite(d) then
  begin
    if d > 0 then Exit(JSMakeUndefined());
    d := 0;
  end;
  idx := Trunc(d);
  if idx < 0 then
    idx := len + idx;
  if (idx < 0) or (idx >= len) then
    Exit(JSMakeUndefined());
  Result := JSMakeString(JSUTF16CharAt(s, idx));
end;

function TFloriaJSStringHelper.CharAt(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  i: Integer;
begin
  s := ThisString(AThis);
  i := IntArg(AArgs, 0, 0);
  if (i < 0) or (i >= JSUTF16Length(s)) then
    Exit(JSMakeString(''));
  Result := JSMakeString(JSUTF16CharAt(s, i));
end;

function TFloriaJSStringHelper.CharCodeAt(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  i: Integer;
begin
  s := ThisString(AThis);
  i := IntArg(AArgs, 0, 0);
  if (i < 0) or (i >= JSUTF16Length(s)) then
    Exit(JSMakeNumber(NaN));
  Result := JSMakeNumber(JSUTF16CharCodeAt(s, i));
end;

function TFloriaJSStringHelper.IndexOf(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, needle: string;
  from, p: Integer;
begin
  s := ThisString(AThis);
  needle := JSMakeUndefined().ToString();
  if Length(AArgs) > 0 then needle := AArgs[0].ToString();

  from := IntArg(AArgs, 1, 0);
  Result := JSMakeNumber(JSUTF16IndexOf(s, needle, from));
end;

function TFloriaJSStringHelper.LastIndexOf(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, needle: string;
  from, i, maxStart: Integer;
begin
  s := ThisString(AThis);
  needle := JSMakeUndefined().ToString();
  if Length(AArgs) > 0 then needle := AArgs[0].ToString();

  from := IntArg(AArgs, 1, JSUTF16Length(s));
  Result := JSMakeNumber(JSUTF16LastIndexOf(s, needle, from));
end;

function TFloriaJSStringHelper.Includes(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, needle: string;
  from, p: Integer;
begin
  s := ThisString(AThis);
  needle := '';
  if Length(AArgs) > 0 then needle := AArgs[0].ToString();

  from := IntArg(AArgs, 1, 0);
  Result := JSMakeBoolean(JSUTF16IndexOf(s, needle, from) >= 0);
end;

function TFloriaJSStringHelper.StartsWith(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, needle: string;
  pos: Integer;
begin
  s := ThisString(AThis);
  needle := '';
  if Length(AArgs) > 0 then needle := AArgs[0].ToString();

  pos := IntArg(AArgs, 1, 0);
  Result := JSMakeBoolean(JSUTF16IndexOf(s, needle, pos) = pos);
end;

function TFloriaJSStringHelper.EndsWith(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, needle: string;
  finish: Integer;
begin
  s := ThisString(AThis);
  needle := '';
  if Length(AArgs) > 0 then needle := AArgs[0].ToString();

  finish := IntArg(AArgs, 1, JSUTF16Length(s));
  if finish < 0 then finish := 0;
  if finish > JSUTF16Length(s) then finish := JSUTF16Length(s);
  if JSUTF16Length(needle) > finish then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(
    JSUTF16Slice(s, finish - JSUTF16Length(needle), JSUTF16Length(needle)) = needle);
end;

function TFloriaJSStringHelper.Slice(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  start, finish: Integer;
begin
  s := ThisString(AThis);
  start := NormalizeIndex(IntArg(AArgs, 0, 0), JSUTF16Length(s));
  finish := NormalizeIndex(IntArg(AArgs, 1, JSUTF16Length(s)), JSUTF16Length(s));

  if finish <= start then
    Exit(JSMakeString(''));

  Result := JSMakeString(JSUTF16Slice(s, start, finish - start));
end;

function TFloriaJSStringHelper.Substring(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  start, finish, temp: Integer;
begin
  s := ThisString(AThis);

  start := IntArg(AArgs, 0, 0);
  finish := IntArg(AArgs, 1, JSUTF16Length(s));

  if start < 0 then start := 0;
  if start > JSUTF16Length(s) then start := JSUTF16Length(s);
  if finish < 0 then finish := 0;
  if finish > JSUTF16Length(s) then finish := JSUTF16Length(s);

  if start > finish then
  begin
    temp := start;
    start := finish;
    finish := temp;
  end;

  Result := JSMakeString(JSUTF16Slice(s, start, finish - start));
end;

function TFloriaJSStringHelper.Substr(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  start, count: Integer;
begin
  s := ThisString(AThis);

  start := IntArg(AArgs, 0, 0);
  if start < 0 then
  begin
    start := JSUTF16Length(s) + start;
    if start < 0 then start := 0;
  end;
  if start > JSUTF16Length(s) then start := JSUTF16Length(s);

  count := IntArg(AArgs, 1, JSUTF16Length(s) - start);
  if count < 0 then count := 0;
  if start + count > JSUTF16Length(s) then count := JSUTF16Length(s) - start;

  Result := JSMakeString(JSUTF16Slice(s, start, count));
end;

function TFloriaJSStringHelper.ToUpperCase(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeString(UpperCase(ThisString(AThis)));
end;

function TFloriaJSStringHelper.ToLowerCase(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeString(LowerCase(ThisString(AThis)));
end;

function TFloriaJSStringHelper.Trim(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeString(SysUtils.Trim(ThisString(AThis)));
end;

function TFloriaJSStringHelper.TrimStart(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeString(TrimLeft(ThisString(AThis)));
end;

function TFloriaJSStringHelper.TrimEnd(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeString(TrimRight(ThisString(AThis)));
end;

function TFloriaJSStringHelper.Split(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, separator: string;
  res: TFloriaJSArray;
  limit, i, startPos, p: Integer;
  re: TFloriaJSRegExp;
  pieces: TStringList;
begin
  s := ThisString(AThis);
  res := FHeap.NewArray();

  limit := -1;
  if (Length(AArgs) > 1) and not AArgs[1].IsUndefined() then
    limit := NumberToInt(AArgs[1]);

  if limit = 0 then
    Exit(JSMakeArray(res));

  if (Length(AArgs) = 0) or AArgs[0].IsUndefined() then
  begin
    res.Push(JSMakeString(s));
    Exit(JSMakeArray(res));
  end;

  if AArgs[0].IsObject() and (AArgs[0].ObjVal is TFloriaJSRegExp) then
  begin
    re := TFloriaJSRegExp(AArgs[0].ObjVal);
    pieces := TStringList.Create();
    try
      re.RegEngine.Split(s, pieces);
      for i := 0 to pieces.Count - 1 do
      begin
        if (limit >= 0) and (res.Length() >= limit) then Break;
        res.Push(JSMakeString(pieces[i]));
      end;
    finally
      pieces.Free();
    end;
    Exit(JSMakeArray(res));
  end;

  separator := AArgs[0].ToString();

  if separator = '' then
  begin
    for i := 1 to Length(s) do
    begin
      if (limit >= 0) and (res.Length() >= limit) then Break;
      res.Push(JSMakeString(Copy(s, i, 1)));
    end;
    Exit(JSMakeArray(res));
  end;

  startPos := 1;
  while (limit < 0) or (res.Length() < limit) do
  begin
    p := PosEx(separator, s, startPos);
    if p = 0 then Break;
    res.Push(JSMakeString(Copy(s, startPos, p - startPos)));
    startPos := p + Length(separator);
  end;

  if (limit < 0) or (res.Length() < limit) then
    res.Push(JSMakeString(Copy(s, startPos, Length(s) - startPos + 1)));

  Result := JSMakeArray(res);
end;

function TFloriaJSStringHelper.ReplacementText(const AWhole, AMatch: string;
  AIndex: Integer; const AReplacement: TFloriaJSValue): string;
var
  cbArgs: array[0..2] of TFloriaJSValue;
begin
  if AReplacement.IsFunction() then
  begin
    cbArgs[0] := JSMakeString(AMatch);
    cbArgs[1] := JSMakeNumber(AIndex);
    cbArgs[2] := JSMakeString(AWhole);
    Result := FHeap.InvokeFunction(AReplacement, cbArgs, JSMakeUndefined()).ToString();
  end
  else
    Result := AReplacement.ToString();
end;

function TFloriaJSStringHelper.Replace(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, searchStr, outText, m: string;
  replacement: TFloriaJSValue;
  p, mPos, mLen, lastPos: Integer;
  re: TFloriaJSRegExp;
begin
  s := ThisString(AThis);

  replacement := JSMakeUndefined();
  if Length(AArgs) > 1 then replacement := AArgs[1];

  if (Length(AArgs) > 0) and AArgs[0].IsObject() and (AArgs[0].ObjVal is TFloriaJSRegExp) then
  begin
    re := TFloriaJSRegExp(AArgs[0].ObjVal);
    try
      if not re.RegEngine.Exec(s) then
        Exit(JSMakeString(s));

      if not re.Global then
      begin
        mPos := re.RegEngine.MatchPos[0];
        mLen := re.RegEngine.MatchLen[0];
        m := re.RegEngine.Match[0];
        outText := Copy(s, 1, mPos - 1) +
          ReplacementText(s, m, mPos - 1, replacement) +
          Copy(s, mPos + mLen, Length(s) - mPos - mLen + 1);
        Exit(JSMakeString(outText));
      end;

      outText := '';
      lastPos := 1;
      repeat
        mPos := re.RegEngine.MatchPos[0];
        mLen := re.RegEngine.MatchLen[0];
        m := re.RegEngine.Match[0];
        outText := outText + Copy(s, lastPos, mPos - lastPos) +
          ReplacementText(s, m, mPos - 1, replacement);
        lastPos := mPos + mLen;
      until not re.RegEngine.ExecNext();
      outText := outText + Copy(s, lastPos, Length(s) - lastPos + 1);
      Exit(JSMakeString(outText));
    except
      Exit(JSMakeString(s));
    end;
  end;

  searchStr := StringArg(AArgs, 0, 'undefined');

  if searchStr = '' then
    Exit(JSMakeString(ReplacementText(s, '', 0, replacement) + s));

  p := PosEx(searchStr, s, 1);
  if p = 0 then
    Exit(JSMakeString(s));

  outText := Copy(s, 1, p - 1) +
    ReplacementText(s, searchStr, p - 1, replacement) +
    Copy(s, p + Length(searchStr), Length(s) - p - Length(searchStr) + 1);
  Result := JSMakeString(outText);
end;

function TFloriaJSStringHelper.ReplaceAll(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, searchStr, outText: string;
  replacement: TFloriaJSValue;
  p, startPos, i: Integer;
begin
  s := ThisString(AThis);
  searchStr := StringArg(AArgs, 0, 'undefined');

  replacement := JSMakeUndefined();
  if Length(AArgs) > 1 then replacement := AArgs[1];

  if searchStr = '' then
  begin
    outText := ReplacementText(s, '', 0, replacement);
    for i := 1 to Length(s) do
      outText := outText + Copy(s, i, 1) + ReplacementText(s, '', i, replacement);
    Exit(JSMakeString(outText));
  end;

  outText := '';
  startPos := 1;
  while True do
  begin
    p := PosEx(searchStr, s, startPos);
    if p = 0 then Break;
    outText := outText + Copy(s, startPos, p - startPos) +
      ReplacementText(s, searchStr, p - 1, replacement);
    startPos := p + Length(searchStr);
  end;
  outText := outText + Copy(s, startPos, Length(s) - startPos + 1);

  Result := JSMakeString(outText);
end;

function TFloriaJSStringHelper.Match(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, pat: string;
  re: TFloriaJSRegExp;
  resArr: TFloriaJSArray;
  v: TFloriaJSValue;
  prevIndex: Integer;
begin
  s := ThisString(AThis);
  if (Length(AArgs) > 0) and AArgs[0].IsObject() and (AArgs[0].ObjVal is TFloriaJSRegExp) then
    re := TFloriaJSRegExp(AArgs[0].ObjVal)
  else
  begin
    if Length(AArgs) > 0 then
      pat := AArgs[0].ToString()
    else
      pat := '';
    re := FloriaJSNewRegExp(pat, '', FHeap);
  end;

  if not re.Global then
    Exit(re.Exec(s, FHeap));

  // Global regex: collect all match[0]
  resArr := FHeap.NewArray();
  re.LastIndex := 0;
  while True do
  begin
    prevIndex := re.LastIndex;
    v := re.Exec(s, FHeap);
    if v.IsNull() then Break;
    resArr.Push(v.ObjVal.GetProperty('0'));
    if re.LastIndex <= prevIndex then
      re.LastIndex := prevIndex + 1;
    if re.LastIndex > Length(s) then Break;
  end;
  re.LastIndex := 0;

  if resArr.Length() = 0 then
    Result := JSMakeNull()
  else
    Result := JSMakeArray(resArr);
end;

function TFloriaJSStringHelper.MatchAll(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  re: TFloriaJSRegExp;
  matcher: TFloriaJSValue;
  source: TFloriaJSArray;
  heap: TFloriaJSHeap;
begin
  s := ThisString(AThis);
  heap := FHeap;

  { The @@matchAll protocol takes precedence when the argument defines it. }
  if (Length(AArgs) > 0) and AArgs[0].IsObject() then
  begin
    matcher := AArgs[0].AsObject().GetWellKnownProperty('Symbol.matchAll');
    if matcher.IsFunction() then
      Exit(heap.InvokeFunction(matcher, [JSMakeString(s)], AArgs[0]));
  end;

  if (Length(AArgs) > 0) and AArgs[0].IsObject() and
     (AArgs[0].ObjVal is TFloriaJSRegExp) then
  begin
    re := TFloriaJSRegExp(AArgs[0].ObjVal);
    if not re.Global then
      raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('TypeError',
        'String.prototype.matchAll called with a non-global RegExp argument')));
    { Iterate a copy so the original regexp's lastIndex is not mutated. }
    re := FloriaJSNewRegExp(re.Pattern, re.Flags, heap);
    re.LastIndex := TFloriaJSRegExp(AArgs[0].ObjVal).LastIndex;
  end
  else if (Length(AArgs) > 0) and (not AArgs[0].IsUndefined()) and
          (not AArgs[0].IsNull()) then
    re := FloriaJSNewRegExp(JSToString(AArgs[0]), 'g', heap)
  else
    re := FloriaJSNewRegExp('', 'g', heap);

  source := heap.NewArray();
  source.Push(JSMakeObject(re));
  source.Push(JSMakeString(s));
  Result := JSMakeObject(heap.Track(
    TFloriaJSIterator.Create(heap, fikRegExpMatches, JSMakeArray(source))));
end;

function TFloriaJSStringHelper.RegExpMatchAll(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  re, clone: TFloriaJSRegExp;
  source: TFloriaJSArray;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSRegExp) then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError',
      'RegExp.prototype[Symbol.matchAll] called on an incompatible receiver')));
  re := TFloriaJSRegExp(AThis.ObjVal);
  s := '';
  if Length(AArgs) > 0 then
    s := JSToString(AArgs[0]);
  if not re.Global then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError',
      'RegExp.prototype[Symbol.matchAll] requires a global RegExp')));
  clone := FloriaJSNewRegExp(re.Pattern, re.Flags, FHeap);
  clone.LastIndex := re.LastIndex;
  source := FHeap.NewArray();
  source.Push(JSMakeObject(clone));
  source.Push(JSMakeString(s));
  Result := JSMakeObject(FHeap.Track(
    TFloriaJSIterator.Create(FHeap, fikRegExpMatches, JSMakeArray(source))));
end;

function TFloriaJSStringHelper.Search(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, pat: string;
  re: TFloriaJSRegExp;
begin
  s := ThisString(AThis);
  if (Length(AArgs) > 0) and AArgs[0].IsObject() and (AArgs[0].ObjVal is TFloriaJSRegExp) then
    re := TFloriaJSRegExp(AArgs[0].ObjVal)
  else
  begin
    if Length(AArgs) > 0 then
      pat := AArgs[0].ToString()
    else
      pat := '';
    re := FloriaJSNewRegExp(pat, '', FHeap);
  end;

  try
    if re.RegEngine.Exec(s) then
      Result := JSMakeNumber(re.RegEngine.MatchPos[0] - 1)
    else
      Result := JSMakeNumber(-1);
  except
    Result := JSMakeNumber(-1);
  end;
end;

function TFloriaJSStringHelper.ArgString(const AValue: TFloriaJSValue): string;
begin
  { String.prototype.concat performs ToString on each argument, including
    Symbol.toPrimitive and a user-supplied `toString`. }
  Result := JSToString(AValue);
end;

function TFloriaJSStringHelper.Concat(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  i: Integer;
begin
  s := ThisString(AThis);
  for i := 0 to High(AArgs) do
    s := s + ArgString(AArgs[i]);
  Result := JSMakeString(s);
end;

function TFloriaJSStringHelper.RepeatString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s: string;
  count: Integer;
begin
  s := ThisString(AThis);
  count := IntArg(AArgs, 0, 0);
  if (count <= 0) or (s = '') then
    Exit(JSMakeString(''));
  Result := JSMakeString(DupeString(s, count));
end;

function TFloriaJSStringHelper.PadStart(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, padding, fill: string;
  target, need: Integer;
begin
  s := ThisString(AThis);
  target := IntArg(AArgs, 0, 0);
  if target <= JSUTF16Length(s) then
    Exit(JSMakeString(s));

  padding := StringArg(AArgs, 1, ' ');
  if padding = '' then
    Exit(JSMakeString(s));

  need := target - JSUTF16Length(s);
  fill := DupeString(padding, (need div JSUTF16Length(padding)) + 1);
  Result := JSMakeString(JSUTF16Slice(fill, 0, need) + s);
end;

function TFloriaJSStringHelper.PadEnd(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  s, padding, fill: string;
  target, need: Integer;
begin
  s := ThisString(AThis);
  target := IntArg(AArgs, 0, 0);
  if target <= JSUTF16Length(s) then
    Exit(JSMakeString(s));

  padding := StringArg(AArgs, 1, ' ');
  if padding = '' then
    Exit(JSMakeString(s));

  need := target - JSUTF16Length(s);
  fill := DupeString(padding, (need div JSUTF16Length(padding)) + 1);
  Result := JSMakeString(s + JSUTF16Slice(fill, 0, need));
end;

function TFloriaJSStringHelper.ToStringValue(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  errorHeap: TFloriaJSHeap;
begin
  if AThis.IsString() then
    Exit(JSMakeString(AThis.StrVal));
  if AThis.IsObject() and (AThis.ObjVal is TFloriaJSStringObject) then
    Exit(JSMakeString(TFloriaJSStringObject(AThis.ObjVal).Value));

  { thisStringValue throws for anything other than a String primitive or a
    String object. }
  errorHeap := JSActiveRealmHeap();
  if errorHeap = nil then
    errorHeap := FHeap;
  raise EFloriaJSThrow.Create(JSMakeObject(errorHeap.NewError('TypeError',
    'String.prototype.toString requires that this be a String')));
end;

function TFloriaJSStringHelper.Normalize(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  form: string;
  unicodeForm: TFloriaJSUnicodeForm;
  errorHeap: TFloriaJSHeap;
begin
  if AThis.IsNull() or AThis.IsUndefined() or AThis.IsSymbol() then
  begin
    errorHeap := JSActiveRealmHeap();
    if errorHeap = nil then errorHeap := FHeap;
    raise EFloriaJSThrow.Create(JSMakeObject(errorHeap.NewError('TypeError',
      'String.prototype.normalize requires that this be coercible to a string')));
  end;
  if (Length(AArgs) = 0) or AArgs[0].IsUndefined() then
    form := 'NFC'
  else
  begin
    if AArgs[0].IsSymbol() then
    begin
      errorHeap := JSActiveRealmHeap();
      if errorHeap = nil then errorHeap := FHeap;
      raise EFloriaJSThrow.Create(JSMakeObject(errorHeap.NewError('TypeError',
        'Cannot convert a Symbol value to a string')));
    end;
    form := JSToString(AArgs[0]);
  end;

  if form = 'NFC' then
    unicodeForm := ufNFC
  else if form = 'NFD' then
    unicodeForm := ufNFD
  else if form = 'NFKC' then
    unicodeForm := ufNFKC
  else if form = 'NFKD' then
    unicodeForm := ufNFKD
  else
  begin
    errorHeap := JSActiveRealmHeap();
    if errorHeap = nil then
      errorHeap := FHeap;
    raise EFloriaJSThrow.Create(JSMakeObject(errorHeap.NewError('RangeError',
      'The normalization form should be one of NFC, NFD, NFKC, NFKD')));
  end;

  Result := JSMakeString(FloriaJSUnicodeNormalize(JSToString(AThis), unicodeForm));
end;

function TFloriaJSStringHelper.LocaleCompare(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  other: string;
  errorHeap: TFloriaJSHeap;
begin
  if AThis.IsNull() or AThis.IsUndefined() or AThis.IsSymbol() then
  begin
    errorHeap := JSActiveRealmHeap();
    if errorHeap = nil then errorHeap := FHeap;
    raise EFloriaJSThrow.Create(JSMakeObject(errorHeap.NewError('TypeError',
      'String.prototype.localeCompare requires that this be coercible to a string')));
  end;
  if (Length(AArgs) = 0) or AArgs[0].IsUndefined() then
    other := 'undefined'
  else
    other := JSToString(AArgs[0]);
  Result := JSMakeNumber(FloriaJSUnicodeCompare(JSToString(AThis), other));
end;

procedure RegisterMethod(AHeap: TFloriaJSHeap; AProto: TFloriaJSObject;
  const AName: string; AMethod: TFloriaJSNativeMethod; ALength: Integer = -1);
var
  fn: TFloriaJSFunction;
begin
  fn := AHeap.NewNativeMethod(AName, AMethod);
  { A prototype method is not a constructor, has no `prototype` property, is a
    non-enumerable own property, and has a fixed `length`. }
  fn.NotConstructable := True;
  fn.SuppressPrototype := True;
  fn.LengthOverride := ALength;
  AProto.DefineDataProperty(AName, JSMakeFunction(fn), True, False, True);
end;

procedure FloriaJSRegisterRegExpMatchAll(AHeap: TFloriaJSHeap; AProto: TFloriaJSObject);
var
  helper: TFloriaJSStringHelper;
  sym: TFloriaJSValue;
  fn: TFloriaJSFunction;
begin
  if (AHeap = nil) or (AProto = nil) then Exit;
  sym := JSWellKnownSymbol('Symbol.matchAll');
  if sym.IsUndefined() then Exit;
  helper := TFloriaJSStringHelper.Create(AHeap);
  AHeap.OwnHelper(helper);
  fn := AHeap.NewNativeMethod('[Symbol.matchAll]', @helper.RegExpMatchAll);
  fn.NotConstructable := True;
  fn.SuppressPrototype := True;
  AProto.DefineDataProperty(JSPropertyKeyName(sym), JSMakeFunction(fn), True, False, True);
end;

procedure FloriaJSRegisterString(AHeap: TFloriaJSHeap);
var
  helper: TFloriaJSStringHelper;
  proto: TFloriaJSObject;
  methodFn: TFloriaJSFunction;
begin
  if AHeap = nil then Exit;

  helper := TFloriaJSStringHelper.Create(AHeap);
  AHeap.OwnHelper(helper);

  proto := AHeap.GetStringPrototype();
  RegisterMethod(AHeap, proto, 'at', @helper.At, 1);
  RegisterMethod(AHeap, proto, 'charAt', @helper.CharAt);
  RegisterMethod(AHeap, proto, 'charCodeAt', @helper.CharCodeAt);
  RegisterMethod(AHeap, proto, 'indexOf', @helper.IndexOf);
  RegisterMethod(AHeap, proto, 'lastIndexOf', @helper.LastIndexOf);
  RegisterMethod(AHeap, proto, 'includes', @helper.Includes);
  RegisterMethod(AHeap, proto, 'startsWith', @helper.StartsWith);
  RegisterMethod(AHeap, proto, 'endsWith', @helper.EndsWith);
  RegisterMethod(AHeap, proto, 'slice', @helper.Slice);
  RegisterMethod(AHeap, proto, 'substring', @helper.Substring);
  RegisterMethod(AHeap, proto, 'substr', @helper.Substr);
  RegisterMethod(AHeap, proto, 'toUpperCase', @helper.ToUpperCase);
  RegisterMethod(AHeap, proto, 'toLowerCase', @helper.ToLowerCase);
  RegisterMethod(AHeap, proto, 'trim', @helper.Trim);
  RegisterMethod(AHeap, proto, 'trimStart', @helper.TrimStart);
  RegisterMethod(AHeap, proto, 'trimEnd', @helper.TrimEnd);
  RegisterMethod(AHeap, proto, 'split', @helper.Split);
  RegisterMethod(AHeap, proto, 'replace', @helper.Replace);
  RegisterMethod(AHeap, proto, 'replaceAll', @helper.ReplaceAll);
  RegisterMethod(AHeap, proto, 'match', @helper.Match);
  RegisterMethod(AHeap, proto, 'matchAll', @helper.MatchAll, 1);
  RegisterMethod(AHeap, proto, 'search', @helper.Search);
  RegisterMethod(AHeap, proto, 'concat', @helper.Concat);
  RegisterMethod(AHeap, proto, 'repeat', @helper.RepeatString);
  RegisterMethod(AHeap, proto, 'padStart', @helper.PadStart);
  RegisterMethod(AHeap, proto, 'padEnd', @helper.PadEnd);
  methodFn := AHeap.NewNativeMethod('normalize', @helper.Normalize);
  methodFn.NotConstructable := True;
  methodFn.SuppressPrototype := True;
  proto.DefineDataProperty('normalize', JSMakeFunction(methodFn), True, False, True);
  methodFn := AHeap.NewNativeMethod('localeCompare', @helper.LocaleCompare);
  methodFn.NotConstructable := True;
  methodFn.SuppressPrototype := True;
  methodFn.LengthOverride := 1;
  proto.DefineDataProperty('localeCompare', JSMakeFunction(methodFn), True, False, True);
  RegisterMethod(AHeap, proto, 'toString', @helper.ToStringValue);
  RegisterMethod(AHeap, proto, 'valueOf', @helper.ToStringValue);
end;

end.
