{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Bytecode Instruction Set & Chunk Container      }
{                                                                          }
{   Defines virtual machine opcodes, instruction encoding, constant pool,  }
{   and bytecode chunks for the QML V4-class execution engine.             }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.bytecode;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, floria.js.types, floria.js.value;

type
  { VM Opcode Enumeration }
  TFloriaJSOpcode = (
    opNop,
    // Stack Manipulation
    opPop,               // Pop top value
    opDup,               // Duplicate top value
    opSwap,              // Swap top two values

    // Primitives & Constants
    opConst,             // Push constant from pool: Imm = const index
    opUndefined,         // Push undefined
    opNull,              // Push null
    opTrue,              // Push true
    opFalse,             // Push false
    opZero,              // Push number 0
    opOne,               // Push number 1

    // Variables & Environments
    opLoadLoc,           // Push local variable: Imm = slot index
    opStoreLoc,          // Store top into local slot: Imm = slot index (leaves value on stack)
    opSetLoc,            // Store top into local slot and pop: Imm = slot index
    opLoadGlobal,        // Push global by name: Imm = const index (string)
    opStoreGlobal,       // Store into global: Imm = const index (string), leaves value on stack
    opSetGlobal,         // Store into global: Imm = const index (string), pops value
    opLoadEnv,           // Push variable from environment: Imm = const index (name)
    opStoreEnv,          // Store variable into environment: Imm = const index (name)
    opDefineEnv,         // Define variable into current environment: Imm = const index (name), pops value

    // Objects & Arrays
    opNewObject,         // Push new empty object
    opNewArray,          // Push new array: Imm = element count
    opGetProp,           // Pop prop, pop obj -> push obj[prop]
    opGetPropNamed,      // Pop obj -> push obj[name]: Imm = const index (name)
    opSetProp,           // Pop val, pop prop, pop obj -> obj[prop] = val, push val
    opSetPropNamed,      // Pop val, pop obj -> obj[name] = val: Imm = const index, push val
    opGetPropOptional,   // Pop prop, pop obj -> if null/undefined push undefined else obj[prop]
    opGetPropNamedOpt,   // Pop obj -> if null/undefined push undefined else obj[name]: Imm = const index
    opDeleteProp,        // Pop prop, pop obj -> push delete obj[prop]
    opIn,                // Pop obj, pop prop -> push prop in obj
    opInstanceOf,        // Pop ctor, pop obj -> push obj instanceof ctor

    // Arithmetic & Bitwise
    opAdd,               // a + b
    opSub,               // a - b
    opMul,               // a * b
    opDiv,               // a / b
    opMod,               // a % b
    opPower,             // a ** b
    opNeg,               // -a
    opPos,               // +a
    opBitNot,            // ~a
    opBitAnd,            // a & b
    opBitOr,             // a | b
    opBitXor,            // a ^ b
    opShl,               // a << b
    opShr,               // a >> b (logical)
    opSar,               // a >>> b (arithmetic)

    // Comparisons
    opEq,                // a == b
    opStrictEq,          // a === b
    opNotEq,             // a != b
    opStrictNotEq,       // a !== b
    opLt,                // a < b
    opLe,                // a <= b
    opGt,                // a > b
    opGe,                // a >= b

    // Unary & Logic
    opNot,               // !a
    opTypeOf,            // typeof a
    opVoid,              // void a -> push undefined

    // Jumps & Control Flow
    opJump,              // Jump to absolute IP: Imm = target IP
    opJumpIfFalse,       // Pop cond; if falsy jump to Imm
    opJumpIfTrue,        // Pop cond; if truthy jump to Imm
    opJumpIfNullish,     // Peek cond; if null/undefined jump to Imm, else pop cond
    opJumpIfFalseyPeek,  // Peek cond; if falsy jump to Imm, else pop cond (for &&)
    opJumpIfTruthyPeek,  // Peek cond; if truthy jump to Imm, else pop cond (for ||)

    // Function Calls & Construction
    opCall,              // Call: Imm = arg count, stack: [callee, this, arg0..argN-1]
    opCallOpt,           // Optional call: Imm = arg count
    opNew,               // Construct: Imm = arg count, stack: [ctor, arg0..argN-1]
    opReturn,            // Return top value from function
    opClosure,           // Instantiate function: Imm = function bytecode chunk index

    // Exceptions
    opThrow,             // Throw top value
    opPushTry,           // Push exception handler: Imm = catch IP offset
    opPopTry,            // Pop exception handler

    // Iteration Helpers
    opForInInit,         // Pop obj -> Push array of enumerable keys
    opForOfInit,         // Pop iterable -> Push array of items

    // Loop & VM Control
    opHalt               // End of execution
  );

  { Single Bytecode Instruction }
  TFloriaJSInstruction = packed record
    Op: TFloriaJSOpcode;
    Imm: Int32;
    Line: Int32;
  end;

  { Bytecode Chunk for a Script or Function Prototype }
  TFloriaJSBytecode = class
  private
    FName: string;
    FCode: array of TFloriaJSInstruction;
    FCodeCount: Integer;
    FCodeCapacity: Integer;
    FConstants: array of TFloriaJSValue;
    FConstCount: Integer;
    FConstCapacity: Integer;
    FLocalNames: TStringList;
    FArgNames: TStringList;
    FSubFunctions: TFPList;
    FIsArrow: Boolean;
    FIsAsync: Boolean;

    procedure EnsureCodeCapacity();
    procedure EnsureConstCapacity();
  public
    constructor Create(const AName: string = '');
    destructor Destroy(); override;

    { Instruction Emission }
    function  Emit(AOp: TFloriaJSOpcode; AImm: Int32 = 0; ALine: Int32 = 0): Integer;
    procedure PatchJump(AIndex: Integer; ATarget: Integer);
    function  CurrentIP(): Integer;

    { Constant Pool }
    function  AddConstant(const AValue: TFloriaJSValue): Integer;
    function  AddStringConstant(const AStr: string): Integer;
    function  AddNumberConstant(ANum: Double): Integer;
    function  GetConstant(AIndex: Integer): TFloriaJSValue;
    function  GetConstantCount(): Integer;

    { Local Variables & Parameters }
    function  AddLocal(const AName: string): Integer;
    function  FindLocal(const AName: string): Integer;
    function  GetLocalCount(): Integer;
    function  GetLocalName(AIndex: Integer): string;

    function  AddArgument(const AName: string): Integer;
    function  GetArgumentCount(): Integer;
    function  GetArgumentName(AIndex: Integer): string;

    { Sub-function Prototypes }
    function  AddSubFunction(AFunc: TFloriaJSBytecode): Integer;
    function  GetSubFunction(AIndex: Integer): TFloriaJSBytecode;
    function  GetSubFunctionCount(): Integer;

    { Instruction Access }
    function  GetInstruction(AIndex: Integer): TFloriaJSInstruction;
    function  GetInstructionCount(): Integer;

    { Disassembly / Debug }
    function  Disassemble(): string;
    function  DisassembleInstruction(AIndex: Integer): string;

    property Name: string read FName write FName;
    property IsArrow: Boolean read FIsArrow write FIsArrow;
    property IsAsync: Boolean read FIsAsync write FIsAsync;
  end;

