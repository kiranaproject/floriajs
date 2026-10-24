{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Host Timers (setTimeout, clearTimeout)          }
{                                                                          }
{   Provides standard setTimeout, clearTimeout, setInterval, and           }
{   clearInterval timer scheduling primitives.                             }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.timers;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, floria.js.types, floria.js.value, floria.js.env;

type
  { Timer Record }
  TFloriaJSTimer = record
    Id: Integer;
    Callback: TFloriaJSValue;
    Args: array of TFloriaJSValue;
    DelayMS: Double;
    DueMS: Double;
    Active: Boolean;
    Repeats: Boolean;
  end;

procedure FloriaJSRegisterTimers(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
procedure FloriaJSProcessTimers(AHeap: TFloriaJSHeap);

implementation

var
  GTimers: array of TFloriaJSTimer;
  GTimerCount: Integer = 0;
  GNextTimerId: Integer = 1;
  GSharedTimerHeap: TFloriaJSHeap = nil;

function CurrentMS(): Double;
begin
  Result := (Now() - 25569.0) * 86400000.0;
end;

function AllocTimerId(): Integer;
begin
  Inc(GNextTimerId);
  Result := GNextTimerId;
end;

function JSSetTimeout(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  id, i, argCount: Integer;
  delay: Double;
  job: TFloriaJSPromiseJob;
  heap: TFloriaJSHeap;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsFunction() then
    Exit(JSMakeNumber(0));

  delay := 0.0;
  if Length(AArgs) > 1 then
    delay := AArgs[1].ToNumber();
  if delay < 0.0 then delay := 0.0;

  id := AllocTimerId();

  if GTimerCount >= Length(GTimers) then
    SetLength(GTimers, (GTimerCount + 1) * 2);

  GTimers[GTimerCount].Id := id;
  GTimers[GTimerCount].Callback := AArgs[0];
  JSRetainValue(AArgs[0]);
  GTimers[GTimerCount].DelayMS := delay;
  GTimers[GTimerCount].DueMS := CurrentMS() + delay;
  GTimers[GTimerCount].Active := True;
  GTimers[GTimerCount].Repeats := False;

  argCount := Length(AArgs) - 2;
  if argCount > 0 then
  begin
    SetLength(GTimers[GTimerCount].Args, argCount);
    for i := 0 to argCount - 1 do
    begin
      GTimers[GTimerCount].Args[i] := AArgs[i + 2];
      JSRetainValue(AArgs[i + 2]);
    end;
  end
  else
    SetLength(GTimers[GTimerCount].Args, 0);

  Inc(GTimerCount);

  // If delay is 0, also enqueue as a promise job for immediate microtask execution
  heap := GSharedTimerHeap;
  if (delay <= 0) and (heap <> nil) then
  begin
    job.OnFulfilled := AArgs[0];
    job.OnRejected := JSMakeUndefined();
    job.OnFinally := JSMakeUndefined();
    job.Value := JSMakeUndefined();
    job.Child := nil;
    heap.EnqueuePromiseJob(job);
  end;

  Result := JSMakeNumber(id);
end;

function JSClearTimeout(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  id, i, j: Integer;
begin
  if Length(AArgs) = 0 then Exit(JSMakeUndefined());
  id := Round(AArgs[0].ToNumber());

  for i := 0 to GTimerCount - 1 do
  begin
    if GTimers[i].Id = id then
    begin
      if GTimers[i].Active then
      begin
        GTimers[i].Active := False;
        JSReleaseValue(GTimers[i].Callback);
        for j := 0 to High(GTimers[i].Args) do
          JSReleaseValue(GTimers[i].Args[j]);
        SetLength(GTimers[i].Args, 0);
      end;
      Break;
    end;
  end;

  Result := JSMakeUndefined();
end;

function JSSetInterval(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  res: TFloriaJSValue;
  id: Integer;
  i: Integer;
begin
  res := JSSetTimeout(AArgs, AThis);
  id := Round(res.NumVal);
  for i := 0 to GTimerCount - 1 do
  begin
    if GTimers[i].Id = id then
    begin
      GTimers[i].Repeats := True;
      Break;
    end;
  end;
  Result := res;
end;

procedure FloriaJSProcessTimers(AHeap: TFloriaJSHeap);
var
  nowTime: Double;
  i, j: Integer;
  cb: TFloriaJSValue;
begin
  nowTime := CurrentMS();

  for i := 0 to GTimerCount - 1 do
  begin
    if GTimers[i].Active and (nowTime >= GTimers[i].DueMS) then
    begin
      cb := GTimers[i].Callback;
      if (AHeap <> nil) and cb.IsFunction() then
        AHeap.InvokeFunction(cb, GTimers[i].Args, JSMakeUndefined());

      if GTimers[i].Repeats then
        GTimers[i].DueMS := nowTime + GTimers[i].DelayMS
      else
      begin
        GTimers[i].Active := False;
        JSReleaseValue(GTimers[i].Callback);
        for j := 0 to High(GTimers[i].Args) do
          JSReleaseValue(GTimers[i].Args[j]);
        SetLength(GTimers[i].Args, 0);
      end;
    end;
  end;
end;

procedure FloriaJSRegisterTimers(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;

  GSharedTimerHeap := AHeap;
  AEnv.Define('setTimeout', JSMakeFunction(AHeap.NewNativeFunction('setTimeout', @JSSetTimeout)));
  AEnv.Define('clearTimeout', JSMakeFunction(AHeap.NewNativeFunction('clearTimeout', @JSClearTimeout)));
  AEnv.Define('setInterval', JSMakeFunction(AHeap.NewNativeFunction('setInterval', @JSSetInterval)));
  AEnv.Define('clearInterval', JSMakeFunction(AHeap.NewNativeFunction('clearInterval', @JSClearTimeout)));
end;

initialization

finalization
  SetLength(GTimers, 0);

end.
