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
    IsLoop: Boolean;
    TryDepth: Integer;
    EnvDepth: Integer;
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
    FTryDepth: Integer;
    FTryStack: array of TFloriaJSBlockStmt;
    FEnvDepth: Integer;

    procedure PushLoopContext(const ALabel: string = ''; AIsLoop: Boolean = True);
    procedure PopLoopContext(ABreakTarget: Integer);
    procedure AddBreakJump(AJumpIdx: Integer; const ALabel: string = '');
    procedure AddContinueJump(AJumpIdx: Integer; const ALabel: string = '');
    procedure CompileParametersPrologue(AParams: TStringList);

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
    procedure CompileDestructuring(APattern: TFloriaJSExprNode);
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
    function CompileFunctionBody(const AName: string; AParams: TStringList; ABody: TFloriaJSStmtNode; AIsAsync: Boolean = False; AIsArrow: Boolean = False): TFloriaJSBytecode;
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
  FTryDepth := 0;
  SetLength(FTryStack, 16);
  FEnvDepth := 0;
end;

destructor TFloriaJSCompiler.Destroy();
begin
  SetLength(FLoopStack, 0);
  SetLength(FTryStack, 0);
  inherited Destroy();
end;

procedure TFloriaJSCompiler.PushLoopContext(const ALabel: string; AIsLoop: Boolean);
begin
  if FLoopDepth >= FLoopCapacity then
  begin
    FLoopCapacity := FLoopCapacity * 2;
    SetLength(FLoopStack, FLoopCapacity);
  end;

  FLoopStack[FLoopDepth].LabelName := ALabel;
  FLoopStack[FLoopDepth].ContinueTarget := -1;
  FLoopStack[FLoopDepth].IsLoop := AIsLoop;
  FLoopStack[FLoopDepth].TryDepth := FTryDepth;
  FLoopStack[FLoopDepth].EnvDepth := FEnvDepth;
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
      if (FLoopStack[i].LabelName = ALabel) and FLoopStack[i].IsLoop then
      begin
        targetDepth := i;
        Break;
      end;
  end
  else
  begin
    for i := FLoopDepth - 1 downto 0 do
      if FLoopStack[i].IsLoop then
      begin
        targetDepth := i;
        Break;
      end;
  end;

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

function TFloriaJSCompiler.CompileFunctionBody(const AName: string; AParams: TStringList; ABody: TFloriaJSStmtNode; AIsAsync: Boolean; AIsArrow: Boolean): TFloriaJSBytecode;
var
  compiler: TFloriaJSCompiler;
  subCode: TFloriaJSBytecode;
  i: Integer;
  pName: string;
begin
  compiler := TFloriaJSCompiler.Create();
  try
    subCode := TFloriaJSBytecode.Create(AName);
    subCode.IsArrow := AIsArrow;
    subCode.IsAsync := AIsAsync;

    if AParams <> nil then
      for i := 0 to AParams.Count - 1 do
      begin
        pName := AParams[i];
        if pName = '' then
          pName := '$param' + IntToStr(i);
        subCode.AddArgument(pName);
      end;

    compiler.FBytecode := subCode;
    compiler.FIsTopLevel := False;
    compiler.FResultLoc := -1;
    compiler.CompileParametersPrologue(AParams);
    if ABody is TFloriaJSBlockStmt then
      compiler.CompileBlockStmt(TFloriaJSBlockStmt(ABody))
    else if ABody is TFloriaJSExprStmt then
    begin
      compiler.CompileExpr(TFloriaJSExprStmt(ABody).Expression);
      subCode.Emit(opReturn);
      Exit(subCode);
    end
    else
      compiler.CompileStmt(ABody);

    subCode.Emit(opUndefined);
    subCode.Emit(opReturn);
    Result := subCode;
  finally
    compiler.Free();
  end;
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
  else if AExpr is TFloriaJSSpreadExpr then
    CompileExpr(TFloriaJSSpreadExpr(AExpr).Expression)
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
  else if (Length(AIdent.Name) > 0) and (AIdent.Name[1] = '$') then
  begin
    locIdx := FBytecode.FindLocal(AIdent.Name);
    if locIdx >= 0 then
      FBytecode.Emit(opLoadLoc, locIdx, AIdent.Line)
    else
      FBytecode.Emit(opLoadEnv, FBytecode.AddStringConstant(AIdent.Name), AIdent.Line);
  end
  else
    FBytecode.Emit(opLoadEnv, FBytecode.AddStringConstant(AIdent.Name), AIdent.Line);
end;

