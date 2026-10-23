program test_comma2;
uses
  SysUtils, floria.js.lexer, floria.js.parser, floria.js.evaluator, floria.js.value, floria.js.env, floria.js.stdlib;
var
  L: TFloriaJSLexer;
  P: TFloriaJSParser;
  E: TFloriaJSEvaluator;
  Prog: TFloriaJSProgram;
  Heap: TFloriaJSHeap;
  Env: TFloriaJSEnvironment;
  Res: TFloriaJSValue;
begin
  Heap := TFloriaJSHeap.Create();
  Env := TFloriaJSEnvironment.Create(nil);
  Heap.TrackEnvironment(Env);
  FloriaJSRegisterStdLib(Env, Heap, nil);
  E := TFloriaJSEvaluator.Create(Heap);
  L := TFloriaJSLexer.Create('var a = (1, 2); a;');
  P := TFloriaJSParser.Create(L);
  Prog := P.ParseProgram();
  if P.HasErrors() then
    Writeln('ERR: ' + P.GetError(0))
  else
  begin
    Res := E.ExecuteProgram(Prog, Env);
    Writeln(Res.ToString());
  end;
  P.Free;
  L.Free;
  E.Free;
  Heap.Free;
end.
