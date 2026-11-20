{ ************************************************************************** }
{                                                                            }
{   Floria JS Test262 Host — One Scenario per Process                       }
{                                                                            }
{   Copyright (c) 2026 Dio Affriza                                          }
{   SPDX-License-Identifier: MPL-2.0                                        }
{                                                                            }
{ ************************************************************************** }

program FloriaTest262Host;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math,
  floriajs, floria.js.value, floria.test262.report;

const
  EXIT_PASS = 0;
  EXIT_TEST_FAILURE = 1;
  EXIT_USAGE = 2;
  EXIT_HOST_FAILURE = 3;
  EXIT_INTERNAL_ERROR = 4;

  ASYNC_COMPLETE = 'Test262:AsyncTestComplete';
  ASYNC_FAILURE_PREFIX = 'Test262:AsyncTestFailure:';

  USAGE_TEXT =
    'Usage: floria-test262-host [options] --test <file.js>' + LineEnding +
    '  --scenario-id <id>   Stable identifier (defaults to the test filename)' + LineEnding +
    '  --variant <mode>     non-strict (default) or raw' + LineEnding +
    '  --harness <file.js>  Evaluate before the test; repeat in required order' + LineEnding +
    '  --test <file.js>     Evaluate exactly once after all harness files' + LineEnding +
    '  --strict             Evaluate the test source as strict mode' + LineEnding +
    '  --async              Require a Test262 done-print completion message' + LineEnding +
    '  --help               Show this help' + LineEnding +
    'Every source is a filename. No source text, sorting, warm-up, or retries.' + LineEnding;

type
  THostOptions = record
    ScenarioId: string;
    Variant: string;
    HarnessFiles: array of string;
    TestFile: string;
    Async: Boolean;
    Strict: Boolean;
    IsModule: Boolean;
    ModuleRoot: string;
  end;

  TAsyncCompletion = record
    Count: Integer;
    FailureSeen: Boolean;
    FailureMessage: string;
  end;

  { One extra realm created by `$262.createRealm`. The realm object lives in
    the caller's heap while its global object and intrinsics belong to a
    separate context-owned heap. Keeping both pointers together lets a native
    callback find the target context from the receiver. }
  TRealmEntry = record
    RealmObject: TFloriaJSObject;
    Context: TFloriaJSContext;
  end;

  PTFloriaJSValue = ^TFloriaJSValue;

  TAgentState = (asReady, asRunning, asWaiting, asDone);

  { A cooperative diagnostic agent. Each agent owns a separate context; the
    host runs one agent at a time and switches only at explicit agent calls. }
  TAgent = class
  public
    Context: TFloriaJSContext;
    Script: string;
    Reports: TStringList;
    Broadcasts: TList;
    State: TAgentState;
    constructor Create(AContext: TFloriaJSContext; const AScript: string);
    destructor Destroy(); override;
  end;

  EUsageError = class(Exception);

  EHostSourceError = class(Exception)
  private
    FUnderlyingClass: string;
  public
    constructor Create(const AMessage, AUnderlyingClass: string);
    property UnderlyingClass: string read FUnderlyingClass;
  end;

var
  GPrintOutput: TStringList = nil;
  GContext: TFloriaJSContext = nil;
  GEngine: TFloriaJSEngine = nil;
  GStrictTest: Boolean = False;
  GRealms: array of TRealmEntry;
  GAgents: TList = nil;
  GMainAgent: TAgent = nil;
  GCurrentAgent: TAgent = nil;
  GSharedBuffers: TList = nil;

procedure SetupHost262(AContext: TFloriaJSContext); forward;

constructor EHostSourceError.Create(const AMessage, AUnderlyingClass: string);
begin
  inherited Create(AMessage);
  FUnderlyingClass := AUnderlyingClass;
end;

function NextArgumentValue(const AOption: string; var AIndex: Integer): string;
begin
  if AIndex >= ParamCount() then
    raise EUsageError.Create('missing value for ' + AOption);
  Inc(AIndex);
  Result := ParamStr(AIndex);
  if Result = '' then
    raise EUsageError.Create('empty value for ' + AOption);
end;

function ParseArguments(): THostOptions;
var
  i: Integer;
  option: string;
