// Many short-lived objects: allocation, and a baseline for collection cost.
var n = 0;
for (var i = 0; i < 2000; i++) {
  var o = { v: i };
  n = n + o.v;
}
n;
