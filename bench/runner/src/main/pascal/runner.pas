{ ************************************************************************** }
{                                                                          }
{   Floria JS — File Benchmark Runner                                      }
{                                                                          }
{   Loads each workload from a .js file, runs it, and reports the time.    }
{                                                                          }
{   This exists so the interpreter is exercised the way a host application }
{   uses it — read a file, execute it — rather than through an in-process   }
{   string built for the occasion. The same .js files are run by Node in    }
{   `bench/node/run_node.js`, which is what makes the two comparable.       }
{                                                                          }
{   Usage:  runner <workload.js> [workload.js ...]                          }
{           runner --dir <directory>                                        }
{                                                                          }
{   Output is one tab-separated line per workload:                         }
{     name <TAB> runs <TAB> total_us <TAB> per_run_us <TAB> result          }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

program runner;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, Unix, BaseUnix, Linux, floriajs;

const
  // Each workload runs this many times and the *fastest* run is reported.
  // Interference can only add time, so the minimum is the closest estimate of
  // the work itself.
  RUNS = 41;

type
  TWorkload = record
    Name: string;
    Source: string;
  end;
  TWorkloads = array of TWorkload;

// Microseconds from CLOCK_MONOTONIC.
//
// `Now()` is unsuitable: it has millisecond resolution and can jump when the
// wall clock is adjusted, which is far too coarse for a microbenchmark.
function NowMicros(): Int64;
var
  ts: Timespec;
begin
  if clock_gettime(CLOCK_MONOTONIC, @ts) <> 0 then
    Exit(0);
  Result := Int64(ts.tv_sec) * 1000000 + Int64(ts.tv_nsec) div 1000;
end;

procedure AddFile(var AList: TWorkloads; const APath: string);
var
  sl: TStringList;
  n: Integer;
begin
  sl := TStringList.Create();
  try
    sl.LoadFromFile(APath);
    n := Length(AList);
    SetLength(AList, n + 1);
    AList[n].Name := ChangeFileExt(ExtractFileName(APath), '');
    AList[n].Source := sl.Text;
  finally
    sl.Free();
  end;
end;

procedure CollectFiles(const ADir: string; var AList: TWorkloads);
var
  sr: TSearchRec;
  files: TStringList;
  i: Integer;
begin
  files := TStringList.Create();
  try
    if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*.js', faAnyFile, sr) = 0 then
    begin
      repeat
        if (sr.Name <> '.') and (sr.Name <> '..') then
          files.Add(IncludeTrailingPathDelimiter(ADir) + sr.Name);
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    files.Sort();
    for i := 0 to files.Count - 1 do
      AddFile(AList, files[i]);
  finally
    files.Free();
  end;
end;

// Runs ASource once and returns its wall time in microseconds.
//
// A fresh engine per measurement is deliberate: it keeps one workload's globals
// and heap from affecting another's timing, and it matches what Node does when
// each workload is evaluated in its own context.
function TimeOnce(const ASource: string; out AResult: string; out AOk: Boolean): Int64;
var
  engine: TFloriaJSEngine;
  res: TFloriaJSResult;
  start: Int64;
begin
  engine := TFloriaJSEngine.Create();
  try
    start := NowMicros();
    res := engine.Execute(ASource);
    Result := NowMicros() - start;
    AOk := res.Success;
    if res.Success then
      AResult := res.StringValue
    else
      AResult := 'ERROR: ' + res.ErrorMessage;
  finally
    engine.Free();
  end;
end;

var
  workloads: TWorkloads;
  i, k: Integer;
  best, elapsed, total: Int64;
  resultText: string;
  ok: Boolean;
  args: TStringList;
  n: Integer;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);

  args := TStringList.Create();
  try
    for n := 1 to ParamCount() do
      args.Add(ParamStr(n));

    if args.Count = 0 then
    begin
      WriteLn(StdErr, 'usage: runner <workload.js> ... | --dir <directory>');
      Halt(2);
    end;

    if (args.Count = 2) and (args[0] = '--dir') then
      CollectFiles(args[1], workloads)
    else
      for n := 0 to args.Count - 1 do
        AddFile(workloads, args[n]);

    if Length(workloads) = 0 then
    begin
      WriteLn(StdErr, 'no workloads found');
      Halt(2);
    end;

    // Header, so a reader knows what the columns are without the docs.
    WriteLn('name', #9, 'runs', #9, 'total_us', #9, 'per_run_us', #9, 'result');

    for i := 0 to High(workloads) do
    begin
      // One warm-up run: the first execution pays for lazily created
      // prototypes and other one-time setup that later runs do not.
      TimeOnce(workloads[i].Source, resultText, ok);

      best := High(Int64);
      total := 0;
      for k := 1 to RUNS do
      begin
        elapsed := TimeOnce(workloads[i].Source, resultText, ok);
        total := total + elapsed;
        if elapsed < best then
          best := elapsed;
      end;

      WriteLn(workloads[i].Name, #9, RUNS, #9, total, #9, best, #9, resultText);
    end;
  finally
    args.Free();
  end;
end.