procedure TFloriaJSCompiler.CompileUnaryExpr(AUnary: TFloriaJSUnaryExpr);
var
  member: TFloriaJSMemberExpr;
  ident: TFloriaJSIdentifierExpr;
  locIdx, nameIdx, tmpLoc: Integer;
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
    tkAwait:
      begin
        CompileExpr(AUnary.Operand);
        FBytecode.Emit(opAwait, 0, AUnary.Line);
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
    tkPlusPlus, tkMinusMinus:
      begin
        if AUnary.Operand is TFloriaJSIdentifierExpr then
        begin
          ident := TFloriaJSIdentifierExpr(AUnary.Operand);
          if (Length(ident.Name) > 0) and (ident.Name[1] = '$') then
          begin
            locIdx := FBytecode.FindLocal(ident.Name);
            if AUnary.IsPrefix then
            begin
              if locIdx >= 0 then
                FBytecode.Emit(opLoadLoc, locIdx, AUnary.Line)
              else
                FBytecode.Emit(opLoadEnv, FBytecode.AddStringConstant(ident.Name), AUnary.Line);
              FBytecode.Emit(opOne, 0, AUnary.Line);
              if AUnary.Op = tkPlusPlus then
                FBytecode.Emit(opAdd, 0, AUnary.Line)
              else
                FBytecode.Emit(opSub, 0, AUnary.Line);
              if locIdx >= 0 then
                FBytecode.Emit(opStoreLoc, locIdx, AUnary.Line)
              else
                FBytecode.Emit(opStoreEnv, FBytecode.AddStringConstant(ident.Name), AUnary.Line);
            end
            else
            begin
              if locIdx >= 0 then
                FBytecode.Emit(opLoadLoc, locIdx, AUnary.Line)
              else
                FBytecode.Emit(opLoadEnv, FBytecode.AddStringConstant(ident.Name), AUnary.Line);
              FBytecode.Emit(opDup);
              FBytecode.Emit(opOne, 0, AUnary.Line);
              if AUnary.Op = tkPlusPlus then
                FBytecode.Emit(opAdd, 0, AUnary.Line)
              else
                FBytecode.Emit(opSub, 0, AUnary.Line);
              if locIdx >= 0 then
                FBytecode.Emit(opStoreLoc, locIdx, AUnary.Line)
              else
                FBytecode.Emit(opStoreEnv, FBytecode.AddStringConstant(ident.Name), AUnary.Line);
              FBytecode.Emit(opPop);
            end;
          end
          else
          begin
            nameIdx := FBytecode.AddStringConstant(ident.Name);
            if AUnary.IsPrefix then
            begin
              FBytecode.Emit(opLoadEnv, nameIdx, AUnary.Line);
              FBytecode.Emit(opOne, 0, AUnary.Line);
              if AUnary.Op = tkPlusPlus then
                FBytecode.Emit(opAdd, 0, AUnary.Line)
              else
                FBytecode.Emit(opSub, 0, AUnary.Line);
              FBytecode.Emit(opStoreEnv, nameIdx, AUnary.Line);
            end
            else
            begin
              FBytecode.Emit(opLoadEnv, nameIdx, AUnary.Line);
              FBytecode.Emit(opDup);
              FBytecode.Emit(opOne, 0, AUnary.Line);
              if AUnary.Op = tkPlusPlus then
                FBytecode.Emit(opAdd, 0, AUnary.Line)
              else
                FBytecode.Emit(opSub, 0, AUnary.Line);
              FBytecode.Emit(opStoreEnv, nameIdx, AUnary.Line);
              FBytecode.Emit(opPop);
            end;
          end;
        end
        else if AUnary.Operand is TFloriaJSMemberExpr then
        begin
          member := TFloriaJSMemberExpr(AUnary.Operand);
          CompileExpr(member.Target); // Stack: [Target]
          if not member.Computed then
          begin
            nameIdx := FBytecode.AddStringConstant(member.PropertyName);
            FBytecode.Emit(opDup); // [Target, Target]
            FBytecode.Emit(opGetPropNamed, nameIdx, AUnary.Line); // [Target, Val]
            if AUnary.IsPrefix then
            begin
              FBytecode.Emit(opOne, 0, AUnary.Line);
              if AUnary.Op = tkPlusPlus then
                FBytecode.Emit(opAdd, 0, AUnary.Line)
              else
                FBytecode.Emit(opSub, 0, AUnary.Line);
              FBytecode.Emit(opSetPropNamed, nameIdx, AUnary.Line);
            end
            else
            begin
              FBytecode.Emit(opDup); // [Target, Val, Val]
              tmpLoc := FBytecode.AddLocal('$postfix');
              FBytecode.Emit(opSetLoc, tmpLoc); // [Target, Val]
              FBytecode.Emit(opOne, 0, AUnary.Line);
              if AUnary.Op = tkPlusPlus then
                FBytecode.Emit(opAdd, 0, AUnary.Line)
              else
                FBytecode.Emit(opSub, 0, AUnary.Line);
              FBytecode.Emit(opSetPropNamed, nameIdx, AUnary.Line); // [newVal]
              FBytecode.Emit(opPop); // []
              FBytecode.Emit(opLoadLoc, tmpLoc); // [origVal]
            end;
          end
          else
          begin
            CompileExpr(member.PropertyExpr); // [Target, Prop]
            FBytecode.Emit(opDup2); // [Target, Prop, Target, Prop]
            FBytecode.Emit(opGetProp, 0, AUnary.Line); // [Target, Prop, Val]
            if AUnary.IsPrefix then
            begin
              FBytecode.Emit(opOne, 0, AUnary.Line);
              if AUnary.Op = tkPlusPlus then
                FBytecode.Emit(opAdd, 0, AUnary.Line)
              else
                FBytecode.Emit(opSub, 0, AUnary.Line);
              FBytecode.Emit(opSetProp, 0, AUnary.Line);
            end
            else
            begin
              FBytecode.Emit(opDup); // [Target, Prop, Val, Val]
              tmpLoc := FBytecode.AddLocal('$postfix');
              FBytecode.Emit(opSetLoc, tmpLoc); // [Target, Prop, Val]
              FBytecode.Emit(opOne, 0, AUnary.Line);
              if AUnary.Op = tkPlusPlus then
                FBytecode.Emit(opAdd, 0, AUnary.Line)
              else
                FBytecode.Emit(opSub, 0, AUnary.Line);
              FBytecode.Emit(opSetProp, 0, AUnary.Line);
              FBytecode.Emit(opPop);
              FBytecode.Emit(opLoadLoc, tmpLoc);
            end;
          end;
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
  locIdx, nameIdx: Integer;
