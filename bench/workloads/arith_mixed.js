// A tight numeric loop, isolating operator dispatch.
var x = 1;
for (var i = 0; i < 10000; i++) {
  x = (x * 3 + 7) % 1000;
}
x;
