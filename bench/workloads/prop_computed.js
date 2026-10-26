// Computed keys take the slower key path.
var o = {};
var k = "v";
for (var i = 0; i < 2000; i++) {
  o[k] = i;
}
o[k];
