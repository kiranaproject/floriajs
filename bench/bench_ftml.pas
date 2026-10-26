{ ************************************************************************** }
{                                                                          }
{   Floria JS — FTML Reactive Binding Benchmarks                           }
{                                                                          }
{   P3-05 targets "thousands of reactive updates per frame", so the figure  }
{   that matters is the cost of one property write propagating through a    }
{   binding graph. This measures exactly that: how long a single write to   }
{   a bound property takes, and how the cost scales with the number of      }
{   bindings that depend on it.                                            }
{                                                                          }
{   Usage:  bench_ftml [--out FILE]                                        }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

program bench_ftml;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, floriajs,
  floria.bench.clock, floria.bench.stats, floria.bench.runner;

type
  { One loaded document plus the items the benchmark drives.

    `Leaf` is the bound descendant. `Sink` is a second, unbound item used to
    measure the floor cost of a write: writing to the bound leaf itself would
    replace its binding, so the two probes must not share an item. }
  TFTMLFixture = record
    Engine: TFloriaFTMLEngine;
    Root: TFloriaFTMLItem;
    Leaf: TFloriaFTMLItem;
    Sink: TFloriaFTMLItem;
  end;
  PFTMLFixture = ^TFTMLFixture;

var
  GFanout: PFTMLFixture;
  GDeep: PFTMLFixture;
  GOutFile: string = '';
  GWidth: Double = 100;

{ Builds a document whose width is bound to the root, then returns it loaded. }
function LoadFixture(const AFTML: string): TFTMLFixture;
begin
  Result.Engine := TFloriaFTMLEngine.Create();
  Result.Root := Result.Engine.LoadString(AFTML);
  if Result.Root = nil then
    raise Exception.Create('FTML failed to load: ' + Result.Engine.LastError);
  Result.Leaf := Result.Engine.FindItemById('leaf');
  if Result.Leaf = nil then
    raise Exception.Create('FTML fixture is missing the item with id "leaf"');
  Result.Sink := Result.Engine.FindItemById('sink');
  if Result.Sink = nil then
    raise Exception.Create('FTML fixture is missing the item with id "sink"');
end;

procedure FreeFixture(var AFixture: TFTMLFixture);
begin
  AFixture.Engine.Free();
  AFixture.Engine := nil;
  AFixture.Root := nil;
  AFixture.Leaf := nil;
  AFixture.Sink := nil;
end;

{ One write to a bound property, which must propagate to the leaf. }
procedure WriteBoundWidth(APayload: Pointer);
var
  f: PFTMLFixture;
begin
  f := PFTMLFixture(APayload);
  if (f = nil) or (f^.Root = nil) then Exit;
  GWidth := GWidth + 1;
  if GWidth > 10000 then GWidth := 100;
  f^.Root.Width := GWidth;
end;

{ One write to an item that nothing depends on: the floor cost of a write. }
procedure WriteUnboundLeaf(APayload: Pointer);
var
  f: PFTMLFixture;
begin
  f := PFTMLFixture(APayload);
  if (f = nil) or (f^.Sink = nil) then Exit;
  { The value must change on every write. Writing the same value short-circuits
    the update path and measures roughly a seventh of the real cost. }
  GWidth := GWidth + 1;
  if GWidth > 100000 then GWidth := 1;
  f^.Sink.Width := GWidth;
end;

procedure ParseArgs();
var
  i: Integer;
begin
  i := 1;
  while i <= ParamCount() do
  begin
    if (ParamStr(i) = '--out') and (i < ParamCount()) then
    begin
      GOutFile := ParamStr(i + 1);
      Inc(i);
    end;
    Inc(i);
  end;
end;

const
  { One bound child: root.width flows to leaf.width through an expression. }
  FTML_SHALLOW =
    'Rectangle {' + LineEnding +
    '  id: root' + LineEnding +
    '  width: 100;' + LineEnding +
    '  Rectangle {' + LineEnding +
    '    id: leaf' + LineEnding +
    '    width: root.width + 10;' + LineEnding +
    '  }' + LineEnding +
    '  Rectangle {' + LineEnding +
    '    id: sink' + LineEnding +
    '    width: 1;' + LineEnding +
    '  }' + LineEnding +
    '}' + LineEnding;

  { A deeper chain, to show whether propagation cost compounds with depth. }
  FTML_DEEP =
    'Rectangle {' + LineEnding +
    '  id: root' + LineEnding +
    '  width: 100;' + LineEnding +
    '  Rectangle {' + LineEnding +
    '    id: a' + LineEnding +
    '    width: root.width + 1;' + LineEnding +
    '    Rectangle {' + LineEnding +
    '      id: b' + LineEnding +
    '      width: a.width + 1;' + LineEnding +
    '      Rectangle {' + LineEnding +
    '        id: leaf' + LineEnding +
    '        width: b.width + 1;' + LineEnding +
    '      }' + LineEnding +
    '    }' + LineEnding +
    '  }' + LineEnding +
    '  Rectangle {' + LineEnding +
    '    id: sink' + LineEnding +
    '    width: 1;' + LineEnding +
    '  }' + LineEnding +
    '}' + LineEnding;

var
  runner: TBenchRunner;
  shallow, deep: TFTMLFixture;
  start: Int64;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
  ParseArgs();

  WriteLn('Floria JS benchmark — FTML reactive bindings');
  WriteLn('version: ', FLORIA_JS_VERSION_STRING);
  WriteLn();

  shallow := LoadFixture(FTML_SHALLOW);
  deep := LoadFixture(FTML_DEEP);
  GFanout := @shallow;
  GDeep := @deep;

  runner := TBenchRunner.Create();
  try
    start := BenchNowMicros();
    WriteLn(SummaryHeader());

    { The cost of a write that nothing depends on. }
    runner.Run('binding/unbound-write', @WriteUnboundLeaf, @shallow, 1);

    { A write that propagates one level through an expression. }
    runner.Run('binding/bound-1-level', @WriteBoundWidth, @shallow, 1);

    { A write that propagates three levels, to expose compounding cost. }
    runner.Run('binding/bound-3-levels', @WriteBoundWidth, @deep, 1);

    runner.Report('Summary (FTML)');
    WriteLn('wall clock: ', FormatFloat('#,##0.0', BenchElapsedMicros(start) / 1000.0), ' ms');

    { Correctness check: the binding must actually have propagated. Without
      this the timings could describe a no-op. }
    WriteLn();
    shallow.Root.Width := 250;
    WriteLn('binding check: root.width=250 -> leaf.width=',
      FormatFloat('0', shallow.Leaf.Width), ' (expected 260)');
    if Trunc(shallow.Leaf.Width) <> 260 then
      WriteLn('WARNING: the binding did not propagate; timings are not meaningful');

    if GOutFile <> '' then
    begin
      runner.SaveToFile(GOutFile);
      WriteLn('results written to ', GOutFile);
    end;
  finally
    runner.Free();
    FreeFixture(shallow);
    FreeFixture(deep);
  end;
end.
