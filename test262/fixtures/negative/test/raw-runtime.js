/*---
flags: [raw]
negative:
  phase: runtime
  type: TypeError
---*/
throw new TypeError("raw expected runtime error");
