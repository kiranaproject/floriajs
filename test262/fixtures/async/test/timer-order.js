/*---
flags: [async]
---*/
var order = [];

setTimeout(function () {
  order.push(1);
}, 0);

setTimeout(function () {
  order.push(2);
  print(order.join(","));
  $DONE();
}, 0);
