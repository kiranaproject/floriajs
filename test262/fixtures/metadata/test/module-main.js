/*---
flags: [module]
---*/
import def, { value, plus as add } from "./module-dep.js";
import * as star from "./module-star.js";
import "./module-star.js";

if (def() + add(value, 1) + star.extra !== 54) {
  throw new Error("module linking failed");
}
