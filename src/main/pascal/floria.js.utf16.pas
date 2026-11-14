{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — UTF-16 code-unit helpers                        }
{                                                                          }
{   The runtime stores strings as UTF-8. ECMAScript exposes UTF-16 code    }
{   units, so the JS-visible string operations convert at this boundary.   }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                          }
{   SPDX-License-Identifier: MPL-2.0                                        }
{                                                                          }
{ ************************************************************************** }

unit floria.js.utf16;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

function JSUTF16Length(const AText: string): Integer;
function JSUTF16CharAt(const AText: string; AIndex: Integer): string;
function JSUTF16CharCodeAt(const AText: string; AIndex: Integer): Integer;
function JSUTF16Slice(const AText: string; AStart, ACount: Integer): string;
function JSUTF16FromCharCode(ACodeUnit: LongWord): string;
function JSUTF16FromCodePoint(ACodePoint: LongWord): string;
function JSUTF16IndexOf(const AText, ANeedle: string; AFrom: Integer): Integer;
function JSUTF16LastIndexOf(const AText, ANeedle: string; AFrom: Integer): Integer;
{ Returns the UTF-8 text of the code point beginning at UTF-16 index AIndex,
  and advances AIndex past it. Returns '' at the end. }
function JSUTF16NextCodePoint(const AText: string; var AIndex: Integer): string;

implementation

function JSUTF16Length(const AText: string): Integer;
begin
  Result := Length(UTF8Decode(AText));
end;

function JSUTF16CharAt(const AText: string; AIndex: Integer): string;
var
  text16: UnicodeString;
begin
  text16 := UTF8Decode(AText);
  if (AIndex < 0) or (AIndex >= Length(text16)) then
    Exit('');
  Result := UTF8Encode(text16[AIndex + 1]);
end;

function JSUTF16CharCodeAt(const AText: string; AIndex: Integer): Integer;
var
  text16: UnicodeString;
begin
  text16 := UTF8Decode(AText);
  if (AIndex < 0) or (AIndex >= Length(text16)) then
    Exit(-1);
  Result := Ord(text16[AIndex + 1]);
end;

function JSUTF16Slice(const AText: string; AStart, ACount: Integer): string;
var
  text16: UnicodeString;
begin
  text16 := UTF8Decode(AText);
  if AStart < 0 then
    AStart := 0;
  if AStart > Length(text16) then
    AStart := Length(text16);
  if ACount < 0 then
    ACount := 0;
  if AStart + ACount > Length(text16) then
    ACount := Length(text16) - AStart;
  if ACount = 0 then
    Exit('');
  Result := UTF8Encode(Copy(text16, AStart + 1, ACount));
end;

function JSUTF16FromCharCode(ACodeUnit: LongWord): string;
var
  text16: UnicodeString;
begin
  SetLength(text16, 1);
  text16[1] := WideChar(ACodeUnit and $FFFF);
  Result := UTF8Encode(text16);
end;

function JSUTF16FromCodePoint(ACodePoint: LongWord): string;
var
  text16: UnicodeString;
begin
  if ACodePoint < $10000 then
  begin
    SetLength(text16, 1);
    text16[1] := WideChar(ACodePoint);
  end
  else
  begin
    SetLength(text16, 2);
    text16[1] := WideChar($D800 or ((ACodePoint - $10000) shr 10));
    text16[2] := WideChar($DC00 or ((ACodePoint - $10000) and $3FF));
  end;
  Result := UTF8Encode(text16);
end;

function JSUTF16IndexOf(const AText, ANeedle: string; AFrom: Integer): Integer;
var
  text16, needle16: UnicodeString;
  i: Integer;
begin
  text16 := UTF8Decode(AText);
  needle16 := UTF8Decode(ANeedle);
  if AFrom < 0 then
    AFrom := 0;
  if AFrom > Length(text16) then
    Exit(-1);
  if Length(needle16) = 0 then
    Exit(AFrom);
  for i := AFrom to Length(text16) - Length(needle16) do
    if Copy(text16, i + 1, Length(needle16)) = needle16 then
      Exit(i);
  Result := -1;
end;

function JSUTF16LastIndexOf(const AText, ANeedle: string; AFrom: Integer): Integer;
var
  text16, needle16: UnicodeString;
  i: Integer;
begin
  text16 := UTF8Decode(AText);
  needle16 := UTF8Decode(ANeedle);
  if AFrom < 0 then
    AFrom := 0;
  if AFrom > Length(text16) then
    AFrom := Length(text16);
  if Length(needle16) = 0 then
    Exit(AFrom);
  if AFrom > Length(text16) - Length(needle16) then
    AFrom := Length(text16) - Length(needle16);
  for i := AFrom downto 0 do
    if Copy(text16, i + 1, Length(needle16)) = needle16 then
      Exit(i);
  Result := -1;
end;

function JSUTF16NextCodePoint(const AText: string; var AIndex: Integer): string;
var
  text16: UnicodeString;
  ch: WideChar;
  count: Integer;
begin
  text16 := UTF8Decode(AText);
  if (AIndex < 0) or (AIndex >= Length(text16)) then
  begin
    AIndex := Length(text16);
    Exit('');
  end;

  ch := text16[AIndex + 1];
  count := 1;
  if (ch >= #$D800) and (ch <= #$DBFF) and
     (AIndex + 1 < Length(text16)) then
  begin
    if (text16[AIndex + 2] >= #$DC00) and (text16[AIndex + 2] <= #$DFFF) then
      count := 2;
  end;
  Result := UTF8Encode(Copy(text16, AIndex + 1, count));
  Inc(AIndex, count);
end;

end.
