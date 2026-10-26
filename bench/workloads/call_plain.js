// A plain function called in a loop: frame setup and teardown.
function f(a) {
  return a + 1;
}
var s = 0;
for (var i = 0; i < 1000; i++) {
  s = f(s);
}
s;
