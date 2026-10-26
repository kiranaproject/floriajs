{ ************************************************************************** }
{                                                                          }
{   Floria JS — Benchmark Statistics                                       }
{                                                                          }
{   Summarises a series of timing samples. A single sample is not enough:  }
{   the interesting number is the spread, because an optimisation that     }
{   helps the median but widens the tail is usually a regression for a UI  }
{   runtime that must hold a frame budget.                                 }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.bench.stats;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  TInt64Array = array of Int64;

  { A summary of one benchmark's samples, in microseconds. }
  TBenchSummary = record
    Name: string;
    { Batch size: how many times the workload ran inside one timed sample. }
    Iterations: Integer;
    { Logical operations inside one run of the workload, so that the per-op
      figure is comparable between workloads of different sizes. }
    OpsPerRun: Integer;
    Samples: Integer;
    Min, Max: Int64;
    Mean: Double;
    Median: Double;
    P95: Double;
    StdDev: Double;
    TotalMicros: Int64;
  end;

{ Sorts a copy of the samples and fills in the summary fields. }
function Summarise(const AName: string; ASamples: TInt64Array;
  AIterations: Integer; AOpsPerRun: Integer = 1): TBenchSummary;

{ Microseconds per iteration, which is the comparable figure across benchmarks. }
function MicrosPerOp(const ASummary: TBenchSummary): Double;

{ Formats one summary as an aligned table row. }
function FormatSummary(const ASummary: TBenchSummary): string;

{ The table header matching FormatSummary. }
function SummaryHeader(): string;

implementation

{ Sorts in place. The sample count is small (tens), so a simple insertion sort
  is clearer than pulling in a generic sort and costs nothing measurable. }
procedure SortInt64(var AValues: TInt64Array);
var
  i, j: Integer;
  key: Int64;
begin
  for i := 1 to High(AValues) do
  begin
    key := AValues[i];
    j := i - 1;
    while (j >= 0) and (AValues[j] > key) do
    begin
      AValues[j + 1] := AValues[j];
      Dec(j);
    end;
    AValues[j + 1] := key;
  end;
end;

function Summarise(const AName: string; ASamples: TInt64Array;
  AIterations: Integer; AOpsPerRun: Integer = 1): TBenchSummary;
var
  i, n: Integer;
  sorted: TInt64Array;
  sum, sqSum: Double;
  mean: Double;
begin
  Result := Default(TBenchSummary);
  Result.Name := AName;
  Result.Iterations := AIterations;
  if AOpsPerRun < 1 then AOpsPerRun := 1;
  Result.OpsPerRun := AOpsPerRun;
  n := Length(ASamples);
  Result.Samples := n;
  if n = 0 then Exit;

  sorted := Copy(ASamples);
  SortInt64(sorted);

  Result.Min := sorted[0];
  Result.Max := sorted[n - 1];

  sum := 0;
  for i := 0 to n - 1 do
  begin
    sum := sum + sorted[i];
    Result.TotalMicros := Result.TotalMicros + sorted[i];
  end;
  mean := sum / n;
  Result.Mean := mean;

  sqSum := 0;
  for i := 0 to n - 1 do
    sqSum := sqSum + Sqr(sorted[i] - mean);
  if n > 1 then
    Result.StdDev := Sqrt(sqSum / (n - 1))
  else
    Result.StdDev := 0;

  if Odd(n) then
    Result.Median := sorted[n div 2]
  else
    Result.Median := (sorted[n div 2 - 1] + sorted[n div 2]) / 2.0;

  { Nearest-rank 95th percentile, which needs no interpolation assumption. }
  i := Ceil(0.95 * n) - 1;
  if i < 0 then i := 0;
  if i > n - 1 then i := n - 1;
  Result.P95 := sorted[i];
end;

{ Microseconds per logical operation, i.e. per loop iteration or per call.

  The *minimum* sample is used, which is the standard estimator for a
  microbenchmark. Interference from the scheduler, page faults, or a collection
  pass can only ever make a run slower, so the fastest observed run is the
  closest estimate of the work itself. The median is reported alongside for
  context, but it moves with machine load: two identical runs of a call
  benchmark differed by 71% in median while their minima agreed. }
function MicrosPerOp(const ASummary: TBenchSummary): Double;
var
  total: Int64;
begin
  total := Int64(ASummary.Iterations) * Int64(ASummary.OpsPerRun);
  if total > 0 then
    Result := ASummary.Min / total
  else
    Result := 0;
end;

function SummaryHeader(): string;
begin
  { The millisecond columns describe one *sample*, which is one whole batch of
    `batch` runs. The us/op column already divides by the batch and by the
    operations in one run, so it is the comparable figure. }
  Result := Format('%-30s %8s %11s %11s %11s %13s',
    ['benchmark', 'batch', 'sample ms', 'p95 ms', 'us/op', 'ops/s']);
end;

function FormatSummary(const ASummary: TBenchSummary): string;
var
  perOp: Double;
  opsPerSec: Double;
begin
  perOp := MicrosPerOp(ASummary);
  if perOp > 0 then
    opsPerSec := 1000000.0 / perOp
  else
    opsPerSec := 0;
  Result := Format('%-30s %8d %11.3f %11.3f %11.4f %13.0f',
    [ASummary.Name, ASummary.Iterations, ASummary.Median / 1000.0,
     ASummary.P95 / 1000.0, perOp, opsPerSec]);
end;

end.
