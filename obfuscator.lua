#!/usr/bin/env lua
-- ================================================================
-- obfuscator.lua
-- Lua 代码混淆器 - 主程序
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
--
-- 职责：
--   1. 加载 Pass 系统
--   2. 提供 CLI 交互界面
--   3. 对外暴露 JS Bridge 接口
--
-- 具体的混淆逻辑在 passes/ 目录下各模块中实现

-- ============================================================
-- 兼容性处理
-- ============================================================
if _VERSION then
  local ver = tonumber(_VERSION:match("Lua (%d+%.%d+)") or "0")
  if ver < 5.3 then
    local ok, bit_lib = pcall(require, "bit") or pcall(require, "bit32")
    if ok and bit_lib then
      rawset(_G, "_bxor", bit_lib.bxor)
      rawset(_G, "_band", bit_lib.band)
      rawset(_G, "_bor",  bit_lib.bor)
      rawset(_G, "_bnot", bit_lib.bnot)
      rawset(_G, "_shl",  bit_lib.lshift)
      rawset(_G, "_shr",  bit_lib.rshift)
    else
      if io and io.stderr then io.stderr:write('[Lua Obfuscator] WARNING: ' .. _VERSION .. ' detected. Bitwise operators (~, &, |) require Lua 5.3+ or LuaJIT with bit library.\n') else print('[Lua Obfuscator] WARNING: ' .. _VERSION .. ' detected. Bitwise operators (~, &, |) require Lua 5.3+ or LuaJIT with bit library.') end
    end
  end
end

-- ============================================================
-- 初始化随机数种子
-- ============================================================
local ok_t, t = pcall(os.time)
local ok_c, c = pcall(os.clock)
if ok_t and ok_c then
  math.randomseed(math.floor(t + c * 1000))
else
  math.randomseed(42)
end

-- ============================================================
-- 版本
-- ============================================================
local VERSION = "2.9.0"

-- ============================================================
-- 加载 Pass 系统
-- ============================================================
local PassManager = require("pass_manager")
local passes_loader = require("passes")

local pm = PassManager.new()
passes_loader.load_all(pm)

-- 字符串池（跨 Pass 共享的特殊流程）
local string_pool = require("passes.string_pool")

-- ============================================================
-- 默认配置（CLI 模式使用）
-- ============================================================
local Config = {
  vm_protect                = false,
  string_encryption         = true,
  variable_mangling         = true,
  instruction_substitution  = true,
  constant_encryption       = true,
  advanced_fake_cf          = true,
  control_flow_flattening   = true,
  bogus_control_flow        = true,
  basic_block_splitting     = true,
  junk_comments             = true,
  anti_debug                = false,
  call_indirection          = true,
  -- P1: protection lists (not pass toggles)
  name_whitelist            = {}, -- identifier names preserved by var_mangle
  string_whitelist          = {}, -- exact string values kept plaintext
  preset                    = "balanced",
}

-- Config key -> Pass name mapping
local CONFIG_TO_PASS = {
  vm_protect                = "vm_protect",
  string_encryption         = "string_encryption",
  variable_mangling         = "variable_mangling",
  instruction_substitution  = "instruction_substitution",
  constant_encryption       = "constant_encryption",
  advanced_fake_cf          = "advanced_fake_cf",
  control_flow_flattening   = "control_flow_flattening",
  bogus_control_flow        = "bogus_control_flow",
  basic_block_splitting     = "basic_block_splitting",
  junk_comments             = "junk_comments",
  anti_debug                = "anti_debug",
  call_indirection          = "call_indirection",
}

local PASS_KEYS = {
  "vm_protect", "string_encryption", "variable_mangling",
  "instruction_substitution", "constant_encryption", "advanced_fake_cf",
  "control_flow_flattening", "bogus_control_flow", "basic_block_splitting",
  "junk_comments", "anti_debug", "call_indirection",
}

