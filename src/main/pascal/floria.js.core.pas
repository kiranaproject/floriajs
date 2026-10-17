{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Engine & Execution Context                      }
{                                                                          }
{   Provides the core JavaScript runtime and evaluation context classes    }
{   for the Floria Toolkit ecosystem.                                      }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.core;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, floria.js.types;

type
  { Forward Declarations }
  TFloriaJSEngine = class;
  TFloriaJSContext = class;

  { TFloriaJSContext — Execution context for evaluating scripts }
  TFloriaJSContext = class
  private
    FEngine: TFloriaJSEngine;
    FName: string;
    FGlobalVariables: TStringList;
  public
    constructor Create(AEngine: TFloriaJSEngine; const AName: string = 'global');
    destructor Destroy(); override;

    procedure SetVariable(const AKey, AValue: string);
    function  GetVariable(const AKey: string): string;
    function  HasVariable(const AKey: string): Boolean;

    function  Evaluate(const AScript: string): TFloriaJSResult; virtual;
    procedure Reset(); virtual;

    property Engine: TFloriaJSEngine read FEngine;
    property Name: string read FName write FName;
  end;

  { TFloriaJSEngine — Main JavaScript Runtime Engine }
  TFloriaJSEngine = class
  private
    FInitialized: Boolean;
    FContexts: TFPList;
    FDefaultContext: TFloriaJSContext;
    FMemoryLimit: NativeUInt;
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Initialize(); virtual;
    function  CreateContext(const AName: string = ''): TFloriaJSContext;
    procedure DestroyContext(AContext: TFloriaJSContext);

    function  Execute(const AScript: string): TFloriaJSResult; virtual;

    property Initialized: Boolean read FInitialized;
    property DefaultContext: TFloriaJSContext read FDefaultContext;
    property MemoryLimit: NativeUInt read FMemoryLimit write FMemoryLimit;
  end;

implementation

{ TFloriaJSContext }

constructor TFloriaJSContext.Create(AEngine: TFloriaJSEngine; const AName: string = 'global');
begin
  inherited Create();
  FEngine := AEngine;
  FName := AName;
  FGlobalVariables := TStringList.Create();
  FGlobalVariables.CaseSensitive := True;
end;

destructor TFloriaJSContext.Destroy();
begin
  FreeAndNil(FGlobalVariables);
  inherited Destroy();
end;

procedure TFloriaJSContext.SetVariable(const AKey, AValue: string);
begin
  if FGlobalVariables <> nil then
    FGlobalVariables.Values[AKey] := AValue;
end;

function TFloriaJSContext.GetVariable(const AKey: string): string;
begin
  if FGlobalVariables <> nil then
    Result := FGlobalVariables.Values[AKey]
  else
    Result := '';
end;

function TFloriaJSContext.HasVariable(const AKey: string): Boolean;
begin
  if FGlobalVariables <> nil then
    Result := FGlobalVariables.IndexOfName(AKey) >= 0
  else
    Result := False;
end;

function TFloriaJSContext.Evaluate(const AScript: string): TFloriaJSResult;
begin
  if Length(Trim(AScript)) = 0 then
    Exit(FloriaJSMakeOkResult(''));

  { Starter evaluator: returns script expression or ok result }
  Result := FloriaJSMakeOkResult(AScript);
end;

procedure TFloriaJSContext.Reset();
begin
  if FGlobalVariables <> nil then
    FGlobalVariables.Clear();
end;

{ TFloriaJSEngine }

constructor TFloriaJSEngine.Create();
begin
  inherited Create();
  FInitialized := False;
  FMemoryLimit := 64 * 1024 * 1024; { Default 64MB memory limit }
  FContexts := TFPList.Create();
  Initialize();
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

end.