begin
  if AAssign.Target is TFloriaJSIdentifierExpr then
  begin
    ident := TFloriaJSIdentifierExpr(AAssign.Target);

    if (Length(ident.Name) > 0) and (ident.Name[1] = '$') then
    begin
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
    else
    begin
      nameIdx := FBytecode.AddStringConstant(ident.Name);

      if AAssign.Op <> tkAssign then
      begin
        FBytecode.Emit(opLoadEnv, nameIdx);
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

      FBytecode.Emit(opStoreEnv, nameIdx, AAssign.Line);
    end;
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
  arg: TFloriaJSExprNode;
  i, count: Integer;
  hasSpread: Boolean;
begin
  count := ACall.GetArgumentCount();
  hasSpread := False;
  for i := 0 to count - 1 do
    if (ACall.GetArgument(i) <> nil) and (ACall.GetArgument(i) is TFloriaJSSpreadExpr) then
    begin
      hasSpread := True;
      Break;
    end;

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
  else if ACall.IsNew then
  begin
    CompileExpr(ACall.Callee);
  end
  else
  begin
    CompileExpr(ACall.Callee);
    FBytecode.Emit(opUndefined); // This value
  end;

  if hasSpread then
  begin
    FBytecode.Emit(opNewArray, 0, ACall.Line);
    for i := 0 to count - 1 do
    begin
      arg := ACall.GetArgument(i);
      if arg = nil then
      begin
        FBytecode.Emit(opDup);
        FBytecode.Emit(opDup);
        FBytecode.Emit(opGetPropNamed, FBytecode.AddStringConstant('push'));
        FBytecode.Emit(opSwap);
        FBytecode.Emit(opUndefined);
        FBytecode.Emit(opCall, 1);
        FBytecode.Emit(opPop);
      end
      else if arg is TFloriaJSSpreadExpr then
      begin
        FBytecode.Emit(opDup);
        FBytecode.Emit(opGetPropNamed, FBytecode.AddStringConstant('concat'));
        FBytecode.Emit(opSwap);
        CompileExpr(TFloriaJSSpreadExpr(arg).Expression);
        FBytecode.Emit(opCall, 1);
      end
      else
      begin
        FBytecode.Emit(opDup);
        FBytecode.Emit(opDup);
        FBytecode.Emit(opGetPropNamed, FBytecode.AddStringConstant('push'));
        FBytecode.Emit(opSwap);
        CompileExpr(arg);
        FBytecode.Emit(opCall, 1);
        FBytecode.Emit(opPop);
      end;
    end;

    if ACall.IsNew then
      FBytecode.Emit(opNewSpread, 0, ACall.Line)
    else
      FBytecode.Emit(opCallSpread, 0, ACall.Line);
  end
  else
  begin
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
end;