function FloriaJSOpcodeToString(AOp: TFloriaJSOpcode): string;

implementation

function FloriaJSOpcodeToString(AOp: TFloriaJSOpcode): string;
begin
  case AOp of
    opNop:              Result := 'NOP';
    opPop:              Result := 'POP';
    opDup:              Result := 'DUP';
    opSwap:             Result := 'SWAP';
    opConst:            Result := 'CONST';
    opUndefined:        Result := 'UNDEFINED';
    opNull:             Result := 'NULL';
    opTrue:             Result := 'TRUE';
    opFalse:            Result := 'FALSE';
    opZero:             Result := 'ZERO';
    opOne:              Result := 'ONE';
    opLoadLoc:          Result := 'LOAD_LOC';
    opStoreLoc:         Result := 'STORE_LOC';
    opSetLoc:           Result := 'SET_LOC';
    opLoadGlobal:       Result := 'LOAD_GLOBAL';
    opStoreGlobal:      Result := 'STORE_GLOBAL';
    opSetGlobal:        Result := 'SET_GLOBAL';
    opLoadEnv:          Result := 'LOAD_ENV';
    opStoreEnv:         Result := 'STORE_ENV';
    opDefineEnv:        Result := 'DEFINE_ENV';
    opNewObject:        Result := 'NEW_OBJECT';
    opNewArray:         Result := 'NEW_ARRAY';
    opGetProp:          Result := 'GET_PROP';
    opGetPropNamed:     Result := 'GET_PROP_NAMED';
    opSetProp:          Result := 'SET_PROP';
    opSetPropNamed:     Result := 'SET_PROP_NAMED';
    opGetPropOptional:  Result := 'GET_PROP_OPT';
    opGetPropNamedOpt:  Result := 'GET_PROP_NAMED_OPT';
    opDeleteProp:       Result := 'DELETE_PROP';
    opIn:               Result := 'IN';
    opInstanceOf:       Result := 'INSTANCEOF';
    opAdd:              Result := 'ADD';
    opSub:              Result := 'SUB';
    opMul:              Result := 'MUL';
    opDiv:              Result := 'DIV';
    opMod:              Result := 'MOD';
    opPower:            Result := 'POWER';
    opNeg:              Result := 'NEG';
    opPos:              Result := 'POS';
    opBitNot:           Result := 'BIT_NOT';
    opBitAnd:           Result := 'BIT_AND';
    opBitOr:            Result := 'BIT_OR';
    opBitXor:           Result := 'BIT_XOR';
    opShl:              Result := 'SHL';
    opShr:              Result := 'SHR';
    opSar:              Result := 'SAR';
    opEq:               Result := 'EQ';
    opStrictEq:         Result := 'STRICT_EQ';
    opNotEq:            Result := 'NOT_EQ';
    opStrictNotEq:      Result := 'STRICT_NOT_EQ';
    opLt:               Result := 'LT';
    opLe:               Result := 'LE';
    opGt:               Result := 'GT';
    opGe:               Result := 'GE';
    opNot:              Result := 'NOT';
    opTypeOf:           Result := 'TYPEOF';
    opVoid:             Result := 'VOID';
    opJump:             Result := 'JUMP';
    opJumpIfFalse:      Result := 'JUMP_IF_FALSE';
    opJumpIfTrue:       Result := 'JUMP_IF_TRUE';
    opJumpIfNullish:    Result := 'JUMP_IF_NULLISH';
    opJumpIfFalseyPeek: Result := 'JUMP_IF_FALSEY_PEEK';
    opJumpIfTruthyPeek: Result := 'JUMP_IF_TRUTHY_PEEK';
    opCall:             Result := 'CALL';
    opCallOpt:          Result := 'CALL_OPT';
    opNew:              Result := 'NEW';
    opReturn:           Result := 'RETURN';
    opClosure:          Result := 'CLOSURE';
    opThrow:            Result := 'THROW';
    opPushTry:          Result := 'PUSH_TRY';
    opPopTry:           Result := 'POP_TRY';
    opForInInit:        Result := 'FOR_IN_INIT';
    opForOfInit:        Result := 'FOR_OF_INIT';
    opHalt:             Result := 'HALT';
  else
    Result := 'UNKNOWN';
  end;
