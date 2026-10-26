{ ************************************************************************** }
{                                                                          }
{   Floria JS — VM Benchmarks                                              }
{                                                                          }
{   Measures the four workloads P3-01 names: loops, calls, property access, }
{   and string building. Each is compiled once and executed many times, so  }
{   the numbers describe the interpreter and not the parser.               }
{                                                                          }
{   Usage:  bench_js [--out FILE]                                          }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

program bench_js;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, floriajs,
  floria.bench.clock, floria.bench.stats, floria.bench.runner;

type
  { A compiled workload. The bytecode is produced once by Compile, then executed
    by every timed iteration. }
  TWorkload = record
    Name: string;
    Source: string;
    { Logical operations per run, so ns/op is comparable across workloads. }
    OpsPerRun: Integer;
    Code: TFloriaJSBytecode;
    Engine: TFloriaJSEngine;
  end;
  PWorkload = ^TWorkload;

var
  GWorkloads: array of TWorkload;
  GOutFile: string = '';

{ Executes one compiled workload.

  The heap is collected first, exactly as TFloriaJSContext.Execute does before
  running a script. Without it each run leaves its garbage behind, the heap
  grows by about a thousand objects per run, and later samples are measurably
  slower than earlier ones — which shows up as run-to-run instability rather
  than as a leak. }
procedure RunWorkload(APayload: Pointer);
var
  w: PWorkload;
  ctx: TFloriaJSContext;
begin
  w := PWorkload(APayload);
  if (w = nil) or (w^.Code = nil) or (w^.Engine = nil) then Exit;
  ctx := w^.Engine.DefaultContext;
  ctx.Heap.Collect();
  ctx.VM.Execute(w^.Code, ctx.GlobalEnv);
end;

{ Compiles ASource for AName and appends it to the workload list.

  Compilation is done here, outside any timed region, because the benchmark is
  about execution cost. A fresh engine per workload keeps one workload's globals
  from affecting another's timings. }
procedure AddWorkload(const AName, ASource: string; AOpsPerRun: Integer);
var
  engine: TFloriaJSEngine;
  lexer: TFloriaJSLexer;
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  code: TFloriaJSBytecode;
begin
  engine := TFloriaJSEngine.Create();
  lexer := TFloriaJSLexer.Create(ASource);
  parser := TFloriaJSParser.Create(lexer);
  try
    prog := parser.ParseProgram();
    if parser.HasErrors() then
      raise Exception.Create('benchmark "' + AName + '" failed to parse: ' + parser.GetError(0));
    code := engine.DefaultContext.Compiler.CompileProgram(prog);
    code.Retain();
  finally
    prog.Free();
    parser.Free();
    lexer.Free();
  end;

  SetLength(GWorkloads, Length(GWorkloads) + 1);
  GWorkloads[High(GWorkloads)].Name := AName;
  GWorkloads[High(GWorkloads)].Source := ASource;
  GWorkloads[High(GWorkloads)].OpsPerRun := AOpsPerRun;
  GWorkloads[High(GWorkloads)].Code := code;
  GWorkloads[High(GWorkloads)].Engine := engine;
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

procedure DefineWorkloads();
begin
  { Loops: a counting loop, which is the cheapest possible dispatch path and so
    exposes raw per-instruction overhead. }
  AddWorkload('loop/count-10k',
    'var s = 0; for (var i = 0; i < 10000; i++) { s = s + 1; } s;', 10000);

  { Loops: nested, to show whether the outer loop's cost is amortised. }
  AddWorkload('loop/nested-100x100',
    'var s = 0; for (var i = 0; i < 100; i++) { for (var j = 0; j < 100; j++) { s = s + 1; } } s;', 10000);

  { Loops: while, which has no increment clause and a different dispatch shape. }
  AddWorkload('loop/while-10k',
    'var i = 0; var s = 0; while (i < 10000) { s = s + 1; i = i + 1; } s;', 10000);

  { Calls: a plain function called in a loop. Measures frame setup and teardown. }
  AddWorkload('call/plain-1k',
    'function f(a) { return a + 1; } var s = 0;' +
    'for (var i = 0; i < 1000; i++) { s = f(s); } s;', 1000);

  { Calls: no arguments, to separate argument marshalling from frame cost. }
  AddWorkload('call/noargs-1k',
    'var n = 0; function f() { n = n + 1; return n; }' +
    'for (var i = 0; i < 1000; i++) { f(); } n;', 1000);

  { Calls: recursion, which also exercises the frame stack growth path. }
  AddWorkload('call/recursive-fib-16',
    'function fib(n) { if (n < 2) { return n; } return fib(n - 1) + fib(n - 2); } fib(16);', 3193);

  { Property access: reads and writes on a small object. }
  AddWorkload('prop/read-write-5k',
    'var o = {a: 0}; for (var i = 0; i < 5000; i++) { o.a = o.a + 1; } o.a;', 5000);

  { Property access: computed keys, which take the slower key path. }
  AddWorkload('prop/computed-2k',
    'var o = {}; var k = "v"; for (var i = 0; i < 2000; i++) { o[k] = i; } o[k];', 2000);

  { Property access: array element writes, which is the hot path for UI state. }
  AddWorkload('prop/array-write-5k',
    'var a = []; for (var i = 0; i < 5000; i++) { a[i] = i; } a.length;', 5000);

  { Strings: concatenation in a loop. This allocates, so it also measures the
    heap's contribution to a string-heavy workload. }
  AddWorkload('string/concat-2k',
    'var s = ""; for (var i = 0; i < 2000; i++) { s = s + "x"; } s.length;', 2000);

  { Arithmetic: a tight numeric loop, to isolate the operator dispatch path. }
  AddWorkload('arith/mixed-10k',
    'var x = 1; for (var i = 0; i < 10000; i++) { x = (x * 3 + 7) % 1000; } x;', 10000);

  { Objects: allocating many short-lived objects, which measures allocation and
    gives a baseline for collection cost. }
  AddWorkload('object/alloc-2k',
    'var n = 0; for (var i = 0; i < 2000; i++) { var o = {v: i}; n = n + o.v; } n;', 2000);
end;

var
  runner: TBenchRunner;
  i: Integer;
  start: Int64;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
  ParseArgs();
  DefineWorkloads();

  WriteLn('Floria JS benchmark — VM workloads');
  WriteLn('version: ', FLORIA_JS_VERSION_STRING);
  WriteLn();

  runner := TBenchRunner.Create();
  try
    start := BenchNowMicros();
    WriteLn(SummaryHeader());
    for i := 0 to High(GWorkloads) do
      runner.Run(GWorkloads[i].Name, @RunWorkload, @GWorkloads[i],
        GWorkloads[i].OpsPerRun);
    runner.Report('Summary (VM)');
    WriteLn('wall clock: ', FormatFloat('#,##0.0', BenchElapsedMicros(start) / 1000.0), ' ms');
    if GOutFile <> '' then
    begin
      runner.SaveToFile(GOutFile);
      WriteLn('results written to ', GOutFile);
    end;
  finally
    runner.Free();
    for i := 0 to High(GWorkloads) do
    begin
      if GWorkloads[i].Code <> nil then
        GWorkloads[i].Code.Release();
      GWorkloads[i].Engine.Free();
    end;
  end;
end.
