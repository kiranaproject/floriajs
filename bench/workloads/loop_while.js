// `while` has no increment clause and a different dispatch shape.
var i = 0;
var s = 0;
while (i < 10000) {
  s = s + 1;
  i = i + 1;
}
s;