end;

{ TFloriaJSBytecode }

constructor TFloriaJSBytecode.Create(const AName: string);
begin
  inherited Create();
  FName := AName;
  FCodeCount := 0;
  FCodeCapacity := 32;
  SetLength(FCode, FCodeCapacity);

  FConstCount := 0;
  FConstCapacity := 16;
  SetLength(FConstants, FConstCapacity);

  FLocalNames := TStringList.Create();
  FArgNames := TStringList.Create();
  FSubFunctions := TFPList.Create();
  FIsArrow := False;
  FIsAsync := False;
end;

destructor TFloriaJSBytecode.Destroy();
var
  i: Integer;
begin
  SetLength(FCode, 0);
  SetLength(FConstants, 0);
  FreeAndNil(FLocalNames);
  FreeAndNil(FArgNames);

  if FSubFunctions <> nil then
  begin
    for i := 0 to FSubFunctions.Count - 1 do
      TObject(FSubFunctions[i]).Free();
    FreeAndNil(FSubFunctions);
  end;

  inherited Destroy();
end;

procedure TFloriaJSBytecode.EnsureCodeCapacity();
begin
  if FCodeCount >= FCodeCapacity then
  begin
    FCodeCapacity := FCodeCapacity * 2;
    SetLength(FCode, FCodeCapacity);
  end;
