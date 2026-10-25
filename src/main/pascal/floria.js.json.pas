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
  Classes, SysUtils, Math, floria.js.types, floria.js.value, floria.js.env,
  floria.js.number;

type
  { Host Object for JSON Global }
  TFloriaJSJSONObject = class(TFloriaJSObject)
  private
    FFormatSettings: TFormatSettings;
    { JSON serialisation context: the replacer (function or key list) applied to
      every value. ECMAScript passes the property key to `toJSON` and to the
      replacer, so the key travels with the recursive call. }
    FReplacerFn: TFloriaJSValue;
    FReplacerKeys: TStringList;
    FHasReplacerKeys: Boolean;
    FReviverFn: TFloriaJSValue;

    function EscapeString(const S: string): string;
    { Walks the parsed tree bottom-up, calling the reviver with (key, value) on
      every member, as ECMAScript specifies. }
    function ApplyReviver(const AHolder: TFloriaJSObject; const AKey: string): TFloriaJSValue;
    function ApplyToJSON(const AVal: TFloriaJSValue; const AKey: string): TFloriaJSValue;
    function ApplyReplacer(const AVal: TFloriaJSValue; const AKey: string): TFloriaJSValue;
    function PrepareValue(const AVal: TFloriaJSValue; const AKey: string): TFloriaJSValue;
    function Serialize(const AVal: TFloriaJSValue; AVisited: TFPList; const AIndent: string; const AGap: string; const AKey: string): string;
  public
    constructor Create(AHeap: TFloriaJSHeap);
    destructor Destroy(); override;
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
  inherited Create(AHeap.GetObjectPrototype());
  Heap := AHeap;
  FReplacerKeys := TStringList.Create();
  FReplacerKeys.CaseSensitive := True;
  FReplacerKeys.Sorted := False;
  FReplacerFn := JSMakeUndefined();
  FHasReplacerKeys := False;
  FReviverFn := JSMakeUndefined();
  FFormatSettings := DefaultFormatSettings;
  FFormatSettings.DecimalSeparator := '.';
end;

destructor TFloriaJSJSONObject.Destroy();
begin
  FreeAndNil(FReplacerKeys);
  inherited Destroy();
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


{ Calls `value.toJSON(key)` when the value has one. ECMAScript looks the method
  up on the value itself (including inherited), and passes the property key. }

{ The reviver walk. Each property is revived depth-first, then the reviver is
  called on the holder/key pair; returning undefined deletes the property. }
function TFloriaJSJSONObject.ApplyReviver(const AHolder: TFloriaJSObject; const AKey: string): TFloriaJSValue;
var
  value, revived: TFloriaJSValue;
  arr: TFloriaJSArray;
  i: Integer;
  keys: TStringList;
begin
  value := AHolder.GetProperty(AKey);

  if value.IsArray() then
  begin
    arr := value.AsArray();
    for i := 0 to arr.Length() - 1 do
    begin
      revived := ApplyReviver(arr, IntToStr(i));
      if revived.IsUndefined() then
        arr.DeleteElement(i)
      else
        arr.SetElement(i, revived);
    end;
  end
  else if value.IsObject() and not value.IsFunction() then
  begin
    keys := TStringList.Create();
    try
      value.AsObject().GetKeys(keys);
      for i := 0 to keys.Count - 1 do
      begin
        revived := ApplyReviver(value.AsObject(), keys[i]);
        if revived.IsUndefined() then
          value.AsObject().DeleteProperty(keys[i])
        else
          value.AsObject().SetProperty(keys[i], revived);
      end;
    finally
      keys.Free();
    end;
  end;

  Result := Heap.InvokeFunction(FReviverFn, [JSMakeString(AKey), value],
    JSMakeObject(AHolder));
end;

function TFloriaJSJSONObject.ApplyToJSON(const AVal: TFloriaJSValue; const AKey: string): TFloriaJSValue;
var
  toJSON, holder: TFloriaJSValue;
begin
  if not AVal.IsObject() then
    Exit(AVal);
  if AVal.AsObject() = nil then
    Exit(AVal);

  toJSON := AVal.AsObject().GetProperty('toJSON');
  if not toJSON.IsFunction() then
    Exit(AVal);

  holder := JSMakeString(AKey);
  Result := Heap.InvokeFunction(toJSON, [holder], AVal);
end;

{ Applies the replacer, when one was supplied. A function replacer is called
  with `(key, value)` and its result is serialised; a key-array replacer filters
  object properties elsewhere. }
