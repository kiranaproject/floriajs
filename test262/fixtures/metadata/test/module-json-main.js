/*---
flags: [module]
---*/
import data from "./module-json-data.json" with { type: "json" };
if (data.name !== "floria" || data.count !== 3 || data.ok !== true || data.items[2] !== null) {
  throw new Error("JSON module failed");
}
