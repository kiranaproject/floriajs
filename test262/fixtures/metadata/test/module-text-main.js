/*---
flags: [module]
---*/
import value from "./module-text_FIXTURE" with { type: "text" };
if (typeof value !== "string" || value.indexOf("hello from text") < 0) {
  throw new Error("text module failed: " + value);
}