procedure TFloriaJSCompiler.CompileObjectExpr(AObj: TFloriaJSObjectExpr);
var
  i, count, tmpLoc: Integer;
  propName: string;
begin
  FBytecode.Emit(opNewObject, 0, AObj.Line);
  count := AObj.GetPropertyCount();

  for i := 0 to count - 1 do
  begin
    case AObj.GetPropertyKind(i) of
      fjpkNormal:
        begin
          propName := AObj.GetPropertyKey(i);
          FBytecode.Emit(opDup); // Duplicate object reference
          CompileExpr(AObj.GetPropertyValue(i));
          FBytecode.Emit(opSetPropNamed, FBytecode.AddStringConstant(propName));
          FBytecode.Emit(opPop); // Pop assigned value, keeping object on stack
        end;
      fjpkComputed:
        begin
          FBytecode.Emit(opDup); // [obj, obj]
          CompileExpr(AObj.GetPropertyKeyExpr(i)); // [obj, obj, key]
          CompileExpr(AObj.GetPropertyValue(i)); // [obj, obj, key, val]
          FBytecode.Emit(opSetProp); // [obj, val]
          FBytecode.Emit(opPop); // [obj]
        end;
      fjpkSpread:
        begin
          tmpLoc := FBytecode.AddNewLocal('$obj');
          FBytecode.Emit(opStoreLoc, tmpLoc);
          FBytecode.Emit(opLoadEnv, FBytecode.AddStringConstant('Object'));
          FBytecode.Emit(opGetPropNamed, FBytecode.AddStringConstant('assign'));
          FBytecode.Emit(opLoadEnv, FBytecode.AddStringConstant('Object'));
          FBytecode.Emit(opLoadLoc, tmpLoc);
          CompileExpr(AObj.GetPropertyValue(i));
          FBytecode.Emit(opCall, 2);
          FBytecode.Emit(opPop);
        end;
      fjpkGetter:
        begin
          propName := AObj.GetPropertyKey(i);
          if AObj.GetPropertyKeyExpr(i) <> nil then
          begin
            CompileExpr(AObj.GetPropertyKeyExpr(i));
            CompileExpr(AObj.GetPropertyValue(i));
            FBytecode.Emit(opDefineGetter, -1);
          end
          else
          begin
            CompileExpr(AObj.GetPropertyValue(i));
            FBytecode.Emit(opDefineGetter, FBytecode.AddStringConstant(propName));
          end;
        end;
      fjpkSetter:
        begin
          propName := AObj.GetPropertyKey(i);
          if AObj.GetPropertyKeyExpr(i) <> nil then
          begin
            CompileExpr(AObj.GetPropertyKeyExpr(i));
            CompileExpr(AObj.GetPropertyValue(i));
            FBytecode.Emit(opDefineSetter, -1);
          end
          else
          begin
            CompileExpr(AObj.GetPropertyValue(i));
            FBytecode.Emit(opDefineSetter, FBytecode.AddStringConstant(propName));
          end;
        end;
    end;
  end;
end;

procedure TFloriaJSCompiler.CompileArrayExpr(AArr: TFloriaJSArrayExpr);
var
  i, count: Integer;
  hasSpread: Boolean;
begin
  count := AArr.GetElementCount();
  hasSpread := False;
  for i := 0 to count - 1 do
    if (AArr.GetElement(i) <> nil) and (AArr.GetElement(i) is TFloriaJSSpreadExpr) then
    begin
      hasSpread := True;
      Break;
    end;

  if not hasSpread then
  begin
    for i := 0 to count - 1 do
      CompileExpr(AArr.GetElement(i));
    FBytecode.Emit(opNewArray, count, AArr.Line);
  end
  else
  begin
    FBytecode.Emit(opNewArray, 0, AArr.Line);
    for i := 0 to count - 1 do
    begin
      if AArr.GetElement(i) = nil then
      begin
        FBytecode.Emit(opDup);
        FBytecode.Emit(opDup);
        FBytecode.Emit(opGetPropNamed, FBytecode.AddStringConstant('push'));
        FBytecode.Emit(opSwap);
        FBytecode.Emit(opUndefined);
        FBytecode.Emit(opCall, 1);
        FBytecode.Emit(opPop);
      end
      else if AArr.GetElement(i) is TFloriaJSSpreadExpr then
      begin
        FBytecode.Emit(opDup);
        FBytecode.Emit(opGetPropNamed, FBytecode.AddStringConstant('concat'));
        FBytecode.Emit(opSwap);
        CompileExpr(TFloriaJSSpreadExpr(AArr.GetElement(i)).Expression);
        FBytecode.Emit(opCall, 1);
      end
      else
      begin
        FBytecode.Emit(opDup);
        FBytecode.Emit(opDup);
        FBytecode.Emit(opGetPropNamed, FBytecode.AddStringConstant('push'));
        FBytecode.Emit(opSwap);
        CompileExpr(AArr.GetElement(i));
        FBytecode.Emit(opCall, 1);
        FBytecode.Emit(opPop);
      end;
    end;
  end;
