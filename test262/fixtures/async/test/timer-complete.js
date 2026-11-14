/*---
flags: [async]
---*/
setTimeout(function (left, right) {
  print(left + "," + right);
  $DONE();
}, 0, "x", "y");
