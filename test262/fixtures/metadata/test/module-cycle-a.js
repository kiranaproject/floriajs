import { b } from "./module-cycle-b.js";
export let a = 1;
export function getB() { return b; }
