/*---
flags: [module]
---*/
import { value, bump } from "./module-live-dep.js";
if (value !== 1) throw new Error("initial value " + value);
bump();
if (value !== 2) throw new Error("live value " + value);
