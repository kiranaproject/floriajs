/*---
includes: [throw-fixture.js]
negative:
  phase: runtime
  type: TypeError
---*/
throw new TypeError("test must not run");
