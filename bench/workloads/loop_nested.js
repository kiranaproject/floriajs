// Nested loop, to show whether the outer loop's cost is amortised.
var s = 0;
for (var i = 0; i < 100; i++) {
  for (var j = 0; j < 100; j++) {
    s = s + 1;
  }
}
s;
