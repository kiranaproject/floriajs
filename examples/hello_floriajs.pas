{ ************************************************************************** }
{                                                                          }
{   Floria JS (floriajs) — Hello World Example                             }
{                                                                          }
{   Copyright (c) 2026 Dio Affriza                                         }
{   SPDX-License-Identifier: MPL-2.0                                       }
{                                                                          }
{ ************************************************************************** }

program hello_floriajs;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, floriajs;

function PascalSquare(const AArgs: array of TFloriaJSValue; AThis: TFloriaJSValue): TFloriaJSValue;
begin
  if Length(AArgs) > 0 then
    Result := JSMakeNumber(AArgs[0].ToNumber() * AArgs[0].ToNumber())
  else
    Result := JSMakeNumber(0.0);
end;

var
  Engine: TFloriaJSEngine;
  Ctx: TFloriaJSContext;
  Res: TFloriaJSResult;
  i: Integer;

begin
  WriteLn('=== Floria JS — Pure Pascal JavaScript Engine Demo ===');
  WriteLn('Engine Version: ', FLORIA_JS_VERSION_STRING);
  WriteLn();

  Engine := TFloriaJSEngine.Create();
  try
    Ctx := Engine.DefaultContext;

    // 1. Host Interop: Register native Pascal function in JS
    Ctx.RegisterFunction('pascalSquare', @PascalSquare);

    // 2. Execute JavaScript script with math, functions, and console
    Res := Ctx.Evaluate(
      'console.log("Hello from pure Object Pascal JavaScript Engine!");' + LineEnding +
      'let radius = 7;' + LineEnding +
      'let area = Math.PI * pascalSquare(radius);' + LineEnding +
      'console.log("Circle area for radius " + radius + " is " + Math.round(area * 100) / 100);' + LineEnding +
      '' + LineEnding +
      'function factorial(n) {' + LineEnding +
      '  if (n <= 1) return 1;' + LineEnding +
      '  return n * factorial(n - 1);' + LineEnding +
      '}' + LineEnding +
      'console.log("Factorial of 6 is " + factorial(6));' + LineEnding +
      'area;'
    );

    // 3. Print captured console logs
    for i := 0 to Ctx.Output.Count - 1 do
      WriteLn('[JS Console] ', Ctx.Output[i]);

    WriteLn();
    if Res.Success then
      WriteLn('Script Return Value: ', Res.StringValue)
    else
      WriteLn('Execution Error: ', Res.ErrorMessage);
  finally
    Engine.Free();
  end;
  WriteLn();
  WriteLn('Floria JS Engine: Cleaned up successfully.');
end.
