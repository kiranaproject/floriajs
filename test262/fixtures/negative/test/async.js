/*---
flags: [async]
negative:
  phase: runtime
  type: TypeError
---*/
throw new TypeError("async is not supported");
