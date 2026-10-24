{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — RegExp Object & Pattern Matching Engine         }
{                                                                          }
{   Provides standard JavaScript RegExp object, pattern compilation,       }
{   test, exec, and string integration via native Pascal RegExpr.          }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.regexp;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, RegExpr, floria.js.types, floria.js.value, floria.js.env;

type
  { RegExp Object }
  TFloriaJSRegExp = class(TFloriaJSObject)
  private
    FRegExpr: TRegExpr;
    FPattern: string;
    FFlags: string;
    FGlobal: Boolean;
    FIgnoreCase: Boolean;
    FMultiline: Boolean;
    FLastIndex: Integer;

    procedure CompilePattern();
  public
    constructor Create(const APattern: string = ''; const AFlags: string = ''; AProto: TFloriaJSObject = nil);
    destructor Destroy(); override;

    function Test(const AStr: string): Boolean;
    function Exec(const AStr: string; AHeap: TFloriaJSHeap): TFloriaJSValue;
    function Replace(const AStr, AReplacement: string): string;

    property Pattern: string read FPattern;
    property Flags: string read FFlags;
    property Global: Boolean read FGlobal;
    property IgnoreCase: Boolean read FIgnoreCase;
    property Multiline: Boolean read FMultiline;
    property LastIndex: Integer read FLastIndex write FLastIndex;
    property RegEngine: TRegExpr read FRegExpr;
  end;

function FloriaJSNewRegExp(const APattern, AFlags: string; AHeap: TFloriaJSHeap): TFloriaJSRegExp;
procedure FloriaJSRegisterRegExp(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);

implementation

var
  GSharedRegExpProto: TFloriaJSObject = nil;
  GSharedRegExpHeap: TFloriaJSHeap = nil;

{ TFloriaJSRegExp }

constructor TFloriaJSRegExp.Create(const APattern: string; const AFlags: string; AProto: TFloriaJSObject);
var
  i: Integer;
begin
  inherited Create(AProto);
  FPattern := APattern;
  FFlags := AFlags;
  FGlobal := False;
  FIgnoreCase := False;
  FMultiline := False;
  FLastIndex := 0;

  for i := 1 to Length(AFlags) do
  begin
    case AFlags[i] of
      'g': FGlobal := True;
      'i': FIgnoreCase := True;
      'm': FMultiline := True;
    end;
  end;

  FRegExpr := TRegExpr.Create();
  CompilePattern();
end;

destructor TFloriaJSRegExp.Destroy();
begin
  FreeAndNil(FRegExpr);
  inherited Destroy();
end;

procedure TFloriaJSRegExp.CompilePattern();
begin
  if FRegExpr = nil then Exit;
  try
    FRegExpr.Expression := FPattern;
    FRegExpr.ModifierI := FIgnoreCase;
    FRegExpr.ModifierM := FMultiline;
    FRegExpr.Compile();
  except
    on E: Exception do
      raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('SyntaxError', 'Invalid regular expression: /' + FPattern + '/: ' + E.Message)));
  end;
end;

function TFloriaJSRegExp.Test(const AStr: string): Boolean;
var
  res: TFloriaJSValue;
begin
  if FGlobal then
  begin
    res := Exec(AStr, nil);
    Result := not res.IsNull();
  end
  else
  begin
    if FRegExpr = nil then Exit(False);
    try
      Result := FRegExpr.Exec(AStr);
    except
      Result := False;
    end;
  end;
end;

function TFloriaJSRegExp.Exec(const AStr: string; AHeap: TFloriaJSHeap): TFloriaJSValue;
var
  matched: Boolean;
  arr: TFloriaJSArray;
  i, count, matchStart, matchLen: Integer;
begin
  if FRegExpr = nil then Exit(JSMakeNull());

  try
    if FGlobal then
    begin
      if (FLastIndex < 0) or (FLastIndex > Length(AStr)) then
      begin
        FLastIndex := 0;
        Exit(JSMakeNull());
      end;
      FRegExpr.InputString := AStr;
      matched := FRegExpr.ExecPos(FLastIndex + 1);
    end
    else
      matched := FRegExpr.Exec(AStr);
  except
    Exit(JSMakeNull());
  end;

  if not matched then
  begin
    if FGlobal then FLastIndex := 0;
    Exit(JSMakeNull());
  end;

  matchStart := FRegExpr.MatchPos[0] - 1; // 0-based index
  matchLen := FRegExpr.MatchLen[0];

  if AHeap <> nil then
    arr := AHeap.NewArray()
  else
    arr := TFloriaJSArray.Create();

  arr.Push(JSMakeString(FRegExpr.Match[0]));

  count := FRegExpr.SubExprMatchCount;
  for i := 1 to count do
    arr.Push(JSMakeString(FRegExpr.Match[i]));

  arr.SetProperty('index', JSMakeNumber(matchStart));
  arr.SetProperty('input', JSMakeString(AStr));

  if FGlobal then
  begin
    if matchLen = 0 then
      FLastIndex := matchStart + 1
    else
      FLastIndex := matchStart + matchLen;
  end;

  Result := JSMakeObject(arr);
end;

function TFloriaJSRegExp.Replace(const AStr, AReplacement: string): string;
begin
  if FRegExpr = nil then Exit(AStr);
  try
    Result := FRegExpr.Replace(AStr, AReplacement, not FGlobal);
  except
    Result := AStr;
  end;