begin
  Result.ScenarioId := '';
  Result.Variant := 'non-strict';
  Result.TestFile := '';
  Result.Async := False;
  Result.Strict := False;
  Result.IsModule := False;
  Result.ModuleRoot := '';
  { A module test's root is derived from the test file unless overridden. }
  SetLength(Result.HarnessFiles, 0);

  i := 1;
  while i <= ParamCount() do
  begin
    option := ParamStr(i);
    if (option = '--help') or (option = '-h') then
    begin
      Write(USAGE_TEXT);
      Halt(EXIT_PASS);
    end
    else if option = '--scenario-id' then
    begin
      if Result.ScenarioId <> '' then
        raise EUsageError.Create('--scenario-id may only be supplied once');
      Result.ScenarioId := NextArgumentValue(option, i);
    end
    else if option = '--variant' then
    begin
      Result.Variant := NextArgumentValue(option, i);
      if (Result.Variant <> 'raw') and (Result.Variant <> 'non-strict') and
         (Result.Variant <> 'strict') then
        raise EUsageError.Create('unsupported variant: ' + Result.Variant);
    end
    else if option = '--strict' then
    begin
      if Result.Strict then
        raise EUsageError.Create('--strict may only be supplied once');
      Result.Strict := True;
    end
    else if option = '--async' then
    begin
      if Result.Async then
        raise EUsageError.Create('--async may only be supplied once');
      Result.Async := True;
    end
    else if option = '--harness' then
    begin
      option := NextArgumentValue(option, i);
      SetLength(Result.HarnessFiles, Length(Result.HarnessFiles) + 1);
      Result.HarnessFiles[High(Result.HarnessFiles)] := option;
    end
    else if option = '--test' then
    begin
      if Result.TestFile <> '' then
        raise EUsageError.Create('--test must be supplied exactly once');
      Result.TestFile := NextArgumentValue(option, i);
    end
    else if option = '--module' then
      Result.IsModule := True
    else if option = '--module-root' then
      Result.ModuleRoot := NextArgumentValue(option, i)
    else
      raise EUsageError.Create('unknown argument: ' + option);
    Inc(i);
  end;

  if Result.TestFile = '' then
    raise EUsageError.Create('--test is required');
  if (Result.Variant = 'raw') and (Length(Result.HarnessFiles) > 0) then
    raise EUsageError.Create('raw scenarios cannot have harness files');
  if (Result.Variant = 'raw') and Result.Async then
    raise EUsageError.Create('raw scenarios cannot require an async completion');
  if (Result.Variant = 'raw') and Result.Strict then
    raise EUsageError.Create('raw scenarios cannot be forced into strict mode');
  if Result.ScenarioId = '' then
    Result.ScenarioId := ChangeFileExt(ExtractFileName(Result.TestFile), '');
end;

function ReadSourceBytes(const AFileName: string): string;
var
  stream: TFileStream;
  size: Int64;
begin
  if not FileExists(AFileName) then
    raise EHostSourceError.Create('File not found: ' + AFileName, '');

  try
    stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
    try
      size := stream.Size;
      if size > MaxInt then
        raise EHostSourceError.Create('File too large: ' + AFileName, '');
      SetLength(Result, SizeInt(size));
      if size > 0 then
        stream.ReadBuffer(Result[1], SizeInt(size));
    finally
      stream.Free();
    end;
  except
    on E: EHostSourceError do
      raise;
    on E: Exception do
      raise EHostSourceError.Create('Cannot read ' + AFileName + ': ' + E.Message,
        E.ClassName);
  end;
end;

function JoinArguments(const AArgs: array of TFloriaJSValue): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(AArgs) do
  begin
    if i > 0 then
      Result := Result + ' ';
    Result := Result + AArgs[i].ToString();
  end;
end;

function HostPrint(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if GPrintOutput <> nil then
    GPrintOutput.Add(JoinArguments(AArgs));
  Result := JSMakeUndefined();
end;

function HostEvalScript(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  targetContext: TFloriaJSContext;
begin
  if GCurrentAgent <> nil then
    targetContext := GCurrentAgent.Context
  else
    targetContext := GContext;
  if (targetContext = nil) or (Length(AArgs) = 0) then
    Exit(JSMakeUndefined());
  { The re-entrant path deliberately does not collect or drain microtasks while
    the caller's VM frame still holds live values. Errors propagate as normal
    JavaScript throws; the returned value is not pinned. }
  Result := targetContext.EvaluateReentrant(AArgs[0].ToString());
end;

function FindRealmContext(const AThis: TFloriaJSValue): TFloriaJSContext;
var
  i: Integer;
begin
  Result := nil;
  if not AThis.IsObject() then
    Exit;
  for i := High(GRealms) downto 0 do
    if GRealms[i].RealmObject = AThis.ObjVal then
      Exit(GRealms[i].Context);
end;

function HostRealmEvalScript(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  realmContext: TFloriaJSContext;
begin
  realmContext := FindRealmContext(AThis);
  if (realmContext = nil) or (Length(AArgs) = 0) then
    Exit(JSMakeUndefined());
  { Evaluate in the realm that owns this `evalScript`, not in the caller's
    context. The re-entrant path keeps the caller's live values safe. }
  Result := realmContext.EvaluateReentrant(AArgs[0].ToString());
end;

function HostCreateRealm(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  realmContext: TFloriaJSContext;
  realmObject: TFloriaJSObject;
  index: Integer;
begin
  if (GEngine = nil) or (GContext = nil) then
    Exit(JSMakeUndefined());

  { A realm is a genuinely separate context: its own heap, global object,
    intrinsics, timer registry, and output list. Nothing mutable is shared with
    the caller's realm. }
  realmContext := GEngine.CreateContext('realm');

  realmObject := GContext.Heap.NewObject(GContext.Heap.GetObjectPrototype());
  realmObject.SetProperty('global', realmContext.GetGlobal('globalThis'));
  realmObject.SetProperty('evalScript', JSMakeFunction(
    GContext.Heap.NewNativeFunction('evalScript', @HostRealmEvalScript)));
  { The registry keeps the realm object alive for the lifetime of the process
    so a later `evalScript` call can still resolve its context. }
  realmObject.Pin();

  index := Length(GRealms);
  SetLength(GRealms, index + 1);
  GRealms[index].RealmObject := realmObject;
  GRealms[index].Context := realmContext;

  Result := JSMakeObject(realmObject);
end;

{ Cooperative agents }

constructor TAgent.Create(AContext: TFloriaJSContext; const AScript: string);
begin
  inherited Create();
  Context := AContext;
  Script := AScript;
  Reports := TStringList.Create();
  Broadcasts := TList.Create();
  State := asReady;
end;

destructor TAgent.Destroy();
var
  i: Integer;
begin
  Reports.Free();
  if Broadcasts <> nil then
  begin
    for i := 0 to Broadcasts.Count - 1 do
      Dispose(PTFloriaJSValue(Broadcasts[i]));
    Broadcasts.Free();
  end;
  inherited Destroy();
end;

procedure RunAgent(AAgent: TAgent);
var
  saved: TAgent;
begin
  if (AAgent = nil) or (AAgent.State <> asReady) then
    Exit;
  AAgent.State := asRunning;
  saved := GCurrentAgent;
  GCurrentAgent := AAgent;
  try
    try
      AAgent.Context.Evaluate(AAgent.Script);
    except
      on E: Exception do
        if GMainAgent <> nil then
          GMainAgent.Reports.Add('agent-error: ' + E.Message);
    end;
  finally
    AAgent.State := asDone;
    GCurrentAgent := saved;
  end;
end;

function RunOneReadyAgent(): Boolean;
var
  i: Integer;
begin
  Result := False;
  if GAgents = nil then
    Exit;
  for i := 0 to GAgents.Count - 1 do
    if TAgent(GAgents[i]).State = asReady then
    begin
      RunAgent(TAgent(GAgents[i]));
      Exit(True);
    end;
end;

procedure RunReadyAgents();
begin
  while RunOneReadyAgent() do ;
end;

procedure DrainAgentJobs();
var
  i: Integer;
begin
  if GAgents = nil then
    Exit;
  for i := 0 to GAgents.Count - 1 do
    TAgent(GAgents[i]).Context.DrainPromiseJobs();
end;

procedure YieldToAgents();
begin
  RunOneReadyAgent();
end;

function HostAgentStart(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  agentContext: TFloriaJSContext;
  agent: TAgent;
  script: string;
begin
  if (GEngine = nil) or (Length(AArgs) = 0) then
    Exit(JSMakeUndefined());
  script := AArgs[0].ToString();
  agentContext := GEngine.CreateContext('agent');
  SetupHost262(agentContext);
  agent := TAgent.Create(agentContext, script);
  GAgents.Add(agent);
  Result := JSMakeUndefined();
end;

function HostAgentReport(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if (GMainAgent <> nil) and (Length(AArgs) > 0) then
    GMainAgent.Reports.Add(AArgs[0].ToString());
  Result := JSMakeUndefined();
end;

function HostAgentGetReport(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if GMainAgent = nil then
    Exit(JSMakeUndefined());
  DrainAgentJobs();
  while (GMainAgent.Reports.Count = 0) and RunOneReadyAgent() do
    DrainAgentJobs();
  if GMainAgent.Reports.Count > 0 then
  begin
    Result := JSMakeString(GMainAgent.Reports[0]);
    GMainAgent.Reports.Delete(0);
  end
  else
    Result := JSMakeUndefined();
end;

function HostAgentBroadcast(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  i: Integer;
  value: TFloriaJSValue;
  slot: PTFloriaJSValue;
begin
  if Length(AArgs) > 0 then
    value := AArgs[0]
  else
    value := JSMakeUndefined();
  if GAgents <> nil then
    for i := 0 to GAgents.Count - 1 do
    begin
      New(slot);
      slot^ := value;
      TAgent(GAgents[i]).Broadcasts.Add(slot);
    end;
  Result := JSMakeUndefined();
end;

function HostAgentReceiveBroadcast(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if GCurrentAgent = nil then
    Exit(JSMakeUndefined());
  while (GCurrentAgent.Broadcasts.Count = 0) and RunOneReadyAgent() do ;
  if GCurrentAgent.Broadcasts.Count > 0 then
  begin
    Result := PTFloriaJSValue(GCurrentAgent.Broadcasts[0])^;
    Dispose(PTFloriaJSValue(GCurrentAgent.Broadcasts[0]));
    GCurrentAgent.Broadcasts.Delete(0);
    if (Length(AArgs) > 0) and AArgs[0].IsFunction() then
      Result := GCurrentAgent.Context.Heap.InvokeFunction(
        AArgs[0], [Result], JSMakeUndefined());
  end
  else
    Result := JSMakeUndefined();
end;

function HostAgentSleep(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  deadline: QWord;
  ms: QWord;
begin
  ms := 0;
  if Length(AArgs) > 0 then
    ms := Trunc(AArgs[0].ToNumber());
  deadline := GetTickCount64() + ms;
  while GetTickCount64() < deadline do
  begin
    if not RunOneReadyAgent() then
      Sleep(1);
  end;
  Result := JSMakeUndefined();
end;

function HostAgentMonotonicNow(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeNumber(GetTickCount64());
end;

function HostAgentLeave(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if GCurrentAgent <> nil then
    GCurrentAgent.State := asDone;
  Result := JSMakeUndefined();
end;

function HostAgentGetSharedArrayBuffer(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  size: Integer;
begin
  size := 0;
  if Length(AArgs) > 0 then
    size := Trunc(AArgs[0].ToNumber());
  if (GMainAgent = nil) or (GMainAgent.Context = nil) then
    Exit(JSMakeUndefined());
  Result := GMainAgent.Context.EvaluateValue(
    'new SharedArrayBuffer(' + IntToStr(size) + ')');
  if Result.IsObject() then
    GSharedBuffers.Add(Result.ObjVal);
end;

function HostAgentWait(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  deadline: QWord;
  ms: QWord;
begin
  ms := 0;
  if Length(AArgs) > 3 then
    ms := Trunc(AArgs[3].ToNumber());
  deadline := GetTickCount64() + ms;
  while GetTickCount64() < deadline do
  begin
    if not RunOneReadyAgent() then
      Sleep(1);
  end;
  Result := JSMakeString('timed-out');
end;

function HostAgentTryWait(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeBoolean(False);
end;

procedure SetupHost262(AContext: TFloriaJSContext);
var
  host262, agentObj: TFloriaJSObject;
begin
  if AContext = nil then
    Exit;
  host262 := AContext.Heap.NewObject(AContext.Heap.GetObjectPrototype());
  host262.SetProperty('global', AContext.GetGlobal('globalThis'));
  host262.SetProperty('evalScript', JSMakeFunction(
    AContext.Heap.NewNativeFunction('evalScript', @HostEvalScript)));
  host262.SetProperty('createRealm', JSMakeFunction(
    AContext.Heap.NewNativeFunction('createRealm', @HostCreateRealm)));

  agentObj := AContext.Heap.NewObject(AContext.Heap.GetObjectPrototype());
  agentObj.SetProperty('start', JSMakeFunction(
    AContext.Heap.NewNativeFunction('start', @HostAgentStart)));
  agentObj.SetProperty('report', JSMakeFunction(
    AContext.Heap.NewNativeFunction('report', @HostAgentReport)));
  agentObj.SetProperty('getReport', JSMakeFunction(
    AContext.Heap.NewNativeFunction('getReport', @HostAgentGetReport)));
  agentObj.SetProperty('broadcast', JSMakeFunction(
    AContext.Heap.NewNativeFunction('broadcast', @HostAgentBroadcast)));
  agentObj.SetProperty('receiveBroadcast', JSMakeFunction(
    AContext.Heap.NewNativeFunction('receiveBroadcast', @HostAgentReceiveBroadcast)));
  agentObj.SetProperty('sleep', JSMakeFunction(
    AContext.Heap.NewNativeFunction('sleep', @HostAgentSleep)));
  agentObj.SetProperty('monotonicNow', JSMakeFunction(
    AContext.Heap.NewNativeFunction('monotonicNow', @HostAgentMonotonicNow)));
  agentObj.SetProperty('leave', JSMakeFunction(
    AContext.Heap.NewNativeFunction('leave', @HostAgentLeave)));
  agentObj.SetProperty('leaving', JSMakeFunction(
    AContext.Heap.NewNativeFunction('leaving', @HostAgentLeave)));
  agentObj.SetProperty('getSharedArrayBuffer', JSMakeFunction(
    AContext.Heap.NewNativeFunction('getSharedArrayBuffer', @HostAgentGetSharedArrayBuffer)));
  agentObj.SetProperty('wait', JSMakeFunction(
    AContext.Heap.NewNativeFunction('wait', @HostAgentWait)));
  agentObj.SetProperty('tryWait', JSMakeFunction(
    AContext.Heap.NewNativeFunction('tryWait', @HostAgentTryWait)));
  host262.SetProperty('agent', JSMakeObject(agentObj));
  AContext.SetGlobal('$262', JSMakeObject(host262));
end;

function InspectAsyncCompletion(const ALines: TStringList): TAsyncCompletion;
var
  i: Integer;
  line: string;
begin
  Result.Count := 0;
  Result.FailureSeen := False;
  Result.FailureMessage := '';
  if ALines = nil then
    Exit;
  for i := 0 to ALines.Count - 1 do
  begin
    line := ALines[i];
    if line = ASYNC_COMPLETE then
      Inc(Result.Count)
    else if Copy(line, 1, Length(ASYNC_FAILURE_PREFIX)) = ASYNC_FAILURE_PREFIX then
    begin
      Inc(Result.Count);
      Result.FailureSeen := True;
      if Result.FailureMessage = '' then
        Result.FailureMessage := Copy(line, Length(ASYNC_FAILURE_PREFIX) + 1, MaxInt);
    end;
  end;
end;

procedure SplitAsyncFailure(const AMessage: string; out AName, ADetail: string);
var
  separator: Integer;
begin
  separator := Pos(': ', AMessage);
  if separator > 1 then
  begin
    AName := Copy(AMessage, 1, separator - 1);
    ADetail := Copy(AMessage, separator + 2, MaxInt);
  end
  else
  begin
    AName := 'Test262Error';
    ADetail := AMessage;
  end;
end;

function RunAsyncCompletion(const AContext: TFloriaJSContext;
  var AReport: THostReport; const ATestFile: string): Integer;
var
  completion: TAsyncCompletion;
  errorName, errorDetail: string;
  delay: Integer;
begin
  { Pump this context's timers and microtasks until completion. There is no
    internal deadline: a test that never prints completion or leaves a pending
    timer remains alive until the orchestrator's external deadline kills it.
    The host never treats pending work as completion. }
  while True do
  begin
    AContext.PumpTimers();
    completion := InspectAsyncCompletion(GPrintOutput);
    if completion.Count > 0 then
      Break;
    delay := AContext.NextTimerDelayMS();
    if delay < 0 then
      Sleep(5)
    else if delay = 0 then
      Sleep(1)
    else
      Sleep(Min(delay, 5));
  end;

  if completion.Count > 1 then
  begin
    FailHostReport(AReport, 'fail', 'runtime', 'async-completion-repeated',
      'test', 0, ATestFile, '',
      'async completion was reported ' + IntToStr(completion.Count) + ' times', '');
    Exit(EXIT_TEST_FAILURE);
  end;

  if completion.FailureSeen then
  begin
    SplitAsyncFailure(completion.FailureMessage, errorName, errorDetail);
    FailHostReport(AReport, 'fail', 'runtime', 'async-failure',
      'test', 0, ATestFile, errorName, errorDetail, '');
    Exit(EXIT_TEST_FAILURE);
  end;

  AReport.Outcome := 'pass';
  AReport.Phase := 'success';
  AReport.Reason := 'async-complete';
  Result := EXIT_PASS;
end;

function EvaluateSource(const AContext: TFloriaJSContext;
  const AFileName, ASourceRole: string; ASourceIndex: Integer;
  var AReport: THostReport): Integer;
var
  source: string;
  diagnostic: TFloriaJSDiagnosticResult;
begin
  try
    source := ReadSourceBytes(AFileName);
  except
    on E: EHostSourceError do
    begin
      FailHostReport(AReport, 'harness-error', 'host', 'source-io',
        ASourceRole, ASourceIndex, AFileName, '', E.Message,
        E.UnderlyingClass);
      Exit(EXIT_HOST_FAILURE);
    end;
  end;

  { The Test262 strict variant evaluates the test source with a leading
    directive. Harness files keep their own source unchanged. }
  if GStrictTest and (ASourceRole = 'test') then
    source := '"use strict";' + LineEnding + source;

  { One evaluation of this source, in the context shared with all other
    sources in this process. There is no reset or benchmark execution here. }
  diagnostic := AContext.EvaluateDetailed(source, AFileName);
  ApplyDiagnostic(AReport, diagnostic, ASourceRole, ASourceIndex);
  if diagnostic.Result.Success then
    Result := EXIT_PASS
  else if AReport.Outcome = 'fail' then
    Result := EXIT_TEST_FAILURE
  else
    Result := EXIT_HOST_FAILURE;
end;


{ ------------------------------------------------------------------------ }
{ Module loader for the diagnostic host.                                   }
{ ------------------------------------------------------------------------ }

type
  { Resolves a specifier relative to the referring module's path inside the
    upstream test root, and caches each file it reads. }
  TFixtureModuleLoader = class
  private
    FRoot: string;
  public
    constructor Create(const ARoot: string);
    function Load(const ASpecifier, AReferrer: string;
      out ASource, AResolvedName: string): Boolean;
  end;

constructor TFixtureModuleLoader.Create(const ARoot: string);
begin
  inherited Create();
  FRoot := IncludeTrailingPathDelimiter(ARoot);
end;

function TFixtureModuleLoader.Load(const ASpecifier, AReferrer: string;
  out ASource, AResolvedName: string): Boolean;
var
  baseDir, candidate: string;
begin
  ASource := '';
  AResolvedName := '';
  if not (ASpecifier.StartsWith('./') or ASpecifier.StartsWith('../')) then
    Exit(False);
  if AReferrer <> '' then
  begin
    { The referrer is the record's identifier, which is a path relative to the
      module root. }
    baseDir := ExtractFileDir(IncludeTrailingPathDelimiter(FRoot) + AReferrer);
  end
  else
    baseDir := ExcludeTrailingPathDelimiter(FRoot);
  candidate := ExpandFileName(IncludeTrailingPathDelimiter(baseDir) + ASpecifier);
  if not FileExists(candidate) then
  begin
    if FileExists(candidate + '.js') then
      candidate := candidate + '.js'
    else
      Exit(False);
  end;

  { A JSON module is wrapped in a default export; a text fixture becomes a
    module exporting its contents as a string. The engine has no JSON import
    of its own, so the wrapping happens here. }
  if LowerCase(ExtractFileExt(candidate)) = '.json' then
    ASource := 'export default ' + ReadSourceBytes(candidate) + ';'
  else if ExtractFileExt(candidate) = '' then
    ASource := 'export default ' + QuotedStr(ReadSourceBytes(candidate)) + ';'
  else
    ASource := ReadSourceBytes(candidate);
  AResolvedName := ExtractRelativePath(FRoot, candidate);
  Result := True;
end;

function RunScenario(const AOptions: THostOptions;
  var AReport: THostReport): Integer;
var
  engine: TFloriaJSEngine;
  context: TFloriaJSContext;
  loader: TFixtureModuleLoader;
  moduleSource, moduleId: string;
  diagnostic: TFloriaJSDiagnosticResult;
  moduleResult: TFloriaJSResult;
  i: Integer;
begin
  engine := TFloriaJSEngine.Create();
  try
    context := engine.DefaultContext;
    GEngine := engine;
    GContext := context;
    GStrictTest := AOptions.Strict;
    context.RegisterFunction('print', @HostPrint);

    GAgents := TList.Create();
    GSharedBuffers := TList.Create();
    GMainAgent := TAgent.Create(context, '');
    GMainAgent.State := asRunning;
    GCurrentAgent := GMainAgent;
    SetupHost262(context);
    JSSetAtomicsYieldHook(@YieldToAgents);

    for i := 0 to High(AOptions.HarnessFiles) do
    begin
      Result := EvaluateSource(context, AOptions.HarnessFiles[i], 'harness',
        i, AReport);
      if Result <> EXIT_PASS then
        Exit;
    end;

    if AOptions.IsModule then
    begin
      loader := TFixtureModuleLoader.Create(AOptions.ModuleRoot);
      try
        context.SetModuleLoader(TFloriaJSModuleLoader(@loader.Load));
        { The entry identifier is the path relative to the module root, so a
          dependency resolves against the right directory. }
        moduleId := ExtractRelativePath(
          IncludeTrailingPathDelimiter(AOptions.ModuleRoot), AOptions.TestFile);
        moduleSource := ReadSourceBytes(AOptions.TestFile);
        diagnostic := context.EvaluateModuleDetailed(moduleId, moduleSource);
        ApplyDiagnostic(AReport, diagnostic, 'test', 0);
        if diagnostic.Result.Success then
          Result := EXIT_PASS
        else if AReport.Outcome = 'fail' then
          Result := EXIT_TEST_FAILURE
        else
          Result := EXIT_HOST_FAILURE;
      finally
        loader.Free();
      end;
    end
    else
      Result := EvaluateSource(context, AOptions.TestFile, 'test', 0, AReport);
    if (Result = EXIT_PASS) and AOptions.Async then
      Result := RunAsyncCompletion(context, AReport, AOptions.TestFile);
  finally
    CopyCapturedOutput(AReport, context.Output, GPrintOutput);
    SetLength(GRealms, 0);
    if GAgents <> nil then
    begin
      for i := 0 to GAgents.Count - 1 do
        TAgent(GAgents[i]).Free();
      FreeAndNil(GAgents);
    end;
    FreeAndNil(GSharedBuffers);
    FreeAndNil(GMainAgent);
    JSSetAtomicsYieldHook(nil);
    GCurrentAgent := nil;
    GContext := nil;
    GEngine := nil;
    GStrictTest := False;
    engine.Free();
  end;
end;

var
  options: THostOptions;
  report: THostReport;
  started, elapsed: QWord;
  status: Integer;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
  started := GetTickCount64();
  GPrintOutput := TStringList.Create();
  try
    try
      options := ParseArguments();
      InitHostReport(report, options.ScenarioId, options.Variant,
        options.TestFile);
      status := RunScenario(options, report);
    except
      on E: EUsageError do
      begin
        InitHostReport(report, '', 'non-strict', '');
        FailHostReport(report, 'harness-error', 'host', 'invalid-arguments',
          'host', -1, '', '', E.Message, E.ClassName);
        status := EXIT_USAGE;
      end;
      on E: Exception do
      begin
        InitHostReport(report, '', 'non-strict', '');
        FailHostReport(report, 'harness-error', 'host', 'internal-host-error',
          'host', -1, '', '', E.Message, E.ClassName);
        status := EXIT_INTERNAL_ERROR;
      end;
    end;

    elapsed := GetTickCount64() - started;
    WriteLn(HostReportJSON(report, elapsed));
    Halt(status);
  finally
    GPrintOutput.Free();
    GPrintOutput := nil;
  end;
end.
