{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Declarative QML & JS Parser Demo                }
{                                                                          }
{   Demonstrates parsing declarative QML-style UI component trees with     }
{   reactive bindings, signal handlers, and child hierarchies.             }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

program parse_qml_demo;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, floriajs;

procedure PrintComponent(AComp: TFloriaJSQMLComponent; AIndent: string);
var
  i: Integer;
begin
  if AComp = nil then Exit;

  WriteLn(AIndent, '+-- Component: ', AComp.ComponentType, ' [id: "', AComp.Id, '"]');

  // Properties
  for i := 0 to AComp.GetPropertyCount() - 1 do
  begin
    WriteLn(AIndent, '    |-- Property: ', AComp.GetPropertyName(i));
  end;

  // Signals
  for i := 0 to AComp.GetSignalCount() - 1 do
  begin
    WriteLn(AIndent, '    |-- Signal:   ', AComp.GetSignalName(i));
  end;

  // Children
  for i := 0 to AComp.GetChildCount() - 1 do
  begin
    PrintComponent(AComp.GetChild(i), AIndent + '    ');
  end;
end;

var
  source: string;
  parser: TFloriaJSParser;
  comp: TFloriaJSQMLComponent;

begin
  WriteLn('=== Floria JS — Declarative QML Component Parser Demo ===');
  WriteLn();

  source :=
    'Rectangle {' + LineEnding +
    '  id: mainWindow' + LineEnding +
    '  width: 800;' + LineEnding +
    '  height: 600;' + LineEnding +
    '  color: "#1e1e2e";' + LineEnding +
    '  onClicked: {' + LineEnding +
    '    console.log("Window clicked!");' + LineEnding +
    '  }' + LineEnding +
    '  Button {' + LineEnding +
    '    id: submitBtn' + LineEnding +
    '    text: "Submit";' + LineEnding +
    '    width: 120;' + LineEnding +
    '    height: 40;' + LineEnding +
    '    onClicked: {' + LineEnding +
    '      handleSubmit();' + LineEnding +
    '    }' + LineEnding +
    '  }' + LineEnding +
    '  Text {' + LineEnding +
    '    id: statusLabel' + LineEnding +
    '    text: "Ready";' + LineEnding +
    '  }' + LineEnding +
    '}';

  WriteLn('Input QML Script:');
  WriteLn('----------------------------------------------------');
  WriteLn(source);
  WriteLn('----------------------------------------------------');
  WriteLn();

  parser := TFloriaJSParser.Create(source);
  try
    comp := parser.ParseQMLComponent();
    try
      if parser.HasErrors() then
      begin
        WriteLn('Errors encountered during parsing:');
        WriteLn(parser.GetError(0));
      end
      else
      begin
        WriteLn('Parsed QML Component Hierarchy:');
        PrintComponent(comp, '');
        WriteLn();
        WriteLn('Success! Declarative component tree parsed cleanly.');
      end;
    finally
      comp.Free();
    end;
  finally
    parser.Free();
  end;
end.
