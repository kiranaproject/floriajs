var realm = $262.createRealm();
var other = realm.global;
if (other === globalThis) {
  throw new Error("realm shares the caller global");
}
if (other.Array === Array || other.Object === Object) {
  throw new Error("realm shares caller intrinsics");
}
if (realm.evalScript("var realmLocal = 6; realmLocal * 7;") !== 42) {
  throw new Error("realm evalScript did not run in the realm");
}
if (typeof realmLocal !== "undefined") {
  throw new Error("realm binding leaked into the caller");
}
other.realmValue = 5;
if (typeof realmValue !== "undefined") {
  throw new Error("realm global property leaked into the caller");
}
print(other.Array.prototype instanceof other.Object, other.Array === Array);
