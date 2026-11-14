{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Engine & Execution Context                      }
{                                                                          }
{   Provides the core JavaScript runtime, execution context, heap, and     }
{   script evaluation engine for the Floria Toolkit ecosystem.             }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.core;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, floria.js.types, floria.js.ast, floria.js.parser,
  floria.js.value, floria.js.env, floria.js.stdlib, floria.js.timers,
  floria.js.bytecode, floria.js.vm, floria.js.compiler;

type
  { Forward Declarations }
  TFloriaJSEngine = class;
  TFloriaJSContext = class;

  { TFloriaJSContext — Execution context for evaluating scripts }
  TFloriaJSContext = class
  private
    FEngine: TFloriaJSEngine;
    FName: string;
    FHeap: TFloriaJSHeap;
    FGlobalEnv: TFloriaJSEnvironment;
    FVM: TFloriaJSVM;
    FCompiler: TFloriaJSCompiler;
    FOutput: TStringList;
    FGlobalObject: TFloriaJSObject;

    procedure InitContext();
    function  EvaluateScript(const AScript: string): TFloriaJSValue;
    function  GetTimerRegistry(): TFloriaJSTimerRegistry;
  public
    constructor Create(AEngine: TFloriaJSEngine; const AName: string = 'global');
    destructor Destroy(); override;

    procedure SetVariable(const AKey, AValue: string);
    function  GetVariable(const AKey: string): string;
    function  HasVariable(const AKey: string): Boolean;

    procedure SetGlobal(const AName: string; const AValue: TFloriaJSValue);
    function  GetGlobal(const AName: string): TFloriaJSValue;
    procedure RegisterFunction(const AName: string; AProc: TFloriaJSNativeProc);
    procedure RegisterMethod(const AName: string; AMethod: TFloriaJSNativeMethod);

    function  Evaluate(const AScript: string): TFloriaJSResult; virtual;
    { Executes once and returns phase-aware diagnostics without changing the
      legacy result or its error strings. }
    function  EvaluateDetailed(const AScript: string; const ASourceName: string = ''): TFloriaJSDiagnosticResult;
    { Runs the contents of a JavaScript file. A missing or unreadable file is
      reported as a failed result rather than an exception, so a host can show
      the error. }
    function  EvaluateFile(const AFileName: string): TFloriaJSResult; virtual;
    function  EvaluateFileDetailed(const AFileName: string): TFloriaJSDiagnosticResult;
    function  EvaluateValue(const AScript: string): TFloriaJSValue; virtual;
    { Evaluates source from a native callback without running heap collection
      or draining Promise jobs. This is the re-entrant path used by
      `$262.evalScript`: the caller's VM stack/environment may still hold live
      values. Parse and compile errors are thrown as JavaScript SyntaxError;
      runtime throws propagate unchanged. }
    function  EvaluateReentrant(const AScript: string): TFloriaJSValue; virtual;
    function  Call(const AFuncName: string; const AArgs: array of TFloriaJSValue): TFloriaJSValue; virtual;

    { Gives a value that was handed out back to the runtime. The object the
      value points at becomes eligible for reclamation once nothing refers to
      it any more. }
    procedure ReleaseValue(const AValue: TFloriaJSValue); virtual;

    { Runs all already-queued Promise jobs, including jobs queued by other
      jobs, until the microtask queue is empty. }
    procedure DrainPromiseJobs();
    { Executes every due timer in this context, then drains the Promise jobs
      those callbacks queued. }
    procedure PumpTimers();
    function  HasPendingTimers(): Boolean;
    function  PendingTimerCount(): Integer;
    { -1 when no timer is pending, 0 when one is due, otherwise milliseconds
      to the nearest due timer. }
    function  NextTimerDelayMS(): Integer;
    function  HasPendingWork(): Boolean;

    procedure Reset(); virtual;

    property Engine: TFloriaJSEngine read FEngine;
    property Name: string read FName write FName;
    property Heap: TFloriaJSHeap read FHeap;
    property GlobalEnv: TFloriaJSEnvironment read FGlobalEnv;
    property VM: TFloriaJSVM read FVM;
    property Compiler: TFloriaJSCompiler read FCompiler;
    property Output: TStringList read FOutput;
  end;

  { TFloriaJSEngine — Main JavaScript Runtime Engine }
  TFloriaJSEngine = class
  private
    FInitialized: Boolean;
    FContexts: TFPList;
    FDefaultContext: TFloriaJSContext;
    FMemoryLimit: NativeUInt;
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Initialize(); virtual;
    function  CreateContext(const AName: string = ''): TFloriaJSContext;
    procedure DestroyContext(AContext: TFloriaJSContext);

    function  Execute(const AScript: string): TFloriaJSResult; virtual;
    function  ExecuteDetailed(const AScript: string; const ASourceName: string = ''): TFloriaJSDiagnosticResult;
    { Runs the contents of a JavaScript file through the default context. }
    function  ExecuteFile(const AFileName: string): TFloriaJSResult; virtual;
    function  ExecuteFileDetailed(const AFileName: string): TFloriaJSDiagnosticResult;
    function  ExecuteValue(const AScript: string): TFloriaJSValue; virtual;
    procedure ReleaseValue(const AValue: TFloriaJSValue); virtual;
    procedure RegisterFunction(const AName: string; AProc: TFloriaJSNativeProc);

    property Initialized: Boolean read FInitialized;
    property DefaultContext: TFloriaJSContext read FDefaultContext;
    property MemoryLimit: NativeUInt read FMemoryLimit write FMemoryLimit;
  end;

