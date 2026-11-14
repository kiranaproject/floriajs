{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Host Timers (setTimeout, clearTimeout)          }
{                                                                          }
{   Provides standard setTimeout, clearTimeout, setInterval, and           }
{   clearInterval timer scheduling primitives.                             }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                          }
{   SPDX-License-Identifier: MPL-2.0                                        }
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
    Running: Boolean;
  end;

  { One timer queue owned by one heap (and therefore by one context). Native
    timer functions are methods of this object, so they always schedule into
    the queue of the context that created them. }
  TFloriaJSTimerRegistry = class
  private
    FHeap: TFloriaJSHeap;
    FTimers: array of TFloriaJSTimer;
    FCount: Integer;
    FNextId: Integer;
    function CurrentMS(): Double;
    function AllocTimerId(): Integer;
    function FindIndex(AId: Integer): Integer;
    procedure ReleaseEntry(var AEntry: TFloriaJSTimer);
    function Schedule(const AArgs: array of TFloriaJSValue; ARepeats: Boolean): TFloriaJSValue;
  public
    constructor Create(AHeap: TFloriaJSHeap);
    destructor Destroy(); override;

    function SetTimeout(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function SetInterval(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function ClearTimer(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;

    procedure Register(AEnv: TFloriaJSEnvironment);
    procedure ProcessDue();
    function PendingCount(): Integer;
    function HasPending(): Boolean;
    { -1 when no timer is pending, 0 when a timer is already due, otherwise
      the whole-millisecond delay to the next due timer. }
    function NextDelayMS(): Integer;
    procedure ClearAll();
  end;

procedure FloriaJSRegisterTimers(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
procedure FloriaJSProcessTimers(AHeap: TFloriaJSHeap);

implementation

constructor TFloriaJSTimerRegistry.Create(AHeap: TFloriaJSHeap);
begin
  inherited Create();
  FHeap := AHeap;
  FCount := 0;
  FNextId := 1;
  SetLength(FTimers, 0);
end;

destructor TFloriaJSTimerRegistry.Destroy();
begin
  ClearAll();
  inherited Destroy();
end;

function TFloriaJSTimerRegistry.CurrentMS(): Double;
begin
  Result := (Now() - 25569.0) * 86400000.0;
end;

function TFloriaJSTimerRegistry.AllocTimerId(): Integer;
begin
  Result := FNextId;
  Inc(FNextId);
  if FNextId < 1 then
    FNextId := 1;
end;

function TFloriaJSTimerRegistry.FindIndex(AId: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to FCount - 1 do
    if FTimers[i].Id = AId then
      Exit(i);
end;

procedure TFloriaJSTimerRegistry.ReleaseEntry(var AEntry: TFloriaJSTimer);
var
  i: Integer;
begin
  JSReleaseValue(AEntry.Callback);
  for i := 0 to High(AEntry.Args) do
    JSReleaseValue(AEntry.Args[i]);
  AEntry.Callback := JSMakeUndefined();
  SetLength(AEntry.Args, 0);
  AEntry.Active := False;
end;

function TFloriaJSTimerRegistry.Schedule(const AArgs: array of TFloriaJSValue;
  ARepeats: Boolean): TFloriaJSValue;
var
  id, i, argCount: Integer;
  delay: Double;
  entry: TFloriaJSTimer;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsFunction() then
    Exit(JSMakeNumber(0));

  delay := 0.0;
  if Length(AArgs) > 1 then
    delay := AArgs[1].ToNumber();
  { NaN and negative delays are treated as zero, matching timer scheduling
    rather than leaving a timer that can never become due. }
  if (delay <> delay) or (delay < 0.0) then
    delay := 0.0;

  id := AllocTimerId();

  entry := Default(TFloriaJSTimer);
  entry.Id := id;
  entry.Callback := AArgs[0];
  JSRetainValue(AArgs[0]);
  entry.DelayMS := delay;
  entry.DueMS := CurrentMS() + delay;
  entry.Active := True;
  entry.Repeats := ARepeats;
  entry.Running := False;

  argCount := Length(AArgs) - 2;
  if argCount > 0 then
  begin
    SetLength(entry.Args, argCount);
    for i := 0 to argCount - 1 do
    begin
      entry.Args[i] := AArgs[i + 2];
      JSRetainValue(AArgs[i + 2]);
    end;
  end
  else
    SetLength(entry.Args, 0);

  if FCount >= Length(FTimers) then
    SetLength(FTimers, (FCount + 1) * 2);
  FTimers[FCount] := entry;
  Inc(FCount);

  Result := JSMakeNumber(id);
end;

function TFloriaJSTimerRegistry.SetTimeout(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := Schedule(AArgs, False);
end;

function TFloriaJSTimerRegistry.SetInterval(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := Schedule(AArgs, True);
end;

function TFloriaJSTimerRegistry.ClearTimer(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  id, index: Integer;
begin
  if Length(AArgs) = 0 then
    Exit(JSMakeUndefined());
  id := Round(AArgs[0].ToNumber());
  index := FindIndex(id);
  if index >= 0 then
  begin
    FTimers[index].Active := False;
    { A callback that is already running must not have its argument values
      released underneath it. ProcessDue releases them after invocation. }
    if not FTimers[index].Running then
      ReleaseEntry(FTimers[index]);
  end;
  Result := JSMakeUndefined();
end;

procedure TFloriaJSTimerRegistry.ProcessDue();
var
  nowTime: Double;
  i, snapshot: Integer;
  callback: TFloriaJSValue;
  callbackArgs: array of TFloriaJSValue;
begin
  nowTime := CurrentMS();
  { Timers scheduled by a callback are handled by the next pump pass. A
    fixed snapshot also keeps a zero-delay callback chain from trapping the
    whole pump in one invocation. }
  snapshot := FCount;
  i := 0;
  while i < snapshot do
  begin
    if FTimers[i].Active and (nowTime >= FTimers[i].DueMS) then
    begin
      callback := FTimers[i].Callback;
      callbackArgs := FTimers[i].Args;
      FTimers[i].Running := True;
      { A non-repeating timer is removed from the active set before its
        callback runs, so a nested pump or a clearTimeout() call cannot make
        it execute twice. }
      if not FTimers[i].Repeats then
        FTimers[i].Active := False;
      try
        if (FHeap <> nil) and callback.IsFunction() then
          FHeap.InvokeFunction(callback, callbackArgs, JSMakeUndefined());
      finally
        FTimers[i].Running := False;
        if FTimers[i].Repeats then
        begin
          if FTimers[i].Active then
            FTimers[i].DueMS := CurrentMS() + FTimers[i].DelayMS
          else
            ReleaseEntry(FTimers[i]);
        end
        else
          ReleaseEntry(FTimers[i]);
      end;
    end;
    Inc(i);
  end;

  { Drop inactive entries after the pass. Timers scheduled by callbacks remain
    active and are retained in their scheduling order. }
  snapshot := 0;
  for i := 0 to FCount - 1 do
    if FTimers[i].Active then
    begin
      if snapshot <> i then
        FTimers[snapshot] := FTimers[i];
      Inc(snapshot);
    end;
  FCount := snapshot;
end;

function TFloriaJSTimerRegistry.PendingCount(): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FCount - 1 do
    if FTimers[i].Active then
      Inc(Result);
end;

function TFloriaJSTimerRegistry.HasPending(): Boolean;
begin
  Result := PendingCount() > 0;
end;

function TFloriaJSTimerRegistry.NextDelayMS(): Integer;
var
  i: Integer;
  delay: Double;
  best: Double;
begin
  best := 0.0;
  Result := -1;
  for i := 0 to FCount - 1 do
  begin
    if not FTimers[i].Active then
      Continue;
    delay := FTimers[i].DueMS - CurrentMS();
    if delay <= 0.0 then
      Exit(0);
    if (Result < 0) or (delay < best) then
    begin
      best := delay;
      Result := Round(delay);
      if Result < 1 then
        Result := 1;
    end;
  end;
end;

procedure TFloriaJSTimerRegistry.ClearAll();
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
    ReleaseEntry(FTimers[i]);
  SetLength(FTimers, 0);
  FCount := 0;
end;

procedure TFloriaJSTimerRegistry.Register(AEnv: TFloriaJSEnvironment);
begin
  if (AEnv = nil) or (FHeap = nil) then
    Exit;
  AEnv.Define('setTimeout', JSMakeFunction(
    FHeap.NewNativeMethod('setTimeout', @Self.SetTimeout)));
  AEnv.Define('clearTimeout', JSMakeFunction(
    FHeap.NewNativeMethod('clearTimeout', @Self.ClearTimer)));
  AEnv.Define('setInterval', JSMakeFunction(
    FHeap.NewNativeMethod('setInterval', @Self.SetInterval)));
  AEnv.Define('clearInterval', JSMakeFunction(
    FHeap.NewNativeMethod('clearInterval', @Self.ClearTimer)));
end;

function RegistryOf(AHeap: TFloriaJSHeap): TFloriaJSTimerRegistry;
begin
  Result := nil;
  if (AHeap <> nil) and (AHeap.TimerRegistry <> nil) then
    Result := TFloriaJSTimerRegistry(AHeap.TimerRegistry);
end;

procedure FloriaJSRegisterTimers(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  registry: TFloriaJSTimerRegistry;
begin
  if (AEnv = nil) or (AHeap = nil) then
    Exit;

  registry := RegistryOf(AHeap);
  if registry = nil then
  begin
    registry := TFloriaJSTimerRegistry.Create(AHeap);
    AHeap.TimerRegistry := registry;
  end;
  registry.Register(AEnv);
end;

procedure FloriaJSProcessTimers(AHeap: TFloriaJSHeap);
var
  registry: TFloriaJSTimerRegistry;
begin
  registry := RegistryOf(AHeap);
  if registry <> nil then
    registry.ProcessDue();
end;

end.
