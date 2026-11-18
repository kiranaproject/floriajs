{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Bytecode Virtual Machine Execution Engine       }
{                                                                          }
{   High-performance stack-based virtual machine for QML V4-class          }
{   JavaScript execution, local variable slots, and call frames.           }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.vm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, floria.js.types, floria.js.value,
  floria.js.env, floria.js.bytecode, floria.js.collections, floria.js.utf16;

type
  { Call Stack Frame }
  TFloriaJSCallFrame = record
    Bytecode: TFloriaJSBytecode;
    IP: Integer;
    BaseBP: Integer;
    ThisVal: TFloriaJSValue;
    Env: TFloriaJSEnvironment;
    { Target for var/function declarations. It differs from Env for a
      non-strict eval, whose lexical declarations go to Env but whose var
      declarations go to the caller's variable environment. }
    VarEnv: TFloriaJSEnvironment;
    InitialEnv: TFloriaJSEnvironment;
    OwnsCallEnv: Boolean;
    IsConstructor: Boolean;
    ConstructedObj: TFloriaJSObject;
  end;

  { Exception Try/Catch Handler Entry }
  TFloriaJSTryEntry = record
    CatchIP: Integer;
    FrameIndex: Integer;
    StackDepth: Integer;
    Env: TFloriaJSEnvironment;
  end;

  { Virtual Machine }
  TFloriaJSVM = class
  private
    FHeap: TFloriaJSHeap;
    FOwnsHeap: Boolean;
    FGlobalEnv: TFloriaJSEnvironment;

    { Value Stack }
    FStack: array of TFloriaJSValue;
    FSP: Integer;
    FStackCapacity: Integer;

    { Call Frames }
    FFrames: array of TFloriaJSCallFrame;
    FFP: Integer;
    FFrameCapacity: Integer;
    FMaxCallDepth: Integer;

    { The generator whose body is currently executing, and the value it last
      yielded. Set while RunLoop runs a generator frame so opYield can suspend
      by unwinding to the generator runner. }
    FActiveGenerator: TFloriaJSGenerator;
    FYieldedValue: TFloriaJSValue;
    FIsSuspending: Boolean;

    { Try/Catch Exception Stack }
    FTryHandlers: array of TFloriaJSTryEntry;
    FTryCount: Integer;
    FTryCapacity: Integer;

    procedure EnsureStackCapacity();
    procedure PushFrame(ABytecode: TFloriaJSBytecode; AEnv: TFloriaJSEnvironment; const AThis: TFloriaJSValue; ABaseBP: Integer = 0; AIsConstructor: Boolean = False; AConstructedObj: TFloriaJSObject = nil; AOwnsCallEnv: Boolean = False; AVarEnv: TFloriaJSEnvironment = nil);
    procedure PopFrame();

    procedure PushTryHandler(ACatchIP: Integer; AFrameIndex, AStackDepth: Integer; AEnv: TFloriaJSEnvironment);
    procedure PopTryHandler();
    procedure HandleThrow(const AErrVal: TFloriaJSValue);
    function  RunLoop(AInitialFP, AInitialBaseBP: Integer): TFloriaJSValue;

    function  GetMemberValue(const AObj: TFloriaJSValue; const APropName: string): TFloriaJSValue;
    procedure SetMemberValue(const AObj: TFloriaJSValue; const APropName: string; const AVal: TFloriaJSValue);
    function  HeapInvoker(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;
    function  InvokeNative(const AFn: TFloriaJSFunction; const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;
    function  HeapConstructor(const AFuncVal: TFloriaJSValue; const AArgs: TFloriaJSValueArray): TFloriaJSValue;
    procedure HeapJobRunner(const AJob: TFloriaJSPromiseJob);
    function  EvalIndirect(const ASource: string): TFloriaJSValue;
    function  EvalSource(const ASource: string; AEnv, AVarEnv: TFloriaJSEnvironment;
      const AThis: TFloriaJSValue): TFloriaJSValue;
    function  RunGenerator(AGen: TFloriaJSGenerator; const ASent: TFloriaJSValue;
      out AValue: TFloriaJSValue; out ADone: Boolean): Boolean;
    function  MakeGenerator(AFn: TFloriaJSFunction; const AArgs: array of TFloriaJSValue;
      const AThisVal: TFloriaJSValue; AParentEnv: TFloriaJSEnvironment): TFloriaJSGenerator;
    function  ResolveCallThis(const ASubCode: TFloriaJSBytecode;
      const AThisVal: TFloriaJSValue): TFloriaJSValue;
    procedure SuspendActiveFrame(const AValue: TFloriaJSValue);
    procedure ResumeAsyncTask(ATask: TFloriaJSGenerator;
      const AValue: TFloriaJSValue; AIsRejection: Boolean);
    procedure FinishAsyncTask(ATask: TFloriaJSGenerator;
      const AValue: TFloriaJSValue; AIsRejection: Boolean);
    function  StartAsyncTask(AFn: TFloriaJSFunction;
      const AArgs: array of TFloriaJSValue; const AThisVal: TFloriaJSValue;
      AParentEnv: TFloriaJSEnvironment): TFloriaJSPromise;
    function  StartAsyncGenerator(AFn: TFloriaJSFunction;
      const AArgs: array of TFloriaJSValue; const AThisVal: TFloriaJSValue;
      AParentEnv: TFloriaJSEnvironment): TFloriaJSGenerator;
    function  AsyncGeneratorNext(AGen: TFloriaJSGenerator;
      const ASent: TFloriaJSValue; AMode: Integer): TFloriaJSPromise;
    procedure FinishAsyncGenerator(ATask: TFloriaJSGenerator;
      const AValue: TFloriaJSValue; ADone: Boolean);
  public
    constructor Create(AHeap: TFloriaJSHeap = nil; AGlobalEnv: TFloriaJSEnvironment = nil);
    destructor Destroy(); override;

    { Stack Operations }
    procedure Push(const AVal: TFloriaJSValue);
    function  Pop(): TFloriaJSValue;
    function  Peek(ADepth: Integer = 0): TFloriaJSValue;
    function  GetStackDepth(): Integer;
    procedure ResetStack();

    { Execution Entry Points }
    function  Execute(ABytecode: TFloriaJSBytecode; AEnv: TFloriaJSEnvironment = nil): TFloriaJSValue;
    function  Execute(ABytecode: TFloriaJSBytecode; AEnv: TFloriaJSEnvironment; const AThis: TFloriaJSValue; AVarEnv: TFloriaJSEnvironment = nil): TFloriaJSValue;
    function  CallFunction(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue): TFloriaJSValue;
    function  CallFunction(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue; const AThisVal: TFloriaJSValue): TFloriaJSValue;
    function  ConstructObject(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue): TFloriaJSValue;

    property Heap: TFloriaJSHeap read FHeap;
    property GlobalEnv: TFloriaJSEnvironment read FGlobalEnv write FGlobalEnv;
    property MaxCallDepth: Integer read FMaxCallDepth write FMaxCallDepth;
  end;

implementation

uses
  floria.js.parser, floria.js.compiler, floria.js.ast;

{ TFloriaJSVM }

constructor TFloriaJSVM.Create(AHeap: TFloriaJSHeap; AGlobalEnv: TFloriaJSEnvironment);
begin
  inherited Create();
  if AHeap <> nil then
  begin
    FHeap := AHeap;
    FOwnsHeap := False;
  end
  else
  begin
    FHeap := TFloriaJSHeap.Create();
    FOwnsHeap := True;
  end;

  FGlobalEnv := AGlobalEnv;
  if (FGlobalEnv <> nil) and (FGlobalEnv.Heap = nil) then
    FGlobalEnv.Heap := FHeap;
  FMaxCallDepth := 512;

  FStackCapacity := 256;
  SetLength(FStack, FStackCapacity);
  FSP := 0;

  FFrameCapacity := 64;
  SetLength(FFrames, FFrameCapacity);
  FFP := -1;

  FTryCapacity := 16;
  SetLength(FTryHandlers, FTryCapacity);
  FTryCount := 0;

  FActiveGenerator := nil;
  FYieldedValue := JSMakeUndefined();
  FIsSuspending := False;

  if FHeap <> nil then
  begin
    FHeap.SetFunctionInvoker(@HeapInvoker);
    FHeap.SetConstructInvoker(@HeapConstructor);
    FHeap.SetEvalInvoker(@EvalIndirect);
    { Without this the queue filled up and was silently dropped, so no `.then`,
      `.catch`, or `.finally` callback ever ran. }
    FHeap.SetJobRunner(@HeapJobRunner);
  end;
end;

function TFloriaJSVM.InvokeNative(const AFn: TFloriaJSFunction;
  const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;
var
  savedHeap: TFloriaJSHeap;
begin
  savedHeap := JSActiveRealmHeap();
  JSSetActiveRealmHeap(AFn.Heap);
  try
    if Assigned(AFn.NativeMethod) then
      Result := AFn.NativeMethod(AArgs, AThis)
    else if Assigned(AFn.NativeProc) then
      Result := AFn.NativeProc(AArgs, AThis)
    else
      Result := JSMakeUndefined();
  finally
    JSSetActiveRealmHeap(savedHeap);
  end;
end;

function TFloriaJSVM.EvalIndirect(const ASource: string): TFloriaJSValue;
begin
  Result := EvalSource(ASource, FGlobalEnv, FGlobalEnv, JSMakeUndefined());
end;

function TFloriaJSVM.EvalSource(const ASource: string; AEnv, AVarEnv: TFloriaJSEnvironment;
  const AThis: TFloriaJSValue): TFloriaJSValue;
var
  parser: TFloriaJSParser;
  prog: TFloriaJSProgram;
  code: TFloriaJSBytecode;
  compiler: TFloriaJSCompiler;
  evalEnv: TFloriaJSEnvironment;
begin
  if Length(Trim(ASource)) = 0 then
    Exit(JSMakeUndefined());
  if AEnv = nil then
    AEnv := FGlobalEnv;

  parser := TFloriaJSParser.Create(ASource);
  try
    prog := parser.ParseProgram();
    try
      if parser.HasErrors() then
        raise EFloriaJSThrow.Create(JSMakeObject(
          FHeap.NewError('SyntaxError', parser.GetError(0))));

      compiler := TFloriaJSCompiler.Create();
      try
        try
          code := compiler.CompileProgram(prog);
        except
          on E: EFloriaJSCompileError do
            raise EFloriaJSThrow.Create(JSMakeObject(
              FHeap.NewError('SyntaxError', E.Message)));
        end;
      finally
        compiler.Free();
      end;

      try
        { Strict eval gets its own variable environment; non-strict direct eval
          uses the caller's environment so `var` declarations are visible there.
          The re-entrant path deliberately skips heap collection and microtask
          draining while the caller's frame still holds live values. }
        if code.IsStrict then
        begin
          { Strict eval has one fresh environment for var and lexical
            declarations. }
          evalEnv := TFloriaJSEnvironment.Create(AEnv, FHeap);
          FHeap.TrackEnvironment(evalEnv);
          try
            Result := Execute(code, evalEnv, AThis, evalEnv);
          finally
            if evalEnv.Captured then
              evalEnv.Detach()
            else
            begin
              FHeap.Untrack(evalEnv);
              evalEnv.Free();
            end;
          end;
        end
        else
        begin
          { Non-strict eval puts var/function declarations in the caller's
            variable environment and lexical declarations in a fresh
            environment that disappears after evaluation. }
          evalEnv := TFloriaJSEnvironment.Create(AEnv, FHeap);
          FHeap.TrackEnvironment(evalEnv);
          try
            if AVarEnv <> nil then
              Result := Execute(code, evalEnv, AThis, AVarEnv)
            else
              Result := Execute(code, evalEnv, AThis, AEnv);
          finally
            if evalEnv.Captured then
              evalEnv.Detach()
            else
            begin
              FHeap.Untrack(evalEnv);
              evalEnv.Free();
            end;
          end;
        end;
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

function TFloriaJSVM.HeapInvoker(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := CallFunction(AFuncVal, AArgs, AThis);
end;

function TFloriaJSVM.HeapConstructor(const AFuncVal: TFloriaJSValue; const AArgs: TFloriaJSValueArray): TFloriaJSValue;
begin
  Result := ConstructObject(AFuncVal, AArgs);
end;

{ Runs one settled-promise reaction. The handler receives the settled value; its
  return value settles the child promise. A throw rejects the child instead. }



{ Creates a suspended generator for AFn, binding its parameters into a fresh
  activation environment exactly as a normal call does. All three call paths
  (opCall, opCallOpt, and CallFunction) use this so they cannot diverge. }
function TFloriaJSVM.ResolveCallThis(const ASubCode: TFloriaJSBytecode;
  const AThisVal: TFloriaJSValue): TFloriaJSValue;
begin
  { A plain call of a non-strict function receives the global object. Strict
    functions keep undefined, and explicit receivers are unchanged. }
  if (ASubCode <> nil) and (not ASubCode.IsStrict) and
     (AThisVal.IsUndefined() or AThisVal.IsNull()) and
     (FGlobalEnv <> nil) and (FGlobalEnv.DelegateObject <> nil) then
    Result := JSMakeObject(FGlobalEnv.DelegateObject)
  else
    Result := AThisVal;
end;

function TFloriaJSVM.MakeGenerator(AFn: TFloriaJSFunction;
  const AArgs: array of TFloriaJSValue; const AThisVal: TFloriaJSValue;
  AParentEnv: TFloriaJSEnvironment): TFloriaJSGenerator;
var
  subCode: TFloriaJSBytecode;
  callEnv: TFloriaJSEnvironment;
  argsArr: TFloriaJSArray;
  argsCopy: TFloriaJSValueArray;
  i: Integer;
begin
  subCode := TFloriaJSBytecode(AFn.Bytecode);

  if AFn.ClosureEnv <> nil then
    callEnv := TFloriaJSEnvironment.Create(TFloriaJSEnvironment(AFn.ClosureEnv), FHeap)
  else
    callEnv := TFloriaJSEnvironment.Create(AParentEnv, FHeap);
  FHeap.TrackEnvironment(callEnv);
  if AFn.IsNamedExpression then
    callEnv.Define(AFn.Name, JSMakeFunction(AFn), True);

  if subCode.LocalsInEnv then
    for i := 0 to subCode.GetArgumentCount() - 1 do
    begin
      if i < Length(AArgs) then
        callEnv.Define(subCode.GetArgumentName(i), AArgs[i], False)
      else
        callEnv.Define(subCode.GetArgumentName(i), JSMakeUndefined(), False);
    end;
  if not AFn.IsArrow then
  begin
    callEnv.Define('this', AThisVal);
    if (FHeap <> nil) and subCode.NeedsArguments then
    begin
      argsArr := FHeap.NewArray();
      for i := 0 to High(AArgs) do
        argsArr.Push(AArgs[i]);
      callEnv.Define('arguments', JSMakeObject(argsArr));
    end;
  end;

  Result := TFloriaJSGenerator(FHeap.Track(TFloriaJSGenerator.Create(FHeap)));
  if AFn.IsAsyncGenerator then
    Result.Prototype := FHeap.GetAsyncGeneratorPrototype();
  Result.Bytecode := subCode;
  Result.SetEnv(callEnv);
  SetLength(argsCopy, Length(AArgs));
  for i := 0 to High(AArgs) do
    argsCopy[i] := AArgs[i];
  Result.Args := argsCopy;
  Result.ThisVal := AThisVal;
  Result.Runner := @RunGenerator;
end;

procedure TFloriaJSVM.HeapJobRunner(const AJob: TFloriaJSPromiseJob);
var
  handler, arg, resultValue: TFloriaJSValue;
begin
  if AJob.Kind <> pjkReaction then
  begin
    if AJob.Target <> nil then
    begin
      if AJob.Kind = pjkReject then
        AJob.Target.Reject(AJob.Value)
      else
        AJob.Target.Fulfill(AJob.Value);
    end;
    Exit;
  end;

  handler := JSMakeUndefined();
  if AJob.IsFinally then
    handler := AJob.OnFinally
  else if AJob.IsRejection then
    handler := AJob.OnRejected
  else
    handler := AJob.OnFulfilled;

  { A missing handler passes the settlement through to the child. }
  if not handler.IsFunction() then
  begin
    if AJob.Child <> nil then
    begin
      if AJob.IsRejection then
        AJob.Child.Reject(AJob.Value)
      else
        AJob.Child.Fulfill(AJob.Value);
    end;
    Exit;
  end;

  arg := AJob.Value;
  try
    resultValue := CallFunction(handler, [arg], JSMakeUndefined());
  except
    on E: EFloriaJSThrow do
    begin
      if AJob.Child <> nil then
        AJob.Child.Reject(E.Value);
      Exit;
    end;
  end;

  if AJob.Child = nil then
    Exit;

  if AJob.IsFinally then
  begin
    { `finally` ignores the callback's value and forwards the original one. }
    if AJob.IsRejection then
      AJob.Child.Reject(AJob.Value)
    else
      AJob.Child.Fulfill(AJob.Value);
  end
  else if resultValue.IsPromise() then
  begin
    { Returning a promise makes the child adopt it. }
    resultValue.AsPromise().Attach(JSMakeUndefined(), JSMakeUndefined(),
      JSMakeUndefined(), False, AJob.Child);
  end
  else
    AJob.Child.Fulfill(resultValue);
end;

{ Starts or resumes a generator body.

  On the first call the frame is created from the generator's stored bytecode,
  environment and arguments. On later calls the saved IP and operand stack are
  restored instead, so execution continues just past the `yield` that
  suspended it. The body runs until it yields again (AValue is the yielded
  value, ADone is False) or returns (AValue is the return value, ADone is True).
  A throw completes the generator and propagates. }
procedure TFloriaJSVM.SuspendActiveFrame(const AValue: TFloriaJSValue);
var
  baseBP, i, firstOwn: Integer;
  catchIP, frameOffset, stackDepth: Integer;
  envPtr: Pointer;
begin
  if FActiveGenerator = nil then
    Exit;

  baseBP := FFrames[FFP].BaseBP;
  FActiveGenerator.IP := FFrames[FFP].IP;
  FActiveGenerator.ThisVal := FFrames[FFP].ThisVal;
  FActiveGenerator.CurrentEnv := FFrames[FFP].Env;
  FActiveGenerator.BaseBP := baseBP;
  FActiveGenerator.ClearSnapshot();
  for i := baseBP to FSP - 1 do
    FActiveGenerator.PushSnapshotValue(FStack[i]);
  FActiveGenerator.StackCount := FSP - baseBP;

  { Try handlers created inside this generator frame are suspended with it.
    They must leave the VM's active stack while suspended, then be rebased onto
    the new frame when the generator resumes. }
  firstOwn := FTryCount;
  while (firstOwn > 0) and
        (FTryHandlers[firstOwn - 1].FrameIndex >= FActiveGenerator.FrameFP) do
    Dec(firstOwn);
  FActiveGenerator.ClearTrySnapshots();
  for i := firstOwn to FTryCount - 1 do
  begin
    catchIP := FTryHandlers[i].CatchIP;
    frameOffset := FTryHandlers[i].FrameIndex - FActiveGenerator.FrameFP;
    stackDepth := FTryHandlers[i].StackDepth - baseBP;
    envPtr := FTryHandlers[i].Env;
    FActiveGenerator.PushTrySnapshot(catchIP, frameOffset, stackDepth, envPtr);
  end;
  FTryCount := firstOwn;

  FYieldedValue := AValue;
  FIsSuspending := True;
  while FFP > FActiveGenerator.FrameFP do
    PopFrame();
  while FSP > FActiveGenerator.BaseBP do
    Pop();
end;

procedure TFloriaJSVM.FinishAsyncTask(ATask: TFloriaJSGenerator;
  const AValue: TFloriaJSValue; AIsRejection: Boolean);
begin
  try
    if ATask.AsyncPromise <> nil then
    begin
      if AIsRejection then
        ATask.AsyncPromise.Reject(AValue)
      else
        ATask.AsyncPromise.Fulfill(AValue);
    end;
  finally
    ATask.HasPendingThrow := False;
    ATask.PendingThrow := JSMakeUndefined();
    ATask.AsyncPromise := nil;
    ATask.Release();
  end;
end;

procedure TFloriaJSVM.ResumeAsyncTask(ATask: TFloriaJSGenerator;
  const AValue: TFloriaJSValue; AIsRejection: Boolean);
var
  done: Boolean;
  resultValue, awaited, onFulfilled, onRejected: TFloriaJSValue;
begin
  if ATask = nil then
    Exit;
  done := False;
  resultValue := JSMakeUndefined();
  ATask.HasPendingThrow := AIsRejection;
  if AIsRejection then
    ATask.PendingThrow := AValue
  else
    ATask.PendingThrow := JSMakeUndefined();
  try
    RunGenerator(ATask, AValue, resultValue, done);
  except
    on E: EFloriaJSThrow do
    begin
      if ATask.IsAsyncGenerator then
      begin
        ATask.State := fjgsCompleted;
        ATask.ReturnValue := JSMakeUndefined();
        if ATask.AsyncPromise <> nil then
          ATask.AsyncPromise.Reject(E.Value);
        ATask.AsyncPromise := nil;
        ATask.AsyncGeneratorYielded := False;
        ATask.Release();
      end
      else
        FinishAsyncTask(ATask, E.Value, True);
      Exit;
    end;
  end;

  if ATask.IsAsyncGenerator then
  begin
    if done then
    begin
      FinishAsyncGenerator(ATask, resultValue, True);
      Exit;
    end;
    if ATask.AsyncGeneratorYielded then
    begin
      { A yielded promise is awaited before delivery. Non-promise values are
        delivered immediately, which keeps concurrent next() calls simple. }
      if resultValue.IsPromise() then
      begin
        onFulfilled := JSMakeFunction(FHeap.NewNativeMethod('onYieldFulfilled',
          @ATask.AsyncYieldFulfilled));
        onRejected := JSMakeFunction(FHeap.NewNativeMethod('onYieldRejected',
          @ATask.AsyncYieldRejected));
        resultValue.AsPromise().Attach(onFulfilled, onRejected, JSMakeUndefined(), False, nil);
        Exit;
      end;
      FinishAsyncGenerator(ATask, resultValue, False);
      Exit;
    end;
    { Otherwise this suspension is an await. Fall through to the normal
      promise-adoption path; the pending next() promise stays pending. }
  end;

  if done then
  begin
    FinishAsyncTask(ATask, resultValue, False);
    Exit;
  end;

  { The suspended value is the operand of await. Resolve it like
    Promise.resolve so thenables are adopted as well. }
  awaited := FHeap.PromiseResolve([resultValue], JSMakeUndefined());
  if not awaited.IsPromise() then
  begin
    FinishAsyncTask(ATask, resultValue, False);
    Exit;
  end;

  onFulfilled := JSMakeFunction(FHeap.NewNativeMethod('onFulfilled',
    @ATask.AsyncFulfilled));
  onRejected := JSMakeFunction(FHeap.NewNativeMethod('onRejected',
    @ATask.AsyncRejected));
  awaited.AsPromise().Attach(onFulfilled, onRejected, JSMakeUndefined(), False, nil);
end;

function TFloriaJSVM.StartAsyncTask(AFn: TFloriaJSFunction;
  const AArgs: array of TFloriaJSValue; const AThisVal: TFloriaJSValue;
  AParentEnv: TFloriaJSEnvironment): TFloriaJSPromise;
var
  task: TFloriaJSGenerator;
  promise: TFloriaJSPromise;
begin
  promise := FHeap.NewPromise();
  task := MakeGenerator(AFn, AArgs, AThisVal, AParentEnv);
  task.IsAsyncTask := True;
  task.AsyncResume := @ResumeAsyncTask;
  task.AsyncPromise := promise;
  task.Retain();
  Result := promise;
  ResumeAsyncTask(task, JSMakeUndefined(), False);
end;

function TFloriaJSVM.StartAsyncGenerator(AFn: TFloriaJSFunction;
  const AArgs: array of TFloriaJSValue; const AThisVal: TFloriaJSValue;
  AParentEnv: TFloriaJSEnvironment): TFloriaJSGenerator;
begin
  Result := MakeGenerator(AFn, AArgs, AThisVal, AParentEnv);
  Result.IsAsyncTask := True;
  Result.IsAsyncGenerator := True;
  Result.AsyncResume := @ResumeAsyncTask;
  Result.AsyncGeneratorNext := @AsyncGeneratorNext;
end;

procedure TFloriaJSVM.FinishAsyncGenerator(ATask: TFloriaJSGenerator;
  const AValue: TFloriaJSValue; ADone: Boolean);
var
  resultObj: TFloriaJSObject;
  promise: TFloriaJSPromise;
begin
  promise := ATask.AsyncPromise;
  if promise <> nil then
  begin
    resultObj := FHeap.NewObject(FHeap.GetObjectPrototype());
    resultObj.SetProperty('value', AValue);
    resultObj.SetProperty('done', JSMakeBoolean(ADone));
    promise.Fulfill(JSMakeObject(resultObj));
  end;
  ATask.AsyncPromise := nil;
  ATask.AsyncGeneratorYielded := False;
  ATask.Release();
end;

function TFloriaJSVM.AsyncGeneratorNext(AGen: TFloriaJSGenerator;
  const ASent: TFloriaJSValue; AMode: Integer): TFloriaJSPromise;
var
  promise: TFloriaJSPromise;
  resultObj: TFloriaJSObject;
  iterator, method, inner, adopted, onFulfilled, onRejected: TFloriaJSValue;
  trapName: string;
begin
  promise := FHeap.NewPromise();

  if AGen.State = fjgsCompleted then
  begin
    resultObj := FHeap.NewObject(FHeap.GetObjectPrototype());
    resultObj.SetProperty('value', AGen.ReturnValue);
    resultObj.SetProperty('done', JSMakeBoolean(True));
    promise.Fulfill(JSMakeObject(resultObj));
    Exit(promise);
  end;

  if (AMode <> 0) and AGen.InYieldStar and AGen.YieldStarIterator.IsObject() then
  begin
    iterator := AGen.YieldStarIterator;
    if AMode = 1 then
      trapName := 'return'
    else
      trapName := 'throw';
    method := iterator.AsObject().GetProperty(trapName);
    if not method.IsFunction() then
    begin
      if AMode = 2 then
      begin
        promise.Reject(JSMakeObject(FHeap.NewError('TypeError',
          'The iterator does not provide a throw method')));
        Exit(promise);
      end;
      AGen.ClearSnapshot();
      AGen.State := fjgsCompleted;
      AGen.ReturnValue := ASent;
      resultObj := FHeap.NewObject(FHeap.GetObjectPrototype());
      resultObj.SetProperty('value', ASent);
      resultObj.SetProperty('done', JSMakeBoolean(True));
      promise.Fulfill(JSMakeObject(resultObj));
      Exit(promise);
    end;

    inner := FHeap.InvokeFunction(method, [ASent], iterator);
    AGen.AsyncPromise := promise;
    AGen.Retain();
    adopted := FHeap.PromiseResolve([inner], JSMakeUndefined());
    if AMode = 1 then
    begin
      onFulfilled := JSMakeFunction(FHeap.NewNativeMethod('onReturnFulfilled',
        @AGen.AsyncReturnFulfilled));
      onRejected := JSMakeFunction(FHeap.NewNativeMethod('onReturnRejected',
        @AGen.AsyncReturnRejected));
    end
    else
    begin
      onFulfilled := JSMakeFunction(FHeap.NewNativeMethod('onThrowFulfilled',
        @AGen.AsyncThrowFulfilled));
      onRejected := JSMakeFunction(FHeap.NewNativeMethod('onThrowRejected',
        @AGen.AsyncThrowRejected));
    end;
    adopted.AsPromise().Attach(onFulfilled, onRejected, JSMakeUndefined(), False, nil);
    Exit(promise);
  end;

  if AMode = 1 then
  begin
    AGen.ClearSnapshot();
    AGen.State := fjgsCompleted;
    AGen.ReturnValue := ASent;
    resultObj := FHeap.NewObject(FHeap.GetObjectPrototype());
    resultObj.SetProperty('value', ASent);
    resultObj.SetProperty('done', JSMakeBoolean(True));
    promise.Fulfill(JSMakeObject(resultObj));
    Exit(promise);
  end;

  if AMode = 2 then
  begin
    AGen.AsyncPromise := promise;
    AGen.Retain();
    ResumeAsyncTask(AGen, ASent, True);
    Exit(promise);
  end;

  AGen.AsyncPromise := promise;
  AGen.AsyncGeneratorYielded := False;
  AGen.Retain();
  ResumeAsyncTask(AGen, ASent, False);
  Result := promise;
end;

function TFloriaJSVM.RunGenerator(AGen: TFloriaJSGenerator;
  const ASent: TFloriaJSValue; out AValue: TFloriaJSValue;
  out ADone: Boolean): Boolean;
var
  subCode: TFloriaJSBytecode;
  genEnv: TFloriaJSEnvironment;
  baseBP, i, initialFP: Integer;
  savedStack: TFloriaJSValueArray;
  savedCount: Integer;
  isResume: Boolean;
  prevGenerator: TFloriaJSGenerator;
  prevSuspending: Boolean;
  prevYielded: TFloriaJSValue;
  catchIP, frameOffset, stackDepth: Integer;
  envPtr: Pointer;
  pending: TFloriaJSValue;
begin
  Result := False;
  AValue := JSMakeUndefined();
  ADone := True;

  subCode := TFloriaJSBytecode(AGen.Bytecode);
  if subCode = nil then
    Exit;

  genEnv := TFloriaJSEnvironment(AGen.Env);
  { A top-level generator has no closure environment; fall back to the global
    one so the frame still has a scope to resolve names in. }
  if genEnv = nil then
    genEnv := FGlobalEnv;
  isResume := (AGen.State = fjgsSuspendedYield);

  baseBP := FSP;
  initialFP := FFP;

  { Restore or seed the frame's local slots. }
  if isResume then
  begin
    { The snapshot holds the stack from this frame's base up to the yield.
      Restoring it recreates the frame exactly; the sent value is then pushed
      as the result of the `yield` expression. }
    savedCount := AGen.StackCount;
    SetLength(savedStack, savedCount);
    for i := 0 to savedCount - 1 do
      savedStack[i] := AGen.SnapshotValue(i);
    for i := 0 to savedCount - 1 do
      Push(savedStack[i]);
    AGen.ClearSnapshot();
  end
  else
  begin
    { The parameter prologue reads its arguments from the local slots, so the
      first run seeds them from the captured arguments. }
    for i := 0 to subCode.GetLocalCount() - 1 do
    begin
      if i < Length(AGen.Args) then
        Push(AGen.Args[i])
      else
        Push(JSMakeUndefined());
    end;
  end;

  prevGenerator := FActiveGenerator;
  prevSuspending := FIsSuspending;
  prevYielded := FYieldedValue;
  FActiveGenerator := AGen;
  FIsSuspending := False;
  FYieldedValue := JSMakeUndefined();

  PushFrame(subCode, genEnv, AGen.ThisVal, baseBP, False, nil, False);
  { Remember this frame so a later yield unwinds exactly back to it. }
  AGen.FrameFP := FFP;
  if isResume then
  begin
    FFrames[FFP].IP := AGen.IP;
    if AGen.CurrentEnv <> nil then
      FFrames[FFP].Env := TFloriaJSEnvironment(AGen.CurrentEnv);
  end;

  { Re-register try handlers that were suspended with this generator, rebased
    onto the frame's new position. }
  for i := 0 to AGen.TrySnapshotCount() - 1 do
  begin
    AGen.GetTrySnapshot(i, catchIP, frameOffset, stackDepth, envPtr);
    PushTryHandler(catchIP, FFP + frameOffset, baseBP + stackDepth,
      TFloriaJSEnvironment(envPtr));
  end;
  AGen.ClearTrySnapshots();

  try
    AGen.State := fjgsRunning;
    { A rejection resumes the task by throwing at the await point; otherwise
      the settled value becomes the result of the await/yield expression. }
    if AGen.HasPendingThrow then
    begin
      pending := AGen.PendingThrow;
      AGen.HasPendingThrow := False;
      AGen.PendingThrow := JSMakeUndefined();
      HandleThrow(pending);
    end
    else if isResume then
      Push(ASent);

    { RunLoop leaves the frame's result on the stack. It also unwinds the frame
      itself on return, so the value sits above the frame's base. }
    AValue := RunLoop(initialFP, baseBP);

    if FIsSuspending then
    begin
      AValue := FYieldedValue;
      ADone := False;
      AGen.State := fjgsSuspendedYield;
    end
    else
    begin
      ADone := True;
      AGen.State := fjgsCompleted;
    end;
    Result := True;
  finally
    while FFP > initialFP do
      PopFrame();
    while FSP > baseBP do
      Pop();
    { A completed activation no longer needs its pinned environment. A
      suspended one keeps it until the next resume or destruction. }
    if ADone and (AGen.CurrentEnv <> nil) then
      AGen.CurrentEnv := nil;
    FActiveGenerator := prevGenerator;
    FIsSuspending := prevSuspending;
    FYieldedValue := prevYielded;
  end;
end;

destructor TFloriaJSVM.Destroy();
begin
  if (FHeap <> nil) and not FOwnsHeap then
  begin
    FHeap.SetFunctionInvoker(nil);
    FHeap.SetConstructInvoker(nil);
    FHeap.SetEvalInvoker(nil);
    FHeap.SetJobRunner(nil);
  end;

  SetLength(FStack, 0);
  SetLength(FFrames, 0);
  SetLength(FTryHandlers, 0);

  if FOwnsHeap then
    FreeAndNil(FHeap);

  inherited Destroy();
end;

procedure TFloriaJSVM.EnsureStackCapacity();
begin
  if FSP >= FStackCapacity then
  begin
    FStackCapacity := FStackCapacity * 2;
    SetLength(FStack, FStackCapacity);
  end;
end;

procedure TFloriaJSVM.Push(const AVal: TFloriaJSValue);
begin
  EnsureStackCapacity();
  FStack[FSP] := AVal;
  Inc(FSP);
end;

function TFloriaJSVM.Pop(): TFloriaJSValue;
begin
  if FSP > 0 then
  begin
    Dec(FSP);
    Result := FStack[FSP];
    FStack[FSP] := JSMakeUndefined();
  end
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSVM.Peek(ADepth: Integer): TFloriaJSValue;
var
  idx: Integer;
begin
  idx := FSP - 1 - ADepth;
  if (idx >= 0) and (idx < FSP) then
    Result := FStack[idx]
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSVM.GetStackDepth(): Integer;
begin
  Result := FSP;
end;

procedure TFloriaJSVM.ResetStack();
var
  i: Integer;
begin
  for i := 0 to FSP - 1 do
    FStack[i] := JSMakeUndefined();
  FSP := 0;
  FFP := -1;
  FTryCount := 0;
end;

procedure TFloriaJSVM.PushFrame(ABytecode: TFloriaJSBytecode; AEnv: TFloriaJSEnvironment; const AThis: TFloriaJSValue; ABaseBP: Integer; AIsConstructor: Boolean; AConstructedObj: TFloriaJSObject; AOwnsCallEnv: Boolean; AVarEnv: TFloriaJSEnvironment);
begin
  if FFP + 1 >= FMaxCallDepth then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('RangeError', 'Maximum call stack size exceeded')));

  Inc(FFP);
  if FFP >= FFrameCapacity then
  begin
    FFrameCapacity := FFrameCapacity * 2;
    SetLength(FFrames, FFrameCapacity);
  end;

  FFrames[FFP].Bytecode := ABytecode;
  FFrames[FFP].IP := 0;
  FFrames[FFP].BaseBP := ABaseBP;
  if AThis.IsUndefined() and (AEnv <> nil) then
    FFrames[FFP].ThisVal := AEnv.GetDefault('globalThis', JSMakeUndefined())
  else
    FFrames[FFP].ThisVal := AThis;
  FFrames[FFP].Env := AEnv;
  if AVarEnv <> nil then
    FFrames[FFP].VarEnv := AVarEnv
  else
    FFrames[FFP].VarEnv := AEnv;
  FFrames[FFP].InitialEnv := AEnv;
  FFrames[FFP].OwnsCallEnv := AOwnsCallEnv;
  FFrames[FFP].IsConstructor := AIsConstructor;
  FFrames[FFP].ConstructedObj := AConstructedObj;
end;

procedure TFloriaJSVM.PopFrame();
var
  frameEnv, parentEnv, stopEnv: TFloriaJSEnvironment;
begin
  if FFP >= 0 then
  begin
    frameEnv := FFrames[FFP].Env;
    if FFrames[FFP].OwnsCallEnv and (FFrames[FFP].InitialEnv <> nil) then
      stopEnv := FFrames[FFP].InitialEnv.Parent
    else
      stopEnv := FFrames[FFP].InitialEnv;

    while (frameEnv <> nil) and (frameEnv <> FGlobalEnv) and (frameEnv <> stopEnv) do
    begin
      parentEnv := frameEnv.Parent;
      if not frameEnv.Captured then
      begin
        if FHeap <> nil then
          FHeap.Untrack(frameEnv);
        frameEnv.Free();
      end
      else
        frameEnv.Detach();
      frameEnv := parentEnv;
    end;

    FFrames[FFP].Bytecode := nil;
    FFrames[FFP].Env := nil;
    FFrames[FFP].VarEnv := nil;
    FFrames[FFP].InitialEnv := nil;
    FFrames[FFP].ConstructedObj := nil;
    FFrames[FFP].ThisVal := JSMakeUndefined();
    Dec(FFP);
  end;
end;

procedure TFloriaJSVM.PushTryHandler(ACatchIP: Integer; AFrameIndex, AStackDepth: Integer; AEnv: TFloriaJSEnvironment);
begin
  if FTryCount >= FTryCapacity then
  begin
    FTryCapacity := FTryCapacity * 2;
    SetLength(FTryHandlers, FTryCapacity);
  end;

  FTryHandlers[FTryCount].CatchIP := ACatchIP;
  FTryHandlers[FTryCount].FrameIndex := AFrameIndex;
  FTryHandlers[FTryCount].StackDepth := AStackDepth;
  FTryHandlers[FTryCount].Env := AEnv;
  Inc(FTryCount);
end;

procedure TFloriaJSVM.PopTryHandler();
begin
  if FTryCount > 0 then
    Dec(FTryCount);
end;

procedure TFloriaJSVM.HandleThrow(const AErrVal: TFloriaJSValue);
var
  handler: TFloriaJSTryEntry;
  i: Integer;
begin
  if FTryCount > 0 then
  begin
    Dec(FTryCount);
    handler := FTryHandlers[FTryCount];

    // Unwind call frames down to the handler's frame
    while FFP > handler.FrameIndex do
      PopFrame();

    // Clean stack down to handler stack depth
    for i := handler.StackDepth to FSP - 1 do
      FStack[i] := JSMakeUndefined();
    FSP := handler.StackDepth;

    // Push caught error value onto stack
    Push(AErrVal);

    // Jump to catch block IP
    if FFP >= 0 then
    begin
      FFrames[FFP].IP := handler.CatchIP;
      FFrames[FFP].Env := handler.Env;
    end;
  end
  else
  begin
    // Uncaught exception - re-raise out of VM
    raise EFloriaJSThrow.Create(AErrVal);
  end;
end;

function TFloriaJSVM.GetMemberValue(const AObj: TFloriaJSValue; const APropName: string): TFloriaJSValue;
var
  i: Integer;
begin
  if AObj.IsNull() then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Cannot read properties of null (reading ''' + APropName + ''')')));
  if AObj.IsUndefined() then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Cannot read properties of undefined (reading ''' + APropName + ''')')));

  if AObj.IsObject() then
    Exit(AObj.AsObject().GetPropertyWithReceiver(APropName, AObj.AsObject()));

  if AObj.IsString() then
  begin
    if APropName = 'length' then
      Exit(JSMakeNumber(JSUTF16Length(AObj.StrVal)));
    if TryStrToInt(APropName, i) and (i >= 0) and
       (i < JSUTF16Length(AObj.StrVal)) then
      Exit(JSMakeString(JSUTF16CharAt(AObj.StrVal, i)));
    if FHeap <> nil then
      Exit(FHeap.GetStringPrototype().GetProperty(APropName));
  end;

  if AObj.IsNumber() then
  begin
    if FHeap <> nil then
      Exit(FHeap.GetNumberPrototype().GetProperty(APropName));
  end;

  if AObj.IsSymbol() then
  begin
    if APropName = 'description' then
    begin
      if AObj.StrVal = '' then
        Exit(JSMakeUndefined())
      else
        Exit(JSMakeString(AObj.StrVal));
    end;
  end;

  Result := JSMakeUndefined();
end;

procedure TFloriaJSVM.SetMemberValue(const AObj: TFloriaJSValue; const APropName: string; const AVal: TFloriaJSValue);
begin
  if AObj.IsNull() then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Cannot set properties of null (setting ''' + APropName + ''')')));
  if AObj.IsUndefined() then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Cannot set properties of undefined (setting ''' + APropName + ''')')));

  if AObj.IsObject() then
  begin
    { A symbol-keyed property is not enumerable: it does not appear in
      Object.keys, for...in, or JSON. The key prefix marks it. }
    if (Length(APropName) > 0) and (APropName[1] = #1) then
      AObj.AsObject().SetPropertyNonEnumerable(APropName, AVal)
    else
      AObj.AsObject().SetProperty(APropName, AVal);
  end;
end;

function TFloriaJSVM.Execute(ABytecode: TFloriaJSBytecode; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
begin
  Result := Execute(ABytecode, AEnv, JSMakeUndefined());
end;

function TFloriaJSVM.Execute(ABytecode: TFloriaJSBytecode; AEnv: TFloriaJSEnvironment; const AThis: TFloriaJSValue; AVarEnv: TFloriaJSEnvironment): TFloriaJSValue;
var
  i, initialFP, initialBaseBP: Integer;
  savedHeap: TFloriaJSHeap;
begin
  if ABytecode = nil then Exit(JSMakeUndefined());

  if AEnv = nil then
    AEnv := FGlobalEnv;

  initialFP := FFP;
  initialBaseBP := FSP;

  // Reserve local variable slots on the value stack
  for i := 0 to ABytecode.GetLocalCount() - 1 do
    Push(JSMakeUndefined());

  savedHeap := JSActiveRealmHeap();
  JSSetActiveRealmHeap(FHeap);
  PushFrame(ABytecode, AEnv, AThis, initialBaseBP, False, nil, False, AVarEnv);
  try
    Result := RunLoop(initialFP, initialBaseBP);
  finally
    JSSetActiveRealmHeap(savedHeap);
    while FFP > initialFP do
      PopFrame();
    while FSP > initialBaseBP do
      Pop();
  end;
end;

function TFloriaJSVM.RunLoop(AInitialFP, AInitialBaseBP: Integer): TFloriaJSValue;
var
  curFrame: ^TFloriaJSCallFrame;
  inst: TFloriaJSInstruction;
  a, b, val, retVal, propVal, objVal, calleeVal, thisVal, resVal: TFloriaJSValue;
  savedNewTarget: TFloriaJSValue;
  savedConstructor: TFloriaJSFunction;
  intrinsicName: string;
  propName, varName, propKeyStr, pName, restName, evalText: string;
  argc, i, j, callBaseBP, asyncInitialFP: Integer;
  idx64, shapeId: Int64;
  cacheIdx, instIP: Integer;
  args: array of TFloriaJSValue;
  fn: TFloriaJSFunction;
  subCode: TFloriaJSBytecode;
  callEnv, oldEnv: TFloriaJSEnvironment;
  arrObj, restArr: TFloriaJSArray;
  fnObj, protoObj, currObj: TFloriaJSObject;
  keysList: TStringList;
  promise: TFloriaJSPromise;
  iterObj: TFloriaJSIterator;
  genObj: TFloriaJSGenerator;
  targetIP: Integer;
begin
  while FFP > AInitialFP do
  begin
    { Keep the exception frame outside the per-instruction dispatch loop.
      Entering try/except once per RunLoop instead of once per instruction
      removes the wrapper from the hot path while preserving JavaScript
      catch/finally semantics through HandleThrow. }
    try
      while FFP > AInitialFP do
      begin
        curFrame := @FFrames[FFP];
    if curFrame^.IP >= curFrame^.Bytecode.GetInstructionCount() then
    begin
      // Implicit return undefined at end of bytecode
      retVal := JSMakeUndefined();
      while FSP > curFrame^.BaseBP do
        Pop();
      if curFrame^.IsConstructor then
        Push(JSMakeObject(curFrame^.ConstructedObj))
      else
        Push(retVal);
      PopFrame();
      Continue;
    end;

    instIP := curFrame^.IP;
    inst := curFrame^.Bytecode.GetInstruction(instIP);
    Inc(curFrame^.IP);

      case inst.Op of
        opNop: ;

        // Stack
        opPop:
          Pop();

        opDup:
          Push(Peek());

        opDup2:
          begin
            b := Peek(0);
            a := Peek(1);
            Push(a);
            Push(b);
          end;

        opSwap:
          begin
            b := Pop();
            a := Pop();
            Push(b);
            Push(a);
          end;

        // Primitives & Constants
        opConst:
          Push(curFrame^.Bytecode.GetConstant(inst.Imm));

        opUndefined:
          Push(JSMakeUndefined());

        opNull:
          Push(JSMakeNull());

        opTrue:
          Push(JSMakeBoolean(True));

        opFalse:
          Push(JSMakeBoolean(False));

        opZero:
          Push(JSMakeNumber(0.0));

        opOne:
          Push(JSMakeNumber(1.0));

        // Variables
        opLoadLoc:
          Push(FStack[curFrame^.BaseBP + inst.Imm]);

        opStoreLoc:
          begin
            val := Peek();
            FStack[curFrame^.BaseBP + inst.Imm] := val;
          end;

        opSetLoc:
          begin
            val := Pop();
            FStack[curFrame^.BaseBP + inst.Imm] := val;
          end;

        opLoadGlobal:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            if FGlobalEnv <> nil then
              Push(FGlobalEnv.GetDefault(varName, JSMakeUndefined()))
            else
              Push(JSMakeUndefined());
          end;

        opStoreGlobal:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            val := Peek();
            if FGlobalEnv <> nil then
              FGlobalEnv.Assign(varName, val, curFrame^.Bytecode.IsStrict);
          end;

        opSetGlobal:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            val := Pop();
            if FGlobalEnv <> nil then
              FGlobalEnv.Assign(varName, val, curFrame^.Bytecode.IsStrict);
          end;

        opLoadEnv:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            if (curFrame^.Env <> nil) and curFrame^.Env.Get(varName, val) then
              Push(val)
            else if (FGlobalEnv <> nil) and FGlobalEnv.Get(varName, val) then
              Push(val)
            else
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('ReferenceError', varName + ' is not defined')));
          end;

        opLoadEnvQuiet:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            if (curFrame^.Env <> nil) and curFrame^.Env.Get(varName, val) then
              Push(val)
            else if (FGlobalEnv <> nil) and FGlobalEnv.Get(varName, val) then
              Push(val)
            else
              Push(JSMakeUndefined());
          end;

        opStoreEnv:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            val := Peek();
            if curFrame^.Env <> nil then
              curFrame^.Env.Assign(varName, val, curFrame^.Bytecode.IsStrict)
            else if FGlobalEnv <> nil then
              FGlobalEnv.Assign(varName, val, curFrame^.Bytecode.IsStrict);
          end;

        opDefineEnv:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            val := Pop();
            if curFrame^.VarEnv <> nil then
              curFrame^.VarEnv.Define(varName, val, False, bkVar)
            else if FGlobalEnv <> nil then
              FGlobalEnv.Define(varName, val, False, bkVar);
          end;

        opDefineConst:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            val := Pop();
            if curFrame^.Env <> nil then
            begin
              if not curFrame^.Env.InitializeLexical(varName, val) then
                curFrame^.Env.Define(varName, val, True, bkConst);
            end
            else if FGlobalEnv <> nil then
            begin
              if not FGlobalEnv.InitializeLexical(varName, val) then
                FGlobalEnv.Define(varName, val, True, bkConst);
            end;
          end;

        opDefineLet:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            val := Pop();
            if curFrame^.Env <> nil then
            begin
              if not curFrame^.Env.InitializeLexical(varName, val) then
                curFrame^.Env.Define(varName, val, False, bkLet);
            end
            else if FGlobalEnv <> nil then
            begin
              if not FGlobalEnv.InitializeLexical(varName, val) then
                FGlobalEnv.Define(varName, val, False, bkLet);
            end;
          end;

        opDeclareVar:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            if curFrame^.VarEnv <> nil then
              curFrame^.VarEnv.DeclareVar(varName)
            else if FGlobalEnv <> nil then
              FGlobalEnv.DeclareVar(varName);
          end;

        opDeclareLet, opDeclareConst:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            if curFrame^.Env <> nil then
            begin
              if inst.Op = opDeclareConst then
                curFrame^.Env.DeclareLexical(varName, True, bkConst)
              else
                curFrame^.Env.DeclareLexical(varName, False, bkLet);
            end
            else if FGlobalEnv <> nil then
            begin
              if inst.Op = opDeclareConst then
                FGlobalEnv.DeclareLexical(varName, True, bkConst)
              else
                FGlobalEnv.DeclareLexical(varName, False, bkLet);
            end;
          end;

        opPushEnv:
          begin
            curFrame^.Env := TFloriaJSEnvironment.Create(curFrame^.Env, FHeap);
            FHeap.TrackEnvironment(curFrame^.Env);
          end;

        opPushWith:
          begin
            objVal := Pop();
            if objVal.IsNull() or objVal.IsUndefined() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError',
                'with statement requires an object')));
            if not objVal.IsObject() then
            begin
              if objVal.IsString() then
              begin
                fnObj := FHeap.NewObject(FHeap.GetStringPrototype());
                fnObj.SetProperty('length', JSMakeNumber(JSUTF16Length(objVal.StrVal)));
                objVal := JSMakeObject(fnObj);
              end
              else if objVal.IsNumber() then
                objVal := JSMakeObject(FHeap.NewObject(FHeap.GetNumberPrototype()))
              else
                objVal := JSMakeObject(FHeap.NewObject(FHeap.GetObjectPrototype()));
            end;
            curFrame^.Env := TFloriaJSEnvironment.Create(curFrame^.Env, FHeap);
            curFrame^.Env.DelegateObject := objVal.AsObject();
            FHeap.TrackEnvironment(curFrame^.Env);
          end;

        opPopEnv:
          begin
            if (curFrame^.Env <> nil) and (curFrame^.Env.Parent <> nil) then
            begin
              oldEnv := curFrame^.Env;
              curFrame^.Env := oldEnv.Parent;
              if not oldEnv.Captured then
              begin
                if FHeap <> nil then
                  FHeap.Untrack(oldEnv);
                oldEnv.Free();
              end
              else
                oldEnv.Detach();
            end;
          end;

        // Objects & Arrays
        opNewObject:
          Push(JSMakeObject(FHeap.NewObject(FHeap.GetObjectPrototype())));

        opNewArray:
          begin
            argc := inst.Imm;
            arrObj := FHeap.NewArray();
            SetLength(args, argc);
            for i := argc - 1 downto 0 do
              args[i] := Pop();
            for i := 0 to argc - 1 do
              arrObj.Push(args[i]);
            Push(JSMakeObject(arrObj));
          end;

        opArrayMarkHole:
          begin
            { Array literals push a placeholder for an elided element, then
              mark the index as a hole. Peeking keeps the array on the stack. }
            objVal := Peek();
            if objVal.IsArray() then
              objVal.AsArray().MarkHole(inst.Imm);
          end;

        opArrayPushHole:
          begin
            { Spread-built array literals append holes one element at a time. }
            objVal := Pop();
            if objVal.IsArray() then
              objVal.AsArray().PushHole();
          end;

        opSpreadIterable:
          begin
            { Spread iterates the value and produces a dense array: holes in an
              array source become explicit undefined elements. }
            objVal := Pop();
            if objVal.IsNull() or objVal.IsUndefined() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', objVal.ToString() + ' is not iterable')));

            { The source is consumed through the iteration protocol, so Map,
              Set, and iterator objects spread as well as arrays and strings. }
            if not JSGetIterator(FHeap, objVal, iterObj) then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', objVal.ToString() + ' is not iterable')));
            arrObj := JSIteratorToArray(iterObj);

            Push(JSMakeArray(arrObj));
          end;

        opGetProp:
          begin
            propVal := Pop();
            objVal := Pop();
            if objVal.IsArray() and JSArrayIndexFromNumber(propVal, idx64) then
              Push(TFloriaJSArray(objVal.ObjVal).GetElementByIndex(idx64))
            else if objVal.IsObject() and (objVal.Kind = fjstObject) and
                    (not (objVal.ObjVal is TFloriaJSProxy)) and propVal.IsString() then
            begin
              propKeyStr := propVal.StrVal;
              currObj := objVal.AsObject();
              shapeId := currObj.ShapeId();
              if curFrame^.Bytecode.LookupKeyPropertyCache(instIP, shapeId,
                   propKeyStr, cacheIdx) and
                 (cacheIdx >= 0) and
                 (not currObj.OwnPropertyHasGetter(cacheIdx)) then
                Push(currObj.OwnPropertyValue(cacheIdx))
              else
              begin
                cacheIdx := currObj.IndexOfOwnProperty(propKeyStr);
                if (cacheIdx >= 0) and
                   (not currObj.OwnPropertyHasGetter(cacheIdx)) then
                  curFrame^.Bytecode.StoreKeyPropertyCache(instIP, shapeId,
                    propKeyStr, cacheIdx);
                Push(GetMemberValue(objVal, propKeyStr));
              end;
            end
            else
              Push(GetMemberValue(objVal, JSPropertyKeyName(propVal)));
          end;

        opGetPropNamed:
          begin
            propName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            objVal := Pop();
            if objVal.IsObject() and (objVal.Kind = fjstObject) and
               (not (objVal.ObjVal is TFloriaJSProxy)) then
            begin
              currObj := objVal.AsObject();
              shapeId := currObj.ShapeId();
              if curFrame^.Bytecode.LookupPropertyCache(instIP, shapeId, cacheIdx) and
                 (cacheIdx >= 0) and
                 (not currObj.OwnPropertyHasGetter(cacheIdx)) then
                Push(currObj.OwnPropertyValue(cacheIdx))
              else
              begin
                cacheIdx := currObj.IndexOfOwnProperty(propName);
                if (cacheIdx >= 0) and
                   (not currObj.OwnPropertyHasGetter(cacheIdx)) then
                  curFrame^.Bytecode.StorePropertyCache(instIP, shapeId, cacheIdx);
                Push(GetMemberValue(objVal, propName));
              end;
            end
            else
              Push(GetMemberValue(objVal, propName));
          end;

        opSetProp:
          begin
            val := Pop();
            propVal := Pop();
            objVal := Pop();
            if objVal.IsArray() and JSArrayIndexFromNumber(propVal, idx64) then
              TFloriaJSArray(objVal.ObjVal).SetElementByIndex(idx64, val)
            else if objVal.IsObject() and (objVal.Kind = fjstObject) and
                    (not (objVal.ObjVal is TFloriaJSProxy)) and propVal.IsString() then
            begin
              propKeyStr := propVal.StrVal;
              currObj := objVal.AsObject();
              shapeId := currObj.ShapeId();
              if curFrame^.Bytecode.LookupKeyPropertyCache(instIP, shapeId,
                   propKeyStr, cacheIdx) and
                 (cacheIdx >= 0) and
                 currObj.OwnPropertyIsWritable(cacheIdx) then
                currObj.SetOwnPropertyValue(cacheIdx, val)
              else
              begin
                SetMemberValue(objVal, propKeyStr, val);
                shapeId := currObj.ShapeId();
                cacheIdx := currObj.IndexOfOwnProperty(propKeyStr);
                if (cacheIdx >= 0) and
                   currObj.OwnPropertyIsWritable(cacheIdx) then
                  curFrame^.Bytecode.StoreKeyPropertyCache(instIP, shapeId,
                    propKeyStr, cacheIdx);
              end;
            end
            else
              SetMemberValue(objVal, JSPropertyKeyName(propVal), val);
            Push(val);
          end;

        opSetPropNamed:
          begin
            propName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            val := Pop();
            objVal := Pop();
            if objVal.IsObject() and (objVal.Kind = fjstObject) and
               (not (objVal.ObjVal is TFloriaJSProxy)) then
            begin
              currObj := objVal.AsObject();
              shapeId := currObj.ShapeId();
              if curFrame^.Bytecode.LookupPropertyCache(instIP, shapeId, cacheIdx) and
                 (cacheIdx >= 0) and
                 currObj.OwnPropertyIsWritable(cacheIdx) then
                currObj.SetOwnPropertyValue(cacheIdx, val)
              else
              begin
                SetMemberValue(objVal, propName, val);
                shapeId := currObj.ShapeId();
                cacheIdx := currObj.IndexOfOwnProperty(propName);
                if (cacheIdx >= 0) and
                   currObj.OwnPropertyIsWritable(cacheIdx) then
                  curFrame^.Bytecode.StorePropertyCache(instIP, shapeId, cacheIdx);
              end;
            end
            else
              SetMemberValue(objVal, propName, val);
            Push(val);
          end;

        opGetPropOptional:
          begin
            propVal := Pop();
            objVal := Pop();
            if objVal.IsNull() or objVal.IsUndefined() then
              Push(JSMakeUndefined())
            else if objVal.IsArray() and JSArrayIndexFromNumber(propVal, idx64) then
              Push(TFloriaJSArray(objVal.ObjVal).GetElementByIndex(idx64))
            else
              Push(GetMemberValue(objVal, JSPropertyKeyName(propVal)));
          end;

        opGetPropNamedOpt:
          begin
            propName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            objVal := Pop();
            if objVal.IsNull() or objVal.IsUndefined() then
              Push(JSMakeUndefined())
            else if objVal.IsObject() and (objVal.Kind = fjstObject) and
                    (not (objVal.ObjVal is TFloriaJSProxy)) then
            begin
              currObj := objVal.AsObject();
              shapeId := currObj.ShapeId();
              if curFrame^.Bytecode.LookupPropertyCache(instIP, shapeId, cacheIdx) and
                 (cacheIdx >= 0) and
                 (not currObj.OwnPropertyHasGetter(cacheIdx)) then
                Push(currObj.OwnPropertyValue(cacheIdx))
              else
              begin
                cacheIdx := currObj.IndexOfOwnProperty(propName);
                if (cacheIdx >= 0) and
                   (not currObj.OwnPropertyHasGetter(cacheIdx)) then
                  curFrame^.Bytecode.StorePropertyCache(instIP, shapeId, cacheIdx);
                Push(GetMemberValue(objVal, propName));
              end;
            end
            else
              Push(GetMemberValue(objVal, propName));
          end;

        opDefineGetter:
          begin
            val := Pop();
            if inst.Imm >= 0 then
              propName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString()
            else
              propName := Pop().ToString();
            objVal := Peek();
            if objVal.IsObject() then
              objVal.AsObject().DefineGetter(propName, val);
          end;

        opDefineSetter:
          begin
            val := Pop();
            if inst.Imm >= 0 then
              propName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString()
            else
              propName := Pop().ToString();
            objVal := Peek();
            if objVal.IsObject() then
              objVal.AsObject().DefineSetter(propName, val);
          end;

        opObjectRest:
          begin
            argc := inst.Imm;
            keysList := TStringList.Create();
            try
              for i := 0 to argc - 1 do
                keysList.Add(Pop().ToString());
              objVal := Pop();
              fnObj := FHeap.NewObject();
              if objVal.IsObject() and (objVal.AsObject() <> nil) then
              begin
                for i := 0 to objVal.AsObject().GetPropertyCount() - 1 do
                begin
                  propName := objVal.AsObject().GetPropertyKey(i);
                  if keysList.IndexOf(propName) < 0 then
                    fnObj.SetProperty(propName, objVal.AsObject().GetProperty(propName));
                end;
              end;
              Push(JSMakeObject(fnObj));
            finally
              keysList.Free();
            end;
          end;

        opSetProto:
          begin
            propVal := Pop();   { the new prototype }
            objVal := Pop();    { the object to link }
            if objVal.IsObject() and (objVal.ObjVal <> nil) then
              objVal.AsObject().Prototype := propVal.AsObject();
          end;

        opDefineHidden:
          begin
            { Pop value, pop object, define a non-enumerable property. Class
              methods and `prototype` are installed this way. }
            val := Pop();
            objVal := Pop();
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            if objVal.IsObject() and (objVal.ObjVal <> nil) then
              objVal.AsObject().SetPropertyNonEnumerable(varName, val);
          end;

        opDefineGetterHidden:
          begin
            { Class accessors are non-enumerable, like class methods. }
            val := Pop();
            objVal := Pop();
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            if objVal.IsObject() and (objVal.ObjVal <> nil) then
            begin
              objVal.AsObject().DefineGetter(varName, val);
              objVal.AsObject().SetEnumerable(varName, False);
            end;
          end;

        opDefineSetterHidden:
          begin
            val := Pop();
            objVal := Pop();
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            if objVal.IsObject() and (objVal.ObjVal <> nil) then
            begin
              objVal.AsObject().DefineSetter(varName, val);
              objVal.AsObject().SetEnumerable(varName, False);
            end;
          end;

        opDeleteEnv:
          begin
            { `delete identifier` never reads the binding. A declared variable is
              non-deletable, so the answer is false and the binding stays; an
              unknown name answers true without creating anything. }
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            if ((curFrame^.Env <> nil) and curFrame^.Env.Has(varName)) or
               ((FGlobalEnv <> nil) and FGlobalEnv.Has(varName)) then
              Push(JSMakeBoolean(False))
            else
              Push(JSMakeBoolean(True));
          end;

        opDeleteProp:
          begin
            propVal := Pop();
            objVal := Pop();
            { A member expression on null or undefined fails while it is being
              evaluated, so `delete null.x` throws rather than answering true. }
            if objVal.IsNull() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError',
                'Cannot convert undefined or null to object')))
            else if objVal.IsUndefined() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError',
                'Cannot convert undefined or null to object')))
            else if objVal.IsObject() then
              Push(JSMakeBoolean(objVal.AsObject().DeleteProperty(propVal.ToString())))
            else
              Push(JSMakeBoolean(True));
          end;

        opIn:
          begin
            objVal := Pop();
            propVal := Pop();
            if not objVal.IsObject() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Cannot use ''in'' operator to search for ''' + propVal.ToString() + ''' in ' + objVal.ToString())));
            Push(JSMakeBoolean(objVal.AsObject().HasProperty(propVal.ToString())));
          end;

        opInstanceOf:
          begin
            calleeVal := Pop();
            objVal := Pop();
            if not calleeVal.IsFunction() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Right-hand side of ''instanceof'' is not callable')));
            if not objVal.IsObject() then
              Push(JSMakeBoolean(False))
            else
              Push(JSMakeBoolean(JSInstanceOf(objVal, calleeVal)));
          end;

        // Arithmetic & Bitwise
        opAdd:
          begin
            b := Pop();
            a := Pop();
            Push(JSAdd(a, b));
          end;

        opSub:
          begin
            b := Pop();
            a := Pop();
            Push(JSSubtract(a, b));
          end;

        opMul:
          begin
            b := Pop();
            a := Pop();
            Push(JSMultiply(a, b));
          end;

        opDiv:
          begin
            b := Pop();
            a := Pop();
            Push(JSDivide(a, b));
          end;

        opMod:
          begin
            b := Pop();
            a := Pop();
            Push(JSModulo(a, b));
          end;

        opPower:
          begin
            b := Pop();
            a := Pop();
            Push(JSPower(a, b));
          end;

        opNeg:
          Push(JSUnaryMinus(Pop()));

        opPos:
          Push(JSUnaryPlus(Pop()));

        opBitNot:
          Push(JSUnaryBitNot(Pop()));

        opBitAnd:
          begin
            b := Pop();
            a := Pop();
            Push(JSBitAnd(a, b));
          end;

        opBitOr:
          begin
            b := Pop();
            a := Pop();
            Push(JSBitOr(a, b));
          end;

        opBitXor:
          begin
            b := Pop();
            a := Pop();
            Push(JSBitXor(a, b));
          end;

        opShl:
          begin
            b := Pop();
            a := Pop();
            Push(JSShiftLeft(a, b));
          end;

        opShr:
          begin
            b := Pop();
            a := Pop();
            Push(JSShiftRight(a, b));
          end;

        opSar:
          begin
            b := Pop();
            a := Pop();
            Push(JSShiftRightUnsigned(a, b));
          end;

        // Comparisons
        opEq:
          begin
            b := Pop();
            a := Pop();
            Push(JSMakeBoolean(JSEqual(a, b)));
          end;

        opStrictEq:
          begin
            b := Pop();
            a := Pop();
            Push(JSMakeBoolean(JSStrictEqual(a, b)));
          end;

        opNotEq:
          begin
            b := Pop();
            a := Pop();
            Push(JSMakeBoolean(not JSEqual(a, b)));
          end;

        opStrictNotEq:
          begin
            b := Pop();
            a := Pop();
            Push(JSMakeBoolean(not JSStrictEqual(a, b)));
          end;

        opLt:
          begin
            b := Pop();
            a := Pop();
            Push(JSMakeBoolean(JSLessThan(a, b)));
          end;

        opLe:
          begin
            b := Pop();
            a := Pop();
            Push(JSMakeBoolean(JSLessEqual(a, b)));
          end;

        opGt:
          begin
            b := Pop();
            a := Pop();
            Push(JSMakeBoolean(JSGreaterThan(a, b)));
          end;

        opGe:
          begin
            b := Pop();
            a := Pop();
            Push(JSMakeBoolean(JSGreaterEqual(a, b)));
          end;

        opNot:
          Push(JSMakeBoolean(not Pop().ToBoolean()));

        opTypeOf:
          Push(JSMakeString(JSTypeOf(Pop())));

        opVoid:
          begin
            Pop();
            Push(JSMakeUndefined());
          end;

        opAwait:
          begin
            val := Pop();
            if (FActiveGenerator <> nil) and FActiveGenerator.IsAsyncTask then
            begin
              { In an async body, await is a suspension point. The driver
                resumes the task with the settled value or throws its reason. }
              FActiveGenerator.AsyncGeneratorYielded := False;
              SuspendActiveFrame(val);
              Break;
            end
            else if val.IsPromise() then
            begin
              promise := val.AsPromise();
              while (promise.State = fjspPending) and (FHeap <> nil) and FHeap.HasPromiseJobs() do
                FHeap.RunPendingJobs();

              if promise.State = fjspRejected then
                raise EFloriaJSThrow.Create(promise.ResultValue);
              if promise.State = fjspFulfilled then
                Push(promise.ResultValue)
              else
                Push(JSMakeUndefined());
            end
            else
              Push(val);
          end;

        // Jumps
        opJump:
          curFrame^.IP := inst.Imm;

        opJumpIfFalse:
          begin
            if not Pop().ToBoolean() then
              curFrame^.IP := inst.Imm;
          end;

        opJumpIfTrue:
          begin
            if Pop().ToBoolean() then
              curFrame^.IP := inst.Imm;
          end;

        opJumpIfNullish:
          begin
            val := Peek();
            if not (val.IsNull() or val.IsUndefined()) then
              curFrame^.IP := inst.Imm
            else
              Pop();
          end;

        opJumpNullish:
          begin
            val := Peek();
            if val.IsNull() or val.IsUndefined() then
            begin
              Pop();
              curFrame^.IP := inst.Imm;
            end;
          end;

        opJumpIfFalseyPeek:
          begin
            val := Peek();
            if not val.ToBoolean() then
              curFrame^.IP := inst.Imm
            else
              Pop();
          end;

        opJumpIfTruthyPeek:
          begin
            val := Peek();
            if val.ToBoolean() then
              curFrame^.IP := inst.Imm
            else
              Pop();
          end;

        // Calls & Construction
        opCall, opCallOpt, opCallEval, opCallSpread, opCallEvalSpread:
          begin
            if (inst.Op = opCallSpread) or (inst.Op = opCallEvalSpread) then
            begin
              val := Pop();
              if val.IsObject() and (val.AsObject() is TFloriaJSArray) then
              begin
                argc := TFloriaJSArray(val.AsObject()).Length();
                SetLength(args, argc);
                for i := 0 to argc - 1 do
                  args[i] := TFloriaJSArray(val.AsObject()).GetElement(i);
              end
              else
              begin
                argc := 0;
                SetLength(args, 0);
              end;
              thisVal := Pop();
              calleeVal := Pop();
            end
            else
            begin
              argc := inst.Imm;
              SetLength(args, argc);
              for i := argc - 1 downto 0 do
                args[i] := Pop();
              thisVal := Pop();
              calleeVal := Pop();
            end;

            if (inst.Op = opCallOpt) and (calleeVal.IsNull() or calleeVal.IsUndefined()) then
            begin
              Push(JSMakeUndefined());
              Continue;
            end;

            { A syntactic `eval(...)` call runs in the caller's environment when
              the resolved value is still the intrinsic eval function. A local
              binding with the same name falls through to a normal call. }
            if (inst.Op in [opCallEval, opCallEvalSpread]) and calleeVal.IsFunction() and
               (calleeVal.AsFunction().IntrinsicName = 'eval') then
            begin
              if argc > 0 then
                val := args[0]
              else
                val := JSMakeUndefined();
              if not val.IsString() then
                Push(val)
              else
              begin
                evalText := val.StrVal;
                if curFrame^.Bytecode.IsStrict then
                  evalText := '"use strict";' + #10 + evalText;
                Push(EvalSource(evalText, curFrame^.Env, curFrame^.VarEnv,
                  curFrame^.ThisVal));
              end;
              Continue;
            end;

            if calleeVal.IsObject() and (calleeVal.ObjVal is TFloriaJSProxy) then
            begin
              Push(TFloriaJSProxy(calleeVal.ObjVal).Call(args, thisVal));
              Continue;
            end;

            if not calleeVal.IsFunction() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', calleeVal.ToString() + ' is not a function')));

            fn := calleeVal.AsFunction();
            if fn = nil then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a function')));

            if fn is TFloriaJSBoundFunction then
            begin
              { A call of a bound function ignores the receiver it was called
                with and runs the target with the bound this and the bound
                arguments in front of the call arguments. }
              Push(FHeap.InvokeFunction(TFloriaJSBoundFunction(fn).Target,
                TFloriaJSBoundFunction(fn).CombineArguments(args),
                TFloriaJSBoundFunction(fn).BoundThis));
            end
            else if fn.IsNative then
            begin
              resVal := InvokeNative(fn, args, thisVal);
              Push(resVal);
            end
            else if fn.Bytecode <> nil then
            begin
              subCode := TFloriaJSBytecode(fn.Bytecode);
              if not fn.IsArrow then
                thisVal := ResolveCallThis(subCode, thisVal);

              if fn.IsAsyncGenerator then
              begin
                genObj := StartAsyncGenerator(fn, args, thisVal, curFrame^.Env);
                Push(JSMakeObject(genObj));
                Continue;
              end;

              if fn.IsAsync then
              begin
                promise := StartAsyncTask(fn, args, thisVal, curFrame^.Env);
                Push(JSMakePromise(promise));
                Continue;
              end;

              { A generator function returns a suspended generator instead of
                running its body. This mirrors the same branch in CallFunction:
                the inline call path here does not go through it. }
              if subCode.IsGenerator then
              begin
                genObj := MakeGenerator(fn, args, thisVal, curFrame^.Env);
                Push(JSMakeObject(genObj));
                Continue;
              end;

              if fn.ClosureEnv <> nil then
                callEnv := TFloriaJSEnvironment.Create(TFloriaJSEnvironment(fn.ClosureEnv), FHeap)
              else
                callEnv := TFloriaJSEnvironment.Create(curFrame^.Env, FHeap);
              FHeap.TrackEnvironment(callEnv);
              if fn.IsNamedExpression then
                callEnv.Define(fn.Name, JSMakeFunction(fn), True);

              if subCode.LocalsInEnv then
                for i := 0 to subCode.GetArgumentCount() - 1 do
                begin
                  pName := subCode.GetArgumentName(i);
                  if (Length(pName) >= 3) and (Copy(pName, 1, 3) = '...') then
                  begin
                    restName := Copy(pName, 4, Length(pName));
                    restArr := FHeap.NewArray();
                    for j := i to argc - 1 do
                      restArr.Push(args[j]);
                    callEnv.Define(restName, JSMakeObject(restArr), False);
                    Break;
                  end
                  else if i < argc then
                    callEnv.Define(pName, args[i], False)
                  else
                    callEnv.Define(pName, JSMakeUndefined(), False);
                end;

              if not fn.IsArrow then
              begin
                callEnv.Define('this', thisVal);
                if (FHeap <> nil) and subCode.NeedsArguments then
                begin
                  arrObj := FHeap.NewArray();
                  for i := 0 to argc - 1 do
                    arrObj.Push(args[i]);
                  callEnv.Define('arguments', JSMakeObject(arrObj));
                end;
              end;

              callBaseBP := FSP;
              for i := 0 to subCode.GetLocalCount() - 1 do
              begin
                if i < argc then
                  Push(args[i])
                else
                  Push(JSMakeUndefined());
              end;

              if fn.IsAsync then
              begin
                promise := FHeap.NewPromise();
                asyncInitialFP := FFP;
                PushFrame(subCode, callEnv, thisVal, callBaseBP, False, nil, True);
                try
                  resVal := RunLoop(asyncInitialFP, callBaseBP);
                  promise.Fulfill(resVal);
                except
                  on E: EFloriaJSThrow do
                    promise.Reject(E.Value);
                  on E: Exception do
                    promise.Reject(JSMakeString(E.Message));
                end;
                while FFP > asyncInitialFP do
                  PopFrame();
                while FSP > callBaseBP do
                  Pop();
                Push(JSMakePromise(promise));
              end
              else if fn.IsArrow then
                PushFrame(subCode, callEnv, curFrame^.ThisVal, callBaseBP, False, nil, True)
              else
                PushFrame(subCode, callEnv, thisVal, callBaseBP, False, nil, True);
            end
            else
            begin
              Push(JSMakeUndefined());
            end;
          end;

        opNew, opNewSpread:
          begin
            if inst.Op = opNewSpread then
            begin
              val := Pop();
              if val.IsObject() and (val.AsObject() is TFloriaJSArray) then
              begin
                argc := TFloriaJSArray(val.AsObject()).Length();
                SetLength(args, argc);
                for i := 0 to argc - 1 do
                  args[i] := TFloriaJSArray(val.AsObject()).GetElement(i);
              end
              else
              begin
                argc := 0;
                SetLength(args, 0);
              end;
              calleeVal := Pop();
            end
            else
            begin
              argc := inst.Imm;
              SetLength(args, argc);
              for i := argc - 1 downto 0 do
                args[i] := Pop();
              calleeVal := Pop();
            end;

            if calleeVal.IsObject() and (calleeVal.ObjVal is TFloriaJSProxy) then
            begin
              Push(TFloriaJSProxy(calleeVal.ObjVal).Construct(args));
              Continue;
            end;

            if not FHeap.IsConstructable(calleeVal) then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a constructor')));

            { A bound function constructs its target with the bound arguments in
              front of the call arguments and ignores the bound this. The target
              resolves the prototype, so the instance is a normal instance of
              the underlying constructor. }
            if calleeVal.AsFunction() is TFloriaJSBoundFunction then
            begin
              Push(FHeap.ConstructFunction(TFloriaJSBoundFunction(calleeVal.AsFunction()).Target,
                TFloriaJSBoundFunction(calleeVal.AsFunction()).CombineArguments(args)));
              Continue;
            end;

            fn := calleeVal.AsFunction();

            propVal := fn.GetProperty('prototype');
            if propVal.IsObject() then
              protoObj := propVal.AsObject()
            else
            begin
              intrinsicName := 'Object';
              if fn.IntrinsicName <> '' then
                intrinsicName := fn.IntrinsicName;
              protoObj := FHeap.GetPrototypeFromConstructor(calleeVal, intrinsicName);
            end;

            objVal := JSMakeObject(FHeap.NewObject(protoObj));

            if fn.IsNative then
            begin
              savedNewTarget := FHeap.CurrentNewTarget;
              FHeap.CurrentNewTarget := calleeVal;
              savedConstructor := FHeap.CurrentConstructor;
              FHeap.CurrentConstructor := fn;
              try
                resVal := InvokeNative(fn, args, objVal);
              finally
                FHeap.CurrentConstructor := savedConstructor;
                FHeap.CurrentNewTarget := savedNewTarget;
              end;

              if resVal.IsObject() then
                Push(resVal)
              else if (fn.IntrinsicName = 'String') and resVal.IsString() then
                { `new String(value)` boxes the primitive instead of returning
                  the generic object created above. }
                Push(JSMakeObject(FHeap.NewStringObject(protoObj, resVal.StrVal)))
              else if (fn.IntrinsicName = 'Number') and resVal.IsNumber() then
                { `new Number(value)` boxes the primitive so valueOf and
                  toString can recover it. }
                Push(JSMakeObject(FHeap.NewNumberObject(protoObj, resVal.NumVal)))
              else if (fn.IntrinsicName = 'Boolean') and resVal.IsBoolean() then
                Push(JSMakeObject(FHeap.NewBooleanObject(protoObj, resVal.ToBoolean())))
              else
                Push(objVal);
            end
            else if fn.Bytecode <> nil then
            begin
              subCode := TFloriaJSBytecode(fn.Bytecode);
              if not fn.IsArrow then
                thisVal := ResolveCallThis(subCode, thisVal);

              if fn.IsAsyncGenerator then
              begin
                genObj := StartAsyncGenerator(fn, args, thisVal, curFrame^.Env);
                Push(JSMakeObject(genObj));
                Continue;
              end;

              if fn.IsAsync then
              begin
                promise := StartAsyncTask(fn, args, thisVal, curFrame^.Env);
                Push(JSMakePromise(promise));
                Continue;
              end;

              { A generator function returns a suspended generator instead of
                running its body. This mirrors the same branch in CallFunction:
                the inline call path here does not go through it. }
              if subCode.IsGenerator then
              begin
                genObj := MakeGenerator(fn, args, thisVal, curFrame^.Env);
                Push(JSMakeObject(genObj));
                Continue;
              end;

              if fn.ClosureEnv <> nil then
                callEnv := TFloriaJSEnvironment.Create(TFloriaJSEnvironment(fn.ClosureEnv), FHeap)
              else
                callEnv := TFloriaJSEnvironment.Create(curFrame^.Env, FHeap);
              FHeap.TrackEnvironment(callEnv);
              if fn.IsNamedExpression then
                callEnv.Define(fn.Name, JSMakeFunction(fn), True);

              if subCode.LocalsInEnv then
                for i := 0 to subCode.GetArgumentCount() - 1 do
                begin
                  if i < argc then
                    callEnv.Define(subCode.GetArgumentName(i), args[i], False)
                  else
                    callEnv.Define(subCode.GetArgumentName(i), JSMakeUndefined(), False);
                end;

              callEnv.Define('this', objVal);
              if (FHeap <> nil) and subCode.NeedsArguments then
              begin
                arrObj := FHeap.NewArray();
                for i := 0 to argc - 1 do
                  arrObj.Push(args[i]);
                callEnv.Define('arguments', JSMakeObject(arrObj));
              end;

              callBaseBP := FSP;
              for i := 0 to subCode.GetLocalCount() - 1 do
              begin
                if i < argc then
                  Push(args[i])
                else
                  Push(JSMakeUndefined());
              end;

              PushFrame(subCode, callEnv, objVal, callBaseBP, True, objVal.AsObject(), True);
            end;
          end;

        opYield:
          begin
            val := Pop();
            if FActiveGenerator <> nil then
            begin
              FActiveGenerator.AsyncGeneratorYielded := True;
              SuspendActiveFrame(val);
              Break;
            end
            else
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('SyntaxError',
                'yield outside a generator')));
          end;

        opReturn:
          begin
            retVal := Pop();
            while FSP > curFrame^.BaseBP do
              Pop();
            if curFrame^.IsConstructor then
            begin
              if retVal.IsObject() then
                Push(retVal)
              else
                Push(JSMakeObject(curFrame^.ConstructedObj));
            end
            else
              Push(retVal);

            PopFrame();
          end;

        opClosure:
          begin
            subCode := curFrame^.Bytecode.GetSubFunction(inst.Imm);
            fnObj := FHeap.NewBytecodeFunction(subCode.Name, subCode, curFrame^.Env, subCode.IsArrow, subCode.IsAsync);
            TFloriaJSFunction(fnObj).IsAsyncGenerator := subCode.IsAsyncGenerator;
            if curFrame^.Env <> nil then
              curFrame^.Env.MarkCaptured();
            Push(JSMakeObject(fnObj));
          end;

        opThrow:
          begin
            val := Pop();
            HandleThrow(val);
          end;

        opPushTry:
          PushTryHandler(inst.Imm, FFP, FSP, curFrame^.Env);

        opPopTry:
          PopTryHandler();

        opForInInit:
          begin
            objVal := Pop();
            arrObj := FHeap.NewArray();
            if objVal.IsArray() then
            begin
              for i := 0 to objVal.AsArray().Length() - 1 do
                if objVal.AsArray().HasElement(i) then
                  arrObj.Push(JSMakeString(IntToStr(i)));
              for i := 0 to objVal.AsObject().GetPropertyCount() - 1 do
                arrObj.Push(JSMakeString(objVal.AsObject().GetPropertyKey(i)));
            end
            else if objVal.IsString() then
            begin
              { A string is array-like for for…in: its indices are enumerable. }
              for i := 0 to JSUTF16Length(objVal.StrVal) - 1 do
                arrObj.Push(JSMakeString(IntToStr(i)));
            end
            else if objVal.IsObject() and (objVal.ObjVal <> nil) then
            begin
              keysList := TStringList.Create();
              try
                currObj := objVal.AsObject();
                while (currObj <> nil) and (currObj <> FHeap.GetObjectPrototype()) and (currObj <> FHeap.GetArrayPrototype()) do
                begin
                  { Only enumerable own properties are visited; a class method is
                    non-enumerable and must not appear. }
                  for i := 0 to currObj.GetEnumerablePropertyCount() - 1 do
                  begin
                    propKeyStr := currObj.GetEnumerablePropertyKey(i);
                    if keysList.IndexOf(propKeyStr) < 0 then
                      keysList.Add(propKeyStr);
                  end;
                  currObj := currObj.Prototype;
                end;
                for i := 0 to keysList.Count - 1 do
                  arrObj.Push(JSMakeString(keysList[i]));
              finally
                keysList.Free();
              end;
            end;
            Push(JSMakeObject(arrObj));
          end;

        opForOfInit:
          begin
            { The iterable is wrapped in an iterator object rather than copied
              into a temporary array, so the source is walked lazily and Map/Set
              (which have no `length`) can be iterated at all. }
            objVal := Pop();
            if objVal.IsNull() or objVal.IsUndefined() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not iterable')));

            { A generator is iterable but is not one of the collection
              iterators, so it is stepped through its own next(). }
            if objVal.IsObject() and (objVal.ObjVal is TFloriaJSGenerator) then
              Push(objVal)
            else
            begin
              if not JSGetIterator(FHeap, objVal, iterObj) then
                raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', objVal.ToString() + ' is not iterable')));
              Push(JSMakeObject(iterObj));
            end;
          end;

        opForAwaitInit:
          begin
            objVal := Pop();
            if objVal.IsNull() or objVal.IsUndefined() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError',
                'Value is not async iterable')));
            if objVal.IsObject() then
            begin
              resVal := objVal.AsObject().GetWellKnownProperty('Symbol.asyncIterator');
              if resVal.IsFunction() then
              begin
                Push(FHeap.InvokeFunction(resVal, [], objVal));
                Continue;
              end;
            end;
            if objVal.IsObject() and (objVal.ObjVal is TFloriaJSGenerator) then
              Push(objVal)
            else
            begin
              if not JSGetIterator(FHeap, objVal, iterObj) then
                raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError',
                  objVal.ToString() + ' is not iterable')));
              Push(JSMakeObject(iterObj));
            end;
          end;

        opSetYieldStar:
          begin
            val := Pop();
            if FActiveGenerator <> nil then
            begin
              FActiveGenerator.InYieldStar := True;
              FActiveGenerator.YieldStarIterator := val;
            end;
          end;

        opClearYieldStar:
          begin
            if FActiveGenerator <> nil then
            begin
              FActiveGenerator.InYieldStar := False;
              FActiveGenerator.YieldStarDone := False;
              FActiveGenerator.YieldStarIterator := JSMakeUndefined();
            end;
          end;

        opYieldStarDoneJump:
          begin
            if (FActiveGenerator <> nil) and FActiveGenerator.YieldStarDone then
            begin
              FActiveGenerator.YieldStarDone := False;
              curFrame^.IP := inst.Imm;
            end;
          end;

        opForOfNext:
          begin
            { Pop the iterator, push the next value, or jump past the loop when
              the iterator is exhausted. The value is pushed as the loop binding. }
            objVal := Peek();
            if objVal.IsObject() and (objVal.ObjVal is TFloriaJSGenerator) then
            begin
              { Step the generator. This re-enters RunLoop, which may grow
                FFrames and invalidate `curFrame`, so the frame pointer is
                re-fetched before it is used again. }
              { `inst` and `curFrame` are locals captured before the nested
                RunLoop, which may reallocate FFrames. Re-read both after. }
              resVal := TFloriaJSGenerator(objVal.ObjVal).Next([], JSMakeUndefined());
              val := resVal.AsObject().GetProperty('value');
              if resVal.AsObject().GetProperty('done').ToBoolean() then
              begin
                Pop();
                curFrame := @FFrames[FFP];
                curFrame^.IP := inst.Imm;
              end
              else
              begin
                Push(val);
                { The nested RunLoop restores FFP, so this frame is current
                  again; re-read the pointer because FFrames may have moved. }
                curFrame := @FFrames[FFP];
                inst := curFrame^.Bytecode.GetInstruction(curFrame^.IP - 1);
              end;
            end
            else if objVal.IsObject() and (objVal.ObjVal is TFloriaJSIterator) then
            begin
              if JSIteratorNext(TFloriaJSIterator(objVal.ObjVal), val) then
                Push(val)
              else
              begin
                Pop();
                curFrame^.IP := inst.Imm;
              end;
            end
            else
            begin
              Pop();
              curFrame^.IP := inst.Imm;
            end;
          end;

        opAssertIterable:
          begin
            { Destructuring consumes an iterable. Anything the protocol accepts
              is materialised into an array here, which both validates the value
              and gives the index-based unpacking below a uniform source (Map
              and Set have no `length`). }
            objVal := Peek();
            if objVal.IsNull() or objVal.IsUndefined() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Cannot destructure non-iterable: value is null or undefined')));
            if not (objVal.IsArray() or objVal.IsString()) then
            begin
              if not JSGetIterator(FHeap, objVal, iterObj) then
                raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', objVal.ToString() + ' is not iterable')));
              Pop();
              Push(JSMakeArray(JSIteratorToArray(iterObj)));
            end;
          end;

        opHalt:
          begin
            while FFP > AInitialFP do
              PopFrame();
          end;
      end;
      end;
    except
      on E: EFloriaJSThrow do
        HandleThrow(E.Value);
    end;
    { opYield/opAwait set this and break out of the dispatch loop. Leave
      RunLoop entirely instead of re-entering the loop at the next
      instruction. }
    if FIsSuspending then
      Break;
  end;

  if FSP > AInitialBaseBP then
    Result := Pop()
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSVM.CallFunction(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue): TFloriaJSValue;
begin
  Result := CallFunction(AFuncVal, AArgs, JSMakeUndefined());
