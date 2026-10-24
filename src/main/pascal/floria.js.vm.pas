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
  floria.js.env, floria.js.bytecode;

type
  { Call Stack Frame }
  TFloriaJSCallFrame = record
    Bytecode: TFloriaJSBytecode;
    IP: Integer;
    BaseBP: Integer;
    ThisVal: TFloriaJSValue;
    Env: TFloriaJSEnvironment;
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

    { Try/Catch Exception Stack }
    FTryHandlers: array of TFloriaJSTryEntry;
    FTryCount: Integer;
    FTryCapacity: Integer;

    procedure EnsureStackCapacity();
    procedure PushFrame(ABytecode: TFloriaJSBytecode; AEnv: TFloriaJSEnvironment; const AThis: TFloriaJSValue; ABaseBP: Integer = 0; AIsConstructor: Boolean = False; AConstructedObj: TFloriaJSObject = nil; AOwnsCallEnv: Boolean = False);
    procedure PopFrame();

    procedure PushTryHandler(ACatchIP: Integer; AFrameIndex, AStackDepth: Integer; AEnv: TFloriaJSEnvironment);
    procedure PopTryHandler();
    procedure HandleThrow(const AErrVal: TFloriaJSValue);
    function  RunLoop(AInitialFP, AInitialBaseBP: Integer): TFloriaJSValue;

    function  GetMemberValue(const AObj: TFloriaJSValue; const APropName: string): TFloriaJSValue;
    procedure SetMemberValue(const AObj: TFloriaJSValue; const APropName: string; const AVal: TFloriaJSValue);
    function  HeapInvoker(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;
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
    function  Execute(ABytecode: TFloriaJSBytecode; AEnv: TFloriaJSEnvironment; const AThis: TFloriaJSValue): TFloriaJSValue;
    function  CallFunction(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue): TFloriaJSValue;
    function  CallFunction(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue; const AThisVal: TFloriaJSValue): TFloriaJSValue;
    function  ConstructObject(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue): TFloriaJSValue;

    property Heap: TFloriaJSHeap read FHeap;
    property GlobalEnv: TFloriaJSEnvironment read FGlobalEnv write FGlobalEnv;
    property MaxCallDepth: Integer read FMaxCallDepth write FMaxCallDepth;
  end;

implementation

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

  if FHeap <> nil then
    FHeap.SetFunctionInvoker(@HeapInvoker);
end;

function TFloriaJSVM.HeapInvoker(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := CallFunction(AFuncVal, AArgs, AThis);
end;

destructor TFloriaJSVM.Destroy();
begin
  if (FHeap <> nil) and not FOwnsHeap then
    FHeap.SetFunctionInvoker(nil);

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

procedure TFloriaJSVM.PushFrame(ABytecode: TFloriaJSBytecode; AEnv: TFloriaJSEnvironment; const AThis: TFloriaJSValue; ABaseBP: Integer; AIsConstructor: Boolean; AConstructedObj: TFloriaJSObject; AOwnsCallEnv: Boolean);
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
      Exit(JSMakeNumber(Length(AObj.StrVal)));
    if TryStrToInt(APropName, i) and (i >= 0) and (i < Length(AObj.StrVal)) then
      Exit(JSMakeString(Copy(AObj.StrVal, i + 1, 1)));
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
    AObj.AsObject().SetProperty(APropName, AVal);
end;

function TFloriaJSVM.Execute(ABytecode: TFloriaJSBytecode; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
begin
  Result := Execute(ABytecode, AEnv, JSMakeUndefined());
end;

function TFloriaJSVM.Execute(ABytecode: TFloriaJSBytecode; AEnv: TFloriaJSEnvironment; const AThis: TFloriaJSValue): TFloriaJSValue;
var
  i, initialFP, initialBaseBP: Integer;
begin
  if ABytecode = nil then Exit(JSMakeUndefined());

  if AEnv = nil then
    AEnv := FGlobalEnv;

  initialFP := FFP;
  initialBaseBP := FSP;

  // Reserve local variable slots on the value stack
  for i := 0 to ABytecode.GetLocalCount() - 1 do
    Push(JSMakeUndefined());

  PushFrame(ABytecode, AEnv, AThis, initialBaseBP);
  try
    Result := RunLoop(initialFP, initialBaseBP);
  finally
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
  propName, varName, iterStr, propKeyStr, pName, restName: string;
  argc, i, j, callBaseBP, asyncInitialFP: Integer;
  args: array of TFloriaJSValue;
  fn: TFloriaJSFunction;
  subCode: TFloriaJSBytecode;
  callEnv, oldEnv: TFloriaJSEnvironment;
  arrObj, restArr: TFloriaJSArray;
  fnObj, protoObj, currObj: TFloriaJSObject;
  keysList: TStringList;
  promise: TFloriaJSPromise;
  targetIP: Integer;
begin
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

    inst := curFrame^.Bytecode.GetInstruction(curFrame^.IP);
    Inc(curFrame^.IP);

    try
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
              FGlobalEnv.Assign(varName, val);
          end;

        opSetGlobal:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            val := Pop();
            if FGlobalEnv <> nil then
              FGlobalEnv.Assign(varName, val);
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
              curFrame^.Env.Assign(varName, val)
            else if FGlobalEnv <> nil then
              FGlobalEnv.Assign(varName, val);
          end;

        opDefineEnv:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            val := Pop();
            if curFrame^.Env <> nil then
              curFrame^.Env.Define(varName, val, False, bkVar)
            else if FGlobalEnv <> nil then
              FGlobalEnv.Define(varName, val, False, bkVar);
          end;

        opDefineConst:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            val := Pop();
            if curFrame^.Env <> nil then
              curFrame^.Env.Define(varName, val, True, bkConst)
            else if FGlobalEnv <> nil then
              FGlobalEnv.Define(varName, val, True, bkConst);
          end;

        opDefineLet:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            val := Pop();
            if curFrame^.Env <> nil then
              curFrame^.Env.Define(varName, val, False, bkLet)
            else if FGlobalEnv <> nil then
              FGlobalEnv.Define(varName, val, False, bkLet);
          end;

        opDeclareVar:
          begin
            varName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            if curFrame^.Env <> nil then
              curFrame^.Env.DeclareVar(varName)
            else if FGlobalEnv <> nil then
              FGlobalEnv.DeclareVar(varName);
          end;

        opPushEnv:
          begin
            curFrame^.Env := TFloriaJSEnvironment.Create(curFrame^.Env, FHeap);
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

        opGetProp:
          begin
            propVal := Pop();
            objVal := Pop();
            Push(GetMemberValue(objVal, propVal.ToString()));
          end;

        opGetPropNamed:
          begin
            propName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            objVal := Pop();
            Push(GetMemberValue(objVal, propName));
          end;

        opSetProp:
          begin
            val := Pop();
            propVal := Pop();
            objVal := Pop();
            SetMemberValue(objVal, propVal.ToString(), val);
            Push(val);
          end;

        opSetPropNamed:
          begin
            propName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            val := Pop();
            objVal := Pop();
            SetMemberValue(objVal, propName, val);
            Push(val);
          end;

        opGetPropOptional:
          begin
            propVal := Pop();
            objVal := Pop();
            if objVal.IsNull() or objVal.IsUndefined() then
              Push(JSMakeUndefined())
            else
              Push(GetMemberValue(objVal, propVal.ToString()));
          end;

        opGetPropNamedOpt:
          begin
            propName := curFrame^.Bytecode.GetConstant(inst.Imm).ToString();
            objVal := Pop();
            if objVal.IsNull() or objVal.IsUndefined() then
              Push(JSMakeUndefined())
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

        opDeleteProp:
          begin
            propVal := Pop();
            objVal := Pop();
            if objVal.IsObject() then
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
            if val.IsPromise() then
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
        opCall, opCallOpt, opCallSpread:
          begin
            if inst.Op = opCallSpread then
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

            if not calleeVal.IsFunction() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', calleeVal.ToString() + ' is not a function')));

            fn := calleeVal.AsFunction();
            if fn = nil then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a function')));

            if fn.IsNative then
            begin
              if Assigned(fn.NativeMethod) then
                resVal := fn.NativeMethod(args, thisVal)
              else if Assigned(fn.NativeProc) then
                resVal := fn.NativeProc(args, thisVal)
              else
                resVal := JSMakeUndefined();
              Push(resVal);
            end
            else if fn.Bytecode <> nil then
            begin
              subCode := TFloriaJSBytecode(fn.Bytecode);
              if fn.ClosureEnv <> nil then
                callEnv := TFloriaJSEnvironment.Create(TFloriaJSEnvironment(fn.ClosureEnv), FHeap)
              else
                callEnv := TFloriaJSEnvironment.Create(curFrame^.Env, FHeap);
              FHeap.TrackEnvironment(callEnv);

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
                if FHeap <> nil then
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

            if not calleeVal.IsFunction() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a constructor')));

            fn := calleeVal.AsFunction();
            if (fn = nil) or fn.IsArrow then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a constructor')));

            propVal := fn.GetProperty('prototype');
            if propVal.IsObject() then
              protoObj := propVal.AsObject()
            else
              protoObj := FHeap.GetObjectPrototype();

            objVal := JSMakeObject(FHeap.NewObject(protoObj));

            if fn.IsNative then
            begin
              if Assigned(fn.NativeMethod) then
                resVal := fn.NativeMethod(args, objVal)
              else if Assigned(fn.NativeProc) then
                resVal := fn.NativeProc(args, objVal)
              else
                resVal := JSMakeUndefined();

              if resVal.IsObject() then
                Push(resVal)
              else
                Push(objVal);
            end
            else if fn.Bytecode <> nil then
            begin
              subCode := TFloriaJSBytecode(fn.Bytecode);
              if fn.ClosureEnv <> nil then
                callEnv := TFloriaJSEnvironment.Create(TFloriaJSEnvironment(fn.ClosureEnv), FHeap)
              else
                callEnv := TFloriaJSEnvironment.Create(curFrame^.Env, FHeap);
              FHeap.TrackEnvironment(callEnv);

              for i := 0 to subCode.GetArgumentCount() - 1 do
              begin
                if i < argc then
                  callEnv.Define(subCode.GetArgumentName(i), args[i], False)
                else
                  callEnv.Define(subCode.GetArgumentName(i), JSMakeUndefined(), False);
              end;

              callEnv.Define('this', objVal);
              if FHeap <> nil then
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
                if not objVal.AsArray().GetElement(i).IsUndefined() then
                  arrObj.Push(JSMakeString(IntToStr(i)));
              for i := 0 to objVal.AsObject().GetPropertyCount() - 1 do
                arrObj.Push(JSMakeString(objVal.AsObject().GetPropertyKey(i)));
            end
            else if objVal.IsObject() and (objVal.ObjVal <> nil) then
            begin
              keysList := TStringList.Create();
              try
                currObj := objVal.AsObject();
                while (currObj <> nil) and (currObj <> FHeap.GetObjectPrototype()) and (currObj <> FHeap.GetArrayPrototype()) do
                begin
                  for i := 0 to currObj.GetPropertyCount() - 1 do
                  begin
                    propKeyStr := currObj.GetPropertyKey(i);
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
            objVal := Pop();
            if objVal.IsNull() or objVal.IsUndefined() then
              raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not iterable')));

            arrObj := FHeap.NewArray();
            if objVal.IsArray() then
            begin
              for i := 0 to objVal.AsArray().Length - 1 do
                arrObj.Push(objVal.AsArray().GetElement(i));
            end
            else if objVal.IsString() then
            begin
              iterStr := objVal.StrVal;
              for i := 1 to Length(iterStr) do
                arrObj.Push(JSMakeString(iterStr[i]));
            end;
            Push(JSMakeObject(arrObj));
          end;

        opHalt:
          begin
            while FFP > AInitialFP do
              PopFrame();
          end;
      end;
    except
      on E: EFloriaJSThrow do
        HandleThrow(E.Value);
    end;
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
  argc, i, initialFP, initialBaseBP: Integer;
begin
  if not AFuncVal.IsFunction() then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', AFuncVal.ToString() + ' is not a function')));

  fn := AFuncVal.AsFunction();
  if fn = nil then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a function')));

  if fn.IsNative then
  begin
    if Assigned(fn.NativeMethod) then
      Exit(fn.NativeMethod(AArgs, AThisVal))
    else if Assigned(fn.NativeProc) then
      Exit(fn.NativeProc(AArgs, AThisVal))
    else
      Exit(JSMakeUndefined());
  end;

  if fn.Bytecode <> nil then
  begin
    subCode := TFloriaJSBytecode(fn.Bytecode);
    if fn.ClosureEnv <> nil then
      callEnv := TFloriaJSEnvironment.Create(TFloriaJSEnvironment(fn.ClosureEnv))
    else
      callEnv := TFloriaJSEnvironment.Create(FGlobalEnv);
    FHeap.TrackEnvironment(callEnv);

    argc := Length(AArgs);
    for i := 0 to subCode.GetArgumentCount() - 1 do
    begin
      if i < argc then
        callEnv.Define(subCode.GetArgumentName(i), AArgs[i], False)
      else
        callEnv.Define(subCode.GetArgumentName(i), JSMakeUndefined(), False);
    end;

    if not fn.IsArrow then
    begin
      callEnv.Define('this', AThisVal);
      if FHeap <> nil then
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
      PushFrame(subCode, callEnv, AThisVal, initialBaseBP, False, nil, True);
      try
        resVal := RunLoop(initialFP, initialBaseBP);
        promise.Fulfill(resVal);
      except
        on E: EFloriaJSThrow do
          promise.Reject(E.Value);
        on E: Exception do
          promise.Reject(JSMakeString(E.Message));
      end;
      while FFP > initialFP do
        PopFrame();
      while FSP > initialBaseBP do
        Pop();
      Result := JSMakePromise(promise);
    end
    else
    begin
      PushFrame(subCode, callEnv, AThisVal, initialBaseBP, False, nil, True);
      try
        Result := RunLoop(initialFP, initialBaseBP);
      finally
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
  protoVal: TFloriaJSValue;
  protoObj, newObj: TFloriaJSObject;
  retVal: TFloriaJSValue;
begin
  if not AFuncVal.IsFunction() then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a constructor')));

  fn := AFuncVal.AsFunction();
  if (fn = nil) or fn.IsArrow then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a constructor')));

  protoVal := fn.GetProperty('prototype');
  if protoVal.IsObject() then
    protoObj := protoVal.AsObject()
  else
    protoObj := FHeap.GetObjectPrototype();

  newObj := FHeap.NewObject(protoObj);
  retVal := CallFunction(AFuncVal, AArgs, JSMakeObject(newObj));
  if retVal.IsObject() then
    Result := retVal
  else
    Result := JSMakeObject(newObj);
end;

end.
