// No arguments, to separate argument marshalling from frame cost.
var n = 0;
function f() {
  n = n + 1;
  return n;
}
for (var i = 0; i < 1000; i++) {
  f();
}
n;
