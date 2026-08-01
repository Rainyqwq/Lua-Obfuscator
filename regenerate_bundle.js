const fs = require('fs');

// 读取所有源文件
const fileList = [
  ['pass_manager', 'pass_manager.lua'],
  ['passes', 'passes/init.lua'],
  ['passes/init', 'passes/init.lua'],
  ['passes.utils', 'passes/utils.lua'],
  ['passes.string_pool', 'passes/string_pool.lua'],
  ['passes.vm', 'passes/vm.lua'],
  ['passes.vm_protect', 'passes/vm_protect.lua'],
  ['passes.vm_function', 'passes/vm_function.lua'],
  ['passes.string_encrypt', 'passes/string_encrypt.lua'],
  ['passes.var_mangle', 'passes/var_mangle.lua'],
  ['passes.num_encrypt', 'passes/num_encrypt.lua'],
  ['passes.instr_sub', 'passes/instr_sub.lua'],
  ['passes.adv_fake_cf', 'passes/adv_fake_cf.lua'],
  ['passes.cf_flatten', 'passes/cf_flatten.lua'],
  ['passes.bcf', 'passes/bcf.lua'],
  ['passes.bb_split', 'passes/bb_split.lua'],
  ['passes.junk_comment', 'passes/junk_comment.lua'],
  ['passes.header', 'passes/header.lua'],
  ['passes.anti_debug', 'passes/anti_debug.lua'],
  ['passes.call_indirect', 'passes/call_indirect.lua'],
];

// 读取主程序
let obfuscator = fs.readFileSync('obfuscator.lua', 'utf8');
// Strip BOM before concatenating (utf8 mode auto-converts BOM to FEFF char)
if (obfuscator.charCodeAt(0) === 0xFEFF) {
  obfuscator = obfuscator.slice(1);
}
// Strip leading shebang from the top-level obfuscator source.
// After the bundle prelude (`do ... end`), a shebang is no longer at line 1,
// so Lua parses `#!` as invalid syntax (`unexpected symbol near '#'`).
{
  let i = 0;
  while (i < obfuscator.length && /[ \t\r\n]/.test(obfuscator[i])) i++;
  if (obfuscator.startsWith('#!', i)) {
    const nl = obfuscator.indexOf('\n', i);
    obfuscator = nl >= 0 ? obfuscator.slice(nl + 1) : '';
  }
}

// 转义 Lua 字符串 - 严格按照原始逻辑
function escapeLuaString(code) {
  // Strip UTF-8 BOM and shebang
  let start = 0;
  if (code.charCodeAt(0) === 0xFEFF) {
    start = 1;
  }

  // Skip leading whitespace
  let i = start;
  while (i < code.length && (code[i] === ' ' || code[i] === '\t' || code[i] === '\r' || code[i] === '\n')) {
    i++;
  }

  // Skip shebang
  if (code.substring(i, i + 2) === '#!') {
    const nl = code.indexOf('\n', i);
    if (nl !== -1) {
      i = nl + 1;
    } else {
      i = code.length;
    }
  }

  // Trim the code
  if (i > start) {
    code = code.substring(i);
  }

  // Find the right level of = signs for Lua long string
  let level = 0;
  while (true) {
    // Build the closing delimiter: ]===...] where === is level-1 equals signs
    const equals = '='.repeat(level);
    const close = ']' + equals + ']';
    // Check if this exact close sequence appears in the code
    if (code.indexOf(close) === -1) {
      const open = '[' + equals + '[';
      return open + code + close;
    }
    level++;
  }
}

// 构建 bundle
let parts = [];
parts.push('-- Auto-generated bundle: all pass modules inlined\n');
parts.push('do\n\n');

for (const [name, path] of fileList) {
  let code = fs.readFileSync(path, 'utf8');
  // Strip BOM from every embedded module. A BOM at the start of an inlined
  // preload chunk causes load([[...]], name) to return nil under Fengari,
  // which later explodes as "attempt to call a nil value" when the preload
  // function does load(...)().
  if (code.charCodeAt(0) === 0xFEFF) {
    code = code.slice(1);
  }
  const escaped = escapeLuaString(code);
  const chunkName = '@' + path;
  parts.push('  package.preload["' + name + '"] = function()\n');
  parts.push('    return load(' + escaped + ', "' + chunkName + '")()\n');
  parts.push('  end\n\n');
}

parts.push('end\n\n');
parts.push(obfuscator);

const bundle = parts.join('');

// 写回
fs.writeFileSync('obfuscator_bundle.lua', bundle);
console.log('Bundle regenerated! Length:', bundle.length);

// 验证
const check = fs.readFileSync('obfuscator_bundle.lua', 'utf8');

// 找到 vm 模块并验证
const vmPreload = check.indexOf('package.preload["passes.vm"]');
const vmLoadStart = check.indexOf('[[', vmPreload);
const vmEnd = check.indexOf('@passes/vm.lua")()', vmPreload);

if (vmLoadStart > 0 && vmEnd > 0) {
  const vmContent = check.substring(vmLoadStart + 2, vmEnd);
  const vmSource = fs.readFileSync('passes/vm.lua', 'utf8');

  console.log('\nvm module:');
  console.log('  source length:', vmSource.length);
  console.log('  bundle length:', vmContent.length);
  console.log('  has _max_steps:', vmContent.includes('_max_steps'));
  console.log('  has generate_function_vm:', vmContent.includes('generate_function_vm'));
}

// 找到 var_mangle 模块并验证
const varPreload = check.indexOf('package.preload["passes.var_mangle"]');
const varLoadStart = check.indexOf('[[', varPreload);
const varEnd = check.indexOf('@passes/var_mangle.lua")()', varPreload);

if (varLoadStart > 0 && varEnd > 0) {
  const varContent = check.substring(varLoadStart + 2, varEnd);
  console.log('\nvar_mangle module:');
  console.log('  has extract_vm_blocks:', varContent.includes('function extract_vm_blocks'));
  console.log('  has restore_vm_blocks:', varContent.includes('function restore_vm_blocks'));
}

console.log('\n_max_steps = 5000000 total:', (check.match(/_max_steps = 5000000/g) || []).length);
