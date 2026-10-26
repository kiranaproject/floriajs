// **************************************************************************
//
//   Floria JS — Node Reference Runner
//
//   Runs the same .js workloads as `bench/runner` under Node, so the two can
//   be compared on equal terms. Node is the reference implementation: the
//   ratio of floriajs time to Node time is what is portable across machines,
//   because both run on the same hardware.
//
//   Usage:  node bench/node/run_node.js <dir-of-workloads>
//
//   Output matches the Pascal runner exactly:
//     name <TAB> runs <TAB> total_us <TAB> per_run_us <TAB> result
//
//   Copyright (c) 2026 Dio Affriza
//   SPDX-License-Identifier: MPL-2.0
//
// **************************************************************************

'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

// Must match RUNS in bench/runner/src/main/pascal/runner.pas.
const RUNS = 41;

function nowMicros() {
  // process.hrtime.bigint() is monotonic and nanosecond-resolution.
  return process.hrtime.bigint();
}

function microsBetween(startNs, endNs) {
  return Number((endNs - startNs) / 1000n);
}

// Runs one workload in a fresh context, exactly as the Pascal runner uses a
// fresh engine. A shared context would let one workload's globals and heap
// affect the next, and would flatter whichever workload ran last.
function runOnce(source) {
  const context = vm.createContext({});
  const start = nowMicros();
  const result = vm.runInContext(source, context, { filename: 'workload.js' });
  const elapsed = microsBetween(start, nowMicros());
  return { elapsed, result };
}

function collect(dir) {
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.js'))
    .sort()
    .map((f) => ({
      name: path.basename(f, '.js'),
      source: fs.readFileSync(path.join(dir, f), 'utf8'),
    }));
}

function main() {
  // `--file <path>` runs one workload, which lets the caller interleave the two
  // engines per workload and cancel the warm-up bias of always running one of
  // them first. `--dir` runs them all.
  const fileFlag = process.argv.indexOf('--file');
  const dir = fileFlag >= 0 ? null : process.argv[2];
  let workloads;
  if (fileFlag >= 0) {
    const file = process.argv[fileFlag + 1];
    workloads = [{ name: path.basename(file, '.js'), source: fs.readFileSync(file, 'utf8') }];
  } else {
    if (!dir) {
      console.error('usage: node run_node.js <dir-of-workloads> | --file <workload.js>');
      process.exit(2);
    }
    workloads = collect(dir);
  }
  if (workloads.length === 0) {
    console.error('no workloads found in ' + dir);
    process.exit(2);
  }

  console.log(['name', 'runs', 'total_us', 'per_run_us', 'result'].join('\t'));

  for (const w of workloads) {
    // One warm-up run, matching the Pascal runner: the first execution pays for
    // JIT warm-up and lazily created built-ins that later runs do not.
    runOnce(w.source);

    let best = Infinity;
    let total = 0;
    let resultText = '';
    for (let k = 0; k < RUNS; k++) {
      const { elapsed, result } = runOnce(w.source);
      total += elapsed;
      if (elapsed < best) best = elapsed;
      resultText = result === undefined ? 'undefined' : String(result);
    }

    console.log([w.name, RUNS, total, best, resultText].join('\t'));
  }
}

main();
