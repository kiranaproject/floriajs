{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Bytecode Compiler                               }
{                                                                          }
{   Compiles Abstract Syntax Tree (AST) programs, statements, and          }
{   expressions into flat bytecode chunks for the VM execution engine.     }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.compiler;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, floria.js.types, floria.js.lexer, floria.js.ast,
  floria.js.value, floria.js.bytecode;

type
  { Loop and Label Jump Tracking Context }
  TFloriaJSLoopContext = record
    LabelName: string;
    ContinueTarget: Integer;
    BreakJumps: array of Integer;
    ContinueJumps: array of Integer;
  end;

  { Bytecode Compiler }
  TFloriaJSCompiler = class
  private
    FBytecode: TFloriaJSBytecode;
    FIsTopLevel: Boolean;
    FResultLoc: Integer;
    FLoopStack: array of TFloriaJSLoopContext;
    FLoopDepth: Integer;
    FLoopCapacity: Integer;

    procedure PushLoopContext(const ALabel: string = '');
    procedure PopLoopContext(ABreakTarget: Integer);
    procedure AddBreakJump(AJumpIdx: Integer; const ALabel: string = '');
    procedure AddContinueJump(AJumpIdx: Integer; const ALabel: string = '');

    procedure CompileStmt(AStmt: TFloriaJSStmtNode);
    procedure CompileExpr(AExpr: TFloriaJSExprNode);

    procedure CompileLiteralExpr(ALit: TFloriaJSLiteralExpr);
    procedure CompileIdentifierExpr(AIdent: TFloriaJSIdentifierExpr);
    procedure CompileUnaryExpr(AUnary: TFloriaJSUnaryExpr);
    procedure CompileBinaryExpr(ABin: TFloriaJSBinaryExpr);
    procedure CompileAssignExpr(AAssign: TFloriaJSAssignExpr);
    procedure CompileConditionalExpr(ACond: TFloriaJSConditionalExpr);
    procedure CompileMemberExpr(AMember: TFloriaJSMemberExpr);
    procedure CompileCallExpr(ACall: TFloriaJSCallExpr);
    procedure CompileObjectExpr(AObj: TFloriaJSObjectExpr);
    procedure CompileArrayExpr(AArr: TFloriaJSArrayExpr);
    procedure CompileFunctionExpr(AFunc: TFloriaJSFunctionExpr);

    procedure CompileVarStmt(AVar: TFloriaJSVarStmt);
    procedure CompileBlockStmt(ABlock: TFloriaJSBlockStmt);
    procedure CompileIfStmt(AIf: TFloriaJSIfStmt);
    procedure CompileWhileStmt(AWhile: TFloriaJSWhileStmt);
    procedure CompileForStmt(AFor: TFloriaJSForStmt);
    procedure CompileForInOfStmt(AForInOf: TFloriaJSForInOfStmt);
    procedure CompileSwitchStmt(ASwitch: TFloriaJSSwitchStmt);
    procedure CompileLabeledStmt(ALabeled: TFloriaJSLabeledStmt);
    procedure CompileReturnStmt(ARet: TFloriaJSReturnStmt);
    procedure CompileTryStmt(ATry: TFloriaJSTryStmt);
    procedure CompileThrowStmt(AThrow: TFloriaJSThrowStmt);
    procedure CompileBreakStmt(ABreak: TFloriaJSBreakStmt);
    procedure CompileContinueStmt(AContinue: TFloriaJSContinueStmt);
    procedure CompileFunctionDecl(AFuncDecl: TFloriaJSFunctionDecl);
  public
    constructor Create();
    destructor Destroy(); override;

    function CompileProgram(AProgram: TFloriaJSProgram): TFloriaJSBytecode;
    function CompileExpression(AExpr: TFloriaJSExprNode): TFloriaJSBytecode;
  end;

implementation

{ TFloriaJSCompiler }

constructor TFloriaJSCompiler.Create();
begin
  inherited Create();
  FBytecode := nil;
  FLoopDepth := 0;
  FLoopCapacity := 16;
  SetLength(FLoopStack, FLoopCapacity);
end;

destructor TFloriaJSCompiler.Destroy();
begin
  SetLength(FLoopStack, 0);
  inherited Destroy();
end;

procedure TFloriaJSCompiler.PushLoopContext(const ALabel: string);
begin
  if FLoopDepth >= FLoopCapacity then
  begin
    FLoopCapacity := FLoopCapacity * 2;
    SetLength(FLoopStack, FLoopCapacity);
  end;

  FLoopStack[FLoopDepth].LabelName := ALabel;
  FLoopStack[FLoopDepth].ContinueTarget := -1;
  SetLength(FLoopStack[FLoopDepth].BreakJumps, 0);
  SetLength(FLoopStack[FLoopDepth].ContinueJumps, 0);
  Inc(FLoopDepth);
end;

procedure TFloriaJSCompiler.PopLoopContext(ABreakTarget: Integer);
var
  i: Integer;
