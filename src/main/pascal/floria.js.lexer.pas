{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Lexer & Tokenizer                               }
{                                                                          }
{   Provides lexical analysis, scanning, and tokenization for JavaScript   }
{   and FTML declarative scripting in pure Object Pascal.                  }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.lexer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { Token Kinds }
  TFloriaJSTokenKind = (
    { Special }
    tkEOF,
    tkError,
    tkComment,

    { Literals }
    tkIdentifier,
    tkNumber,
    tkString,
    tkRegExp,
    tkTemplateString,
    tkTemplateHead,
    tkTemplateMiddle,
    tkTemplateTail,

    { Keywords }
    tkLet,
    tkConst,
    tkVar,
    tkFunction,
    tkAsync,
    tkAwait,
    tkReturn,
    tkIf,
    tkElse,
    tkFor,
    tkWhile,
    tkDo,
    tkBreak,
    tkContinue,
    tkSwitch,
    tkCase,
    tkDefault,
    tkTry,
    tkCatch,
    tkFinally,
    tkThrow,
    tkNew,
    tkThis,
    tkTypeof,
    tkDelete,
    tkIn,
    tkOf,
    tkInstanceof,
    tkTrue,
    tkFalse,
    tkNull,
    tkUndefined,

    { Delimiters }
    tkLParen,         // (
    tkRParen,         // )
    tkLBrace,         // {
    tkRBrace,         // }
    tkLBracket,       // [
    tkRBracket,       // ]
    tkSemicolon,      // ;
    tkColon,          // :
    tkComma,          // ,
    tkDot,            // .
    tkEllipsis,       // ...
    tkQuestion,       // ?
    tkQuestionDot,    // ?.

    { Operators }
    tkAssign,         { = }
    tkPlus,           { + }
    tkPlusPlus,       { ++ }
    tkPlusAssign,     { += }
    tkMinus,          { - }
    tkMinusMinus,     { -- }
    tkMinusAssign,    { -= }
    tkMultiply,       { * }
    tkMultiplyAssign, { *= }
    tkPower,          { ** }
    tkPowerAssign,    { **= }
    tkNullishAssign,  { ??= }
    tkDivide,         { / }
    tkDivideAssign,   { /= }
    tkModulo,         { % }
    tkModuloAssign,   { %= }

    { Comparisons }
    tkEqual,          { == }
    tkStrictEqual,    { === }
    tkNotEqual,       { != }
    tkStrictNotEqual, { !== }
    tkLessThan,       { < }
    tkLessEqual,      { <= }
    tkGreaterThan,    { > }
    tkGreaterEqual,   { >= }
    tkNot,            { ! }

    { Logical }
    tkAnd,            { && }
    tkOr,             { || }
    tkNullish,        { ?? }

    { Bitwise }
    tkBitAnd,         { & }
    tkBitOr,          { | }
    tkBitXor,         { ^ }
    tkBitNot,         { ~ }
    tkShiftLeft,      { << }
    tkShiftRight,     { >> }
    tkShiftRightUnsigned, { >>> }

    { Arrow }
    tkArrow           { => }
  );

  { Token Record }
  TFloriaJSToken = record
    Kind: TFloriaJSTokenKind;
    Text: string;
    NumberValue: Double;
    Line: Integer;
    Column: Integer;
    StartPos: Integer;
    EndPos: Integer;
  end;

  { TFloriaJSLexer — High-performance single-pass UTF-8 JavaScript Lexer }
  TFloriaJSLexer = class
  private
    FSource: string;
    FPos: Integer;
    FLength: Integer;
    FLine: Integer;
    FColumn: Integer;
    FPeekedToken: TFloriaJSToken;
    FHasPeeked: Boolean;
    FLastTokenKind: TFloriaJSTokenKind;
    FBraceStack: array of Boolean;

    function  PeekChar(): Char;
    function  PeekNextChar(): Char;
    function  AdvanceChar(): Char;
    function  MatchChar(AExpected: Char): Boolean;
    procedure SkipWhitespace();
    function  IsRegexAllowed(): Boolean;
    function  ScanRegExp(AStartLine, AStartCol, AStartPos: Integer): TFloriaJSToken;
    function  ScanIdentifierOrKeyword(): TFloriaJSToken;
    function  ScanNumber(): TFloriaJSToken;
    function  ScanString(AQuote: Char): TFloriaJSToken;
    function  ScanTemplateString(AFromExpression: Boolean = False): TFloriaJSToken;
    function  ScanComment(): TFloriaJSToken;
    function  MakeToken(AKind: TFloriaJSTokenKind; const AText: string; AStartLine, AStartCol, AStartPos: Integer): TFloriaJSToken;
    function  MakeError(const AMessage: string; AStartLine, AStartCol, AStartPos: Integer): TFloriaJSToken;
  public
    constructor Create(const ASource: string);
    destructor Destroy(); override;

    function NextToken(): TFloriaJSToken;
    function PeekToken(): TFloriaJSToken;
    function IsAtEnd(): Boolean;
    procedure Reset();

    class function TokenKindToString(AKind: TFloriaJSTokenKind): string;
  end;

