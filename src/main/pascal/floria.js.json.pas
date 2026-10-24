{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Built-in JSON                                   }
{                                                                          }
{   Implements standard JSON.parse and JSON.stringify according to         }
{   RFC 8259, supporting primitives, arrays, nested objects,              }
{   indentation, circularity detection, and syntax error diagnostics.      }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.json;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math, floria.js.types, floria.js.value, floria.js.env;

type
  { Host Object for JSON Global }
  TFloriaJSJSONObject = class(TFloriaJSObject)
  private
    FFormatSettings: TFormatSettings;
    function EscapeString(const S: string): string;
    function Serialize(const AVal: TFloriaJSValue; AVisited: TFPList; const AIndent: string; const AGap: string): string;
  public
    constructor Create(AHeap: TFloriaJSHeap);
    function Stringify(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function Parse(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
  end;

procedure FloriaJSRegisterJSON(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);

implementation

function CodePointToUtf8(ACode: Cardinal): string;
begin
  if ACode <= $7F then
    Result := Chr(ACode)
  else if ACode <= $7FF then
    Result := Chr($C0 or (ACode shr 6)) + Chr($80 or (ACode and $3F))
  else if ACode <= $FFFF then
    Result := Chr($E0 or (ACode shr 12)) + Chr($80 or ((ACode shr 6) and $3F)) + Chr($80 or (ACode and $3F))
  else
    Result := Chr($F0 or (ACode shr 18)) + Chr($80 or ((ACode shr 12) and $3F)) + Chr($80 or ((ACode shr 6) and $3F)) + Chr($80 or (ACode and $3F));
end;

{ JSON Parser Helper }

type
  TJSONParser = record
    Source: string;
    Pos: Integer;
    Len: Integer;
    Heap: TFloriaJSHeap;
    FormatSettings: TFormatSettings;

    procedure SkipWhitespace();
    function PeekChar(): Char;
    function NextChar(): Char;
    procedure Error(const AMessage: string);
    function ParseString(): string;
    function ParseNumber(): Double;
    function ParseValue(): TFloriaJSValue;
    function ParseArray(): TFloriaJSArray;
    function ParseObject(): TFloriaJSObject;
  end;

procedure TJSONParser.SkipWhitespace();
begin
  while (Pos <= Len) and (Source[Pos] in [#9, #10, #13, ' ']) do
    Inc(Pos);
end;

function TJSONParser.PeekChar(): Char;
begin
  if Pos <= Len then
    Result := Source[Pos]
  else
    Result := #0;
end;

function TJSONParser.NextChar(): Char;
begin
  if Pos <= Len then
  begin
    Result := Source[Pos];
    Inc(Pos);
  end
  else
    Result := #0;
end;

procedure TJSONParser.Error(const AMessage: string);
var
  errMsg: string;
begin
  errMsg := Format('JSON.parse: %s at position %d', [AMessage, Pos]);
  if Heap <> nil then
    raise EFloriaJSThrow.Create(JSMakeObject(Heap.NewError('SyntaxError', errMsg)))
  else
    raise Exception.Create(errMsg);
end;

function TJSONParser.ParseString(): string;
var
  sb: TStringBuilder;
  c, esc: Char;
  hexStr: string;
  codeVal: LongInt;
begin
  if NextChar() <> '"' then
    Error('Expected ''"'' at start of string');

  sb := TStringBuilder.Create();
  try
    while Pos <= Len do
    begin
      c := NextChar();
      if c = '"' then
        Exit(sb.ToString());

      if c = '\' then
      begin
        if Pos > Len then
          Error('Unterminated escape sequence');
        esc := NextChar();
        case esc of
          '"':  sb.Append('"');
          '\':  sb.Append('\');
          '/':  sb.Append('/');
          'b':  sb.Append(#8);
          'f':  sb.Append(#12);
          'n':  sb.Append(#10);
          'r':  sb.Append(#13);
          't':  sb.Append(#9);
          'u':
          begin
            if Pos + 3 > Len then
              Error('Incomplete unicode escape sequence');
            hexStr := Copy(Source, Pos, 4);
            Inc(Pos, 4);
            codeVal := StrToIntDef('$' + hexStr, -1);
            if codeVal < 0 then
              Error('Invalid unicode escape \u' + hexStr);
            sb.Append(CodePointToUtf8(Cardinal(codeVal)));
          end;
        else
          Error('Invalid escape character: \' + esc);
        end;
      end
      else if Ord(c) < 32 then
        Error('Unescaped control character in string')
      else
        sb.Append(c);
    end;

    Error('Unterminated string in JSON');
    Result := '';
  finally
    sb.Free();
  end;
end;

function TJSONParser.ParseNumber(): Double;
var
  startPos: Integer;
  numStr: string;
  val: Double;
begin
  startPos := Pos;
  if PeekChar() = '-' then
    NextChar();

  if PeekChar() = '0' then
    NextChar()
  else if (PeekChar() >= '1') and (PeekChar() <= '9') then
  begin
    while (PeekChar() >= '0') and (PeekChar() <= '9') do
      NextChar();
  end
  else
    Error('Expected digit in number');

  if PeekChar() = '.' then
  begin
    NextChar();
    if not ((PeekChar() >= '0') and (PeekChar() <= '9')) then
      Error('Expected digit after decimal point');
    while (PeekChar() >= '0') and (PeekChar() <= '9') do
      NextChar();
  end;

  if (PeekChar() = 'e') or (PeekChar() = 'E') then
  begin
    NextChar();
    if (PeekChar() = '+') or (PeekChar() = '-') then
      NextChar();
    if not ((PeekChar() >= '0') and (PeekChar() <= '9')) then
      Error('Expected digit in exponent');
    while (PeekChar() >= '0') and (PeekChar() <= '9') do
      NextChar();
  end;

  numStr := Copy(Source, startPos, Pos - startPos);
  if not TryStrToFloat(numStr, val, FormatSettings) then
    Error('Failed to parse number: ' + numStr);

  Result := val;
end;

function TJSONParser.ParseArray(): TFloriaJSArray;
var
  arr: TFloriaJSArray;
  elem: TFloriaJSValue;
begin
  NextChar(); // Consume '['
  SkipWhitespace();

  arr := Heap.NewArray();
  if PeekChar() = ']' then
  begin
    NextChar();
    Exit(arr);
  end;

  while True do
  begin
    elem := ParseValue();
    arr.Push(elem);
    SkipWhitespace();

    if PeekChar() = ',' then
    begin
      NextChar();
      SkipWhitespace();
      if PeekChar() = ']' then
        Error('Unexpected trailing comma in array');
    end
    else if PeekChar() = ']' then
    begin
      NextChar();
      Break;
    end
    else
      Error('Expected '','' or '']'' in array');
  end;

  Result := arr;
end;

function TJSONParser.ParseObject(): TFloriaJSObject;
var
  obj: TFloriaJSObject;
  key: string;
  val: TFloriaJSValue;
begin
  NextChar(); { Consume opening brace }
  SkipWhitespace();

  obj := Heap.NewObject();
  if PeekChar() = '}' then
  begin
    NextChar();
    Exit(obj);
  end;

  while True do
  begin
    if PeekChar() <> '"' then
      Error('Expected string key in object');

    key := ParseString();
    SkipWhitespace();

    if PeekChar() <> ':' then
      Error('Expected '':'' after object key');
    NextChar();
    SkipWhitespace();

    val := ParseValue();
    obj.SetProperty(key, val);
    SkipWhitespace();

    if PeekChar() = ',' then
    begin
      NextChar();
      SkipWhitespace();
      if PeekChar() = '}' then
        Error('Unexpected trailing comma in object');
    end
    else if PeekChar() = '}' then
    begin
      NextChar();
      Break;
    end
    else
      Error('Expected '','' or ''}'' in object');
  end;

  Result := obj;
end;

function TJSONParser.ParseValue(): TFloriaJSValue;
begin
  SkipWhitespace();
  if Pos > Len then
    Error('Unexpected end of JSON input');

  case Source[Pos] of
    '"': Exit(JSMakeString(ParseString()));
    '[': Exit(JSMakeArray(ParseArray()));
    '{': Exit(JSMakeObject(ParseObject()));
    't':
    begin
      if Copy(Source, Pos, 4) = 'true' then
      begin
        Inc(Pos, 4);
        Exit(JSMakeBoolean(True));
      end;
      Error('Unexpected token in JSON');
    end;
    'f':
    begin
      if Copy(Source, Pos, 5) = 'false' then
      begin
        Inc(Pos, 5);
        Exit(JSMakeBoolean(False));
      end;
      Error('Unexpected token in JSON');
    end;
    'n':
    begin
      if Copy(Source, Pos, 4) = 'null' then
      begin
        Inc(Pos, 4);
        Exit(JSMakeNull());
      end;
      Error('Unexpected token in JSON');
    end;
    '-', '0'..'9': Exit(JSMakeNumber(ParseNumber()));
  else
    Error('Unexpected token ''' + Source[Pos] + '''');
  end;

  Result := JSMakeUndefined();
end;

{ TFloriaJSJSONObject }

constructor TFloriaJSJSONObject.Create(AHeap: TFloriaJSHeap);
begin
  inherited Create(nil);
  Heap := AHeap;
  FFormatSettings := DefaultFormatSettings;
  FFormatSettings.DecimalSeparator := '.';
end;

function TFloriaJSJSONObject.EscapeString(const S: string): string;
var
  i: Integer;
  c: Char;
  sb: TStringBuilder;
begin
  sb := TStringBuilder.Create();
  try
    sb.Append('"');
    for i := 1 to Length(S) do
    begin
      c := S[i];
      case c of
        '"':  sb.Append('\"');
        '\':  sb.Append('\\');
        #8:   sb.Append('\b');
        #12:  sb.Append('\f');
        #10:  sb.Append('\n');
        #13:  sb.Append('\r');
        #9:   sb.Append('\t');
        #0..#7, #11, #14..#31:
          sb.Append(Format('\u%.4x', [Ord(c)]));
      else
        sb.Append(c);
      end;
    end;
    sb.Append('"');
    Result := sb.ToString();
  finally
    sb.Free();
  end;
end;

function TFloriaJSJSONObject.Serialize(const AVal: TFloriaJSValue; AVisited: TFPList; const AIndent: string; const AGap: string): string;
var
  sb: TStringBuilder;
  arr: TFloriaJSArray;
  obj: TFloriaJSObject;
  i, count: Integer;
  valStr, propKey, nextIndent: string;
  hasWritten: Boolean;
begin
  if AVal.IsNull() then
    Exit('null');

  if AVal.IsBoolean() then
  begin
    if AVal.BoolVal then
      Exit('true')
    else
      Exit('false');
  end;

  if AVal.IsNumber() then
  begin
    if IsNaN(AVal.NumVal) or IsInfinite(AVal.NumVal) then
      Exit('null');
    if (Frac(AVal.NumVal) = 0.0) and (Abs(AVal.NumVal) <= 9007199254740991.0) then
      Exit(IntToStr(Trunc(AVal.NumVal)))
    else
      Exit(FloatToStr(AVal.NumVal, FFormatSettings));
  end;

  if AVal.IsString() then
    Exit(EscapeString(AVal.StrVal));

  if AVal.IsArray() then
  begin
    arr := AVal.AsArray();
    if arr = nil then
      Exit('null');

    if AVisited.IndexOf(arr) >= 0 then
      raise EFloriaJSThrow.Create(JSMakeObject(Heap.NewError('TypeError', 'Converting circular structure to JSON')));
    AVisited.Add(arr);
    try
      count := arr.Length;
      if count = 0 then
        Exit('[]');

      sb := TStringBuilder.Create();
      try
        sb.Append('[');
        if AGap <> '' then
        begin
          sb.Append(#10);
          nextIndent := AIndent + AGap;
        end
        else
          nextIndent := '';

        for i := 0 to count - 1 do
        begin
          if i > 0 then
          begin
            sb.Append(',');
            if AGap <> '' then
              sb.Append(#10);
          end;

          if AGap <> '' then
            sb.Append(nextIndent);

          if arr.GetElement(i).IsUndefined() or arr.GetElement(i).IsFunction() then
            sb.Append('null')
          else
          begin
            valStr := Serialize(arr.GetElement(i), AVisited, nextIndent, AGap);
            if valStr = '' then
              sb.Append('null')
            else
              sb.Append(valStr);
          end;
        end;

        if AGap <> '' then
        begin
          sb.Append(#10);
          sb.Append(AIndent);
        end;
        sb.Append(']');
        Result := sb.ToString();
      finally
        sb.Free();
      end;
    finally
      AVisited.Remove(arr);
    end;
    Exit;
  end;

  if AVal.IsObject() and not AVal.IsFunction() then
  begin
    obj := AVal.AsObject();
    if obj = nil then
      Exit('null');

    if AVisited.IndexOf(obj) >= 0 then
      raise EFloriaJSThrow.Create(JSMakeObject(Heap.NewError('TypeError', 'Converting circular structure to JSON')));
    AVisited.Add(obj);
    try
      count := obj.GetPropertyCount();
      if count = 0 then
        Exit('{}');

      sb := TStringBuilder.Create();
      try
        sb.Append('{');
        if AGap <> '' then
        begin
          nextIndent := AIndent + AGap;
        end
        else
          nextIndent := '';

        hasWritten := False;
        for i := 0 to count - 1 do
        begin
          propKey := obj.GetPropertyKey(i);
          if obj.GetPropertyValue(i).IsUndefined() or obj.GetPropertyValue(i).IsFunction() then
            Continue;

          valStr := Serialize(obj.GetPropertyValue(i), AVisited, nextIndent, AGap);
          if valStr = '' then
            Continue;

          if hasWritten then
          begin
            sb.Append(',');
          end;

          if AGap <> '' then
          begin
            sb.Append(#10);
            sb.Append(nextIndent);
          end;

          sb.Append(EscapeString(propKey));
          sb.Append(':');
          if AGap <> '' then
            sb.Append(' ');
          sb.Append(valStr);

          hasWritten := True;
        end;

        if AGap <> '' then
        begin
          if hasWritten then
          begin
            sb.Append(#10);
            sb.Append(AIndent);
          end;
        end;
        sb.Append('}');
        Result := sb.ToString();
      finally
        sb.Free();
      end;
    finally
      AVisited.Remove(obj);
    end;
    Exit;
  end;

  Result := '';
end;

function TFloriaJSJSONObject.Stringify(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  visited: TFPList;
  gap: string;
  resStr: string;
  spaceVal: TFloriaJSValue;
  spaceCount, i: Integer;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeUndefined());

  { Top level function or undefined produces undefined in JavaScript }
  if AArgs[0].IsUndefined() or AArgs[0].IsFunction() then
    Exit(JSMakeUndefined());

  gap := '';
  if Length(AArgs) >= 3 then
  begin
    spaceVal := AArgs[2];
    if spaceVal.IsNumber() then
    begin
      spaceCount := Min(10, Max(0, Trunc(spaceVal.NumVal)));
      for i := 1 to spaceCount do
        gap := gap + ' ';
    end
    else if spaceVal.IsString() then
    begin
      gap := Copy(spaceVal.StrVal, 1, 10);
    end;
  end;

  visited := TFPList.Create();
  try
    resStr := Serialize(AArgs[0], visited, '', gap);
    if resStr = '' then
      Result := JSMakeUndefined()
    else
      Result := JSMakeString(resStr);
  finally
    visited.Free();
  end;
end;

function TFloriaJSJSONObject.Parse(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  parser: TJSONParser;
  val: TFloriaJSValue;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsString() then
  begin
    if Heap = nil then
      raise Exception.Create('JSON.parse: unexpected end of input')
    else
      raise EFloriaJSThrow.Create(JSMakeObject(Heap.NewError('SyntaxError', 'JSON.parse: unexpected end of input')));
  end;

  parser.Source := AArgs[0].StrVal;
  parser.Pos := 1;
  parser.Len := Length(parser.Source);
  parser.Heap := Heap;
  parser.FormatSettings := FFormatSettings;

  val := parser.ParseValue();
  parser.SkipWhitespace();
  if parser.Pos <= parser.Len then
    parser.Error('Unexpected non-whitespace token after JSON data');

  Result := val;
end;

procedure FloriaJSRegisterJSON(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  jsonObj: TFloriaJSJSONObject;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;

  jsonObj := TFloriaJSJSONObject.Create(AHeap);
  AHeap.Track(jsonObj);

  jsonObj.SetProperty('stringify', JSMakeFunction(AHeap.NewNativeMethod('stringify', @jsonObj.Stringify)));
  jsonObj.SetProperty('parse', JSMakeFunction(AHeap.NewNativeMethod('parse', @jsonObj.Parse)));
  AEnv.Define('JSON', JSMakeObject(jsonObj));
end;

end.
