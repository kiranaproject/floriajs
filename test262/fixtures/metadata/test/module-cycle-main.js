/*---
flags: [module]
---*/
import { a, getB } from "./module-cycle-a.js";
import { b, getA } from "./module-cycle-b.js";
if (a !== 1 || b !== 2 || getB() !== 2 || getA() !== 1) {
  throw new Error("cycle/live binding failed: " + a + "," + b + "," + getB() + "," + getA());
}