end;

procedure TFloriaJSCompiler.CompileParametersPrologue(AParams: TStringList);
var
  i, nameIdx, skipJump: Integer;
  pName: string;
  defExpr, paramObj: TFloriaJSExprNode;
begin
  if AParams = nil then Exit;

  for i := 0 to AParams.Count - 1 do
  begin
    pName := AParams.Strings[i];
    paramObj := TFloriaJSExprNode(AParams.Objects[i]);
    defExpr := nil;
    if pName = '' then
    begin
      pName := '$param' + IntToStr(i);
      if (paramObj is TFloriaJSAssignExpr) and (TFloriaJSAssignExpr(paramObj).Value <> nil) then
        defExpr := TFloriaJSAssignExpr(paramObj).Value;
    end
    else
      defExpr := paramObj;

    if defExpr <> nil then
    begin
      nameIdx := FBytecode.AddStringConstant(pName);
      FBytecode.Emit(opLoadEnv, nameIdx);
      FBytecode.Emit(opUndefined);
      FBytecode.Emit(opStrictEq);
      skipJump := FBytecode.Emit(opJumpIfFalse, 0);

      CompileExpr(defExpr);
      FBytecode.Emit(opStoreEnv, nameIdx);
      FBytecode.Emit(opPop);

      FBytecode.PatchJump(skipJump, FBytecode.CurrentIP());
    end;

    if (AParams.Strings[i] = '') and (paramObj <> nil) then
    begin
      nameIdx := FBytecode.AddStringConstant(pName);
      FBytecode.Emit(opLoadEnv, nameIdx);
      if paramObj is TFloriaJSAssignExpr then
        CompileDestructuring(TFloriaJSAssignExpr(paramObj).Target)
      else
        CompileDestructuring(paramObj);
    end;
  end;
end;

procedure TFloriaJSCompiler.CompileFunctionExpr(AFunc: TFloriaJSFunctionExpr);
var
  subCode: TFloriaJSBytecode;
  fnIdx: Integer;
begin
  subCode := CompileFunctionBody(AFunc.Name, AFunc.Parameters, AFunc.Body, AFunc.IsAsync, AFunc.IsArrow);
  fnIdx := FBytecode.AddSubFunction(subCode);
  FBytecode.Emit(opClosure, fnIdx, AFunc.Line);
end;

procedure TFloriaJSCompiler.CompileDestructuring(APattern: TFloriaJSExprNode);
var
  objExpr: TFloriaJSObjectExpr;
  arrExpr: TFloriaJSArrayExpr;
  ident: TFloriaJSIdentifierExpr;
  assignExpr: TFloriaJSAssignExpr;
  spreadExpr: TFloriaJSSpreadExpr;
  propValNode, elemNode, valNode: TFloriaJSExprNode;
  propKey: string;
  nameIdx, i, j, count, skipJump: Integer;
  extractedList: TStringList;
