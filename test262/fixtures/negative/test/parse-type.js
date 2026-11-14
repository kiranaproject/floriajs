/*---
negative:
  phase: parse
  type: TypeError
---*/
throw new TypeError("runtime TypeError must not satisfy a parse expectation");
