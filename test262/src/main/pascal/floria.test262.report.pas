{ ************************************************************************** }
{                                                                            }
{   Floria JS Test262 Host — Structured Result Reporting                    }
{                                                                            }
{   Copyright (c) 2026 Dio Affriza                                          }
{   SPDX-License-Identifier: MPL-2.0                                        }
{                                                                            }
{ ************************************************************************** }

unit floria.test262.report;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson,
  floria.js.types, floriajs;

type
  THostReport = record
    ScenarioId: string;
    Variant: string;
    Outcome: string;
    Phase: string;
    Reason: string;
    SourceRole: string;
    SourceIndex: Integer;
    SourceName: string;
    ErrorName: string;
    ErrorMessage: string;
    HostExceptionClass: string;
    Line: Integer;
    Column: Integer;
    ResultType: string;
    ResultString: string;
    LegacyErrorMessage: string;
    ConsoleOutput: array of string;
    PrintOutput: array of string;
  end;

procedure InitHostReport(var AReport: THostReport; const AScenarioId,
  AVariant, ATestName: string);
procedure FailHostReport(var AReport: THostReport; const AOutcome, APhase,
  AReason, ASourceRole: string; ASourceIndex: Integer; const ASourceName,
  AErrorName, AMessage, AHostExceptionClass: string; ALine: Integer = 0;
  AColumn: Integer = 0);
procedure ApplyDiagnostic(var AReport: THostReport;
  const ADiagnostic: TFloriaJSDiagnosticResult; const ASourceRole: string;
  ASourceIndex: Integer);
procedure CopyCapturedOutput(var AReport: THostReport;
  const AConsole, APrint: TStringList);
function HostReportJSON(const AReport: THostReport; ADurationMs: QWord): string;

implementation

function PhaseName(const AKind: TFloriaJSDiagnosticKind): string;
begin
  case AKind of
    fjdkParseError: Result := 'parse';
    fjdkCompileError: Result := 'compile';
    fjdkJavaScriptThrow: Result := 'runtime';
    fjdkHostException: Result := 'host';
  else
    Result := 'success';
  end;
end;

function ResultTypeName(const AKind: TFloriaJSType): string;
begin
  case AKind of
    fjstUndefined: Result := 'undefined';
    fjstNull: Result := 'null';
    fjstBoolean: Result := 'boolean';
    fjstNumber: Result := 'number';
    fjstString: Result := 'string';
    fjstObject: Result := 'object';
    fjstArray: Result := 'array';
    fjstFunction: Result := 'function';
    fjstSymbol: Result := 'symbol';
    fjstError: Result := 'error';
    fjstBigInt: Result := 'bigint';
  else
    Result := 'unknown';
  end;
end;

procedure InitHostReport(var AReport: THostReport; const AScenarioId,
  AVariant, ATestName: string);
begin
  AReport.ScenarioId := AScenarioId;
  AReport.Variant := AVariant;
  AReport.Outcome := 'pass';
  AReport.Phase := 'success';
  AReport.Reason := '';
  AReport.SourceRole := 'test';
  AReport.SourceIndex := 0;
  AReport.SourceName := ATestName;
  AReport.ErrorName := '';
  AReport.ErrorMessage := '';
  AReport.HostExceptionClass := '';
  AReport.Line := 0;
  AReport.Column := 0;
  AReport.ResultType := 'undefined';
  AReport.ResultString := '';
  AReport.LegacyErrorMessage := '';
  SetLength(AReport.ConsoleOutput, 0);
  SetLength(AReport.PrintOutput, 0);
end;

procedure FailHostReport(var AReport: THostReport; const AOutcome, APhase,
  AReason, ASourceRole: string; ASourceIndex: Integer; const ASourceName,
  AErrorName, AMessage, AHostExceptionClass: string; ALine: Integer = 0;
  AColumn: Integer = 0);
begin
  AReport.Outcome := AOutcome;
  AReport.Phase := APhase;
  AReport.Reason := AReason;
  AReport.SourceRole := ASourceRole;
  AReport.SourceIndex := ASourceIndex;
  AReport.SourceName := ASourceName;
  AReport.ErrorName := AErrorName;
  AReport.ErrorMessage := AMessage;
  AReport.HostExceptionClass := AHostExceptionClass;
  AReport.Line := ALine;
  AReport.Column := AColumn;
  AReport.ResultType := 'error';
  AReport.ResultString := '';
  AReport.LegacyErrorMessage := AMessage;
end;

procedure ApplyDiagnostic(var AReport: THostReport;
  const ADiagnostic: TFloriaJSDiagnosticResult; const ASourceRole: string;
  ASourceIndex: Integer);
