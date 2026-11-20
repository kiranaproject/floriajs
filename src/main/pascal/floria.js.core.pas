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
  floria.js.bytecode, floria.js.vm, floria.js.compiler, floria.js.module,
  floria.js.lexer;

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
    FModuleRegistry: TFloriaJSModuleRegistry;

    procedure InitContext();
    function  EvaluateScript(const AScript: string): TFloriaJSValue;
    function  GetTimerRegistry(): TFloriaJSTimerRegistry;
    { Module record helpers. See the implementation for the specification
      sections each one follows. }
    function  ParseModuleRecord(AModule: TFloriaJSModuleRecord;
      const ASource: string; out AErrorMessage: string): Boolean;
    { Every name a module declares at its top level. }
    procedure CollectModuleBindings(AProgram: TFloriaJSProgram; AInto: TStrings);
    { Module early errors for duplicate top-level declarations: a lexical
      binding may not repeat, a function may not repeat, and a lexical binding
      may not share a name with a var or function. Returns False and fills
      AErrorMessage on a conflict. }
    function  CheckModuleBindingDuplicates(AProgram: TFloriaJSProgram;
      out AErrorMessage: string): Boolean;
    { Creates the module's top-level lexical bindings in their uninitialized
      state, which is what gives them a temporal dead zone. }
    procedure HoistModuleLexicals(AProgram: TFloriaJSProgram;
      AEnv: TFloriaJSEnvironment);
    function  CreateModuleEnvironment(): TFloriaJSEnvironment;
    function  LinkModule(AModule: TFloriaJSModuleRecord;
      out AErrorMessage: string): Boolean;
    function  ResolveImportValue(ADep: TFloriaJSModuleRecord;
      const AName: string): TFloriaJSValue;
    { The live reader installed for an import binding. }
    function  ReadImportBinding(AModule: TObject;
      const AImportName: string): TFloriaJSValue;
    { Re-reads every import binding from the exporting module. Called just
      before a module body runs, after its dependencies have evaluated. }
    procedure RefreshImports(AModule: TFloriaJSModuleRecord);
    { Builds the import.meta object for a module. }
    function  MakeImportMeta(AModule: TFloriaJSModuleRecord): TFloriaJSValue;
  public
    { Module helpers the dynamic-import closure and the host use. }
    function  LinkDependency(ADep: TFloriaJSModuleRecord): Boolean;
    procedure EvaluateModuleBody(AModule: TFloriaJSModuleRecord);
    function  MakeNamespaceFor(ADep: TFloriaJSModuleRecord): TFloriaJSValue;
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

    { Evaluates ASource as an ECMAScript module with the given resolved
      identifier. The loader supplies the source of every dependency. Linking
      and evaluation follow the specification, including cycle ordering and
      the TDZ of a binding that has not been initialised yet. }
    function  EvaluateModule(const AIdentifier, ASource: string): TFloriaJSResult;
    { The phase-aware form. A module that fails to parse or link reports a
      parse or compile error, which is what a negative test expects. }
    function  EvaluateModuleDetailed(const AIdentifier,
      ASource: string): TFloriaJSDiagnosticResult;
    { Installs the callback that resolves a module specifier to source. }
    procedure SetModuleLoader(ALoader: TFloriaJSModuleLoader);
    { The namespace object of a module that has been evaluated. }
    function  GetModuleNamespace(const AIdentifier: string): TFloriaJSValue;
    property ModuleRegistry: TFloriaJSModuleRegistry read FModuleRegistry;

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
  if FModuleRegistry <> nil then
  begin
    FModuleRegistry.Loader := nil;
    FreeAndNil(FModuleRegistry);
  end;
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
  FModuleRegistry := TFloriaJSModuleRegistry.Create();
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


{ ------------------------------------------------------------------------ }
{ Module records: parsing, linking, namespace construction, and evaluation. }
{ ------------------------------------------------------------------------ }

type
  { A dynamic `import(specifier)` closes over the importing context and its
    module, so the specifier is resolved relative to the right file. It returns
    a promise of the module namespace. }
  TDynamicImporter = class
  private
    FContext: TFloriaJSContext;
    FModule: TFloriaJSModuleRecord;
  public
    constructor Create(AContext: TFloriaJSContext;
      AModule: TFloriaJSModuleRecord);
    function Import(const AArgs: array of TFloriaJSValue;
      AThis: TFloriaJSValue): TFloriaJSValue;
  end;

  { A namespace accessor reads its exporting module's live binding on every
    access, which is what makes imports live. }
  TNamespaceGetter = class
  private
    FContext: TFloriaJSContext;
    FModule: TFloriaJSModuleRecord;
    FExportName: string;
  public
    constructor Create(AContext: TFloriaJSContext;
      AModule: TFloriaJSModuleRecord; const AExportName: string);
    function Get(const AArgs: array of TFloriaJSValue;
      AThis: TFloriaJSValue): TFloriaJSValue;
  end;