begin
  if FLoopDepth <= 0 then Exit;
  Dec(FLoopDepth);

  // Patch all break jumps from this loop
  for i := 0 to High(FLoopStack[FLoopDepth].BreakJumps) do
    FBytecode.PatchJump(FLoopStack[FLoopDepth].BreakJumps[i], ABreakTarget);

  SetLength(FLoopStack[FLoopDepth].BreakJumps, 0);
  SetLength(FLoopStack[FLoopDepth].ContinueJumps, 0);
end;

procedure TFloriaJSCompiler.AddBreakJump(AJumpIdx: Integer; const ALabel: string);
var
  i, targetDepth: Integer;
begin
  targetDepth := -1;
  if ALabel <> '' then
  begin
    for i := FLoopDepth - 1 downto 0 do
      if FLoopStack[i].LabelName = ALabel then
      begin
        targetDepth := i;
        Break;
      end;
  end
  else if FLoopDepth > 0 then
    targetDepth := FLoopDepth - 1;

  if targetDepth >= 0 then
  begin
    SetLength(FLoopStack[targetDepth].BreakJumps, Length(FLoopStack[targetDepth].BreakJumps) + 1);
    FLoopStack[targetDepth].BreakJumps[High(FLoopStack[targetDepth].BreakJumps)] := AJumpIdx;
  end;
end;

procedure TFloriaJSCompiler.AddContinueJump(AJumpIdx: Integer; const ALabel: string);
var
  i, targetDepth: Integer;
begin
  targetDepth := -1;
  if ALabel <> '' then
  begin
    for i := FLoopDepth - 1 downto 0 do
      if FLoopStack[i].LabelName = ALabel then
      begin
        targetDepth := i;
        Break;
      end;
  end
  else if FLoopDepth > 0 then
    targetDepth := FLoopDepth - 1;

  if targetDepth >= 0 then
  begin
    if FLoopStack[targetDepth].ContinueTarget >= 0 then
      FBytecode.PatchJump(AJumpIdx, FLoopStack[targetDepth].ContinueTarget)
    else
    begin
      SetLength(FLoopStack[targetDepth].ContinueJumps, Length(FLoopStack[targetDepth].ContinueJumps) + 1);
      FLoopStack[targetDepth].ContinueJumps[High(FLoopStack[targetDepth].ContinueJumps)] := AJumpIdx;
    end;
  end;
end;

function TFloriaJSCompiler.CompileProgram(AProgram: TFloriaJSProgram): TFloriaJSBytecode;
var
  i, count: Integer;
begin
  FIsTopLevel := True;
  FBytecode := TFloriaJSBytecode.Create('main');
  Result := FBytecode;
  FResultLoc := FBytecode.AddLocal('$result');

  if AProgram = nil then
  begin
    FBytecode.Emit(opUndefined);
    FBytecode.Emit(opReturn);
    Exit;
  end;

  count := AProgram.GetStatementCount();
  for i := 0 to count - 1 do
    CompileStmt(AProgram.GetStatement(i));

  FBytecode.Emit(opLoadLoc, FResultLoc);
  FBytecode.Emit(opReturn);
end;

function TFloriaJSCompiler.CompileExpression(AExpr: TFloriaJSExprNode): TFloriaJSBytecode;
begin
  FIsTopLevel := False;
  FResultLoc := -1;
  FBytecode := TFloriaJSBytecode.Create('expr');
  Result := FBytecode;

  if AExpr <> nil then
    CompileExpr(AExpr)
  else
    FBytecode.Emit(opUndefined);

  FBytecode.Emit(opReturn);
end;

procedure TFloriaJSCompiler.CompileStmt(AStmt: TFloriaJSStmtNode);
var
  exprStmt: TFloriaJSExprStmt;
begin
  if AStmt = nil then Exit;

  if AStmt is TFloriaJSExprStmt then
  begin
    exprStmt := TFloriaJSExprStmt(AStmt);
    CompileExpr(exprStmt.Expression);
    if FIsTopLevel then
      FBytecode.Emit(opSetLoc, FResultLoc)
    else
      FBytecode.Emit(opPop);
  end
  else if AStmt is TFloriaJSVarStmt then
    CompileVarStmt(TFloriaJSVarStmt(AStmt))
  else if AStmt is TFloriaJSBlockStmt then
    CompileBlockStmt(TFloriaJSBlockStmt(AStmt))
  else if AStmt is TFloriaJSIfStmt then
    CompileIfStmt(TFloriaJSIfStmt(AStmt))
  else if AStmt is TFloriaJSWhileStmt then
    CompileWhileStmt(TFloriaJSWhileStmt(AStmt))
  else if AStmt is TFloriaJSForStmt then
    CompileForStmt(TFloriaJSForStmt(AStmt))
  else if AStmt is TFloriaJSForInOfStmt then
    CompileForInOfStmt(TFloriaJSForInOfStmt(AStmt))
  else if AStmt is TFloriaJSSwitchStmt then
    CompileSwitchStmt(TFloriaJSSwitchStmt(AStmt))
  else if AStmt is TFloriaJSLabeledStmt then
    CompileLabeledStmt(TFloriaJSLabeledStmt(AStmt))
  else if AStmt is TFloriaJSReturnStmt then
    CompileReturnStmt(TFloriaJSReturnStmt(AStmt))
  else if AStmt is TFloriaJSTryStmt then
    CompileTryStmt(TFloriaJSTryStmt(AStmt))
  else if AStmt is TFloriaJSThrowStmt then
    CompileThrowStmt(TFloriaJSThrowStmt(AStmt))
  else if AStmt is TFloriaJSBreakStmt then
    CompileBreakStmt(TFloriaJSBreakStmt(AStmt))
  else if AStmt is TFloriaJSContinueStmt then
    CompileContinueStmt(TFloriaJSContinueStmt(AStmt))
  else if AStmt is TFloriaJSFunctionDecl then
    CompileFunctionDecl(TFloriaJSFunctionDecl(AStmt));