end;

{ RegExp JS Bindings }

function JSRegExpCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  pat, flags: string;
  re: TFloriaJSRegExp;
begin
  pat := '';
  flags := '';

  if Length(AArgs) > 0 then
  begin
    if AArgs[0].IsObject() and (AArgs[0].ObjVal is TFloriaJSRegExp) then
    begin
      pat := TFloriaJSRegExp(AArgs[0].ObjVal).Pattern;
      flags := TFloriaJSRegExp(AArgs[0].ObjVal).Flags;
    end
    else if not AArgs[0].IsUndefined() then
      pat := AArgs[0].ToString();
  end;

  if (Length(AArgs) > 1) and not AArgs[1].IsUndefined() then
    flags := AArgs[1].ToString();

  re := TFloriaJSRegExp.Create(pat, flags, GSharedRegExpProto);
  if GSharedRegExpHeap <> nil then
    GSharedRegExpHeap.Track(re);
  Result := JSMakeObject(re);
end;

function JSRegExpTest(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: string;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSRegExp) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method RegExp.prototype.test called on incompatible receiver')));

  target := '';
  if Length(AArgs) > 0 then target := AArgs[0].ToString();

  Result := JSMakeBoolean(TFloriaJSRegExp(AThis.ObjVal).Test(target));
end;

function JSRegExpExec(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: string;
  heap: TFloriaJSHeap;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSRegExp) then
    raise EFloriaJSThrow.Create(JSMakeObject(TFloriaJSError.Create('TypeError', 'Method RegExp.prototype.exec called on incompatible receiver')));

  target := '';
  if Length(AArgs) > 0 then target := AArgs[0].ToString();

  heap := AThis.ObjVal.Heap;
  if heap = nil then heap := GSharedRegExpHeap;

  Result := TFloriaJSRegExp(AThis.ObjVal).Exec(target, heap);
end;

function JSRegExpToString(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  re: TFloriaJSRegExp;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSRegExp) then
    Exit(JSMakeString('/(?:)/'));

  re := TFloriaJSRegExp(AThis.ObjVal);
  Result := JSMakeString('/' + re.Pattern + '/' + re.Flags);
end;

function JSRegExpGetSource(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSRegExp) then
    Exit(JSMakeString(''));
  Result := JSMakeString(TFloriaJSRegExp(AThis.ObjVal).Pattern);
end;

function JSRegExpGetFlags(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSRegExp) then
    Exit(JSMakeString(''));
  Result := JSMakeString(TFloriaJSRegExp(AThis.ObjVal).Flags);
end;

function JSRegExpGetGlobal(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSRegExp) then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(TFloriaJSRegExp(AThis.ObjVal).Global);
end;

function JSRegExpGetIgnoreCase(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSRegExp) then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(TFloriaJSRegExp(AThis.ObjVal).IgnoreCase);
end;

function JSRegExpGetMultiline(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSRegExp) then
    Exit(JSMakeBoolean(False));
  Result := JSMakeBoolean(TFloriaJSRegExp(AThis.ObjVal).Multiline);
end;

function FloriaJSNewRegExp(const APattern, AFlags: string; AHeap: TFloriaJSHeap): TFloriaJSRegExp;
begin
  Result := TFloriaJSRegExp.Create(APattern, AFlags, GSharedRegExpProto);
  if AHeap <> nil then
    AHeap.Track(Result);
end;

procedure FloriaJSRegisterRegExp(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  reCtor: TFloriaJSFunction;
  getter: TFloriaJSFunction;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;
  GSharedRegExpHeap := AHeap;

  GSharedRegExpProto := AHeap.NewObject();
  GSharedRegExpProto.SetProperty('test', JSMakeFunction(AHeap.NewNativeFunction('test', @JSRegExpTest)));
  GSharedRegExpProto.SetProperty('exec', JSMakeFunction(AHeap.NewNativeFunction('exec', @JSRegExpExec)));
  GSharedRegExpProto.SetProperty('toString', JSMakeFunction(AHeap.NewNativeFunction('toString', @JSRegExpToString)));

  getter := AHeap.NewNativeFunction('get source', @JSRegExpGetSource);
  GSharedRegExpProto.DefineGetter('source', JSMakeFunction(getter));

  getter := AHeap.NewNativeFunction('get flags', @JSRegExpGetFlags);
  GSharedRegExpProto.DefineGetter('flags', JSMakeFunction(getter));

  getter := AHeap.NewNativeFunction('get global', @JSRegExpGetGlobal);
  GSharedRegExpProto.DefineGetter('global', JSMakeFunction(getter));

  getter := AHeap.NewNativeFunction('get ignoreCase', @JSRegExpGetIgnoreCase);
  GSharedRegExpProto.DefineGetter('ignoreCase', JSMakeFunction(getter));

  getter := AHeap.NewNativeFunction('get multiline', @JSRegExpGetMultiline);
  GSharedRegExpProto.DefineGetter('multiline', JSMakeFunction(getter));

  reCtor := AHeap.NewNativeFunction('RegExp', @JSRegExpCtor);
  reCtor.SetProperty('prototype', JSMakeObject(GSharedRegExpProto));
  AEnv.Define('RegExp', JSMakeFunction(reCtor));
end;

end.
