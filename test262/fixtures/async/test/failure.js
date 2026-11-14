/*---
flags: [async]
---*/
Promise.resolve().then(function () {
  $DONE(new TypeError("expected async failure"));
});
