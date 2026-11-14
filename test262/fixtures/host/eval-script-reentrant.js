function stress() {
  var keep = { value: 7 };
  var total = 0;
  for (var i = 0; i < 20; i++) {
    total += $262.evalScript('var scratch = { value: ' + i + ' }; scratch.value;');
  }
  return keep.value + total;
}

var nested = $262.evalScript('$262.evalScript("var deep = 3; deep;")');
print(stress());
print(nested);
