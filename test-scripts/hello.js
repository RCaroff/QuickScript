#!/usr/bin/env node
//
// Test Node.js — vérifie que QuickScript exécute correctement les scripts
// .js / .mjs via node, transmet les @param en argv, et expose les variables
// QS_CONTEXT_*.
//
// @param name=world  Prénom à saluer
//
const args = process.argv.slice(2);
const name = args[0] || "world";

console.log(`Hello, ${name}!  (node ${process.version})`);
console.log(`argv         : ${JSON.stringify(args)}`);
console.log(`QS_FILE_PATH : ${process.env.QS_CONTEXT_FILE_PATH || "(unset)"}`);
console.log(`QS_TARGET    : ${process.env.QS_CONTEXT_TARGET_PATH || "(unset)"}`);
