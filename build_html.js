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

// --- Read bundle ---
let bundle = fs.readFileSync(bundlePath, 'utf-8');

// Strip leading BOM / shebang only (never mid-file: would drop package.preload)
if (bundle.charCodeAt(0) === 0xFEFF) bundle = bundle.slice(1);
{
  let i = 0;
  while (i < bundle.length && /[ \t\r\n]/.test(bundle[i])) i++;
  if (bundle.startsWith('#!', i)) {
    const nl = bundle.indexOf('\n', i);
    bundle = nl >= 0 ? bundle.slice(nl + 1) : '';
  }
}

// Escape for JS template literal:
// 1) \ -> \\
// 2) ` -> \`
// 3) ${ -> \${
const escaped = bundle
  .replace(/\\/g, '\\\\')
  .replace(/`/g, '\\`')
  .replace(/\$\{/g, '\\${');

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

// Find the closing backtick of THIS template only.
// Prefer the canonical terminator "`;\nconst FEATURES" / "`;\r\nconst FEATURES"
// because inner unescaped backticks may exist in stale builds.
let endPos = -1;
const terminators = [
  '`;\r\nconst FEATURES',
  '`;\nconst FEATURES',
  '`;\r\nconst FEATURES =',
  '`;\nconst FEATURES =',
];
for (const t of terminators) {
  const idx = html.indexOf(t, contentStart);
  if (idx >= 0) {
    endPos = idx;
    break;
  }
}

// Fallback: scan with escape awareness (for partially fixed files)
if (endPos < 0) {
  let pos = contentStart;
  while (pos < html.length) {
    if (html[pos] === '\\') { pos += 2; continue; }
    if (html[pos] === '`') { endPos = pos; break; }
    pos++;
  }
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
console.log('  Backslash/backtick escapes added:', (escaped.length - bundle.length));
console.log('  Escaped backticks:', (bundle.match(/`/g) || []).length);
console.log('  Escaped ${:', (bundle.match(/\$\{/g) || []).length);
