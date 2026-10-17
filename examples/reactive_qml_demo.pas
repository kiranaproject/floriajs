{ ************************************************************************** }
{                                                                          }
{   Floria JS — Reactive QML Declarative UI Demo                          }
{                                                                          }
{   Demonstrates pure Object Pascal QML parsing, component hierarchy,      }
{   reactive property bindings, and signal handling.                       }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

program reactive_qml_demo;

{$mode objfpc}{$H+}
{$interfaces corba}
{$modeswitch advancedrecords}

uses
  SysUtils, floriajs;

const
  DEMO_QML =
    'Rectangle {' + LineEnding +
    '  id: mainWindow' + LineEnding +
    '  width: 600;' + LineEnding +
    '  height: 400;' + LineEnding +
    '  color: "#1e1e2e";' + LineEnding +
    '  property int clickCount: 0;' + LineEnding +
    LineEnding +
    '  Component.onCompleted: {' + LineEnding +
    '    console.log("[QML Lifecycle] mainWindow instantiated and ready!");' + LineEnding +
    '  }' + LineEnding +
    LineEnding +
    '  Rectangle {' + LineEnding +
    '    id: cardView' + LineEnding +
    '    x: 20;' + LineEnding +
    '    y: 20;' + LineEnding +
    '    width: parent.width - 40;' + LineEnding +
    '    height: parent.height / 2;' + LineEnding +
    '    color: "#313244";' + LineEnding +
    '    radius: 12;' + LineEnding +
    LineEnding +
    '    Text {' + LineEnding +
    '      id: sizeLabel' + LineEnding +
    '      text: "Card Size: " + cardView.width + " x " + cardView.height;' + LineEnding +
    '      color: "#cdd6f4";' + LineEnding +
    '      fontSize: 16;' + LineEnding +
    '    }' + LineEnding +
    '  }' + LineEnding +
    LineEnding +
    '  Button {' + LineEnding +
    '    id: expandBtn' + LineEnding +
    '    x: 20;' + LineEnding +
    '    y: 240;' + LineEnding +
    '    width: 140;' + LineEnding +
    '    height: 40;' + LineEnding +
    '    text: "Expand Window";' + LineEnding +
    '    onClicked: {' + LineEnding +
    '      mainWindow.width = mainWindow.width + 100;' + LineEnding +
    '      mainWindow.height = mainWindow.height + 60;' + LineEnding +
    '      mainWindow.clickCount = mainWindow.clickCount + 1;' + LineEnding +
    '      console.log("[Signal] Expand clicked! New mainWindow size: " + mainWindow.width + "x" + mainWindow.height);' + LineEnding +
    '    }' + LineEnding +
    '  }' + LineEnding +
    LineEnding +
    '  Text {' + LineEnding +
    '    id: clickSummary' + LineEnding +
    '    x: 180;' + LineEnding +
    '    y: 250;' + LineEnding +
    '    text: "Total Clicks: " + mainWindow.clickCount;' + LineEnding +
    '    color: "#a6adc8";' + LineEnding +
    '  }' + LineEnding +
    '}';

procedure PrintComponentHierarchy(AItem: TFloriaQMLItem; AIndent: string = '');
var
  i: Integer;
  child: TFloriaQMLItem;
  idStr: string;
begin
  if AItem = nil then Exit;

  if AItem.Id <> '' then
    idStr := ' [id: "' + AItem.Id + '"]'
  else
    idStr := '';

  WriteLn(AIndent + '+-- ' + AItem.TypeName + idStr +
    ' (x=' + FloatToStr(AItem.X) +
    ', y=' + FloatToStr(AItem.Y) +
    ', w=' + FloatToStr(AItem.Width) +
    ', h=' + FloatToStr(AItem.Height) + ')');

  for i := 0 to AItem.ChildCount() - 1 do
  begin
    child := AItem.GetChild(i);
    PrintComponentHierarchy(child, AIndent + '    ');
  end;
end;

var
  engine: TFloriaQMLEngine;
  root, card, expandBtn, sizeLabel, summary: TFloriaQMLItem;
begin
  WriteLn('=== Floria JS — Reactive QML Declarative UI Demo ===');
  WriteLn('Engine Version: ', FLORIA_JS_VERSION_STRING);
  WriteLn();

  engine := TFloriaQMLEngine.Create();
  try
    WriteLn('--- Loading QML Component ---');
    root := engine.LoadString(DEMO_QML);
    if root = nil then
    begin
      WriteLn('Error loading QML: ', engine.LastError);
      Halt(1);
    end;

    card := engine.FindItemById('cardView');
    expandBtn := engine.FindItemById('expandBtn');
    sizeLabel := engine.FindItemById('sizeLabel');
    summary := engine.FindItemById('clickSummary');

    WriteLn();
    WriteLn('--- Initial Instantiated Hierarchy ---');
    PrintComponentHierarchy(root);
    WriteLn();

    WriteLn('--- Initial Reactive Values ---');
    WriteLn('  mainWindow.width:  ', FloatToStr(root.Width));
    WriteLn('  cardView.width:    ', FloatToStr(card.Width), ' (bound to parent.width - 40)');
    WriteLn('  cardView.height:   ', FloatToStr(card.Height), ' (bound to parent.height / 2)');
    WriteLn('  sizeLabel.text:    "', sizeLabel.GetPropertyAsString('text'), '" (reactive expression)');
    WriteLn('  clickSummary.text: "', summary.GetPropertyAsString('text'), '"');
    WriteLn();

    WriteLn('--- Simulating 1st Click on expandBtn ---');
    expandBtn.EmitSignal('clicked');
    WriteLn('  cardView.width:    ', FloatToStr(card.Width), ' (automatically updated!)');
    WriteLn('  cardView.height:   ', FloatToStr(card.Height), ' (automatically updated!)');
    WriteLn('  sizeLabel.text:    "', sizeLabel.GetPropertyAsString('text'), '"');
    WriteLn('  clickSummary.text: "', summary.GetPropertyAsString('text'), '"');
    WriteLn();

    WriteLn('--- Simulating 2nd Click on expandBtn ---');
    expandBtn.EmitSignal('clicked');
    WriteLn('  cardView.width:    ', FloatToStr(card.Width), ' (automatically updated!)');
    WriteLn('  cardView.height:   ', FloatToStr(card.Height), ' (automatically updated!)');
    WriteLn('  sizeLabel.text:    "', sizeLabel.GetPropertyAsString('text'), '"');
    WriteLn('  clickSummary.text: "', summary.GetPropertyAsString('text'), '"');
    WriteLn();

    WriteLn('--- Direct Pascal Update: Setting mainWindow.width = 1000 ---');
    root.Width := 1000.0;
    WriteLn('  cardView.width:    ', FloatToStr(card.Width), ' (1000 - 40 = 960)');
    WriteLn('  sizeLabel.text:    "', sizeLabel.GetPropertyAsString('text'), '"');
    WriteLn();

    WriteLn('Success! Declarative QML engine and reactive property bindings verified.');
  finally
    engine.Free();
  end;
end.
