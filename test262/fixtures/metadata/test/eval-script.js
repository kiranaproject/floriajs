/*---
flags: [noStrict]
---*/
$262.evalScript('var metadataNested = 1;');
print($262.global === globalThis);
