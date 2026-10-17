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
  Classes, SysUtils, floria.js.types, floria.js.lexer, floria.js.ast,
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

    function NewEnv(AParent: TFloriaJSEnvironment): TFloriaJSEnvironment;
    function AssignToTarget(ATarget: TFloriaJSExprNode; const AVal: TFloriaJSValue; AOp: TFloriaJSTokenKind; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
  public
    constructor Create(AHeap: TFloriaJSHeap = nil);
    destructor Destroy(); override;

    function EvaluateExpr(AExpr: TFloriaJSExprNode; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
    function ExecuteStmt(AStmt: TFloriaJSStmtNode; AEnv: TFloriaJSEnvironment): TFloriaJSValue;
    function ExecuteProgram(AProg: TFloriaJSProgram; AEnv: TFloriaJSEnvironment): TFloriaJSValue;

    function CallFunction(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;

    property Heap: TFloriaJSHeap read FHeap;
    property MaxCallDepth: Integer read FMaxCallDepth write FMaxCallDepth;
  end;

implementation

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
end;

destructor TFloriaJSEvaluator.Destroy();
begin
  if FOwnsHeap then
    FreeAndNil(FHeap);
  inherited Destroy();
end;

function TFloriaJSEvaluator.NewEnv(AParent: TFloriaJSEnvironment): TFloriaJSEnvironment;
begin
  Result := TFloriaJSEnvironment.Create(AParent);
  if FHeap <> nil then
    FHeap.TrackEnvironment(Result);
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

    if objVal.IsObject() then
      Exit(objVal.AsObject().GetProperty(propName));

    if objVal.IsString() then
    begin
      if propName = 'length' then
        Exit(JSMakeNumber(Length(objVal.StrVal)));
      if TryStrToInt(propName, i) and (i >= 0) and (i < Length(objVal.StrVal)) then
        Exit(JSMakeString(Copy(objVal.StrVal, i + 1, 1)));
    end;

    Exit(JSMakeUndefined());
  end;

  // 8. Call Expression
  if AExpr is TFloriaJSCallExpr then
  begin
    call := TFloriaJSCallExpr(AExpr);
    fnVal := EvaluateExpr(call.Callee, AEnv);

    if call.Callee is TFloriaJSMemberExpr then
      thisVal := EvaluateExpr(TFloriaJSMemberExpr(call.Callee).Target, AEnv)
    else
      thisVal := JSMakeUndefined();

    count := call.GetArgumentCount();
    SetLength(argVals, count);
    for i := 0 to count - 1 do
      argVals[i] := EvaluateExpr(call.GetArgument(i), AEnv);

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
    fnObj := FHeap.NewUserFunction(fnExpr.Name, fnExpr.Parameters, fnExpr.Body, Pointer(AEnv));
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
  retStmt: TFloriaJSReturnStmt;
  fnDecl: TFloriaJSFunctionDecl;
  fnObj: TFloriaJSFunction;
  blockEnv, loopEnv: TFloriaJSEnvironment;
  initVal, retVal: TFloriaJSValue;
  initNode: TFloriaJSASTNode;
  i, count: Integer;
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
    Result := JSMakeUndefined();
    count := blockStmt.GetStatementCount();
    for i := 0 to count - 1 do
      Result := ExecuteStmt(blockStmt.GetStatement(i), blockEnv);
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
    Exit;
  end;

  // 7. Return Statement
  if AStmt is TFloriaJSReturnStmt then
  begin
    retStmt := TFloriaJSReturnStmt(AStmt);
    if retStmt.Argument <> nil then
      retVal := EvaluateExpr(retStmt.Argument, AEnv)
    else
      retVal := JSMakeUndefined();

    raise EFloriaJSReturn.Create(retVal);
  end;

  // 8. Break Statement
  if AStmt is TFloriaJSBreakStmt then
    raise EFloriaJSBreak.Create('');

  // 9. Continue Statement
  if AStmt is TFloriaJSContinueStmt then
    raise EFloriaJSContinue.Create('');

  // 10. Function Declaration
  if AStmt is TFloriaJSFunctionDecl then
  begin
    fnDecl := TFloriaJSFunctionDecl(AStmt);
    fnObj := FHeap.NewUserFunction(fnDecl.Name, fnDecl.Parameters, fnDecl.Body, Pointer(AEnv));
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

  count := AProg.GetStatementCount();
  for i := 0 to count - 1 do
    Result := ExecuteStmt(AProg.GetStatement(i), AEnv);
end;

function TFloriaJSEvaluator.CallFunction(const AFuncVal: TFloriaJSValue; const AArgs: array of TFloriaJSValue; const AThis: TFloriaJSValue): TFloriaJSValue;
var
  fn: TFloriaJSFunction;
  callEnv: TFloriaJSEnvironment;
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

    try
      if fn.Body <> nil then
        ExecuteStmt(fn.Body, callEnv);
      Result := JSMakeUndefined();
    except
      on E: EFloriaJSReturn do
        Result := E.Value;
    end;
  finally
    Dec(FCurrentCallDepth);
  end;
end;

end.