function TFloriaJSJSONObject.ApplyReplacer(const AVal: TFloriaJSValue; const AKey: string): TFloriaJSValue;
begin
  if not FReplacerFn.IsFunction() then
    Exit(AVal);
  Result := Heap.InvokeFunction(FReplacerFn, [JSMakeString(AKey), AVal], JSMakeUndefined());
end;

{ The per-value pipeline ECMAScript applies before serialising: `toJSON`
  first, then the replacer function. }
function TFloriaJSJSONObject.PrepareValue(const AVal: TFloriaJSValue; const AKey: string): TFloriaJSValue;
begin
  Result := ApplyToJSON(AVal, AKey);
  Result := ApplyReplacer(Result, AKey);
end;

function TFloriaJSJSONObject.Serialize(const AVal: TFloriaJSValue; AVisited: TFPList; const AIndent: string; const AGap: string; const AKey: string): string;
var
  sb: TStringBuilder;
  arr: TFloriaJSArray;
  obj: TFloriaJSObject;
  i, count: Integer;
  valStr, propKey, nextIndent: string;
  hasWritten: Boolean;
  value: TFloriaJSValue;
  propVal: TFloriaJSValue;
begin
  { toJSON and the replacer run before any type dispatch, so they can turn any
    value into anything else, including a primitive. }
  value := PrepareValue(AVal, AKey);

  if value.IsNull() then
    Exit('null');

  if value.IsBoolean() then
  begin
    if value.BoolVal then
      Exit('true')
    else
      Exit('false');
  end;

  if value.IsNumber() then
  begin
    if IsNaN(value.NumVal) or IsInfinite(value.NumVal) then
      Exit('null');
    { JSON has no Infinity/NaN, and ECMAScript serialises numbers with the
      same shortest round-tripping form as String(). }
    Exit(JSNumberToStr(value.NumVal));
  end;

  if value.IsString() then
    Exit(EscapeString(value.StrVal));

  if value.IsArray() then
  begin
    arr := value.AsArray();
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
            valStr := Serialize(arr.GetElement(i), AVisited, nextIndent, AGap,
              IntToStr(i));
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

  if value.IsObject() and not value.IsFunction() then
  begin
    obj := value.AsObject();
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

          { A key-array replacer restricts which keys are emitted. }
          if FHasReplacerKeys and (FReplacerKeys.IndexOf(propKey) < 0) then
            Continue;

          { Read through the property so getters run, as ECMAScript requires. }
          propVal := obj.GetProperty(propKey);
          if propVal.IsUndefined() or propVal.IsFunction() then
            Continue;

          valStr := Serialize(propVal, AVisited, nextIndent, AGap, propKey);
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

  { The second argument is either a function replacer or an array of keys. }
  FReplacerFn := JSMakeUndefined();
  FHasReplacerKeys := False;
  if (Length(AArgs) >= 2) and not AArgs[1].IsUndefined() and not AArgs[1].IsNull() then
  begin
    if AArgs[1].IsFunction() then
      FReplacerFn := AArgs[1]
    else if AArgs[1].IsArray() then
    begin
      FReplacerKeys.Clear();
      for i := 0 to AArgs[1].AsArray().Length() - 1 do
      begin
        spaceVal := AArgs[1].AsArray().GetElement(i);
        if spaceVal.IsString() or spaceVal.IsNumber() then
          FReplacerKeys.Add(spaceVal.ToString());
      end;
      FHasReplacerKeys := True;
    end;
  end;

  visited := TFPList.Create();
  try
    { The root value is serialised under the empty key, as ECMAScript does. }
    resStr := Serialize(AArgs[0], visited, '', gap, '');
    if resStr = '' then
      Result := JSMakeUndefined()
    else
      Result := JSMakeString(resStr);
  finally
    visited.Free();
    FReplacerFn := JSMakeUndefined();
    FHasReplacerKeys := False;
    FReplacerKeys.Clear();
  end;
end;

function TFloriaJSJSONObject.Parse(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  parser: TJSONParser;
  val: TFloriaJSValue;
  holder: TFloriaJSObject;
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

  { With a reviver, the tree is walked bottom-up from a synthetic root holder
    whose single property is the parsed value. }
  FReviverFn := JSMakeUndefined();
  if (Length(AArgs) >= 2) and AArgs[1].IsFunction() then
  begin
    FReviverFn := AArgs[1];
    try
      holder := Heap.NewObject(Heap.GetObjectPrototype());
      holder.SetProperty('', val);
      Result := ApplyReviver(holder, '');
    finally
      FReviverFn := JSMakeUndefined();
    end;
  end
  else
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
