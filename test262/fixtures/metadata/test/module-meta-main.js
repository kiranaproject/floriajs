/*---
flags: [module, async]
---*/
if (import.meta.url.indexOf("module-meta-main.js") < 0) {
  throw new Error("import.meta.url missing");
}
import("./module-live-dep.js").then(function (ns) {
  if (ns.value !== 1) throw new Error("dynamic import value " + ns.value);
  $DONE();
}, $DONE);
