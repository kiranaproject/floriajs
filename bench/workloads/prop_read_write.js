// Reads and writes on a small object: the ordinary property path.
var o = { a: 0 };
for (var i = 0; i < 5000; i++) {
  o.a = o.a + 1;
}
o.a;
