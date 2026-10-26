{ ************************************************************************** }
{                                                                          }
{   Floria JS — Benchmark Runner                                           }
{                                                                          }
{   Runs a named workload, repeats it, and reports the distribution of the  }
{   per-run times.                                                         }
{                                                                          }
{   Two decisions matter for trustworthy numbers:                          }
{                                                                          }
{   * Iterations are auto-calibrated so a single timed run lasts long       }
{     enough that timer granularity and scheduler jitter do not dominate.   }
{     A fixed iteration count silently measures noise when the workload is  }
{     fast.                                                                }
{   * Each run is timed separately and the median reported, not the total.  }
{     One outlier (a GC pass, a page fault) then cannot move the result.    }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.bench.runner;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, floria.bench.clock, floria.bench.stats;

type
  { One unit of work. APayload is whatever the caller passed to Run. }
  TBenchProc = procedure(APayload: Pointer);

  TBenchRunner = class
  private
    FSamples: Integer;
    FTargetMicros: Int64;
    FMaxIterations: Integer;
    FResults: array of TBenchSummary;
    FVerbose: Boolean;
  public
    constructor Create();

    { Runs AProc repeatedly and records the summary.

      AName is the label in the report. APayload is handed to AProc unchanged.
      The iteration count is calibrated first, so the caller never has to guess
      a count that is large enough to be meaningful. }
    procedure Run(const AName: string; AProc: TBenchProc;
      APayload: Pointer = nil; AOpsPerRun: Integer = 1);

    { Prints every recorded result as a table, plus a total. }
    procedure Report(const ATitle: string);

    { Writes the results as tab-separated lines, for comparing two runs. }
    procedure SaveToFile(const AFileName: string);

    { How many timed runs to take. More samples stabilise the median. }
    property SampleCount: Integer read FSamples write FSamples;
    property TargetMicros: Int64 read FTargetMicros write FTargetMicros;
    property MaxIterations: Integer read FMaxIterations write FMaxIterations;
    property Verbose: Boolean read FVerbose write FVerbose;
  end;

implementation

const
  { A timed run must exceed this so that a 1 us clock tick is not the signal. }
  MIN_TARGET_MICROS = 20000;

constructor TBenchRunner.Create();
begin
  inherited Create();
  { Samples must be numerous enough that the median is stable: at 15 the
    call benchmarks moved by 30% between runs, which makes the baseline
    useless for detecting anything smaller than a large regression. }
  FSamples := 31;
  FTargetMicros := 50000;
  FMaxIterations := 100000000;
  FVerbose := True;
end;

procedure TBenchRunner.Run(const AName: string; AProc: TBenchProc;
  APayload: Pointer; AOpsPerRun: Integer);
var
  iterations, i, j: Integer;
  start: Int64;
  elapsed, perIter: Int64;
  samples: TInt64Array;
  summary: TBenchSummary;
begin
  if AProc = nil then Exit;

  { Calibrate the *batch* so that one timed sample lasts about the target
    window. The batch is what gets timed; a single call is far too short to
    measure, and a workload that is itself slow needs a batch of one.

    The loop keeps growing the batch until the *measured* time clears the
    target. A workload faster than the clock tick reports 0 us, which the ratio
    step below cannot scale from, so the batch is multiplied instead. }
  iterations := 1;
  while True do
  begin
    start := BenchNowMicros();
    for i := 1 to iterations do
      AProc(APayload);
    elapsed := BenchElapsedMicros(start);

    if (elapsed >= FTargetMicros) or (iterations >= FMaxIterations) then
      Break;

    if elapsed = 0 then
      { Faster than the clock can resolve: grow the batch geometrically until
        it becomes measurable. }
      iterations := iterations * 8
    else
    begin
      { Scale by the observed ratio so the batch reaches the target in one or
        two rounds rather than one doubling per round.

        The ratio must be computed from the measured *total*, not from an
        integer microseconds-per-iteration: when a single iteration is faster
        than the clock tick that value truncates to 1 and the batch stops
        growing while the measurement stays unresolvable. }
      if elapsed < 1 then elapsed := 1;
      i := Integer((Int64(iterations) * FTargetMicros) div elapsed);
      if i < iterations * 2 then
        i := iterations * 2;
      if i > iterations * 16 then
        i := iterations * 16;
      iterations := i;
    end;
    if iterations > FMaxIterations then
      iterations := FMaxIterations;
  end;

  { Round the batch down to a power of two. Calibration lands on slightly
    different values each run (4 versus 3, say), and because the reported
    figure divides by the batch, that alone moved a benchmark by 20%. A power
    of two is stable across runs while still being large enough to time. }
  i := 1;
  while (i * 2 <= iterations) and (i * 2 <= FMaxIterations) do
    i := i * 2;
  iterations := i;

  { One warm-up pass so the calibration itself does not pollute the samples. }
  for i := 1 to iterations do
    AProc(APayload);

  { Each sample times the whole calibrated batch. Timing a single call would
    be below the clock resolution, and dividing that by the batch size would
    under-report the cost by exactly the batch factor.

    The batch is kept for the samples as well, so the per-operation figure is
    the same quantity in every run. Recalibrating per sample would make the
    divisor drift and the results incomparable between runs. }
  SetLength(samples, FSamples);
  for i := 0 to FSamples - 1 do
  begin
    start := BenchNowMicros();
    for j := 1 to iterations do
      AProc(APayload);
    samples[i] := BenchElapsedMicros(start);
  end;

  { A median at or below the clock tick means the batch is still too small to
    time; saying so is better than reporting a fabricated figure. }
  if FVerbose and (Summarise(AName, samples, iterations, AOpsPerRun).Median < 2) then
    WriteLn(Format('  note: "%s" is at the clock resolution (%d us); treat its ' +
      'per-op figure as an upper bound', [AName, BENCH_CLOCK_TICK_MICROS]));

  summary := Summarise(AName, samples, iterations, AOpsPerRun);
  SetLength(FResults, Length(FResults) + 1);
  FResults[High(FResults)] := summary;

  if FVerbose then
    WriteLn(FormatSummary(summary));
end;

procedure TBenchRunner.Report(const ATitle: string);
var
  i: Integer;
  total: Int64;
begin
  WriteLn();
  WriteLn(ATitle);
  WriteLn(StringOfChar('=', Length(ATitle)));
  WriteLn(SummaryHeader());
  total := 0;
  for i := 0 to High(FResults) do
  begin
    WriteLn(FormatSummary(FResults[i]));
    total := total + FResults[i].TotalMicros;
  end;
  WriteLn(StringOfChar('-', Length(SummaryHeader())));
  WriteLn(Format('%-30s %8s %11s %11s %11s %13s',
    ['total wall', '', FormatFloat('#,##0', total / 1000.0) + ' ms', '', '', '']));
end;

procedure TBenchRunner.SaveToFile(const AFileName: string);
var
  f: TextFile;
  i: Integer;
begin
  AssignFile(f, AFileName);
  Rewrite(f);
  try
    WriteLn(f, 'benchmark', #9, 'batch', #9, 'sample_ms', #9, 'p95_ms', #9,
      'us_per_op', #9, 'ops_per_run');
    for i := 0 to High(FResults) do
      WriteLn(f, FResults[i].Name, #9, FResults[i].Iterations, #9,
        FormatFloat('0.000', FResults[i].Median / 1000.0), #9,
        FormatFloat('0.000', FResults[i].P95 / 1000.0), #9,
        FormatFloat('0.0000', MicrosPerOp(FResults[i])), #9,
        FResults[i].OpsPerRun);
  finally
    CloseFile(f);
  end;
end;

end.