begin
  if ADiagnostic.Result.Success then
  begin
    AReport.Outcome := 'pass';
    AReport.Phase := 'success';
    AReport.Reason := '';
    AReport.ErrorName := '';
    AReport.ErrorMessage := '';
    AReport.HostExceptionClass := '';
    AReport.Line := 0;
    AReport.Column := 0;
    AReport.ResultType := ResultTypeName(ADiagnostic.Result.ResultType);
    AReport.ResultString := ADiagnostic.Result.StringValue;
    AReport.LegacyErrorMessage := '';
  end
  else
  begin
    if ADiagnostic.Kind = fjdkHostException then
      AReport.Outcome := 'harness-error'
    else if ASourceRole = 'test' then
      AReport.Outcome := 'fail'
    else
      AReport.Outcome := 'harness-error';

    if ADiagnostic.Kind = fjdkHostException then
      AReport.Reason := 'host-exception'
    else if ASourceRole = 'test' then
      AReport.Reason := 'evaluation-failed'
    else
      AReport.Reason := 'harness-evaluation-failed';

    AReport.Phase := PhaseName(ADiagnostic.Kind);
    AReport.ErrorName := ADiagnostic.ErrorName;
    AReport.ErrorMessage := ADiagnostic.Message;
    AReport.HostExceptionClass := ADiagnostic.HostExceptionClass;
    AReport.Line := ADiagnostic.Line;
    AReport.Column := ADiagnostic.Column;
    AReport.ResultType := 'error';
    AReport.ResultString := '';
    AReport.LegacyErrorMessage := ADiagnostic.Result.ErrorMessage;
  end;
  AReport.SourceRole := ASourceRole;
  AReport.SourceIndex := ASourceIndex;
  AReport.SourceName := ADiagnostic.SourceName;
end;

procedure CopyCapturedOutput(var AReport: THostReport;
  const AConsole, APrint: TStringList);
var
  i: Integer;
begin
  SetLength(AReport.ConsoleOutput, AConsole.Count);
  for i := 0 to AConsole.Count - 1 do
    AReport.ConsoleOutput[i] := AConsole[i];
  SetLength(AReport.PrintOutput, APrint.Count);
  for i := 0 to APrint.Count - 1 do
    AReport.PrintOutput[i] := APrint[i];
end;

function StringArray(const AItems: array of string): TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create();
  for i := 0 to High(AItems) do
    Result.Add(AItems[i]);
end;

{ Replaces invalid UTF-8 sequences with U+FFFD. A JavaScript string can hold a
  lone surrogate, which the engine stores as WTF-8; the report must still be
  valid UTF-8 for the Python runner to decode. }
function SanitizeUTF8(const S: string): string;
var
  i, n, k: Integer;
  b: Byte;
  ok: Boolean;
  cp: LongWord;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    b := Ord(S[i]);
    if b < $80 then
    begin
      Result := Result + S[i];
      Inc(i);
      Continue;
    end;
    if (b and $E0) = $C0 then n := 2
    else if (b and $F0) = $E0 then n := 3
    else if (b and $F8) = $F0 then n := 4
    else n := 0;

    ok := (n > 0) and (i + n - 1 <= Length(S));
    if ok then
      for k := 1 to n - 1 do
        if (Ord(S[i + k]) and $C0) <> $80 then
          ok := False;
    if ok and (n = 3) then
    begin
      cp := ((b and $0F) shl 12) or
        ((Ord(S[i + 1]) and $3F) shl 6) or (Ord(S[i + 2]) and $3F);
      if (cp >= $D800) and (cp <= $DFFF) then
        ok := False;
    end;
    if ok then
    begin
      Result := Result + Copy(S, i, n);
      Inc(i, n);
    end
    else
    begin
      Result := Result + #$EF#$BF#$BD;
      Inc(i);
    end;
  end;
end;

function HostReportJSON(const AReport: THostReport; ADurationMs: QWord): string;
var
  root, error, legacy: TJSONObject;
begin
  root := TJSONObject.Create();
  try
    root.Add('schemaVersion', 1);
    root.Add('scenarioId', AReport.ScenarioId);
    root.Add('variant', AReport.Variant);
    root.Add('outcome', AReport.Outcome);
    root.Add('phase', AReport.Phase);
    root.Add('reason', AReport.Reason);
    root.Add('sourceRole', AReport.SourceRole);
    root.Add('sourceIndex', AReport.SourceIndex);
    root.Add('sourceName', AReport.SourceName);
    root.Add('durationMs', ADurationMs);

    error := TJSONObject.Create();
    error.Add('name', AReport.ErrorName);
    error.Add('message', AReport.ErrorMessage);
    error.Add('hostExceptionClass', AReport.HostExceptionClass);
    error.Add('line', AReport.Line);
    error.Add('column', AReport.Column);
    root.Add('error', error);

    legacy := TJSONObject.Create();
    legacy.Add('success', AReport.Outcome = 'pass');
    legacy.Add('resultType', AReport.ResultType);
    legacy.Add('stringValue', AReport.ResultString);
    legacy.Add('errorMessage', AReport.LegacyErrorMessage);
    root.Add('legacyResult', legacy);

    root.Add('consoleOutput', StringArray(AReport.ConsoleOutput));
    root.Add('printOutput', StringArray(AReport.PrintOutput));
    Result := SanitizeUTF8(root.FormatJSON(AsCompressedJSON));
  finally
    root.Free();
  end;
end;

end.