implementation

type
  { Internal exception carrying structured parser location without changing
    the legacy parser error strings exposed by existing APIs. }
  EFloriaJSParseError = class(Exception)
  private
    FLine: Integer;
    FColumn: Integer;
  public
    constructor Create(const AMessage: string; ALine, AColumn: Integer);
    property Line: Integer read FLine;
    property Column: Integer read FColumn;
  end;

constructor EFloriaJSParseError.Create(const AMessage: string; ALine, AColumn: Integer);
begin
  inherited Create(AMessage);
  FLine := ALine;
  FColumn := AColumn;
end;

procedure AssignDiagnostic(var ADiagnostic: TFloriaJSDiagnosticResult;
  const ABaseResult: TFloriaJSResult; AKind: TFloriaJSDiagnosticKind;
  const ASourceName, AErrorName, AMessage, AHostExceptionClass: string;
  ALine: Integer = 0; AColumn: Integer = 0);
begin
  ADiagnostic.Result := ABaseResult;
  ADiagnostic.Kind := AKind;
  ADiagnostic.ErrorName := AErrorName;
  ADiagnostic.Message := AMessage;
  ADiagnostic.SourceName := ASourceName;
  ADiagnostic.Line := ALine;
  ADiagnostic.Column := AColumn;
  ADiagnostic.HostExceptionClass := AHostExceptionClass;
end;

{ TFloriaJSContext }

constructor TFloriaJSContext.Create(AEngine: TFloriaJSEngine; const AName: string = 'global');
begin
  inherited Create();
  FEngine := AEngine;
  FName := AName;
  FOutput := TStringList.Create();
  FHeap := TFloriaJSHeap.Create();
  FGlobalEnv := TFloriaJSEnvironment(FHeap.TrackEnvironment(TFloriaJSEnvironment.Create(nil, FHeap)));
  FVM := TFloriaJSVM.Create(FHeap);
  FVM.GlobalEnv := FGlobalEnv;
  FCompiler := TFloriaJSCompiler.Create();

  InitContext();
end;

destructor TFloriaJSContext.Destroy();
begin
  FreeAndNil(FCompiler);
  FreeAndNil(FVM);
  FreeAndNil(FHeap);
  FGlobalEnv := nil;
  FreeAndNil(FOutput);
  inherited Destroy();
end;

