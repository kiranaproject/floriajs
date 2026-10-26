// String concatenation in a loop: allocates, so it also measures the heap.
var s = "";
for (var i = 0; i < 2000; i++) {
  s = s + "x";
}
s.length;