begin
  if APattern = nil then Exit;

  if APattern is TFloriaJSIdentifierExpr then
  begin
    ident := TFloriaJSIdentifierExpr(APattern);
    nameIdx := FBytecode.AddStringConstant(ident.Name);
    FBytecode.Emit(opDefineEnv, nameIdx, ident.Line);
  end
  else if APattern is TFloriaJSAssignExpr then
  begin
    assignExpr := TFloriaJSAssignExpr(APattern);
    FBytecode.Emit(opDup);
    FBytecode.Emit(opUndefined);
    FBytecode.Emit(opStrictEq);
    skipJump := FBytecode.Emit(opJumpIfFalse, 0);
    FBytecode.Emit(opPop);
    CompileExpr(assignExpr.Value);
    FBytecode.PatchJump(skipJump, FBytecode.CurrentIP());
    CompileDestructuring(assignExpr.Target);
  end
  else if APattern is TFloriaJSObjectExpr then
  begin
    objExpr := TFloriaJSObjectExpr(APattern);
    count := objExpr.GetPropertyCount();
    extractedList := TStringList.Create();
    try
      for i := 0 to count - 1 do
      begin
        if objExpr.GetPropertyKind(i) = fjpkSpread then
        begin
          valNode := objExpr.GetPropertyValue(i);
          if valNode is TFloriaJSSpreadExpr then
            valNode := TFloriaJSSpreadExpr(valNode).Expression;
          FBytecode.Emit(opDup);
          for j := 0 to extractedList.Count - 1 do
            FBytecode.Emit(opConst, FBytecode.AddStringConstant(extractedList[j]));
          FBytecode.Emit(opObjectRest, extractedList.Count, APattern.Line);
          CompileDestructuring(valNode);
        end
        else
        begin
          propKey := objExpr.GetPropertyKey(i);
          extractedList.Add(propKey);
          propValNode := objExpr.GetPropertyValue(i);
          FBytecode.Emit(opDup);
          FBytecode.Emit(opGetPropNamed, FBytecode.AddStringConstant(propKey));
          CompileDestructuring(propValNode);
        end;
      end;
    finally
      extractedList.Free();
    end;
    FBytecode.Emit(opPop);
  end
  else if APattern is TFloriaJSArrayExpr then
  begin
    arrExpr := TFloriaJSArrayExpr(APattern);
    count := arrExpr.GetElementCount();
    for i := 0 to count - 1 do
    begin
      elemNode := arrExpr.GetElement(i);
      if elemNode = nil then Continue;
      if elemNode is TFloriaJSSpreadExpr then
      begin
        spreadExpr := TFloriaJSSpreadExpr(elemNode);
        FBytecode.Emit(opDup);
        FBytecode.Emit(opGetPropNamed, FBytecode.AddStringConstant('slice'));
        FBytecode.Emit(opSwap);
        FBytecode.Emit(opConst, FBytecode.AddNumberConstant(i));
        FBytecode.Emit(opCall, 1);
        CompileDestructuring(spreadExpr.Expression);
        Break;
      end
      else
      begin
        FBytecode.Emit(opDup);
        FBytecode.Emit(opConst, FBytecode.AddNumberConstant(i));
        FBytecode.Emit(opGetProp);
        CompileDestructuring(elemNode);
      end;
    end;
    FBytecode.Emit(opPop);
  end;
end;

procedure TFloriaJSCompiler.CompileVarStmt(AVar: TFloriaJSVarStmt);
var
  i, count, nameIdx: Integer;
  declName: string;
  declInit: TFloriaJSExprNode;
  declPattern: TFloriaJSExprNode;
begin
  count := AVar.GetDeclaratorCount();
  for i := 0 to count - 1 do
  begin
    declName := AVar.GetDeclaratorName(i);
    declPattern := AVar.GetDeclaratorPattern(i);
    declInit := AVar.GetDeclaratorInit(i);

    if declInit <> nil then
      CompileExpr(declInit)
    else
      FBytecode.Emit(opUndefined);

    if declPattern <> nil then
      CompileDestructuring(declPattern)
    else
    begin
      nameIdx := FBytecode.AddStringConstant(declName);
      FBytecode.Emit(opDefineEnv, nameIdx, AVar.Line);
    end;
  end;
end;

function HasBlockScopedDecls(ABlock: TFloriaJSBlockStmt): Boolean;
var
  i: Integer;
  stmt: TFloriaJSStmtNode;
begin
  Result := False;
  for i := 0 to ABlock.GetStatementCount() - 1 do
  begin
    stmt := ABlock.GetStatement(i);
    if (stmt is TFloriaJSVarStmt) and (TFloriaJSVarStmt(stmt).Kind in [tkLet, tkConst]) then
      Exit(True);
    if stmt is TFloriaJSFunctionDecl then
      Exit(True);
  end;
end;

procedure TFloriaJSCompiler.CompileBlockStmt(ABlock: TFloriaJSBlockStmt);
var
  i, count: Integer;
  needsScope: Boolean;
begin
  count := ABlock.GetStatementCount();
  needsScope := HasBlockScopedDecls(ABlock);
  if needsScope then
  begin
    Inc(FEnvDepth);
    FBytecode.Emit(opPushEnv);
  end;

  for i := 0 to count - 1 do
    CompileStmt(ABlock.GetStatement(i));

  if needsScope then
  begin
    Dec(FEnvDepth);
    FBytecode.Emit(opPopEnv);
  end;
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
  i, loopStart, exitJump, contTarget: Integer;
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
  for i := 0 to High(FLoopStack[FLoopDepth - 1].ContinueJumps) do
    FBytecode.PatchJump(FLoopStack[FLoopDepth - 1].ContinueJumps[i], contTarget);
  SetLength(FLoopStack[FLoopDepth - 1].ContinueJumps, 0);

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
  i, iterLoc, idxLoc, lenLoc, varLoc, nameIdx: Integer;
  loopStart, exitJump, contTarget: Integer;
  isBlockScoped: Boolean;