constructor TDynamicImporter.Create(AContext: TFloriaJSContext;
  AModule: TFloriaJSModuleRecord);
begin
  inherited Create();
  FContext := AContext;
  FModule := AModule;
end;

function TDynamicImporter.Import(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  specifier: string;
  source, resolved: string;
  dep: TFloriaJSModuleRecord;
  promise, target: TFloriaJSPromise;
begin
  Result := JSMakeUndefined();
  if Length(AArgs) = 0 then
    Exit;
  specifier := JSToString(AArgs[0]);

  dep := nil;
  if FModule <> nil then
    dep := FModule.DependencyFor(specifier);
  if dep = nil then
  begin
    { Not already linked: load it through the registry. }
    dep := FContext.ModuleRegistry.Load(specifier, FModule.Identifier);
  end;

  promise := FContext.Heap.NewPromise();
  target := promise;
  if dep = nil then
  begin
    target.Reject(JSMakeObject(FContext.Heap.NewError('TypeError',
      'Cannot resolve module ' + specifier)));
    Exit(JSMakePromise(promise));
  end;

  try
    if not FContext.LinkDependency(dep) then
    begin
      target.Reject(JSMakeObject(FContext.Heap.NewError('SyntaxError',
        'Cannot link module ' + specifier)));
      Exit(JSMakePromise(promise));
    end;
    FContext.EvaluateModuleBody(dep);
    target.Fulfill(FContext.MakeNamespaceFor(dep));
  except
    on E: EFloriaJSThrow do
      target.Reject(E.Value);
  end;
  Result := JSMakePromise(promise);
end;

constructor TNamespaceGetter.Create(AContext: TFloriaJSContext;
  AModule: TFloriaJSModuleRecord; const AExportName: string);
begin
  inherited Create();
  FContext := AContext;
  FModule := AModule;
  FExportName := AExportName;
end;

function TNamespaceGetter.Get(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := FContext.ResolveImportValue(FModule, FExportName);
end;

procedure TFloriaJSContext.SetModuleLoader(ALoader: TFloriaJSModuleLoader);
begin
  if FModuleRegistry <> nil then
    FModuleRegistry.Loader := ALoader;
end;

{ Module early errors for duplicate top-level declarations. Module code is
  strict, so two function declarations may not share a name, and the
  lexically declared names must be disjoint from the var-declared names. }
function TFloriaJSContext.CheckModuleBindingDuplicates(
  AProgram: TFloriaJSProgram; out AErrorMessage: string): Boolean;
var
  i, j: Integer;
  stmt, inner: TFloriaJSStmtNode;
  varStmt: TFloriaJSVarStmt;
  lexical, varNames, functions: TStringList;
  bindingName: string;
begin
  Result := True;
  AErrorMessage := '';
  if AProgram = nil then Exit;

  lexical := TStringList.Create();
  varNames := TStringList.Create();
  functions := TStringList.Create();
  try
    lexical.CaseSensitive := True;
    varNames.CaseSensitive := True;
    functions.CaseSensitive := True;

    for i := 0 to AProgram.GetStatementCount() - 1 do
    begin
      stmt := AProgram.GetStatement(i);
      if stmt is TFloriaJSExportDecl then
        inner := TFloriaJSExportDecl(stmt).Declaration
      else
        inner := stmt;

      if inner is TFloriaJSVarStmt then
      begin
        varStmt := TFloriaJSVarStmt(inner);
        for j := 0 to varStmt.GetDeclaratorCount() - 1 do
        begin
          bindingName := varStmt.GetDeclaratorName(j);
          if bindingName = '' then Continue;
          if varStmt.Kind in [tkLet, tkConst] then
          begin
            if lexical.IndexOf(bindingName) >= 0 then
            begin
              AErrorMessage := 'Duplicate declaration of ' + bindingName;
              Exit(False);
            end;
            lexical.Add(bindingName);
          end
          else if varNames.IndexOf(bindingName) < 0 then
            varNames.Add(bindingName);
        end;
      end
      else if inner is TFloriaJSFunctionDecl then
      begin
        bindingName := TFloriaJSFunctionDecl(inner).Name;
        if bindingName = '' then Continue;
        if functions.IndexOf(bindingName) >= 0 then
        begin
          AErrorMessage := 'Duplicate declaration of ' + bindingName;
          Exit(False);
        end;
        functions.Add(bindingName);
        if varNames.IndexOf(bindingName) < 0 then
          varNames.Add(bindingName);
      end;
    end;

    for i := 0 to lexical.Count - 1 do
      if varNames.IndexOf(lexical[i]) >= 0 then
      begin
        AErrorMessage := 'Duplicate declaration of ' + lexical[i];
        Exit(False);
      end;
  finally
    lexical.Free();
    varNames.Free();
    functions.Free();
  end;
end;

{ Every top-level binding name: var/let/const declarators, function and class
  declarations, and the inner declaration of an export. }
procedure TFloriaJSContext.CollectModuleBindings(AProgram: TFloriaJSProgram;
  AInto: TStrings);
var
  i, j: Integer;
  stmt, inner: TFloriaJSStmtNode;
begin
  if (AProgram = nil) or (AInto = nil) then Exit;
  for i := 0 to AProgram.GetStatementCount() - 1 do
  begin
    stmt := AProgram.GetStatement(i);
    { An imported binding is a local name, so `export { x }` may name it. }
    if stmt is TFloriaJSImportDecl then
    begin
      for j := 0 to TFloriaJSImportDecl(stmt).GetEntryCount() - 1 do
        AInto.Add(TFloriaJSImportDecl(stmt).GetEntryLocalName(j));
      Continue;
    end;
    inner := nil;
    if stmt is TFloriaJSExportDecl then
      inner := TFloriaJSExportDecl(stmt).Declaration
    else
      inner := stmt;
    if inner is TFloriaJSVarStmt then
    begin
      for j := 0 to TFloriaJSVarStmt(inner).GetDeclaratorCount() - 1 do
        if TFloriaJSVarStmt(inner).GetDeclaratorName(j) <> '' then
          AInto.Add(TFloriaJSVarStmt(inner).GetDeclaratorName(j));
      { A destructuring declarator has no name accessor; mark the module as
        having an unanalysable binding so the undeclared-export check is
        skipped rather than producing a false error. }
      for j := 0 to TFloriaJSVarStmt(inner).GetDeclaratorCount() - 1 do
        if (TFloriaJSVarStmt(inner).GetDeclaratorName(j) = '') and
           (TFloriaJSVarStmt(inner).GetDeclaratorPattern(j) <> nil) then
          AInto.Add('*destructured*');
    end
    else if inner is TFloriaJSFunctionDecl then
      AInto.Add(TFloriaJSFunctionDecl(inner).Name);
  end;
end;

{ Creates an uninitialised binding for every top-level let/const/class. The
  body's own declaration then initialises it. }
procedure TFloriaJSContext.HoistModuleLexicals(AProgram: TFloriaJSProgram;
  AEnv: TFloriaJSEnvironment);
var
  i, j: Integer;
  stmt, inner: TFloriaJSStmtNode;
  varStmt: TFloriaJSVarStmt;
begin
  if (AProgram = nil) or (AEnv = nil) then Exit;
  for i := 0 to AProgram.GetStatementCount() - 1 do
  begin
    stmt := AProgram.GetStatement(i);
    if stmt is TFloriaJSExportDecl then
    begin
      { `export default <expr>` and an anonymous default class create the
        `*default*` binding uninitialised, so reading it before the statement
        runs raises the TDZ error. }
      if TFloriaJSExportDecl(stmt).IsDefault and
         (TFloriaJSExportDecl(stmt).Declaration = nil) then
        AEnv.DeclareLexical('*default*', False, bkLet);
      inner := TFloriaJSExportDecl(stmt).Declaration;
    end
    else
      inner := stmt;
    if inner is TFloriaJSVarStmt then
    begin
      varStmt := TFloriaJSVarStmt(inner);
      if varStmt.Kind in [tkLet, tkConst] then
        for j := 0 to varStmt.GetDeclaratorCount() - 1 do
          if varStmt.GetDeclaratorName(j) <> '' then
          begin
            if varStmt.Kind = tkConst then
              AEnv.DeclareLexical(varStmt.GetDeclaratorName(j), True, bkConst)
            else
              AEnv.DeclareLexical(varStmt.GetDeclaratorName(j), False, bkLet);
          end;
    end;
  end;
end;

{ Parses a module body and populates its five entry lists and dependencies.
  Returns False (with a SyntaxError result) when the source is not a valid
  module. }
function TFloriaJSContext.ParseModuleRecord(
  AModule: TFloriaJSModuleRecord; const ASource: string;
  out AErrorMessage: string): Boolean;
var
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  declareNames, exportNames: TStringList;
  i, j: Integer;
  stmt: TFloriaJSStmtNode;
  importDecl: TFloriaJSImportDecl;
  exportDecl: TFloriaJSExportDecl;
  dep: TFloriaJSModuleRecord;
  request: string;
  seen: TStringList;
begin
  Result := False;
  AErrorMessage := '';
  parser := TFloriaJSParser.Create(ASource);
  try
    parser.SetModuleMode(True);
    prog := parser.ParseProgram();
    if parser.HasErrors() then
    begin
      AErrorMessage := parser.GetError(0);
      prog.Free();
      Exit;
    end;
    AModule.Body := prog;

    { Collect the entry lists. }
    for i := 0 to prog.GetStatementCount() - 1 do
    begin
      stmt := prog.GetStatement(i);
      if stmt is TFloriaJSImportDecl then
      begin
        importDecl := TFloriaJSImportDecl(stmt);
        for j := 0 to importDecl.GetEntryCount() - 1 do
          AModule.AddImport(importDecl.ModuleSpecifier,
            importDecl.GetEntryImportName(j), importDecl.GetEntryLocalName(j));
      end
      else if stmt is TFloriaJSExportDecl then
      begin
        exportDecl := TFloriaJSExportDecl(stmt);
        for j := 0 to exportDecl.GetLocalExportCount() - 1 do
          AModule.AddLocalExport(exportDecl.GetLocalExportName(j),
            exportDecl.GetLocalExportAsName(j));
        { `export const x = 1` (and let/var) export every declared name. A
          default export publishes only `default`, even when it also creates a
          local binding. }
        if (not exportDecl.IsDefault) and
           (exportDecl.Declaration is TFloriaJSVarStmt) then
          for j := 0 to TFloriaJSVarStmt(exportDecl.Declaration).GetDeclaratorCount() - 1 do
            AModule.AddLocalExport(
              TFloriaJSVarStmt(exportDecl.Declaration).GetDeclaratorName(j),
              TFloriaJSVarStmt(exportDecl.Declaration).GetDeclaratorName(j));
        { `export function f() {}` and `export class C {}` export their name. }
        if (not exportDecl.IsDefault) and
           (exportDecl.Declaration is TFloriaJSFunctionDecl) then
          AModule.AddLocalExport(
            TFloriaJSFunctionDecl(exportDecl.Declaration).Name,
            TFloriaJSFunctionDecl(exportDecl.Declaration).Name);
        { A default export is published as "default". }
        if exportDecl.IsDefault then
        begin
          if exportDecl.Declaration is TFloriaJSFunctionDecl then
            AModule.AddLocalExport(
              TFloriaJSFunctionDecl(exportDecl.Declaration).Name, 'default')
          else
            AModule.AddLocalExport('*default*', 'default');
        end;
        for j := 0 to exportDecl.GetIndirectExportCount() - 1 do
          AModule.AddIndirectExport(exportDecl.GetIndirectExportFrom(j),
            exportDecl.GetIndirectExportImportName(j),
            exportDecl.GetIndirectExportExportName(j));
        for j := 0 to exportDecl.GetStarExportCount() - 1 do
          AModule.AddStarExport(exportDecl.GetStarExportFrom(j));
      end;
    end;

    { Resolve every requested module through the loader. }
    if FModuleRegistry.Loader = nil then
    begin
      AErrorMessage := 'no module loader is installed';
      Exit;
    end;
    seen := TStringList.Create();
    try
      seen.CaseSensitive := True;
      for i := 0 to prog.GetStatementCount() - 1 do
      begin
        stmt := prog.GetStatement(i);
        request := '';
        if stmt is TFloriaJSImportDecl then
          request := TFloriaJSImportDecl(stmt).ModuleSpecifier
        else if stmt is TFloriaJSExportDecl then
        begin
          exportDecl := TFloriaJSExportDecl(stmt);
          if exportDecl.GetIndirectExportCount() > 0 then
            request := exportDecl.GetIndirectExportFrom(0)
          else if exportDecl.GetStarExportCount() > 0 then
            request := exportDecl.GetStarExportFrom(0);
        end;
        if (request = '') or (seen.IndexOf(request) >= 0) then
          Continue;
        seen.Add(request);
        dep := FModuleRegistry.Load(request, AModule.Identifier);
        if dep = nil then
        begin
          AErrorMessage := 'Cannot resolve module ' + request;
          Exit;
        end;
        AModule.AddDependency(request, dep);
      end;
      { Indirect and star exports may name several distinct modules. }
      for i := 0 to High(AModule.IndirectExportEntries) do
      begin
        request := AModule.IndirectExportEntries[i].ModuleRequest;
        if seen.IndexOf(request) >= 0 then Continue;
        seen.Add(request);
        dep := FModuleRegistry.Load(request, AModule.Identifier);
        if dep = nil then
        begin
          AErrorMessage := 'Cannot resolve module ' + request;
          Exit;
        end;
        AModule.AddDependency(request, dep);
      end;
      for i := 0 to High(AModule.StarExportEntries) do
      begin
        request := AModule.StarExportEntries[i].ModuleRequest;
        if seen.IndexOf(request) >= 0 then Continue;
        seen.Add(request);
        dep := FModuleRegistry.Load(request, AModule.Identifier);
        if dep = nil then
        begin
          AErrorMessage := 'Cannot resolve module ' + request;
          Exit;
        end;
        AModule.AddDependency(request, dep);
      end;
    finally
      seen.Free();
    end;

    { Module early errors: an export name must be unique across the local and
      indirect entries, and a local export must name a declared binding. }
    declareNames := TStringList.Create();
    exportNames := TStringList.Create();
    try
      declareNames.CaseSensitive := True;
      exportNames.CaseSensitive := True;
      CollectModuleBindings(TFloriaJSProgram(AModule.Body), declareNames);
      if not CheckModuleBindingDuplicates(TFloriaJSProgram(AModule.Body),
        AErrorMessage) then
        Exit;
      for i := 0 to High(AModule.LocalExportEntries) do
      begin
        if exportNames.IndexOf(AModule.LocalExportEntries[i].ExportName) >= 0 then
        begin
          AErrorMessage := 'Duplicate export ' + AModule.LocalExportEntries[i].ExportName;
          Exit;
        end;
        exportNames.Add(AModule.LocalExportEntries[i].ExportName);
        if (AModule.LocalExportEntries[i].LocalName <> '*default*') and
           (declareNames.IndexOf('*destructured*') < 0) and
           (declareNames.IndexOf(AModule.LocalExportEntries[i].LocalName) < 0) then
        begin
          AErrorMessage := 'Export ' + AModule.LocalExportEntries[i].LocalName +
            ' is not declared in the module';
          Exit;
        end;
      end;
      for i := 0 to High(AModule.IndirectExportEntries) do
      begin
        if exportNames.IndexOf(AModule.IndirectExportEntries[i].ExportName) >= 0 then
        begin
          AErrorMessage := 'Duplicate export ' + AModule.IndirectExportEntries[i].ExportName;
          Exit;
        end;
        exportNames.Add(AModule.IndirectExportEntries[i].ExportName);
      end;
    finally
      exportNames.Free();
      declareNames.Free();
    end;

    { Link: parse dependencies depth-first, then validate that every import
      resolves. }
    Result := True;
  finally
    parser.Free();
  end;
end;

{ The current value of an exported binding. The binding lives in the exporting
  module's own environment, so a read is always live. }
function TFloriaJSContext.ResolveImportValue(ADep: TFloriaJSModuleRecord;
  const AName: string): TFloriaJSValue;
var
  binding: TFloriaJSResolvedBinding;
  resolveSet: TStringList;
  res: TFloriaJSResolveResult;
begin
  Result := JSMakeUndefined();
  if ADep = nil then Exit;
  if AName = '*' then
    Exit(MakeNamespaceFor(ADep));
  resolveSet := TStringList.Create();
  try
    resolveSet.CaseSensitive := True;
    res := FloriaJSResolveExport(ADep, AName, resolveSet, binding);
  finally
    resolveSet.Free();
  end;
  if res <> rrResolved then
    Exit(JSMakeUndefined());
  if binding.BindingName = '*' then
    Exit(MakeNamespaceFor(binding.Module));
  if (binding.Module <> nil) and (binding.Module.Environment <> nil) then
    Result := binding.Module.Environment.GetDefault(binding.BindingName,
      JSMakeUndefined());
end;

{ The module namespace object: one property per exported name, each reading
  through to the live binding. }
function TFloriaJSContext.MakeNamespaceFor(
  ADep: TFloriaJSModuleRecord): TFloriaJSValue;
var
  names: TStringList;
  ns: TFloriaJSObject;
  i: Integer;
  exportName: string;
  getter: TFloriaJSFunction;
  accessor: TNamespaceGetter;
  holder: TFloriaJSValue;
begin
  if ADep = nil then
    Exit(JSMakeUndefined());
  if ADep.Namespace.IsObject() then
    Exit(ADep.Namespace);

  names := TStringList.Create();
  try
    names.CaseSensitive := True;
    ADep.CollectExportedNames(names);
    ns := FHeap.NewObject(nil, True);
    for i := 0 to names.Count - 1 do
    begin
      exportName := names[i];
      { The getter closes over the exporting module and the export name. }
      accessor := TNamespaceGetter.Create(Self, ADep, exportName);
      getter := FHeap.NewNativeMethod('get ' + exportName, @accessor.Get);
      ns.DefineAccessorProperty(exportName, JSMakeFunction(getter), JSMakeUndefined(),
        True, False);
    end;
    holder := JSMakeObject(ns);
    ADep.Namespace := holder;
    Result := holder;
  finally
    names.Free();
  end;
end;

{ Creates the environment a module body runs in: a child of the global scope
  with no delegate object, so module bindings never appear on globalThis. }
function TFloriaJSContext.CreateModuleEnvironment: TFloriaJSEnvironment;
begin
  Result := TFloriaJSEnvironment(FHeap.TrackEnvironment(
    TFloriaJSEnvironment.Create(FGlobalEnv, FHeap)));
end;

{ Link(module): parse dependencies, then resolve every import to a concrete
  binding or namespace. A failure is reported as a SyntaxError result. }
function TFloriaJSContext.LinkModule(AModule: TFloriaJSModuleRecord;
  out AErrorMessage: string): Boolean;
var
  i: Integer;
  dep: TFloriaJSModuleRecord;
  binding: TFloriaJSResolvedBinding;
  resolveSet: TStringList;
  res: TFloriaJSResolveResult;
  request: string;
begin
  Result := False;
  AErrorMessage := '';

  { Any status past linked means linking is done; re-linking an evaluated
    module would reset it and cause a re-evaluation. }
  if AModule.Status in [fmsLinking, fmsLinked, fmsEvaluating, fmsEvaluated,
    fmsErrored] then
    Exit(AModule.Status <> fmsErrored);

  AModule.Status := fmsLinking;
  try
    if AModule.Body = nil then
    begin
      AErrorMessage := 'module body is not parsed';
      Exit;
    end;

    { Parse and link the dependencies first, which flattens the import graph. }
    for i := 0 to AModule.RequestedModules.Count - 1 do
    begin
      dep := TFloriaJSModuleRecord(AModule.RequestedModules.Objects[i]);
      if (dep = nil) or (dep = AModule) then Continue;
      if dep.Status in [fmsLinking, fmsLinked, fmsEvaluating, fmsEvaluated,
        fmsErrored] then Continue;
      if dep.Body = nil then
      begin
        if dep.SourceText = '' then
        begin
          AErrorMessage := 'module ' + dep.Identifier + ' has no source';
          Exit;
        end;
        if not ParseModuleRecord(dep, dep.SourceText, AErrorMessage) then
          Exit;
      end;
      if not LinkModule(dep, AErrorMessage) then
        Exit;
    end;

    resolveSet := TStringList.Create();
    try
      resolveSet.CaseSensitive := True;
      for i := 0 to High(AModule.ImportEntries) do
      begin
        request := AModule.ImportEntries[i].ModuleRequest;
        dep := AModule.DependencyFor(request);
        if dep = nil then
        begin
          AErrorMessage := 'Cannot resolve module ' + request;
          Exit;
        end;
        if AModule.ImportEntries[i].ImportName = '*' then
          Continue;
        res := FloriaJSResolveExport(dep, AModule.ImportEntries[i].ImportName,
          resolveSet, binding);
        if res = rrAmbiguous then
        begin
          AErrorMessage := 'Ambiguous export ' + AModule.ImportEntries[i].ImportName +
            ' from ' + request;
          Exit;
        end;
        if res <> rrResolved then
        begin
          AErrorMessage := 'The requested module ' + request +
            ' does not provide an export named ' + AModule.ImportEntries[i].ImportName;
          Exit;
        end;
      end;
    finally
      resolveSet.Free();
    end;

    { Compile now, so a duplicate binding or another early error is reported at
      link time, which is a parse-phase SyntaxError. }
    if (AModule.Chunk = nil) and (AModule.Body <> nil) then
      AModule.Chunk := FCompiler.CompileProgram(TFloriaJSProgram(AModule.Body));

    AModule.Environment := CreateModuleEnvironment;
    { Install one binding per import entry. A namespace import binds the
      dependency's namespace object; a named or default import is a live
      mirror of the exporting module's binding. }
    for i := 0 to High(AModule.ImportEntries) do
    begin
      request := AModule.ImportEntries[i].ModuleRequest;
      dep := AModule.DependencyFor(request);
      if dep = nil then Continue;
      AModule.Environment.DefineImport(AModule.ImportEntries[i].LocalName, dep,
        AModule.ImportEntries[i].ImportName, @ReadImportBinding);
    end;
    AModule.Status := fmsLinked;
    Result := True;
  finally
    if (not Result) and (AModule.Status = fmsLinking) then
      AModule.Status := fmsErrored;
  end;
end;

{ Evaluates a linked module. Cycle-safe: a module already evaluating returns
  immediately, which is what lets a cycle observe the partial bindings of its
  peer. }
{ Links one dependency: parse it if necessary, then link it. }
function TFloriaJSContext.LinkDependency(
  ADep: TFloriaJSModuleRecord): Boolean;
var
  message: string;
begin
  Result := False;
  if ADep = nil then Exit;
  if ADep.Status in [fmsLinking, fmsLinked, fmsEvaluating, fmsEvaluated] then
    Exit(True);
  if ADep.Body = nil then
  begin
    if ADep.SourceText = '' then
      Exit;
    if not ParseModuleRecord(ADep, ADep.SourceText, message) then
      Exit;
  end;
  Result := LinkModule(ADep, message);
end;

function TFloriaJSContext.ReadImportBinding(AModule: TObject;
  const AImportName: string): TFloriaJSValue;
begin
  Result := ResolveImportValue(TFloriaJSModuleRecord(AModule), AImportName);
end;

function TFloriaJSContext.MakeImportMeta(
  AModule: TFloriaJSModuleRecord): TFloriaJSValue;
var
  meta: TFloriaJSObject;
begin
  if AModule = nil then
    Exit(JSMakeUndefined());
  if AModule.Meta.IsObject() then
    Exit(AModule.Meta);
  meta := FHeap.NewObject(nil, True);
  meta.SetProperty('url', JSMakeString(AModule.Identifier));
  AModule.Meta := JSMakeObject(meta);
  Result := AModule.Meta;
end;

procedure TFloriaJSContext.RefreshImports(AModule: TFloriaJSModuleRecord);
var
  i: Integer;
  dep: TFloriaJSModuleRecord;
  request, localName: string;
begin
  if (AModule = nil) or (AModule.Environment = nil) then Exit;
  for i := 0 to High(AModule.ImportEntries) do
  begin
    request := AModule.ImportEntries[i].ModuleRequest;
    localName := AModule.ImportEntries[i].LocalName;
    dep := AModule.DependencyFor(request);
    if dep = nil then Continue;
    AModule.Environment.DefineImport(localName, dep,
      AModule.ImportEntries[i].ImportName, @ReadImportBinding);
  end;
end;

procedure TFloriaJSContext.EvaluateModuleBody(AModule: TFloriaJSModuleRecord);
var
  i: Integer;
  dep: TFloriaJSModuleRecord;
  code: TFloriaJSBytecode;
  prog: TFloriaJSProgram;
  savedEnv: TFloriaJSEnvironment;
  importer: TDynamicImporter;
begin
  if AModule.Status = fmsEvaluated then Exit;
  if AModule.Status = fmsEvaluating then Exit;
  if AModule.Status = fmsErrored then Exit;

  AModule.Status := fmsEvaluating;
  try
    { Depth-first, in source order, as 16.2.1.5.3.3 requires. }
    for i := 0 to AModule.RequestedModules.Count - 1 do
    begin
      dep := TFloriaJSModuleRecord(AModule.RequestedModules.Objects[i]);
      if dep <> nil then
        EvaluateModuleBody(dep);
    end;

    { A module's top-level let/const/class are created uninitialised before the
      body runs, so a read before the declaration raises the TDZ error. }
    HoistModuleLexicals(TFloriaJSProgram(AModule.Body), AModule.Environment);
    { The dependencies have evaluated, so import bindings can now be read. }
    RefreshImports(AModule);
    { A module body can read import.meta and call the dynamic import. }
    AModule.Environment.Define('import.meta', MakeImportMeta(AModule), True);
    importer := TDynamicImporter.Create(Self, AModule);
    AModule.Environment.Define('import', JSMakeFunction(
      FHeap.NewNativeMethod('import', @importer.Import)), True);

    prog := TFloriaJSProgram(AModule.Body);
    if prog <> nil then
    begin
      if AModule.Chunk <> nil then
        code := TFloriaJSBytecode(AModule.Chunk)
      else
      begin
        code := FCompiler.CompileProgram(prog);
        AModule.Chunk := code;
      end;
      savedEnv := FGlobalEnv;
      try
        { The module body runs in its own environment, not the global one. The
          var environment is the module's too, so a top-level declaration
          binds there rather than on globalThis. }
        FVM.Execute(code, AModule.Environment, JSMakeUndefined(),
          AModule.Environment);
        { The default export was bound under a private name; publish it under
          the export key the resolver looks for. }
      finally
        FGlobalEnv := savedEnv;
      end;
    end;

    AModule.Status := fmsEvaluated;
  except
    on E: EFloriaJSThrow do
    begin
      AModule.EvaluationError := E.Value;
      AModule.Status := fmsErrored;
      raise;
    end;
  end;
end;

function TFloriaJSContext.EvaluateModuleDetailed(const AIdentifier,
  ASource: string): TFloriaJSDiagnosticResult;
var
  module: TFloriaJSModuleRecord;
  errorMessage: string;
begin
  AssignDiagnostic(Result, FloriaJSMakeOkResult(''), fjdkSuccess,
    AIdentifier, '', '', '');
  if FModuleRegistry = nil then
  begin
    AssignDiagnostic(Result, FloriaJSMakeErrorResult('module registry unavailable'),
      fjdkHostException, AIdentifier, '', 'module registry unavailable', '');
    Exit;
  end;
  if AIdentifier = '' then
  begin
    AssignDiagnostic(Result, FloriaJSMakeErrorResult('a module needs an identifier'),
      fjdkParseError, AIdentifier, 'SyntaxError',
      'a module needs an identifier', '');
    Exit;
  end;

  module := FModuleRegistry.Find(AIdentifier);
  if module = nil then
  begin
    module := TFloriaJSModuleRecord.Create(AIdentifier, FModuleRegistry);
    FModuleRegistry.Add(module);
  end;

  if module.Body = nil then
  begin
    if not ParseModuleRecord(module, ASource, errorMessage) then
    begin
      AssignDiagnostic(Result, FloriaJSMakeErrorResult(errorMessage),
        fjdkParseError, AIdentifier, 'SyntaxError', errorMessage, '');
      Exit;
    end;
  end;

  if FHeap <> nil then
    FHeap.Collect();

  try
    if not LinkModule(module, errorMessage) then
    begin
      AssignDiagnostic(Result, FloriaJSMakeErrorResult(errorMessage),
        fjdkParseError, AIdentifier, 'SyntaxError', errorMessage, '');
      Exit;
    end;
  except
    on E: EFloriaJSCompileError do
    begin
      AssignDiagnostic(Result, FloriaJSMakeErrorResult(E.Message),
        fjdkCompileError, AIdentifier, 'SyntaxError', E.Message, '');
      Exit;
    end;
  end;

  try
    EvaluateModuleBody(module);
  except
    on E: EFloriaJSCompileError do
    begin
      AssignDiagnostic(Result, FloriaJSMakeErrorResult(E.Message),
        fjdkCompileError, AIdentifier, 'SyntaxError', E.Message, '');
      Exit;
    end;
    on E: EFloriaJSThrow do
    begin
      if E.Value.IsObject() and (E.Value.ObjVal is TFloriaJSError) then
        AssignDiagnostic(Result, FloriaJSMakeErrorResult(E.Message),
          fjdkJavaScriptThrow, AIdentifier,
          TFloriaJSError(E.Value.ObjVal).Name, TFloriaJSError(E.Value.ObjVal).Message, '')
      else
        AssignDiagnostic(Result, FloriaJSMakeErrorResult(E.Message),
          fjdkJavaScriptThrow, AIdentifier, '', E.Message, '');
      Exit;
    end;
    on E: Exception do
    begin
      AssignDiagnostic(Result, FloriaJSMakeErrorResult(E.Message),
        fjdkHostException, AIdentifier, '', E.Message, E.ClassName);
      Exit;
    end;
  end;

  DrainPromiseJobs();
end;

function TFloriaJSContext.EvaluateModule(const AIdentifier,
  ASource: string): TFloriaJSResult;
var
  module: TFloriaJSModuleRecord;
  errorMessage: string;
  errVal: TFloriaJSValue;
begin
  Result := FloriaJSMakeOkResult('');
  if FModuleRegistry = nil then
    Exit(FloriaJSMakeErrorResult('module registry is unavailable'));

  if AIdentifier = '' then
    Exit(FloriaJSMakeErrorResult('SyntaxError: a module needs an identifier'));

  module := FModuleRegistry.Find(AIdentifier);
  if module = nil then
  begin
    module := TFloriaJSModuleRecord.Create(AIdentifier, FModuleRegistry);
    if not ParseModuleRecord(module, ASource, errorMessage) then
    begin
      module.Free();
      Exit(FloriaJSMakeErrorResult('SyntaxError: ' + errorMessage));
    end;
    FModuleRegistry.Add(module);
  end
  else if module.Body = nil then
  begin
    if not ParseModuleRecord(module, ASource, errorMessage) then
      Exit(FloriaJSMakeErrorResult('SyntaxError: ' + errorMessage));
  end;

  if FHeap <> nil then
    FHeap.Collect();

  if not LinkModule(module, errorMessage) then
    Exit(FloriaJSMakeErrorResult('SyntaxError: ' + errorMessage));

  try
    EvaluateModuleBody(module);
  except
    on E: EFloriaJSThrow do
    begin
      errVal := E.Value;
      Result := FloriaJSMakeErrorResult(E.Message);
      Exit;
    end;
  end;

  DrainPromiseJobs();
  Result := FloriaJSMakeOkResult('');
end;

function TFloriaJSContext.GetModuleNamespace(
  const AIdentifier: string): TFloriaJSValue;
var
  module: TFloriaJSModuleRecord;
begin
  Result := JSMakeUndefined();
  if FModuleRegistry = nil then Exit;
  module := FModuleRegistry.Find(AIdentifier);
  if module = nil then Exit;
  Result := module.Namespace;
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
