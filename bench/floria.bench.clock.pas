{ ************************************************************************** }
{                                                                          }
{   Floria JS — Benchmark Clock                                            }
{                                                                          }
{   A monotonic microsecond clock for the benchmark suite. Wall-clock time  }
{   is unsuitable because it can jump; CLOCK_MONOTONIC cannot.             }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.bench.clock;

{$mode objfpc}{$H+}

interface

const
  { The smallest interval this clock can distinguish, in microseconds. A batch
    whose measured time is below this cannot be timed meaningfully. }
  BENCH_CLOCK_TICK_MICROS = 2;

{ Microseconds from an arbitrary fixed point. Only differences are meaningful. }
function BenchNowMicros(): Int64;

{ Microseconds elapsed since AStart. }
function BenchElapsedMicros(AStart: Int64): Int64;

implementation

uses
  Unix, BaseUnix, Linux;

function BenchNowMicros(): Int64;
var
  ts: Timespec;
begin
  if clock_gettime(CLOCK_MONOTONIC, @ts) <> 0 then
    Exit(0);
  Result := Int64(ts.tv_sec) * 1000000 + Int64(ts.tv_nsec) div 1000;
end;

function BenchElapsedMicros(AStart: Int64): Int64;
begin
  Result := BenchNowMicros() - AStart;
end;

end.