procedure TFloriaJSContext.InitContext();
begin
  { The global object is live: global var/function bindings are its
    properties, and the root environment delegates to it. }
  FGlobalObject := FHeap.NewObject(FHeap.GetObjectPrototype());
  FGlobalObject.Pin();
  FGlobalEnv.DelegateObject := FGlobalObject;
  FHeap.RealmGlobal := FGlobalObject;

  FloriaJSRegisterStdLib(FGlobalEnv, FHeap, FOutput);

  FGlobalObject.SetPropertyNonEnumerable('globalThis', JSMakeObject(FGlobalObject));
  if FVM <> nil then
    FVM.GlobalEnv := FGlobalEnv;
end;

procedure TFloriaJSContext.SetVariable(const AKey, AValue: string);
begin
  SetGlobal(AKey, JSMakeString(AValue));
end;

function TFloriaJSContext.GetVariable(const AKey: string): string;
var
  v: TFloriaJSValue;
begin
  if FGlobalEnv.Get(AKey, v) then
    Result := v.ToString()
  else
    Result := '';
end;

function TFloriaJSContext.HasVariable(const AKey: string): Boolean;
begin
  Result := FGlobalEnv.Has(AKey);
end;

procedure TFloriaJSContext.SetGlobal(const AName: string; const AValue: TFloriaJSValue);
begin
  FGlobalEnv.Define(AName, AValue);
end;

function TFloriaJSContext.GetGlobal(const AName: string): TFloriaJSValue;
begin
  Result := FGlobalEnv.GetDefault(AName, JSMakeUndefined());
end;

procedure TFloriaJSContext.RegisterFunction(const AName: string; AProc: TFloriaJSNativeProc);
var
  fn: TFloriaJSFunction;
begin
  fn := FHeap.NewNativeFunction(AName, AProc);
  SetGlobal(AName, JSMakeFunction(fn));
end;

procedure TFloriaJSContext.RegisterMethod(const AName: string; AMethod: TFloriaJSNativeMethod);
var
  fn: TFloriaJSFunction;
begin
  fn := FHeap.NewNativeMethod(AName, AMethod);
  SetGlobal(AName, JSMakeFunction(fn));
end;

function TFloriaJSContext.Evaluate(const AScript: string): TFloriaJSResult;
var
  val: TFloriaJSValue;
begin
  if Length(Trim(AScript)) = 0 then
    Exit(FloriaJSMakeOkResult(''));

  try
    { Only the primitive parts of the result are handed out here, so the
      result itself does not have to stay alive after the call. }
    val := EvaluateScript(AScript);
    Result.Success := True;
    Result.ResultType := val.Kind;
    Result.StringValue := val.ToString();
    Result.NumberValue := val.ToNumber();
    Result.BooleanValue := val.ToBoolean();
    Result.ErrorMessage := '';
  except
    on E: Exception do
      Result := FloriaJSMakeErrorResult(E.Message);
  end;
end;

function TFloriaJSContext.EvaluateDetailed(const AScript: string;
  const ASourceName: string = ''): TFloriaJSDiagnosticResult;
var
  val: TFloriaJSValue;
