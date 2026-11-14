/*---
flags: [async]
---*/
var order = [];

Promise.resolve(1).then(function (value) {
  order.push(value);
  return Promise.resolve(2);
}).then(function (value) {
  order.push(value);
  print(order.join(","));
  $DONE();
});
