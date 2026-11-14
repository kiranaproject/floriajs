print(typeof $262.global);
print($262.global === globalThis);

var result = $262.evalScript("var nestedValue = 41; nestedValue + 1;");
print(result);
print(nestedValue);

try {
  $262.evalScript('throw new TypeError("nested boom");');
} catch (error) {
  print(error.name + ":" + error.message);
}

try {
  $262.evalScript("var = ;");
} catch (error) {
  print(error.name);
}