begin
  if Length(Trim(AScript)) = 0 then
  begin
    AssignDiagnostic(Result, FloriaJSMakeOkResult(''), fjdkSuccess,
      ASourceName, '', '', '');
    Exit;
  end;

  try
    val := EvaluateScript(AScript);
    Result.Result.Success := True;
    Result.Result.ResultType := val.Kind;
    Result.Result.StringValue := val.ToString();
    Result.Result.NumberValue := val.ToNumber();
    Result.Result.BooleanValue := val.ToBoolean();
    Result.Result.ErrorMessage := '';
    Result.Kind := fjdkSuccess;
    Result.ErrorName := '';
    Result.Message := '';
    Result.SourceName := ASourceName;
    Result.Line := 0;
    Result.Column := 0;
    Result.HostExceptionClass := '';
  except
    on E: EFloriaJSParseError do
      AssignDiagnostic(Result, FloriaJSMakeErrorResult(E.Message), fjdkParseError,
        ASourceName, 'SyntaxError', E.Message, '', E.Line, E.Column);
    on E: EFloriaJSCompileError do
      AssignDiagnostic(Result, FloriaJSMakeErrorResult(E.Message), fjdkCompileError,
        ASourceName, 'SyntaxError', E.Message, '');
    on E: EFloriaJSThrow do
    begin
      { Copy managed strings immediately; the thrown heap object may be
        collected by a subsequent evaluation. }
      if E.Value.IsObject() and (E.Value.ObjVal is TFloriaJSError) then
        AssignDiagnostic(Result, FloriaJSMakeErrorResult(E.Message), fjdkJavaScriptThrow,
          ASourceName, TFloriaJSError(E.Value.ObjVal).Name,
          TFloriaJSError(E.Value.ObjVal).Message, '')
      else
        AssignDiagnostic(Result, FloriaJSMakeErrorResult(E.Message), fjdkJavaScriptThrow,
          ASourceName, '', E.Message, '');
    end;
    on E: Exception do
      AssignDiagnostic(Result, FloriaJSMakeErrorResult(E.Message), fjdkHostException,
        ASourceName, '', E.Message, E.ClassName);
  end;
end;


{ Reads AFileName and runs it. A missing or unreadable file becomes a failed
  result, so the caller can report it the same way as a script error. }
function TFloriaJSContext.EvaluateFile(const AFileName: string): TFloriaJSResult;
var
  sl: TStringList;
begin
  if not FileExists(AFileName) then
  begin
    Result := FloriaJSMakeErrorResult('File not found: ' + AFileName);
    Exit;
  end;

  sl := TStringList.Create();
  try
    try
      sl.LoadFromFile(AFileName);
    except
      on E: Exception do
      begin
        Result := FloriaJSMakeErrorResult('Cannot read ' + AFileName + ': ' + E.Message);
        Exit;
      end;
    end;
    { The source is run verbatim. TStringList normalises line endings, which
      does not change how the lexer reads it. }
    Result := Evaluate(sl.Text);
  finally
    sl.Free();
  end;
end;

function TFloriaJSContext.EvaluateFileDetailed(const AFileName: string): TFloriaJSDiagnosticResult;
var
  sl: TStringList;
begin
  if not FileExists(AFileName) then
  begin
    AssignDiagnostic(Result,
      FloriaJSMakeErrorResult('File not found: ' + AFileName), fjdkHostException,
      AFileName, '', 'File not found: ' + AFileName, '');
    Exit;
  end;

  sl := TStringList.Create();
  try
    try
      sl.LoadFromFile(AFileName);
    except
      on E: Exception do
      begin
        AssignDiagnostic(Result,
          FloriaJSMakeErrorResult('Cannot read ' + AFileName + ': ' + E.Message),
          fjdkHostException, AFileName, '',
          'Cannot read ' + AFileName + ': ' + E.Message, E.ClassName);
        Exit;
      end;
    end;
    Result := EvaluateDetailed(sl.Text, AFileName);
  finally
    sl.Free();
  end;
end;

function TFloriaJSContext.EvaluateValue(const AScript: string): TFloriaJSValue;
begin
  Result := EvaluateScript(AScript);
  { The caller holds on to the returned value, so the object it points at must
    stay alive for as long as the caller keeps it. }
  if Result.IsObject() and (Result.ObjVal <> nil) then
    Result.ObjVal.Pin;
end;

function TFloriaJSContext.EvaluateScript(const AScript: string): TFloriaJSValue;
var
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  code: TFloriaJSBytecode;
begin
  if Length(Trim(AScript)) = 0 then
    Exit(JSMakeUndefined());

  parser := TFloriaJSParser.Create(AScript);
  try
    prog := parser.ParseProgram();
    try
      if parser.HasErrors() then
        raise EFloriaJSParseError.Create(parser.GetError(0),
          parser.GetErrorLine(0), parser.GetErrorColumn(0));

      if FHeap <> nil then
        FHeap.Collect();

      code := FCompiler.CompileProgram(prog);
      try
        Result := FVM.Execute(code, FGlobalEnv);
      finally
        code.Release();
      end;

      DrainPromiseJobs();
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;
end;