end;

procedure TFloriaJSCompiler.CompileExpr(AExpr: TFloriaJSExprNode);
begin
  if AExpr = nil then
  begin
    FBytecode.Emit(opUndefined);
    Exit;
  end;

  if AExpr is TFloriaJSLiteralExpr then
    CompileLiteralExpr(TFloriaJSLiteralExpr(AExpr))
  else if AExpr is TFloriaJSIdentifierExpr then
    CompileIdentifierExpr(TFloriaJSIdentifierExpr(AExpr))
  else if AExpr is TFloriaJSUnaryExpr then
    CompileUnaryExpr(TFloriaJSUnaryExpr(AExpr))
  else if AExpr is TFloriaJSBinaryExpr then
    CompileBinaryExpr(TFloriaJSBinaryExpr(AExpr))
  else if AExpr is TFloriaJSAssignExpr then
    CompileAssignExpr(TFloriaJSAssignExpr(AExpr))
  else if AExpr is TFloriaJSConditionalExpr then
    CompileConditionalExpr(TFloriaJSConditionalExpr(AExpr))
  else if AExpr is TFloriaJSMemberExpr then
    CompileMemberExpr(TFloriaJSMemberExpr(AExpr))
  else if AExpr is TFloriaJSCallExpr then
    CompileCallExpr(TFloriaJSCallExpr(AExpr))
  else if AExpr is TFloriaJSObjectExpr then
    CompileObjectExpr(TFloriaJSObjectExpr(AExpr))
  else if AExpr is TFloriaJSArrayExpr then
    CompileArrayExpr(TFloriaJSArrayExpr(AExpr))
  else if AExpr is TFloriaJSFunctionExpr then
    CompileFunctionExpr(TFloriaJSFunctionExpr(AExpr))
  else
    FBytecode.Emit(opUndefined);
end;

procedure TFloriaJSCompiler.CompileLiteralExpr(ALit: TFloriaJSLiteralExpr);
begin
  case ALit.ValueType of
    fjstNull:
      FBytecode.Emit(opNull, 0, ALit.Line);
    fjstUndefined:
      FBytecode.Emit(opUndefined, 0, ALit.Line);
    fjstBoolean:
      begin
        if ALit.BoolVal then
          FBytecode.Emit(opTrue, 0, ALit.Line)
        else
          FBytecode.Emit(opFalse, 0, ALit.Line);
      end;
    fjstNumber:
      begin
        if ALit.NumberVal = 0.0 then
          FBytecode.Emit(opZero, 0, ALit.Line)
        else if ALit.NumberVal = 1.0 then
          FBytecode.Emit(opOne, 0, ALit.Line)
        else
          FBytecode.Emit(opConst, FBytecode.AddNumberConstant(ALit.NumberVal), ALit.Line);
      end;
    fjstString:
      FBytecode.Emit(opConst, FBytecode.AddStringConstant(ALit.StringVal), ALit.Line);
  end;
end;

procedure TFloriaJSCompiler.CompileIdentifierExpr(AIdent: TFloriaJSIdentifierExpr);
var
  locIdx: Integer;
begin
  if AIdent.Name = 'undefined' then
    FBytecode.Emit(opUndefined, 0, AIdent.Line)
  else if AIdent.Name = 'NaN' then
    FBytecode.Emit(opConst, FBytecode.AddConstant(JSMakeNumber(NaN)), AIdent.Line)
  else if AIdent.Name = 'Infinity' then
    FBytecode.Emit(opConst, FBytecode.AddConstant(JSMakeNumber(Infinity)), AIdent.Line)
  else
  begin
    locIdx := FBytecode.FindLocal(AIdent.Name);

    if locIdx >= 0 then
      FBytecode.Emit(opLoadLoc, locIdx, AIdent.Line)
    else
      FBytecode.Emit(opLoadEnv, FBytecode.AddStringConstant(AIdent.Name), AIdent.Line);
  end;
end;

procedure TFloriaJSCompiler.CompileUnaryExpr(AUnary: TFloriaJSUnaryExpr);
var
  member: TFloriaJSMemberExpr;
