import { a } from "./module-cycle-a.js";
export let b = 2;
export function getA() { return a; }
