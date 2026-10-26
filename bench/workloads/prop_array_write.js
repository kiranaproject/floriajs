// Array element writes, the hot path for UI state.
var a = [];
for (var i = 0; i < 5000; i++) {
  a[i] = i;
}
a.length;