begin
  case AUnary.Op of
    tkMinus:
      begin
        CompileExpr(AUnary.Operand);
        FBytecode.Emit(opNeg, 0, AUnary.Line);
      end;
    tkPlus:
      begin
        CompileExpr(AUnary.Operand);
        FBytecode.Emit(opPos, 0, AUnary.Line);
      end;
    tkNot:
      begin
        CompileExpr(AUnary.Operand);
        FBytecode.Emit(opNot, 0, AUnary.Line);
      end;
    tkBitNot:
      begin
        CompileExpr(AUnary.Operand);
        FBytecode.Emit(opBitNot, 0, AUnary.Line);
      end;
    tkTypeof:
      begin
        CompileExpr(AUnary.Operand);
        FBytecode.Emit(opTypeOf, 0, AUnary.Line);
      end;
    tkDelete:
      begin
        if AUnary.Operand is TFloriaJSMemberExpr then
        begin
          member := TFloriaJSMemberExpr(AUnary.Operand);
          CompileExpr(member.Target);
          if member.Computed then
            CompileExpr(member.PropertyExpr)
          else
            FBytecode.Emit(opConst, FBytecode.AddStringConstant(member.PropertyName));
          FBytecode.Emit(opDeleteProp, 0, AUnary.Line);
        end
        else
        begin
          CompileExpr(AUnary.Operand);
          FBytecode.Emit(opPop);
          FBytecode.Emit(opTrue, 0, AUnary.Line);
        end;
      end;
  else
    CompileExpr(AUnary.Operand);
  end;
end;

procedure TFloriaJSCompiler.CompileBinaryExpr(ABin: TFloriaJSBinaryExpr);
var
  jumpIdx: Integer;
begin
  // Short-circuit logicals
  if ABin.Op = tkAnd then
  begin
    CompileExpr(ABin.Left);
    jumpIdx := FBytecode.Emit(opJumpIfFalseyPeek, 0, ABin.Line);
    CompileExpr(ABin.Right);
    FBytecode.PatchJump(jumpIdx, FBytecode.CurrentIP());
    Exit;
  end;

  if ABin.Op = tkOr then
  begin
    CompileExpr(ABin.Left);
    jumpIdx := FBytecode.Emit(opJumpIfTruthyPeek, 0, ABin.Line);
    CompileExpr(ABin.Right);
    FBytecode.PatchJump(jumpIdx, FBytecode.CurrentIP());
    Exit;
  end;

  if ABin.Op = tkNullish then
  begin
    CompileExpr(ABin.Left);
    jumpIdx := FBytecode.Emit(opJumpIfNullish, 0, ABin.Line);
    CompileExpr(ABin.Right);
    FBytecode.PatchJump(jumpIdx, FBytecode.CurrentIP());
    Exit;
  end;

  if ABin.Op = tkComma then
  begin
    CompileExpr(ABin.Left);
    FBytecode.Emit(opPop);
    CompileExpr(ABin.Right);
    Exit;
  end;

  // Standard binary operators
  CompileExpr(ABin.Left);
  CompileExpr(ABin.Right);

  case ABin.Op of
    tkPlus:               FBytecode.Emit(opAdd, 0, ABin.Line);
    tkMinus:              FBytecode.Emit(opSub, 0, ABin.Line);
    tkMultiply:           FBytecode.Emit(opMul, 0, ABin.Line);
    tkDivide:             FBytecode.Emit(opDiv, 0, ABin.Line);
    tkModulo:             FBytecode.Emit(opMod, 0, ABin.Line);
    tkPower:              FBytecode.Emit(opPower, 0, ABin.Line);
    tkEqual:              FBytecode.Emit(opEq, 0, ABin.Line);
    tkStrictEqual:        FBytecode.Emit(opStrictEq, 0, ABin.Line);
    tkNotEqual:           FBytecode.Emit(opNotEq, 0, ABin.Line);
    tkStrictNotEqual:     FBytecode.Emit(opStrictNotEq, 0, ABin.Line);
    tkLessThan:           FBytecode.Emit(opLt, 0, ABin.Line);
    tkLessEqual:          FBytecode.Emit(opLe, 0, ABin.Line);
    tkGreaterThan:        FBytecode.Emit(opGt, 0, ABin.Line);
    tkGreaterEqual:       FBytecode.Emit(opGe, 0, ABin.Line);
    tkIn:                 FBytecode.Emit(opIn, 0, ABin.Line);
    tkInstanceof:         FBytecode.Emit(opInstanceOf, 0, ABin.Line);
    tkBitAnd:             FBytecode.Emit(opBitAnd, 0, ABin.Line);
    tkBitOr:              FBytecode.Emit(opBitOr, 0, ABin.Line);
    tkBitXor:             FBytecode.Emit(opBitXor, 0, ABin.Line);
    tkShiftLeft:          FBytecode.Emit(opShl, 0, ABin.Line);
    tkShiftRight:         FBytecode.Emit(opShr, 0, ABin.Line);
    tkShiftRightUnsigned: FBytecode.Emit(opSar, 0, ABin.Line);
  end;
end;

procedure TFloriaJSCompiler.CompileAssignExpr(AAssign: TFloriaJSAssignExpr);
var
  ident: TFloriaJSIdentifierExpr;
  member: TFloriaJSMemberExpr;
  locIdx: Integer;
