{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — URI Encoding & Decoding                         }
{                                                                          }
{   Provides standard JavaScript encodeURIComponent, decodeURIComponent,   }
{   encodeURI, and decodeURI functions.                                    }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.uri;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, floria.js.types, floria.js.value, floria.js.env,
  floria.js.utf16;

procedure FloriaJSRegisterURI(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);

implementation

function HexVal(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

procedure RaiseURIError();
var
  heap: TFloriaJSHeap;
begin
  heap := JSActiveRealmHeap();
  if heap <> nil then
    raise EFloriaJSThrow.Create(JSMakeObject(heap.NewError('URIError', 'URI malformed')));
  raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('URIError', 'URI malformed')));
end;

{ The characters encodeURIComponent leaves unescaped. }
function IsUnreserved(C: Char): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '!', '~', '*',
    '''', '(', ')']);
end;

{ The extra characters encodeURI leaves unescaped. }
function IsReserved(C: Char): Boolean;
begin
  Result := C in [';', ',', '/', '?', ':', '@', '&', '=', '+', '$', '#'];
end;

procedure AppendPercentByte(var ARes: string; AB: Byte);
begin
  ARes := ARes + '%' + HexStr(AB, 2);
end;

{ Appends the UTF-8 encoding of ACP as %XX escapes. }
procedure AppendEncodedCodePoint(var ARes: string; ACP: LongWord);
var
  b: array[0..3] of Byte;
  n, i: Integer;
begin
  if ACP < $80 then
  begin
    b[0] := ACP;
    n := 1;
  end
  else if ACP < $800 then
  begin
    b[0] := $C0 or (ACP shr 6);
    b[1] := $80 or (ACP and $3F);
    n := 2;
  end
  else if ACP < $10000 then
  begin
    b[0] := $E0 or (ACP shr 12);
    b[1] := $80 or ((ACP shr 6) and $3F);
    b[2] := $80 or (ACP and $3F);
    n := 3;
  end
  else
  begin
    b[0] := $F0 or (ACP shr 18);
    b[1] := $80 or ((ACP shr 12) and $3F);
    b[2] := $80 or ((ACP shr 6) and $3F);
    b[3] := $80 or (ACP and $3F);
    n := 4;
  end;
  for i := 0 to n - 1 do
    AppendPercentByte(ARes, b[i]);
end;

{ Validates a complete UTF-8 byte sequence and returns its code point. }
function DecodeBytes(const ABytes: array of Byte; ACount: Integer;
  out ACP: LongWord): Boolean;
var
  i, need: Integer;
  b: Byte;
  minCP: LongWord;
begin
  Result := False;
  if ACount = 0 then
    Exit;
  b := ABytes[0];
  if b < $80 then
  begin
    ACP := b;
    Exit(ACount = 1);
  end
  else if (b and $E0) = $C0 then
  begin
    need := 1;
    ACP := b and $1F;
    minCP := $80;
  end
  else if (b and $F0) = $E0 then
  begin
    need := 2;
    ACP := b and $0F;
    minCP := $800;
  end
  else if (b and $F8) = $F0 then
  begin
    need := 3;
    ACP := b and $07;
    minCP := $10000;
  end
  else
    Exit(False);

  if ACount <> need + 1 then
    Exit(False);
  for i := 1 to need do
  begin
    b := ABytes[i];
    if (b and $C0) <> $80 then
      Exit(False);
    ACP := (ACP shl 6) or (b and $3F);
  end;
  { Reject overlong encodings, surrogate halves, and out-of-range values. }
  if ACP < minCP then
    Exit(False);
  if (ACP >= $D800) and (ACP <= $DFFF) then
    Exit(False);
  if ACP > $10FFFF then
    Exit(False);
  Result := True;
end;

{ Shared encoder. AEncodeURI selects the larger unescaped set. }
function EncodeURIValue(const AValue: TFloriaJSValue; AEncodeURI: Boolean): string;
var
  src: string;
  text16: UnicodeString;
  res: string;
  i: Integer;
  ch: WideChar;
  cp: LongWord;
  c: Char;
begin
  src := JSToString(AValue);
  text16 := UTF8Decode(src);
  res := '';
  i := 1;
  while i <= Length(text16) do
  begin
    ch := text16[i];
    if (ch >= #$D800) and (ch <= #$DBFF) then
    begin
      { A high surrogate must be followed by a low surrogate. }
      if (i < Length(text16)) and (text16[i + 1] >= #$DC00) and
         (text16[i + 1] <= #$DFFF) then
      begin
        cp := $10000 + ((Ord(ch) - $D800) shl 10) +
          (Ord(text16[i + 1]) - $DC00);
        Inc(i, 2);
      end
      else
        RaiseURIError();
    end
    else if (ch >= #$DC00) and (ch <= #$DFFF) then
      RaiseURIError()
    else
    begin
      cp := Ord(ch);
      Inc(i);
    end;

    if cp < $80 then
    begin
      c := Char(cp);
      if IsUnreserved(c) or (AEncodeURI and IsReserved(c)) then
        res := res + c
      else
        AppendPercentByte(res, cp);
    end
    else
      AppendEncodedCodePoint(res, cp);
  end;
  Result := res;
end;

{ Shared decoder. ADecodeURI keeps reserved characters escaped. }
function DecodeURIValue(const AValue: TFloriaJSValue; ADecodeURI: Boolean): string;
var
  src, res: string;
  i, k, n, h1, h2: Integer;
  b0: Byte;
  bytes: array[0..3] of Byte;
  cp: LongWord;
begin
  src := JSToString(AValue);
  res := '';
  i := 1;
  while i <= Length(src) do
  begin
    if src[i] = '%' then
    begin
      if i + 2 > Length(src) then
        RaiseURIError();
      h1 := HexVal(src[i + 1]);
      h2 := HexVal(src[i + 2]);
      if (h1 < 0) or (h2 < 0) then
        RaiseURIError();

      b0 := (h1 shl 4) or h2;
      bytes[0] := b0;
      if b0 < $80 then
        n := 1
      else if (b0 and $E0) = $C0 then
        n := 2
      else if (b0 and $F0) = $E0 then
        n := 3
      else if (b0 and $F8) = $F0 then
        n := 4
      else
        RaiseURIError();

      { Read the continuation bytes, each written as its own %XX escape. }
      for k := 1 to n - 1 do
      begin
        if (i + 3 * k + 2 > Length(src)) or (src[i + 3 * k] <> '%') then
          RaiseURIError();
        h1 := HexVal(src[i + 3 * k + 1]);
        h2 := HexVal(src[i + 3 * k + 2]);
        if (h1 < 0) or (h2 < 0) then
          RaiseURIError();
        bytes[k] := (h1 shl 4) or h2;
      end;

      if not DecodeBytes(bytes, n, cp) then
        RaiseURIError();

      if ADecodeURI and (cp < $80) and IsReserved(Char(cp)) then
        { decodeURI leaves reserved characters escaped, preserving the exact
          source spelling (`%3b` stays lowercase). }
        res := res + Copy(src, i, 3 * n)
      else
        res := res + JSUTF16FromCodePoint(cp);

      Inc(i, 3 * n);
    end
    else
    begin
      res := res + src[i];
      Inc(i);
    end;
  end;
  Result := res;
end;

function JSEncodeURIComponent(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeString('undefined'));
  Result := JSMakeString(EncodeURIValue(AArgs[0], False));
end;

function JSDecodeURIComponent(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeString('undefined'));
  Result := JSMakeString(DecodeURIValue(AArgs[0], False));
end;

function JSEncodeURI(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeString('undefined'));
  Result := JSMakeString(EncodeURIValue(AArgs[0], True));
end;

function JSDecodeURI(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeString('undefined'));
  Result := JSMakeString(DecodeURIValue(AArgs[0], True));
end;

procedure RegisterURIFunction(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap;
  const AName: string; AProc: TFloriaJSNativeProc);
var
  fn: TFloriaJSFunction;
begin
  fn := AHeap.NewNativeFunction(AName, AProc);
  fn.NotConstructable := True;
  fn.SuppressPrototype := True;
  fn.LengthOverride := 1;
  AEnv.DefineBuiltin(AName, JSMakeFunction(fn));
end;

procedure FloriaJSRegisterURI(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  uriErrCtor: TFloriaJSFunction;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;

  uriErrCtor := AHeap.NewNativeMethod('URIError', @AHeap.ErrorCtor);
  uriErrCtor.IntrinsicName := 'URIError';
  uriErrCtor.LengthOverride := 1;
  uriErrCtor.SetProperty('prototype', JSMakeObject(AHeap.GetURIErrorPrototype()));
  AHeap.GetURIErrorPrototype().SetProperty('constructor', JSMakeFunction(uriErrCtor));
  AEnv.DefineBuiltin('URIError', JSMakeFunction(uriErrCtor));

  RegisterURIFunction(AEnv, AHeap, 'encodeURIComponent', @JSEncodeURIComponent);
  RegisterURIFunction(AEnv, AHeap, 'decodeURIComponent', @JSDecodeURIComponent);
  RegisterURIFunction(AEnv, AHeap, 'encodeURI', @JSEncodeURI);
  RegisterURIFunction(AEnv, AHeap, 'decodeURI', @JSDecodeURI);
end;

end.