-- Protection presets: fast / balanced / max
local PRESETS = {
  fast = {
    vm_protect = false, anti_debug = false,
    string_encryption = true, variable_mangling = true,
    instruction_substitution = false, constant_encryption = true,
    advanced_fake_cf = false, control_flow_flattening = false,
    bogus_control_flow = false, basic_block_splitting = false,
    junk_comments = true, call_indirection = false,
  },
  balanced = {
    vm_protect = false, anti_debug = false,
    string_encryption = true, variable_mangling = true,
    instruction_substitution = true, constant_encryption = true,
    advanced_fake_cf = true, control_flow_flattening = true,
    bogus_control_flow = true, basic_block_splitting = true,
    junk_comments = true, call_indirection = true,
  },
  max = {
    vm_protect = true, anti_debug = true,
    string_encryption = true, variable_mangling = true,
    instruction_substitution = true, constant_encryption = true,
    advanced_fake_cf = true, control_flow_flattening = true,
    bogus_control_flow = true, basic_block_splitting = true,
    junk_comments = true, call_indirection = true,
  },
}

local function copy_list(src)
  local out = {}
  if type(src) ~= "table" then return out end
  for k, v in pairs(src) do
    if type(k) == "number" and type(v) == "string" and v ~= "" then
      out[#out + 1] = v
    elseif type(k) == "string" and k ~= "" and v then
      out[#out + 1] = k
    end
  end
  table.sort(out)
  return out
end

local function list_to_set(list)
  local set = {}
  for _, name in ipairs(copy_list(list)) do set[name] = true end
  return set
end

local function apply_preset(name)
  local p = PRESETS[name]
  if not p then return false, "unknown preset: " .. tostring(name) end
  for _, key in ipairs(PASS_KEYS) do
    if p[key] ~= nil then Config[key] = p[key] end
  end
  Config.preset = name
  return true
end

-- Sync Config to PassManager / pass configs / string pool
local function sync_config_to_passes()
  for config_key, pass_name in pairs(CONFIG_TO_PASS) do
    pm:set_enabled(pass_name, Config[config_key] and true or false)
  end
  pm:set_pass_config("variable_mangling", {
    whitelist = list_to_set(Config.name_whitelist),
  })
  string_pool.set_whitelist(Config.string_whitelist)
end

-- ============================================================
-- 核心混淆函数
-- ============================================================
local function obfuscate(code, vm_module)
  sync_config_to_passes()

  -- 检查 VM 保护是否启用
  local vm_pass = pm:get("vm_protect")
  local do_vm = vm_pass and vm_pass.enabled

  -- Passes are expected to be independently correct.
  -- Do not silently disable user-selected passes for "compatibility".
  -- Structural passes may still rewrite VM output; that is a pass-quality
  -- issue and should be fixed in the pass itself (see bcf/bb_split/etc).

  -- 字符串提取（VM保护时跳过，VM自己处理字符串）
  if not do_vm then
    code = string_pool.extract(code)
  end

  -- 执行 Pass Pipeline
  local ok, result, log = pcall(pm.run, pm, code, {
    vm_module = vm_module,
    max_total_ms = 120000,
  })

  if not ok then
    error("混淆失败: " .. tostring(result))
  end

  -- 字符串恢复（VM保护时跳过）
  if not do_vm then
    local string_pass = pm:get("string_encryption")
    local do_encrypt = string_pass and string_pass.enabled
    if do_encrypt then
      result = string_pool.restore(result)
    else
      result = string_pool.restore_raw(result)
    end
  end

  return result, log
end

-- ============================================================
-- CLI 界面
-- ============================================================
local feature_names = {
  { key = "control_flow_flattening",  name = "控制流平坦化" },
  { key = "constant_encryption",      name = "常量数字加密" },
  { key = "bogus_control_flow",       name = "BCF虚假控制流" },
  { key = "variable_mangling",        name = "变量名混淆" },
  { key = "string_encryption",        name = "字符串加密" },
  { key = "junk_comments",            name = "垃圾注释" },
  { key = "instruction_substitution", name = "指令替换" },
 { key = "advanced_fake_cf",         name = "虚假控制流增强" },
  { key = "basic_block_splitting",   name = "基本块拆分" },
 { key = "vm_protect",               name = "VM字节码虚拟化" },
  { key = "anti_debug",               name = "反调试检测" },
  { key = "call_indirection",         name = "调用间接化" },
}

local function print_banner()
  print(string.format([[
  ╔══════════════════════════════════════════╗
  ║   Lua Obfuscator v%s                 ║
  ║   代码混淆 & VM虚拟化保护工具           ║
  ╚══════════════════════════════════════════╝
]], VERSION))
end

local function print_status()
  print("\n  当前配置：")
  for i, feat in ipairs(feature_names) do
    local status = Config[feat.key] and "✓" or "✗"
    print(string.format("    %d. [%s] %s", i, status, feat.name))
  end
  print()
end

local function toggle_feature(num)
  if num < 1 or num > #feature_names then
    print("  无效编号")
    return
  end
  local feat = feature_names[num]
  Config[feat.key] = not Config[feat.key]
  local status = Config[feat.key] and "启用" or "禁用"
  print(string.format("  %s: %s", feat.name, status))
end

local function enable_all()
  for _, feat in ipairs(feature_names) do
    Config[feat.key] = true
  end
  print("  已全部启用")
end

local function disable_all()
  for _, feat in ipairs(feature_names) do
    Config[feat.key] = false
  end
  print("  已全部禁用")
end

local function read_file(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local content = f:read("*a")
  f:close()
  return content
end

local function write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then return nil, err end
  f:write(content)
  f:close()
  return true
end

local function do_obfuscate(input_path, output_path)
  local code, err = read_file(input_path)
  if not code then
    print("  ❌ 读取失败: " .. tostring(err))
    return
  end

  print(string.format("\n  读取输入文件: %s", input_path))
  print(string.format("  原始代码长度: %d 字节", #code))
  print("  开始混淆...")

  local ok, result, log = pcall(obfuscate, code)
  if not ok then
    print("  ❌ " .. tostring(result))
    return
  end

  write_file(output_path, result)
  print(string.format("  ✅ 输出已保存到: %s", output_path))
  print(string.format("  混淆后长度: %d 字节 (膨胀 %.1fx)", #result, #result / #code))

  if log then
    print("\n  Pipeline 执行日志:")
    for _, entry in ipairs(log) do
      print(string.format("    [%s] %s: %d → %d bytes", entry.name, entry.title, entry.input_size, entry.output_size))
    end
  end
end

local function interactive_input()
  print("\n  请输入要混淆的 Lua 代码（输入空行结束）：")
  print("  " .. string.rep("-", 40))
  local lines = {}
  while true do
    io.write("  > ")
    local line = io.read()
    if not line or line == "" then break end
    lines[#lines + 1] = line
  end
  return table.concat(lines, "\n")
end

local function run_demo()
  -- 演示代码在 demo 模式中内联
  return [[
local function greet(name)
  return "Hello, " .. name .. "!"
end
for i = 1, 5 do
  print(greet("World " .. i))
end
]]
end

local function fibonacci(n)
  if n <= 1 then return n end
  return fibonacci(n - 1) + fibonacci(n - 2)
end

local function print_help()
  print(string.format([[
Lua Obfuscator v%s - 使用说明

用法:
  lua obfuscator.lua [选项]

选项:
  -i, --input <file>    输入文件
  -o, --output <file>   输出文件（默认: <input>_obf.lua）
  --preset <name>          protection preset: fast | balanced | max
  --vm                     enable VM bytecode virtualization
  --preserve-name <id>     name whitelist (repeatable)
  --preserve-string <s>    string whitelist (repeatable, exact match)
  --export-config <file>   export current config as Lua table
  --import-config <file>   import config from Lua table
  --no-cfe                 disable control flow flattening
  --no-num                 disable constant number encryption
  --no-bcf                 disable BCF
  --no-var                 disable variable mangling
  --no-str                 disable string encryption
  --no-junk                disable junk comments
  --no-instr               disable instruction substitution
  --no-advbcf              disable advanced fake CF
  --no-bbsplit             disable basic block splitting
  --demo                   run demo
  -h, --help            显示帮助

交互模式:
  直接运行不带参数进入交互模式
  支持功能开关、输入代码、批量处理等
]], VERSION))
end

local function interactive_loop()
  print_banner()
  print_status()

  local _is_cli = false
  for i = 1, #arg do
    local v = arg[i]
    if v == "-i" or v == "--input" or v == "--help" or v == "-h" or v == "--demo" or v == "--export-config" or v == "--import-config" or v == "--preset" then
      _is_cli = true
      break
    end
  end

  while true do
    io.write("\n  > ")
    local input = io.read()
    if not input then break end

    input = input:match("^%s*(.-)%s*$")

    if input == "" then
      -- 空行
    elseif input == "q" or input == "quit" or input == "exit" then
      print("  再见！")
      break
    elseif input == "h" or input == "help" then
      print_help()
    elseif input == "s" or input == "status" then
      print_status()
    elseif input == "a" or input == "all" then
      enable_all()
      print_status()
    elseif input == "n" or input == "none" then
      disable_all()
      print_status()
    elseif input:match("^%d+$") then
      toggle_feature(tonumber(input))
    elseif input == "e" or input == "encode" then
      local code = interactive_input()
      if code and code ~= "" then
        local ok, result = pcall(obfuscate, code)
        if ok then
          print("\n  " .. string.rep("=", 50))
          print(result)
          print("  " .. string.rep("=", 50))
        else
          print("  ❌ " .. tostring(result))
        end
      end
    elseif input == "d" or input == "demo" then
      local code = run_demo()
      print("\n  原始代码:")
      print("  " .. string.rep("-", 40))
      for line in code:gmatch("[^\n]+") do
        print("  " .. line)
      end
      print("  " .. string.rep("-", 40))
      print("\n  混淆中...")
      local ok, result = pcall(obfuscate, code)
      if ok then
        print("  混淆后代码:")
        print("  " .. string.rep("=", 50))
        print(result)
        print("  " .. string.rep("=", 50))
      else
        print("  ❌ " .. tostring(result))
      end
    elseif input == "f" or input == "fib" then
      print("\n  计算 fibonacci(35)...")
      local t0 = os.clock()
      local r = fibonacci(35)
      local t1 = os.clock()
      print(string.format("  结果: %d (耗时: %.3fs)", r, t1 - t0))
    else
      print("  未知命令。输入 h 查看帮助。")
    end
  end
end

-- ============================================================
-- JS Bridge 接口
-- ============================================================
local M = {}

function M.obfuscate_code(code, options, vm_module)
  if options then
    M.set_config(options)
  end

  local ok, result = pcall(obfuscate, code, vm_module)
  if not ok then
    error(tostring(result))
  end
  return result
end

function M.get_config()
  local cfg = {}
  for _, key in ipairs(PASS_KEYS) do cfg[key] = Config[key] and true or false end
  cfg.preset = Config.preset
  cfg.name_whitelist = copy_list(Config.name_whitelist)
  cfg.string_whitelist = copy_list(Config.string_whitelist)
  return cfg
end

function M.set_config(options)
  if type(options) ~= "table" then return end
  local has_pass_key = false
  for key, _ in pairs(options) do
    if CONFIG_TO_PASS[key] ~= nil then has_pass_key = true; break end
  end
  if options.preset and PRESETS[options.preset] and not has_pass_key then
    apply_preset(options.preset)
  elseif options.preset and PRESETS[options.preset] and has_pass_key then
    apply_preset(options.preset)
    for key, value in pairs(options) do
      if CONFIG_TO_PASS[key] ~= nil then
        Config[key] = value and true or false
      end
    end
    Config.preset = "custom"
  elseif has_pass_key then
    for key, value in pairs(options) do
      if CONFIG_TO_PASS[key] ~= nil then
        Config[key] = value and true or false
      end
    end
    Config.preset = "custom"
  end
  if options.name_whitelist ~= nil then
    Config.name_whitelist = copy_list(options.name_whitelist)
  end
  if options.string_whitelist ~= nil then
    Config.string_whitelist = copy_list(options.string_whitelist)
  end
end
function M.apply_preset(name)
  return apply_preset(name)
end

function M.list_presets()
  return { "fast", "balanced", "max" }
end

function M.list_passes()
  return pm:list()
end

function M.set_pass_enabled(name, enabled)
  return pm:set_enabled(name, enabled)
end

function M.set_pass_config(name, key, value)
  return pm:set_config(name, key, value)
end

function M.export_pass_config()
  return pm:export_config()
end

function M.import_pass_config(config)
  return pm:import_config(config)
end

function M.export_user_config()
  sync_config_to_passes()
  local cfg = M.get_config()
  cfg.version = VERSION
  cfg.passes = pm:export_config()
  return cfg
end
function M.import_user_config(config)
  if type(config) ~= "table" then return false, "config must be a table" end
  if config.preset and PRESETS[config.preset] and not config.passes then
    apply_preset(config.preset)
  end
  M.set_config(config)
  if type(config.passes) == "table" then
    pm:import_config(config.passes)
    for config_key, pass_name in pairs(CONFIG_TO_PASS) do
      local info = pm:get(pass_name)
      if info then Config[config_key] = info.enabled and true or false end
    end
    Config.preset = "custom"
  end
  return true
end

M.VERSION = VERSION
M.PRESETS = PRESETS

-- ============================================================
-- CLI 入口
-- ============================================================
local _is_cli = false
if arg then
  for i = 1, #arg do
    local v = arg[i]
    if v == "-i" or v == "--input" or v == "--help" or v == "-h" or v == "--demo" or v == "--export-config" or v == "--import-config" or v == "--preset" then
      _is_cli = true
      break
    end
  end
end

if _is_cli then
  local args = {}
  if arg then for i = 1, #arg do args[#args + 1] = arg[i] end end

  local input, output = nil, nil
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "-h" or a == "--help" then
      print_help()
      os.exit(0)
    elseif a == "-i" or a == "--input" then
      i = i + 1; input = args[i]
    elseif a == "-o" or a == "--output" then
      i = i + 1; output = args[i]
    elseif a == "--no-cfe" then Config.control_flow_flattening = false
    elseif a == "--no-num" then Config.constant_encryption = false
    elseif a == "--no-bcf" then Config.bogus_control_flow = false
    elseif a == "--no-var" then Config.variable_mangling = false
    elseif a == "--no-str" then Config.string_encryption = false
    elseif a == "--no-junk" then Config.junk_comments = false
    elseif a == "--no-instr" then Config.instruction_substitution = false
   elseif a == "--no-advbcf" then Config.advanced_fake_cf = false
    elseif a == "--no-bbsplit" then Config.basic_block_splitting = false
   elseif a == "--vm" then Config.vm_protect = true
    elseif a == "--preset" then
      i = i + 1
      local okp, errp = apply_preset(args[i])
      if not okp then print("ERROR: " .. tostring(errp)); os.exit(1) end
    elseif a == "--preserve-name" then
      i = i + 1
      if args[i] and args[i] ~= "" then
        Config.name_whitelist[#Config.name_whitelist + 1] = args[i]
      end
    elseif a == "--preserve-string" then
      i = i + 1
      if args[i] then
        Config.string_whitelist[#Config.string_whitelist + 1] = args[i]
      end
    elseif a == "--export-config" then
      i = i + 1
      local outp = args[i] or "obfuscator_config.lua"
      local snap = M.export_user_config()
      local function dump(v, indent)
        indent = indent or 0
        local sp = string.rep("  ", indent)
        local t = type(v)
        if t == "string" then return string.format("%q", v)
        elseif t == "number" or t == "boolean" then return tostring(v)
        elseif t == "table" then
          local parts = {"{\n"}
          local keys = {}
          for k in pairs(v) do keys[#keys+1] = k end
          table.sort(keys, function(x,y) return tostring(x)<tostring(y) end)
          for _, k in ipairs(keys) do
            local key
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then key = k
            else key = "[" .. dump(k) .. "]" end
            parts[#parts+1] = sp .. "  " .. key .. " = " .. dump(v[k], indent+1) .. ",\n"
          end
          parts[#parts+1] = sp .. "}"
          return table.concat(parts)
        else return "nil" end
      end
      local body = "return " .. dump(snap) .. "\n"
      local okw, errw = write_file(outp, body)
      if not okw then print("ERROR: " .. tostring(errw)); os.exit(1) end
      print("Wrote config: " .. outp)
      os.exit(0)
    elseif a == "--import-config" then
      i = i + 1
      local inp = args[i]
      if not inp then print("ERROR: --import-config needs a file"); os.exit(1) end
      local chunk, err = loadfile(inp)
      if not chunk then print("ERROR: " .. tostring(err)); os.exit(1) end
      local okc, cfg = pcall(chunk)
      if not okc then print("ERROR: " .. tostring(cfg)); os.exit(1) end
      local oki, erri = M.import_user_config(cfg)
      if not oki then print("ERROR: " .. tostring(erri)); os.exit(1) end
      print("Imported config from " .. inp)    elseif a == "--demo" then
      local code = run_demo()
      local ok, result = pcall(obfuscate, code)
      if ok then print(result) else print("ERROR: " .. tostring(result)); os.exit(1) end
      os.exit(0)
    elseif not a:match("^%-") then
      if not input then input = a end
    end
    i = i + 1
  end

  if input then
    output = output or input:gsub("%.lua$", "") .. "_obf.lua"
    do_obfuscate(input, output)
  else
    print_help()
  end
end

return M