begin
  if AAssign.Target is TFloriaJSIdentifierExpr then
  begin
    ident := TFloriaJSIdentifierExpr(AAssign.Target);
    locIdx := FBytecode.FindLocal(ident.Name);

    // If compound assignment (e.g. +=), load original value first
    if AAssign.Op <> tkAssign then
    begin
      if locIdx >= 0 then
        FBytecode.Emit(opLoadLoc, locIdx)
      else
        FBytecode.Emit(opLoadEnv, FBytecode.AddStringConstant(ident.Name));

      CompileExpr(AAssign.Value);
      case AAssign.Op of
        tkPlusAssign:     FBytecode.Emit(opAdd);
        tkMinusAssign:    FBytecode.Emit(opSub);
        tkMultiplyAssign: FBytecode.Emit(opMul);
        tkDivideAssign:   FBytecode.Emit(opDiv);
        tkModuloAssign:   FBytecode.Emit(opMod);
        tkPowerAssign:    FBytecode.Emit(opPower);
      end;
    end
    else
      CompileExpr(AAssign.Value);

    if locIdx >= 0 then
      FBytecode.Emit(opStoreLoc, locIdx, AAssign.Line)
    else
      FBytecode.Emit(opStoreEnv, FBytecode.AddStringConstant(ident.Name), AAssign.Line);
  end
  else if AAssign.Target is TFloriaJSMemberExpr then
  begin
    member := TFloriaJSMemberExpr(AAssign.Target);
    CompileExpr(member.Target);

    if member.Computed then
    begin
      CompileExpr(member.PropertyExpr);
      CompileExpr(AAssign.Value);
      FBytecode.Emit(opSetProp, 0, AAssign.Line);
    end
    else
    begin
      CompileExpr(AAssign.Value);
      FBytecode.Emit(opSetPropNamed, FBytecode.AddStringConstant(member.PropertyName), AAssign.Line);
    end;
  end;
end;

procedure TFloriaJSCompiler.CompileConditionalExpr(ACond: TFloriaJSConditionalExpr);
var
  elseJump, endJump: Integer;
begin
  CompileExpr(ACond.Condition);
  elseJump := FBytecode.Emit(opJumpIfFalse, 0, ACond.Line);

  CompileExpr(ACond.Consequent);
  endJump := FBytecode.Emit(opJump, 0);

  FBytecode.PatchJump(elseJump, FBytecode.CurrentIP());
  CompileExpr(ACond.Alternate);
  FBytecode.PatchJump(endJump, FBytecode.CurrentIP());
end;

procedure TFloriaJSCompiler.CompileMemberExpr(AMember: TFloriaJSMemberExpr);
begin
  CompileExpr(AMember.Target);

  if AMember.IsOptional then
  begin
    if AMember.Computed then
    begin
      CompileExpr(AMember.PropertyExpr);
      FBytecode.Emit(opGetPropOptional, 0, AMember.Line);
    end
    else
      FBytecode.Emit(opGetPropNamedOpt, FBytecode.AddStringConstant(AMember.PropertyName), AMember.Line);
  end
  else
  begin
    if AMember.Computed then
    begin
      CompileExpr(AMember.PropertyExpr);
      FBytecode.Emit(opGetProp, 0, AMember.Line);
    end
    else
      FBytecode.Emit(opGetPropNamed, FBytecode.AddStringConstant(AMember.PropertyName), AMember.Line);
  end;
end;

procedure TFloriaJSCompiler.CompileCallExpr(ACall: TFloriaJSCallExpr);
var
  member: TFloriaJSMemberExpr;
  i, count: Integer;
begin
  count := ACall.GetArgumentCount();

  if not ACall.IsNew and (ACall.Callee is TFloriaJSMemberExpr) then
  begin
    member := TFloriaJSMemberExpr(ACall.Callee);
    CompileExpr(member.Target); // Stack: [Target]
    FBytecode.Emit(opDup);      // Stack: [Target, Target]

    if member.Computed then
    begin
      CompileExpr(member.PropertyExpr);
      FBytecode.Emit(opGetProp);
    end
    else
      FBytecode.Emit(opGetPropNamed, FBytecode.AddStringConstant(member.PropertyName));

    // Stack: [Target, Method] -> Swap to [Method, Target (this)]
    FBytecode.Emit(opSwap);
  end
  else
  begin
    CompileExpr(ACall.Callee);
    FBytecode.Emit(opUndefined); // This value
  end;

  // Push arguments
  for i := 0 to count - 1 do
    CompileExpr(ACall.GetArgument(i));

  if ACall.IsNew then
    FBytecode.Emit(opNew, count, ACall.Line)
  else if ACall.IsOptional then
    FBytecode.Emit(opCallOpt, count, ACall.Line)
  else
    FBytecode.Emit(opCall, count, ACall.Line);
end;

procedure TFloriaJSCompiler.CompileObjectExpr(AObj: TFloriaJSObjectExpr);
var
  i, count: Integer;
  propName: string;
begin
  FBytecode.Emit(opNewObject, 0, AObj.Line);
  count := AObj.GetPropertyCount();

  for i := 0 to count - 1 do
  begin
    propName := AObj.GetPropertyKey(i);
    FBytecode.Emit(opDup); // Duplicate object reference
    CompileExpr(AObj.GetPropertyValue(i));
    FBytecode.Emit(opSetPropNamed, FBytecode.AddStringConstant(propName));
    FBytecode.Emit(opPop); // Pop assigned value, keeping object on stack
  end;
