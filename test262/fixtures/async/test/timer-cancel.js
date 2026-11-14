/*---
flags: [async]
---*/
var fired = false;
var cancelled = setTimeout(function () {
  fired = true;
  print("cancelled-ran");
}, 0);
clearTimeout(cancelled);

setTimeout(function () {
  print(fired ? "cancelled-ran" : "cancelled-blocked");
  $DONE();
}, 0);