end;

function TFloriaJSVM.CallFunction(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue; const AThisVal: TFloriaJSValue): TFloriaJSValue;
var
  fn: TFloriaJSFunction;
  subCode: TFloriaJSBytecode;
  callEnv: TFloriaJSEnvironment;
  arrObj: TFloriaJSArray;
  promise: TFloriaJSPromise;
  resVal: TFloriaJSValue;
  callArgs: TFloriaJSValueArray;
  genObj: TFloriaJSGenerator;
  effectiveThis: TFloriaJSValue;
  argc, i, initialFP, initialBaseBP, savedTryCount: Integer;
begin
  if AFuncVal.IsObject() and (AFuncVal.ObjVal is TFloriaJSProxy) then
    Exit(TFloriaJSProxy(AFuncVal.ObjVal).Call(AArgs, AThisVal));

  if not AFuncVal.IsFunction() then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', AFuncVal.ToString() + ' is not a function')));

  fn := AFuncVal.AsFunction();
  if fn = nil then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a function')));

  if fn is TFloriaJSBoundFunction then
  begin
    { Calls through .call/.apply and heap-side built-ins reach the target with
      the bound this and the bound arguments in front of the call arguments. }
    SetLength(callArgs, Length(AArgs));
    for i := 0 to High(AArgs) do
      callArgs[i] := AArgs[i];
    Exit(CallFunction(TFloriaJSBoundFunction(fn).Target,
      TFloriaJSBoundFunction(fn).CombineArguments(callArgs),
      TFloriaJSBoundFunction(fn).BoundThis));
  end;

  if fn.IsNative then
    Exit(InvokeNative(fn, AArgs, AThisVal));

  if fn.Bytecode <> nil then
  begin
    subCode := TFloriaJSBytecode(fn.Bytecode);
    effectiveThis := AThisVal;
    if not fn.IsArrow then
      effectiveThis := ResolveCallThis(subCode, AThisVal);

    if fn.IsAsyncGenerator then
      Exit(JSMakeObject(StartAsyncGenerator(fn, AArgs, effectiveThis, FGlobalEnv)));

    if fn.IsAsync then
      Exit(JSMakePromise(StartAsyncTask(fn, AArgs, effectiveThis, FGlobalEnv)));

    { Calling a generator function does not run its body: it captures the
      arguments and environment and returns a suspended generator. }
    if subCode.IsGenerator then
    begin
      genObj := MakeGenerator(fn, AArgs, effectiveThis, FGlobalEnv);
      Exit(JSMakeObject(genObj));
    end;

    if fn.ClosureEnv <> nil then
      callEnv := TFloriaJSEnvironment.Create(TFloriaJSEnvironment(fn.ClosureEnv))
    else
      callEnv := TFloriaJSEnvironment.Create(FGlobalEnv);
    FHeap.TrackEnvironment(callEnv);
    if fn.IsNamedExpression then
      callEnv.Define(fn.Name, JSMakeFunction(fn), True);

    argc := Length(AArgs);
    if subCode.LocalsInEnv then
      for i := 0 to subCode.GetArgumentCount() - 1 do
      begin
        if i < argc then
          callEnv.Define(subCode.GetArgumentName(i), AArgs[i], False)
        else
          callEnv.Define(subCode.GetArgumentName(i), JSMakeUndefined(), False);
      end;

    if not fn.IsArrow then
    begin
      callEnv.Define('this', effectiveThis);
      if (FHeap <> nil) and subCode.NeedsArguments then
      begin
        arrObj := FHeap.NewArray();
        for i := 0 to argc - 1 do
          arrObj.Push(AArgs[i]);
        callEnv.Define('arguments', JSMakeObject(arrObj));
      end;
    end;

    initialFP := FFP;
    initialBaseBP := FSP;

    for i := 0 to subCode.GetLocalCount() - 1 do
    begin
      if i < argc then
        Push(AArgs[i])
      else
        Push(JSMakeUndefined());
    end;

    if fn.IsAsync then
    begin
      promise := FHeap.NewPromise();
      PushFrame(subCode, callEnv, effectiveThis, initialBaseBP, False, nil, True);
      savedTryCount := FTryCount;
      FTryCount := 0;
      try
        resVal := RunLoop(initialFP, initialBaseBP);
        promise.Fulfill(resVal);
      except
        on E: EFloriaJSThrow do
          promise.Reject(E.Value);
        on E: Exception do
          promise.Reject(JSMakeString(E.Message));
      end;
      FTryCount := savedTryCount;
      while FFP > initialFP do
        PopFrame();
      while FSP > initialBaseBP do
        Pop();
      Result := JSMakePromise(promise);
    end
    else
    begin
      PushFrame(subCode, callEnv, effectiveThis, initialBaseBP, False, nil, True);
      savedTryCount := FTryCount;
      FTryCount := 0;
      try
        Result := RunLoop(initialFP, initialBaseBP);
      finally
        FTryCount := savedTryCount;
        while FFP > initialFP do
          PopFrame();
        while FSP > initialBaseBP do
          Pop();
      end;
    end;
  end
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSVM.ConstructObject(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue): TFloriaJSValue;
var
  fn: TFloriaJSFunction;
  protoObj, newObj: TFloriaJSObject;
  retVal, savedNewTarget, newTarget: TFloriaJSValue;
  callArgs: TFloriaJSValueArray;
  thisVal: TFloriaJSValue;
  savedConstructor: TFloriaJSFunction;
  intrinsicName: string;
  i: Integer;
