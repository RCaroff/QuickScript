#!/usr/bin/env node
//
// Node.js test — checks that QuickScript correctly runs .js / .mjs
// scripts via node, passes the @param values in argv, and exposes the
// QS_CONTEXT_* variables.
//
// @param name=world  Name to greet
//
const args = process.argv.slice(2);
const name = args[0] || "world";

console.log(`Hello, ${name}!  (node ${process.version})`);
console.log(`argv         : ${JSON.stringify(args)}`);
console.log(`QS_FILE_PATH : ${process.env.QS_CONTEXT_FILE_PATH || "(unset)"}`);
console.log(`QS_TARGET    : ${process.env.QS_CONTEXT_TARGET_PATH || "(unset)"}`);