function TFloriaJSContext.EvaluateReentrant(const AScript: string): TFloriaJSValue;
var
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  code: TFloriaJSBytecode;
begin
  if Length(Trim(AScript)) = 0 then
    Exit(JSMakeUndefined());

  parser := TFloriaJSParser.Create(AScript);
  try
    prog := parser.ParseProgram();
    try
      if parser.HasErrors() then
        raise EFloriaJSThrow.Create(JSMakeObject(
          FHeap.NewError('SyntaxError', parser.GetError(0))));

      try
        code := FCompiler.CompileProgram(prog);
      except
        on E: EFloriaJSCompileError do
          raise EFloriaJSThrow.Create(JSMakeObject(
            FHeap.NewError('SyntaxError', E.Message)));
      end;
      try
        { Deliberately no Collect() and no Promise-job drain here. The caller
          is a native function inside a live VM frame; collection could free
          values that frame still holds, and draining microtasks would run
          them at the wrong nesting depth. }
        Result := FVM.Execute(code, FGlobalEnv);
      finally
        code.Release();
      end;
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;
end;

function TFloriaJSContext.GetTimerRegistry(): TFloriaJSTimerRegistry;
begin
  if (FHeap <> nil) and (FHeap.TimerRegistry <> nil) then
    Result := TFloriaJSTimerRegistry(FHeap.TimerRegistry)
  else
    Result := nil;
end;

procedure TFloriaJSContext.DrainPromiseJobs();
begin
  if FHeap = nil then
    Exit;
  FHeap.RunPendingJobs();
  while FHeap.HasPromiseJobs() do
    FHeap.RunPendingJobs();
end;

procedure TFloriaJSContext.PumpTimers();
var
  registry: TFloriaJSTimerRegistry;
begin
  registry := GetTimerRegistry();
  if registry <> nil then
    registry.ProcessDue();
  DrainPromiseJobs();
end;

function TFloriaJSContext.HasPendingTimers(): Boolean;
var
  registry: TFloriaJSTimerRegistry;
begin
  registry := GetTimerRegistry();
  Result := (registry <> nil) and registry.HasPending();
end;

function TFloriaJSContext.PendingTimerCount(): Integer;
var
  registry: TFloriaJSTimerRegistry;
begin
  registry := GetTimerRegistry();
  if registry <> nil then
    Result := registry.PendingCount()
  else
    Result := 0;
end;

function TFloriaJSContext.NextTimerDelayMS(): Integer;
var
  registry: TFloriaJSTimerRegistry;
begin
  registry := GetTimerRegistry();
  if registry <> nil then
    Result := registry.NextDelayMS()
  else
    Result := -1;
end;

function TFloriaJSContext.HasPendingWork(): Boolean;
begin
  Result := HasPendingTimers() or ((FHeap <> nil) and FHeap.HasPromiseJobs());
end;

function TFloriaJSContext.Call(const AFuncName: string; const AArgs: array of TFloriaJSValue): TFloriaJSValue;
var
  fnVal: TFloriaJSValue;
begin
  fnVal := GetGlobal(AFuncName);
  if not fnVal.IsFunction() then
    Exit(JSMakeUndefined());

  Result := FVM.CallFunction(fnVal, AArgs, JSMakeUndefined());

  { The caller holds on to the returned value, so the object it points at must
    stay alive for as long as the caller keeps it. }
  if Result.IsObject() and (Result.ObjVal <> nil) then
    Result.ObjVal.Pin;
end;

procedure TFloriaJSContext.ReleaseValue(const AValue: TFloriaJSValue);
begin
  { The object is given back to the runtime, which may reclaim it as soon as
    nothing refers to it any more. }
  if AValue.IsObject() and (AValue.ObjVal <> nil) then
    AValue.ObjVal.Unpin;