end;

procedure TFloriaJSCompiler.CompileArrayExpr(AArr: TFloriaJSArrayExpr);
var
  i, count: Integer;
begin
  count := AArr.GetElementCount();
  for i := 0 to count - 1 do
    CompileExpr(AArr.GetElement(i));

  FBytecode.Emit(opNewArray, count, AArr.Line);
end;

procedure TFloriaJSCompiler.CompileFunctionExpr(AFunc: TFloriaJSFunctionExpr);
var
  compiler: TFloriaJSCompiler;
  subCode: TFloriaJSBytecode;
  fnIdx, i: Integer;
begin
  compiler := TFloriaJSCompiler.Create();
  try
    subCode := TFloriaJSBytecode.Create(AFunc.Name);
    subCode.IsArrow := AFunc.IsArrow;

    // Add arguments as first locals
    if AFunc.Parameters <> nil then
      for i := 0 to AFunc.Parameters.Count - 1 do
        subCode.AddArgument(AFunc.Parameters[i]);

    compiler.FBytecode := subCode;
    compiler.FIsTopLevel := False;
    compiler.FResultLoc := -1;
    if AFunc.Body is TFloriaJSBlockStmt then
      compiler.CompileBlockStmt(TFloriaJSBlockStmt(AFunc.Body))
    else
      compiler.CompileStmt(AFunc.Body);

    subCode.Emit(opUndefined);
    subCode.Emit(opReturn);

    fnIdx := FBytecode.AddSubFunction(subCode);
    FBytecode.Emit(opClosure, fnIdx, AFunc.Line);
  finally
    compiler.Free();
  end;
end;

procedure TFloriaJSCompiler.CompileVarStmt(AVar: TFloriaJSVarStmt);
var
  i, count, locIdx, nameIdx: Integer;
  declName: string;
  declInit: TFloriaJSExprNode;
begin
  count := AVar.GetDeclaratorCount();
  for i := 0 to count - 1 do
  begin
    declName := AVar.GetDeclaratorName(i);
    declInit := AVar.GetDeclaratorInit(i);

    if declInit <> nil then
      CompileExpr(declInit)
    else
      FBytecode.Emit(opUndefined);

    if FIsTopLevel then
    begin
      nameIdx := FBytecode.AddStringConstant(declName);
      FBytecode.Emit(opDefineEnv, nameIdx, AVar.Line);
    end
    else
    begin
      locIdx := FBytecode.AddLocal(declName);
      FBytecode.Emit(opSetLoc, locIdx, AVar.Line);
    end;
  end;
end;

procedure TFloriaJSCompiler.CompileBlockStmt(ABlock: TFloriaJSBlockStmt);
var
  i, count: Integer;
begin
  count := ABlock.GetStatementCount();
  for i := 0 to count - 1 do
    CompileStmt(ABlock.GetStatement(i));
end;

procedure TFloriaJSCompiler.CompileIfStmt(AIf: TFloriaJSIfStmt);
var
  elseJump, endJump: Integer;
begin
  CompileExpr(AIf.Condition);
  elseJump := FBytecode.Emit(opJumpIfFalse, 0, AIf.Line);

  CompileStmt(AIf.Consequent);

  if AIf.Alternate <> nil then
  begin
    endJump := FBytecode.Emit(opJump, 0);
    FBytecode.PatchJump(elseJump, FBytecode.CurrentIP());
    CompileStmt(AIf.Alternate);
    FBytecode.PatchJump(endJump, FBytecode.CurrentIP());
  end
  else
    FBytecode.PatchJump(elseJump, FBytecode.CurrentIP());
end;

procedure TFloriaJSCompiler.CompileWhileStmt(AWhile: TFloriaJSWhileStmt);
var
  loopStart, exitJump: Integer;
begin
  loopStart := FBytecode.CurrentIP();
  PushLoopContext();
  FLoopStack[FLoopDepth - 1].ContinueTarget := loopStart;

  CompileExpr(AWhile.Condition);
  exitJump := FBytecode.Emit(opJumpIfFalse, 0, AWhile.Line);
  AddBreakJump(exitJump);

  CompileStmt(AWhile.Body);
  FBytecode.Emit(opJump, loopStart);

  PopLoopContext(FBytecode.CurrentIP());
end;

procedure TFloriaJSCompiler.CompileForStmt(AFor: TFloriaJSForStmt);
var
  loopStart, exitJump, contTarget: Integer;