end;

procedure TFloriaJSBytecode.EnsureConstCapacity();
begin
  if FConstCount >= FConstCapacity then
  begin
    FConstCapacity := FConstCapacity * 2;
    SetLength(FConstants, FConstCapacity);
  end;
end;

function TFloriaJSBytecode.Emit(AOp: TFloriaJSOpcode; AImm: Int32; ALine: Int32): Integer;
begin
  EnsureCodeCapacity();
  FCode[FCodeCount].Op := AOp;
  FCode[FCodeCount].Imm := AImm;
  FCode[FCodeCount].Line := ALine;
  Result := FCodeCount;
  Inc(FCodeCount);
end;

procedure TFloriaJSBytecode.PatchJump(AIndex: Integer; ATarget: Integer);
begin
  if (AIndex >= 0) and (AIndex < FCodeCount) then
    FCode[AIndex].Imm := ATarget;
end;

function TFloriaJSBytecode.CurrentIP(): Integer;
begin
  Result := FCodeCount;
end;

function TFloriaJSBytecode.AddConstant(const AValue: TFloriaJSValue): Integer;
var
  i: Integer;
begin
  // De-duplicate primitives
  for i := 0 to FConstCount - 1 do
  begin
    if JSStrictEqual(FConstants[i], AValue) then
      Exit(i);
  end;

  EnsureConstCapacity();
  FConstants[FConstCount] := AValue;
  Result := FConstCount;
  Inc(FConstCount);
end;

function TFloriaJSBytecode.AddStringConstant(const AStr: string): Integer;
begin
  Result := AddConstant(JSMakeString(AStr));
end;

function TFloriaJSBytecode.AddNumberConstant(ANum: Double): Integer;
begin
  Result := AddConstant(JSMakeNumber(ANum));
end;

function TFloriaJSBytecode.GetConstant(AIndex: Integer): TFloriaJSValue;
begin
  if (AIndex >= 0) and (AIndex < FConstCount) then
    Result := FConstants[AIndex]
  else
    Result := JSMakeUndefined();
end;

function TFloriaJSBytecode.GetConstantCount(): Integer;
begin
  Result := FConstCount;
end;

function TFloriaJSBytecode.AddLocal(const AName: string): Integer;
begin
  Result := FindLocal(AName);
  if Result >= 0 then Exit;

  Result := FLocalNames.Add(AName);
end;

function TFloriaJSBytecode.FindLocal(const AName: string): Integer;
begin
  Result := FLocalNames.IndexOf(AName);
end;

function TFloriaJSBytecode.GetLocalCount(): Integer;
begin
  Result := FLocalNames.Count;
end;

function TFloriaJSBytecode.GetLocalName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FLocalNames.Count) then
    Result := FLocalNames[AIndex]
  else
    Result := '';
end;

