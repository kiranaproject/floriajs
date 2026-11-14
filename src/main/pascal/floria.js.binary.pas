{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Binary data: ArrayBuffer, TypedArray, DataView  }
{                                                                          }
{   Values are stored as raw bytes. Typed arrays and DataView convert at   }
{   the JavaScript boundary; the heap owns the backing buffer.             }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                          }
{   SPDX-License-Identifier: MPL-2.0                                        }
{                                                                          }
{ ************************************************************************** }

unit floria.js.binary;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, floria.js.types, floria.js.value, floria.js.env,
  floria.js.number;

type
  TFloriaJSBinaryKind = (fbkUint8, fbkInt8, fbkUint8Clamped, fbkUint16,
    fbkInt16, fbkUint32, fbkInt32, fbkFloat32, fbkFloat64,
    fbkBigInt64, fbkBigUint64);

  TFloriaJSArrayBuffer = class(TFloriaJSObject)
  private
    FBytes: array of Byte;
    FByteLength: Integer;
    FShared: Boolean;
  public
    constructor Create(AHeap: TFloriaJSHeap; ALength: Integer; AShared: Boolean = False);
    function  GetPropertyWithReceiver(const AName: string;
      AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    function  HasOwnProperty(const AName: string): Boolean; override;
    property ByteLength: Integer read FByteLength;
    property Shared: Boolean read FShared;
    function  ByteAt(AIndex: Integer): Byte;
    procedure SetByteAt(AIndex: Integer; AValue: Byte);
    function  SliceBytes(AStart, AEnd: Integer): TFloriaJSArrayBuffer;
  end;

  TFloriaJSTypedArray = class(TFloriaJSObject)
  private
    FBuffer: TFloriaJSArrayBuffer;
    FOffset: Integer;
    FLength: Integer;
    FKind: TFloriaJSBinaryKind;
    function  ElementSize(): Integer;
    function  ReadElement(AIndex: Integer): TFloriaJSValue;
    procedure WriteElement(AIndex: Integer; const AValue: TFloriaJSValue);
  public
    constructor Create(AHeap: TFloriaJSHeap; ABuffer: TFloriaJSArrayBuffer;
      AOffset, ALength: Integer; AKind: TFloriaJSBinaryKind; AProto: TFloriaJSObject);
    function  GetPropertyWithReceiver(const AName: string;
      AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    procedure SetProperty(const AName: string; const AValue: TFloriaJSValue); override;
    function  HasOwnProperty(const AName: string): Boolean; override;
    property Buffer: TFloriaJSArrayBuffer read FBuffer;
    property Offset: Integer read FOffset;
    property Length: Integer read FLength;
    property Kind: TFloriaJSBinaryKind read FKind;
    destructor Destroy(); override;
    function  ElementSizePublic(): Integer;
    function  ReadElementPublic(AIndex: Integer): TFloriaJSValue;
    procedure WriteElementPublic(AIndex: Integer; const AValue: TFloriaJSValue);
  end;

  TFloriaJSDataView = class(TFloriaJSObject)
  private
    FBuffer: TFloriaJSArrayBuffer;
    FOffset: Integer;
    FLength: Integer;
  public
    constructor Create(AHeap: TFloriaJSHeap; ABuffer: TFloriaJSArrayBuffer;
      AOffset, ALength: Integer; AProto: TFloriaJSObject);
    function  GetPropertyWithReceiver(const AName: string;
      AReceiver: TFloriaJSObject): TFloriaJSValue; override;
    property Buffer: TFloriaJSArrayBuffer read FBuffer;
    property Offset: Integer read FOffset;
    property Length: Integer read FLength;
    destructor Destroy(); override;
  end;

procedure FloriaJSRegisterBinary(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);

implementation

function BigIntDigits(const AValue: TFloriaJSValue; AHeap: TFloriaJSHeap): string;
var
  valueOf, converted: TFloriaJSValue;
begin
  if AValue.IsBigInt() then
    Exit(AValue.StrVal);
  if AValue.IsObject() and (AHeap <> nil) then
  begin
    valueOf := AValue.AsObject().GetProperty('valueOf');
    if valueOf.IsFunction() then
    begin
      converted := AHeap.InvokeFunction(valueOf, [], AValue);
      if converted.IsBigInt() then
        Exit(converted.StrVal);
      if converted.IsNumber() then
        Exit(IntToStr(Trunc(converted.ToNumber())));
    end;
  end;
  if AValue.IsNumber() then
    Exit(IntToStr(Trunc(AValue.ToNumber())));
  if AValue.IsBoolean() then
  begin
    if AValue.ToBoolean() then Exit('1') else Exit('0');
  end;
  Result := '0';
end;

function BigIntToUInt64(const ADigits: string): UInt64;
begin
  if (ADigits <> '') and (ADigits[1] = '-') then
    Result := UInt64(StrToInt64(ADigits))
  else
  begin
    try
      Result := StrToQWord(ADigits);
    except
      Result := UInt64(StrToInt64(ADigits));
    end;
  end;
end;

function BigIntToInt64(const ADigits: string): Int64;
begin
  try
    Result := StrToInt64(ADigits);
  except
    Result := Int64(StrToQWord(ADigits));
  end;
end;

function ElementSizeOf(AKind: TFloriaJSBinaryKind): Integer;
begin
  case AKind of
    fbkUint8, fbkInt8, fbkUint8Clamped: Result := 1;
    fbkUint16, fbkInt16: Result := 2;
    fbkUint32, fbkInt32, fbkFloat32: Result := 4;
    fbkFloat64, fbkBigInt64, fbkBigUint64: Result := 8;
  else
    Result := 1;
  end;
end;

{ TFloriaJSArrayBuffer }

constructor TFloriaJSArrayBuffer.Create(AHeap: TFloriaJSHeap; ALength: Integer; AShared: Boolean);
begin
  inherited Create(nil);
  Heap := AHeap;
  if ALength < 0 then ALength := 0;
  FByteLength := ALength;
  FShared := AShared;
  SetLength(FBytes, ALength);
end;

function TFloriaJSArrayBuffer.ByteAt(AIndex: Integer): Byte;
begin
  Result := FBytes[AIndex];
end;

procedure TFloriaJSArrayBuffer.SetByteAt(AIndex: Integer; AValue: Byte);
begin
  FBytes[AIndex] := AValue;
end;

function TFloriaJSArrayBuffer.SliceBytes(AStart, AEnd: Integer): TFloriaJSArrayBuffer;
var
  i: Integer;
begin
  Result := TFloriaJSArrayBuffer.Create(Heap, AEnd - AStart, FShared);
  for i := AStart to AEnd - 1 do
    Result.SetByteAt(i - AStart, ByteAt(i));
end;

function TFloriaJSArrayBuffer.GetPropertyWithReceiver(const AName: string;
  AReceiver: TFloriaJSObject): TFloriaJSValue;
begin
  if AName = 'byteLength' then
    Exit(JSMakeNumber(FByteLength));
  Result := inherited GetPropertyWithReceiver(AName, AReceiver);
end;

function TFloriaJSArrayBuffer.HasOwnProperty(const AName: string): Boolean;
begin
  Result := (AName = 'byteLength') or inherited HasOwnProperty(AName);
end;

{ TFloriaJSTypedArray }

constructor TFloriaJSTypedArray.Create(AHeap: TFloriaJSHeap;
  ABuffer: TFloriaJSArrayBuffer; AOffset, ALength: Integer;
  AKind: TFloriaJSBinaryKind; AProto: TFloriaJSObject);
begin
  inherited Create(AProto);
  Heap := AHeap;
  FBuffer := ABuffer;
  FOffset := AOffset;
  FLength := ALength;
  FKind := AKind;
  if FBuffer <> nil then
    FBuffer.Retain();
end;

destructor TFloriaJSTypedArray.Destroy();
begin
  if FBuffer <> nil then
  begin
    FBuffer.Release();
    FBuffer := nil;
  end;
  inherited Destroy();
end;

function TFloriaJSTypedArray.ElementSize(): Integer;
begin
  Result := ElementSizeOf(FKind);
end;

function TFloriaJSTypedArray.ElementSizePublic(): Integer;
begin
  Result := ElementSize();
end;

function TFloriaJSTypedArray.ReadElement(AIndex: Integer): TFloriaJSValue;
var
  pos: Integer;
  b: Byte;
  w: Word;
  dw: LongWord;
  s: Single;
  d: Double;
  i: Integer;
  raw64: UInt64;
begin
  if (AIndex < 0) or (AIndex >= FLength) or (FBuffer = nil) then
    Exit(JSMakeUndefined());
  pos := FOffset + AIndex * ElementSize();
  case FKind of
    fbkUint8, fbkUint8Clamped:
      Result := JSMakeNumber(FBuffer.ByteAt(pos));
    fbkInt8:
      begin
        b := FBuffer.ByteAt(pos);
        Result := JSMakeNumber(ShortInt(b));
      end;
    fbkUint16:
      begin
        w := 0;
        for i := 0 to 1 do w := w or (Word(FBuffer.ByteAt(pos + i)) shl (i * 8));
        Result := JSMakeNumber(w);
      end;
    fbkInt16:
      begin
        w := 0;
        for i := 0 to 1 do w := w or (Word(FBuffer.ByteAt(pos + i)) shl (i * 8));
        Result := JSMakeNumber(SmallInt(w));
      end;
    fbkUint32:
      begin
        dw := 0;
        for i := 0 to 3 do dw := dw or (LongWord(FBuffer.ByteAt(pos + i)) shl (i * 8));
        Result := JSMakeNumber(dw);
      end;
    fbkInt32:
      begin
        dw := 0;
        for i := 0 to 3 do dw := dw or (LongWord(FBuffer.ByteAt(pos + i)) shl (i * 8));
        Result := JSMakeNumber(LongInt(dw));
      end;
    fbkFloat32:
      begin
        dw := 0;
        for i := 0 to 3 do dw := dw or (LongWord(FBuffer.ByteAt(pos + i)) shl (i * 8));
        Move(dw, s, 4);
        Result := JSMakeNumber(s);
      end;
    fbkFloat64:
      begin
        raw64 := 0;
        for i := 0 to 7 do raw64 := raw64 or (UInt64(FBuffer.ByteAt(pos + i)) shl (i * 8));
        Move(raw64, d, 8);
        Result := JSMakeNumber(d);
      end;
    fbkBigInt64:
      begin
        raw64 := 0;
        for i := 0 to 7 do raw64 := raw64 or (UInt64(FBuffer.ByteAt(pos + i)) shl (i * 8));
        Result := JSMakeBigInt(IntToStr(Int64(raw64)));
      end;
    fbkBigUint64:
      begin
        raw64 := 0;
        for i := 0 to 7 do raw64 := raw64 or (UInt64(FBuffer.ByteAt(pos + i)) shl (i * 8));
        Result := JSMakeBigInt(UIntToStr(raw64));
      end;
  else
    Result := JSMakeUndefined();
  end;
end;

function TFloriaJSTypedArray.ReadElementPublic(AIndex: Integer): TFloriaJSValue;
begin
  Result := ReadElement(AIndex);
end;

procedure TFloriaJSTypedArray.WriteElement(AIndex: Integer;
  const AValue: TFloriaJSValue);
var
  pos, i32: Integer;
  num, clamped: Double;
  b: Byte;
  w: Word;
  dw: LongWord;
  s: Single;
  d: Double;
  i: Integer;
  dw64: UInt64;
begin
  if (AIndex < 0) or (AIndex >= FLength) or (FBuffer = nil) then
    Exit;
  pos := FOffset + AIndex * ElementSize();
  num := AValue.ToNumber();
  case FKind of
    fbkUint8:
      FBuffer.SetByteAt(pos, Byte(Trunc(num) and $FF));
    fbkInt8:
      FBuffer.SetByteAt(pos, Byte(ShortInt(Trunc(num) and $FF)));
    fbkUint8Clamped:
      begin
        if IsNaN(num) or (num <= 0) then
          clamped := 0
        else if num >= 255 then
          clamped := 255
        else
          clamped := Floor(num + 0.5);
        FBuffer.SetByteAt(pos, Byte(Trunc(clamped)));
      end;
    fbkUint16:
      begin
        w := Word(Trunc(num) and $FFFF);
        for i := 0 to 1 do FBuffer.SetByteAt(pos + i, Byte((w shr (i * 8)) and $FF));
      end;
    fbkInt16:
      begin
        w := Word(SmallInt(Trunc(num) and $FFFF));
        for i := 0 to 1 do FBuffer.SetByteAt(pos + i, Byte((w shr (i * 8)) and $FF));
      end;
    fbkUint32:
      begin
        dw := LongWord(Trunc(num));
        for i := 0 to 3 do FBuffer.SetByteAt(pos + i, Byte((dw shr (i * 8)) and $FF));
      end;
    fbkInt32:
      begin
        i32 := LongInt(Trunc(num));
        for i := 0 to 3 do FBuffer.SetByteAt(pos + i, Byte((LongWord(i32) shr (i * 8)) and $FF));
      end;
    fbkFloat32:
      begin
        s := num;
        dw := 0;
        Move(s, dw, 4);
        for i := 0 to 3 do FBuffer.SetByteAt(pos + i, Byte((dw shr (i * 8)) and $FF));
      end;
    fbkFloat64:
      begin
        d := num;
        dw64 := 0;
        Move(d, dw64, 8);
        for i := 0 to 7 do FBuffer.SetByteAt(pos + i, Byte((dw64 shr (i * 8)) and $FF));
      end;
    fbkBigInt64:
      begin
        dw64 := BigIntToUInt64(BigIntDigits(AValue, Heap));
        for i := 0 to 7 do
          FBuffer.SetByteAt(pos + i, Byte((dw64 shr (i * 8)) and $FF));
      end;
    fbkBigUint64:
      begin
        dw64 := BigIntToUInt64(BigIntDigits(AValue, Heap));
        for i := 0 to 7 do
          FBuffer.SetByteAt(pos + i, Byte((dw64 shr (i * 8)) and $FF));
      end;
  end;
end;

procedure TFloriaJSTypedArray.WriteElementPublic(AIndex: Integer;
  const AValue: TFloriaJSValue);
begin
  WriteElement(AIndex, AValue);
end;

function TFloriaJSTypedArray.GetPropertyWithReceiver(const AName: string;
  AReceiver: TFloriaJSObject): TFloriaJSValue;
var
  idx: Integer;
begin
  if AName = 'length' then Exit(JSMakeNumber(FLength));
  if AName = 'byteLength' then Exit(JSMakeNumber(FLength * ElementSize()));
  if AName = 'byteOffset' then Exit(JSMakeNumber(FOffset));
  if AName = 'buffer' then Exit(JSMakeObject(FBuffer));
  if TryStrToInt(AName, idx) and (idx >= 0) and (idx < FLength) then
    Exit(ReadElement(idx));
  Result := inherited GetPropertyWithReceiver(AName, AReceiver);
end;

procedure TFloriaJSTypedArray.SetProperty(const AName: string;
  const AValue: TFloriaJSValue);
var
  idx: Integer;
begin
  if TryStrToInt(AName, idx) and (idx >= 0) and (idx < FLength) then
  begin
    WriteElement(idx, AValue);
    Exit;
  end;
  inherited SetProperty(AName, AValue);
end;

function TFloriaJSTypedArray.HasOwnProperty(const AName: string): Boolean;
var
  idx: Integer;
begin
  if (AName = 'length') or (AName = 'byteLength') or (AName = 'byteOffset') or
     (AName = 'buffer') then
    Exit(True);
  if TryStrToInt(AName, idx) and (idx >= 0) and (idx < FLength) then
    Exit(True);
  Result := inherited HasOwnProperty(AName);
end;

{ TFloriaJSDataView }

constructor TFloriaJSDataView.Create(AHeap: TFloriaJSHeap;
  ABuffer: TFloriaJSArrayBuffer; AOffset, ALength: Integer; AProto: TFloriaJSObject);
begin
  inherited Create(AProto);
  Heap := AHeap;
  FBuffer := ABuffer;
  FOffset := AOffset;
  FLength := ALength;
  if FBuffer <> nil then FBuffer.Retain();
end;

destructor TFloriaJSDataView.Destroy();
begin
  if FBuffer <> nil then
  begin
    FBuffer.Release();
    FBuffer := nil;
  end;
  inherited Destroy();
end;

function TFloriaJSDataView.GetPropertyWithReceiver(const AName: string;
  AReceiver: TFloriaJSObject): TFloriaJSValue;
begin
  if AName = 'byteLength' then Exit(JSMakeNumber(FLength));
  if AName = 'byteOffset' then Exit(JSMakeNumber(FOffset));
  if AName = 'buffer' then Exit(JSMakeObject(FBuffer));
  Result := inherited GetPropertyWithReceiver(AName, AReceiver);
end;

{ Reader/writer helpers shared by the DataView methods. }

type
  TAtomicsWaiter = record
    Buffer: TFloriaJSArrayBuffer;
    Index: Integer;
    Promise: TFloriaJSPromise;
  end;

var
  GAtomicsWaiters: array of TAtomicsWaiter;

type
  TFloriaJSBinaryHelper = class
  private
    FHeap: TFloriaJSHeap;
    function  BufferArg(const AThis: TFloriaJSValue): TFloriaJSArrayBuffer;
    function  OffsetArg(const AArgs: array of TFloriaJSValue; AIndex,
      ADefault: Integer): Integer;
    function  BigEndianArg(const AArgs: array of TFloriaJSValue;
      AIndex: Integer): Boolean;
    procedure CheckRange(ABuffer: TFloriaJSArrayBuffer; AOffset, ACount: Integer);
    function  ReadRaw(ABuffer: TFloriaJSArrayBuffer; AOffset, ASize: Integer;
      ABigEndian: Boolean): UInt64;
    procedure WriteRaw(ABuffer: TFloriaJSArrayBuffer; AOffset, ASize: Integer;
      AValue: UInt64; ABigEndian: Boolean);
    function  AtomicsArray(const AArgs: array of TFloriaJSValue;
      out AIndex: Integer): TFloriaJSTypedArray;
  public
    constructor Create(AHeap: TFloriaJSHeap);

    function  ArrayBufferCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  SharedArrayBufferCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  ArrayBufferSlice(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  ArrayBufferIsView(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;

    function  AtomicsLoad(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AtomicsStore(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AtomicsAdd(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AtomicsSub(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AtomicsAnd_(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AtomicsOr_(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AtomicsXor_(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AtomicsExchange(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AtomicsCompareExchange(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AtomicsIsLockFree(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AtomicsWait(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AtomicsWaitAsync(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  AtomicsNotify(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;

    function  TypedArrayCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewCtor(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;

    function  TypedSet(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  TypedSubarray(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  TypedSlice(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  TypedFill(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;

    function  DataViewGetInt8(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewGetUint8(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewGetInt16(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewGetUint16(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewGetInt32(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewGetUint32(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewGetFloat32(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewGetFloat64(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewSetInt8(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewSetUint8(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewSetInt16(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewSetUint16(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewSetInt32(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewSetUint32(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewSetFloat32(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
    function  DataViewSetFloat64(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
  end;

constructor TFloriaJSBinaryHelper.Create(AHeap: TFloriaJSHeap);
begin
  inherited Create();
  FHeap := AHeap;
end;

function TFloriaJSBinaryHelper.BufferArg(const AThis: TFloriaJSValue): TFloriaJSArrayBuffer;
begin
  Result := nil;
  if not AThis.IsObject() then Exit;
  if AThis.ObjVal is TFloriaJSArrayBuffer then
    Result := TFloriaJSArrayBuffer(AThis.ObjVal)
  else if AThis.ObjVal is TFloriaJSTypedArray then
    Result := TFloriaJSTypedArray(AThis.ObjVal).Buffer
  else if AThis.ObjVal is TFloriaJSDataView then
    Result := TFloriaJSDataView(AThis.ObjVal).Buffer;
end;

function TFloriaJSBinaryHelper.OffsetArg(const AArgs: array of TFloriaJSValue;
  AIndex, ADefault: Integer): Integer;
begin
  if AIndex > High(AArgs) then Exit(ADefault);
  Result := Trunc(AArgs[AIndex].ToNumber());
end;

function TFloriaJSBinaryHelper.BigEndianArg(
  const AArgs: array of TFloriaJSValue; AIndex: Integer): Boolean;
begin
  if AIndex > High(AArgs) then Exit(False);
  Result := AArgs[AIndex].ToBoolean();
end;

procedure TFloriaJSBinaryHelper.CheckRange(ABuffer: TFloriaJSArrayBuffer;
  AOffset, ACount: Integer);
begin
  if (ABuffer = nil) or (AOffset < 0) or (ACount < 0) or
     (AOffset + ACount > ABuffer.ByteLength) then
    raise EFloriaJSThrow.Create(JSMakeObject(
      FHeap.NewError('RangeError', 'Offset is outside the bounds of the DataView')));
end;

function TFloriaJSBinaryHelper.ReadRaw(ABuffer: TFloriaJSArrayBuffer;
  AOffset, ASize: Integer; ABigEndian: Boolean): UInt64;
var
  i, src: Integer;
begin
  CheckRange(ABuffer, AOffset, ASize);
  Result := 0;
  for i := 0 to ASize - 1 do
  begin
    if ABigEndian then
      src := AOffset + i
    else
      src := AOffset + ASize - 1 - i;
    Result := (Result shl 8) or ABuffer.ByteAt(src);
  end;
end;

procedure TFloriaJSBinaryHelper.WriteRaw(ABuffer: TFloriaJSArrayBuffer;
  AOffset, ASize: Integer; AValue: UInt64; ABigEndian: Boolean);
var
  i, dst: Integer;
begin
  CheckRange(ABuffer, AOffset, ASize);
  for i := 0 to ASize - 1 do
  begin
    if ABigEndian then
      dst := AOffset + ASize - 1 - i
    else
      dst := AOffset + i;
    ABuffer.SetByteAt(dst, Byte((AValue shr (i * 8)) and $FF));
  end;
end;

function TFloriaJSBinaryHelper.ArrayBufferCtor(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  bufLen: Integer;
  buffer: TFloriaJSArrayBuffer;
begin
  if Length(AArgs) = 0 then
    bufLen := 0
  else
    bufLen := Trunc(AArgs[0].ToNumber());
  if bufLen < 0 then
    raise EFloriaJSThrow.Create(JSMakeObject(
      FHeap.NewError('RangeError', 'Invalid array buffer length')));
  buffer := TFloriaJSArrayBuffer.Create(FHeap, bufLen);
  buffer.Prototype := FHeap.GetPrototypeFromConstructor(
    FHeap.CurrentNewTarget, 'ArrayBuffer');
  Result := JSMakeObject(FHeap.Track(buffer));
end;

function TFloriaJSBinaryHelper.SharedArrayBufferCtor(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  bufLen: Integer;
  buffer: TFloriaJSArrayBuffer;
begin
  if Length(AArgs) = 0 then
    bufLen := 0
  else
    bufLen := Trunc(AArgs[0].ToNumber());
  if bufLen < 0 then
    raise EFloriaJSThrow.Create(JSMakeObject(
      FHeap.NewError('RangeError', 'Invalid array buffer length')));
  buffer := TFloriaJSArrayBuffer.Create(FHeap, bufLen, True);
  buffer.Prototype := FHeap.GetPrototypeFromConstructor(
    FHeap.CurrentNewTarget, 'SharedArrayBuffer');
  Result := JSMakeObject(FHeap.Track(buffer));
end;

function TFloriaJSBinaryHelper.AtomicsArray(
  const AArgs: array of TFloriaJSValue; out AIndex: Integer): TFloriaJSTypedArray;
var
  index: Integer;
  d: Double;
begin
  Result := nil;
  AIndex := 0;
  if (Length(AArgs) < 2) or not AArgs[0].IsObject() or
     not (AArgs[0].ObjVal is TFloriaJSTypedArray) then
    raise EFloriaJSThrow.Create(JSMakeObject(
      FHeap.NewError('TypeError', 'Atomics requires an integer typed array')));
  Result := TFloriaJSTypedArray(AArgs[0].ObjVal);
  if Result.Kind in [fbkFloat32, fbkFloat64] then
    raise EFloriaJSThrow.Create(JSMakeObject(
      FHeap.NewError('TypeError', 'Atomics requires an integer typed array')));
  d := AArgs[1].ToNumber();
  if IsNaN(d) then
    d := 0;
  if IsInfinite(d) then
    raise EFloriaJSThrow.Create(JSMakeObject(
      FHeap.NewError('RangeError', 'Invalid atomic index')));
  index := Trunc(d);
  if (index < 0) or (index >= Result.Length) then
    raise EFloriaJSThrow.Create(JSMakeObject(
      FHeap.NewError('RangeError', 'Invalid atomic index')));
  AIndex := index;
end;

function AtomicsEqual(const A, B: TFloriaJSValue): Boolean;
begin
  if A.IsBigInt() or B.IsBigInt() then
    Result := A.ToString() = B.ToString()
  else
    Result := A.ToNumber() = B.ToNumber();
end;

function AtomicsNormalize(AArr: TFloriaJSTypedArray;
  const AValue: TFloriaJSValue): Double;
var
  d: Double;
begin
  d := AValue.ToNumber();
  if IsNaN(d) then
    d := 0;
  case AArr.Kind of
    fbkUint8, fbkUint8Clamped: Result := Byte(Trunc(d));
    fbkInt8: Result := ShortInt(Byte(Trunc(d)));
    fbkUint16: Result := Word(Trunc(d));
    fbkInt16: Result := SmallInt(Word(Trunc(d)));
    fbkUint32: Result := LongWord(Trunc(d));
    fbkInt32: Result := LongInt(LongWord(Trunc(d)));
  else
    Result := d;
  end;
end;

function AtomicsEqualForArray(AArr: TFloriaJSTypedArray;
  const A, B: TFloriaJSValue): Boolean;
begin
  if AArr.Kind = fbkBigUint64 then
    Result := BigIntToUInt64(A.StrVal) = BigIntToUInt64(B.StrVal)
  else if AArr.Kind = fbkBigInt64 then
    Result := BigIntToInt64(A.StrVal) = BigIntToInt64(B.StrVal)
  else
    Result := AtomicsNormalize(AArr, A) = AtomicsNormalize(AArr, B);
end;

function TFloriaJSBinaryHelper.AtomicsLoad(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  index: Integer;
  arr: TFloriaJSTypedArray;
begin
  arr := AtomicsArray(AArgs, index);
  JSAtomicsYield();
  Result := arr.ReadElementPublic(index);
end;

function TFloriaJSBinaryHelper.AtomicsStore(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  index: Integer;
  arr: TFloriaJSTypedArray;
  value: TFloriaJSValue;
  d: Double;
begin
  arr := AtomicsArray(AArgs, index);
  if Length(AArgs) > 2 then value := AArgs[2] else value := JSMakeUndefined();
  arr.WriteElementPublic(index, value);
  if arr.Kind in [fbkBigInt64, fbkBigUint64] then
    Result := JSMakeBigInt(BigIntDigits(value, FHeap))
  else
  begin
    d := value.ToNumber();
    if IsNaN(d) then
      d := 0;
    Result := JSMakeNumber(Trunc(d));
  end;
end;

function TFloriaJSBinaryHelper.AtomicsAdd(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  index: Integer;
  arr: TFloriaJSTypedArray;
  oldValue, newValue: TFloriaJSValue;
begin
  arr := AtomicsArray(AArgs, index);
  oldValue := arr.ReadElementPublic(index);
  if arr.Kind in [fbkBigInt64, fbkBigUint64] then
    newValue := JSMakeBigInt(BigIntAdd(oldValue.StrVal, AArgs[2].StrVal))
  else
    newValue := JSMakeNumber(oldValue.ToNumber() + AArgs[2].ToNumber());
  arr.WriteElementPublic(index, newValue);
  Result := oldValue;
end;

function TFloriaJSBinaryHelper.AtomicsSub(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  index: Integer;
  arr: TFloriaJSTypedArray;
  oldValue, newValue: TFloriaJSValue;
begin
  arr := AtomicsArray(AArgs, index);
  oldValue := arr.ReadElementPublic(index);
  if arr.Kind in [fbkBigInt64, fbkBigUint64] then
    newValue := JSMakeBigInt(BigIntSub(oldValue.StrVal, AArgs[2].StrVal))
  else
    newValue := JSMakeNumber(oldValue.ToNumber() - AArgs[2].ToNumber());
  arr.WriteElementPublic(index, newValue);
  Result := oldValue;
end;

function TFloriaJSBinaryHelper.AtomicsAnd_(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  index: Integer;
  arr: TFloriaJSTypedArray;
  oldValue: TFloriaJSValue;
begin
  arr := AtomicsArray(AArgs, index);
  oldValue := arr.ReadElementPublic(index);
  if arr.Kind in [fbkBigInt64, fbkBigUint64] then
    arr.WriteElementPublic(index, JSMakeBigInt(IntToStr(
      BigIntToInt64(oldValue.StrVal) and BigIntToInt64(AArgs[2].StrVal))))
  else
    arr.WriteElementPublic(index, JSMakeNumber(
      Int64(Trunc(oldValue.ToNumber())) and Int64(Trunc(AArgs[2].ToNumber()))));
  Result := oldValue;
end;

function TFloriaJSBinaryHelper.AtomicsOr_(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  index: Integer;
  arr: TFloriaJSTypedArray;
  oldValue: TFloriaJSValue;
begin
  arr := AtomicsArray(AArgs, index);
  oldValue := arr.ReadElementPublic(index);
  if arr.Kind in [fbkBigInt64, fbkBigUint64] then
    arr.WriteElementPublic(index, JSMakeBigInt(IntToStr(
      BigIntToInt64(oldValue.StrVal) or BigIntToInt64(AArgs[2].StrVal))))
  else
    arr.WriteElementPublic(index, JSMakeNumber(
      Int64(Trunc(oldValue.ToNumber())) or Int64(Trunc(AArgs[2].ToNumber()))));
  Result := oldValue;
end;

function TFloriaJSBinaryHelper.AtomicsXor_(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  index: Integer;
  arr: TFloriaJSTypedArray;
  oldValue: TFloriaJSValue;
begin
  arr := AtomicsArray(AArgs, index);
  oldValue := arr.ReadElementPublic(index);
  if arr.Kind in [fbkBigInt64, fbkBigUint64] then
    arr.WriteElementPublic(index, JSMakeBigInt(IntToStr(
      BigIntToInt64(oldValue.StrVal) xor BigIntToInt64(AArgs[2].StrVal))))
  else
    arr.WriteElementPublic(index, JSMakeNumber(
      Int64(Trunc(oldValue.ToNumber())) xor Int64(Trunc(AArgs[2].ToNumber()))));
  Result := oldValue;
end;

function TFloriaJSBinaryHelper.AtomicsExchange(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  index: Integer;
  arr: TFloriaJSTypedArray;
  oldValue: TFloriaJSValue;
begin
  arr := AtomicsArray(AArgs, index);
  oldValue := arr.ReadElementPublic(index);
  arr.WriteElementPublic(index, AArgs[2]);
  Result := oldValue;
end;

function TFloriaJSBinaryHelper.AtomicsCompareExchange(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  index: Integer;
  arr: TFloriaJSTypedArray;
  oldValue: TFloriaJSValue;
begin
  arr := AtomicsArray(AArgs, index);
  oldValue := arr.ReadElementPublic(index);
  if AtomicsEqualForArray(arr, oldValue, AArgs[2]) then
    arr.WriteElementPublic(index, AArgs[3]);
  Result := oldValue;
end;

function TFloriaJSBinaryHelper.AtomicsIsLockFree(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  size: Integer;
begin
  size := 0;
  if Length(AArgs) > 0 then
    size := Trunc(AArgs[0].ToNumber());
  Result := JSMakeBoolean(size in [1, 2, 4, 8]);
end;

function TFloriaJSBinaryHelper.AtomicsWait(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  index: Integer;
  arr: TFloriaJSTypedArray;
  current: TFloriaJSValue;
begin
  arr := AtomicsArray(AArgs, index);
  if (arr.Buffer = nil) or (not arr.Buffer.Shared) then
    raise EFloriaJSThrow.Create(JSMakeObject(
      FHeap.NewError('TypeError', 'Atomics.wait requires a SharedArrayBuffer')));
  current := arr.ReadElementPublic(index);
  if not AtomicsEqualForArray(arr, current, AArgs[2]) then
    Exit(JSMakeString('not-equal'));
  { A single-threaded runtime has no other agent to notify this waiter. }
  Result := JSMakeString('timed-out');
end;

function TFloriaJSBinaryHelper.AtomicsWaitAsync(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  index: Integer;
  arr: TFloriaJSTypedArray;
  current, resultObj, promiseVal: TFloriaJSValue;
  promise: TFloriaJSPromise;
  timeout: Double;
  infinite: Boolean;
begin
  arr := AtomicsArray(AArgs, index);
  if (arr.Buffer = nil) or (not arr.Buffer.Shared) then
    raise EFloriaJSThrow.Create(JSMakeObject(
      FHeap.NewError('TypeError', 'Atomics.waitAsync requires a SharedArrayBuffer')));
  current := arr.ReadElementPublic(index);
  resultObj := JSMakeObject(FHeap.NewObject(FHeap.GetObjectPrototype()));
  if not AtomicsEqualForArray(arr, current, AArgs[2]) then
  begin
    resultObj.AsObject().SetProperty('async', JSMakeBoolean(False));
    resultObj.AsObject().SetProperty('value', JSMakeString('not-equal'));
    Exit(resultObj);
  end;

  infinite := False;
  timeout := 0;
  if Length(AArgs) > 3 then
  begin
    if AArgs[3].IsUndefined() then
      infinite := True
    else
    begin
      timeout := AArgs[3].ToNumber();
      if IsNaN(timeout) then
        infinite := True
      else if timeout < 0 then
        timeout := 0;
    end;
  end
  else
    infinite := True;

  if (not infinite) and (timeout = 0) then
  begin
    resultObj.AsObject().SetProperty('async', JSMakeBoolean(False));
    resultObj.AsObject().SetProperty('value', JSMakeString('timed-out'));
    Exit(resultObj);
  end;

  promise := FHeap.NewPromise();
  if infinite then
  begin
    SetLength(GAtomicsWaiters, Length(GAtomicsWaiters) + 1);
    GAtomicsWaiters[High(GAtomicsWaiters)].Buffer := arr.Buffer;
    GAtomicsWaiters[High(GAtomicsWaiters)].Index := index;
    GAtomicsWaiters[High(GAtomicsWaiters)].Promise := promise;
  end
  else
    promise.Fulfill(JSMakeString('timed-out'));

  resultObj.AsObject().SetProperty('async', JSMakeBoolean(True));
  resultObj.AsObject().SetProperty('value', JSMakePromise(promise));
  Result := resultObj;
end;

function TFloriaJSBinaryHelper.AtomicsNotify(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  index, i, count, limit: Integer;
  arr: TFloriaJSTypedArray;
begin
  arr := AtomicsArray(AArgs, index);
  count := 0;
  if Length(AArgs) > 2 then
    limit := Trunc(AArgs[2].ToNumber())
  else
    limit := High(Integer);
  if limit < 0 then
    limit := 0;
  for i := High(GAtomicsWaiters) downto 0 do
  begin
    if (GAtomicsWaiters[i].Buffer = arr.Buffer) and
       (GAtomicsWaiters[i].Index = index) then
    begin
      if GAtomicsWaiters[i].Promise <> nil then
        GAtomicsWaiters[i].Promise.Fulfill(JSMakeString('ok'));
      GAtomicsWaiters[i] := GAtomicsWaiters[High(GAtomicsWaiters)];
      SetLength(GAtomicsWaiters, Length(GAtomicsWaiters) - 1);
      Inc(count);
      if count >= limit then
        Break;
    end;
  end;
  Result := JSMakeNumber(count);
end;

function TFloriaJSBinaryHelper.ArrayBufferSlice(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  start, finish: Integer;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSArrayBuffer) then
    Exit(JSMakeUndefined());
  buffer := TFloriaJSArrayBuffer(AThis.ObjVal);
  start := OffsetArg(AArgs, 0, 0);
  finish := OffsetArg(AArgs, 1, buffer.ByteLength);
  if start < 0 then start := buffer.ByteLength + start;
  if finish < 0 then finish := buffer.ByteLength + finish;
  if start < 0 then start := 0;
  if finish < start then finish := start;
  if finish > buffer.ByteLength then finish := buffer.ByteLength;
  buffer := buffer.SliceBytes(start, finish);
  if AThis.IsObject() then
    buffer.Prototype := AThis.AsObject().Prototype;
  Result := JSMakeObject(FHeap.Track(buffer));
end;

function TFloriaJSBinaryHelper.ArrayBufferIsView(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  Result := JSMakeBoolean((Length(AArgs) > 0) and AArgs[0].IsObject() and
    ((AArgs[0].ObjVal is TFloriaJSTypedArray) or
     (AArgs[0].ObjVal is TFloriaJSDataView)));
end;

function TFloriaJSBinaryHelper.TypedArrayCtor(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  kind: TFloriaJSBinaryKind;
  proto: TFloriaJSObject;
  viewLen, offset, size, i, count: Integer;
  buffer: TFloriaJSArrayBuffer;
  resultArray: TFloriaJSTypedArray;
  sourceObj: TFloriaJSObject;
  sourceVal: TFloriaJSValue;
  arg0: TFloriaJSValue;
begin
  { The active constructor carries the element kind. The newTarget realm
    selects the default prototype when the newTarget has no object
    `prototype`. }
  kind := fbkUint8;
  proto := nil;
  if FHeap.CurrentConstructor <> nil then
  begin
    if FHeap.CurrentConstructor.HasProperty('__kind') then
      kind := TFloriaJSBinaryKind(Trunc(
        FHeap.CurrentConstructor.GetProperty('__kind').ToNumber()));
    if FHeap.CurrentConstructor.IntrinsicName <> '' then
      proto := FHeap.GetPrototypeFromConstructor(FHeap.CurrentNewTarget,
        FHeap.CurrentConstructor.IntrinsicName);
  end
  else if AThis.IsFunction() then
  begin
    if AThis.AsFunction().HasProperty('__kind') then
      kind := TFloriaJSBinaryKind(Trunc(AThis.AsFunction().GetProperty('__kind').ToNumber()));
    if AThis.AsFunction().HasProperty('prototype') then
      proto := AThis.AsFunction().GetProperty('prototype').AsObject();
  end
  else if AThis.IsObject() then
  begin
    { Constructing passes the new instance as `this`; its prototype identifies
      the typed-array kind. }
    proto := AThis.AsObject().Prototype;
    if (proto <> nil) and proto.HasProperty('__kind') then
      kind := TFloriaJSBinaryKind(Trunc(proto.GetProperty('__kind').ToNumber()));
  end;
  size := ElementSizeOf(kind);

  arg0 := JSMakeUndefined();
  if Length(AArgs) > 0 then
    arg0 := AArgs[0];

  if arg0.IsObject() and (arg0.ObjVal is TFloriaJSArrayBuffer) then
  begin
    buffer := TFloriaJSArrayBuffer(arg0.ObjVal);
    offset := OffsetArg(AArgs, 1, 0);
    if Length(AArgs) > 2 then
      viewLen := Trunc(AArgs[2].ToNumber())
    else
      viewLen := (buffer.ByteLength - offset) div size;
    if (offset < 0) or (viewLen < 0) or
       (offset + viewLen * size > buffer.ByteLength) then
      raise EFloriaJSThrow.Create(JSMakeObject(
        FHeap.NewError('RangeError', 'Invalid typed array length')));
    resultArray := TFloriaJSTypedArray.Create(FHeap, buffer, offset, viewLen, kind, proto);
    Exit(JSMakeObject(FHeap.Track(resultArray)));
  end;

  if arg0.IsObject() and (arg0.ObjVal is TFloriaJSTypedArray) then
  begin
    count := TFloriaJSTypedArray(arg0.ObjVal).Length;
    buffer := TFloriaJSArrayBuffer.Create(FHeap, count * size);
    FHeap.Track(buffer);
    resultArray := TFloriaJSTypedArray.Create(FHeap, buffer, 0, count, kind, proto);
    resultArray.SetProperty('__keep', JSMakeObject(buffer));
    for i := 0 to count - 1 do
      resultArray.WriteElementPublic(i, TFloriaJSTypedArray(arg0.ObjVal).ReadElementPublic(i));
    Exit(JSMakeObject(FHeap.Track(resultArray)));
  end;

  if arg0.IsObject() then
  begin
    sourceObj := arg0.AsObject();
    if sourceObj.HasProperty('length') then
      count := Trunc(sourceObj.GetProperty('length').ToNumber())
    else
      count := 0;
    buffer := TFloriaJSArrayBuffer.Create(FHeap, count * size);
    FHeap.Track(buffer);
    resultArray := TFloriaJSTypedArray.Create(FHeap, buffer, 0, count, kind, proto);
    resultArray.SetProperty('__keep', JSMakeObject(buffer));
    for i := 0 to count - 1 do
    begin
      sourceVal := sourceObj.GetProperty(IntToStr(i));
      resultArray.WriteElementPublic(i, sourceVal);
    end;
    Exit(JSMakeObject(FHeap.Track(resultArray)));
  end;

  if arg0.IsUndefined() then
    viewLen := 0
  else
    viewLen := Trunc(arg0.ToNumber());
  if viewLen < 0 then
    raise EFloriaJSThrow.Create(JSMakeObject(
      FHeap.NewError('RangeError', 'Invalid typed array length')));
  buffer := TFloriaJSArrayBuffer.Create(FHeap, viewLen * size);
  FHeap.Track(buffer);
  resultArray := TFloriaJSTypedArray.Create(FHeap, buffer, 0, viewLen, kind, proto);
  resultArray.SetProperty('__keep', JSMakeObject(buffer));
  Result := JSMakeObject(FHeap.Track(resultArray));
end;

function TFloriaJSBinaryHelper.DataViewCtor(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset, viewLen, size: Integer;
  proto: TFloriaJSObject;
begin
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() or
     not (AArgs[0].ObjVal is TFloriaJSArrayBuffer) then
    raise EFloriaJSThrow.Create(JSMakeObject(
      FHeap.NewError('TypeError', 'First argument to DataView constructor must be an ArrayBuffer')));
  buffer := TFloriaJSArrayBuffer(AArgs[0].ObjVal);
  offset := OffsetArg(AArgs, 1, 0);
  if Length(AArgs) > 2 then
    size := Trunc(AArgs[2].ToNumber())
  else
    size := buffer.ByteLength - offset;
  if (offset < 0) or (size < 0) or (offset + size > buffer.ByteLength) then
    raise EFloriaJSThrow.Create(JSMakeObject(
      FHeap.NewError('RangeError', 'Invalid DataView length')));
  proto := FHeap.GetPrototypeFromConstructor(
    FHeap.CurrentNewTarget, 'DataView');
  Result := JSMakeObject(FHeap.Track(TFloriaJSDataView.Create(FHeap, buffer, offset, size, proto)));
end;

function TFloriaJSBinaryHelper.TypedSet(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: TFloriaJSTypedArray;
  i, offset, count: Integer;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSTypedArray) then
    Exit(JSMakeUndefined());
  target := TFloriaJSTypedArray(AThis.ObjVal);
  offset := OffsetArg(AArgs, 1, 0);
  if (Length(AArgs) = 0) or not AArgs[0].IsObject() then
    Exit(JSMakeUndefined());
  count := Trunc(AArgs[0].AsObject().GetProperty('length').ToNumber());
  for i := 0 to count - 1 do
    target.WriteElementPublic(offset + i, AArgs[0].AsObject().GetProperty(IntToStr(i)));
  Result := JSMakeUndefined();
end;

function TFloriaJSBinaryHelper.TypedSubarray(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  source: TFloriaJSTypedArray;
  start, finish: Integer;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSTypedArray) then
    Exit(JSMakeUndefined());
  source := TFloriaJSTypedArray(AThis.ObjVal);
  start := OffsetArg(AArgs, 0, 0);
  finish := OffsetArg(AArgs, 1, source.Length);
  if start < 0 then start := source.Length + start;
  if finish < 0 then finish := source.Length + finish;
  if start < 0 then start := 0;
  if finish < start then finish := start;
  if finish > source.Length then finish := source.Length;
  Result := JSMakeObject(FHeap.Track(TFloriaJSTypedArray.Create(FHeap,
    source.Buffer, source.Offset + start * source.ElementSizePublic(),
    finish - start, source.Kind, source.Prototype)));
end;

function TFloriaJSBinaryHelper.TypedSlice(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  source, copy: TFloriaJSTypedArray;
  start, finish, count, i: Integer;
  buffer: TFloriaJSArrayBuffer;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSTypedArray) then
    Exit(JSMakeUndefined());
  source := TFloriaJSTypedArray(AThis.ObjVal);
  start := OffsetArg(AArgs, 0, 0);
  finish := OffsetArg(AArgs, 1, source.Length);
  if start < 0 then start := source.Length + start;
  if finish < 0 then finish := source.Length + finish;
  if start < 0 then start := 0;
  if finish < start then finish := start;
  if finish > source.Length then finish := source.Length;
  count := finish - start;
  buffer := TFloriaJSArrayBuffer.Create(FHeap, count * source.ElementSizePublic());
  FHeap.Track(buffer);
  copy := TFloriaJSTypedArray.Create(FHeap, buffer, 0, count, source.Kind, source.Prototype);
  copy.SetProperty('__keep', JSMakeObject(buffer));
  for i := 0 to count - 1 do
    copy.WriteElementPublic(i, source.ReadElementPublic(start + i));
  Result := JSMakeObject(FHeap.Track(copy));
end;

function TFloriaJSBinaryHelper.TypedFill(
  const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
var
  target: TFloriaJSTypedArray;
  start, finish, i: Integer;
  value: TFloriaJSValue;
begin
  if not AThis.IsObject() or not (AThis.ObjVal is TFloriaJSTypedArray) then
    Exit(JSMakeUndefined());
  target := TFloriaJSTypedArray(AThis.ObjVal);
  value := JSMakeUndefined();
  if Length(AArgs) > 0 then value := AArgs[0];
  start := OffsetArg(AArgs, 1, 0);
  finish := OffsetArg(AArgs, 2, target.Length);
  if start < 0 then start := 0;
  if finish > target.Length then finish := target.Length;
  for i := start to finish - 1 do
    target.WriteElementPublic(i, value);
  Result := AThis;
end;

function TFloriaJSBinaryHelper.DataViewGetInt8(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  Result := JSMakeNumber(ShortInt(ReadRaw(buffer, offset, 1, False)));
end;

function TFloriaJSBinaryHelper.DataViewGetUint8(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  Result := JSMakeNumber(ReadRaw(buffer, offset, 1, False));
end;

function TFloriaJSBinaryHelper.DataViewGetInt16(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  Result := JSMakeNumber(SmallInt(ReadRaw(buffer, offset, 2, BigEndianArg(AArgs, 1))));
end;

function TFloriaJSBinaryHelper.DataViewGetUint16(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  Result := JSMakeNumber(Word(ReadRaw(buffer, offset, 2, BigEndianArg(AArgs, 1))));
end;

function TFloriaJSBinaryHelper.DataViewGetInt32(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  Result := JSMakeNumber(LongInt(ReadRaw(buffer, offset, 4, BigEndianArg(AArgs, 1))));
end;

function TFloriaJSBinaryHelper.DataViewGetUint32(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  Result := JSMakeNumber(LongWord(ReadRaw(buffer, offset, 4, BigEndianArg(AArgs, 1))));
end;

function TFloriaJSBinaryHelper.DataViewGetFloat32(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
  raw: LongWord;
  s: Single;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  raw := LongWord(ReadRaw(buffer, offset, 4, BigEndianArg(AArgs, 1)));
  Move(raw, s, 4);
  Result := JSMakeNumber(s);
end;

function TFloriaJSBinaryHelper.DataViewGetFloat64(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
  raw: UInt64;
  d: Double;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  raw := ReadRaw(buffer, offset, 8, BigEndianArg(AArgs, 1));
  Move(raw, d, 8);
  Result := JSMakeNumber(d);
end;

function TFloriaJSBinaryHelper.DataViewSetInt8(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  if Length(AArgs) < 2 then Exit(JSMakeUndefined());
  WriteRaw(buffer, offset, 1, Byte(ShortInt(Trunc(AArgs[1].ToNumber()))), False);
  Result := JSMakeUndefined();
end;

function TFloriaJSBinaryHelper.DataViewSetUint8(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  if Length(AArgs) < 2 then Exit(JSMakeUndefined());
  WriteRaw(buffer, offset, 1, Byte(Trunc(AArgs[1].ToNumber())), False);
  Result := JSMakeUndefined();
end;

function TFloriaJSBinaryHelper.DataViewSetInt16(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  if Length(AArgs) < 2 then Exit(JSMakeUndefined());
  WriteRaw(buffer, offset, 2, Word(SmallInt(Trunc(AArgs[1].ToNumber()))),
    BigEndianArg(AArgs, 2));
  Result := JSMakeUndefined();
end;

function TFloriaJSBinaryHelper.DataViewSetUint16(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  if Length(AArgs) < 2 then Exit(JSMakeUndefined());
  WriteRaw(buffer, offset, 2, Word(Trunc(AArgs[1].ToNumber())), BigEndianArg(AArgs, 2));
  Result := JSMakeUndefined();
end;

function TFloriaJSBinaryHelper.DataViewSetInt32(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  if Length(AArgs) < 2 then Exit(JSMakeUndefined());
  WriteRaw(buffer, offset, 4, LongWord(LongInt(Trunc(AArgs[1].ToNumber()))),
    BigEndianArg(AArgs, 2));
  Result := JSMakeUndefined();
end;

function TFloriaJSBinaryHelper.DataViewSetUint32(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  if Length(AArgs) < 2 then Exit(JSMakeUndefined());
  WriteRaw(buffer, offset, 4, LongWord(Trunc(AArgs[1].ToNumber())), BigEndianArg(AArgs, 2));
  Result := JSMakeUndefined();
end;

function TFloriaJSBinaryHelper.DataViewSetFloat32(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
  s: Single;
  raw: LongWord;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  if Length(AArgs) < 2 then Exit(JSMakeUndefined());
  s := AArgs[1].ToNumber();
  raw := 0;
  Move(s, raw, 4);
  WriteRaw(buffer, offset, 4, raw, BigEndianArg(AArgs, 2));
  Result := JSMakeUndefined();
end;

function TFloriaJSBinaryHelper.DataViewSetFloat64(const AArgs: array of TFloriaJSValue;
  AThis: TFloriaJSValue): TFloriaJSValue;
var
  buffer: TFloriaJSArrayBuffer;
  offset: Integer;
  d: Double;
  raw: UInt64;
begin
  buffer := BufferArg(AThis);
  offset := TFloriaJSDataView(AThis.ObjVal).Offset + OffsetArg(AArgs, 0, 0);
  if Length(AArgs) < 2 then Exit(JSMakeUndefined());
  d := AArgs[1].ToNumber();
  raw := 0;
  Move(d, raw, 8);
  WriteRaw(buffer, offset, 8, raw, BigEndianArg(AArgs, 2));
  Result := JSMakeUndefined();
end;

procedure RegisterMethod(AHeap: TFloriaJSHeap; AProto: TFloriaJSObject;
  const AName: string; AMethod: TFloriaJSNativeMethod);
begin
  AProto.SetProperty(AName, JSMakeFunction(AHeap.NewNativeMethod(AName, AMethod)));
end;

procedure FloriaJSRegisterBinary(AEnv: TFloriaJSEnvironment; AHeap: TFloriaJSHeap);
var
  helper: TFloriaJSBinaryHelper;
  arrayBufferCtor, sharedCtor, dataViewCtor, typedCtor: TFloriaJSFunction;
  arrayBufferProto, sharedProto, dataViewProto, typedProto, kindProto: TFloriaJSObject;
  atomicsObj: TFloriaJSObject;
  i: Integer;
  names: array[0..10] of string;
  kinds: array[0..10] of TFloriaJSBinaryKind;
begin
  if (AEnv = nil) or (AHeap = nil) then Exit;
  helper := TFloriaJSBinaryHelper.Create(AHeap);
  AHeap.OwnHelper(helper);

  { ArrayBuffer }
  arrayBufferCtor := AHeap.NewNativeMethod('ArrayBuffer', @helper.ArrayBufferCtor);
  arrayBufferCtor.IntrinsicName := 'ArrayBuffer';
  arrayBufferProto := AHeap.NewObject(AHeap.GetObjectPrototype());
  arrayBufferCtor.SetProperty('prototype', JSMakeObject(arrayBufferProto));
  arrayBufferProto.SetProperty('constructor', JSMakeFunction(arrayBufferCtor));
  RegisterMethod(AHeap, arrayBufferProto, 'slice', @helper.ArrayBufferSlice);
  arrayBufferCtor.SetProperty('isView',
    JSMakeFunction(AHeap.NewNativeMethod('isView', @helper.ArrayBufferIsView)));
  AEnv.Define('ArrayBuffer', JSMakeFunction(arrayBufferCtor));

  { SharedArrayBuffer }
  sharedCtor := AHeap.NewNativeMethod('SharedArrayBuffer', @helper.SharedArrayBufferCtor);
  sharedCtor.IntrinsicName := 'SharedArrayBuffer';
  sharedProto := AHeap.NewObject(AHeap.GetObjectPrototype());
  sharedCtor.SetProperty('prototype', JSMakeObject(sharedProto));
  sharedProto.SetProperty('constructor', JSMakeFunction(sharedCtor));
  RegisterMethod(AHeap, sharedProto, 'slice', @helper.ArrayBufferSlice);
  AEnv.Define('SharedArrayBuffer', JSMakeFunction(sharedCtor));

  { Atomics }
  atomicsObj := AHeap.NewObject(AHeap.GetObjectPrototype());
  atomicsObj.SetProperty('load', JSMakeFunction(AHeap.NewNativeMethod('load', @helper.AtomicsLoad)));
  atomicsObj.SetProperty('store', JSMakeFunction(AHeap.NewNativeMethod('store', @helper.AtomicsStore)));
  atomicsObj.SetProperty('add', JSMakeFunction(AHeap.NewNativeMethod('add', @helper.AtomicsAdd)));
  atomicsObj.SetProperty('sub', JSMakeFunction(AHeap.NewNativeMethod('sub', @helper.AtomicsSub)));
  atomicsObj.SetProperty('and', JSMakeFunction(AHeap.NewNativeMethod('and', @helper.AtomicsAnd_)));
  atomicsObj.SetProperty('or', JSMakeFunction(AHeap.NewNativeMethod('or', @helper.AtomicsOr_)));
  atomicsObj.SetProperty('xor', JSMakeFunction(AHeap.NewNativeMethod('xor', @helper.AtomicsXor_)));
  atomicsObj.SetProperty('exchange', JSMakeFunction(AHeap.NewNativeMethod('exchange', @helper.AtomicsExchange)));
  atomicsObj.SetProperty('compareExchange', JSMakeFunction(AHeap.NewNativeMethod('compareExchange', @helper.AtomicsCompareExchange)));
  atomicsObj.SetProperty('isLockFree', JSMakeFunction(AHeap.NewNativeMethod('isLockFree', @helper.AtomicsIsLockFree)));
  atomicsObj.SetProperty('wait', JSMakeFunction(AHeap.NewNativeMethod('wait', @helper.AtomicsWait)));
  atomicsObj.SetProperty('waitAsync', JSMakeFunction(AHeap.NewNativeMethod('waitAsync', @helper.AtomicsWaitAsync)));
  atomicsObj.SetProperty('notify', JSMakeFunction(AHeap.NewNativeMethod('notify', @helper.AtomicsNotify)));
  AEnv.Define('Atomics', JSMakeObject(atomicsObj));

  { DataView }
  dataViewCtor := AHeap.NewNativeMethod('DataView', @helper.DataViewCtor);
  dataViewCtor.IntrinsicName := 'DataView';
  dataViewProto := AHeap.NewObject(AHeap.GetObjectPrototype());
  dataViewCtor.SetProperty('prototype', JSMakeObject(dataViewProto));
  dataViewProto.SetProperty('constructor', JSMakeFunction(dataViewCtor));
  RegisterMethod(AHeap, dataViewProto, 'getInt8', @helper.DataViewGetInt8);
  RegisterMethod(AHeap, dataViewProto, 'getUint8', @helper.DataViewGetUint8);
  RegisterMethod(AHeap, dataViewProto, 'getInt16', @helper.DataViewGetInt16);
  RegisterMethod(AHeap, dataViewProto, 'getUint16', @helper.DataViewGetUint16);
  RegisterMethod(AHeap, dataViewProto, 'getInt32', @helper.DataViewGetInt32);
  RegisterMethod(AHeap, dataViewProto, 'getUint32', @helper.DataViewGetUint32);
  RegisterMethod(AHeap, dataViewProto, 'getFloat32', @helper.DataViewGetFloat32);
  RegisterMethod(AHeap, dataViewProto, 'getFloat64', @helper.DataViewGetFloat64);
  RegisterMethod(AHeap, dataViewProto, 'setInt8', @helper.DataViewSetInt8);
  RegisterMethod(AHeap, dataViewProto, 'setUint8', @helper.DataViewSetUint8);
  RegisterMethod(AHeap, dataViewProto, 'setInt16', @helper.DataViewSetInt16);
  RegisterMethod(AHeap, dataViewProto, 'setUint16', @helper.DataViewSetUint16);
  RegisterMethod(AHeap, dataViewProto, 'setInt32', @helper.DataViewSetInt32);
  RegisterMethod(AHeap, dataViewProto, 'setUint32', @helper.DataViewSetUint32);
  RegisterMethod(AHeap, dataViewProto, 'setFloat32', @helper.DataViewSetFloat32);
  RegisterMethod(AHeap, dataViewProto, 'setFloat64', @helper.DataViewSetFloat64);
  AEnv.Define('DataView', JSMakeFunction(dataViewCtor));

  { A shared base typed-array prototype holds the generic methods. }
  typedProto := AHeap.NewObject(AHeap.GetObjectPrototype());
  RegisterMethod(AHeap, typedProto, 'set', @helper.TypedSet);
  RegisterMethod(AHeap, typedProto, 'subarray', @helper.TypedSubarray);
  RegisterMethod(AHeap, typedProto, 'slice', @helper.TypedSlice);
  RegisterMethod(AHeap, typedProto, 'fill', @helper.TypedFill);

  names[0] := 'Uint8Array';      kinds[0] := fbkUint8;
  names[1] := 'Int8Array';       kinds[1] := fbkInt8;
  names[2] := 'Uint8ClampedArray'; kinds[2] := fbkUint8Clamped;
  names[3] := 'Uint16Array';     kinds[3] := fbkUint16;
  names[4] := 'Int16Array';      kinds[4] := fbkInt16;
  names[5] := 'Uint32Array';     kinds[5] := fbkUint32;
  names[6] := 'Int32Array';      kinds[6] := fbkInt32;
  names[7] := 'Float32Array';    kinds[7] := fbkFloat32;
  names[8] := 'Float64Array';    kinds[8] := fbkFloat64;
  names[9] := 'BigInt64Array';   kinds[9] := fbkBigInt64;
  names[10] := 'BigUint64Array'; kinds[10] := fbkBigUint64;

  for i := 0 to 10 do
  begin
    typedCtor := AHeap.NewNativeMethod(names[i], @helper.TypedArrayCtor);
    typedCtor.IntrinsicName := names[i];
    kindProto := AHeap.NewObject(typedProto);
    typedCtor.SetProperty('prototype', JSMakeObject(kindProto));
    kindProto.SetProperty('constructor', JSMakeFunction(typedCtor));
    typedCtor.SetProperty('__kind', JSMakeNumber(Ord(kinds[i])));
    typedCtor.SetProperty('BYTES_PER_ELEMENT', JSMakeNumber(ElementSizeOf(kinds[i])));
    kindProto.SetProperty('__kind', JSMakeNumber(Ord(kinds[i])));
    kindProto.SetProperty('BYTES_PER_ELEMENT', JSMakeNumber(ElementSizeOf(kinds[i])));
    AEnv.Define(names[i], JSMakeFunction(typedCtor));
  end;
end;

end.