begin
  if AFor.Init <> nil then
  begin
    if AFor.Init is TFloriaJSStmtNode then
      CompileStmt(TFloriaJSStmtNode(AFor.Init))
    else if AFor.Init is TFloriaJSExprNode then
    begin
      CompileExpr(TFloriaJSExprNode(AFor.Init));
      FBytecode.Emit(opPop);
    end;
  end;

  loopStart := FBytecode.CurrentIP();
  PushLoopContext(AFor.LabelName);

  if AFor.Test <> nil then
  begin
    CompileExpr(AFor.Test);
    exitJump := FBytecode.Emit(opJumpIfFalse, 0, AFor.Line);
    AddBreakJump(exitJump, AFor.LabelName);
  end;

  CompileStmt(AFor.Body);

  contTarget := FBytecode.CurrentIP();
  FLoopStack[FLoopDepth - 1].ContinueTarget := contTarget;

  if AFor.Update <> nil then
  begin
    CompileExpr(AFor.Update);
    FBytecode.Emit(opPop);
  end;

  FBytecode.Emit(opJump, loopStart);
  PopLoopContext(FBytecode.CurrentIP());
end;

procedure TFloriaJSCompiler.CompileForInOfStmt(AForInOf: TFloriaJSForInOfStmt);
var
  iterLoc, idxLoc, lenLoc, varLoc, nameIdx: Integer;
  loopStart, exitJump, contTarget: Integer;
begin
  iterLoc := FBytecode.AddLocal('$iter');
  idxLoc := FBytecode.AddLocal('$idx');
  lenLoc := FBytecode.AddLocal('$len');

  // Evaluate iterable
  CompileExpr(AForInOf.Iterable);
  if AForInOf.IsOf then
    FBytecode.Emit(opForOfInit)
  else
    FBytecode.Emit(opForInInit);

  FBytecode.Emit(opSetLoc, iterLoc);

  // Initialize index to 0
  FBytecode.Emit(opZero);
  FBytecode.Emit(opSetLoc, idxLoc);

  // Get length
  FBytecode.Emit(opLoadLoc, iterLoc);
  FBytecode.Emit(opGetPropNamed, FBytecode.AddStringConstant('length'));
  FBytecode.Emit(opSetLoc, lenLoc);

  // Loop test: idx < len
  loopStart := FBytecode.CurrentIP();
  PushLoopContext(AForInOf.LabelName);

  FBytecode.Emit(opLoadLoc, idxLoc);
  FBytecode.Emit(opLoadLoc, lenLoc);
  FBytecode.Emit(opLt);
  exitJump := FBytecode.Emit(opJumpIfFalse, 0);
  AddBreakJump(exitJump, AForInOf.LabelName);

  // Fetch current element/key: iter[idx]
  FBytecode.Emit(opLoadLoc, iterLoc);
  FBytecode.Emit(opLoadLoc, idxLoc);
  FBytecode.Emit(opGetProp);

  // Bind to loop variable
  if FIsTopLevel and (AForInOf.VarKind = tkVar) then
  begin
    nameIdx := FBytecode.AddStringConstant(AForInOf.VarName);
    FBytecode.Emit(opDefineEnv, nameIdx);
  end
  else
  begin
    varLoc := FBytecode.FindLocal(AForInOf.VarName);
    if (varLoc < 0) and (AForInOf.VarKind in [tkLet, tkConst, tkVar]) then
      varLoc := FBytecode.AddLocal(AForInOf.VarName);

    if varLoc >= 0 then
      FBytecode.Emit(opSetLoc, varLoc)
    else
    begin
      nameIdx := FBytecode.AddStringConstant(AForInOf.VarName);
      FBytecode.Emit(opStoreEnv, nameIdx);
      FBytecode.Emit(opPop);
    end;
  end;

  // Compile body
  CompileStmt(AForInOf.Body);

  // Continue target: increment idx
  contTarget := FBytecode.CurrentIP();
  FLoopStack[FLoopDepth - 1].ContinueTarget := contTarget;

  FBytecode.Emit(opLoadLoc, idxLoc);
  FBytecode.Emit(opOne);
  FBytecode.Emit(opAdd);
  FBytecode.Emit(opSetLoc, idxLoc);

  FBytecode.Emit(opJump, loopStart);
  PopLoopContext(FBytecode.CurrentIP());
end;

procedure TFloriaJSCompiler.CompileSwitchStmt(ASwitch: TFloriaJSSwitchStmt);
var
  discLoc, i, s, count, defaultIdx, defaultJump, endJump, clauseIP, endIP: Integer;
  testJumps: array of Integer;
  caseClause: TFloriaJSSwitchCase;
begin
  count := ASwitch.GetCaseCount();
  SetLength(testJumps, count);
  defaultIdx := -1;
  defaultJump := -1;
  endJump := -1;

  discLoc := FBytecode.AddLocal('$disc');
  CompileExpr(ASwitch.Discriminant);
  FBytecode.Emit(opSetLoc, discLoc);

  PushLoopContext(); // For unlabelled break

  // Test clauses
  for i := 0 to count - 1 do
  begin
    caseClause := ASwitch.GetCase(i);
    if not caseClause.IsDefault then
    begin
      FBytecode.Emit(opLoadLoc, discLoc);
      CompileExpr(caseClause.Test);
      FBytecode.Emit(opStrictEq);
      testJumps[i] := FBytecode.Emit(opJumpIfTrue, 0);
    end
    else
    begin
      defaultIdx := i;
      testJumps[i] := -1;
    end;
  end;

  // Jump to default clause or end
  if defaultIdx >= 0 then
    defaultJump := FBytecode.Emit(opJump, 0)
  else
    endJump := FBytecode.Emit(opJump, 0);

  // Emit case bodies in order
  for i := 0 to count - 1 do
  begin
    caseClause := ASwitch.GetCase(i);
    clauseIP := FBytecode.CurrentIP();
    if not caseClause.IsDefault then
      FBytecode.PatchJump(testJumps[i], clauseIP)
    else
      FBytecode.PatchJump(defaultJump, clauseIP);

    for s := 0 to caseClause.GetStatementCount() - 1 do
      CompileStmt(caseClause.GetStatement(s));
  end;

  endIP := FBytecode.CurrentIP();
  if defaultIdx < 0 then
    FBytecode.PatchJump(endJump, endIP);

  PopLoopContext(endIP);