begin
  iterLoc := FBytecode.AddNewLocal('$iter');
  idxLoc := FBytecode.AddNewLocal('$idx');
  lenLoc := FBytecode.AddNewLocal('$len');

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
  isBlockScoped := AForInOf.VarKind in [tkLet, tkConst];
  if isBlockScoped then
  begin
    Inc(FEnvDepth);
    FBytecode.Emit(opPushEnv);
  end;

  nameIdx := FBytecode.AddStringConstant(AForInOf.VarName);
  if AForInOf.VarKind in [tkLet, tkConst, tkVar] then
    FBytecode.Emit(opDefineEnv, nameIdx)
  else
  begin
    FBytecode.Emit(opStoreEnv, nameIdx);
    FBytecode.Emit(opPop);
  end;

  // Compile body
  CompileStmt(AForInOf.Body);

  if isBlockScoped then
  begin
    Dec(FEnvDepth);
    FBytecode.Emit(opPopEnv);
  end;

  // Continue target: increment idx
  contTarget := FBytecode.CurrentIP();
  FLoopStack[FLoopDepth - 1].ContinueTarget := contTarget;
  for i := 0 to High(FLoopStack[FLoopDepth - 1].ContinueJumps) do
    FBytecode.PatchJump(FLoopStack[FLoopDepth - 1].ContinueJumps[i], contTarget);
  SetLength(FLoopStack[FLoopDepth - 1].ContinueJumps, 0);

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

  discLoc := FBytecode.AddNewLocal('$disc');
  CompileExpr(ASwitch.Discriminant);
  FBytecode.Emit(opSetLoc, discLoc);

  PushLoopContext('', False); // For unlabelled break

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
  PushLoopContext(ALabeled.LabelName, False);
  CompileStmt(ALabeled.Body);
  PopLoopContext(FBytecode.CurrentIP());
end;

procedure TFloriaJSCompiler.CompileReturnStmt(ARet: TFloriaJSReturnStmt);
var
  k, tmpRet: Integer;
begin
  if ARet.Argument <> nil then
    CompileExpr(ARet.Argument)
  else
    FBytecode.Emit(opUndefined);

  if FTryDepth > 0 then
  begin
    tmpRet := FBytecode.AddLocal('$return');
    FBytecode.Emit(opSetLoc, tmpRet);
    for k := FTryDepth - 1 downto 0 do
    begin
      if FTryStack[k] <> nil then
        CompileStmt(FTryStack[k]);
      FBytecode.Emit(opPopTry);
    end;
    FBytecode.Emit(opLoadLoc, tmpRet);
  end;

  for k := FEnvDepth - 1 downto 0 do
    FBytecode.Emit(opPopEnv);

  FBytecode.Emit(opReturn, 0, ARet.Line);
end;

procedure TFloriaJSCompiler.CompileTryStmt(ATry: TFloriaJSTryStmt);
var
  tryIdx, endJump, nameIdx, tmpErr: Integer;
begin
  if ATry.CatchBlock <> nil then
  begin
    if FTryDepth >= Length(FTryStack) then
      SetLength(FTryStack, Length(FTryStack) * 2);
    FTryStack[FTryDepth] := ATry.FinallyBlock;
    Inc(FTryDepth);

    tryIdx := FBytecode.Emit(opPushTry, 0, ATry.Line);
    CompileStmt(ATry.Block);
    FBytecode.Emit(opPopTry);
    Dec(FTryDepth);

    endJump := FBytecode.Emit(opJump, 0);

    FBytecode.PatchJump(tryIdx, FBytecode.CurrentIP());
    if ATry.CatchParam <> '' then
    begin
      FBytecode.Emit(opPushEnv);
      nameIdx := FBytecode.AddStringConstant(ATry.CatchParam);
      FBytecode.Emit(opDefineEnv, nameIdx, ATry.Line);
    end
    else
      FBytecode.Emit(opPop);

    CompileStmt(ATry.CatchBlock);

    if ATry.CatchParam <> '' then
      FBytecode.Emit(opPopEnv);

    FBytecode.PatchJump(endJump, FBytecode.CurrentIP());

    if ATry.FinallyBlock <> nil then
      CompileStmt(ATry.FinallyBlock);
  end
  else
  begin
    if FTryDepth >= Length(FTryStack) then
      SetLength(FTryStack, Length(FTryStack) * 2);
    FTryStack[FTryDepth] := ATry.FinallyBlock;
    Inc(FTryDepth);

    tryIdx := FBytecode.Emit(opPushTry, 0, ATry.Line);
    CompileStmt(ATry.Block);
    FBytecode.Emit(opPopTry);
    Dec(FTryDepth);

    if ATry.FinallyBlock <> nil then
      CompileStmt(ATry.FinallyBlock);
    endJump := FBytecode.Emit(opJump, 0);

    FBytecode.PatchJump(tryIdx, FBytecode.CurrentIP());
    tmpErr := FBytecode.AddNewLocal('$finallyErr');
    FBytecode.Emit(opSetLoc, tmpErr);
    if ATry.FinallyBlock <> nil then
      CompileStmt(ATry.FinallyBlock);
    FBytecode.Emit(opLoadLoc, tmpErr);
    FBytecode.Emit(opThrow, 0, ATry.Line);

    FBytecode.PatchJump(endJump, FBytecode.CurrentIP());
  end;
