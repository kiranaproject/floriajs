/*---
flags: [async]
---*/
Promise.resolve().then(function () {
  $DONE();
  $DONE();
});
