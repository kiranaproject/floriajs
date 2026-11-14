/*---
flags: [async]
---*/
var count = 0;
var id = setInterval(function () {
  count += 1;
  if (count === 3) {
    clearInterval(id);
    print("count=" + count);
    $DONE();
  }
}, 0);