end;

procedure TFloriaJSCompiler.CompileThrowStmt(AThrow: TFloriaJSThrowStmt);
begin
  CompileExpr(AThrow.Expression);
  FBytecode.Emit(opThrow, 0, AThrow.Line);
end;

procedure TFloriaJSCompiler.CompileBreakStmt(ABreak: TFloriaJSBreakStmt);
var
  jumpIdx, targetDepth, i, k: Integer;
begin
  targetDepth := -1;
  if ABreak.LabelName <> '' then
  begin
    for i := FLoopDepth - 1 downto 0 do
      if FLoopStack[i].LabelName = ABreak.LabelName then
      begin
        targetDepth := i;
        Break;
      end;
  end
  else if FLoopDepth > 0 then
    targetDepth := FLoopDepth - 1;

  if targetDepth >= 0 then
  begin
    for k := FTryDepth - 1 downto FLoopStack[targetDepth].TryDepth do
    begin
      if FTryStack[k] <> nil then
        CompileStmt(FTryStack[k]);
      FBytecode.Emit(opPopTry);
    end;
    for k := FEnvDepth - 1 downto FLoopStack[targetDepth].EnvDepth do
      FBytecode.Emit(opPopEnv);
  end;

  jumpIdx := FBytecode.Emit(opJump, 0, ABreak.Line);
  AddBreakJump(jumpIdx, ABreak.LabelName);
end;

procedure TFloriaJSCompiler.CompileContinueStmt(AContinue: TFloriaJSContinueStmt);
var
  jumpIdx, targetDepth, i, k: Integer;
begin
  targetDepth := -1;
  if AContinue.LabelName <> '' then
  begin
    for i := FLoopDepth - 1 downto 0 do
      if (FLoopStack[i].LabelName = AContinue.LabelName) and FLoopStack[i].IsLoop then
      begin
        targetDepth := i;
        Break;
      end;
  end
  else
  begin
    for i := FLoopDepth - 1 downto 0 do
      if FLoopStack[i].IsLoop then
      begin
        targetDepth := i;
        Break;
      end;
  end;

  if targetDepth >= 0 then
  begin
    for k := FTryDepth - 1 downto FLoopStack[targetDepth].TryDepth do
    begin
      if FTryStack[k] <> nil then
        CompileStmt(FTryStack[k]);
      FBytecode.Emit(opPopTry);
    end;
    for k := FEnvDepth - 1 downto FLoopStack[targetDepth].EnvDepth do
      FBytecode.Emit(opPopEnv);
  end;

  jumpIdx := FBytecode.Emit(opJump, 0, AContinue.Line);
  AddContinueJump(jumpIdx, AContinue.LabelName);
end;

procedure TFloriaJSCompiler.CompileFunctionDecl(AFuncDecl: TFloriaJSFunctionDecl);
var
  subCode: TFloriaJSBytecode;
  fnIdx, nameIdx: Integer;
begin
  subCode := CompileFunctionBody(AFuncDecl.Name, AFuncDecl.Parameters, AFuncDecl.Body, AFuncDecl.IsAsync, False);
  fnIdx := FBytecode.AddSubFunction(subCode);
  nameIdx := FBytecode.AddStringConstant(AFuncDecl.Name);
  FBytecode.Emit(opClosure, fnIdx, AFuncDecl.Line);
  FBytecode.Emit(opDefineEnv, nameIdx, AFuncDecl.Line);
end;

end.
