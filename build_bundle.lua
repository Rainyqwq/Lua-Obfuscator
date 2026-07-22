-- ================================================================
-- build_bundle.lua
-- 构建脚本：将所有 Pass 模块内联到 obfuscator
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 读取 obfuscator.lua + 所有 pass 文件，生成单一 bundle Lua 文件

local function read_file(path)
  local f = io.open(path, "r")
  if not f then error("Cannot read: " .. path) end
  local c = f:read("*a")
  f:close()
  return c
end

local function strip_shebang(code)
  -- Strip UTF-8 BOM then an optional leading shebang only.
  if code:sub(1, 3) == "\239\187\191" then
    code = code:sub(4)
  elseif code:byte(1) == 0xFEFF then
    code = code:sub(2)
  end
  local start = 1
  while true do
    local c = code:sub(start, start)
    if c == " " or c == "\t" or c == "\r" or c == "\n" then
      start = start + 1
    else
      break
    end
  end
  if code:sub(start, start + 1) == "#!" then
    local nl = code:find("\n", start, true)
    if nl then
      code = code:sub(nl + 1)
    else
      code = ""
    end
  elseif start > 1 then
    code = code:sub(start)
  end
  return code
end

local function escape_lua_string(code)
  -- Use [=...[...]=] long string to avoid escaping issues
  -- Find the right level of = signs that doesn't appear in the code
  local level = 0
  while true do
    local sep = string.rep("=", level)
    local close = "]" .. sep .. "]"
    if not code:find(close, 1, true) then
      local open = "[" .. sep .. "["
      return open .. code .. close
    end
    level = level + 1
  end
end

-- Read all pass files
local pass_files = {
  {"pass_manager", "pass_manager.lua"},
  {"passes", "passes/init.lua"},
  {"passes.utils", "passes/utils.lua"},
  {"passes.string_pool", "passes/string_pool.lua"},
  {"passes.vm", "passes/vm.lua"},
  {"passes.vm_protect", "passes/vm_protect.lua"},
  {"passes.string_encrypt", "passes/string_encrypt.lua"},
  {"passes.var_mangle", "passes/var_mangle.lua"},
  {"passes.num_encrypt", "passes/num_encrypt.lua"},
  {"passes.instr_sub", "passes/instr_sub.lua"},
  {"passes.adv_fake_cf", "passes/adv_fake_cf.lua"},
  {"passes.cf_flatten", "passes/cf_flatten.lua"},
 {"passes.bcf", "passes/bcf.lua"},
  {"passes.bb_split", "passes/bb_split.lua"},
 {"passes.junk_comment", "passes/junk_comment.lua"},
  {"passes.header", "passes/header.lua"},
  {"passes.init", "passes/init.lua"},
}

-- Build the bundle
local parts = {}

-- Add package.preload registrations
parts[#parts + 1] = "-- Auto-generated bundle: all pass modules inlined\n"
parts[#parts + 1] = "do\n"

for _, pf in ipairs(pass_files) do
  local module_name, file_path = pf[1], pf[2]
  local code = strip_shebang(read_file(file_path))
  local escaped = escape_lua_string(code)
  parts[#parts + 1] = string.format(
    '  package.preload[%q] = function()\n    return load(%s, %q)()\n  end\n',
    module_name, escaped, "@" .. file_path
  )
end

parts[#parts + 1] = "end\n\n"

-- Add the obfuscator code
local obf_code = strip_shebang(read_file("obfuscator.lua"))
parts[#parts + 1] = obf_code

local bundle = table.concat(parts)

-- Write output
local out = io.open("obfuscator_bundle.lua", "w")
out:write(bundle)
out:close()

print(string.format("Bundle: %d bytes (%d modules)", #bundle, #pass_files))