function TFloriaJSBytecode.AddArgument(const AName: string): Integer;
begin
  Result := FArgNames.Add(AName);
  AddLocal(AName);
end;

function TFloriaJSBytecode.GetArgumentCount(): Integer;
begin
  Result := FArgNames.Count;
end;

function TFloriaJSBytecode.GetArgumentName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FArgNames.Count) then
    Result := FArgNames[AIndex]
  else
    Result := '';
end;

function TFloriaJSBytecode.AddSubFunction(AFunc: TFloriaJSBytecode): Integer;
begin
  Result := FSubFunctions.Add(AFunc);
end;

function TFloriaJSBytecode.GetSubFunction(AIndex: Integer): TFloriaJSBytecode;
begin
  if (AIndex >= 0) and (AIndex < FSubFunctions.Count) then
    Result := TFloriaJSBytecode(FSubFunctions[AIndex])
  else
    Result := nil;
end;

function TFloriaJSBytecode.GetSubFunctionCount(): Integer;
begin
  Result := FSubFunctions.Count;
end;

function TFloriaJSBytecode.GetInstruction(AIndex: Integer): TFloriaJSInstruction;
begin
  if (AIndex >= 0) and (AIndex < FCodeCount) then
    Result := FCode[AIndex]
  else
  begin
    Result.Op := opHalt;
    Result.Imm := 0;
    Result.Line := 0;
  end;
end;

function TFloriaJSBytecode.GetInstructionCount(): Integer;
begin
  Result := FCodeCount;
end;

function TFloriaJSBytecode.Disassemble(): string;
var
  sb: TStringBuilder;
  i: Integer;
begin
  sb := TStringBuilder.Create();
  try
    if FName <> '' then
      sb.AppendLine('=== Disassembly: ' + FName + ' ===')
    else
      sb.AppendLine('=== Disassembly: <anonymous> ===');

    sb.AppendLine(Format('Locals: %d, Args: %d, Constants: %d', [FLocalNames.Count, FArgNames.Count, FConstCount]));

    for i := 0 to FCodeCount - 1 do
      sb.AppendLine(DisassembleInstruction(i));

    Result := sb.ToString();
  finally
    sb.Free();
  end;
end;

function TFloriaJSBytecode.DisassembleInstruction(AIndex: Integer): string;
var
  inst: TFloriaJSInstruction;
  opStr, comment: string;
begin
  if (AIndex < 0) or (AIndex >= FCodeCount) then
    Exit(Format('%04d  INVALID', [AIndex]));

  inst := FCode[AIndex];
  opStr := FloriaJSOpcodeToString(inst.Op);
  comment := '';

  case inst.Op of
    opConst:
      comment := '; ' + GetConstant(inst.Imm).ToString();
    opLoadLoc, opStoreLoc, opSetLoc:
      comment := '; ' + GetLocalName(inst.Imm);
    opLoadGlobal, opStoreGlobal, opSetGlobal, opLoadEnv, opStoreEnv, opGetPropNamed, opSetPropNamed, opGetPropNamedOpt:
      comment := '; ' + GetConstant(inst.Imm).ToString();
    opJump, opJumpIfFalse, opJumpIfTrue, opJumpIfNullish, opJumpIfFalseyPeek, opJumpIfTruthyPeek, opPushTry:
      comment := Format('-> %04d', [inst.Imm]);
    opCall, opCallOpt, opNew:
      comment := Format('argc: %d', [inst.Imm]);
    opClosure:
      begin
        if (inst.Imm >= 0) and (inst.Imm < FSubFunctions.Count) then
          comment := '; ' + TFloriaJSBytecode(FSubFunctions[inst.Imm]).Name;
      end;
  end;

  if comment <> '' then
    Result := Format('%04d  %-20s %-8d %s', [AIndex, opStr, inst.Imm, comment])
  else
    Result := Format('%04d  %-20s %d', [AIndex, opStr, inst.Imm]);
end;

end.