begin
  if AFuncVal.IsObject() and (AFuncVal.ObjVal is TFloriaJSProxy) then
    Exit(TFloriaJSProxy(AFuncVal.ObjVal).Construct(AArgs));

  if not FHeap.IsConstructable(AFuncVal) then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a constructor')));

  { `new Bound(...)` ignores the bound this: it constructs the target with the
    combined bound and call arguments and installs the target's prototype. }
  fn := AFuncVal.AsFunction();
  SetLength(callArgs, Length(AArgs));
  for i := 0 to High(AArgs) do
    callArgs[i] := AArgs[i];
  if fn is TFloriaJSBoundFunction then
  begin
    callArgs := TFloriaJSBoundFunction(fn).CombineArguments(callArgs);
    fn := TFloriaJSBoundFunction(fn).ConstructorTarget();
    if fn = nil then
      raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a constructor')));
  end;

  { `Reflect.construct` may supply a different newTarget. Its realm decides the
    default prototype when the newTarget has no object `prototype`. }
  savedNewTarget := FHeap.CurrentNewTarget;
  newTarget := savedNewTarget;
  if not newTarget.IsFunction() then
    newTarget := JSMakeFunction(fn);
  FHeap.CurrentNewTarget := newTarget;
  savedConstructor := FHeap.CurrentConstructor;
  FHeap.CurrentConstructor := fn;
  try
    intrinsicName := 'Object';
    if fn.IntrinsicName <> '' then
      intrinsicName := fn.IntrinsicName;
    protoObj := FHeap.GetPrototypeFromConstructor(newTarget, intrinsicName);
    if protoObj = nil then
      protoObj := FHeap.GetObjectPrototype();

    { `new String(value)` constructs a boxed String object. The native
      constructor produces the primitive, so wrap it with the prototype chosen
      by newTarget instead of returning the generic pre-created object. }
    if fn.IntrinsicName = 'String' then
    begin
      retVal := CallFunction(JSMakeFunction(fn), callArgs, JSMakeUndefined());
      if retVal.IsString() then
        Result := JSMakeObject(FHeap.NewStringObject(protoObj, retVal.StrVal))
      else
        Result := retVal;
    end
    else
    begin
      newObj := FHeap.NewObject(protoObj);
      thisVal := JSMakeObject(newObj);
      retVal := CallFunction(JSMakeFunction(fn), callArgs, thisVal);
      if retVal.IsObject() then
        Result := retVal
      else
        Result := thisVal;
    end;
  finally
    FHeap.CurrentConstructor := savedConstructor;
    FHeap.CurrentNewTarget := savedNewTarget;
  end;
end;

end.
