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

// ================================================================
// Inline lib/fengari-web.js as a JS string constant so the Web Worker
// can eval() it without a network fetch (which fails on file://).
// Patch the UMD root from `window` to `self`: a blob Worker has no
// `window`, but `self` is the global in both Workers and the main
// thread (where self === window).
// ================================================================
const fengariPath = path.join(__dirname, 'lib', 'fengari-web.js');
let fengariSrc = fs.readFileSync(fengariPath, 'utf8');

// Strip leading UTF-8 BOM if present
if (fengariSrc.charCodeAt(0) === 0xFEFF) {
  fengariSrc = fengariSrc.slice(1);
}

// Patch the single UMD root injection: }(window,function(){ -> }(self,function(){
const umdFrom = '(window,function(){';
const umdTo = '(self,function(){';
const umdCount = fengariSrc.split(umdFrom).length - 1;
if (umdCount !== 1) {
  console.error('ERROR: expected exactly 1 UMD root "(window,function(){" in fengari-web.js, found ' + umdCount);
  process.exit(1);
}
fengariSrc = fengariSrc.replace(umdFrom, umdTo);

// Escape for a JS template literal: \ -> \\, ` -> \`, ${ -> \${
let fengariEscaped = fengariSrc
  .replace(/\\/g, '\\\\')
  .replace(/`/g, '\\`')
  .replace(/\$\{/g, '\\${');

// Re-read the freshly-written index.html and inject `const FENGARI_SOURCE = \`…\`;`
// right after the <script src="lib/fengari-web.js"></script> tag.
let html2 = fs.readFileSync(htmlPath);
if (html2[0] === 0xEF && html2[1] === 0xBB && html2[2] === 0xBF) {
  html2 = html2.slice(3);
}

const injectHead = Buffer.from('\n<script>\n// Inlined fengari source for the Web Worker (file://-safe; UMD root patched window->self)\nconst FENGARI_SOURCE = `');
const injectTail = Buffer.from('`;\n</script>\n');

// Idempotency: strip any previously-injected FENGARI_SOURCE block so re-running
// build_html.js doesn't accumulate duplicates (a duplicate `const` would crash the page).
html2 = stripInjected(html2, injectHead, injectTail);

const fengariTag = Buffer.from('<script src="lib/fengari-web.js"></script>');
const tagPos = indexOf(html2, fengariTag);
if (tagPos < 0) {
  console.error('ERROR: "<script src="lib/fengari-web.js"></script>" marker not found in index.html');
  process.exit(1);
}
const injectPos = tagPos + fengariTag.length;

const newHtml2 = Buffer.concat([
  html2.slice(0, injectPos),
  injectHead,
  Buffer.from(fengariEscaped, 'utf8'),
  injectTail,
  html2.slice(injectPos),
]);

fs.writeFileSync(htmlPath, newHtml2);

console.log('FENGARI_SOURCE inlined:');
console.log('  fengari source length:', fengariSrc.length, 'chars');
console.log('  inlined (escaped) length:', fengariEscaped.length, 'chars');
console.log('  UMD root patched: window -> self (' + umdCount + ' occurrence)');

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

// Helper: remove a previously-injected block delimited by head..tail (inclusive).
// Used to keep FENGARI_SOURCE injection idempotent across repeated builds.
function stripInjected(buf, head, tail) {
  const out = [];
  let pos = 0;
  while (true) {
    const h = indexOf(buf, head, pos);
    if (h < 0) break;
    const t = indexOf(buf, tail, h + head.length);
    if (t < 0) break; // unbalanced; leave the rest untouched
    out.push(buf.slice(pos, h));
    pos = t + tail.length;
  }
  if (pos === 0) return buf; // nothing stripped
  out.push(buf.slice(pos));
  return Buffer.concat(out);
}
