var order = [];

Promise.resolve().then(function () {
  order.push("microtask");
  print(order.join(","));
});

$262.evalScript('order.push("nested");');
order.push("after");
