const fs = require('fs');
const fengari = require('fengari');
const lua = fengari.lua;
const lauxlib = fengari.lauxlib;
const lualib = fengari.lualib;

function stripLeadingLuaShebang(code) {
  if (typeof code !== 'string' || !code) return code;
  if (code.charCodeAt(0) === 0xFEFF) code = code.slice(1);
  let i = 0;
  while (i < code.length && (code[i] === ' ' || code[i] === '\t' || code[i] === '\r' || code[i] === '\n')) i++;
  if (code.startsWith('#!', i)) {
    const nl = code.indexOf('\n', i);
    code = nl >= 0 ? code.slice(nl + 1) : '';
  }
  return code;
}

// Extract OBFUSCATOR_LUA from index.html the same way browser template literal does
const html = fs.readFileSync('index.html', 'utf-8');
const marker = 'const OBFUSCATOR_LUA = `';
const start = html.indexOf(marker);
if (start < 0) throw new Error('OBFUSCATOR_LUA not found');
let pos = start + marker.length;
let result = '';
while (pos < html.length) {
  const ch = html[pos];
  if (ch === '\\') { result += html[pos] + html[pos+1]; pos += 2; continue; }
  if (ch === '`') break;
  result += ch; pos++;
}
let code = eval('`' + result + '`');
code = stripLeadingLuaShebang(code);

console.log('code len', code.length);
console.log('has preload', code.includes('package.preload'));
console.log('shebang remaining', code.includes('#!'));

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// Browser-like: disable filesystem module search
const disableFs = `
package.path = ""
package.cpath = ""
package.searchers[2] = nil
package.searchers[3] = nil
package.searchers[4] = nil
`;
let status = lauxlib.luaL_loadbuffer(L, fengari.to_luastring(disableFs), disableFs.length, fengari.to_luastring('=disable'));
if (status !== lua.LUA_OK) throw new Error(lua.lua_tojsstring(L, -1));
status = lua.lua_pcall(L, 0, 0, 0);
if (status !== lua.LUA_OK) throw new Error(lua.lua_tojsstring(L, -1));

status = lauxlib.luaL_loadbuffer(L, fengari.to_luastring(code), code.length, fengari.to_luastring('=obfuscator'));
if (status !== lua.LUA_OK) { console.log('LOAD FAIL', lua.lua_tojsstring(L, -1)); process.exit(1); }
status = lua.lua_pcall(L, 0, 1, 0);
if (status !== lua.LUA_OK) { console.log('EXEC FAIL', lua.lua_tojsstring(L, -1)); process.exit(1); }
console.log('bundle loaded OK (no FS searchers)');

const testCode = `
local ok, mod = pcall(require, "pass_manager")
if not ok then error("pass_manager: "..tostring(mod)) end
local ok2, mod2 = pcall(require, "passes.bb_split")
if not ok2 then error("bb_split: "..tostring(mod2)) end
print("require OK pass_manager + bb_split name=" .. tostring(mod2.name))
local Obf = ...
`;
// stack has module return; keep it
// better: setglobal from stack top
lua.lua_setglobal(L, fengari.to_luastring('_obfuscator'));

const t2 = `
local ok, mod = pcall(require, "pass_manager")
assert(ok, tostring(mod))
local ok2, mod2 = pcall(require, "passes.bb_split")
assert(ok2, tostring(mod2))
print("require OK: " .. tostring(mod2.name))
local O = _obfuscator
local src = [[
local a = 1
print(a + 2)
]]
local out = O.obfuscate_code(src, {
  vm_protect=false, string_encryption=true, variable_mangling=true,
  instruction_substitution=true, constant_encryption=true,
  advanced_fake_cf=true, control_flow_flattening=false,
  bogus_control_flow=true, basic_block_splitting=true, junk_comments=true
})
assert(type(out)=="string" and #out > 0)
print("obfuscate OK len=" .. #out)
`;
status = lauxlib.luaL_loadbuffer(L, fengari.to_luastring(t2), t2.length, fengari.to_luastring('=test'));
if (status !== lua.LUA_OK) { console.log('test LOAD FAIL', lua.lua_tojsstring(L, -1)); process.exit(1); }
status = lua.lua_pcall(L, 0, 0, 0);
if (status !== lua.LUA_OK) { console.log('test EXEC FAIL', lua.lua_tojsstring(L, -1)); process.exit(1); }
console.log('ALL PASS');
lua.lua_close(L);