end;

procedure TFloriaJSContext.Reset();
begin
  FHeap.Clear();
  FGlobalEnv := TFloriaJSEnvironment(FHeap.TrackEnvironment(TFloriaJSEnvironment.Create(nil, FHeap)));
  FVM.ResetStack();
  FOutput.Clear();
  InitContext();
end;

{ TFloriaJSEngine }

constructor TFloriaJSEngine.Create();
begin
  inherited Create();
  FInitialized := False;
  FMemoryLimit := 64 * 1024 * 1024; { Default 64MB memory limit }
  FContexts := TFPList.Create();
  Initialize();
end;

destructor TFloriaJSEngine.Destroy();
var
  i: Integer;
begin
  if FContexts <> nil then
  begin
    for i := FContexts.Count - 1 downto 0 do
      TFloriaJSContext(FContexts[i]).Free();
    FreeAndNil(FContexts);
  end;
  inherited Destroy();
end;

procedure TFloriaJSEngine.Initialize();
begin
  if not FInitialized then
  begin
    FDefaultContext := CreateContext('default');
    FInitialized := True;
  end;
end;

function TFloriaJSEngine.CreateContext(const AName: string = ''): TFloriaJSContext;
var
  ctxName: string;
begin
  if AName = '' then
    ctxName := Format('context_%d', [FContexts.Count])
  else
    ctxName := AName;

  Result := TFloriaJSContext.Create(Self, ctxName);
  FContexts.Add(Result);
end;

procedure TFloriaJSEngine.DestroyContext(AContext: TFloriaJSContext);
begin
  if (AContext <> nil) and (FContexts <> nil) then
  begin
    FContexts.Remove(AContext);
    if FDefaultContext = AContext then
      FDefaultContext := nil;
    AContext.Free();
  end;
end;

function TFloriaJSEngine.Execute(const AScript: string): TFloriaJSResult;
begin
  if FDefaultContext <> nil then
    Result := FDefaultContext.Evaluate(AScript)
  else
    Result := FloriaJSMakeErrorResult('No active execution context');
end;

function TFloriaJSEngine.ExecuteDetailed(const AScript: string;
  const ASourceName: string = ''): TFloriaJSDiagnosticResult;
begin
  if FDefaultContext <> nil then
    Result := FDefaultContext.EvaluateDetailed(AScript, ASourceName)
  else
    AssignDiagnostic(Result,
      FloriaJSMakeErrorResult('No active execution context'), fjdkHostException,
      ASourceName, '', 'No active execution context', '');
end;

function TFloriaJSEngine.ExecuteFile(const AFileName: string): TFloriaJSResult;
begin
  if FDefaultContext <> nil then
    Result := FDefaultContext.EvaluateFile(AFileName)
  else
    Result := FloriaJSMakeErrorResult('No default context');
end;

function TFloriaJSEngine.ExecuteFileDetailed(const AFileName: string): TFloriaJSDiagnosticResult;
begin
  if FDefaultContext <> nil then
    Result := FDefaultContext.EvaluateFileDetailed(AFileName)
  else
    AssignDiagnostic(Result,
      FloriaJSMakeErrorResult('No default context'), fjdkHostException,
      AFileName, '', 'No default context', '');
end;

function TFloriaJSEngine.ExecuteValue(const AScript: string): TFloriaJSValue;
begin
  if FDefaultContext <> nil then
    Result := FDefaultContext.EvaluateValue(AScript)
  else
    Result := JSMakeUndefined();
end;

procedure TFloriaJSEngine.ReleaseValue(const AValue: TFloriaJSValue);
begin
  if FDefaultContext <> nil then
    FDefaultContext.ReleaseValue(AValue);
end;

procedure TFloriaJSEngine.RegisterFunction(const AName: string; AProc: TFloriaJSNativeProc);
begin
  if FDefaultContext <> nil then
    FDefaultContext.RegisterFunction(AName, AProc);
end;

end.
