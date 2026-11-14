/*---
flags: [async]
---*/
var completed = false;
Promise.resolve(1).then(function () {
  completed = true;
});
