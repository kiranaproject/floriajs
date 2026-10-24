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
  floria.js.value, floria.js.env, floria.js.evaluator, floria.js.stdlib,
  floria.js.bytecode, floria.js.vm, floria.js.compiler;

type
  { Execution Backend Engine }
  TFloriaJSExecutionBackend = (fjbInterpreter, fjbBytecodeVM);

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
    FEvaluator: TFloriaJSEvaluator;
    FVM: TFloriaJSVM;
    FCompiler: TFloriaJSCompiler;
    FBackend: TFloriaJSExecutionBackend;
    FOutput: TStringList;

    procedure InitContext();
    function  EvaluateScript(const AScript: string): TFloriaJSValue;
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
    function  EvaluateValue(const AScript: string): TFloriaJSValue; virtual;
    function  EvaluateBytecode(const AScript: string): TFloriaJSResult; virtual;
    function  Call(const AFuncName: string; const AArgs: array of TFloriaJSValue): TFloriaJSValue; virtual;

    { Gives a value that was handed out back to the runtime. The object the
      value points at becomes eligible for reclamation once nothing refers to
      it any more. }
    procedure ReleaseValue(const AValue: TFloriaJSValue); virtual;

    procedure Reset(); virtual;

    property Engine: TFloriaJSEngine read FEngine;
    property Name: string read FName write FName;
    property Heap: TFloriaJSHeap read FHeap;
    property GlobalEnv: TFloriaJSEnvironment read FGlobalEnv;
    property Evaluator: TFloriaJSEvaluator read FEvaluator;
    property VM: TFloriaJSVM read FVM;
    property Compiler: TFloriaJSCompiler read FCompiler;
    property Backend: TFloriaJSExecutionBackend read FBackend write FBackend;
    property Output: TStringList read FOutput;
  end;

  { TFloriaJSEngine — Main JavaScript Runtime Engine }
  TFloriaJSEngine = class
  private
    FInitialized: Boolean;
    FContexts: TFPList;
    FDefaultContext: TFloriaJSContext;
    FMemoryLimit: NativeUInt;
    FBackend: TFloriaJSExecutionBackend;
    function  GetBackend(): TFloriaJSExecutionBackend;
    procedure SetBackend(ABackend: TFloriaJSExecutionBackend);
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Initialize(); virtual;
    function  CreateContext(const AName: string = ''): TFloriaJSContext;
    procedure DestroyContext(AContext: TFloriaJSContext);

    function  Execute(const AScript: string): TFloriaJSResult; virtual;
    function  ExecuteValue(const AScript: string): TFloriaJSValue; virtual;
    function  ExecuteBytecode(const AScript: string): TFloriaJSResult; virtual;
    procedure ReleaseValue(const AValue: TFloriaJSValue); virtual;
    procedure RegisterFunction(const AName: string; AProc: TFloriaJSNativeProc);

    property Initialized: Boolean read FInitialized;
    property DefaultContext: TFloriaJSContext read FDefaultContext;
    property MemoryLimit: NativeUInt read FMemoryLimit write FMemoryLimit;
    property Backend: TFloriaJSExecutionBackend read GetBackend write SetBackend;
  end;

implementation

{ TFloriaJSContext }

constructor TFloriaJSContext.Create(AEngine: TFloriaJSEngine; const AName: string = 'global');
begin
  inherited Create();
  FEngine := AEngine;
  FName := AName;
  FBackend := fjbInterpreter;
  if AEngine <> nil then
    FBackend := AEngine.Backend;
  FOutput := TStringList.Create();
  FHeap := TFloriaJSHeap.Create();
  FGlobalEnv := TFloriaJSEnvironment(FHeap.TrackEnvironment(TFloriaJSEnvironment.Create(nil)));
  FEvaluator := TFloriaJSEvaluator.Create(FHeap);
  FVM := TFloriaJSVM.Create(FHeap);
  FVM.GlobalEnv := FGlobalEnv;
  FCompiler := TFloriaJSCompiler.Create();

  InitContext();
end;

destructor TFloriaJSContext.Destroy();
begin
  FreeAndNil(FCompiler);
  FreeAndNil(FVM);
  FreeAndNil(FEvaluator);
  FreeAndNil(FHeap);
  FGlobalEnv := nil;
  FreeAndNil(FOutput);
  inherited Destroy();
end;

procedure TFloriaJSContext.InitContext();
begin
  FloriaJSRegisterStdLib(FGlobalEnv, FHeap, FOutput);
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

function TFloriaJSContext.EvaluateBytecode(const AScript: string): TFloriaJSResult;
var
  savedBackend: TFloriaJSExecutionBackend;
begin
  savedBackend := FBackend;
  FBackend := fjbBytecodeVM;
  try
    Result := Evaluate(AScript);
  finally
    FBackend := savedBackend;
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
        raise Exception.Create(parser.GetError(0));

      if FBackend = fjbBytecodeVM then
      begin
        code := FCompiler.CompileProgram(prog);
        try
          Result := FVM.Execute(code, FGlobalEnv);
        finally
          code.Free();
        end;
      end
      else
        Result := FEvaluator.ExecuteProgram(prog, FGlobalEnv);
    finally
      prog.Free();
    end;
  finally
    parser.Free();
  end;
end;

function TFloriaJSContext.Call(const AFuncName: string; const AArgs: array of TFloriaJSValue): TFloriaJSValue;
var
  fnVal: TFloriaJSValue;
begin
  fnVal := GetGlobal(AFuncName);
  if not fnVal.IsFunction() then
    Exit(JSMakeUndefined());

  if FBackend = fjbBytecodeVM then
    Result := FVM.CallFunction(fnVal, AArgs, JSMakeUndefined())
  else
    Result := FEvaluator.CallFunction(fnVal, AArgs, JSMakeUndefined());

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
  FGlobalEnv := TFloriaJSEnvironment(FHeap.TrackEnvironment(TFloriaJSEnvironment.Create(nil)));
  FVM.ResetStack();
  FOutput.Clear();
  InitContext();
end;

{ TFloriaJSEngine }

constructor TFloriaJSEngine.Create();
begin
  inherited Create();
  FInitialized := False;
  FBackend := fjbInterpreter;
  FMemoryLimit := 64 * 1024 * 1024; { Default 64MB memory limit }
  FContexts := TFPList.Create();
  Initialize();
end;

function TFloriaJSEngine.GetBackend(): TFloriaJSExecutionBackend;
begin
  Result := FBackend;
end;

procedure TFloriaJSEngine.SetBackend(ABackend: TFloriaJSExecutionBackend);
var
  i: Integer;
begin
  FBackend := ABackend;
  if FContexts <> nil then
    for i := 0 to FContexts.Count - 1 do
      TFloriaJSContext(FContexts[i]).Backend := ABackend;
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

function TFloriaJSEngine.ExecuteBytecode(const AScript: string): TFloriaJSResult;
begin
  if FDefaultContext <> nil then
    Result := FDefaultContext.EvaluateBytecode(AScript)
  else
    Result := FloriaJSMakeErrorResult('No active execution context');
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
