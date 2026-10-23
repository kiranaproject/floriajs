{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — AST Evaluator & Execution Runtime               }
{                                                                          }
{   Executes parsed AST statements, evaluates expressions, handles         }
{   functions, closures, loops, and control flow signals.                  }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.evaluator;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, floria.js.types, floria.js.lexer, floria.js.ast,
  floria.js.value, floria.js.env;

type
  { Control Flow Signal Exceptions }
  EFloriaJSReturn = class(Exception)
  public
    Value: TFloriaJSValue;
    constructor Create(const AValue: TFloriaJSValue);
  end;

  EFloriaJSBreak = class(Exception);
  EFloriaJSContinue = class(Exception);

  { Runtime AST Evaluator }
  TFloriaJSEvaluator = class
  private
    FHeap: TFloriaJSHeap;
    FOwnsHeap: Boolean;
    FMaxCallDepth: Integer;
    FCurrentCallDepth: Integer;
    FClosureCount: Integer;

    function NewEnv(AParent: TFloriaJSEnvironment): TFloriaJSEnvironment;
    procedure ReleaseEnv(AEnv: TFloriaJSEnvironment);
    procedure ReclaimOrphanedEnvironments();
    function AssignToTarget(ATarget: TFloriaJSExprNode; const AVal: TFloriaJSValue; AOp: TFloriaJSTokenKind; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
    procedure RunPromiseJob(const AJob: TFloriaJSPromiseJob);
    function GetMemberValue(const AObj: TFloriaJSValue; const APropName: string): TFloriaJSValue;
    function ConstructObject(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue): TFloriaJSValue;
    function RunCatchClause(const ATryStmt: TFloriaJSTryStmt; const AThrown: TFloriaJSValue;
      AEnv: TFloriaJSEnvironment): TFloriaJSValue;
  public
    constructor Create(AHeap: TFloriaJSHeap = nil);
    destructor Destroy(); override;

    function EvaluateExpr(AExpr: TFloriaJSExprNode; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
    function ExecuteStmt(AStmt: TFloriaJSStmtNode; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
    function ExecuteProgram(AProg: TFloriaJSProgram; AEnv: TFloriaJSEnvironment): TFloriaJSValue;

    function CallFunction(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;

    procedure DrainMicrotasks();

    procedure RetainEnv(AEnv: TFloriaJSEnvironment);
    procedure OrphanEnv(AEnv: TFloriaJSEnvironment);
    function GetClosureCount(): Integer;

    property Heap: TFloriaJSHeap read FHeap;
    property MaxCallDepth: Integer read FMaxCallDepth write FMaxCallDepth;
  end;

implementation

type
  { What a try statement remembered while its try block was running }
  TFloriaJSTryPending = (ftpNone, ftpError, ftpReturn, ftpBreak, ftpContinue);

{ EFloriaJSReturn }

constructor EFloriaJSReturn.Create(const AValue: TFloriaJSValue);
begin
  inherited Create('return');
  Value := AValue;
end;

{ TFloriaJSEvaluator }

constructor TFloriaJSEvaluator.Create(AHeap: TFloriaJSHeap);
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
  FMaxCallDepth := 1024;
  FCurrentCallDepth := 0;
  FClosureCount := 0;
  if FHeap <> nil then
  begin
    FHeap.SetJobRunner(@RunPromiseJob);
    FHeap.SetFunctionInvoker(@CallFunction);
  end;
end;

destructor TFloriaJSEvaluator.Destroy();
begin
  if FHeap <> nil then
  begin
    FHeap.SetJobRunner(nil);
    FHeap.SetFunctionInvoker(nil);
  end;
  if FOwnsHeap then
    FreeAndNil(FHeap);
  inherited Destroy();
end;

function TFloriaJSEvaluator.GetMemberValue(const AObj: TFloriaJSValue; const APropName: string): TFloriaJSValue;
var
  i: Integer;
begin
  if AObj.IsObject() then
    Exit(AObj.AsObject().GetProperty(APropName));

  if AObj.IsString() then
  begin
    if APropName = 'length' then
      Exit(JSMakeNumber(Length(AObj.StrVal)));
    if TryStrToInt(APropName, i) and (i >= 0) and (i < Length(AObj.StrVal)) then
      Exit(JSMakeString(Copy(AObj.StrVal, i + 1, 1)));
    { Strings are primitives, so their methods live on a shared prototype
      that the heap owns rather than on the string itself. }
    if FHeap <> nil then
      Exit(FHeap.GetStringPrototype().GetProperty(APropName));
  end;

  Exit(JSMakeUndefined());
end;

function TFloriaJSEvaluator.ConstructObject(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue): TFloriaJSValue;
var
  fn: TFloriaJSFunction;
  protoVal: TFloriaJSValue;
  obj: TFloriaJSObject;
  resultVal: TFloriaJSValue;
begin
  if not AFuncVal.IsFunction() then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a constructor')));

  fn := AFuncVal.AsFunction();
  if fn = nil then
    raise EFloriaJSThrow.Create(JSMakeObject(FHeap.NewError('TypeError', 'Value is not a constructor')));

  { The object starts out with the prototype of its constructor, so the
    properties the constructor publishes there are visible to it. }
  protoVal := fn.GetProperty('prototype');
  if protoVal.IsObject() then
    obj := FHeap.NewObject(protoVal.AsObject())
  else
    obj := FHeap.NewObject();

  resultVal := CallFunction(AFuncVal, AArgs, JSMakeObject(obj));

  { A constructor that returns an object replaces the object that was created
    for it; a primitive return value is ignored, as in JavaScript. }
  if resultVal.IsObject() then
    Exit(resultVal);

  Result := JSMakeObject(obj);
end;

procedure TFloriaJSEvaluator.RunPromiseJob(const AJob: TFloriaJSPromiseJob);
var
  handler, res: TFloriaJSValue;
begin
  if AJob.Child = nil then Exit;

  if AJob.IsFinally then
  begin
    try
      if AJob.OnFinally.IsFunction() then
        CallFunction(AJob.OnFinally, [], JSMakeUndefined());
      if AJob.IsRejection then
        AJob.Child.Reject(AJob.Value)
      else
        AJob.Child.Fulfill(AJob.Value);
    except
      on E: EFloriaJSThrow do AJob.Child.Reject(E.Value);
      on E: Exception do AJob.Child.Reject(JSMakeString(E.Message));
    end;
    Exit;
  end;

  if AJob.IsRejection then
    handler := AJob.OnRejected
  else
    handler := AJob.OnFulfilled;

  if not handler.IsFunction() then
  begin
    if AJob.IsRejection then
      AJob.Child.Reject(AJob.Value)
    else
      AJob.Child.Fulfill(AJob.Value);
    Exit;
  end;

  try
    res := CallFunction(handler, [AJob.Value], JSMakeUndefined());
    AJob.Child.Fulfill(res);
  except
    on E: EFloriaJSThrow do AJob.Child.Reject(E.Value);
    on E: Exception do AJob.Child.Reject(JSMakeString(E.Message));
  end;
end;

procedure TFloriaJSEvaluator.DrainMicrotasks();
begin
  if FHeap <> nil then
    FHeap.RunPendingJobs();
end;

function TFloriaJSEvaluator.NewEnv(AParent: TFloriaJSEnvironment): TFloriaJSEnvironment;
begin
  Result := TFloriaJSEnvironment.Create(AParent);
  if FHeap <> nil then
    FHeap.TrackEnvironment(Result);
end;

procedure TFloriaJSEvaluator.ReleaseEnv(AEnv: TFloriaJSEnvironment);
begin
  if AEnv = nil then Exit;
  if FHeap <> nil then
    FHeap.Untrack(AEnv);
  AEnv.Free();
end;

procedure TFloriaJSEvaluator.RetainEnv(AEnv: TFloriaJSEnvironment);
begin
  { Hands ownership of an environment to the JS heap, so it stays alive for
    as long as the runtime instead of being reclaimed with its creator. }
  if (AEnv <> nil) and (FHeap <> nil) then
    FHeap.TrackEnvironment(AEnv);
end;

procedure TFloriaJSEvaluator.OrphanEnv(AEnv: TFloriaJSEnvironment);
begin
  if AEnv = nil then Exit;
  if FHeap <> nil then
    FHeap.TrackEnvironment(AEnv);
  AEnv.Detach;
end;

procedure TFloriaJSEvaluator.ReclaimOrphanedEnvironments();
var
  i, j: Integer;
  env: TFloriaJSEnvironment;
  obj: TFloriaJSObject;
  fn: TFloriaJSFunction;
  kept: TFPList;
  hasOrphans, keep: Boolean;

  procedure MarkKept(AEnv: TFloriaJSEnvironment);
  var
    cur: TFloriaJSEnvironment;
  begin
    cur := AEnv;
    while cur <> nil do
    begin
      if kept.IndexOf(cur) >= 0 then Exit;
      kept.Add(cur);
      cur := cur.Parent;
    end;
  end;

begin
  if FHeap = nil then Exit;

  hasOrphans := False;
  for i := 0 to FHeap.GetEnvironmentCount() - 1 do
    if TFloriaJSEnvironment(FHeap.GetEnvironment(i)).Detached then
    begin
      hasOrphans := True;
      Break;
    end;
  if not hasOrphans then Exit;

  kept := TFPList.Create();
  try
    for i := 0 to FHeap.GetEnvironmentCount() - 1 do
    begin
      env := TFloriaJSEnvironment(FHeap.GetEnvironment(i));
      if (env = nil) or (not env.Detached) then Continue;

      keep := False;
      for j := 0 to FHeap.GetObjectCount() - 1 do
      begin
        obj := FHeap.GetObject(j);
        if not (obj is TFloriaJSFunction) then Continue;
        fn := TFloriaJSFunction(obj);
        if fn.ClosureEnv <> Pointer(env) then Continue;
        if fn.Pinned or (fn.RefCount > env.CountReferences(fn)) then
        begin
          keep := True;
          Break;
        end;
      end;

      if keep then
        MarkKept(env);
    end;

    for i := FHeap.GetEnvironmentCount() - 1 downto 0 do
    begin
      env := TFloriaJSEnvironment(FHeap.GetEnvironment(i));
      if (env = nil) or (not env.Detached) or (kept.IndexOf(env) >= 0) then Continue;
      FHeap.Untrack(env);
      env.Free();
    end;
  finally
    kept.Free();
  end;
end;

function TFloriaJSEvaluator.GetClosureCount(): Integer;
begin
  Result := FClosureCount;
end;

function TFloriaJSEvaluator.RunCatchClause(const ATryStmt: TFloriaJSTryStmt;
  const AThrown: TFloriaJSValue; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
var
  catchEnv: TFloriaJSEnvironment;
  closureMark: Integer;
begin
  { The thrown value is bound in a scope of its own, so it is only visible
    inside the catch clause. }
  catchEnv := NewEnv(AEnv);
  closureMark := FClosureCount;

  try
    if ATryStmt.CatchParam <> '' then
      catchEnv.Define(ATryStmt.CatchParam, AThrown);
    Result := ExecuteStmt(ATryStmt.CatchBlock, catchEnv);
  finally
    { The catch scope can only outlive the clause when a closure captured it.
      Otherwise it is reclaimed immediately. }
    if FClosureCount = closureMark then
      ReleaseEnv(catchEnv)
    else
      OrphanEnv(catchEnv);
  end;
end;

function TFloriaJSEvaluator.AssignToTarget(ATarget: TFloriaJSExprNode; const AVal: TFloriaJSValue; AOp: TFloriaJSTokenKind; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
var
  ident: TFloriaJSIdentifierExpr;
  member: TFloriaJSMemberExpr;
  oldVal, computedVal, objVal: TFloriaJSValue;
  propName: string;
begin
  // Identifier assignment
  if ATarget is TFloriaJSIdentifierExpr then
  begin
    ident := TFloriaJSIdentifierExpr(ATarget);
    if AOp = tkAssign then
      computedVal := AVal
    else
    begin
      oldVal := AEnv.GetDefault(ident.Name, JSMakeUndefined());
      case AOp of
        tkPlusAssign:     computedVal := JSAdd(oldVal, AVal);
        tkMinusAssign:    computedVal := JSSubtract(oldVal, AVal);
        tkMultiplyAssign: computedVal := JSMultiply(oldVal, AVal);
        tkDivideAssign:   computedVal := JSDivide(oldVal, AVal);
        tkModuloAssign:   computedVal := JSModulo(oldVal, AVal);
        tkPowerAssign:    computedVal := JSPower(oldVal, AVal);
      else
        computedVal := AVal;
      end;
    end;

    AEnv.Assign(ident.Name, computedVal);
    Exit(computedVal);
  end;

  // Member expression assignment: obj.prop = val or obj[prop] = val
  if ATarget is TFloriaJSMemberExpr then
  begin
    member := TFloriaJSMemberExpr(ATarget);
    objVal := EvaluateExpr(member.Target, AEnv);

    if not member.Computed then
      propName := member.PropertyName
    else
      propName := EvaluateExpr(member.PropertyExpr, AEnv).ToString();

    if AOp = tkAssign then
      computedVal := AVal
    else
    begin
      if objVal.IsObject() then
        oldVal := objVal.AsObject().GetProperty(propName)
      else
        oldVal := JSMakeUndefined();

      case AOp of
        tkPlusAssign:     computedVal := JSAdd(oldVal, AVal);
        tkMinusAssign:    computedVal := JSSubtract(oldVal, AVal);
        tkMultiplyAssign: computedVal := JSMultiply(oldVal, AVal);
        tkDivideAssign:   computedVal := JSDivide(oldVal, AVal);
        tkModuloAssign:   computedVal := JSModulo(oldVal, AVal);
        tkPowerAssign:    computedVal := JSPower(oldVal, AVal);
      else
        computedVal := AVal;
      end;
    end;

    if objVal.IsObject() then
      objVal.AsObject().SetProperty(propName, computedVal);

    Exit(computedVal);
  end;

  Result := AVal;
end;

function TFloriaJSEvaluator.EvaluateExpr(AExpr: TFloriaJSExprNode; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
var
  lit: TFloriaJSLiteralExpr;
  ident: TFloriaJSIdentifierExpr;
  unary: TFloriaJSUnaryExpr;
  bin: TFloriaJSBinaryExpr;
  cond: TFloriaJSConditionalExpr;
  assign: TFloriaJSAssignExpr;
  member: TFloriaJSMemberExpr;
  call: TFloriaJSCallExpr;
  arrLit: TFloriaJSArrayExpr;
  objLit: TFloriaJSObjectExpr;
  fnExpr: TFloriaJSFunctionExpr;
  promise: TFloriaJSPromise;
  lVal, rVal, objVal, thisVal, fnVal: TFloriaJSValue;
  arrObj: TFloriaJSArray;
  jsObj: TFloriaJSObject;
  fnObj: TFloriaJSFunction;
  argVals: array of TFloriaJSValue;
  propName: string;
  i, count: Integer;
begin
  if AExpr = nil then
    Exit(JSMakeUndefined());

  // 1. Literal
  if AExpr is TFloriaJSLiteralExpr then
  begin
    lit := TFloriaJSLiteralExpr(AExpr);
    case lit.ValueType of
      fjstNumber:    Exit(JSMakeNumber(lit.NumberVal));
      fjstString:    Exit(JSMakeString(lit.StringVal));
      fjstBoolean:   Exit(JSMakeBoolean(lit.BoolVal));
      fjstNull:      Exit(JSMakeNull());
      fjstUndefined: Exit(JSMakeUndefined());
    else
      Exit(JSMakeUndefined());
    end;
  end;

  // 2. Identifier
  if AExpr is TFloriaJSIdentifierExpr then
  begin
    ident := TFloriaJSIdentifierExpr(AExpr);
    if AEnv.Get(ident.Name, lVal) then
      Exit(lVal)
    else
      Exit(JSMakeUndefined());
  end;

  // 3. Unary Expression
  if AExpr is TFloriaJSUnaryExpr then
  begin
    unary := TFloriaJSUnaryExpr(AExpr);
    if unary.IsPrefix then
    begin
      case unary.Op of
        tkMinus:   Exit(JSUnaryMinus(EvaluateExpr(unary.Operand, AEnv)));
        tkPlus:    Exit(JSUnaryPlus(EvaluateExpr(unary.Operand, AEnv)));
        tkNot:     Exit(JSUnaryNot(EvaluateExpr(unary.Operand, AEnv)));
        tkBitNot:  Exit(JSUnaryBitNot(EvaluateExpr(unary.Operand, AEnv)));
        tkTypeof:
        begin
          if unary.Operand is TFloriaJSIdentifierExpr then
            Exit(JSMakeString(JSTypeOf(AEnv.GetDefault(TFloriaJSIdentifierExpr(unary.Operand).Name, JSMakeUndefined()))))
          else
            Exit(JSMakeString(JSTypeOf(EvaluateExpr(unary.Operand, AEnv))));
        end;
        tkAwait:
        begin
          lVal := EvaluateExpr(unary.Operand, AEnv);
          if lVal.IsPromise() then
          begin
            promise := lVal.AsPromise();
            { There is no host event source, so drain the microtask queue to
              let every promise that can still settle do so. }
            while (promise.State = fjspPending) and FHeap.HasPromiseJobs() do
              FHeap.RunPendingJobs();

            if promise.State = fjspRejected then
              raise EFloriaJSThrow.Create(promise.ResultValue);
            if promise.State = fjspFulfilled then
              Exit(promise.ResultValue);
            Exit(JSMakeUndefined());
          end;
          Exit(lVal);
        end;
        tkPlusPlus:
        begin
          lVal := EvaluateExpr(unary.Operand, AEnv);
          rVal := JSMakeNumber(lVal.ToNumber() + 1.0);
          AssignToTarget(unary.Operand, rVal, tkAssign, AEnv);
          Exit(rVal);
        end;
        tkMinusMinus:
        begin
          lVal := EvaluateExpr(unary.Operand, AEnv);
          rVal := JSMakeNumber(lVal.ToNumber() - 1.0);
          AssignToTarget(unary.Operand, rVal, tkAssign, AEnv);
          Exit(rVal);
        end;
      else
        Exit(JSMakeUndefined());
      end;
    end
    else
    begin
      // Postfix ++ / --
      lVal := EvaluateExpr(unary.Operand, AEnv);
      case unary.Op of
        tkPlusPlus:
        begin
          rVal := JSMakeNumber(lVal.ToNumber() + 1.0);
          AssignToTarget(unary.Operand, rVal, tkAssign, AEnv);
          Exit(lVal); // Returns previous value
        end;
        tkMinusMinus:
        begin
          rVal := JSMakeNumber(lVal.ToNumber() - 1.0);
          AssignToTarget(unary.Operand, rVal, tkAssign, AEnv);
          Exit(lVal);
        end;
      else
        Exit(lVal);
      end;
    end;
  end;

  // 4. Binary Expression
  if AExpr is TFloriaJSBinaryExpr then
  begin
    bin := TFloriaJSBinaryExpr(AExpr);

    // Short-circuit logical operators
    if bin.Op = tkAnd then
    begin
      lVal := EvaluateExpr(bin.Left, AEnv);
      if not lVal.ToBoolean() then Exit(lVal);
      Exit(EvaluateExpr(bin.Right, AEnv));
    end;

    if bin.Op = tkOr then
    begin
      lVal := EvaluateExpr(bin.Left, AEnv);
      if lVal.ToBoolean() then Exit(lVal);
      Exit(EvaluateExpr(bin.Right, AEnv));
    end;

    if bin.Op = tkNullish then
    begin
      lVal := EvaluateExpr(bin.Left, AEnv);
      if not (lVal.IsUndefined() or lVal.IsNull()) then Exit(lVal);
      Exit(EvaluateExpr(bin.Right, AEnv));
    end;

    lVal := EvaluateExpr(bin.Left, AEnv);
    rVal := EvaluateExpr(bin.Right, AEnv);

    case bin.Op of
      tkPlus:               Exit(JSAdd(lVal, rVal));
      tkMinus:              Exit(JSSubtract(lVal, rVal));
      tkMultiply:           Exit(JSMultiply(lVal, rVal));
      tkDivide:             Exit(JSDivide(lVal, rVal));
      tkModulo:             Exit(JSModulo(lVal, rVal));
      tkPower:              Exit(JSPower(lVal, rVal));
      tkEqual:              Exit(JSMakeBoolean(JSEqual(lVal, rVal)));
      tkStrictEqual:        Exit(JSMakeBoolean(JSStrictEqual(lVal, rVal)));
      tkNotEqual:           Exit(JSMakeBoolean(not JSEqual(lVal, rVal)));
      tkStrictNotEqual:     Exit(JSMakeBoolean(not JSStrictEqual(lVal, rVal)));
      tkLessThan:           Exit(JSMakeBoolean(JSLessThan(lVal, rVal)));
      tkLessEqual:          Exit(JSMakeBoolean(JSLessEqual(lVal, rVal)));
      tkGreaterThan:        Exit(JSMakeBoolean(JSGreaterThan(lVal, rVal)));
      tkGreaterEqual:       Exit(JSMakeBoolean(JSGreaterEqual(lVal, rVal)));
      tkBitAnd:             Exit(JSBitAnd(lVal, rVal));
      tkBitOr:              Exit(JSBitOr(lVal, rVal));
      tkBitXor:             Exit(JSBitXor(lVal, rVal));
      tkShiftLeft:          Exit(JSShiftLeft(lVal, rVal));
      tkShiftRight:         Exit(JSShiftRight(lVal, rVal));
      tkShiftRightUnsigned: Exit(JSShiftRightUnsigned(lVal, rVal));
      tkIn:
        begin
          if not rVal.IsObject() then
            Exit(JSMakeBoolean(False));
          Exit(JSMakeBoolean(rVal.AsObject().HasProperty(lVal.ToString())));
        end;
      tkInstanceof:
        begin
          if not lVal.IsObject() then
            Exit(JSMakeBoolean(False));
          if not rVal.IsFunction() then
            Exit(JSMakeBoolean(False));
          { Walk prototype chain }
          Exit(JSMakeBoolean(JSInstanceOf(lVal, rVal)));
        end;
    else
      Exit(JSMakeUndefined());
    end;
  end;

  // 5. Conditional (Ternary) Expression
  if AExpr is TFloriaJSConditionalExpr then
  begin
    cond := TFloriaJSConditionalExpr(AExpr);
    lVal := EvaluateExpr(cond.Condition, AEnv);
    if lVal.ToBoolean() then
      Exit(EvaluateExpr(cond.Consequent, AEnv))
    else
      Exit(EvaluateExpr(cond.Alternate, AEnv));
  end;

  // 6. Assignment Expression
  if AExpr is TFloriaJSAssignExpr then
  begin
    assign := TFloriaJSAssignExpr(AExpr);
    rVal := EvaluateExpr(assign.Value, AEnv);
    Exit(AssignToTarget(assign.Target, rVal, assign.Op, AEnv));
  end;

  // 7. Member Expression
  if AExpr is TFloriaJSMemberExpr then
  begin
    member := TFloriaJSMemberExpr(AExpr);
    objVal := EvaluateExpr(member.Target, AEnv);

    if not member.Computed then
      propName := member.PropertyName
    else
      propName := EvaluateExpr(member.PropertyExpr, AEnv).ToString();

    Exit(GetMemberValue(objVal, propName));
  end;

  // 8. Call Expression (and construction with new)
  if AExpr is TFloriaJSCallExpr then
  begin
    call := TFloriaJSCallExpr(AExpr);
    fnVal := EvaluateExpr(call.Callee, AEnv);

    if not call.IsNew then
    begin
      if call.Callee is TFloriaJSMemberExpr then
        thisVal := EvaluateExpr(TFloriaJSMemberExpr(call.Callee).Target, AEnv)
      else
        thisVal := JSMakeUndefined();
    end;

    count := call.GetArgumentCount();
    SetLength(argVals, count);
    for i := 0 to count - 1 do
      argVals[i] := EvaluateExpr(call.GetArgument(i), AEnv);

    if call.IsNew then
      Exit(ConstructObject(fnVal, argVals));

    Exit(CallFunction(fnVal, argVals, thisVal));
  end;

  // 9. Array Literal
  if AExpr is TFloriaJSArrayExpr then
  begin
    arrLit := TFloriaJSArrayExpr(AExpr);
    arrObj := FHeap.NewArray();
    for i := 0 to arrLit.GetElementCount() - 1 do
      arrObj.Push(EvaluateExpr(arrLit.GetElement(i), AEnv));
    Exit(JSMakeArray(arrObj));
  end;

  // 10. Object Literal
  if AExpr is TFloriaJSObjectExpr then
  begin
    objLit := TFloriaJSObjectExpr(AExpr);
    jsObj := FHeap.NewObject();
    for i := 0 to objLit.GetPropertyCount() - 1 do
      jsObj.SetProperty(objLit.GetPropertyKey(i), EvaluateExpr(objLit.GetPropertyValue(i), AEnv));
    Exit(JSMakeObject(jsObj));
  end;

  // 11. Function Expression
  if AExpr is TFloriaJSFunctionExpr then
  begin
    fnExpr := TFloriaJSFunctionExpr(AExpr);
    fnObj := FHeap.NewUserFunction(fnExpr.Name, fnExpr.Parameters, fnExpr.Body, Pointer(AEnv), False, fnExpr.IsAsync);
    Inc(FClosureCount);
    { The closure refers to the environment it was created in, so that
      environment must outlive the scope it belongs to. }
    AEnv.MarkCaptured;
    Exit(JSMakeFunction(fnObj));
  end;

  Result := JSMakeUndefined();
end;

function TFloriaJSEvaluator.ExecuteStmt(AStmt: TFloriaJSStmtNode; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
var
  exprStmt: TFloriaJSExprStmt;
  varStmt: TFloriaJSVarStmt;
  blockStmt: TFloriaJSBlockStmt;
  ifStmt: TFloriaJSIfStmt;
  whileStmt: TFloriaJSWhileStmt;
  forStmt: TFloriaJSForStmt;
  switchStmt: TFloriaJSSwitchStmt;
  caseClause: TFloriaJSSwitchCase;
  tryStmt: TFloriaJSTryStmt;
  throwStmt: TFloriaJSThrowStmt;
  retStmt: TFloriaJSReturnStmt;
  fnDecl: TFloriaJSFunctionDecl;
  fnObj: TFloriaJSFunction;
  blockEnv, loopEnv, switchEnv: TFloriaJSEnvironment;
  initVal, retVal, discVal: TFloriaJSValue;
  pendingValue: TFloriaJSValue;
  pending: TFloriaJSTryPending;
  initNode: TFloriaJSASTNode;
  closureMark: Integer;
  startIdx, i, j, count: Integer;
begin
  if AStmt = nil then
    Exit(JSMakeUndefined());

  // 1. Expression Statement
  if AStmt is TFloriaJSExprStmt then
  begin
    exprStmt := TFloriaJSExprStmt(AStmt);
    Exit(EvaluateExpr(exprStmt.Expression, AEnv));
  end;

  // 2. Variable Declaration Statement: let, const, var
  if AStmt is TFloriaJSVarStmt then
  begin
    varStmt := TFloriaJSVarStmt(AStmt);
    count := varStmt.GetDeclaratorCount();
    for i := 0 to count - 1 do
    begin
      if varStmt.GetDeclaratorInit(i) <> nil then
        initVal := EvaluateExpr(varStmt.GetDeclaratorInit(i), AEnv)
      else
        initVal := JSMakeUndefined();

      AEnv.Define(varStmt.GetDeclaratorName(i), initVal, varStmt.Kind = tkConst);
    end;
    Exit(JSMakeUndefined());
  end;

  // 3. Block Statement
  if AStmt is TFloriaJSBlockStmt then
  begin
    blockStmt := TFloriaJSBlockStmt(AStmt);
    blockEnv := NewEnv(AEnv);
    closureMark := FClosureCount;
    try
      Result := JSMakeUndefined();
      count := blockStmt.GetStatementCount();
      for i := 0 to count - 1 do
        Result := ExecuteStmt(blockStmt.GetStatement(i), blockEnv);
    finally
      { A block scope can only outlive its execution when a closure captured
        it. When no closure was created the scope is reclaimed immediately,
        which keeps repeated block execution from growing the heap. }
      if FClosureCount = closureMark then
        ReleaseEnv(blockEnv)
      else
        OrphanEnv(blockEnv);
    end;
    Exit;
  end;

  // 4. If Statement
  if AStmt is TFloriaJSIfStmt then
  begin
    ifStmt := TFloriaJSIfStmt(AStmt);
    if EvaluateExpr(ifStmt.Condition, AEnv).ToBoolean() then
      Exit(ExecuteStmt(ifStmt.Consequent, AEnv))
    else if ifStmt.Alternate <> nil then
      Exit(ExecuteStmt(ifStmt.Alternate, AEnv))
    else
      Exit(JSMakeUndefined());
  end;

  // 5. While & Do-While Statement
  if AStmt is TFloriaJSWhileStmt then
  begin
    whileStmt := TFloriaJSWhileStmt(AStmt);
    Result := JSMakeUndefined();

    if whileStmt.IsDoWhile then
    begin
      repeat
        try
          Result := ExecuteStmt(whileStmt.Body, AEnv);
        except
          on EFloriaJSBreak do Break;
          on EFloriaJSContinue do ;
        end;
      until not EvaluateExpr(whileStmt.Condition, AEnv).ToBoolean();
    end
    else
    begin
      while EvaluateExpr(whileStmt.Condition, AEnv).ToBoolean() do
      begin
        try
          Result := ExecuteStmt(whileStmt.Body, AEnv);
        except
          on EFloriaJSBreak do Break;
          on EFloriaJSContinue do ;
        end;
      end;
    end;
    Exit;
  end;

  // 6. For Statement
  if AStmt is TFloriaJSForStmt then
  begin
    forStmt := TFloriaJSForStmt(AStmt);
    loopEnv := NewEnv(AEnv);
    closureMark := FClosureCount;

    try
      initNode := forStmt.Init;
      if initNode <> nil then
      begin
        if initNode is TFloriaJSStmtNode then
          ExecuteStmt(TFloriaJSStmtNode(initNode), loopEnv)
        else if initNode is TFloriaJSExprNode then
          EvaluateExpr(TFloriaJSExprNode(initNode), loopEnv);
      end;

      Result := JSMakeUndefined();
      while True do
      begin
        if forStmt.Test <> nil then
        begin
          if not EvaluateExpr(forStmt.Test, loopEnv).ToBoolean() then
            Break;
        end;

        try
          Result := ExecuteStmt(forStmt.Body, loopEnv);
        except
          on EFloriaJSBreak do Break;
          on EFloriaJSContinue do ;
        end;

        if forStmt.Update <> nil then
          EvaluateExpr(forStmt.Update, loopEnv);
      end;
    finally
      { The loop scope can only escape the loop when a closure captured it. }
      if FClosureCount = closureMark then
        ReleaseEnv(loopEnv)
      else
        OrphanEnv(loopEnv);
    end;
    Exit;
  end;

  // 7. Switch Statement
  if AStmt is TFloriaJSSwitchStmt then
  begin
    switchStmt := TFloriaJSSwitchStmt(AStmt);
    switchEnv := NewEnv(AEnv);
    closureMark := FClosureCount;

    try
      discVal := EvaluateExpr(switchStmt.Discriminant, switchEnv);

      { Locate the clause to start from: the first case whose test matches
        the discriminant, or the default clause when nothing matches. }
      startIdx := -1;
      for i := 0 to switchStmt.GetCaseCount() - 1 do
      begin
        caseClause := switchStmt.GetCase(i);
        if caseClause.IsDefault then
          Continue;
        if JSStrictEqual(discVal, EvaluateExpr(caseClause.Test, switchEnv)) then
        begin
          startIdx := i;
          Break;
        end;
      end;

      if startIdx < 0 then
        for i := 0 to switchStmt.GetCaseCount() - 1 do
          if switchStmt.GetCase(i).IsDefault then
          begin
            startIdx := i;
            Break;
          end;

      Result := JSMakeUndefined();
      if startIdx < 0 then
        Exit;

      { Clauses fall through to the ones that follow them, until a break
        statement ends the switch. }
      try
        for i := startIdx to switchStmt.GetCaseCount() - 1 do
        begin
          caseClause := switchStmt.GetCase(i);
          for j := 0 to caseClause.GetStatementCount() - 1 do
            Result := ExecuteStmt(caseClause.GetStatement(j), switchEnv);
        end;
      except
        on EFloriaJSBreak do ;  { A break leaves the switch }
        on EFloriaJSContinue do raise; { A continue belongs to the enclosing loop }
      end;
    finally
      { The switch scope can only outlive the switch when a closure captured
        it. Otherwise it is reclaimed immediately. }
      if FClosureCount = closureMark then
        ReleaseEnv(switchEnv)
      else
        OrphanEnv(switchEnv);
    end;
    Exit;
  end;

  // 8. Try Statement
  if AStmt is TFloriaJSTryStmt then
  begin
    tryStmt := TFloriaJSTryStmt(AStmt);

    { The try block runs first. An error or a control flow signal is
      remembered instead of travelling on, so that the catch clause and the
      finally clause never run while an exception is in flight. Raising a
      new error there would replace the pending one and would leave it
      behind unreleased. }
    pending := ftpNone;
    pendingValue := JSMakeUndefined();

    try
      Result := ExecuteStmt(tryStmt.Block, AEnv);
    except
      on E: EFloriaJSReturn do
      begin
        pending := ftpReturn;
        pendingValue := E.Value;
      end;
      on E: EFloriaJSBreak do
        pending := ftpBreak;
      on E: EFloriaJSContinue do
        pending := ftpContinue;
      on E: EFloriaJSThrow do
      begin
        pending := ftpError;
        pendingValue := E.Value;
      end;
      on E: Exception do
      begin
        { A runtime error of the host is caught like any other error. }
        pending := ftpError;
        pendingValue := JSMakeString(E.Message);
      end;
    end;

    { The catch clause handles a remembered error. Without a catch clause the
      error keeps travelling outwards. }
    if (pending = ftpError) and (tryStmt.CatchBlock <> nil) then
    begin
      Result := RunCatchClause(tryStmt, pendingValue, AEnv);
      pending := ftpNone;
    end;

    { The finally clause runs in every case, also when the try block raised
      an error or the clause is left with a return, a break or a continue.
      An error it raises itself replaces the pending one. }
    if tryStmt.FinallyBlock <> nil then
      ExecuteStmt(tryStmt.FinallyBlock, AEnv);

    { An error that was not handled and a control flow signal travel on. }
    case pending of
      ftpError:    raise EFloriaJSThrow.Create(pendingValue);
      ftpReturn:   raise EFloriaJSReturn.Create(pendingValue);
      ftpBreak:    raise EFloriaJSBreak.Create('');
      ftpContinue: raise EFloriaJSContinue.Create('');
    end;

    Exit;
  end;

  // 9. Throw Statement
  if AStmt is TFloriaJSThrowStmt then
  begin
    throwStmt := TFloriaJSThrowStmt(AStmt);
    raise EFloriaJSThrow.Create(EvaluateExpr(throwStmt.Expression, AEnv));
  end;

  // 10. Return Statement
  if AStmt is TFloriaJSReturnStmt then
  begin
    retStmt := TFloriaJSReturnStmt(AStmt);
    if retStmt.Argument <> nil then
      retVal := EvaluateExpr(retStmt.Argument, AEnv)
    else
      retVal := JSMakeUndefined();

    raise EFloriaJSReturn.Create(retVal);
  end;

  // 11. Break Statement
  if AStmt is TFloriaJSBreakStmt then
    raise EFloriaJSBreak.Create('');

  // 12. Continue Statement
  if AStmt is TFloriaJSContinueStmt then
    raise EFloriaJSContinue.Create('');

  // 13. Function Declaration
  if AStmt is TFloriaJSFunctionDecl then
  begin
    fnDecl := TFloriaJSFunctionDecl(AStmt);
    fnObj := FHeap.NewUserFunction(fnDecl.Name, fnDecl.Parameters, fnDecl.Body, Pointer(AEnv), False, fnDecl.IsAsync);
    Inc(FClosureCount);
    { The closure refers to the environment it was created in, so that
      environment must outlive the scope it belongs to. }
    AEnv.MarkCaptured;
    AEnv.Define(fnDecl.Name, JSMakeFunction(fnObj));
    Exit(JSMakeUndefined());
  end;

  Result := JSMakeUndefined();
end;

function TFloriaJSEvaluator.ExecuteProgram(AProg: TFloriaJSProgram; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
var
  i, count: Integer;
begin
  Result := JSMakeUndefined();
  if AProg = nil then Exit;

  { Safe point: no transient copy of a value of a running script is alive
    here, so the runtime can reclaim the environments and the objects that
    nothing refers to any more. The objects that the host holds on to are
    pinned and stay alive. }
  if FHeap <> nil then
  begin
    ReclaimOrphanedEnvironments();
    FHeap.Collect();
  end;

  count := AProg.GetStatementCount();
  for i := 0 to count - 1 do
    Result := ExecuteStmt(AProg.GetStatement(i), AEnv);

  { Run deferred promise reactions (then/catch/finally) before returning.
    The completion value of the script stays the one captured while the last
    statement ran, exactly as it is in JavaScript. }
  if FHeap <> nil then
  begin
    FHeap.RunPendingJobs();
    while FHeap.HasPromiseJobs() do
      FHeap.RunPendingJobs();
  end;
end;

function TFloriaJSEvaluator.CallFunction(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;
var
  fn: TFloriaJSFunction;
  callEnv: TFloriaJSEnvironment;
  closureMark: Integer;
  promise: TFloriaJSPromise;
  i, paramCount: Integer;
begin
  if not AFuncVal.IsFunction() then
    Exit(JSMakeUndefined());

  fn := AFuncVal.AsFunction();
  if fn = nil then
    Exit(JSMakeUndefined());

  Inc(FCurrentCallDepth);
  try
    if FCurrentCallDepth > FMaxCallDepth then
      raise Exception.Create('Maximum call stack size exceeded');

    // 1. Native host callback
    if fn.IsNative then
    begin
      if Assigned(fn.NativeProc) then
        Exit(fn.NativeProc(AArgs, AThis));
      if Assigned(fn.NativeMethod) then
        Exit(fn.NativeMethod(AArgs, AThis));
      Exit(JSMakeUndefined());
    end;

    // 2. User-defined AST function
    callEnv := NewEnv(TFloriaJSEnvironment(fn.ClosureEnv));
    callEnv.Define('this', AThis);
    paramCount := fn.ParamNames.Count;
    for i := 0 to paramCount - 1 do
    begin
      if i <= High(AArgs) then
        callEnv.Define(fn.ParamNames[i], AArgs[i])
      else
        callEnv.Define(fn.ParamNames[i], JSMakeUndefined());
    end;

    closureMark := FClosureCount;

    { Async functions execute synchronously up to the first await (as in
      JavaScript) but always hand back a promise. }
    if fn.IsAsync then
    begin
      promise := FHeap.NewPromise();
      try
        try
          if fn.Body <> nil then
            ExecuteStmt(fn.Body, callEnv);
          promise.Fulfill(JSMakeUndefined());
        except
          on E: EFloriaJSReturn do
            promise.Fulfill(E.Value);
          on E: EFloriaJSThrow do
            promise.Reject(E.Value);
          on E: Exception do
            promise.Reject(JSMakeString(E.Message));
        end;
      finally
        if FClosureCount = closureMark then
          ReleaseEnv(callEnv)
        else
          OrphanEnv(callEnv);
      end;
      Exit(JSMakePromise(promise));
    end;

    try
      try
        if fn.Body <> nil then
          ExecuteStmt(fn.Body, callEnv);
        Result := JSMakeUndefined();
      except
        on E: EFloriaJSReturn do
          Result := E.Value;
      end;
    finally
      { The activation scope can only escape the call when a closure captured
        it. Otherwise it is reclaimed right away, so recursive or repeated
        calls do not accumulate environments. }
      if FClosureCount = closureMark then
        ReleaseEnv(callEnv)
      else
        OrphanEnv(callEnv);
    end;
  finally
    Dec(FCurrentCallDepth);
  end;
end;

end.