implementation

{ Keyword Table Lookup }

function CheckKeyword(const AText: string): TFloriaJSTokenKind;
begin
  case AText of
    'let':        Result := tkLet;
    'const':      Result := tkConst;
    'var':        Result := tkVar;
    'function':   Result := tkFunction;
    'async':      Result := tkAsync;
    'await':      Result := tkAwait;
    'return':     Result := tkReturn;
    'if':         Result := tkIf;
    'else':       Result := tkElse;
    'for':        Result := tkFor;
    'while':      Result := tkWhile;
    'do':         Result := tkDo;
    'break':      Result := tkBreak;
    'continue':   Result := tkContinue;
    'switch':     Result := tkSwitch;
    'case':       Result := tkCase;
    'default':    Result := tkDefault;
    'try':        Result := tkTry;
    'catch':      Result := tkCatch;
    'finally':    Result := tkFinally;
    'throw':      Result := tkThrow;
    'new':        Result := tkNew;
    'this':       Result := tkThis;
    'typeof':     Result := tkTypeof;
    'delete':     Result := tkDelete;
    'in':         Result := tkIn;
    'of':         Result := tkOf;
    'instanceof': Result := tkInstanceof;
    'true':       Result := tkTrue;
    'false':      Result := tkFalse;
    'null':       Result := tkNull;
    'undefined':  Result := tkUndefined;
  else
    Result := tkIdentifier;
  end;
end;

{ Helper character classifications }

function IsIdentStart(C: Char): Boolean; inline;
begin
  Result := (C in ['a'..'z', 'A'..'Z', '_', '$']);
end;

function IsIdentPart(C: Char): Boolean; inline;
begin
  Result := (C in ['a'..'z', 'A'..'Z', '0'..'9', '_', '$']);
end;

function IsDigit(C: Char): Boolean; inline;
begin
  Result := (C in ['0'..'9']);
end;

function IsHexDigit(C: Char): Boolean; inline;
begin
  Result := (C in ['0'..'9', 'a'..'f', 'A'..'F']);
end;

{ TFloriaJSLexer }

constructor TFloriaJSLexer.Create(const ASource: string);
begin
  inherited Create();
  FSource := ASource;
  FLength := Length(FSource);
  Reset();
end;

destructor TFloriaJSLexer.Destroy();
begin
  inherited Destroy();
end;

procedure TFloriaJSLexer.Reset();
begin
  FPos := 1;
  FLine := 1;
  FColumn := 1;
  FHasPeeked := False;
  FLastTokenKind := tkEOF;
  SetLength(FBraceStack, 0);
end;

function TFloriaJSLexer.IsAtEnd(): Boolean;
begin
  Result := (FPos > FLength);
end;

function TFloriaJSLexer.PeekChar(): Char;
begin
  if FPos > FLength then
    Result := #0
  else
    Result := FSource[FPos];
end;

function TFloriaJSLexer.PeekNextChar(): Char;
begin
  if FPos + 1 > FLength then
    Result := #0
  else
    Result := FSource[FPos + 1];
end;

