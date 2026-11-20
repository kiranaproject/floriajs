{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — ECMAScript Module Records                       }
{                                                                          }
{   Implements the Module Record abstract operations: the five entry lists, }
{   ResolveExport, and the module namespace object. A host supplies source  }
{   for a specifier through a loader callback.                              }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

unit floria.js.module;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, floria.js.types, floria.js.value, floria.js.env,
  floria.js.bytecode;

type
  TFloriaJSModuleRecord = class;
  TFloriaJSModuleRegistry = class;

  { One entry of [[ImportEntries]]. }
  TFloriaJSImportEntry = record
    ModuleRequest: string;
    { The name in the exporting module: 'default', a name, or '*' for a
      namespace import. }
    ImportName: string;
    { The local binding created in the importing module. }
    LocalName: string;
  end;

  { One entry of [[LocalExportEntries]]. }
  TFloriaJSLocalExportEntry = record
    LocalName: string;
    ExportName: string;
  end;

  { One entry of [[IndirectExportEntries]]. }
  TFloriaJSIndirectExportEntry = record
    ModuleRequest: string;
    ImportName: string;
    ExportName: string;
  end;

  { One entry of [[StarExportEntries]]. }
  TFloriaJSStarExportEntry = record
    ModuleRequest: string;
    { Non-empty only for `export * as ns from "m"`, which is modelled as an
      indirect entry. }
    ExportName: string;
  end;

  { The module lifecycle status. }
  TFloriaJSModuleStatus = (fmsUnlinked, fmsLinking, fmsLinked, fmsEvaluating,
    fmsEvaluated, fmsErrored);

  TFloriaJSResolveResult = (rrResolved, rrAmbiguous, rrNotFound);

  TFloriaJSResolvedBinding = record
    Module: TFloriaJSModuleRecord;
    { '*' means the module namespace object. }
    BindingName: string;
  end;

  { Supplies the source text for a specifier, resolved relative to the
    referring module's identifier. Returns False when it cannot be resolved. }
  TFloriaJSModuleLoader = function(const ASpecifier, AReferrer: string;
    out ASource, AResolvedName: string): Boolean of object;

  TFloriaJSModuleRecord = class
  public
    Identifier: string;
    Registry: TFloriaJSModuleRegistry;
    { [[Realm]] — the environment the module body runs in, created at link. }
    Environment: TFloriaJSEnvironment;
    { The module namespace object, built once at link. }
    Namespace: TFloriaJSValue;
    Status: TFloriaJSModuleStatus;
    { [[EvaluationError]], set when Status is fmsErrored. }
    EvaluationError: TFloriaJSValue;
    { The parsed program body and the compiled chunk, owned by the record. }
    Body: TObject;
    Chunk: TObject;
    { The source text, kept so a dependency can be parsed when it is linked. }
    SourceText: string;
    { The import.meta object, created on first access. }
    Meta: TFloriaJSValue;
    { The request list, parallel to the resolved dependencies. }
    RequestedModules: TStringList;
    Dependencies: TFPList;

    ImportEntries: array of TFloriaJSImportEntry;
    LocalExportEntries: array of TFloriaJSLocalExportEntry;
    IndirectExportEntries: array of TFloriaJSIndirectExportEntry;
    StarExportEntries: array of TFloriaJSStarExportEntry;

    constructor Create(const AIdentifier: string;
      ARegistry: TFloriaJSModuleRegistry);
    destructor Destroy(); override;

    procedure AddImport(const AModuleRequest, AImportName, ALocalName: string);
    procedure AddLocalExport(const ALocalName, AExportName: string);
    procedure AddIndirectExport(const AModuleRequest, AImportName, AExportName: string);
    procedure AddStarExport(const AModuleRequest: string);
    procedure AddDependency(const AModuleRequest: string;
      ADependency: TFloriaJSModuleRecord);

    { The dependency record for a module request, or nil. }
    function DependencyFor(const AModuleRequest: string): TFloriaJSModuleRecord;
    { The names this module exports, including star re-exports. AStarSet
      guards against a circular `export *`. }
    procedure CollectExportedNames(AInto: TStrings; AStarSet: TStrings = nil);
  end;

  { The module records of one realm plus the loader used to resolve
    specifiers. Owns every record it creates. }
  TFloriaJSModuleRegistry = class
  private
    FModules: TStringList;
    FLoader: TFloriaJSModuleLoader;
  public
    constructor Create();
    destructor Destroy(); override;

    property Loader: TFloriaJSModuleLoader read FLoader write FLoader;

    { Returns the record for AIdentifier, loading it on demand through the
      loader when it is not present yet. Returns nil when it cannot be
      loaded. }
    function Load(const AIdentifier, AReferrer: string): TFloriaJSModuleRecord;
    procedure Add(AModule: TFloriaJSModuleRecord);
    function Find(const AIdentifier: string): TFloriaJSModuleRecord;
    function Count(): Integer;
    function ByIndex(AIndex: Integer): TFloriaJSModuleRecord;
  end;

{ ResolveExport(exportName) over the module graph. AResolveSet guards against
  cycles of star exports. }
function FloriaJSResolveExport(AModule: TFloriaJSModuleRecord;
  const AExportName: string; AResolveSet: TStrings;
  out ABinding: TFloriaJSResolvedBinding): TFloriaJSResolveResult;

implementation

{ TFloriaJSModuleRecord }

constructor TFloriaJSModuleRecord.Create(const AIdentifier: string;
  ARegistry: TFloriaJSModuleRegistry);
begin
  inherited Create();
  Identifier := AIdentifier;
  Registry := ARegistry;
  Environment := nil;
  Namespace := JSMakeUndefined();
  Status := fmsUnlinked;
  EvaluationError := JSMakeUndefined();
  Body := nil;
  Chunk := nil;
  SourceText := '';
  Meta := JSMakeUndefined();
  RequestedModules := TStringList.Create();
  RequestedModules.CaseSensitive := True;
  Dependencies := TFPList.Create();
end;

destructor TFloriaJSModuleRecord.Destroy();
begin
  { The compiled chunk is reference counted; the record holds one reference. }
  if Chunk <> nil then
    TFloriaJSBytecode(Chunk).Release();
  FreeAndNil(Dependencies);
  FreeAndNil(RequestedModules);
  SetLength(ImportEntries, 0);
  SetLength(LocalExportEntries, 0);
  SetLength(IndirectExportEntries, 0);
  SetLength(StarExportEntries, 0);
  inherited Destroy();
end;

procedure TFloriaJSModuleRecord.AddImport(const AModuleRequest, AImportName,
  ALocalName: string);
var
  n: Integer;
begin
  n := Length(ImportEntries);
  SetLength(ImportEntries, n + 1);
  ImportEntries[n].ModuleRequest := AModuleRequest;
  ImportEntries[n].ImportName := AImportName;
  ImportEntries[n].LocalName := ALocalName;
end;

procedure TFloriaJSModuleRecord.AddLocalExport(const ALocalName,
  AExportName: string);
var
  n: Integer;
begin
  n := Length(LocalExportEntries);
  SetLength(LocalExportEntries, n + 1);
  LocalExportEntries[n].LocalName := ALocalName;
  LocalExportEntries[n].ExportName := AExportName;
end;

procedure TFloriaJSModuleRecord.AddIndirectExport(const AModuleRequest,
  AImportName, AExportName: string);
var
  n: Integer;
begin
  n := Length(IndirectExportEntries);
  SetLength(IndirectExportEntries, n + 1);
  IndirectExportEntries[n].ModuleRequest := AModuleRequest;
  IndirectExportEntries[n].ImportName := AImportName;
  IndirectExportEntries[n].ExportName := AExportName;
end;

procedure TFloriaJSModuleRecord.AddStarExport(const AModuleRequest: string);
var
  n: Integer;
begin
  n := Length(StarExportEntries);
  SetLength(StarExportEntries, n + 1);
  StarExportEntries[n].ModuleRequest := AModuleRequest;
  StarExportEntries[n].ExportName := '';
end;

procedure TFloriaJSModuleRecord.AddDependency(const AModuleRequest: string;
  ADependency: TFloriaJSModuleRecord);
var
  idx: Integer;
begin
  idx := RequestedModules.IndexOf(AModuleRequest);
  if idx < 0 then
  begin
    RequestedModules.AddObject(AModuleRequest, ADependency);
    Exit;
  end;
  RequestedModules.Objects[idx] := ADependency;
end;

function TFloriaJSModuleRecord.DependencyFor(
  const AModuleRequest: string): TFloriaJSModuleRecord;
var
  idx: Integer;
begin
  Result := nil;
  idx := RequestedModules.IndexOf(AModuleRequest);
  if idx >= 0 then
    Result := TFloriaJSModuleRecord(RequestedModules.Objects[idx]);
end;

procedure TFloriaJSModuleRecord.CollectExportedNames(AInto: TStrings;
  AStarSet: TStrings);
var
  i: Integer;
  dep: TFloriaJSModuleRecord;
  sub: TStringList;
  binding: TFloriaJSResolvedBinding;
  resolveSet: TStringList;
  ownStarSet: Boolean;
  res: TFloriaJSResolveResult;
begin
  if AInto = nil then Exit;
  for i := 0 to High(LocalExportEntries) do
    if AInto.IndexOf(LocalExportEntries[i].ExportName) < 0 then
      AInto.Add(LocalExportEntries[i].ExportName);
  for i := 0 to High(IndirectExportEntries) do
    if AInto.IndexOf(IndirectExportEntries[i].ExportName) < 0 then
      AInto.Add(IndirectExportEntries[i].ExportName);

  { A star export contributes every name the peer exports, except "default",
    and only when the name is not ambiguous across several star exports. }
  if Length(StarExportEntries) = 0 then
    Exit;

  { A circular `export *` reaches this module again; stop there rather than
    recursing forever. The outermost call owns the set. }
  ownStarSet := AStarSet = nil;
  if ownStarSet then
  begin
    AStarSet := TStringList.Create();
  end;
  if AStarSet.IndexOf(Identifier) >= 0 then
  begin
    if ownStarSet then
      FreeAndNil(AStarSet);
    Exit;
  end;
  AStarSet.Add(Identifier);
  sub := TStringList.Create();
  resolveSet := TStringList.Create();
  try
    sub.CaseSensitive := True;
    resolveSet.CaseSensitive := True;
    for i := 0 to High(StarExportEntries) do
    begin
      dep := DependencyFor(StarExportEntries[i].ModuleRequest);
      if dep = nil then Continue;
      dep.CollectExportedNames(sub, AStarSet);
    end;
    for i := 0 to sub.Count - 1 do
    begin
      if (sub[i] = 'default') or (AInto.IndexOf(sub[i]) >= 0) then
        Continue;
      { Each name gets its own resolve set; FloriaJSResolveExport guards its
        own star-export cycles with it. }
      resolveSet.Clear();
      res := FloriaJSResolveExport(Self, sub[i], resolveSet, binding);
      if res = rrResolved then
        AInto.Add(sub[i]);
    end;
  finally
    if ownStarSet then
      FreeAndNil(AStarSet);
    resolveSet.Free();
    sub.Free();
  end;
end;

{ TFloriaJSModuleRegistry }

constructor TFloriaJSModuleRegistry.Create();
begin
  inherited Create();
  FModules := TStringList.Create();
  FModules.CaseSensitive := True;
  { Not sorted: a module identifier can arrive before its dependencies and the
    list is small, so a linear lookup is both simpler and order-independent. }
  FModules.Sorted := False;
  FModules.Duplicates := dupIgnore;
  FLoader := nil;
end;

destructor TFloriaJSModuleRegistry.Destroy();
var
  i: Integer;
begin
  if FModules <> nil then
  begin
    for i := 0 to FModules.Count - 1 do
      TFloriaJSModuleRecord(FModules.Objects[i]).Free();
    FreeAndNil(FModules);
  end;
  inherited Destroy();
end;

function TFloriaJSModuleRegistry.Find(
  const AIdentifier: string): TFloriaJSModuleRecord;
var
  idx: Integer;
begin
  Result := nil;
  if (FModules = nil) or (AIdentifier = '') then Exit;
  idx := FModules.IndexOf(AIdentifier);
  if idx >= 0 then
    Result := TFloriaJSModuleRecord(FModules.Objects[idx]);
end;

procedure TFloriaJSModuleRegistry.Add(AModule: TFloriaJSModuleRecord);
begin
  if (AModule = nil) or (FModules = nil) then Exit;
  { The caller keeps ownership, so a duplicate is never freed here; the
    registry simply keeps the record it already had. }
  if FModules.IndexOf(AModule.Identifier) < 0 then
    FModules.AddObject(AModule.Identifier, AModule);
end;

function TFloriaJSModuleRegistry.Load(const AIdentifier,
  AReferrer: string): TFloriaJSModuleRecord;
var
  source, resolved: string;
begin
  Result := Find(AIdentifier);
  if Result <> nil then Exit;
  if not Assigned(FLoader) then Exit;
  resolved := '';
  if not FLoader(AIdentifier, AReferrer, source, resolved) then Exit;
  { A loader may canonicalise the specifier. Fall back to the request so the
    record always has a usable identifier. }
  if resolved = '' then
    resolved := AIdentifier;
  Result := Find(resolved);
  if Result <> nil then
  begin
    if Result.SourceText = '' then
      Result.SourceText := source;
    Exit;
  end;
  Result := TFloriaJSModuleRecord.Create(resolved, Self);
  Result.SourceText := source;
  FModules.AddObject(resolved, Result);
end;

function TFloriaJSModuleRegistry.Count(): Integer;
begin
  if FModules <> nil then
    Result := FModules.Count
  else
    Result := 0;
end;

function TFloriaJSModuleRegistry.ByIndex(AIndex: Integer): TFloriaJSModuleRecord;
begin
  if (FModules <> nil) and (AIndex >= 0) and (AIndex < FModules.Count) then
    Result := TFloriaJSModuleRecord(FModules.Objects[AIndex])
  else
    Result := nil;
end;

{ ResolveExport as specified in 16.2.1.5.3.1. }
function FloriaJSResolveExport(AModule: TFloriaJSModuleRecord;
  const AExportName: string; AResolveSet: TStrings;
  out ABinding: TFloriaJSResolvedBinding): TFloriaJSResolveResult;
var
  i: Integer;
  marker: string;
  starModule, indirectModule: TFloriaJSModuleRecord;
  sub: TFloriaJSResolveResult;
  subBinding: TFloriaJSResolvedBinding;
  starResolution: TFloriaJSResolvedBinding;
  resolution: TFloriaJSResolveResult;
  ambiguous: Boolean;
begin
  ABinding.Module := nil;
  ABinding.BindingName := '';

  if AModule = nil then
    Exit(rrNotFound);

  marker := AExportName + '#' + AModule.Identifier;
  if (AResolveSet <> nil) and (AResolveSet.IndexOf(marker) >= 0) then
    Exit(rrNotFound);

  { A local export wins outright. }
  for i := 0 to High(AModule.LocalExportEntries) do
    if AModule.LocalExportEntries[i].ExportName = AExportName then
    begin
      ABinding.Module := AModule;
      ABinding.BindingName := AModule.LocalExportEntries[i].LocalName;
      Exit(rrResolved);
    end;

  { An indirect export forwards to another module. }
  for i := 0 to High(AModule.IndirectExportEntries) do
    if AModule.IndirectExportEntries[i].ExportName = AExportName then
    begin
      indirectModule := AModule.DependencyFor(
        AModule.IndirectExportEntries[i].ModuleRequest);
      if indirectModule = nil then
        Exit(rrNotFound);
      if AModule.IndirectExportEntries[i].ImportName = '*' then
      begin
        ABinding.Module := indirectModule;
        ABinding.BindingName := '*';
        Exit(rrResolved);
      end;
      if AResolveSet <> nil then
        AResolveSet.Add(marker);
      sub := FloriaJSResolveExport(indirectModule,
        AModule.IndirectExportEntries[i].ImportName, AResolveSet, subBinding);
      if sub = rrResolved then
        ABinding := subBinding;
      Exit(sub);
    end;

  if (AExportName = 'default') or (AExportName = '__proto__') then
    Exit(rrNotFound);

  if AResolveSet <> nil then
    AResolveSet.Add(marker);

  { Otherwise the star exports are searched. Two different resolutions of the
    same name are ambiguous. }
  resolution := rrNotFound;
  ambiguous := False;
  starResolution.Module := nil;
  starResolution.BindingName := '';
  for i := 0 to High(AModule.StarExportEntries) do
  begin
    starModule := AModule.DependencyFor(AModule.StarExportEntries[i].ModuleRequest);
    if starModule = nil then
      Continue;
    sub := FloriaJSResolveExport(starModule, AExportName, AResolveSet, subBinding);
    if sub = rrAmbiguous then
      Exit(rrAmbiguous);
    if sub = rrResolved then
    begin
      if resolution = rrNotFound then
      begin
        resolution := rrResolved;
        starResolution := subBinding;
      end
      else if (starResolution.Module <> subBinding.Module) or
              (starResolution.BindingName <> subBinding.BindingName) then
        ambiguous := True;
    end;
  end;

  if ambiguous then
    Exit(rrAmbiguous);
  if resolution = rrResolved then
  begin
    ABinding := starResolution;
    Exit(rrResolved);
  end;
  Result := rrNotFound;
end;

end.