end;

procedure TFloriaJSCompiler.CompileLabeledStmt(ALabeled: TFloriaJSLabeledStmt);
begin
  PushLoopContext(ALabeled.LabelName);
  CompileStmt(ALabeled.Body);
  PopLoopContext(FBytecode.CurrentIP());
end;

procedure TFloriaJSCompiler.CompileReturnStmt(ARet: TFloriaJSReturnStmt);
begin
  if ARet.Argument <> nil then
    CompileExpr(ARet.Argument)
  else
    FBytecode.Emit(opUndefined);

  FBytecode.Emit(opReturn, 0, ARet.Line);
end;

procedure TFloriaJSCompiler.CompileTryStmt(ATry: TFloriaJSTryStmt);
var
  tryIdx, endJump, catchVarIdx: Integer;
begin
  tryIdx := FBytecode.Emit(opPushTry, 0, ATry.Line);
  CompileStmt(ATry.Block);
  FBytecode.Emit(opPopTry);
  endJump := FBytecode.Emit(opJump, 0);

  FBytecode.PatchJump(tryIdx, FBytecode.CurrentIP());
  if ATry.CatchParam <> '' then
  begin
    catchVarIdx := FBytecode.AddLocal(ATry.CatchParam);
    FBytecode.Emit(opSetLoc, catchVarIdx);
  end
  else
    FBytecode.Emit(opPop);

  if ATry.CatchBlock <> nil then
    CompileStmt(ATry.CatchBlock);

  FBytecode.PatchJump(endJump, FBytecode.CurrentIP());

  if ATry.FinallyBlock <> nil then
    CompileStmt(ATry.FinallyBlock);
end;

procedure TFloriaJSCompiler.CompileThrowStmt(AThrow: TFloriaJSThrowStmt);
begin
  CompileExpr(AThrow.Expression);
  FBytecode.Emit(opThrow, 0, AThrow.Line);
end;

procedure TFloriaJSCompiler.CompileBreakStmt(ABreak: TFloriaJSBreakStmt);
var
  jumpIdx: Integer;
begin
  jumpIdx := FBytecode.Emit(opJump, 0, ABreak.Line);
  AddBreakJump(jumpIdx, ABreak.LabelName);
end;

procedure TFloriaJSCompiler.CompileContinueStmt(AContinue: TFloriaJSContinueStmt);
var
  jumpIdx: Integer;
begin
  jumpIdx := FBytecode.Emit(opJump, 0, AContinue.Line);
  AddContinueJump(jumpIdx, AContinue.LabelName);
end;

procedure TFloriaJSCompiler.CompileFunctionDecl(AFuncDecl: TFloriaJSFunctionDecl);
var
  compiler: TFloriaJSCompiler;
  subCode: TFloriaJSBytecode;
  fnIdx, locIdx, nameIdx, i: Integer;
begin
  compiler := TFloriaJSCompiler.Create();
  try
    subCode := TFloriaJSBytecode.Create(AFuncDecl.Name);

    if AFuncDecl.Parameters <> nil then
      for i := 0 to AFuncDecl.Parameters.Count - 1 do
        subCode.AddArgument(AFuncDecl.Parameters[i]);

    compiler.FBytecode := subCode;
    compiler.FIsTopLevel := False;
    compiler.FResultLoc := -1;
    if AFuncDecl.Body is TFloriaJSBlockStmt then
      compiler.CompileBlockStmt(TFloriaJSBlockStmt(AFuncDecl.Body))
    else
      compiler.CompileStmt(AFuncDecl.Body);

    subCode.Emit(opUndefined);
    subCode.Emit(opReturn);

    fnIdx := FBytecode.AddSubFunction(subCode);

    if FIsTopLevel then
    begin
      nameIdx := FBytecode.AddStringConstant(AFuncDecl.Name);
      FBytecode.Emit(opClosure, fnIdx, AFuncDecl.Line);
      FBytecode.Emit(opDefineEnv, nameIdx, AFuncDecl.Line);
    end
    else
    begin
      locIdx := FBytecode.AddLocal(AFuncDecl.Name);
      FBytecode.Emit(opClosure, fnIdx, AFuncDecl.Line);
      FBytecode.Emit(opSetLoc, locIdx, AFuncDecl.Line);
    end;
  finally
    compiler.Free();
  end;
end;

end.