function TFloriaJSLexer.AdvanceChar(): Char;
begin
  if FPos > FLength then
    Exit(#0);

  Result := FSource[FPos];
  Inc(FPos);
  if Result = #10 then
  begin
    Inc(FLine);
    FColumn := 1;
  end
  else
    Inc(FColumn);
end;

function TFloriaJSLexer.MatchChar(AExpected: Char): Boolean;
begin
  if (FPos > FLength) or (FSource[FPos] <> AExpected) then
    Exit(False);

  AdvanceChar();
  Result := True;
end;

procedure TFloriaJSLexer.SkipWhitespace();
var
  c: Char;
begin
  while not IsAtEnd() do
  begin
    c := PeekChar();
    case c of
      ' ', #9, #11, #12, #13:
        AdvanceChar();
      #10:
        AdvanceChar();
    else
      Break;
    end;
  end;
end;

function TFloriaJSLexer.MakeToken(AKind: TFloriaJSTokenKind; const AText: string; AStartLine, AStartCol, AStartPos: Integer): TFloriaJSToken;
begin
  Result.Kind := AKind;
  Result.Text := AText;
  Result.NumberValue := 0.0;
  Result.Line := AStartLine;
  Result.Column := AStartCol;
  Result.StartPos := AStartPos;
  Result.EndPos := FPos - 1;
  if AKind <> tkComment then
    FLastTokenKind := AKind;
end;

function TFloriaJSLexer.MakeError(const AMessage: string; AStartLine, AStartCol, AStartPos: Integer): TFloriaJSToken;
begin
  Result.Kind := tkError;
  Result.Text := AMessage;
  Result.NumberValue := 0.0;
  Result.Line := AStartLine;
  Result.Column := AStartCol;
  Result.StartPos := AStartPos;
  Result.EndPos := FPos - 1;
end;

function TFloriaJSLexer.ScanIdentifierOrKeyword(): TFloriaJSToken;
var
  startPos, startCol, startLine: Integer;
  txt: string;
  kind: TFloriaJSTokenKind;
begin
  startPos := FPos;
  startLine := FLine;
  startCol := FColumn;

  while (not IsAtEnd()) and IsIdentPart(PeekChar()) do
    AdvanceChar();

  txt := Copy(FSource, startPos, FPos - startPos);
  kind := CheckKeyword(txt);

  Result := MakeToken(kind, txt, startLine, startCol, startPos);
end;

function TFloriaJSLexer.ScanNumber(): TFloriaJSToken;
var
  startPos, startCol, startLine: Integer;
  numStr: string;
  val: Double;
  fs: TFormatSettings;
begin
  startPos := FPos;
  startLine := FLine;
  startCol := FColumn;

  { Check for Hex (0x), Binary (0b), Octal (0o) }
  if (PeekChar() = '0') and (PeekNextChar() in ['x', 'X']) then
  begin
    AdvanceChar(); { 0 }
    AdvanceChar(); { x }
    while (not IsAtEnd()) and IsHexDigit(PeekChar()) do
      AdvanceChar();
    numStr := Copy(FSource, startPos, FPos - startPos);
    val := StrToInt64('$' + Copy(numStr, 3, Length(numStr) - 2));
    Result := MakeToken(tkNumber, numStr, startLine, startCol, startPos);
    Result.NumberValue := val;
    Exit;
  end;

  if (PeekChar() = '0') and (PeekNextChar() in ['b', 'B']) then
  begin
    AdvanceChar(); { 0 }
    AdvanceChar(); { b }
    val := 0.0;
    while (not IsAtEnd()) and (PeekChar() in ['0', '1']) do
    begin
      val := val * 2.0 + (Ord(AdvanceChar()) - Ord('0'));
    end;
    numStr := Copy(FSource, startPos, FPos - startPos);
    Result := MakeToken(tkNumber, numStr, startLine, startCol, startPos);
    Result.NumberValue := val;
    Exit;
  end;

  if (PeekChar() = '0') and (PeekNextChar() in ['o', 'O']) then
  begin
    AdvanceChar(); { 0 }
    AdvanceChar(); { o }
    val := 0.0;
    while (not IsAtEnd()) and (PeekChar() in ['0'..'7']) do
    begin
      val := val * 8.0 + (Ord(AdvanceChar()) - Ord('0'));
    end;
    numStr := Copy(FSource, startPos, FPos - startPos);
    Result := MakeToken(tkNumber, numStr, startLine, startCol, startPos);
    Result.NumberValue := val;
    Exit;
  end;

  { Decimal integer part }
  while (not IsAtEnd()) do
  begin
    if IsDigit(PeekChar()) then
      AdvanceChar()
    else if PeekChar() = '_' then
      AdvanceChar()
    else
      Break;
  end;

  { Fractional part }
  if (PeekChar() = '.') and IsDigit(PeekNextChar()) then
  begin
    AdvanceChar(); { Consume '.' }
    while (not IsAtEnd()) do
    begin
      if IsDigit(PeekChar()) then
        AdvanceChar()
      else if PeekChar() = '_' then
        AdvanceChar()
      else
        Break;
    end;
  end;

  { Scientific exponent: e or E }
  if PeekChar() in ['e', 'E'] then
  begin
    AdvanceChar();
    if PeekChar() in ['+', '-'] then
      AdvanceChar();
    while (not IsAtEnd()) do
    begin
      if IsDigit(PeekChar()) then
        AdvanceChar()
      else if PeekChar() = '_' then
        AdvanceChar()
      else
        Break;
    end;
  end;

  numStr := Copy(FSource, startPos, FPos - startPos);
  { Remove numeric separators }
  numStr := StringReplace(numStr, '_', '', [rfReplaceAll]);
  fs.DecimalSeparator := '.';
  if not TryStrToFloat(numStr, val, fs) then
    val := 0.0;

  Result := MakeToken(tkNumber, numStr, startLine, startCol, startPos);
  Result.NumberValue := val;
end;

function TFloriaJSLexer.ScanString(AQuote: Char): TFloriaJSToken;
var
  startPos, startCol, startLine: Integer;
  sb: string;
  c, esc: Char;
  hexCode: string;
  valInt: Integer;
begin
  startPos := FPos;
  startLine := FLine;
  startCol := FColumn;

  AdvanceChar(); { Consume opening quote }
  sb := '';

  while not IsAtEnd() do
  begin
    c := AdvanceChar();
    if c = AQuote then
    begin
      Result := MakeToken(tkString, sb, startLine, startCol, startPos);
      Exit;
    end
    else if c = '\' then
    begin
      if IsAtEnd() then
        Exit(MakeError('Unterminated escape sequence in string literal', startLine, startCol, startPos));

      esc := AdvanceChar();
      case esc of
        'n':  sb := sb + #10;
        'r':  sb := sb + #13;
        't':  sb := sb + #9;
        'b':  sb := sb + #8;
        'f':  sb := sb + #12;
        'v':  sb := sb + #11;
        '0':  sb := sb + #0;
        '\':  sb := sb + '\';
        '''': sb := sb + '''';
        '"':  sb := sb + '"';
        'x':
        begin
          hexCode := AdvanceChar() + AdvanceChar();
          if TryStrToInt('$' + hexCode, valInt) then
            sb := sb + Chr(valInt)
          else
            sb := sb + '\x' + hexCode;
        end;
        'u':
        begin
          hexCode := AdvanceChar() + AdvanceChar() + AdvanceChar() + AdvanceChar();
          if TryStrToInt('$' + hexCode, valInt) then
            sb := sb + WideChar(valInt)
          else
            sb := sb + '\u' + hexCode;
        end;
      else
        sb := sb + esc;
      end;
    end
    else
      sb := sb + c;
  end;

  Result := MakeError('Unterminated string literal', startLine, startCol, startPos);
end;

function TFloriaJSLexer.ScanTemplateString(AFromExpression: Boolean = False): TFloriaJSToken;
var
  startPos, startCol, startLine: Integer;
  sb: string;
  c, esc: Char;
begin
  startPos := FPos;
  startLine := FLine;
  startCol := FColumn;

  if not AFromExpression then
    AdvanceChar(); // Consume opening backtick

  sb := '';

  while not IsAtEnd() do
  begin
    c := AdvanceChar();
    if c = '`' then
    begin
      if AFromExpression then
        Result := MakeToken(tkTemplateTail, sb, startLine, startCol, startPos)
      else
        Result := MakeToken(tkTemplateString, sb, startLine, startCol, startPos);
      Exit;
    end
    else if (c = '$') and (PeekChar() = '{') then
    begin
      AdvanceChar(); // Consume '{'
      SetLength(FBraceStack, Length(FBraceStack) + 1);
      FBraceStack[High(FBraceStack)] := True;

      if AFromExpression then
        Result := MakeToken(tkTemplateMiddle, sb, startLine, startCol, startPos)
      else
        Result := MakeToken(tkTemplateHead, sb, startLine, startCol, startPos);
      Exit;
    end
    else if c = '\' then
    begin
      if IsAtEnd() then Break;
      esc := AdvanceChar();
      case esc of
        '`': sb := sb + '`';
        '$': sb := sb + '$';
        '\': sb := sb + '\';
        'n': sb := sb + #10;
        'r': sb := sb + #13;
        't': sb := sb + #9;
        'b': sb := sb + #8;
        'f': sb := sb + #12;
        '0': sb := sb + #0;
      else
        sb := sb + esc;
      end;
    end
    else
      sb := sb + c;
  end;

  Result := MakeError('Unterminated template string literal', startLine, startCol, startPos);
end;

function TFloriaJSLexer.ScanComment(): TFloriaJSToken;
var
  startPos, startCol, startLine: Integer;
  txt: string;
begin
  startPos := FPos;
  startLine := FLine;
  startCol := FColumn;

  AdvanceChar(); { Consume initial '/' }

  if PeekChar() = '/' then
  begin
    { Single line comment: // ... }
    AdvanceChar();
    while (not IsAtEnd()) and (PeekChar() <> #10) do
      AdvanceChar();
    txt := Copy(FSource, startPos, FPos - startPos);
    Result := MakeToken(tkComment, txt, startLine, startCol, startPos);
  end
  else if PeekChar() = '*' then
  begin
    { Multi-line comment: /* ... */ }
    AdvanceChar();
    while not IsAtEnd() do
    begin
      if (PeekChar() = '*') and (PeekNextChar() = '/') then
      begin
        AdvanceChar();
        AdvanceChar();
        Break;
      end;
      AdvanceChar();
    end;
    txt := Copy(FSource, startPos, FPos - startPos);
    Result := MakeToken(tkComment, txt, startLine, startCol, startPos);
  end
  else
    Result := MakeError('Invalid comment scanner state', startLine, startCol, startPos);
end;

function TFloriaJSLexer.IsRegexAllowed(): Boolean;
begin
  case FLastTokenKind of
    tkIdentifier, tkNumber, tkString, tkTemplateTail,
    tkRParen, tkRBracket, tkRBrace,
    tkPlusPlus, tkMinusMinus:
      Result := False;
  else
    Result := True;
  end;
end;

function TFloriaJSLexer.ScanRegExp(AStartLine, AStartCol, AStartPos: Integer): TFloriaJSToken;
var
  pat, flags: string;
  inClass: Boolean;
  ch: Char;
begin
  pat := '';
  flags := '';
  inClass := False;
  while not IsAtEnd() do
  begin
    ch := AdvanceChar();
    if ch = '\' then
    begin
      pat := pat + '\';
      if not IsAtEnd() then
        pat := pat + AdvanceChar();
    end
    else if ch = '[' then
    begin
      inClass := True;
      pat := pat + '[';
    end
    else if ch = ']' then
    begin
      inClass := False;
      pat := pat + ']';
    end
    else if (ch = '/') and not inClass then
      Break
    else if (ch = #10) or (ch = #13) then
      Exit(MakeError('Unterminated regular expression literal', AStartLine, AStartCol, AStartPos))
    else
      pat := pat + ch;
  end;

  while not IsAtEnd() and (PeekChar() in ['a'..'z', 'A'..'Z']) do
    flags := flags + AdvanceChar();

  Result := MakeToken(tkRegExp, pat + #0 + flags, AStartLine, AStartCol, AStartPos);
end;

function TFloriaJSLexer.NextToken(): TFloriaJSToken;
var
  startLine, startCol, startPos: Integer;
  c: Char;
begin
  if FHasPeeked then
  begin
    FHasPeeked := False;
    Exit(FPeekedToken);
  end;

  while True do
  begin
    SkipWhitespace();

    if IsAtEnd() then
      Exit(MakeToken(tkEOF, '', FLine, FColumn, FPos));

    startPos := FPos;
    startLine := FLine;
    startCol := FColumn;
    c := PeekChar();

    { Comments: // and /* */ }
    if (c = '/') and ((PeekNextChar() = '/') or (PeekNextChar() = '*')) then
    begin
      ScanComment();
      Continue; { Skip comment and continue to next token }
    end;

    { Identifiers and Keywords }
    if IsIdentStart(c) then
      Exit(ScanIdentifierOrKeyword());

    { Numbers (including leading dot floats like .5) }
    if IsDigit(c) or ((c = '.') and IsDigit(PeekNextChar())) then
      Exit(ScanNumber());

    { Strings: ' or " }
    if (c = '''') or (c = '"') then
      Exit(ScanString(c));

    { Template Strings: ` }
    if c = '`' then
      Exit(ScanTemplateString());

    { Operators and Punctuation }
    AdvanceChar();

    case c of
      '(': Exit(MakeToken(tkLParen, '(', startLine, startCol, startPos));
      ')': Exit(MakeToken(tkRParen, ')', startLine, startCol, startPos));
      '{':
      begin
        if Length(FBraceStack) > 0 then
        begin
          SetLength(FBraceStack, Length(FBraceStack) + 1);
          FBraceStack[High(FBraceStack)] := False;
        end;
        Exit(MakeToken(tkLBrace, '{', startLine, startCol, startPos));
      end;

      '}':
      begin
        if Length(FBraceStack) > 0 then
        begin
          if FBraceStack[High(FBraceStack)] = True then
          begin
            SetLength(FBraceStack, Length(FBraceStack) - 1);
            Exit(ScanTemplateString(True));
          end
          else
            SetLength(FBraceStack, Length(FBraceStack) - 1);
        end;
        Exit(MakeToken(tkRBrace, '}', startLine, startCol, startPos));
      end;

      '[': Exit(MakeToken(tkLBracket, '[', startLine, startCol, startPos));
      ']': Exit(MakeToken(tkRBracket, ']', startLine, startCol, startPos));
      ';': Exit(MakeToken(tkSemicolon, ';', startLine, startCol, startPos));
      ',': Exit(MakeToken(tkComma, ',', startLine, startCol, startPos));
      ':': Exit(MakeToken(tkColon, ':', startLine, startCol, startPos));
      '~': Exit(MakeToken(tkBitNot, '~', startLine, startCol, startPos));

      '.':
      begin
        if (PeekChar() = '.') and (PeekNextChar() = '.') then
        begin
          AdvanceChar();
          AdvanceChar();
          Exit(MakeToken(tkEllipsis, '...', startLine, startCol, startPos));
        end;
        Exit(MakeToken(tkDot, '.', startLine, startCol, startPos));
      end;

      '?':
      begin
        if MatchChar('?') then
        begin
          if MatchChar('=') then
            Exit(MakeToken(tkNullishAssign, '??=', startLine, startCol, startPos))
          else
            Exit(MakeToken(tkNullish, '??', startLine, startCol, startPos));
        end
        else if MatchChar('.') then
        begin
          { Optional chaining: ?. must not be confused with ternary ? followed by
            numeric property access. If followed by a digit, treat as ?.ternary
            is handled elsewhere, but simply prefer ?. in that ambiguous form. }
          if (FPos <= Length(FSource)) and IsDigit(FSource[FPos]) then
            Exit(MakeToken(tkQuestion, '?', startLine, startCol, startPos))
          else
            Exit(MakeToken(tkQuestionDot, '?.', startLine, startCol, startPos));
        end
        else
          Exit(MakeToken(tkQuestion, '?', startLine, startCol, startPos));
      end;

      '+':
      begin
        if MatchChar('+') then
          Exit(MakeToken(tkPlusPlus, '++', startLine, startCol, startPos))
        else if MatchChar('=') then
          Exit(MakeToken(tkPlusAssign, '+=', startLine, startCol, startPos))
        else
          Exit(MakeToken(tkPlus, '+', startLine, startCol, startPos));
      end;

      '-':
      begin
        if MatchChar('-') then
          Exit(MakeToken(tkMinusMinus, '--', startLine, startCol, startPos))
        else if MatchChar('=') then
          Exit(MakeToken(tkMinusAssign, '-=', startLine, startCol, startPos))
        else
          Exit(MakeToken(tkMinus, '-', startLine, startCol, startPos));
      end;

      '*':
      begin
        if MatchChar('*') then
        begin
          if MatchChar('=') then
            Exit(MakeToken(tkPowerAssign, '**=', startLine, startCol, startPos))
          else
            Exit(MakeToken(tkPower, '**', startLine, startCol, startPos));
        end
        else if MatchChar('=') then
          Exit(MakeToken(tkMultiplyAssign, '*=', startLine, startCol, startPos))
        else
          Exit(MakeToken(tkMultiply, '*', startLine, startCol, startPos));
      end;

      '/':
      begin
        if MatchChar('=') then
          Exit(MakeToken(tkDivideAssign, '/=', startLine, startCol, startPos))
        else if IsRegexAllowed() then
          Exit(ScanRegExp(startLine, startCol, startPos))
        else
          Exit(MakeToken(tkDivide, '/', startLine, startCol, startPos));
      end;

      '%':
      begin
        if MatchChar('=') then
          Exit(MakeToken(tkModuloAssign, '%=', startLine, startCol, startPos))
        else
          Exit(MakeToken(tkModulo, '%', startLine, startCol, startPos));
      end;

      '=':
      begin
        if MatchChar('=') then
        begin
          if MatchChar('=') then
            Exit(MakeToken(tkStrictEqual, '===', startLine, startCol, startPos))
          else
            Exit(MakeToken(tkEqual, '==', startLine, startCol, startPos));
        end
        else if MatchChar('>') then
          Exit(MakeToken(tkArrow, '=>', startLine, startCol, startPos))
        else
          Exit(MakeToken(tkAssign, '=', startLine, startCol, startPos));
      end;

      '!':
      begin
        if MatchChar('=') then
        begin
          if MatchChar('=') then
            Exit(MakeToken(tkStrictNotEqual, '!==', startLine, startCol, startPos))
          else
            Exit(MakeToken(tkNotEqual, '!=', startLine, startCol, startPos));
        end
        else
          Exit(MakeToken(tkNot, '!', startLine, startCol, startPos));
      end;

      '<':
      begin
        if MatchChar('<') then
          Exit(MakeToken(tkShiftLeft, '<<', startLine, startCol, startPos))
        else if MatchChar('=') then
          Exit(MakeToken(tkLessEqual, '<=', startLine, startCol, startPos))
        else
          Exit(MakeToken(tkLessThan, '<', startLine, startCol, startPos));
      end;

      '>':
      begin
        if MatchChar('>') then
        begin
          if MatchChar('>') then
            Exit(MakeToken(tkShiftRightUnsigned, '>>>', startLine, startCol, startPos))
          else
            Exit(MakeToken(tkShiftRight, '>>', startLine, startCol, startPos));
        end
        else if MatchChar('=') then
          Exit(MakeToken(tkGreaterEqual, '>=', startLine, startCol, startPos))
        else
          Exit(MakeToken(tkGreaterThan, '>', startLine, startCol, startPos));
      end;

      '&':
      begin
        if MatchChar('&') then
          Exit(MakeToken(tkAnd, '&&', startLine, startCol, startPos))
        else
          Exit(MakeToken(tkBitAnd, '&', startLine, startCol, startPos));
      end;

      '|':
      begin
        if MatchChar('|') then
          Exit(MakeToken(tkOr, '||', startLine, startCol, startPos))
        else
          Exit(MakeToken(tkBitOr, '|', startLine, startCol, startPos));
      end;

      '^':
        Exit(MakeToken(tkBitXor, '^', startLine, startCol, startPos));

    else
      Exit(MakeError('Unexpected character: ''' + c + '''', startLine, startCol, startPos));
    end;
  end;
end;

function TFloriaJSLexer.PeekToken(): TFloriaJSToken;
begin
  if not FHasPeeked then
  begin
    FPeekedToken := NextToken();
    FHasPeeked := True;
  end;
  Result := FPeekedToken;
end;

class function TFloriaJSLexer.TokenKindToString(AKind: TFloriaJSTokenKind): string;
begin
  case AKind of
    tkEOF:            Result := 'EOF';
    tkError:          Result := 'Error';
    tkComment:        Result := 'Comment';
    tkIdentifier:     Result := 'Identifier';
    tkNumber:         Result := 'Number';
    tkString:         Result := 'String';
    tkRegExp:         Result := 'RegExp';
    tkTemplateString: Result := 'TemplateString';
    tkTemplateHead:   Result := 'TemplateHead';
    tkTemplateMiddle: Result := 'TemplateMiddle';
    tkTemplateTail:   Result := 'TemplateTail';
    tkLet:            Result := 'let';
    tkConst:          Result := 'const';
    tkVar:            Result := 'var';
    tkFunction:       Result := 'function';
    tkAsync:          Result := 'async';
    tkAwait:          Result := 'await';
    tkReturn:         Result := 'return';
    tkIf:             Result := 'if';
    tkElse:           Result := 'else';
    tkFor:            Result := 'for';
    tkWhile:          Result := 'while';
    tkDo:             Result := 'do';
    tkBreak:          Result := 'break';
    tkContinue:       Result := 'continue';
    tkSwitch:         Result := 'switch';
    tkCase:           Result := 'case';
    tkDefault:        Result := 'default';
    tkTry:            Result := 'try';
    tkCatch:          Result := 'catch';
    tkFinally:        Result := 'finally';
    tkThrow:          Result := 'throw';
    tkNew:            Result := 'new';
    tkThis:           Result := 'this';
    tkTypeof:         Result := 'typeof';
    tkDelete:         Result := 'delete';
    tkIn:             Result := 'in';
    tkOf:             Result := 'of';
    tkInstanceof:     Result := 'instanceof';
    tkTrue:           Result := 'true';
    tkFalse:          Result := 'false';
    tkNull:           Result := 'null';
    tkUndefined:      Result := 'undefined';
    tkLParen:         Result := '(';
    tkRParen:         Result := ')';
    tkLBrace:         Result := '{';
    tkRBrace:         Result := '}';
    tkLBracket:       Result := '[';
    tkRBracket:       Result := ']';
    tkSemicolon:      Result := ';';
    tkColon:          Result := ':';
    tkComma:          Result := ',';
    tkDot:            Result := '.';
    tkEllipsis:       Result := '...';
    tkQuestion:       Result := '?';
    tkQuestionDot:    Result := '?.';
    tkAssign:         Result := '=';
    tkPlus:           Result := '+';
    tkPlusPlus:       Result := '++';
    tkPlusAssign:     Result := '+=';
    tkMinus:          Result := '-';
    tkMinusMinus:     Result := '--';
    tkMinusAssign:    Result := '-=';
    tkMultiply:       Result := '*';
    tkPower:          Result := '**';
    tkPowerAssign:    Result := '**=';
    tkMultiplyAssign: Result := '*=';
    tkDivide:         Result := '/';
    tkDivideAssign:   Result := '/=';
    tkModulo:         Result := '%';
    tkModuloAssign:   Result := '%=';
    tkEqual:          Result := '==';
    tkStrictEqual:    Result := '===';
    tkNotEqual:       Result := '!=';
    tkStrictNotEqual: Result := '!==';
    tkLessThan:       Result := '<';
    tkLessEqual:      Result := '<=';
    tkGreaterThan:    Result := '>';
    tkGreaterEqual:   Result := '>=';
    tkNot:            Result := '!';
    tkAnd:            Result := '&&';
    tkOr:             Result := '||';
    tkNullish:        Result := '??';
    tkNullishAssign:  Result := '??=';
    tkBitAnd:         Result := '&';
    tkBitOr:          Result := '|';
    tkBitXor:         Result := '^';
    tkBitNot:         Result := '~';
    tkShiftLeft:      Result := '<<';
    tkShiftRight:     Result := '>>';
    tkShiftRightUnsigned: Result := '>>>';
    tkArrow:          Result := '=>';
  else
    Result := 'Unknown';
  end;
end;

end.
