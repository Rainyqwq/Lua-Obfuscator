// ================================================================
// build_html.js
// Sync obfuscator_bundle.lua into index.html's OBFUSCATOR_LUA section
//
// Author: Rainy_qwq
// URL:    https://github.com/Rainyqwq/Lua-Obfuscator
// License: MIT
// ================================================================
// The Lua bundle is embedded in a JS template literal (backtick string).
// Must escape: backslash, backtick, and ${ so the template does not terminate early.

const fs = require('fs');
const path = require('path');

const bundlePath = path.join(__dirname, 'obfuscator_bundle.lua');
const htmlPath = path.join(__dirname, 'index.html');

// --- Read bundle as Buffer ---
let bundle = fs.readFileSync(bundlePath);

// Strip leading UTF-8 BOM if present
if (bundle[0] === 0xEF && bundle[1] === 0xBB && bundle[2] === 0xBF) {
  bundle = bundle.slice(3);
}

// Strip leading shebang and whitespace
let start = 0;
while (start < bundle.length && (bundle[start] === 0x20 || bundle[start] === 0x09 ||
       bundle[start] === 0x0D || bundle[start] === 0x0A)) start++;
if (bundle[start] === 0x23 && bundle[start + 1] === 0x21) {  // #!
  let nl = start;
  while (nl < bundle.length && bundle[nl] !== 0x0A) nl++;
  start = nl + 1;
}
if (start > 0) bundle = bundle.slice(start);

// --- Read index.html as Buffer ---
let html = fs.readFileSync(htmlPath);

// Strip UTF-8 BOM if present
if (html[0] === 0xEF && html[1] === 0xBB && html[2] === 0xBF) {
  html = html.slice(3);
}

// Find the OBFUSCATOR_LUA template literal section
const startMarker = Buffer.from('const OBFUSCATOR_LUA = `');
const startPos = indexOf(html, startMarker);
if (startPos < 0) {
  console.error('ERROR: "const OBFUSCATOR_LUA = `" marker not found in index.html');
  process.exit(1);
}

const contentStart = startPos + startMarker.length;

// Find the closing backtick of THIS template only.
let endPos = -1;
const terminators = [
  Buffer.from('`;\r\nconst FEATURES'),
  Buffer.from('`;\nconst FEATURES'),
  Buffer.from('`;\r\nconst FEATURES ='),
  Buffer.from('`;\nconst FEATURES ='),
];
for (const t of terminators) {
  const idx = indexOf(html, t, contentStart);
  if (idx >= 0) {
    endPos = idx;
    break;
  }
}

// Fallback: scan for first unescaped backtick
if (endPos < 0) {
  let pos = contentStart;
  while (pos < html.length) {
    if (html[pos] === 0x5C) { pos += 2; continue; }  // backslash escape
    if (html[pos] === 0x60) { endPos = pos; break; }  // backtick
    pos++;
  }
}

if (endPos < 0) {
  console.error('ERROR: closing backtick for OBFUSCATOR_LUA not found');
  process.exit(1);
}

// Escape bundle for JS template literal:
// 1) \ -> \\
// 2) ` -> \`
// 3) ${ -> \${
let escaped = bundle.toString('utf8')
  .replace(/\\/g, '\\\\')
  .replace(/`/g, '\\`')
  .replace(/\$\{/g, '\\${');

// Convert escaped string back to Buffer
const escapedBuf = Buffer.from(escaped, 'utf8');

// Build new HTML
const before = html.slice(0, contentStart);
const after = html.slice(endPos);
const newHtml = Buffer.concat([before, escapedBuf, after]);

fs.writeFileSync(htmlPath, newHtml);

console.log('index.html updated:');
console.log('  Old content length:', endPos - contentStart, 'chars');
console.log('  New content length:', escaped.length, 'chars');
console.log('  Bundle source length:', bundle.length, 'chars');
console.log('  Backslash/backtick escapes added:', (escaped.length - bundle.length));

// Helper: find pattern in Buffer
function indexOf(buf, pattern, start) {
  start = start || 0;
  outer:
  for (let i = start; i <= buf.length - pattern.length; i++) {
    for (let j = 0; j < pattern.length; j++) {
      if (buf[i + j] !== pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}
