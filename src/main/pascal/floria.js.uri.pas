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
  Classes, SysUtils, floria.js.types, floria.js.value, floria.js.env;

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

function JSEncodeURIComponent(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  src, res: string;
  i: Integer;
  c: Char;
  b: Byte;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeString('undefined'));

  src := AArgs[0].ToString();
  res := '';
  for i := 1 to Length(src) do
  begin
    c := src[i];
    case c of
      'A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '!', '~', '*', '''', '(', ')':
        res := res + c;
    else
      b := Ord(c);
      res := res + '%' + HexStr(b, 2);
    end;
  end;
  Result := JSMakeString(res);
end;

function JSDecodeURIComponent(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  src, res: string;
  i, h1, h2: Integer;
  b: Byte;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeString('undefined'));

  src := AArgs[0].ToString();
  res := '';
  i := 1;
  while i <= Length(src) do
  begin
    if src[i] = '%' then
    begin
      if i + 2 > Length(src) then
        raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('URIError', 'URI malformed')));

      h1 := HexVal(src[i + 1]);
      h2 := HexVal(src[i + 2]);
      if (h1 < 0) or (h2 < 0) then
        raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('URIError', 'URI malformed')));

      b := (h1 shl 4) or h2;
      res := res + Chr(b);
      Inc(i, 3);
    end
    else
    begin
      res := res + src[i];
      Inc(i);
    end;
  end;
  Result := JSMakeString(res);
end;

function JSEncodeURI(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  src, res: string;
  i: Integer;
  c: Char;
  b: Byte;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeString('undefined'));

  src := AArgs[0].ToString();
  res := '';
  for i := 1 to Length(src) do
  begin
    c := src[i];
    case c of
      // Unreserved + reserved characters
      'A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '!', '~', '*', '''', '(', ')',
      ';', ',', '/', '?', ':', '@', '&', '=', '+', '$', '#':
        res := res + c;
    else
      b := Ord(c);
      res := res + '%' + HexStr(b, 2);
    end;
  end;
  Result := JSMakeString(res);
end;

function JSDecodeURI(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  src, res: string;
  i, h1, h2: Integer;
  b: Byte;
  ch: Char;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeString('undefined'));

  src := AArgs[0].ToString();
  res := '';
  i := 1;
  while i <= Length(src) do
  begin
    if src[i] = '%' then
    begin
      if i + 2 > Length(src) then
        raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('URIError', 'URI malformed')));

      h1 := HexVal(src[i + 1]);
      h2 := HexVal(src[i + 2]);
      if (h1 < 0) or (h2 < 0) then
        raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('URIError', 'URI malformed')));

      b := (h1 shl 4) or h2;
      ch := Chr(b);
      // If reserved character in encodeURI, keep it escaped
      if ch in [';', ',', '/', '?', ':', '@', '&', '=', '+', '$', '#'] then
        res := res + '%' + src[i + 1] + src[i + 2]
      else
        res := res + ch;
      Inc(i, 3);
    end
    else
    begin
      res := res + src[i];
      Inc(i);
    end;
  end;
  Result := JSMakeString(res);
end;

procedure FloriaJSRegisterURI(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  uriErrCtor: TFloriaJSFunction;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;

  uriErrCtor := AHeap.NewNativeMethod('URIError', @AHeap.ErrorCtor);
  uriErrCtor.SetProperty('prototype', JSMakeObject(AHeap.GetErrorPrototype()));
  AEnv.Define('URIError', JSMakeFunction(uriErrCtor));

  AEnv.Define('encodeURIComponent', JSMakeFunction(AHeap.NewNativeFunction('encodeURIComponent', @JSEncodeURIComponent)));
  AEnv.Define('decodeURIComponent', JSMakeFunction(AHeap.NewNativeFunction('decodeURIComponent', @JSDecodeURIComponent)));
  AEnv.Define('encodeURI', JSMakeFunction(AHeap.NewNativeFunction('encodeURI', @JSEncodeURI)));
  AEnv.Define('decodeURI', JSMakeFunction(AHeap.NewNativeFunction('decodeURI', @JSDecodeURI)));
end;

end.
