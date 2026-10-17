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

var
  Engine: TFloriaJSEngine;
  Ctx: TFloriaJSContext;
  Res: TFloriaJSResult;

begin
  WriteLn('Floria JS Engine: Initializing...');
  Engine := TFloriaJSEngine.Create();
  try
    Ctx := Engine.DefaultContext;
    Ctx.SetVariable('version', FLORIA_JS_VERSION_STRING);
    WriteLn('Default context name: ', Ctx.Name);
    WriteLn('Context variable "version": ', Ctx.GetVariable('version'));

    Res := Ctx.Evaluate('console.log("Hello from FloriaJS!");');
    if Res.Success then
      WriteLn('Evaluation succeeded: ', Res.StringValue)
    else
      WriteLn('Evaluation failed: ', Res.ErrorMessage);
  finally
    Engine.Free();
  end;
  WriteLn('Floria JS Engine: Cleaned up successfully.');
end.
