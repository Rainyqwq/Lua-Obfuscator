// ================================================================
// build_html.js
// Sync obfuscator_bundle.lua into index.html's OBFUSCATOR_LUA section
//
// Author: Rainy_qwq
// URL:    https://github.com/Rainyqwq/Lua-Obfuscator
// License: MIT
// ================================================================
// The Lua bundle is embedded in a JS template literal (backtick string).
// JS template literals process escape sequences (\n -> newline, \\ -> \),
// which corrupts Lua source containing backslash escapes in string literals.
// This script doubles all backslashes so JS produces the correct literal text.

const fs = require('fs');
const path = require('path');

const bundlePath = path.join(__dirname, 'obfuscator_bundle.lua');
const htmlPath = path.join(__dirname, 'index.html');

// --- Read bundle ---
let bundle = fs.readFileSync(bundlePath, 'utf-8');

// Strip shebang if present
const shebangIdx = bundle.indexOf('#!');
if (shebangIdx === 0) {
  bundle = bundle.substring(bundle.indexOf('\n') + 1);
}

// Escape backslashes for JS template literal: \ -> \\
// (backticks and ${ are not present in the bundle, verified at build time)
const escaped = bundle.replace(/\\/g, '\\\\');

// --- Read index.html ---
let html = fs.readFileSync(htmlPath, 'utf-8');

// Find the OBFUSCATOR_LUA template literal section
const startMarker = 'const OBFUSCATOR_LUA = `';
const startPos = html.indexOf(startMarker);
if (startPos < 0) {
  console.error('ERROR: "const OBFUSCATOR_LUA = `" marker not found in index.html');
  process.exit(1);
}

const contentStart = startPos + startMarker.length;

// Find the closing backtick, skipping over backslash-escaped characters
let pos = contentStart;
let endPos = -1;
while (pos < html.length) {
  if (html[pos] === '\\') { pos += 2; continue; }
  if (html[pos] === '`') { endPos = pos; break; }
  pos++;
}
if (endPos < 0) {
  console.error('ERROR: closing backtick for OBFUSCATOR_LUA not found');
  process.exit(1);
}

// Replace content between backticks
const newHtml = html.substring(0, contentStart) + escaped + html.substring(endPos);

fs.writeFileSync(htmlPath, newHtml, 'utf-8');

console.log('index.html updated:');
console.log('  Old content length:', endPos - contentStart, 'chars');
console.log('  New content length:', escaped.length, 'chars');
console.log('  Bundle source length:', bundle.length, 'chars');
console.log('  Backslash escapes added:', (escaped.length - bundle.length));
