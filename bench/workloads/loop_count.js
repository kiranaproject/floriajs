// Counting loop: the cheapest dispatch path, so it exposes raw per-instruction
// overhead. Returns a value so the work cannot be optimised away.
var s = 0;
for (var i = 0; i < 10000; i++) {
  s = s + 1;
}
s;
